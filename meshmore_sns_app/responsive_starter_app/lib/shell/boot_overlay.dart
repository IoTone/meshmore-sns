// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/meshcore_controller.dart';
import 'package:meshcore/meshcore.dart';

import 'boot_surface.dart';

/// Boot-time busy overlay (R8 polish). On a cold launch the
/// BLE auto-connect → APP_START → SELF_INFO → drain chain typically
/// takes 3–8 s, during which the Dashboard renders blank-ish and
/// feels unresponsive. The overlay covers that gap with a branded
/// NERV-style "synchronising" screen that:
///
/// - Shows only on the first reach to `ready` (this session). Once
///   the controller reaches `ready` we fade out and never show
///   again — later disconnects/reconnects use the regular status
///   slab, not the overlay.
/// - Stops its own animations during the fade so widget-test
///   `pumpAndSettle` actually settles.
/// - Is drawn in the reader's own theme.
///
/// **The palette decision, revised.** This screen used to boot in the NERV
/// orange-and-lime palette whatever preset the reader had chosen, on the theory
/// that a launch is a brand moment, with Studio exempted because its owner asked
/// for no hue anywhere. That made the most-seen screen in the app the one screen
/// that did not belong to the theme it was starting: a reader on Daybreak saw a
/// black-and-orange console and then a white page, and the two had nothing in
/// common. Every preset boots in its own colours now, and what makes a launch
/// recognisable is the geometry, which is the same in all eleven: four corner
/// brackets, one hexagonal dial, the name at the top left, the status above the
/// navigation area, SKIP at the bottom right.
///
/// The consequence worth stating: the overlay's ground is the skin's own `base`,
/// the same colour the screen behind it paints, so the fade into the dashboard is
/// a change of content rather than a change of theme.
/// - Honours `Skip` so anyone in an offline session isn't blocked.
class BootOverlay extends StatefulWidget {
  const BootOverlay({super.key, required this.child});

  /// The shell content rendered behind the overlay.
  final Widget child;

  @override
  State<BootOverlay> createState() => _BootOverlayState();
}

class _BootOverlayState extends State<BootOverlay>
    with TickerProviderStateMixin {
  /// Live AnimationController, repeats while overlay is visible.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1.0, // start visible
  );

  /// True once we've finished the dismiss animation. From then on
  /// the overlay's Builder returns the child directly with zero
  /// overhead — and the Stack stops layering anything above.
  bool _dismissed = false;

  /// True once the user tapped SKIP (latches; we don't re-show on
  /// later reconnects in the same session anyway, but this is the
  /// signal "they actively asked me to leave").
  bool _skipped = false;

  /// How long the overlay may sit on a launch that has not settled.
  ///
  /// The overlay exists to cover the app while the radio link comes up, and the
  /// reconnect ladder is allowed to run for about two and a half minutes. That
  /// is a fine rule for a background retry and a bad one for a launch screen:
  /// measured on the handset with a paired radio that was out of range, the
  /// whole app sat behind a spinner and the only way through was a SKIP button.
  /// The app is offline-first, so after this the dashboard takes over and its
  /// own slab says what the link is doing.
  static const Duration _patience = Duration(seconds: 8);

  Timer? _patienceTimer;

  @override
  void initState() {
    super.initState();
    _patienceTimer = Timer(_patience, () {
      if (mounted) _beginFadeOut();
    });
  }

  @override
  void dispose() {
    _patienceTimer?.cancel();
    _spin.dispose();
    _fade.dispose();
    super.dispose();
  }

  Future<void> _beginFadeOut() async {
    if (_dismissed) return;
    _spin.stop();
    await _fade.animateTo(0, curve: Curves.easeOut);
    if (mounted) setState(() => _dismissed = true);
  }

  void _onSkip() {
    setState(() => _skipped = true);
    _beginFadeOut();
  }

  @override
  Widget build(BuildContext context) {
    // R68: the child must stay at Stack index 0 before AND after the
    // overlay is dismissed. It used to be returned bare once dismissed,
    // which changed the parent's shape (Stack -> child), so Flutter
    // unmounted the whole shell and built a second one: every screen's
    // State was created twice at launch, once under the overlay and once
    // after it. Keeping a one-child Stack reuses the element.
    if (_dismissed) return Stack(children: <Widget>[widget.child]);

    final MeshcoreController mc = context.watch<MeshcoreController>();
    final bool ready = mc.state == MeshcoreConnectionState.ready;

    // "Nothing in flight": disconnected, not attempting a connect,
    // and no paired device → there is no boot work to wait for, so
    // the overlay is just covering empty UI. Dismiss now. This also
    // makes the offline-first launch path (no radio paired yet) read
    // as a normal Dashboard from the first frame.
    final bool quiescent =
        mc.state == MeshcoreConnectionState.disconnected &&
            !mc.isConnecting &&
            !mc.hasPairedDevice;

    // **A radio that is paired and unreachable is not boot work.** Measured on
    // the handset: the overlay sat on top of a perfectly usable app for the
    // whole reconnect ladder (about two and a half minutes) because the state
    // it waits for never arrives, and once the ladder gave up it sat there
    // still, with only SKIP as the way through. The dashboard already has a slab
    // that says LINK LOST and offers Retry, and the stored chats, places and
    // maps do not need a radio, so the moment an attempt has failed the overlay
    // gets out of the way.
    final bool linkSettled = mc.state == MeshcoreConnectionState.failed ||
        mc.gaveUp;

    if ((ready || quiescent || linkSettled) &&
        !_skipped &&
        _fade.value > 0 &&
        !_fade.isAnimating) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _beginFadeOut());
    }

    final AppLocalizations l = AppLocalizations.of(context);
    final String status = switch (mc.state) {
      MeshcoreConnectionState.ready => l.bootReady,
      MeshcoreConnectionState.handshaking => l.bootHandshaking,
      MeshcoreConnectionState.reconnecting => l.bootHandshaking,
      MeshcoreConnectionState.failed => l.bootOffline,
      MeshcoreConnectionState.disconnected => mc.isConnecting
          ? l.bootConnecting
          : l.bootOffline,
    };

    // The surface owns its own colours (see `MmBootSurface`), so this overlay
    // only decides *when* a launch screen is needed and *what it says*.
    return Stack(
      children: <Widget>[
        widget.child,
        IgnorePointer(
          ignoring: _dismissed || _fade.value == 0,
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _fade,
              curve: Curves.easeInOut,
            ),
            child: MmBootSurface(
              dial: _spin,
              name: l.bootHeader,
              subtitle: l.bootSubtitle,
              status: status,
              skipLabel: l.bootSkip,
              onSkip: _onSkip,
            ),
          ),
        ),
      ],
    );
  }
}

