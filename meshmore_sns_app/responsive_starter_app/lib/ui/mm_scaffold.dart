// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/mm_skin.dart';
import '../theme/theme_controller.dart';
import 'mm_scroll_edge.dart';

/// Per-screen chrome wrapper. Paints the skin's base ground and overlays
/// its retro-futuristic ornament (CRT scanlines + corner brackets) once,
/// so every screen built on it inherits the look. Ornament is suppressed
/// under **reduce-motion** (UX-brief R13 parity rule).
///
/// It also owns the page's bottom edge ([MmScrollEdge]): one line at the
/// bottom of the body says whether the page continues and how far down the
/// reader is. A screen opts out with [bottomEdge] false when its own bottom
/// edge is a control — a composer, a docked action bar, a canvas whose
/// controls reach the edge — because a rule over a control is a rule over the
/// thing the reader came to press.
class MmScaffold extends StatelessWidget {
  const MmScaffold({
    super.key,
    required this.child,
    this.padding,
    this.bottomEdge = true,
    this.closingRule = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Whether the bottom edge line is drawn at all.
  final bool bottomEdge;

  /// Whether a body with no scrollable gets the solid closing rule instead of
  /// nothing. See [MmScrollEdge.closing].
  final bool closingRule;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    bool reduceMotion = false;
    try {
      reduceMotion = context.watch<ThemeController>().reduceMotion;
    } on ProviderNotFoundException {
      // No ThemeController above us (isolated test) — assume motion ok.
    }
    final Widget inner = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    final bool ornament = skin.ornament.any && !reduceMotion;
    final Widget framed = bottomEdge
        ? MmScrollEdge(closing: closingRule, child: inner)
        : inner;
    // The app draws edge to edge, because Android 15 and later enforce it for a
    // targetSdk of 35 and above, and this app targets 36. So the body's own
    // bottom edge is the device's navigation area, and the Scaffold does not
    // lift the body clear of it: its `minInsets.bottom` is the keyboard, not the
    // system bar, so a Scaffold with no bottomNavigationBar places the body at
    // the physical bottom. The bar's own height is 24 dp on a gesture phone and
    // 48 dp on a three-button one, so the number is read and never written.
    //
    // The inset is applied here and then consumed, so a SafeArea below us adds
    // nothing and the composer screens do not end up 24 dp short twice. The
    // ColoredBox stays outside the padding, so the skin's ground still fills the
    // whole screen and the strip below the body reads as ground, not as a gap.
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final Widget body = Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: framed,
      ),
    );
    return ColoredBox(
      color: skin.color.base,
      // The ground is painted by ColoredBox, not by a Material. Any
      // ListTile or InkWell below us then has no ink surface: the tap
      // ripple is invisible and debug builds report ("ListTile background
      // color or ink splashes may be invisible"). A transparent Material
      // supplies the surface without painting a second ground or
      // overriding the skin's text styles.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: body),
            if (ornament)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: SkinChromePainter(
                      scanlineOpacity: skin.ornament.scanlineOpacity,
                      brackets: skin.ornament.cornerBrackets,
                      accent: skin.color.accent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Draws CRT scanlines (faint dark horizontal rules) and NERV-style L
/// corner brackets. Static (no per-frame animation) so it never forces
/// a repaint.
class SkinChromePainter extends CustomPainter {
  const SkinChromePainter({
    required this.scanlineOpacity,
    required this.brackets,
    required this.accent,
  });

  final double scanlineOpacity;
  final bool brackets;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (scanlineOpacity > 0) {
      final Paint p = Paint()
        ..color = const Color(0xFF000000).withValues(alpha: scanlineOpacity)
        ..strokeWidth = 1;
      for (double y = 0; y < size.height; y += 3) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      }
    }
    if (brackets) {
      const double len = 18, m = 6;
      final Paint p = Paint()
        ..color = accent.withValues(alpha: .8)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final double w = size.width, h = size.height;
      canvas.drawPath(
          Path()
            ..moveTo(m, m + len)
            ..lineTo(m, m)
            ..lineTo(m + len, m),
          p);
      canvas.drawPath(
          Path()
            ..moveTo(w - m - len, m)
            ..lineTo(w - m, m)
            ..lineTo(w - m, m + len),
          p);
      canvas.drawPath(
          Path()
            ..moveTo(m, h - m - len)
            ..lineTo(m, h - m)
            ..lineTo(m + len, h - m),
          p);
      canvas.drawPath(
          Path()
            ..moveTo(w - m - len, h - m)
            ..lineTo(w - m, h - m)
            ..lineTo(w - m, h - m - len),
          p);
    }
  }

  @override
  bool shouldRepaint(SkinChromePainter old) =>
      old.scanlineOpacity != scanlineOpacity ||
      old.brackets != brackets ||
      old.accent != accent;
}
