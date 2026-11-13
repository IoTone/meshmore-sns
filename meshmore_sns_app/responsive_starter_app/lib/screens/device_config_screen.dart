// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_collapse_controller.dart';
import '../ui/mm_collapsible.dart';
import '../ui/mm_confirm.dart';
import '../ui/mm_scaffold.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/own_location.dart';
import '../meshcore/radio_config_transaction.dart';
import '../meshcore/radio_safety_store.dart';
import '../meshcore/region_presets.dart';
import '../perms/location_service.dart';
import '../perms/permissions_service.dart';
import '../ui/mm_components.dart';
import '../ui/mm_shape.dart';
import '../util/relative_time.dart';
import 'device_contacts_screen.dart';

/// The advert-location policy integers → a UI label.
///
/// The integers are MeshCore's (`src/helpers/CommonCLI.h`, shared by
/// repeater / room / sensor firmware):
///   0 = ADVERT_LOC_NONE  — advertise no position at all
///   1 = ADVERT_LOC_SHARE — advertise the LIVE sensor/GPS fix
///   2 = ADVERT_LOC_PREFS — advertise the STORED (pinned) pair
///
/// CAVEAT — the companion firmware this app talks to does NOT implement
/// that distinction. At `companion-v1.17.1`, `examples/companion_radio/
/// NodePrefs.h:9-10` defines only NONE and SHARE, and `MyMesh.cpp:1252,
/// 1336,2251` test only `== ADVERT_LOC_NONE`; any other value advertises
/// `sensors.node_lat/lon`, the same single store `CMD_SET_ADVERT_LATLON`
/// writes and the GPS overwrites. On a companion, 1 and 2 behave
/// identically and "Pinned" does not pin. The labels follow the shared
/// definition so they are right for any firmware that does honour it.
///
/// One mapping shared by the picker and the confirmation toast, so the
/// two cannot drift apart.
String advertPolicyLabel(AppLocalizations l, int policy) => switch (policy) {
      1 => l.deviceAdvertSourceGps,
      2 => l.deviceAdvertSourcePinned,
      _ => l.deviceAdvertSourceNone,
    };

/// Device configuration (R7) + LoRa region selection (R15). The
/// **Radio / Region** section is wired to the M4 protocol surface
/// (`setRadioParams` / `setRadioTxPower`). Other sections remain
/// scaffolds (later U-steps).
///
/// "Region" is an app convenience — the companion protocol only
/// carries raw frequency/BW/SF/CR, with no per-region opcode. We
/// ship a small list of community/regulatory presets (US, EU 868,
/// Japan/ARIB STD-T108) and a Custom entry; only cited values are
/// pre-filled. **All nodes must use identical radio params or they
/// can't hear each other**, so match your mesh, and confirm the
/// settings are legal in your jurisdiction (Japan additionally
/// requires firmware-side listen-before-talk).
class DeviceConfigScreen extends StatefulWidget {
  const DeviceConfigScreen({super.key});

  @override
  State<DeviceConfigScreen> createState() => _DeviceConfigScreenState();
}

class _DeviceConfigScreenState extends State<DeviceConfigScreen> {
  final TextEditingController _freq = TextEditingController();
  final TextEditingController _bw = TextEditingController();
  final TextEditingController _sf = TextEditingController();
  final TextEditingController _cr = TextEditingController();
  final TextEditingController _tx = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _lat = TextEditingController();
  final TextEditingController _lon = TextEditingController();
  bool _loaded = false;

  // Path hash length in bytes (1..3). Not on SelfInfo: it arrives with
  // DeviceInfo, which can land after the self-info snapshot, so it loads
  // through its own guard.
  int _pathHashSize = 1;

  /// The point the last transaction replaced, if the store still has one.
  /// Non-null means an undo is available and has not been used.
  RadioOperatingPoint? _armed;
  bool _pathHashLoaded = false;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _freq,
      _bw,
      _sf,
      _cr,
      _tx,
      _name,
      _lat,
      _lon
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // Snapshot of what `_loadFrom` last wrote. Lets us detect
  // "user hasn't touched these fields" so the auto-reload doesn't
  // clobber in-progress edits.
  String _lastLoadedLat = '';
  String _lastLoadedLon = '';
  String _lastLoadedName = '';

  void _loadFrom(SelfInfo s) {
    _freq.text = s.frequencyMhz.toString();
    _bw.text = s.bandwidthKhz.toString();
    _sf.text = s.spreadingFactor.toString();
    _cr.text = s.codingRate.toString();
    _tx.text = s.txPowerDbm.toString();
    _name.text = s.name;
    _lat.text = s.latitude == 0 ? '' : s.latitude.toString();
    _lon.text = s.longitude == 0 ? '' : s.longitude.toString();
    _lastLoadedLat = _lat.text;
    _lastLoadedLon = _lon.text;
    _lastLoadedName = _name.text;
    setState(() => _loaded = true);
  }

  /// Re-sync text fields when the device's `selfInfo` has changed
  /// AND the user hasn't typed over the previously-loaded values.
  /// This is what makes the periodic location-refresh actually
  /// appear in the lat/lon fields instead of freezing at the
  /// initial-handshake snapshot.
  void _maybeReloadFromSelfInfo(SelfInfo s) {
    final String latNext = s.latitude == 0 ? '' : s.latitude.toString();
    final String lonNext = s.longitude == 0 ? '' : s.longitude.toString();
    final String nameNext = s.name;
    final bool latUntouched = _lat.text == _lastLoadedLat;
    final bool lonUntouched = _lon.text == _lastLoadedLon;
    final bool nameUntouched = _name.text == _lastLoadedName;
    if (latUntouched && _lat.text != latNext) {
      _lat.text = latNext;
      _lastLoadedLat = latNext;
    }
    if (lonUntouched && _lon.text != lonNext) {
      _lon.text = lonNext;
      _lastLoadedLon = lonNext;
    }
    if (nameUntouched && _name.text != nameNext) {
      _name.text = nameNext;
      _lastLoadedName = nameNext;
    }
  }

  Future<void> _applyName(MeshcoreController mc) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String n = _name.text.trim();
    if (n.isEmpty) {
      _toast(l.deviceToastNameEmpty);
      return;
    }
    try {
      await mc.setAdvertName(n);
      _toast(l.deviceToastNameSet);
    } catch (e) {
      _toast(l.deviceToastSendFailed('$e'));
    }
  }

  /// R22 / U13 — read the device's own SelfInfo lat/lon back into
  /// the form (in case the user typed something and wants to revert
  /// to what the device is currently reporting).
  void _readDeviceLocation(MeshcoreController mc) {
    final AppLocalizations l = AppLocalizations.of(context);
    final SelfInfo? s = mc.selfInfo;
    if (s == null) {
      _toast(l.deviceToastNoDeviceYet);
      return;
    }
    if (s.latitude == 0 && s.longitude == 0) {
      _toast(l.deviceToastNoGpsYet);
      return;
    }
    setState(() {
      _lat.text = s.latitude.toString();
      _lon.text = s.longitude.toString();
    });
    _toast(l.deviceToastLoadedDeviceLoc);
  }

  /// R22 / U13 — request a one-shot phone-GPS fix and populate the
  /// lat/lon fields with it. Permission is requested just-in-time
  /// (we don't ask at first-run; the user only pays the permission
  /// cost if they actually take this action).
  Future<void> _usePhoneLocation(MeshcoreController mc) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final PermissionsService perms = context.read<PermissionsService>();
    final PermissionResult r = await perms.requestLocation();
    if (!mounted) return;
    if (r != PermissionResult.granted && r != PermissionResult.notApplicable) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(r == PermissionResult.permanentlyDenied
              ? l.deviceLocPermDeniedPerm
              : l.deviceLocPermDenied),
          action: SnackBarAction(
            label: l.deviceOpenSettings,
            onPressed: () => perms.openAppSettingsPage(),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    _toast(l.deviceToastGettingPhoneFix);
    final bool ok = await mc.requestPhoneLocationFix();
    if (!mounted) return;
    if (!ok) {
      _toast(l.deviceToastPhoneFixFailed);
      return;
    }
    final OwnLocation? loc = mc.phoneLocationFix;
    if (loc == null) {
      _toast(l.deviceToastNoFixReturned);
      return;
    }
    setState(() {
      _lat.text = loc.latitude.toStringAsFixed(6);
      _lon.text = loc.longitude.toStringAsFixed(6);
    });
    _toast(l.deviceToastGotPhoneLoc);
  }

  Future<void> _applyLocation(MeshcoreController mc) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final double? la = double.tryParse(_lat.text.trim());
    final double? lo = double.tryParse(_lon.text.trim());
    if (la == null || lo == null || la.abs() > 90 || lo.abs() > 180) {
      _toast(l.deviceToastInvalidLatLon);
      return;
    }
    try {
      await mc.setAdvertLatLon(latitude: la, longitude: lo);
      _toast(l.deviceToastAdvertLocSet);
    } catch (e) {
      _toast(l.deviceToastSendFailed('$e'));
    }
  }

  /// Fill the radio fields from a region preset. Nothing is sent: the radio
  /// has one Apply, so a picked preset and a typed value travel the same way
  /// and a preset can never look applied while the form holds other numbers.
  String _fillFromPreset(RegionPreset p) {
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() {
      _freq.text = p.frequencyMhz.toString();
      _bw.text = p.bandwidthKhz.toString();
      _sf.text = p.spreadingFactor.toString();
      _cr.text = p.codingRate.toString();
      _tx.text = p.txPowerDbm.toString();
      // A preset that carries a path hash size applies it too: nodes that
      // disagree on it cannot forward directed traffic for each other.
      if (p.pathHashSize != null) _pathHashSize = p.pathHashSize!;
    });
    return localizedPresetLabel(l, p.id);
  }

  /// The preset the radio is actually on, or Custom when it matches none.
  String _presetLabel(AppLocalizations l, SelfInfo? si) {
    if (si == null) return l.deviceRegionUnknown;
    final RegionPreset? match = matchPresetByRadioParams(
      frequencyMhz: si.frequencyMhz,
      bandwidthKhz: si.bandwidthKhz,
      spreadingFactor: si.spreadingFactor,
      codingRate: si.codingRate,
    );
    return match == null
        ? l.deviceRegionCustom
        : localizedPresetLabel(l, match.id);
  }

  /// The preset chooser. A sheet, because fifteen booked-out chips on the page
  /// pushed every field below the fold (R103) and this section is the page's
  /// reason to exist.
  Future<void> _pickPreset(MeshcoreController mc, SelfInfo? si) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    // An event handler, so the non-subscribing read: `context.skin` watches.
    final MmSkin skin = context.skinRead;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (BuildContext ctx, ScrollController ctl) => ListView(
          controller: ctl,
          // The sheet is not inside `MmScaffold`, so the navigation area is
          // added here: the last region in the list was sitting under the
          // gesture handle.
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 24 + MediaQuery.paddingOf(ctx).bottom),
          children: <Widget>[
            Text(l.deviceRegionBand, style: mmSectionLabelStyle(skin)),
            const SizedBox(height: 4),
            for (final RegionFamily fam in RegionFamily.values)
              if (kRegionPresets.any(
                  (RegionPreset p) => regionFamilyOf(p.id) == fam)) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Text(_familyLabel(l, fam),
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: skin.type.sizeSm,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600)),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final RegionPreset p in kRegionPresets)
                      if (regionFamilyOf(p.id) == fam)
                        _RegionChip(
                          label: localizedPresetLabel(l, p.id),
                          note: p.note,
                          selected: si != null &&
                              matchPresetByRadioParams(
                                    frequencyMhz: si.frequencyMhz,
                                    bandwidthKhz: si.bandwidthKhz,
                                    spreadingFactor: si.spreadingFactor,
                                    codingRate: si.codingRate,
                                  )?.id ==
                                  p.id,
                          onTap: () {
                            final String name = _fillFromPreset(p);
                            Navigator.pop(ctx);
                            _toast(l.deviceRegionLoadedOffline(name));
                          },
                        ),
                  ],
                ),
              ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.my_location, size: 16),
                label: Text(l.deviceRegionSuggestFromLocation),
                onPressed: () {
                  Navigator.pop(ctx);
                  _suggestFromMyLocation(mc);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Suggest a preset from the phone's GPS fix. No-op if location is
  /// unavailable or the fix falls outside every shipped country box.
  /// Shows a confirmation dialog before applying so a user near a
  /// national border can override.
  Future<void> _suggestFromMyLocation(MeshcoreController mc) async {
    final AppLocalizations l = AppLocalizations.of(context);
    // `requestFix` (not `currentFix`) so the runtime permission is
    // asked for here. `currentFix` used to return a bare null and this
    // path reported "no fix" whether the user had never granted
    // location or was simply standing indoors.
    final LocationOutcome outcome = await const GeolocatorLocationService()
        .requestFix(timeLimit: const Duration(seconds: 15));
    final PhoneFix? fix = outcome.fix;
    if (fix == null) {
      final LocationFailure failure = outcome.failure!;
      _toast(switch (failure) {
        LocationFailure.permissionDeniedForever => l.deviceLocPermDeniedPerm,
        LocationFailure.permissionDenied => l.deviceLocPermDenied,
        _ => l.deviceRegionSuggestNoFix,
      });
      return;
    }
    final RegionPreset? p = suggestPresetForLatLon(fix.latitude, fix.longitude);
    if (p == null) {
      _toast(l.deviceRegionSuggestNoMatch);
      return;
    }
    if (!mounted) return;
    final bool ok = await mmConfirm(
      context,
      title: l.deviceRegionSuggestTitle,
      body: l.deviceRegionSuggestBody(localizedPresetLabel(l, p.id),
          fix.latitude.toStringAsFixed(3), fix.longitude.toStringAsFixed(3)),
      cancelLabel: l.cancel,
      confirmLabel: l.deviceRegionSuggestApply,
    );
    if (ok && mounted) {
      final String name = _fillFromPreset(p);
      _toast(l.deviceRegionLoadedOffline(name));
    }
  }

  void _toast(String m) {
    // Most callers run after a BLE write; the user may have left the
    // screen by then (same guard as Diagnostics' _toast).
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  /// A stable name for this radio in the safety record: its public key, so a
  /// different radio never inherits another one's undo.
  String? _radioKey(MeshcoreController mc) {
    final SelfInfo? si = mc.selfInfo;
    if (si == null) return null;
    return si.publicKey.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Run the operating-point transaction and say what the radio answered.
  ///
  /// Returns true when every write was confirmed. The caller shows the toast;
  /// this method owns the side effects a transaction has to keep: the record
  /// on disk before the first frame, and the refresh that proves the write
  /// took effect.
  Future<bool> _runTransaction(
      MeshcoreController mc, RadioOperatingPoint target,
      {required String radioKey}) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final RadioConfigOutcome out =
        await RadioConfigTransaction.run(target, mc.sendRadioConfig);
    if (!out.isApplied) {
      final RadioConfigStep step = out.failedStep!;
      final RadioAnswer answer = out.answer!;
      final String param = _stepLabel(l, step);
      if (answer.isUnsupported) {
        _toast(l.deviceRadioUnsupported(param));
      } else if (answer.status == RadioAnswerStatus.noAnswer) {
        _toast(l.deviceRadioSilent(param));
      } else {
        _toast(l.deviceRadioRefused(
            param, answer.errorCode == null ? '?' : '${answer.errorCode}'));
      }
      return false;
    }
    mc.refreshDeviceInfo();
    unawaited(_reloadArmed(mc));
    return true;
  }

  String _stepLabel(AppLocalizations l, RadioConfigStep step) => switch (step) {
        RadioConfigStep.params => l.deviceRadioParams,
        RadioConfigStep.txPower => l.deviceTxPower,
        RadioConfigStep.pathHash => l.devicePathHashSize,
      };

  Future<void> _reloadArmed(MeshcoreController mc) async {
    final String? key = _radioKey(mc);
    if (key == null) return;
    final RadioOperatingPoint? armed = await RadioSafetyStore.armed(key);
    if (!mounted) return;
    if (armed != _armed) setState(() => _armed = armed);
  }

  /// Take back the last radio change. Single use: the record is consumed
  /// before the write, so a failed undo cannot be retried into a second
  /// rewrite of stale values.
  Future<void> _revertRadio(MeshcoreController mc) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String? key = _radioKey(mc);
    if (key == null || !mc.isReady) {
      _toast(l.deviceConnectFirst);
      return;
    }
    final RadioOperatingPoint? previous = await RadioSafetyStore.consume(key);
    if (!mounted) return;
    if (previous == null) {
      setState(() => _armed = null);
      _toast(l.deviceRadioRevertUnavailable);
      return;
    }
    final bool ok = await _runTransaction(mc, previous, radioKey: key);
    if (!mounted) return;
    setState(() => _armed = null);
    _toast(ok ? l.deviceRadioReverted : l.deviceRadioRevertFailed);
  }

  Future<void> _applyRadio(MeshcoreController mc) async {
    final AppLocalizations l = AppLocalizations.of(context);
    // R25+3 — the user-reported bug: "Apply radio settings" was
    // greyed out when not connected, with no clue why. Now we keep
    // the button enabled and surface an explicit toast — picking a
    // preset while offline at least leaves a clear trail of what to
    // do next, rather than looking like the app is broken.
    if (!mc.isReady) {
      _toast(l.deviceConnectFirst);
      return;
    }
    final double? f = double.tryParse(_freq.text);
    final double? b = double.tryParse(_bw.text);
    final int? sf = int.tryParse(_sf.text);
    final int? cr = int.tryParse(_cr.text);
    if (f == null || b == null || sf == null || cr == null) {
      _toast(l.deviceToastInvalidRadio);
      return;
    }
    final String? key = _radioKey(mc);
    final RadioOperatingPoint? previous =
        RadioOperatingPoint.known(mc.selfInfo, mc.deviceInfo);
    if (key == null || previous == null) {
      // The path-hash size arrives in the device info, not in the self info,
      // so a radio that has not answered a device query has no recorded value
      // to come back to. Refusing here is the whole point: a one-way write to
      // a radio whose old values are unknown cannot be undone.
      _toast(l.deviceRadioUnknownState);
      return;
    }
    final int tx = int.tryParse(_tx.text) ?? previous.txPowerDbm;
    // The previous operating point goes to disk BEFORE the first frame: if
    // the link dies mid-transaction, the way back is already recorded.
    await RadioSafetyStore.arm(key, previous);
    final RadioOperatingPoint target = RadioOperatingPoint(
      frequencyMhz: f,
      bandwidthKhz: b,
      spreadingFactor: sf,
      codingRate: cr,
      txPowerDbm: tx,
      pathHashMode: _pathHashSize - 1,
    );
    if (await _runTransaction(mc, target, radioKey: key) && mounted) {
      _toast(l.deviceRadioApplied);
    }
  }

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ready = mc.state == MeshcoreConnectionState.ready;
    final SelfInfo? si = mc.selfInfo;
    if (!_loaded && si != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loaded) _loadFrom(si);
      });
    } else if (_loaded && si != null) {
      // Subsequent SelfInfo arrivals (e.g. the dashboard's 60 s
      // refresh trigger) — sync the lat/lon/name fields into the
      // form unless the user has edited them since the last load.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeReloadFromSelfInfo(si);
      });
    }
    // DeviceInfo arrives on its own schedule, after the self-info snapshot,
    // so path hash cannot ride along with _loadFrom. Load it once and never
    // overwrite what the user then chose.
    if (_armed == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reloadArmed(mc);
      });
    }
    final DeviceInfo? di = mc.deviceInfo;
    if (!_pathHashLoaded && di != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_pathHashLoaded) {
          setState(() {
            _pathHashSize = di.pathHashMode + 1;
            _pathHashLoaded = true;
          });
        }
      });
    }

    Widget num(String label, TextEditingController c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
            ],
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.deviceConfigTitle)),
      body: MmScaffold(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            // R103 — the applied band is a fact, the picker is an action.
            // The banner used to live inside the section, so the only way to
            // keep it visible was to keep ~15 region chips expanded on open:
            // on a 387 dp phone at 1.3x text that pushed every other group
            // off the first screen. The banner stays; the picker folds.
            _CurrentRegionBanner(si: si, cs: cs, l: l),
            const Divider(height: 28),
            MmCollapsibleSection(
              id: MmGroupIds.devRadio,
              title: l.deviceRadioParams,
              initiallyExpanded: true,
              children: <Widget>[
                // R103 kept the fifteen chips off the page; the chooser is a
                // sheet now, and a picked preset only fills the fields. One
                // Apply sends whatever the form holds.
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.public,
                      size: 18, color: cs.onSurfaceVariant),
                  title: Text(l.deviceRegionBand),
                  subtitle: Text(_presetLabel(l, si),
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickPreset(mc, si),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.info_outline,
                        size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(l.deviceRegionDisclaimerShort,
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: context.skin.type.sizeSm)),
                    ),
                    MmAction(
                      dense: true,
                      label: l.deviceRegionWhy,
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (BuildContext ctx) => AlertDialog(
                          title: Text(l.deviceRegionCaveatTitle),
                          content: SingleChildScrollView(
                              child: Text(l.deviceRegionDisclaimer)),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(l.deviceRegionCaveatClose),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                num(l.deviceFrequency, _freq),
                num(l.deviceBandwidth, _bw),
                num(l.deviceSpreadingFactor, _sf),
                num(l.deviceCodingRate, _cr),
                num(l.deviceTxPower, _tx),
                const SizedBox(height: 16),
                // Path hash length. Kept as a bare 1/2/3 segmented control
                // rather than a numeric field: it is a three-value choice,
                // and words would overflow the segment row at 1.3x text.
                Builder(builder: (BuildContext _) {
                  final DeviceInfo? d = mc.deviceInfo;
                  final String help = d == null
                      ? l.devicePathHashUnread
                      : _pathHashSize != d.pathHashMode + 1
                          ? l.devicePathHashMismatch(
                              '${d.pathHashMode + 1}', '$_pathHashSize')
                          : l.devicePathHashSizeHelp;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(l.devicePathHashSize,
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: context.skin.type.sizeBody,
                              letterSpacing: 1)),
                      const SizedBox(height: 6),
                      SegmentedButton<int>(
                        segments: const <ButtonSegment<int>>[
                          ButtonSegment<int>(value: 1, label: Text('1')),
                          ButtonSegment<int>(value: 2, label: Text('2')),
                          ButtonSegment<int>(value: 3, label: Text('3')),
                        ],
                        selected: <int>{_pathHashSize},
                        showSelectedIcon: false,
                        onSelectionChanged: (Set<int> next) =>
                            setState(() => _pathHashSize = next.first),
                      ),
                      const SizedBox(height: 6),
                      Text(help,
                          style: TextStyle(
                              color: d != null &&
                                      _pathHashSize != d.pathHashMode + 1
                                  ? cs.error
                                  : cs.onSurfaceVariant,
                              fontSize: context.skin.type.sizeBody,
                              height: 1.4)),
                    ],
                  );
                }),
                const SizedBox(height: 12),
                // Wrap, not Row+Spacer: two buttons on one line while they
                // fit (same left/right placement), stacking instead of
                // overflowing by 8.5 px at 320dp with 2.0x text.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 8,
                  children: <Widget>[
                    if (si != null)
                      MmAction(
                        label: l.deviceLoadFromDevice,
                        onPressed: () => _loadFrom(si),
                      ),
                    if (_armed != null)
                      MmAction(
                        label: l.deviceRadioRevert,
                        onPressed: () => _revertRadio(mc),
                      ),
                    FilledButton.icon(
                      icon: const Icon(Icons.send),
                      label: Text(l.deviceApplyRadio),
                      // R25+3 — always tappable. _applyRadio handles the
                      // not-ready case explicitly so a user with the form
                      // already populated (e.g. via Suggest-from-location
                      // while offline) gets actionable feedback instead
                      // of a dead button.
                      onPressed: () => _applyRadio(mc),
                    ),
                  ],
                ),
                // The same action, the same control as Diagnostics offers it
                // with: an `OutlinedButton.icon` here was a third button style
                // on a page that already shows `MmAction` and `FilledButton`,
                // and "Pair a radio" should not look like a different act
                // depending on which screen you reach it from.
                if (!ready)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: MmAction(
                        icon: Icons.add_link,
                        label: l.diagnosticsPairRadio,
                        onPressed: () => context.push('/pair'),
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 28),

            // IDENTITY / ADVERT (R7)
            MmCollapsibleSection(
              id: MmGroupIds.devIdentity,
              title: l.deviceIdentityAdvert,
              children: <Widget>[
                const SizedBox(height: 6),
                TextField(
                  controller: _name,
                  maxLength: 31,
                  decoration: InputDecoration(
                      labelText: l.deviceAdvertName, isDense: true),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: MmAction(
                    dense: true,
                    icon: Icons.badge_outlined,
                    label: l.deviceSetName,
                    onPressed: ready ? () => _applyName(mc) : null,
                  ),
                ),
                // Advert location SOURCE — the segment values are the FIRMWARE's
                // policy integers, they are NOT the visual order of our labels.
                // MeshCore `src/helpers/CommonCLI.h` defines:
                //   0 = ADVERT_LOC_NONE  — advertise no position at all
                //   1 = ADVERT_LOC_SHARE — advertise the LIVE sensor/GPS fix
                //   2 = ADVERT_LOC_PREFS — advertise the STORED (pinned) pair
                // Labels used to be attached to 1=Pinned / 2=GPS, i.e. reversed
                // against the firmware's shared definition. NOTE: companion
                // firmware (`companion-v1.17.1`) tests only `== ADVERT_LOC_NONE`
                // (`MyMesh.cpp:1252,1336,2251`), so there 1 and 2 behave
                // identically and neither pins; see [advertPolicyLabel].
                // Sent via CMD_SET_OTHER_PARAMS (0x26).
                const SizedBox(height: 6),
                Text(l.deviceAdvertSource,
                    style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: context.skin.type.sizeBody,
                        letterSpacing: 1)),
                const SizedBox(height: 4),
                Builder(builder: (BuildContext _) {
                  final SelfInfo? si = mc.selfInfo;
                  final int current = si?.advertLocPolicy ?? 0;
                  return SegmentedButton<int>(
                    segments: <ButtonSegment<int>>[
                      ButtonSegment<int>(
                          value: 0,
                          label: Text(advertPolicyLabel(l, 0)),
                          icon: const Icon(Icons.do_not_disturb, size: 16)),
                      ButtonSegment<int>(
                          value: 1,
                          label: Text(advertPolicyLabel(l, 1)),
                          icon: const Icon(Icons.satellite_alt, size: 16)),
                      ButtonSegment<int>(
                          value: 2,
                          label: Text(advertPolicyLabel(l, 2)),
                          icon: const Icon(Icons.push_pin_outlined, size: 16)),
                    ],
                    selected: <int>{current},
                    showSelectedIcon: false,
                    onSelectionChanged: ready && si != null
                        ? (Set<int> next) async {
                            final int v = next.first;
                            if (v == current) return;
                            try {
                              await mc.setAdvertLocPolicy(v);
                              _toast(advertPolicyLabel(l, v));
                            } catch (e) {
                              _toast(l.deviceToastSendFailed('$e'));
                            }
                          }
                        : null,
                  );
                }),
                // R38 — on-board GPS module (separate from advert policy
                // above). Without this, picking "Device GPS" above only
                // controls whether GPS coords get *included in adverts* —
                // the firmware never reads its GPS chip into
                // sensors.node_lat/lon. Defaults gps=0, gps_interval=0;
                // we surface the live values + a switch + interval picker.
                _GpsModuleControls(mc: mc, ready: ready, cs: cs, l: l),
                const SizedBox(height: 8),
                // What the device currently reports — read-only "ground
                // truth" line. The editable text fields below are
                // **staging**; this line is the wire-side value. Always
                // shown so divergence is visible at a glance.
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.developer_board,
                          size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          () {
                            if (si == null) return l.deviceLocReportsAwaiting;
                            if (si.latitude.abs() < 1e-9 &&
                                si.longitude.abs() < 1e-9) {
                              return l.deviceLocReportsNone;
                            }
                            return l.deviceLocReportsValue(
                                si.latitude.toStringAsFixed(5),
                                si.longitude.toStringAsFixed(5));
                          }(),
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: context.skin.type.sizeSm,
                              fontFamily: context.skin.type.monoFamily),
                        ),
                      ),
                    ],
                  ),
                ),
                _LatLonField(
                  label: l.deviceAdvertLatitude,
                  hint: 'e.g. 35.681',
                  controller: _lat,
                  deviceValue: si?.latitude,
                  unsavedLabel: l.deviceLocUnsaved,
                ),
                _LatLonField(
                  label: l.deviceAdvertLongitude,
                  hint: 'e.g. 139.767',
                  controller: _lon,
                  deviceValue: si?.longitude,
                  unsavedLabel: l.deviceLocUnsaved,
                ),
                // R22 / U13 — populate-the-field actions (no broadcast).
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.smartphone, size: 16),
                        label: Text(l.deviceUsePhoneLocation),
                        onPressed: () => _usePhoneLocation(mc),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.developer_board, size: 16),
                        label: Text(l.deviceReadDeviceLocation),
                        onPressed: () => _readDeviceLocation(mc),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: MmAction(
                    dense: true,
                    icon: Icons.my_location,
                    label: l.deviceSetAdvertLocation,
                    onPressed: ready ? () => _applyLocation(mc) : null,
                  ),
                ),
                Text(
                  l.deviceAdvertPropagatesHint,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeBody),
                ),
              ],
            ),
            const Divider(height: 28),

            // CHANNELS → dedicated screen
            Text(l.deviceChannelsSection,
                style: TextStyle(
                    color: cs.primary, fontSize: context.skin.type.sizeBody, letterSpacing: 3)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tag),
              title: Text(l.deviceManageChannels),
              subtitle: Text(l.deviceActiveChannelSub(mc.activeChannelName)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/channels'),
            ),
            const Divider(height: 28),

            // OTHER PARAMS — editable. Each setter wraps
            // CMD_SET_OTHER_PARAMS (0x26) and preserves the other
            // three fields by reading them off SelfInfo.
            MmCollapsibleSection(
              id: MmGroupIds.devOther,
              title: l.deviceOtherParamsSection,
              children: <Widget>[
                const SizedBox(height: 4),
                if (si == null)
                  Text(l.otherAwaitingDevice,
                      style: TextStyle(
                          color: cs.onSurface,
                          fontFamily: context.skin.type.wordsMono,
                          height: 1.5))
                else
                  _OtherParamsEditor(mc: mc, si: si, enabled: ready),
              ],
            ),
            const Divider(height: 28),

            // DEVICE (read-only)
            MmCollapsibleSection(
              id: MmGroupIds.devDevice,
              title: l.deviceDeviceSection,
              children: <Widget>[
                const SizedBox(height: 4),
                Builder(builder: (BuildContext _) {
                  final DeviceInfo? d = mc.deviceInfo;
                  final String batt = mc.batteryMillivolts == null
                      ? '—'
                      : l.deviceBatteryValue(
                              mc.batteryVolts!.toStringAsFixed(2),
                              mc.batteryPercent!) +
                          (mc.charging == true ? ' ⚡' : '');
                  return Text(
                    d == null
                        ? '${l.deviceReadoutQuerying}\n'
                            '${l.deviceReadoutBattery(batt)}'
                        : '${l.deviceReadoutFirmware(d.firmwareVersion)}\n'
                            '${l.deviceReadoutBuild(d.firmwareBuildDate)}\n'
                            '${l.deviceReadoutManufacturer(d.manufacturer)}\n'
                            '${l.deviceReadoutContacts(d.maxContacts, d.maxGroupChannels)}\n'
                            '${l.deviceReadoutBlePin(d.blePin)}\n'
                            '${l.deviceReadoutPathHash(d.pathHashMode + 1)}\n'
                            '${_repeatRanges(mc, l)}'
                            '${_airtimeLimit(mc, l)}'
                            '${_secondProfile(mc, l)}'
                            '${l.deviceReadoutBattery(batt)}',
                    style: TextStyle(
                        color: cs.onSurface,
                        fontFamily: context.skin.type.monoFamily,
                        height: 1.5),
                  );
                }),
                // The cost, where the status line is. Shown only once a frame
                // has been heard on the second profile, because the note
                // explains a line that is otherwise absent.
                if (mc.radio2Seen)
                  Padding(
                    key: const Key('device-radio2-note'),
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l.deviceRadio2Note,
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: context.skin.type.sizeSm,
                          height: 1.4),
                    ),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.battery_charging_full),
                  title: Text(l.batteryTitle),
                  subtitle: Text(l.batteryConfigSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/battery'),
                ),
              ],
            ),
            const Divider(height: 28),

            // CONTACT TABLE — the radio's own add policy. Folded by default
            // because it is a policy, not a reading; a user meets it when the
            // table fills, and the count is here either way.
            MmCollapsibleSection(
              id: MmGroupIds.devContacts,
              title: l.deviceContactsSection,
              initiallyExpanded: false,
              children: <Widget>[
                const SizedBox(height: 4),
                _ContactTableEditor(mc: mc, enabled: ready),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether a frame has been heard on the radio's **second** profile.
///
/// Status only, by decision: the app decodes the profile tag on every received
/// frame and can report that one exists, but it neither shows that profile's
/// parameters nor changes them. A second profile takes 96-99 % of the primary's
/// airtime, so switching it is a decision for the radio's own configuration; a
/// quiet second profile is indistinguishable from none, which is why this says
/// "nothing heard" rather than "single profile".
String _secondProfile(MeshcoreController mc, AppLocalizations l) {
  final DateTime? at = mc.radio2LastSeen;
  if (at == null) return '${l.deviceRadio2Never}\n';
  return '${l.deviceRadio2Seen(deviceAgo(l, DateTime.now().difference(at)))}\n';
}

/// The radio's own duty-cycle limit, as one readout line.
///
/// `airtime_factor` `af` means the radio may transmit `1 / (1 + af)` of the
/// time. The app's meter sets its own budget, so this is the figure the app's
/// number should be read against; `—` until the radio answers, because a
/// guessed limit is worse than none.
String _airtimeLimit(MeshcoreController mc, AppLocalizations l) {
  final TuningParams? t = mc.tuningParams;
  if (t == null) return '${l.deviceAirtimeLimitUnknown}\n';
  final double share = 1 / (1 + t.airtimeFactor);
  return '${l.deviceAirtimeLimit((share * 100).round(), t.airtimeFactor.toStringAsFixed(2))}\n';
}

/// The bands the radio will relay in, as one readout line.
///
/// The radio answers `CMD_GET_ALLOWED_REPEAT_FREQ` with a list of kHz ranges,
/// and an empty list means it reported none. A radio that hears a channel and
/// will not repeat it looks exactly like a range problem, so the rule is worth
/// one line where the rest of the radio's own limits are.
String _repeatRanges(MeshcoreController mc, AppLocalizations l) {
  final List<({int lowerKhz, int upperKhz})>? r = mc.allowedRepeatFreq;
  if (r == null) return '${l.deviceRepeatUnknown}\n';
  if (r.isEmpty) return '${l.deviceRepeatNone}\n';
  String mhz(int khz) => (khz / 1000).toStringAsFixed(khz % 1000 == 0 ? 0 : 3);
  final String ranges = <String>[
    for (final ({int lowerKhz, int upperKhz}) x in r)
      '${mhz(x.lowerKhz)}–${mhz(x.upperKhz)}',
  ].join(', ');
  return '${l.deviceRepeatRanges(ranges)}\n';
}

/// The radio's contact-table policy, as switches that write the whole byte.
///
/// Each control sends `CMD_SET_AUTOADD_CONFIG` (0x3A) with the other bits
/// carried through, then re-reads the policy, because the radio clamps and may
/// refuse and its answer is the only truth. The count above the switches is the
/// same one the device-contacts screen shows, so "full" is visible on the page
/// where the policy that fills it is set.
class _ContactTableEditor extends StatefulWidget {
  const _ContactTableEditor({required this.mc, required this.enabled});
  final MeshcoreController mc;
  final bool enabled;

  @override
  State<_ContactTableEditor> createState() => _ContactTableEditorState();
}

class _ContactTableEditorState extends State<_ContactTableEditor> {
  bool _asked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _asked || !widget.mc.isReady) return;
      _asked = true;
      widget.mc.requestAutoAddConfig();
    });
  }

  Future<void> _write(Future<bool> Function() op) async {
    if (_busy) return;
    setState(() => _busy = true);
    await op();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final MeshcoreController mc = widget.mc;
    final AutoAddConfig? cfg = mc.autoAddConfig;
    final int? count = mc.deviceContactCount;
    final int? max = mc.maxContacts;
    final bool allow = widget.enabled && cfg != null && !_busy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l.autoAddIntro,
            style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: context.skin.type.sizeBody)),
        const SizedBox(height: 4),
        if (count != null)
          Text(
            max == null
                ? l.deviceContactsCountOnly(count)
                : l.deviceContactsCount(count, max),
            style: TextStyle(
                color: mc.contactsFull ? cs.error : cs.onSurface,
                fontFamily: context.skin.type.monoFamily),
          ),
        if (cfg == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            // Only say it is reading when it is: with no radio there is
            // nothing to read, and the page says so elsewhere.
            child: Text(
                widget.enabled ? l.autoAddUnknown : l.otherAwaitingDevice,
                style: TextStyle(color: cs.onSurfaceVariant)),
          )
        else ...<Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: cfg.overwriteOldest,
            onChanged: allow
                ? (bool v) => _write(() =>
                    mc.setAutoAddConfig(overwriteOldest: v))
                : null,
            title: Text(l.autoAddOverwriteOldest),
            subtitle: Text(l.autoAddOverwriteOldestHint),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: cfg.chat,
            onChanged:
                allow ? (bool v) => _write(() => mc.setAutoAddConfig(chat: v)) : null,
            title: Text(l.autoAddChat),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: cfg.repeater,
            onChanged: allow
                ? (bool v) => _write(() => mc.setAutoAddConfig(repeater: v))
                : null,
            title: Text(l.autoAddRepeater),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: cfg.roomServer,
            onChanged: allow
                ? (bool v) => _write(() => mc.setAutoAddConfig(roomServer: v))
                : null,
            title: Text(l.autoAddRoomServer),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: cfg.sensor,
            onChanged:
                allow ? (bool v) => _write(() => mc.setAutoAddConfig(sensor: v)) : null,
            title: Text(l.autoAddSensor),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.autoAddMaxHops),
            subtitle: Text(l.autoAddMaxHopsHint),
            trailing: SizedBox(
              width: telemLabelWidth(MediaQuery.textScalerOf(context)),
              child: TextFormField(
                key: const ValueKey<String>('auto-add-hops'),
                initialValue: '${cfg.maxHops}',
                enabled: allow,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.end,
                decoration: const InputDecoration(isDense: true),
                onFieldSubmitted: (String v) {
                  final int? n = int.tryParse(v.trim());
                  if (n == null || n < 0 || n > kAutoAddMaxHops) return;
                  _write(() => mc.setAutoAddConfig(maxHops: n));
                },
              ),
            ),
          ),
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.contacts),
          title: Text(l.autoAddManage),
          subtitle: Text(l.deviceContactsTitle),
          trailing: const Icon(Icons.chevron_right),
          // The radio-contacts screen has no named route: it is a
          // diagnostic page reached from the device sheet, so the same shape
          // is used here rather than inventing a second way in.
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const DeviceContactsScreen())),
        ),
      ],
    );
  }
}

/// Width of the "Base / Location / Environment" label column: 88dp at
/// normal text size, growing with the system text scale up to 120dp.
/// Fixed at 88 it broke "Environment" as "Environme / nt" on a phone set
/// to 1.3x. The cap keeps room for the three segments on a small screen.
@visibleForTesting
double telemLabelWidth(TextScaler scaler) =>
    (88 * scaler.scale(1)).clamp(88.0, 120.0);

/// Narrowest the three-segment control gets at 1.0x text (Off / Contacts /
/// Anyone, compact density, measured on the device). It scales with the text
/// like the labels do, so it is the other half of the fit question below.
const double _telemetrySegmentsAt1x = 208;

/// True when a label column and the segmented control can share one line.
/// Below this the row stacks: a stretched label column plus a squeezed
/// SegmentedButton overflowed by 37 px on a 387dp phone at 1.3x, and by
/// more at 2.0x.
@visibleForTesting
bool telemetryRowFits({
  required double available,
  required TextScaler scaler,
}) =>
    telemLabelWidth(scaler) + 8 + _telemetrySegmentsAt1x * scaler.scale(1) <=
    available;

/// Editable OTHER PARAMS block. The three settings (manual-add,
/// telemetry mode, multi-acks) all share the same `CMD_SET_OTHER_PARAMS`
/// (0x26) wire surface; each setter on `MeshcoreController` preserves
/// the other fields so we don't accidentally clobber them when only
/// one changes.
class _OtherParamsEditor extends StatefulWidget {
  const _OtherParamsEditor({
    required this.mc,
    required this.si,
    required this.enabled,
  });
  final MeshcoreController mc;
  final SelfInfo si;
  final bool enabled;

  @override
  State<_OtherParamsEditor> createState() => _OtherParamsEditorState();
}

class _OtherParamsEditorState extends State<_OtherParamsEditor> {
  // Telemetry mode is a packed byte: bits 0-1 = base, 2-3 = location,
  // 4-5 = environment. Each is a MeshCore *permission* level (companion
  // firmware NodePrefs.h): 0 = DENY, 1 = ALLOW_FLAGS (per-contact
  // flags), 2 = ALLOW_ALL. 3 is undefined, so we clamp to [0, 2] both on
  // read and write. This governs who may *request* each telemetry class
  // from the device — not whether the device has the sensor.
  late int _telBase = _telMode(widget.si.telemetryModeRaw);
  late int _telLoc = _telMode(widget.si.telemetryModeRaw >> 2);
  late int _telEnv = _telMode(widget.si.telemetryModeRaw >> 4);
  late int _multiAcks = widget.si.multiAcks;

  static const int telemDeny = 0;
  static const int telemFlags = 1;
  static const int telemAll = 2;


  /// Mask to the 2-bit field and clamp the undefined value 3 down to the
  /// highest defined level (ALLOW_ALL).
  static int _telMode(int raw) {
    final int v = raw & 0x03;
    return v > telemAll ? telemAll : v;
  }

  int get _telPacked => _telBase | (_telLoc << 2) | (_telEnv << 4);

  @override
  void didUpdateWidget(_OtherParamsEditor old) {
    super.didUpdateWidget(old);
    // SelfInfo can change underfoot (the device echoes back the new
    // value after a successful SET) — re-sync the local UI state to
    // match the truth.
    if (old.si.telemetryModeRaw != widget.si.telemetryModeRaw) {
      _telBase = _telMode(widget.si.telemetryModeRaw);
      _telLoc = _telMode(widget.si.telemetryModeRaw >> 2);
      _telEnv = _telMode(widget.si.telemetryModeRaw >> 4);
    }
    if (old.si.multiAcks != widget.si.multiAcks) {
      _multiAcks = widget.si.multiAcks;
    }
  }

  Future<void> _applyTelemetryMode() async {
    await widget.mc.setTelemetryMode(_telPacked);
    _snack();
  }

  Future<void> _applyMultiAcks(int v) async {
    setState(() => _multiAcks = v);
    await widget.mc.setMultiAcks(v);
    _snack();
  }

  void _snack() {
    if (!mounted) return;
    final AppLocalizations l = AppLocalizations.of(context);
    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l.otherSentSnack)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // manual-add — boolean.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(l.otherManualAddTitle),
          subtitle: Text(
            widget.si.manualAddContacts
                ? l.otherManualAddSubOn
                : l.otherManualAddSubOff,
            style: TextStyle(
                color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeBody),
          ),
          value: widget.si.manualAddContacts,
          onChanged: widget.enabled
              ? (bool v) async {
                  await widget.mc.setManualAddContacts(v);
                  _snack();
                }
              : null,
        ),
        const SizedBox(height: 6),
        // multi-acks — 0..3 segmented.
        Text(l.otherMultiAcksLabel,
            style: TextStyle(
                color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeBody, letterSpacing: 1)),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          segments: const <ButtonSegment<int>>[
            ButtonSegment<int>(value: 0, label: Text('0')),
            ButtonSegment<int>(value: 1, label: Text('1')),
            ButtonSegment<int>(value: 2, label: Text('2')),
            ButtonSegment<int>(value: 3, label: Text('3')),
          ],
          selected: <int>{_multiAcks.clamp(0, 3)},
          showSelectedIcon: false,
          onSelectionChanged: widget.enabled
              ? (Set<int> next) => _applyMultiAcks(next.first)
              : null,
        ),
        const SizedBox(height: 4),
        Text(l.otherMultiAcksHelper,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeSm)),
        const SizedBox(height: 8),
        // Telemetry sharing — base / location / environment. Each is a
        // permission level (Off / Contacts / Anyone) packed into one
        // byte; applied to the device on each change.
        Text(l.otherTelemetryModeTitle,
            style: TextStyle(
                color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeBody, letterSpacing: 1)),
        const SizedBox(height: 4),
        for (final (String, int, void Function(int)) row
            in <(String, int, void Function(int))>[
          (
            l.otherTelemetryBase,
            _telBase,
            (int v) {
              setState(() => _telBase = v);
              _applyTelemetryMode();
            }
          ),
          (
            l.otherTelemetryLoc,
            _telLoc,
            (int v) {
              setState(() => _telLoc = v);
              _applyTelemetryMode();
            }
          ),
          (
            l.otherTelemetryEnv,
            _telEnv,
            (int v) {
              setState(() => _telEnv = v);
              _applyTelemetryMode();
            }
          ),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: LayoutBuilder(
              builder: (BuildContext c, BoxConstraints box) {
                final TextScaler scaler = MediaQuery.textScalerOf(context);
                final Widget label = Text(row.$1,
                    style: TextStyle(color: cs.onSurface, fontSize: context.skin.type.sizeBodyLg));
                final Widget segments = SegmentedButton<int>(
                  segments: <ButtonSegment<int>>[
                    ButtonSegment<int>(
                        value: telemDeny, label: Text(l.otherTelemetryDeny)),
                    ButtonSegment<int>(
                        value: telemFlags, label: Text(l.otherTelemetryFlags)),
                    ButtonSegment<int>(
                        value: telemAll, label: Text(l.otherTelemetryAll)),
                  ],
                  selected: <int>{row.$2},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact),
                  onSelectionChanged:
                      widget.enabled ? (Set<int> s) => row.$3(s.first) : null,
                );
                // Label and control side by side while both fit (the 1.0x
                // layout, unchanged); stacked once the text scale leaves no
                // room, so neither side is squeezed into a break or an
                // overflow.
                if (telemetryRowFits(
                    available: box.maxWidth, scaler: scaler)) {
                  return Row(
                    children: <Widget>[
                      SizedBox(width: telemLabelWidth(scaler), child: label),
                      const SizedBox(width: 8),
                      Expanded(child: segments),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    label,
                    const SizedBox(height: 4),
                    segments,
                  ],
                );
              },
            ),
          ),
        const SizedBox(height: 4),
        Text(
          l.otherTelemetryModeHelp,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeSm),
        ),
      ],
    );
  }
}

/// Lat/lon `TextField` that subscribes to its own controller +
/// compares the typed text against the device's current
/// `selfInfo` value. When they diverge, an "✱ unsaved" suffix
/// renders in the input decoration so the user knows the
/// staged value hasn't been pushed to the device yet.
///
/// The comparison tolerates floating-point noise (1e-5 ≈ 1.1 m
/// at the equator) — typing "35.681" should not show "unsaved"
/// against a device value of 35.6810002 from JSON round-tripping.
class _LatLonField extends StatefulWidget {
  const _LatLonField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.deviceValue,
    required this.unsavedLabel,
  });

  final String label;
  final String hint;
  final TextEditingController controller;

  /// The device's last-reported value for this field. May be null
  /// (no selfInfo yet) — in that case we never show "unsaved"
  /// since we have no baseline.
  final double? deviceValue;

  final String unsavedLabel;

  @override
  State<_LatLonField> createState() => _LatLonFieldState();
}

class _LatLonFieldState extends State<_LatLonField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool get _unsaved {
    final double? dev = widget.deviceValue;
    if (dev == null) return false;
    final double? typed = double.tryParse(widget.controller.text.trim());
    if (typed == null) {
      // Empty / unparseable text: treat as unsaved iff the device
      // has a non-zero value.
      return dev.abs() >= 1e-9;
    }
    return (typed - dev).abs() > 1e-5;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: widget.controller,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
        ],
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          isDense: true,
          suffix: _unsaved
              ? Text(
                  widget.unsavedLabel,
                  style: TextStyle(
                      color: cs.tertiary,
                      fontSize: context.skin.type.sizeSm,
                      fontWeight: FontWeight.w600),
                )
              : null,
        ),
      ),
    );
  }
}

/// R39 — banner at the top of the region section that names the
/// currently-applied preset (matched against the device's live
/// radio params). Removes the "what am I on?" guesswork.
class _CurrentRegionBanner extends StatelessWidget {
  const _CurrentRegionBanner({
    required this.si,
    required this.cs,
    required this.l,
  });
  final SelfInfo? si;
  final ColorScheme cs;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final RegionPreset? match = si == null
        ? null
        : matchPresetByRadioParams(
            frequencyMhz: si!.frequencyMhz,
            bandwidthKhz: si!.bandwidthKhz,
            spreadingFactor: si!.spreadingFactor,
            codingRate: si!.codingRate,
          );
    final String label = si == null
        ? l.deviceRegionUnknown
        : match != null
            ? localizedPresetLabel(l, match.id)
            : l.deviceRegionCustom;
    final bool isCustom = si != null && match == null;
    final Color border = isCustom ? cs.tertiary : cs.primary;
    final Color fg = isCustom ? cs.tertiary : cs.primary;
    final MmSkin skin = context.skin;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: skin.space.rowInset, vertical: skin.space.rowGap),
      decoration: BoxDecoration(
        color: skin.color.surface,
        borderRadius: mmRadius(context, kRadiusSm),
        // The region badge's whole signal is its outline: custom vs matched.
        // At 50 % both drew the same faint edge on paper.
        border:
            Border.all(color: border, width: skin.shape.borderWidth),
      ),
      child: Row(
        children: <Widget>[
          Icon(isCustom ? Icons.tune : Icons.public, size: 18, color: fg),
          SizedBox(width: skin.space.rowGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l.deviceRegionCurrent,
                    style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: context.skin.type.sizeMicro,
                        letterSpacing: 2)),
                SizedBox(height: skin.space.insideText),
                Text(label,
                    style: TextStyle(
                        color: fg, fontSize: context.skin.type.size(15), fontWeight: FontWeight.w600)),
                if (si != null)
                  Text(
                    '${si!.frequencyMhz} MHz · ${si!.bandwidthKhz} kHz · '
                    'SF${si!.spreadingFactor} · CR${si!.codingRate} · '
                    '${si!.txPowerDbm} dBm',
                    style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontFamily: context.skin.type.monoFamily,
                        fontSize: context.skin.type.sizeSm),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _familyLabel(AppLocalizations l, RegionFamily f) => switch (f) {
      RegionFamily.americas => l.deviceRegionFamilyAmericas,
      RegionFamily.europe => l.deviceRegionFamilyEurope,
      RegionFamily.asiaPacific => l.deviceRegionFamilyAsiaPacific,
      RegionFamily.other => l.deviceRegionFamilyOther,
    };

/// R39 — selectable region preset chip. Highlights when the
/// preset's tuple matches the device's live radio params.
class _RegionChip extends StatelessWidget {
  const _RegionChip({
    required this.label,
    required this.note,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String? note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return InputChip(
      selected: selected,
      onPressed: onTap,
      avatar:
          selected ? Icon(Icons.check, size: 16, color: cs.onPrimary) : null,
      label: Text(label),
      tooltip: note,
      selectedColor: cs.primary,
      labelStyle: TextStyle(
        color: selected ? cs.onPrimary : cs.onSurface,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}

/// R38 — on-board GPS module controls.
///
/// Two firmware custom-vars: `gps` (0/1, powers the module) and
/// `gps_interval` (seconds, 0-86400, polling cadence into
/// `sensors.node_lat/lon`). Both default to 0 on fresh firmware.
/// Without these, picking "Device GPS" in the advert-source
/// segmented button above is a no-op — that policy only governs
/// whether GPS coords get *into adverts*, not whether the device
/// reads its chip at all.
class _GpsModuleControls extends StatelessWidget {
  const _GpsModuleControls({
    required this.mc,
    required this.ready,
    required this.cs,
    required this.l,
  });

  final MeshcoreController mc;
  final bool ready;
  final ColorScheme cs;
  final AppLocalizations l;

  static const List<int> _intervalOptions = <int>[0, 10, 30, 60, 300];

  static String _intervalLabel(AppLocalizations l, int sec) {
    if (sec <= 0) return l.deviceGpsIntervalOff;
    if (sec < 60) return l.deviceGpsIntervalSec(sec);
    if (sec < 3600) return l.deviceGpsIntervalMin(sec ~/ 60);
    return l.deviceGpsIntervalHour(sec ~/ 3600);
  }

  @override
  Widget build(BuildContext context) {
    final bool? enabled = mc.deviceGpsEnabled;
    final int? interval = mc.deviceGpsIntervalSec;
    final bool unknown = enabled == null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.deviceGpsModule,
              style: TextStyle(
                  color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeBody, letterSpacing: 1)),
          const SizedBox(height: 4),
          // gps switch
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(l.deviceGpsEnable),
            subtitle: Text(
              unknown
                  ? l.deviceGpsUnknown
                  : enabled
                      ? l.deviceGpsEnabledHint
                      : l.deviceGpsDisabledHint,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            value: enabled ?? false,
            onChanged: !ready || unknown
                ? null
                : (bool v) async {
                    try {
                      await mc.setCustomVar(name: 'gps', value: v ? '1' : '0');
                    } catch (_) {/* silent — toast is overkill */}
                  },
          ),
          // gps_interval picker — only when the firmware actually
          // advertises the key. On hardware where it isn't exposed
          // (e.g. T1000-E v1.15.0) writes ERR with ILLEGAL_ARG, so
          // hide the control and show a one-line note instead.
          if (mc.supportsGpsInterval == true)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer_outlined),
              title: Text(l.deviceGpsInterval),
              subtitle: Text(
                interval == null
                    ? l.deviceGpsUnknown
                    : _intervalLabel(l, interval),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              enabled: ready && enabled == true,
              trailing: const Icon(Icons.chevron_right),
              onTap: !(ready && enabled == true)
                  ? null
                  : () => _pickInterval(context, interval ?? 0),
            )
          else if (mc.supportsGpsInterval == false && enabled == true)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              // The reason is a tooltip rather than a line: a firmware key
              // name is not something to read on the page.
              child: Tooltip(
                message: l.deviceGpsIntervalWhy,
                child: Text(l.deviceGpsIntervalFixedByFirmware,
                    style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: context.skin.type.sizeSm)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickInterval(BuildContext ctx, int current) async {
    final int? picked = await showMmPicker<int>(
      context: ctx,
      title: l.deviceGpsInterval,
      current: current,
      items: <MmPickerItem<int>>[
        for (final int s in _intervalOptions)
          MmPickerItem<int>.option(s, _intervalLabel(l, s)),
      ],
    );
    if (picked != null && picked != current) {
      try {
        await mc.setCustomVar(
          name: 'gps_interval',
          value: '$picked',
          // Some firmware builds don't expose gps_interval as a
          // settable sensors key — they reply ILLEGAL_ARG. Don't
          // surface that in the recent-activity feed.
          absorbErrorFromUserFeed: true,
        );
      } catch (_) {/* silent */}
    }
  }
}
