// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';

/// The one design every launch screen in this app wears.
///
/// There used to be two. A cold launch showed `BrandedSplashScreen` — logo,
/// name, tagline and version, centred, in Material's own colours — for a fixed
/// two and a bit seconds while preferences loaded, and then threw it away for
/// `BootOverlay`, which is corner brackets and a hexagonal dial in the theme's
/// own palette, and waited up to eight seconds for the radio. Two loading
/// screens with different geometry, different type and different wording, one
/// after the other, is what "the loading screen does not work properly" looks
/// like from the outside.
///
/// This is that screen, once: four corner brackets, one dial, the app's name at
/// the top left, what it is doing above the navigation area, and SKIP at the
/// bottom right when there is something to skip. Every colour is read from the
/// skin here rather than passed in, so no caller can launch in a palette the
/// reader did not choose.
class MmBootSurface extends StatelessWidget {
  const MmBootSurface({
    super.key,
    required this.dial,
    required this.name,
    required this.subtitle,
    required this.status,
    this.skipLabel,
    this.onSkip,
  });

  /// The dial's rotation, 0 to 1, repeating. Owned by the caller so this widget
  /// stays stateless and a test can hold it still.
  final Animation<double> dial;

  /// The app's name, top left.
  final String name;

  /// The name's companion, top right.
  final String subtitle;

  /// What the app is doing right now, above the navigation area.
  final String status;

  /// The way out, when there is one. The prefs gate has nothing to skip; the
  /// radio wait does.
  final String? skipLabel;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    // Every colour is read here, from the skin, rather than passed in: the whole
    // point of this widget is that a launch looks like the theme the reader
    // chose, and a caller that can pass a palette is a caller that can break
    // that. Text is the ink tiers the theme tests already hold to 4.5:1 on
    // `base`; the accent is spent on the graphics, where the bar is 3:1.
    final MmSkin skin = context.skin;
    final Color accent = skin.color.accent;
    final Color alt = skin.color.ok;
    final Color fg = skin.color.fg;
    final Color muted = skin.color.fgMuted;
    final Color bg = skin.color.surface;
    final Color bgDeep = skin.color.base;
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
                    final MmType type = context.skin.type;
                    final TextStyle headStyle = TextStyle(
                        color: fg,
                        fontFamily: type.wordsMono,
                        fontSize: type.sizeSm,
                        letterSpacing: 4);
                    final TextStyle subStyle = TextStyle(
                        color: muted,
                        fontFamily: type.wordsMono,
                        fontSize: type.sizeSm,
                        letterSpacing: 4);
                    final bool oneLine = mmPairFitsOneLine(
                      context,
                      a: name,
                      aStyle: headStyle,
                      b: subtitle,
                      bStyle: subStyle,
                      gap: 12,
                      width: c.maxWidth,
                    );
                    final Widget head = Text(name, style: headStyle);
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
                  animation: dial,
                  builder: (BuildContext _, Widget? __) {
                    return CustomPaint(
                      size: const Size(240, 240),
                      painter: _BootDialPainter(
                        accent: accent,
                        alt: alt,
                        t: dial.value,
                      ),
                    );
                  },
                ),
              ),
              // Status text below centre, above the navigation area: the
              // overlay is full-bleed and is not inside `MmScaffold`, so its
              // literals are clearance from the glass, not from the bar.
              Positioned(
                left: 0,
                right: 0,
                bottom: 96 + MediaQuery.paddingOf(context).bottom,
                child: Center(
                  child: Text(
                    status,
                    style: TextStyle(
                        color: fg,
                        fontFamily: context.skin.type.wordsMono,
                        fontSize: context.skin.type.sizeBodyLg,
                        letterSpacing: 3),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              // Skip in bottom-right, when the caller has something to skip.
              if (skipLabel != null && onSkip != null)
              Positioned(
                right: 16,
                bottom: 16 + MediaQuery.paddingOf(context).bottom,
                // A control, not a caption: it is the only way out of a launch
                // that has not settled, so it wears an action's ink rather than
                // the accent that means "this is going well".
                child: MmAction(
                  key: const ValueKey<String>('boot-skip'),
                  label: skipLabel!,
                  dense: true,
                  onPressed: onSkip,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four small "L" brackets in each corner: the frame that makes a launch
/// recognisable in every theme.
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

/// Centre dial: concentric rotating chevrons, a steady hexagon, and a pulse at
/// twelve o'clock. Hand-drawn, so no asset has to be shipped in eleven colours
/// and none of it depends on a font.
class _BootDialPainter extends CustomPainter {
  _BootDialPainter({
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
  bool shouldRepaint(covariant _BootDialPainter old) =>
      old.t != t;
}
