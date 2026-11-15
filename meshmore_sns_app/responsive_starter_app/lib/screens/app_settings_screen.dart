// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/demo_mode.dart';
import '../chat/history_export_action.dart';
import '../gen/app_localizations.dart';
import '../l10n/locale_controller.dart';
import '../meshcore/airtime.dart';
import '../meshcore/block_store.dart';
import '../media/media_prefs.dart';
import '../meshcore/meshcore_controller.dart';
import '../notifications/notifier.dart';
import '../perms/battery_exemption.dart';
import '../perms/permissions_service.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import '../ui/mm_collapsible.dart';
import '../ui/mm_confirm.dart';
import '../ui/mm_collapse_controller.dart';
import '../ui/storage_use_block.dart';
import '../ui/mm_scaffold.dart';
import '../util/mm_format.dart';
import '../tts/tts_controller.dart';

/// General app settings (R3/R4/R5/R21). Connection, language, TTS,
/// notifications, diagnostics, About/Terms. The **global TTS switch**
/// (R5 parent control) is functional from U3; the remaining rows are
/// routed scaffolds wired in U5.
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  /// R21 / U12 — first-time toggle-on of the background keepalive
  /// triggers the **notifications** permission ask. If the user
  /// declines we revert the switch and surface a snack with
  /// "Open settings". If they grant it, we proceed to start the
  /// foreground service via the existing setter.
  Future<void> _onBgToggle(
      BuildContext ctx, MeshcoreController mc, bool v) async {
    if (!v) {
      await mc.setBackgroundKeepaliveEnabled(false);
      return;
    }
    final PermissionsService perms = ctx.read<PermissionsService>();
    final bool already = await perms.notificationsGranted();
    PermissionResult r = PermissionResult.granted;
    if (!already) {
      r = await perms.requestNotifications();
    }
    if (!ctx.mounted) return;
    if (r == PermissionResult.granted || r == PermissionResult.notApplicable) {
      await mc.setBackgroundKeepaliveEnabled(true);
      return;
    }
    // Denied — keep the toggle off and explain.
    final AppLocalizations l = AppLocalizations.of(ctx);
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
      SnackBar(
        content: Text(r == PermissionResult.permanentlyDenied
            ? l.settingsNotifDeniedPermanent
            : l.settingsNotifDeniedTransient),
        action: SnackBarAction(
          label: l.deviceOpenSettings,
          onPressed: () => ctx.read<PermissionsService>().openAppSettingsPage(),
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  /// A stand-in for a screen mounted without the store (a harness, a screenshot
  /// test). Static so it does not make this widget mutable; the app always has
  /// the real one above it.
  static final FormatPrefs _fallbackFormat = FormatPrefs();

  Future<void> _pickUnits(
      BuildContext ctx, FormatPrefs fmt, AppLocalizations l) async {
    final DistanceUnits? picked = await showModalBottomSheet<DistanceUnits>(
      context: ctx,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              dense: true,
              key: const ValueKey<String>('units-metric'),
              title: Text(l.settingsUnitsMetric),
              subtitle: Text(l.settingsUnitsMetricHint),
              trailing: fmt.units == DistanceUnits.metric
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(sheet, DistanceUnits.metric),
            ),
            ListTile(
              dense: true,
              key: const ValueKey<String>('units-imperial'),
              title: Text(l.settingsUnitsImperial),
              subtitle: Text(l.settingsUnitsImperialHint),
              trailing: fmt.units == DistanceUnits.imperial
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(sheet, DistanceUnits.imperial),
            ),
          ],
        ),
      ),
    );
    if (picked != null) await fmt.setUnits(picked);
  }

  String _languageLabel(AppLocalizations l, Locale? loc) {
    if (loc == null) return l.settingsLanguageSystem;
    return switch (loc.languageCode) {
      'en' => l.settingsLanguageEnglish,
      'ja' => l.settingsLanguageJapanese,
      _ => loc.languageCode,
    };
  }

  Future<void> _pickLanguage(BuildContext ctx, LocaleController lc) async {
    final AppLocalizations l = AppLocalizations.of(ctx);
    final Locale? picked = await showModalBottomSheet<Locale?>(
      context: ctx,
      showDragHandle: true,
      builder: (BuildContext _) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              dense: true,
              title: Text(l.settingsLanguageSystem),
              trailing: lc.locale == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, null),
            ),
            ListTile(
              dense: true,
              title: Text(l.settingsLanguageEnglish),
              trailing: lc.locale?.languageCode == 'en'
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(ctx, const Locale('en')),
            ),
            ListTile(
              dense: true,
              title: Text(l.settingsLanguageJapanese),
              trailing: lc.locale?.languageCode == 'ja'
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(ctx, const Locale('ja')),
            ),
          ],
        ),
      ),
    );
    // `null` picked means "system default"; `picked == null && popped
    // by drag` means no change. Disambiguate by looking at whether the
    // sheet actually returned a value vs being dismissed. showModal*
    // returns null on dismiss, so we can't tell them apart here —
    // treat any returned-null as "system default" via an explicit tap
    // (drag-dismissed without tapping won't have a "System" trailing
    // check to confirm). Edge: dismissing the sheet now also resets
    // to system. Acceptable in v1.
    await lc.set(picked);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TtsController tts = context.watch<TtsController>();
    final DemoMode demo = context.watch<DemoMode>();
    final MeshcoreController mc = context.watch<MeshcoreController>();
    // A harness may mount this screen without the provider; the neutral defaults
    // are the same answer the app gives before the store has loaded.
    final FormatPrefs fmt = context.watchFormatPrefs ?? _fallbackFormat;
    final LocaleController lc = context.watch<LocaleController>();
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsHeading)),
      body: MmScaffold(
        child: ListView(
          padding: context.skin.space.padScreen,
          children: <Widget>[
            // D8.20 — the OS may have the permission off while the app is
            // otherwise ready. Say so once, in the place the toggle lives, so
            // a silent lock screen is not mistaken for a radio failure.
            const _NotificationsDeniedBanner(),
            const _NotificationHealthRow(),
            MmSectionHeader(l.settingsAppGroupRadio),
            // Radio-free mode. Off is the normal state; turning it off asks an
            // already-paired companion to reconnect rather than waiting for the
            // next launch.
            SwitchListTile(
              dense: true,
              title: Text(l.demoModeRow),
              subtitle: Text(
                l.demoModeSubtitle,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              secondary: Icon(demo.enabled ? Icons.science : Icons.podcasts),
              value: demo.enabled,
              onChanged: (bool v) => demo.setEnabled(v,
                  onEnabled: () => mc.disconnect(),
                  onDisabled: () => mc.autoConnectIfPaired()),
            ),
            // R17/U8 — Android background keep-alive (foreground service
            // + persistent notification). No-op on iOS.
            SwitchListTile(
              dense: true,
              title: Text(l.settingsBackgroundTitle),
              subtitle: Text(
                !mc.backgroundKeepaliveEnabled
                    ? l.settingsBackgroundOff
                    : mc.keepaliveFailure != null
                        ? l.settingsBackgroundFailed
                        // "On" is a preference; the service is a fact. The row
                        // used to say on whenever the switch was on and no Dart
                        // exception had been recorded, which is not the same
                        // thing: the plugin can start and immediately stop the
                        // service natively and still return success.
                        : !mc.keepaliveRunning
                            ? l.settingsBackgroundNotRunning
                            : l.settingsBackgroundOn,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              secondary: Icon(mc.backgroundKeepaliveEnabled
                  ? Icons.cloud_sync
                  : Icons.cloud_off),
              value: mc.backgroundKeepaliveEnabled,
              onChanged: (bool v) => _onBgToggle(context, mc, v),
            ),
            // The switch above is a preference. This is the fact that decides
            // whether the OS honours it: an OEM can stop a foreground service
            // that is still on the battery-optimisation list, and until this
            // row existed the app had no way to say so.
            _BatteryExemptionRow(enabled: mc.backgroundKeepaliveEnabled),
            // Background peer-telemetry polling — politely cycles
            // contacts so temperature / altitude populate across the
            // fabric. Costs a little OTA airtime; off = no telemetry
            // traffic from us.
            SwitchListTile(
              dense: true,
              title: Text(l.settingsTelemetryPoll),
              subtitle: Text(
                mc.telemetryPollEnabled
                    ? l.settingsTelemetryPollOn
                    : l.settingsTelemetryPollOff,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              secondary: Icon(mc.telemetryPollEnabled
                  ? Icons.thermostat
                  : Icons.thermostat_auto),
              value: mc.telemetryPollEnabled,
              onChanged: (bool v) => mc.setTelemetryPollEnabled(v),
            ),
            // APP-C5 — the app meters its own transmitter and stops at the
            // limit. The policy is a claim about the channel, not about the
            // law: the radio keeps its own regulatory limit either way.
            ListTile(
              dense: true,
              leading: const Icon(Icons.data_usage),
              title: Text(l.settingsAirtimeTitle),
              subtitle: Text(
                mc.airtimePolicy == AirtimePolicy.ownedChannel
                    ? l.airtimePolicyOwned
                    : l.airtimePolicyOnePercent,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickAirtimePolicy(context, mc, l),
            ),
            // The cutoff the owner asked for: the policy above says what the
            // channel's budget is, this says whether this app enforces it, and
            // the line under it is the only place the time left in the hour is
            // stated.
            SwitchListTile(
              dense: true,
              key: const ValueKey<String>('settings-airtime-cutoff'),
              secondary: const Icon(Icons.hourglass_bottom),
              title: Text(l.airtimeCutoffTitle),
              subtitle: Text(
                mc.airtimeCutoff
                    ? l.airtimeCutoffSubtitle
                    : l.airtimeCutoffOff,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              value: mc.airtimeCutoff,
              onChanged: (bool v) => mc.setAirtimeCutoff(v),
            ),
            ListTile(
              dense: true,
              key: const ValueKey<String>('settings-airtime-left'),
              title: Text(l.airtimeLeftInHour),
              trailing: Text(
                switch (mc.airtimeLeft) {
                  final Duration left => l.airtimeLeftValue(
                      _mmShort(left), _mmShort(mc.airtimeBudget!)),
                  null => l.airtimePolicyOwned,
                },
                style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures()
                    ]),
              ),
            ),
            SizedBox(height: context.skin.space.sectionGap),
            MmSectionHeader(l.settingsAppGroupReading),
            // Units and clock. The app had no such setting at all: distances were
            // metres and kilometres in six formatting sites and every timestamp
            // followed the phone's locale, so a reader who thinks in miles
            // converted in their head and a 12-hour phone showed two clock
            // conventions in one app.
            ListTile(
              dense: true,
              key: const ValueKey<String>('settings-units-distance'),
              leading: const Icon(Icons.straighten),
              title: Text(l.settingsUnits),
              subtitle: Text(
                  fmt.units == DistanceUnits.imperial
                      ? l.settingsUnitsImperial
                      : l.settingsUnitsMetric,
                  style: TextStyle(color: cs.onSurfaceVariant)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickUnits(context, fmt, l),
            ),
            SwitchListTile(
              dense: true,
              key: const ValueKey<String>('settings-clock-24'),
              secondary: const Icon(Icons.schedule),
              title: Text(l.settingsClock24),
              subtitle: Text(
                  fmt.clock24 ? l.settingsClock24On : l.settingsClock12On,
                  style: TextStyle(color: cs.onSurfaceVariant)),
              value: fmt.clock24,
              onChanged: (bool v) => fmt.setClock24(v),
            ),
            SwitchListTile(
              dense: true,
              key: const ValueKey<String>('settings-temperature'),
              secondary: const Icon(Icons.thermostat),
              title: Text(l.settingsCelsius),
              subtitle: Text(
                  fmt.celsius ? l.settingsCelsiusOn : l.settingsFahrenheitOn,
                  style: TextStyle(color: cs.onSurfaceVariant)),
              value: fmt.celsius,
              onChanged: (bool v) => fmt.setCelsius(v),
            ),
            SizedBox(height: context.skin.space.sectionGap),
            MmSectionHeader(l.settingsAppGroupSound),
            // Spoken messages: how the app reads incoming messages aloud. This is
            // a reading preference — rate, pitch, which engine — and it belongs
            // with the other reading and sound controls, not with what a message
            // costs to send.
            ListTile(
              dense: true,
              leading: const Icon(Icons.record_voice_over_outlined),
              title: Text(l.voiceSettingsTitle),
              subtitle: Text(
                '${l.voiceRate} ${tts.rate.toStringAsFixed(1)}× · '
                '${l.voicePitch} ${tts.pitch.toStringAsFixed(1)}'
                '${tts.voice == null ? '' : ' · ${tts.voice!.name}'}',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/voice'),
            ),
            // R4 — language picker. Tap-to-open bottom sheet with
            // System / English / 日本語; the choice is persisted by
            // LocaleController and re-skins the whole tree live.
            ListTile(
              dense: true,
              leading: const Icon(Icons.language),
              title: Text(l.settingsLanguage),
              subtitle: Text(_languageLabel(l, lc.locale),
                  style: TextStyle(color: cs.onSurfaceVariant)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickLanguage(context, lc),
            ),
            // SPEECH (R5) — functional from U3. Off by default; the
            // per-channel toggle in the Chat header is gated on this.
            // Speech also answers to the audio master, so an enabled
            // switch can still be inaudible — say so rather than
            // leaving the user with a toggle that does nothing.
            SwitchListTile(
              dense: true,
              title: Text(l.settingsSpeech),
              subtitle: Text(
                !tts.enabled
                    ? l.settingsSpeechOff
                    : tts.speechAudible
                        ? l.settingsSpeechOn
                        : l.settingsSpeechMuted,
                style: TextStyle(
                    color: tts.enabled && !tts.speechAudible
                        ? cs.error
                        : cs.onSurfaceVariant),
              ),
              secondary: Icon(tts.enabled && tts.speechAudible
                  ? Icons.record_voice_over
                  : Icons.voice_over_off),
              value: tts.enabled,
              onChanged: (bool v) => tts.setEnabled(v),
            ),
            // Silence is per channel and lives on the channel's own sheet, in
            // Settings → Channels: asking it here answered for slot 0 only, so
            // the switch that said "public channel notifications" was the one
            // channel nobody could silence from anywhere else — and the sheet
            // pointed back here. One place, every channel.
            ListTile(
              dense: true,
              key: const ValueKey<String>('settings-channel-silence'),
              leading: const Icon(Icons.notifications_off_outlined),
              title: Text(l.settingsSilencePerChannel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/channels'),
            ),
            // Voice lives on Settings → Chat & media, with everything else a
            // message is. This row was a second door to the same page.
            SizedBox(height: context.skin.space.sectionGap),
            MmSectionHeader(l.settingsAppGroupData),
            // Colour or grey. A mesh photo has one budget and grey is a third
            // of the data, so grey is the default and this is the way back.
            _PhotoColorSwitch(cs: cs, l: l),
            // R36 — Auto-publish location. Lives here so users find
            // it under "App settings" rather than buried in Device
            // config; the device-side advert policy is separate.
            ListTile(
              dense: true,
              leading: const Icon(Icons.satellite_alt),
              title: Text(l.locTitle),
              subtitle: Text(l.locTileSubtitle,
                  style: TextStyle(color: cs.onSurfaceVariant)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/location'),
            ),
            SizedBox(height: context.skin.space.sectionGap),
            MmSectionHeader(l.settingsAppGroupSystem),
            // R21 / U12 — Permissions row: jumps to the OS app-settings
            // page where the user can flip BLE / Notifications etc.
            // back on after a permanent denial.
            ListTile(
              dense: true,
              leading: const Icon(Icons.lock_outline),
              title: Text(l.settingsPermissions),
              subtitle: Text(
                l.settingsPermissionsSubtitle,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () =>
                  context.read<PermissionsService>().openAppSettingsPage(),
            ),
            // APP-F1..F3 - blocking is a content setting, so it lives with the
            // content settings rather than in Device configuration.
            ListTile(
              dense: true,
              leading: const Icon(Icons.block),
              title: Text(l.blockedKeysTitle),
              subtitle: Text(
                l.blockedKeysSubtitle(context.watch<BlockStore>().count),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/blocks'),
            ),
            // A backup is the opposite promise to the per-conversation export:
            // that one hands over this thread only, this one hands over
            // everything, which is what restore reads.
            ListTile(
              dense: true,
              key: const ValueKey<String>('settings-export-history'),
              leading: const Icon(Icons.save_alt),
              title: Text(l.settingsHistoryExportRow),
              subtitle: Text(l.settingsHistoryExportSubtitle,
                  style: TextStyle(color: cs.onSurfaceVariant)),
              trailing: const Icon(Icons.ios_share),
              onTap: () => exportAllHistory(context, mc),
            ),
            // Storage: every store states its own bound, and until this block
            // there was no single place where growth was visible. It shows the
            // sizes that exist (map data has a real byte counter, the sealed
            // history reports its own record size) and the counts that are rows
            // rather than files. The action clears only what the app can rebuild.
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: MmCollapsibleSection(
                id: MmGroupIds.persStorage,
                title: l.storageTitle,
                initiallyExpanded: false,
                children: <Widget>[
                  const StorageUseBlock(),
                ],
              ),
            ),
            // Radio access: the pairing PIN is the radio's own gate on a new
            // Bluetooth pairing (`CMD_SET_DEVICE_PIN` 0x25), and until this block
            // the only way to change it was the radio's own screen.
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: MmCollapsibleSection(
                id: MmGroupIds.persSecurity,
                title: l.settingsSecuritySection,
                initiallyExpanded: false,
                children: <Widget>[_RadioPinBlock(mc: mc)],
              ),
            ),
            // The terms and privacy row is on About, where a reader looks for
            // what the app is and what it promises. App settings is for things
            // you change, and this page is read.
          ],
        ),
      ),
    );
  }

  /// The two policies, with what each one claims. A list rather than a switch
  /// because "no limit" is a statement about the frequency, not a preference
  /// about speed, and it needs a sentence to be safe.
  /// Seconds or minutes, whichever reads shorter.
  static String _mmShort(Duration d) {
    final int s = d.inSeconds;
    return s < 60 ? '${s}s' : '${(s / 60).toStringAsFixed(1)} min';
  }

  Future<void> _pickAirtimePolicy(
      BuildContext ctx, MeshcoreController mc, AppLocalizations l) async {
    final AirtimePolicy? chosen = await showMmPicker<AirtimePolicy>(
      context: ctx,
      title: l.settingsAirtimeTitle,
      current: mc.airtimePolicy,
      items: <MmPickerItem<AirtimePolicy>>[
        MmPickerItem<AirtimePolicy>.header(l.settingsAirtimeTitle),
        MmPickerItem<AirtimePolicy>.option(
            AirtimePolicy.onePercentDutyCycle, l.airtimePolicyOnePercentSub,
            icon: Icons.timer_outlined),
        MmPickerItem<AirtimePolicy>.option(
            AirtimePolicy.ownedChannel, l.airtimePolicyOwnedSub,
            icon: Icons.all_inclusive),
        MmPickerItem<AirtimePolicy>.header(l.settingsAirtimeHelp),
      ],
    );
    if (chosen == null) return;
    await mc.setAirtimePolicy(chosen);
  }
}

/// A one-line notice when the OS notification permission is off.
///
/// It reads the permission each build rather than caching it, because the
/// user can grant it from system settings and come back without a restart.
class _NotificationsDeniedBanner extends StatelessWidget {
  const _NotificationsDeniedBanner();

  @override
  Widget build(BuildContext context) {
    final PermissionsService perms = context.read<PermissionsService>();
    return FutureBuilder<bool>(
      future: perms.notificationsGranted(),
      builder: (BuildContext ctx, AsyncSnapshot<bool> snap) {
        if (snap.data != false) return const SizedBox.shrink();
        final AppLocalizations l = AppLocalizations.of(ctx);
        return ListTile(
              dense: true,
          leading: const Icon(Icons.notifications_off_outlined),
          title: Text(l.notifDeniedBanner),
          trailing: MmAction(
            label: l.deviceOpenSettings,
            dense: true,
            onPressed: () =>
                ctx.read<PermissionsService>().openAppSettingsPage(),
          ),
        );
      },
    );
  }
}

/// L13 — the OS state the app cannot otherwise see: a channel the user
/// deleted, or one they lowered to "silent". Without this row the app keeps
/// promising alerts it can no longer make loud.
class _NotificationHealthRow extends StatelessWidget {
  const _NotificationHealthRow();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Notifier? notifier = context.watch<Notifier?>();
    if (notifier == null) return const SizedBox.shrink();
    return FutureBuilder<NotifierHealth>(
      future: notifier.health(refresh: true),
      builder: (BuildContext ctx, AsyncSnapshot<NotifierHealth> snap) {
        final NotifierHealth? state = snap.data;
        if (state == null ||
            state == NotifierHealth.ok ||
            state == NotifierHealth.blocked) {
          // Blocked is the permission banner's job, above.
          return const SizedBox.shrink();
        }
        return ListTile(
              dense: true,
          key: const ValueKey<String>('notif-health'),
          leading: const Icon(Icons.volume_mute_outlined),
          title: Text(state == NotifierHealth.quiet
              ? l.notifQuietBanner
              : l.notifMissingChannelBanner),
          // MmAction, not a TextButton: a page-level text button reads as a
          // label in this app (affordance audit), and the guard says so.
          trailing: MmAction(
            dense: true,
            label: l.deviceOpenSettings,
            onPressed: () =>
                ctx.read<PermissionsService>().openAppSettingsPage(),
          ),
        );
      },
    );
  }
}

/// Whether Android will let the keep-alive keep running.
///
/// The background switch above is a preference; this is the fact that decides
/// whether the OS honours it. An OEM's battery management can stop a
/// foreground service that is still on the optimisation list, and the app could
/// not see that state, so "I get no notifications" had no answer anywhere in
/// the UI (`docs/MISSING-WORK.md` §9).
///
/// Only the problem state is drawn. Exempt is the promise holding, and
/// unavailable is a platform that cannot answer: a row for either would be a
/// line the reader can do nothing with, and the second would be a warning that
/// may be false.
class _BatteryExemptionRow extends StatefulWidget {
  const _BatteryExemptionRow({required this.enabled});

  /// Whether the reader has asked for the background link at all. With the
  /// switch off there is no promise to keep, so there is nothing to warn about.
  final bool enabled;

  @override
  State<_BatteryExemptionRow> createState() => _BatteryExemptionRowState();
}

class _BatteryExemptionRowState extends State<_BatteryExemptionRow>
    with WidgetsBindingObserver {
  /// Null until the first answer, so the row does not flash on a slow read.
  BatteryExemption? _state;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_read());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The request leaves the app for the OS page, so the answer can only have
    // changed once the reader comes back.
    if (state == AppLifecycleState.resumed) unawaited(_read());
  }

  Future<void> _read() async {
    final BatteryExemptionService? service =
        context.read<BatteryExemptionService?>();
    if (service == null) return;
    final BatteryExemption read = await service.read();
    if (!mounted) return;
    setState(() => _state = read);
  }

  Future<void> _ask() async {
    final BatteryExemptionService? service =
        context.read<BatteryExemptionService?>();
    if (service == null || _asking) return;
    setState(() => _asking = true);
    await service.request();
    if (!mounted) return;
    setState(() => _asking = false);
    // The request resolves when the OS page closes, not when the user agrees,
    // so the state is read again rather than assumed.
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (!widget.enabled || _state != BatteryExemption.optimised) {
      return const SizedBox.shrink();
    }
    return ListTile(
              dense: true,
      key: const ValueKey<String>('settings-battery-exemption'),
      leading: const Icon(Icons.battery_alert_outlined),
      title: Text(l.settingsBatteryOptimisedTitle),
      subtitle: Text(
        l.settingsBatteryOptimisedSub,
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
      trailing: MmAction(
        dense: true,
        label: l.settingsBatteryAllow,
        onPressed: _asking ? null : _ask,
      ),
    );
  }
}

/// The radio's pairing PIN: read from `DEVICE_INFO`, written with
/// `CMD_SET_DEVICE_PIN` (0x25). 0 clears it, otherwise exactly six digits.
class _RadioPinBlock extends StatefulWidget {
  const _RadioPinBlock({required this.mc});
  final MeshcoreController mc;

  @override
  State<_RadioPinBlock> createState() => _RadioPinBlockState();
}

class _RadioPinBlockState extends State<_RadioPinBlock> {
  final TextEditingController _pin = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _write(int pin, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ScaffoldMessengerState sm = ScaffoldMessenger.of(context);
    final bool ok = await widget.mc.setDevicePin(pin);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    _pin.clear();
    sm
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(done)));
  }

  Future<void> _remove() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool go = await mmConfirm(
      context,
      title: l.settingsPinRemove,
      body: l.settingsPinConfirmRemove,
      cancelLabel: l.actionCancel,
      confirmLabel: l.settingsPinRemove,
      destructive: true,
    );
    if (go && mounted) await _write(0, l.settingsPinRemoved);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int? pin = widget.mc.deviceInfo?.blePin;
    final bool ready = widget.mc.isReady && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(l.settingsPinIntro,
              style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        ListTile(
              dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.settingsPinCurrent),
          subtitle: Text(
            pin == null || pin == 0 ? l.settingsPinNone : '$pin',
            style: TextStyle(
                color: cs.onSurface, fontFamily: context.skin.type.monoFamily),
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const ValueKey<String>('device-pin'),
                controller: _pin,
                enabled: ready,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l.settingsPinHint,
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 8),
            MmAction(
              label: l.settingsPinSet,
              onPressed: !ready
                  ? null
                  : () {
                      final int? v = int.tryParse(_pin.text.trim());
                      final ScaffoldMessengerState sm =
                          ScaffoldMessenger.of(context);
                      if (v == null || v < 100000 || v > 999999) {
                        sm
                          ..clearSnackBars()
                          ..showSnackBar(
                              SnackBar(content: Text(l.settingsPinBad)));
                        return;
                      }
                      _write(v, l.settingsPinDone);
                    },
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: MmAction(
            label: l.settingsPinRemove,
            onPressed: !ready || pin == null || pin == 0 ? null : _remove,
          ),
        ),
      ],
    );
  }
}

/// The colour-photo switch, on its own so the page stays stateless.
///
/// It reads the preference once on mount and writes on every change. A
/// `FutureBuilder` would rebuild the row on each notify and lose the thumb,
/// and converting the whole settings page to a stateful widget for one switch
/// would be a bigger change than the switch.
class _PhotoColorSwitch extends StatefulWidget {
  const _PhotoColorSwitch({required this.cs, required this.l});

  final ColorScheme cs;
  final AppLocalizations l;

  @override
  State<_PhotoColorSwitch> createState() => _PhotoColorSwitchState();
}

class _PhotoColorSwitchState extends State<_PhotoColorSwitch> {
  bool _color = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    MediaPrefs.colorPhotos().then((bool v) {
      if (!mounted) return;
      setState(() {
        _color = v;
        _loaded = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
              dense: true,
      key: const ValueKey<String>('settings-photo-color'),
      title: Text(widget.l.settingsPhotoColorTitle),
      subtitle: Text(widget.l.settingsPhotoColorSub,
          style: TextStyle(color: widget.cs.onSurfaceVariant)),
      value: _color,
      // Off until the preference has been read: a thumb that jumps after the
      // first frame is worse than a moment of "off".
      onChanged: !_loaded
          ? null
          : (bool v) async {
              setState(() => _color = v);
              await MediaPrefs.setColorPhotos(v);
            },
    );
  }
}
