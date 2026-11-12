// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/meshcore_controller.dart';
import '../theme/mm_skin.dart';
import '../theme/mm_tokens.dart';
import '../ui/mm_components.dart';
import 'package:meshcore/meshcore.dart';

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
/// - Uses the NERV palette regardless of the user's chosen preset (a
///   brand moment) -- except **Studio** (R68), whose owner asked for no
///   hue anywhere: it boots in Studio's own greys.
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
  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _bgDeep = Color(0xFF000000);
  static const Color _accent = Color(0xFFFF7A00); // NERV orange
  static const Color _alt = Color(0xFF9CFF00); // NERV ok-green
  static const Color _fg = Color(0xFFE6ECF5);

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

    // R68: Studio is monochrome, so its boot surface must not flash the
    // NERV orange/lime. Every other preset keeps the brand palette.
    final MmSkin skin = context.skin;
    final bool studio = skin.preset == MmThemePreset.studio;
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
            child: _BootSurface(
              spin: _spin,
              accent: studio ? skin.color.accent : _accent,
              alt: studio ? skin.color.fgMuted : _alt,
              fg: studio ? skin.color.fg : _fg,
              bg: studio ? skin.color.surface : _bg,
              bgDeep: studio ? skin.color.base : _bgDeep,
              header: l.bootHeader,
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

class _BootSurface extends StatelessWidget {
  const _BootSurface({
    required this.spin,
    required this.accent,
    required this.alt,
    required this.fg,
    required this.bg,
    required this.bgDeep,
    required this.header,
    required this.subtitle,
    required this.status,
    required this.skipLabel,
    required this.onSkip,
  });

  final AnimationController spin;
  final Color accent;
  final Color alt;
  final Color fg;
  final Color bg;
  final Color bgDeep;
  final String header;
  final String subtitle;
  final String status;
  final String skipLabel;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgDeep,
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[bg, bgDeep],
            ),
          ),
          child: Stack(
            children: <Widget>[
              // Corner brackets (NERV-style frame).
              Positioned.fill(
                child: CustomPaint(
                  painter: _CornerBracketsPainter(accent),
                ),
              ),
              // Top header strip. Both labels are letter-spaced monospace, and
              // between them they are wider than a phone at 1.3 text: measured
              // on the handset at 432 dp, two `Flexible`s sharing the row split
              // it evenly and the boot screen's own name read
              // "MESHMORE / SY…" — the first thing a launch shows, cut.
              //
              // So the pair is measured with the real painter: on one line at
              // the two edges while both fit, and one above the other (header
              // at the start, subtitle under it at the end) when they do not.
              // Nothing is ellipsised, because a clipped name is not a name.
              Positioned(
                top: 24,
                left: 24,
                right: 24,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    final TextStyle headStyle = TextStyle(
                        color: accent,
                        fontFamily: context.skin.type.wordsMono,
                        fontSize: 11,
                        letterSpacing: 4);
                    final TextStyle subStyle = TextStyle(
                        color: alt,
                        fontFamily: context.skin.type.wordsMono,
                        fontSize: 11,
                        letterSpacing: 4);
                    final bool oneLine = mmPairFitsOneLine(
                      context,
                      a: header,
                      aStyle: headStyle,
                      b: subtitle,
                      bStyle: subStyle,
                      gap: 12,
                      width: c.maxWidth,
                    );
                    final Widget head = Text(header, style: headStyle);
                    final Widget sub = Text(subtitle,
                        textAlign: TextAlign.end, style: subStyle);
                    if (oneLine) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[head, sub],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        head,
                        const SizedBox(height: 6),
                        Align(alignment: Alignment.centerRight, child: sub),
                      ],
                    );
                  },
                ),
              ),
              // Centre spinner.
              Center(
                child: AnimatedBuilder(
                  animation: spin,
                  builder: (BuildContext _, Widget? __) {
                    return CustomPaint(
                      size: const Size(240, 240),
                      painter: _NervSpinnerPainter(
                        accent: accent,
                        alt: alt,
                        t: spin.value,
                      ),
                    );
                  },
                ),
              ),
              // Status text below centre.
              Positioned(
                left: 0,
                right: 0,
                bottom: 96,
                child: Center(
                  child: Text(
                    status,
                    style: TextStyle(
                        color: fg,
                        fontFamily: context.skin.type.wordsMono,
                        fontSize: 14,
                        letterSpacing: 3),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              // Skip in bottom-right.
              Positioned(
                right: 16,
                bottom: 16,
                child: TextButton(
                  onPressed: onSkip,
                  child: Text(skipLabel,
                      style: TextStyle(
                          color: alt,
                          fontFamily: context.skin.type.wordsMono,
                          fontSize: 12,
                          letterSpacing: 3)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four small "L" brackets in each corner — the NERV frame look.
class _CornerBracketsPainter extends CustomPainter {
  _CornerBracketsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: .85);
    const double arm = 28;
    const double inset = 14;
    // TL
    canvas.drawPath(
      Path()
        ..moveTo(inset, inset + arm)
        ..lineTo(inset, inset)
        ..lineTo(inset + arm, inset),
      p,
    );
    // TR
    canvas.drawPath(
      Path()
        ..moveTo(size.width - inset - arm, inset)
        ..lineTo(size.width - inset, inset)
        ..lineTo(size.width - inset, inset + arm),
      p,
    );
    // BR
    canvas.drawPath(
      Path()
        ..moveTo(size.width - inset, size.height - inset - arm)
        ..lineTo(size.width - inset, size.height - inset)
        ..lineTo(size.width - inset - arm, size.height - inset),
      p,
    );
    // BL
    canvas.drawPath(
      Path()
        ..moveTo(inset + arm, size.height - inset)
        ..lineTo(inset, size.height - inset)
        ..lineTo(inset, size.height - inset - arm),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _CornerBracketsPainter old) =>
      old.color != color;
}

/// Centre spinner — concentric rotating chevrons + a steady hex
/// outline + an alt-colour pulse at 12 o'clock. Deliberately
/// hand-drawn to evoke NERV/EVA HUDs without using copyrighted
/// assets.
class _NervSpinnerPainter extends CustomPainter {
  _NervSpinnerPainter({
    required this.accent,
    required this.alt,
    required this.t,
  });
  final Color accent;
  final Color alt;
  final double t; // 0..1 repeating

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = math.min(size.width, size.height) / 2 - 4;

    // Static hex outline.
    final Path hex = Path();
    for (int i = 0; i < 6; i++) {
      final double a = i * math.pi / 3 + math.pi / 6;
      final Offset p =
          c + Offset(r * math.cos(a), r * math.sin(a));
      if (i == 0) {
        hex.moveTo(p.dx, p.dy);
      } else {
        hex.lineTo(p.dx, p.dy);
      }
    }
    hex.close();
    canvas.drawPath(
      hex,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent.withValues(alpha: .55),
    );

    // Rotating chevron ring (clockwise, full revolution = 4 s).
    final double angle = t * 2 * math.pi;
    for (int i = 0; i < 8; i++) {
      final double a = angle + i * math.pi / 4;
      final double inset = i.isEven ? r - 12 : r - 22;
      final Offset cTip =
          c + Offset(inset * math.cos(a), inset * math.sin(a));
      final Offset cWingA = c +
          Offset(
            (inset - 8) * math.cos(a + 0.18),
            (inset - 8) * math.sin(a + 0.18),
          );
      final Offset cWingB = c +
          Offset(
            (inset - 8) * math.cos(a - 0.18),
            (inset - 8) * math.sin(a - 0.18),
          );
      final Paint pp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color =
            accent.withValues(alpha: i.isEven ? 0.85 : 0.35);
      canvas.drawPath(
        Path()
          ..moveTo(cWingA.dx, cWingA.dy)
          ..lineTo(cTip.dx, cTip.dy)
          ..lineTo(cWingB.dx, cWingB.dy),
        pp,
      );
    }

    // Inner crosshair + dot.
    final Paint cross = Paint()
      ..color = accent.withValues(alpha: .9)
      ..strokeWidth = 1.4;
    canvas.drawLine(c.translate(-12, 0), c.translate(12, 0), cross);
    canvas.drawLine(c.translate(0, -12), c.translate(0, 12), cross);
    canvas.drawCircle(c, 4, Paint()..color = accent);

    // Alt-colour 12-o'clock pulse — green dot that breathes.
    final double pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    canvas.drawCircle(
      c.translate(0, -r),
      4 + 2 * pulse,
      Paint()..color = alt.withValues(alpha: 0.55 + 0.45 * pulse),
    );
  }

  @override
  bool shouldRepaint(covariant _NervSpinnerPainter old) =>
      old.t != t;
}
