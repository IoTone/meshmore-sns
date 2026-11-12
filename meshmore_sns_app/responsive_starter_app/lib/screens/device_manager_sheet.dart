// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/ble_connector.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/paired_device_history.dart';
import 'device_contacts_screen.dart';
import '../ui/mm_shape.dart';
import '../theme/mm_skin.dart';
import 'package:meshcore/meshcore.dart';
import '../util/relative_time.dart';

/// R41 — Device management sheet. Single place to:
///   - see what we're currently paired to and the live connection state,
///   - disconnect or reconnect,
///   - forget the paired device,
///   - scan for nearby MeshCore devices and pick a different one (when
///     two T1000-Es are in range, this is how you choose).
///
/// Lives in a modal bottom sheet rather than a full screen so it can be
/// summoned from the dashboard's "DEVICE" chip with one tap and
/// dismissed by swiping down — no nested-route boilerplate.
class DeviceManagerSheet extends StatefulWidget {
  const DeviceManagerSheet({super.key});

  /// Convenience opener so callers don't have to remember the modal
  /// presentation flags.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => const DeviceManagerSheet(),
    );
  }

  @override
  State<DeviceManagerSheet> createState() => _DeviceManagerSheetState();
}

class _DeviceManagerSheetState extends State<DeviceManagerSheet> {
  /// Live snapshot of devices found in the current scan. Keyed by
  /// remote ID so a device whose RSSI updates doesn't appear twice.
  final Map<String, ScanResult> _hits = <String, ScanResult>{};

  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _scanning = false;
  String? _scanError;

  @override
  void dispose() {
    _scanSub?.cancel();
    BleConnector.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _scanError = null;
      _hits.clear();
    });
    try {
      _scanSub = BleConnector.scanForDevices(
        timeout: const Duration(seconds: 12),
      ).listen(
        (List<ScanResult> snapshot) {
          if (!mounted) return;
          // Merge into the keyed map so we don't lose earlier hits
          // when a snapshot omits a device that's now out of range
          // for a single sweep. Each device is upserted by remote id.
          for (final ScanResult r in snapshot) {
            _hits[r.device.remoteId.str] = r;
          }
          setState(() {});
        },
        onError: (Object e) {
          if (!mounted) return;
          setState(() {
            _scanError = '$e';
            _scanning = false;
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _scanning = false);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanError = '$e';
        _scanning = false;
      });
    }
  }

  Future<void> _stopScan() async {
    await BleConnector.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _pickDevice(
      MeshcoreController mc, ScanResult r) async {
    await _stopScan();
    final String name = r.device.platformName.isNotEmpty
        ? r.device.platformName
        : (r.device.advName.isNotEmpty
            ? r.device.advName
            : r.device.remoteId.str);
    if (!mounted) return;
    Navigator.of(context).pop();
    await mc.connectToPickedDevice(
        remoteId: r.device.remoteId.str, name: name);
  }

  Future<void> _disconnect(MeshcoreController mc) async {
    await mc.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _forget(MeshcoreController mc) async {
    await mc.forgetDevice();
    if (mounted) Navigator.of(context).pop();
  }

  /// Coarse human-readable "last used" — fine-grained timestamps are
  /// unhelpful for a "pick a previous device" list. Buckets: now /
  /// minutes / hours / days. Mirrors the chat / nodes screen's
  /// ago-formatter idiom.
  String _relativeAgo(int unix, AppLocalizations l) {
    if (unix <= 0) return l.deviceMgrAgoNever;
    return deviceAgo(l, ageSinceUnix(unix));
  }

  String _stateLabel(MeshcoreController mc, AppLocalizations l) {
    if (mc.isConnecting) return l.deviceMgrStateConnecting;
    return switch (mc.state) {
      MeshcoreConnectionState.ready => l.deviceMgrStateConnected,
      MeshcoreConnectionState.handshaking => l.deviceMgrStateConnecting,
      MeshcoreConnectionState.reconnecting =>
        l.deviceMgrStateReconnecting,
      MeshcoreConnectionState.failed => l.deviceMgrStateFailed,
      MeshcoreConnectionState.disconnected =>
        l.deviceMgrStateDisconnected,
    };
  }

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool isLive = mc.state == MeshcoreConnectionState.ready ||
        mc.state == MeshcoreConnectionState.handshaking;
    final bool isPaired = mc.hasPairedDevice;
    final MmSkin skin = context.skin;

    final List<ScanResult> sortedHits = _hits.values.toList()
      ..sort((ScanResult a, ScanResult b) =>
          b.rssi.compareTo(a.rssi));

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(skin.space.screenEdge, 0,
            skin.space.screenEdge, skin.space.rowInset),
        // The sheet is a modal with no app bar and no second route out, and its
        // content is a header, three action rows, the pair flow, the scan row,
        // the hint and the hit list: at 320 dp with 200 % text it overflowed by
        // 358 px, so the bottom of it — the list you came for — was off-screen.
        // It scrolls, and the sheet is already `isScrollControlled`.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
            // Header.
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(l.deviceMgrTitle,
                  style: TextStyle(
                      color: cs.primary,
                      fontSize: context.skin.type.sizeBody,
                      letterSpacing: 3)),
            ),
            // Current state line.
            _StatusRow(
              name: mc.pairedName ?? l.deviceMgrNoPair,
              state: _stateLabel(mc, l),
              alert: mc.state == MeshcoreConnectionState.failed,
              live: isLive,
            ),
            const SizedBox(height: 12),
            // Primary actions row.
            Row(
              children: <Widget>[
                if (isLive)
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link_off, size: 18),
                      label: Text(l.deviceMgrDisconnect),
                      onPressed: () => _disconnect(mc),
                    ),
                  )
                else if (isPaired)
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.link, size: 18),
                      label: Text(l.deviceMgrReconnect),
                      onPressed: mc.isConnecting
                          ? null
                          : () {
                              // The sheet's context survives the push; only a
                              // pop would take it away.
                              GoRouter.of(context).push('/connect');
                            },
                    ),
                  ),
                if (isPaired) const SizedBox(width: 8),
                if (isPaired)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(l.deviceMgrForget),
                    onPressed: () => _forget(mc),
                  ),
              ],
            ),
            // The guided flow, for a first pairing or a new radio: one screen
            // that explains each state instead of a scan list on its own.
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.add_link, color: cs.primary),
              title: Text(l.deviceMgrPairNew),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // Capture the router before the pop: the sheet's context is
                // gone by the time the push would run.
                final GoRouter router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.push('/connect');
              },
            ),
            // Probe + manage the radio's actual contact list (diagnose a
            // full table / a contact that won't DM).
            if (mc.isReady)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading:
                    Icon(Icons.contacts_outlined, color: cs.onSurfaceVariant),
                title: Text(l.deviceContactsTitle),
                subtitle: mc.deviceContactCount == null
                    ? null
                    : Text(l.deviceContactsCountOnly(mc.deviceContactCount!),
                        style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontFamily: context.skin.type.monoFamily,
                            fontSize: context.skin.type.sizeSm)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final NavigatorState nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute<void>(
                      builder: (_) => const DeviceContactsScreen()));
                },
              ),
            // R41+1 — Recently paired list. Quickest path back to
            // a device the user has used before, without scanning.
            // Hidden when empty (first-run users see only the scan
            // option). The currently-paired device is suppressed
            // from the list because it already appears in the
            // status row above.
            if (mc.pairedHistory
                .where((PairedDeviceHistoryEntry e) =>
                    e.remoteId != mc.pairedRemoteId)
                .isNotEmpty) ...<Widget>[
              const Divider(height: 28),
              Text(l.deviceMgrRecent,
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: context.skin.type.sizeSm,
                      letterSpacing: 2)),
              const SizedBox(height: 4),
              for (final PairedDeviceHistoryEntry e
                  in mc.pairedHistory)
                if (e.remoteId != mc.pairedRemoteId)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.history,
                        color: cs.onSurfaceVariant),
                    title: Text(e.name),
                    subtitle: Text(
                      '${e.remoteId}  ·  '
                      '${_relativeAgo(e.lastUsedUnix, l)}',
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontFamily: context.skin.type.monoFamily,
                          fontSize: context.skin.type.sizeSm),
                    ),
                    trailing: IconButton(
                      tooltip: l.deviceMgrForget,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () =>
                          mc.forgetHistoryEntry(e.remoteId),
                    ),
                    onTap: () async {
                      if (!mounted) return;
                      Navigator.of(context).pop();
                      await mc.connectFromHistory(e.remoteId);
                    },
                  ),
            ],
            const Divider(height: 28),
            // Scan section.
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(l.deviceMgrPick,
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: context.skin.type.sizeSm,
                          letterSpacing: 2)),
                ),
                if (_scanning)
                  TextButton.icon(
                    icon: const Icon(Icons.stop_circle_outlined,
                        size: 16),
                    label: Text(l.deviceMgrStopScan),
                    onPressed: _stopScan,
                  )
                else
                  TextButton.icon(
                    icon: const Icon(Icons.search, size: 16),
                    label: Text(l.deviceMgrScan),
                    onPressed: _startScan,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (_scanError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l.deviceMgrScanFailed('$_scanError'),
                  style: TextStyle(
                      color: cs.error, fontSize: context.skin.type.sizeBody),
                ),
              ),
            if (sortedHits.isEmpty && !_scanning && _scanError == null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12),
                child: Text(l.deviceMgrScanHint,
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeBody)),
              ),
            if (sortedHits.isEmpty && _scanning)
              Padding(
                padding: EdgeInsets.symmetric(
                    vertical: context.skin.space.emptyState),
                child: Center(
                  child: SizedBox.square(
                    dimension: context.skin.space.screenEdge,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            // Hit list — capped to ~6 rows of fixed scroll so the
            // sheet doesn't grow past the screen on a noisy scan.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sortedHits.length,
                itemBuilder: (BuildContext _, int i) {
                  final ScanResult r = sortedHits[i];
                  final String name = r.device.platformName.isNotEmpty
                      ? r.device.platformName
                      : (r.device.advName.isNotEmpty
                          ? r.device.advName
                          : r.device.remoteId.str);
                  // Highlight the currently-paired device, if any.
                  final bool isCurrent =
                      mc.pairedName == name; // best-effort match
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isCurrent
                          ? Icons.check_circle
                          : Icons.bluetooth,
                      color: isCurrent
                          ? cs.primary
                          : cs.onSurfaceVariant,
                    ),
                    title: Text(name),
                    subtitle: Text(
                      '${r.device.remoteId.str}  ·  '
                      'RSSI ${r.rssi}',
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontFamily: context.skin.type.monoFamily,
                          fontSize: context.skin.type.sizeSm),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickDevice(mc, r),
                  );
                },
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.name,
    required this.state,
    required this.alert,
    required this.live,
  });
  final String name;
  final String state;
  final bool alert;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color accent = alert
        ? cs.error
        : live
            ? cs.primary
            : cs.onSurfaceVariant;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.skin.space.rowInset,
          vertical: context.skin.space.rowGap),
      decoration: BoxDecoration(
        color: context.skin.color.surface,
        borderRadius: mmRadius(context, kRadiusSm),
        // The status card's edge is its state colour, drawn at full strength:
        // at 50 % it is 1.9:1 on paper, so a live link and a dead one had the
        // same outline.
        border: Border.all(
            color: accent, width: context.skin.shape.borderWidth),
      ),
      child: Row(
        children: <Widget>[
          Icon(
              live
                  ? Icons.bluetooth_connected
                  : alert
                      ? Icons.error_outline
                      : Icons.bluetooth_disabled,
              color: accent,
              size: 22),
          SizedBox(width: context.skin.space.rowGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(name,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: context.skin.type.sizeBodyLg)),
                SizedBox(height: context.skin.space.insideText),
                Text(state,
                    style: TextStyle(
                        color: accent,
                        fontSize: context.skin.type.sizeSm,
                        letterSpacing: 2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
