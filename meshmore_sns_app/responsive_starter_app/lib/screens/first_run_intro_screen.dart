// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/demo_mode.dart';
import '../gen/app_localizations.dart';
import '../meshcore/meshcore_controller.dart';
import '../perms/first_run_controller.dart';
import '../perms/permissions_service.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_shape.dart';

/// R21 / U12 — first-run permissions intro. Explains *why* the app
/// asks for Bluetooth and notifications, sets the offline-first
/// expectation, and gives the user two clearly-labelled paths:
///
/// 1. **Grant Bluetooth & continue** — the recommended path. Proactively
///    requests the BLE permission set. We deliberately **do not** ask
///    for notifications here; that prompt only fires the first time the
///    user enables "Stay connected in background" (R17 toggle).
/// 2. **Continue offline (skip permissions)** — fully supported. The
///    app still browses message history, themes, channel settings, and
///    diagnostics. Any action that actually needs the radio (Scan,
///    Connect, Send) will surface a per-action prompt later.
///
/// Either path marks first-run as done; the intro never reappears.
class FirstRunIntroScreen extends StatefulWidget {
  const FirstRunIntroScreen({super.key});

  @override
  State<FirstRunIntroScreen> createState() => _FirstRunIntroScreenState();
}

class _FirstRunIntroScreenState extends State<FirstRunIntroScreen> {
  bool _busy = false;
  String? _denialNote;

  Future<void> _grantAndContinue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _denialNote = null;
    });
    final PermissionsService perms = context.read<PermissionsService>();
    final FirstRunController fr = context.read<FirstRunController>();
    final PermissionResult r = await perms.requestBle();
    if (!mounted) return;
    if (r == PermissionResult.granted ||
        r == PermissionResult.notApplicable) {
      await fr.markDone();
      return;
    }
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _denialNote = r == PermissionResult.permanentlyDenied
          ? l.firstRunDeniedPermanent
          : l.firstRunDeniedTransient;
    });
  }

  /// The offline path is demo mode by name: it records the choice so the next
  /// launch does not reach for a radio either, and so the shell can say why
  /// the fabric is empty. A radio that answered the auto-connect before this
  /// tap is dropped, because a demo that keeps a live link is not radio-free.
  Future<void> _continueOffline() async {
    if (_busy) return;
    setState(() => _busy = true);
    final DemoMode demo = context.read<DemoMode>();
    final FirstRunController fr = context.read<FirstRunController>();
    final MeshcoreController mc = context.read<MeshcoreController>();
    await demo.setEnabled(true, onEnabled: () => mc.disconnect());
    await fr.markDone();
  }

  Future<void> _openSettings() async {
    await context.read<PermissionsService>().openAppSettingsPage();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final ColorScheme cs = th.colorScheme;
    return Scaffold(
      body: SafeArea(
        // The page scrolls. It is three paragraph blocks and two full-width
        // buttons on a screen with no app bar and no other route out, and at
        // 320 dp with 200 % text the column overflowed by 2120 px: a new user
        // with large text could not reach "Allow Bluetooth" at all.
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
              horizontal: context.skin.space.sectionGap,
              vertical: context.skin.space.emptyState),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Builder(builder: (BuildContext ctx) {
                final AppLocalizations l = AppLocalizations.of(ctx);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l.firstRunHeader,
                        style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: context.skin.type.sizeBody,
                            letterSpacing: context.skin.type.headingTracking)),
                    SizedBox(height: context.skin.space.screenEdge),
                    Text(
                      l.firstRunTitle,
                      style: th.textTheme.headlineSmall,
                    ),
                    SizedBox(height: context.skin.space.sectionGap),
                    _PermBlock(
                      icon: Icons.bluetooth_searching,
                      title: l.firstRunBleTitle,
                      body: l.firstRunBleBody,
                    ),
                    SizedBox(height: context.skin.space.rowInset),
                    _PermBlock(
                      icon: Icons.notifications_active_outlined,
                      title: l.firstRunNotificationsTitle,
                      body: l.firstRunNotificationsBody,
                    ),
                    SizedBox(height: context.skin.space.rowInset),
                    _PermBlock(
                      icon: Icons.cloud_off,
                      title: l.firstRunOfflineTitle,
                      body: l.firstRunOfflineBody,
                    ),
                  ],
                );
              }),
              // A spacer has no meaning inside a scroll view; the button
              // group is separated by the ladder's group gap instead.
              SizedBox(height: context.skin.space.emptyState),
              if (_denialNote != null) ...<Widget>[
                Container(
                  padding: EdgeInsets.all(context.skin.space.rowInset),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: mmRadius(context, kRadiusSm),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.info_outline,
                          color: cs.onErrorContainer, size: 18),
                      SizedBox(width: context.skin.space.rowGap),
                      Expanded(
                        child: Text(
                          _denialNote!,
                          style: TextStyle(color: cs.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: context.skin.space.rowGap),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(AppLocalizations.of(context).firstRunOpenSettings),
                  ),
                ),
                SizedBox(height: context.skin.space.labelToControl),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _grantAndContinue,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(AppLocalizations.of(context).firstRunGrant),
                ),
              ),
              SizedBox(height: context.skin.space.rowGap),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _continueOffline,
                  icon: const Icon(Icons.cloud_off),
                  label: Text(AppLocalizations.of(context).firstRunSkip),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermBlock extends StatelessWidget {
  const _PermBlock({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: mmRadius(context, 8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: cs.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(body,
                  style: TextStyle(
                      color: cs.onSurfaceVariant, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}
