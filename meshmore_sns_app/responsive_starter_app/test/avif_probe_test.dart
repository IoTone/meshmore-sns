// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:avif_native/avif_native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The codec is native code behind a build hook, so this is the only test that
/// proves the binary actually loads and round-trips on the host that built it.
/// The seam tests (`media_codec_test.dart`) use a fake; this one is the smoke
/// test for the real library.
void main() {
  test('AVIF encodes and decodes a 320x240 RGBA image', () {
    const int w = 320, h = 240;
    final Uint8List rgba = Uint8List(w * h * 4);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int i = (y * w + x) * 4;
        rgba[i] = x * 255 ~/ w;
        rgba[i + 1] = y * 255 ~/ h;
        rgba[i + 2] = (x + y) & 0xFF;
        rgba[i + 3] = 255;
      }
    }
    final Uint8List avif = encodeAvifFrames(
      width: w,
      height: h,
      frames: <AvifEncodeFrame>[AvifEncodeFrame(rgba: rgba)],
      options: const AvifEncodeOptions(
        speed: 8,
        minQuantizer: 20,
        maxQuantizer: 32,
      ),
    );
    expect(avif, isNotEmpty);
    // EBU: every AVIF still is an ISO-BMFF file, so it begins with a box size
    // and the `ftyp` brand.
    expect(String.fromCharCodes(avif.sublist(4, 8)), 'ftyp');

    final AvifImageData back = decodeAvif(avif);
    expect(back.width, w);
    expect(back.height, h);
    expect(back.frames.single.rgba.length, w * h * 4);
  });
}
