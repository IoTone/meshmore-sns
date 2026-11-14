// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../media/mp1.dart';

/// A received MP1 preview, drawn as the palette grid it is.
///
/// No image codec is involved, which is the point: a preview is 24x24 palette
/// indices, so painting them is 576 rectangles and costs nothing on the frame
/// that shows it. Decoding it into a picture first would be work for a picture
/// the reader has not asked for yet.
class Mp1PreviewImage extends StatelessWidget {
  const Mp1PreviewImage({super.key, required this.image, this.size = 56});

  final Mp1Image image;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _Mp1Painter(image)),
    );
  }
}

class _Mp1Painter extends CustomPainter {
  _Mp1Painter(this.image);

  final Mp1Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final double px = size.width / image.width;
    final double py = size.height / image.height;
    final Paint paint = Paint()..isAntiAlias = false;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final int idx = image.indices[y * image.width + x];
        final Mp1Colour c = image.palette.colours[idx.clamp(0, image.palette.colours.length - 1)];
        paint.color = Color.fromARGB(0xFF, c.r, c.g, c.b);
        canvas.drawRect(
          Rect.fromLTWH(x * px, y * py, px + 0.5, py + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Mp1Painter old) => old.image != image;
}
