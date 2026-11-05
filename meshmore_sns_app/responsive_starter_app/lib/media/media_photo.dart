// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';

/// One picture as the app holds it: straight (non-premultiplied) RGBA8, row
/// major, `width * height * 4` bytes.
///
/// Straight alpha is the encoder's input and the decoder's default output, so
/// the value type carries the one form both directions agree on. A renderer
/// that wants premultiplied pixels converts at the display boundary with
/// [premultiplied], which keeps the conversion in one place instead of in
/// every caller.
@immutable
final class MediaPhoto {
  const MediaPhoto({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;

  /// The size every picture is fitted to before it is encoded.
  ///
  /// A container carries 200–350 bytes of overhead before the first pixel, so
  /// a mesh photo only works at the low-bitrate end: 320×240 is what a 2–4 KB
  /// channel budget actually affords. Anything larger is downscaled, never
  /// refused for being large — "your photo is too big" is a worse answer than
  /// a smaller photo.
  static const int floorWidth = 320;
  static const int floorHeight = 240;

  bool get withinFloor => width <= floorWidth && height <= floorHeight;

  bool get isWellFormed =>
      width > 0 && height > 0 && rgba.length == width * height * 4;

  /// The picture fitted inside [floorWidth] × [floorHeight], aspect preserved.
  ///
  /// Downscale only: a picture already inside the floor comes back unchanged,
  /// and nothing is upscaled, because upscaling spends bytes to add no detail.
  MediaPhoto fittedToFloor() =>
      scaledTo(maxWidth: floorWidth, maxHeight: floorHeight);

  /// A box-filtered downscale to fit inside the given bounds.
  ///
  /// Each destination pixel averages the source pixels it covers, which is the
  /// cheapest filter that does not alias text and edges into noise. Nearest
  /// neighbour is rejected on purpose: a 320×240 photo of a sign has to stay
  /// legible, and nearest sampling turns a large photo into a checkerboard.
  MediaPhoto scaledTo({required int maxWidth, required int maxHeight}) {
    if (!isWellFormed) {
      throw ArgumentError.value(<int>[width, height, rgba.length], 'rgba',
          'not a whole picture');
    }
    if (width <= maxWidth && height <= maxHeight) return this;
    final double scale = width / maxWidth > height / maxHeight
        ? maxWidth / width
        : maxHeight / height;
    final int outWidth = (width * scale).round().clamp(1, maxWidth);
    final int outHeight = (height * scale).round().clamp(1, maxHeight);
    final Uint8List out = Uint8List(outWidth * outHeight * 4);
    for (int oy = 0; oy < outHeight; oy++) {
      final int sy0 = oy * height ~/ outHeight;
      final int sy1 = ((oy + 1) * height ~/ outHeight).clamp(sy0 + 1, height);
      for (int ox = 0; ox < outWidth; ox++) {
        final int sx0 = ox * width ~/ outWidth;
        final int sx1 = ((ox + 1) * width ~/ outWidth).clamp(sx0 + 1, width);
        int r = 0, g = 0, b = 0, a = 0, n = 0;
        for (int sy = sy0; sy < sy1; sy++) {
          final int row = sy * width;
          for (int sx = sx0; sx < sx1; sx++) {
            final int i = (row + sx) * 4;
            r += rgba[i];
            g += rgba[i + 1];
            b += rgba[i + 2];
            a += rgba[i + 3];
            n++;
          }
        }
        final int o = (oy * outWidth + ox) * 4;
        out[o] = r ~/ n;
        out[o + 1] = g ~/ n;
        out[o + 2] = b ~/ n;
        out[o + 3] = a ~/ n;
      }
    }
    return MediaPhoto(width: outWidth, height: outHeight, rgba: out);
  }

  /// The same picture with premultiplied alpha, which is the form
  /// `ui.PixelFormat.rgba8888` expects.
  MediaPhoto premultiplied() {
    final Uint8List out = Uint8List.fromList(rgba);
    for (int i = 0; i < out.length; i += 4) {
      final int a = out[i + 3];
      if (a == 255) continue;
      out[i] = out[i] * a ~/ 255;
      out[i + 1] = out[i + 1] * a ~/ 255;
      out[i + 2] = out[i + 2] * a ~/ 255;
    }
    return MediaPhoto(width: width, height: height, rgba: out);
  }

  @override
  bool operator ==(Object other) =>
      other is MediaPhoto &&
      other.width == width &&
      other.height == height &&
      _sameBytes(other.rgba, rgba);

  @override
  int get hashCode => Object.hash(width, height, Object.hashAll(rgba));

  @override
  String toString() => 'MediaPhoto(${width}x$height, ${rgba.length} B)';
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
