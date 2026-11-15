// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

/// A signal-bars glyph drawn as blocks, for the skins that draw in blocks.
///
/// DR Pop's chat rows carry a five-by-five "invader" sprite rather than an icon,
/// so a Material glyph beside them reads as a different application. This is the
/// same idea at menu size: three bars of increasing height, each a stack of
/// whole blocks, on an eight-by-seven grid so every block is the same width.
///
/// It is deliberately not an `Icon`: there is no pixel font in the tree and a
/// bitmap asset would need one file per tint.
class PixelBarsIcon extends StatelessWidget {
  const PixelBarsIcon({
    super.key,
    required this.color,
    this.size = 24,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _PixelBarsPainter(color)),
      );
}

/// The lit cells of the glyph, as `(column, rowFromBottom)` pairs.
///
/// Bars are two blocks wide with one block between them, and rise three, five
/// and seven blocks from a common baseline.
const List<(int, int, int)> _bars = <(int, int, int)>[
  (0, 0, 3),
  (3, 0, 5),
  (6, 0, 7),
];

class _PixelBarsPainter extends CustomPainter {
  const _PixelBarsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const int cols = 8;
    const int rows = 7;
    final double cw = size.width / cols;
    final double ch = size.height / rows;
    final Paint p = Paint()..color = color;
    for (final (int col, int base, int height) in _bars) {
      for (int i = 0; i < height; i++) {
        final int rowFromBottom = base + i;
        canvas.drawRect(
          Rect.fromLTWH(col * cw, size.height - (rowFromBottom + 1) * ch, cw,
              ch),
          p,
        );
        canvas.drawRect(
          Rect.fromLTWH(
              (col + 1) * cw, size.height - (rowFromBottom + 1) * ch, cw, ch),
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelBarsPainter old) => old.color != color;
}
