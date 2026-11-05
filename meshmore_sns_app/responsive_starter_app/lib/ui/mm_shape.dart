// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/mm_skin.dart';

/// A rectangle with 45° **chamfered** (cut) corners — the NERV / HUD
/// panel signature. Used via [mmShapeBorder] from the active skin.
class MmChamferBorder extends OutlinedBorder {
  const MmChamferBorder({super.side = BorderSide.none, this.cut = 12});

  final double cut;

  @override
  MmChamferBorder copyWith({BorderSide? side, double? cut}) =>
      MmChamferBorder(side: side ?? this.side, cut: cut ?? this.cut);

  @override
  ShapeBorder scale(double t) =>
      MmChamferBorder(side: side.scale(t), cut: cut * t);

  Path _path(Rect r, double c) {
    final double k = c.clamp(0.0, math.min(r.width, r.height) / 2);
    return Path()
      ..moveTo(r.left + k, r.top)
      ..lineTo(r.right - k, r.top)
      ..lineTo(r.right, r.top + k)
      ..lineTo(r.right, r.bottom - k)
      ..lineTo(r.right - k, r.bottom)
      ..lineTo(r.left + k, r.bottom)
      ..lineTo(r.left, r.bottom - k)
      ..lineTo(r.left, r.top + k)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width), cut);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect, cut);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(getOuterPath(rect), side.toPaint());
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);
}

/// R98 — the corner a "square" skin actually draws. A hard 0 cuts the
/// border's own pixel at the corner, which at 2.6x density reads as a
/// damaged corner rather than a crisp one. 1 logical px keeps the edge
/// flat to the eye and gives the stroke somewhere to turn.
const double kSquareRadius = 1;

/// W2 — the sub-6 px radii the chrome draws on tags, dots and badges. Named so
/// the source scan can tell a deliberate small corner from a control radius
/// (6 px and above, guarded by `test/ui/square_controls_guard_test.dart`) and
/// so no screen spells a corner as a bare number.
const double kRadiusXs = 2;
const double kRadiusSm = 3;
const double kRadiusMd = 4;

/// R114 — no corner in this app is perfectly sharp.
///
/// A hairline corner is what [kSquareRadius] means: the edge stays flat to the
/// eye and the stroke still has somewhere to turn. A true zero cuts the
/// border's own pixel at the corner, which at phone densities reads as a
/// damaged corner, and it makes the "sharp" presets (SEELE, Dr Pop, RECON)
/// disagree with Studio's square controls for no reason a user can see. Every
/// border and every screen-drawn radius goes through this floor, so the rule
/// lives in one place instead of in seven skins.
double mmCornerFloor(double radius) =>
    radius < kSquareRadius ? kSquareRadius : radius;

/// The [OutlinedBorder] for a skin's [MmShape] — square, rounded, or
/// chamfered — carrying the given [side].
OutlinedBorder mmShapeBorder(MmShape shape, {required BorderSide side}) =>
    switch (shape.corner) {
      MmCorner.sharp => RoundedRectangleBorder(
          side: side,
          borderRadius: BorderRadius.circular(kSquareRadius)),
      MmCorner.rounded => RoundedRectangleBorder(
          side: side,
          borderRadius: BorderRadius.circular(mmCornerFloor(shape.cornerSize))),
      MmCorner.chamfer =>
        MmChamferBorder(side: side, cut: mmCornerFloor(shape.cornerSize)),
    };

/// R71 — the corner radius for a *control or card surface* that a screen
/// draws itself (a `Material`/`Container` with a hard-coded
/// `BorderRadius.circular`). [kSquareRadius] when the active skin sets
/// [MmShape.squareControls] (Studio, R98), [radius] otherwise so the six
/// older presets keep their exact rounding, and never below the
/// [mmCornerFloor] hairline. Screens must use this instead of a literal
/// radius; `test/ui/square_controls_guard_test.dart` fails the build when one
/// reappears.
BorderRadius mmRadius(BuildContext context, double radius) =>
    context.skin.shape.squareControls
        ? BorderRadius.circular(kSquareRadius)
        : BorderRadius.circular(mmCornerFloor(radius));
