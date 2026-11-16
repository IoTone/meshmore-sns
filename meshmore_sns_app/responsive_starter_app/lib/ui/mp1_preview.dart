// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../media/mp1.dart';
import '../media/media_photo.dart';

/// A received MP1 preview, drawn as the palette grid it is.
///
/// No image codec is involved, which is the point: a preview is 24x24 palette
/// indices, so painting them is 576 rectangles and costs nothing on the frame
/// that shows it. Decoding it into a picture first would be work for a picture
/// the reader has not asked for yet.
class Mp1PreviewImage extends StatelessWidget {
  const Mp1PreviewImage({
    super.key,
    required this.image,
    this.size = 56,
    this.color = true,
  });

  final Mp1Image image;
  final double size;

  /// Colour, or the palette in Rec. 601 luma.
  ///
  /// Photos are grey unless the reader asked for colour (Settings → Chat &
  /// photos), and a
  /// preview is a photo: the choice is about what a picture costs on the mesh,
  /// and it applies to every picture the app shows. The luma weights are
  /// [MediaPhoto.inGrayscale]'s, so a preview and a fetched picture of the same
  /// scene grey the same way.
  final bool color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _Mp1Painter(image, color: color)),
    );
  }
}

/// A decoded picture as a thumbnail.
///
/// Raw RGBA, painted by nearest-neighbour: the source is already small (320x240
/// at most) and a filter would cost more than the picture is worth in a strip.
class RgbaThumbnail extends StatelessWidget {
  const RgbaThumbnail({super.key, required this.photo, this.size = 56});

  final MediaPhoto photo;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _RgbaPainter(photo)),
      );
}

/// Rec. 601 luma, the weights a phone camera's own luma uses.
int _luma(int r, int g, int b) =>
    (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);

class _RgbaPainter extends CustomPainter {
  _RgbaPainter(this.photo);

  final MediaPhoto photo;

  @override
  void paint(Canvas canvas, Size size) {
    // One row per scanline, drawn from a 1-pixel-wide strip of the source: the
    // cheapest way to scale RGBA without an image codec.
    final double px = size.width / photo.width;
    final double py = size.height / photo.height;
    for (int y = 0; y < photo.height; y++) {
      for (int x = 0; x < photo.width; x++) {
        final int i = (y * photo.width + x) * 4;
        final Paint p = Paint()
          ..color = Color.fromARGB(
              photo.rgba[i + 3], photo.rgba[i], photo.rgba[i + 1], photo.rgba[i + 2]);
        canvas.drawRect(
            Rect.fromLTWH(x * px, y * py, px + 0.5, py + 0.5), p);
      }
    }
  }

  @override
  bool shouldRepaint(_RgbaPainter old) => old.photo != photo;
}

class _Mp1Painter extends CustomPainter {
  _Mp1Painter(this.image, {this.color = true});

  final Mp1Image image;
  final bool color;

  @override
  void paint(Canvas canvas, Size size) {
    final double px = size.width / image.width;
    final double py = size.height / image.height;
    final Paint paint = Paint()..isAntiAlias = false;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final int idx = image.indices[y * image.width + x];
        final Mp1Colour c = image.palette.colours[idx.clamp(0, image.palette.colours.length - 1)];
        paint.color = color
            ? Color.fromARGB(0xFF, c.r, c.g, c.b)
            : Color.fromARGB(0xFF, _luma(c.r, c.g, c.b), _luma(c.r, c.g, c.b),
                _luma(c.r, c.g, c.b));
        canvas.drawRect(
          Rect.fromLTWH(x * px, y * py, px + 0.5, py + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Mp1Painter old) =>
      old.image != image || old.color != color;
}
