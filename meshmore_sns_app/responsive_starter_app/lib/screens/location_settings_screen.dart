// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../ui/mm_scaffold.dart';
import '../meshcore/auto_publish_controller.dart';
import '../meshcore/meshcore_controller.dart';
import '../perms/location_service.dart';
import '../perms/permissions_service.dart';

/// R36 — App settings → Auto-publish location.
///
/// Master toggle, periodic interval picker, smart-broadcast
/// distance picker, plus a "last published" readout so the
/// user can confirm the loop is actually firing.
class LocationSettingsScreen extends StatelessWidget {
  const LocationSettingsScreen({super.key});

  static String _intervalLabel(AppLocalizations l, int sec) {
    if (sec == 0) return l.locOff;
    if (sec < 3600) return l.locIntervalMin(sec ~/ 60);
    return l.locIntervalHour(sec ~/ 3600);
  }

  static String _movementLabel(AppLocalizations l, int m) {
    if (m == 0) return l.locOff;
    if (m < 1000) return l.locMovementM(m);
    return l.locMovementKm(m ~/ 1000);
  }

  /// R36 — auto-publish is a GPS feature: every publish needs a fix, and
  /// the periodic path runs from a timer with no UI, so it cannot ask
  /// for the permission itself (it reports a denial instead). Ask here,
  /// at the moment the user turns the feature on, so that enabling it
  /// cannot silently produce nothing. Declining leaves the switch off.
  Future<void> _toggleEnabled(
    BuildContext context,
    AutoPublishController ap,
    AppLocalizations l,
    bool value,
  ) async {
    if (!value) {
      await ap.setEnabled(false);
      return;
    }
    final PermissionsService perms = context.read<PermissionsService>();
    final PermissionResult r = await perms.requestLocation();
    if (!context.mounted) return;
    if (r != PermissionResult.granted &&
        r != PermissionResult.notApplicable) {
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
    await ap.setEnabled(true);
  }

  /// R36 — "Publish now": explain a failure instead of doing nothing.
  ///
  /// `publishNow` never prompts (the loop behind it is a timer), so with
  /// the permission denied it simply has no fix. Silently returning left
  /// the button looking broken, so report the reason it hands back.
  Future<void> _publishNow(
    BuildContext context,
    AutoPublishController ap,
    AppLocalizations l,
  ) async {
    final LocationFailure? failure = await ap.publishNow();
    if (failure == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(switch (failure) {
          LocationFailure.permissionDeniedForever =>
            l.deviceLocPermDeniedPerm,
          LocationFailure.permissionDenied => l.deviceLocPermDenied,
          _ => l.deviceRegionSuggestNoFix,
        }),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AutoPublishController ap =
        context.watch<AutoPublishController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final MeshcoreController mc = context.read<MeshcoreController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.locTitle)),
      body: MmScaffold(
        child: ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              l.locHelp,
              style: TextStyle(
                  color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
          // Master toggle.
          SwitchListTile(
            title: Text(l.locMaster),
            subtitle: Text(
              ap.enabled ? l.locMasterOn : l.locMasterOff,
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: .6)),
            ),
            secondary: Icon(
                ap.enabled ? Icons.satellite_alt : Icons.satellite,
                color: ap.enabled ? cs.primary : cs.onSurfaceVariant),
            value: ap.enabled,
            onChanged: (bool v) => _toggleEnabled(context, ap, l, v),
          ),
          const Divider(height: 1),
          // Periodic interval.
          ListTile(
            enabled: ap.enabled,
            leading: const Icon(Icons.timer_outlined),
            title: Text(l.locInterval),
            subtitle: Text(
              _intervalLabel(l, ap.intervalSec),
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: .6)),
            ),
            onTap: !ap.enabled
                ? null
                : () => _pickInterval(context, ap, l),
          ),
          // Smart-broadcast distance.
          ListTile(
            enabled: ap.enabled,
            leading: const Icon(Icons.straighten),
            title: Text(l.locMovement),
            subtitle: Text(
              _movementLabel(l, ap.minMovementMeters),
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: .6)),
            ),
            onTap: !ap.enabled
                ? null
                : () => _pickMovement(context, ap, l),
          ),
          const Divider(height: 1),
          // R62 — the 60 s self-advert beacon is a separate, opt-in
          // choice from auto-publish: it needs no GPS permission and
          // works with the master toggle off.
          Consumer<MeshcoreController>(
            builder: (BuildContext context, MeshcoreController m, _) =>
                SwitchListTile(
              secondary: const Icon(Icons.cell_tower),
              title: Text(l.locBeacon),
              subtitle: Text(
                l.locBeaconSub,
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: .6)),
              ),
              value: m.periodicAdvertEnabled,
              onChanged: (bool v) => m.setPeriodicAdvertEnabled(v),
            ),
          ),
          const Divider(height: 1),
          // "Publish now" — manual trigger so the user can verify.
          ListTile(
            leading: const Icon(Icons.upload),
            title: Text(l.locPublishNow),
            subtitle: Text(l.locPublishNowSub),
            enabled: ap.enabled && mc.isReady,
            onTap: !(ap.enabled && mc.isReady)
                ? null
                : () => _publishNow(context, ap, l),
          ),
          // Last-published readout.
          if (ap.lastPublishedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: cs.outline.withValues(alpha: .35)),
                ),
                child: Text(
                  l.locLastPublished(
                    ap.lastLat!.toStringAsFixed(5),
                    ap.lastLon!.toStringAsFixed(5),
                    _hms(ap.lastPublishedAt!),
                    ap.lastTrigger,
                  ),
                  style: TextStyle(
                      color: cs.onSurface,
                      fontFamily: 'JetBrains Mono',
                      fontSize: 12),
                ),
              ),
            ),
          // Battery transparency footer.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Text(
              l.locBatteryHint,
              style: TextStyle(
                  color: cs.onSurfaceVariant, fontSize: 11),
            ),
          ),
        ],
      ),
      ),
    );
  }

  static String _hms(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Future<void> _pickInterval(BuildContext ctx,
      AutoPublishController ap, AppLocalizations l) async {
    final int? picked = await showModalBottomSheet<int>(
      context: ctx,
      builder: (BuildContext _) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final int s in AutoPublishController.intervalOptions)
              ListTile(
                dense: true,
                leading: Icon(
                  ap.intervalSec == s
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(_intervalLabel(l, s)),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await ap.setIntervalSec(picked);
  }

  Future<void> _pickMovement(BuildContext ctx,
      AutoPublishController ap, AppLocalizations l) async {
    final int? picked = await showModalBottomSheet<int>(
      context: ctx,
      builder: (BuildContext _) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final int m
                in AutoPublishController.movementOptions)
              ListTile(
                dense: true,
                leading: Icon(
                  ap.minMovementMeters == m
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(_movementLabel(l, m)),
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await ap.setMinMovementMeters(picked);
  }
}
