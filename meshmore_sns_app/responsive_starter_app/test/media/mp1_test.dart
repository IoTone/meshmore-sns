// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/media/mp1.dart';
import 'package:meshmore_sns_app/media/media_photo.dart';

/// MP1 is a wire format, so the test is about bytes rather than pictures.
///
/// The format is MeshPix's, and the whole reason to have it is that a MeshPix
/// user can read our preview and we can read theirs. A round trip through our
/// own encoder and decoder would pass even if both disagreed with them, so the
/// header bytes and the packing are asserted directly.
void main() {
  MediaPhoto gradient({int w = 320, int h = 240}) {
    final Uint8List rgba = Uint8List(w * h * 4);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int i = (y * w + x) * 4;
        rgba[i] = (x * 255) ~/ w;
        rgba[i + 1] = (y * 255) ~/ h;
        rgba[i + 2] = 128;
        rgba[i + 3] = 0xFF;
      }
    }
    return MediaPhoto(width: w, height: h, rgba: rgba);
  }

  test('a preview is one channel datagram, never more', () {
    final Uint8List? bytes =
        encodeMp1Preview(gradient(), transferId: 7, upgradeChunks: 12);
    expect(bytes, isNotNull);
    expect(bytes!.length, lessThanOrEqualTo(kMp1MaxPayload),
        reason: 'MP1 exists because 163 bytes is the whole budget');
  });

  test('the header is MeshPix\'s, byte for byte', () {
    final Uint8List? bytes =
        encodeMp1Preview(gradient(), transferId: 0x1234, upgradeChunks: 9);
    expect(bytes, isNotNull);
    expect(bytes![0], 0x4D, reason: "'M'");
    expect(bytes[1], 0x50, reason: "'P'");
    expect(bytes[2], 1, reason: 'version 1');
    // kind preview (0), raw body (0), 16 colours => 4 bpp => bit 5, dithered
    // by default => bit 6.
    expect(bytes[3] & 0x07, 0, reason: 'preview kind');
    expect(bytes[3] & (1 << 3), 0, reason: 'raw body, which every decoder reads');
    expect(bytes[3] & (1 << 6), isNot(0), reason: 'dithered');
    expect(bytes[4], 0x34, reason: 'transfer id low byte');
    expect(bytes[5], 0x12, reason: 'transfer id high byte');
    expect(bytes[6], bytes[7], reason: 'a preview is square');
    expect(bytes[8], anyOf(0, 1), reason: 'a shippable palette id');
    expect(bytes[9], 9, reason: 'the upgrade chunk count travels with it');
  });

  test('the largest picture that fits is preferred, then colour, then size', () {
    final Uint8List? bytes = encodeMp1Preview(gradient(), transferId: 1);
    expect(bytes, isNotNull);
    // 24x24 at four colours is 144 bytes of indices, which fits; 24x24 at
    // sixteen would be 288 and cannot, so the ladder stops on its first rung.
    expect(bytes![6], 24);
    expect(bytes[8], kMp1Mesh4.id);
  });

  test('a decoded preview is the same size, palette and transfer id', () {
    final Uint8List? bytes =
        encodeMp1Preview(gradient(), transferId: 0x0BAD, upgradeChunks: 4);
    final Mp1DecodeResult out = decodeMp1Preview(bytes!);
    expect(out.ok, isTrue);
    final Mp1Image img = out.image!;
    expect(img.width, bytes[6]);
    expect(img.height, bytes[7]);
    expect(img.transferId, 0x0BAD);
    expect(img.upgradeChunks, 4);
    expect(img.indices.length, img.width * img.height);
    expect(img.indices.every((int i) => i >= 0 && i < img.palette.colours.length),
        isTrue);
    // The RGBA view is what the rest of the app draws.
    final MediaPhoto photo = img.toPhoto();
    expect(photo.rgba.length, img.width * img.height * 4);
    expect(photo.rgba[3], 0xFF);
  });

  test('a foreign datagram is refused by name, not by exception', () {
    final Mp1DecodeResult notMine =
        decodeMp1Preview(Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]));
    expect(notMine.ok, isFalse);
    expect(notMine.problem, Mp1Problem.notMp1);

    final Mp1DecodeResult short = decodeMp1Preview(Uint8List(4));
    expect(short.problem, Mp1Problem.truncated);
  });

  test('a zlib body is refused rather than mis-decoded', () {
    final Uint8List bytes =
        Uint8List.fromList(encodeMp1Preview(gradient(), transferId: 2)!);
    // Rewrite the encoding field to zlib, which this build does not ship.
    bytes[3] = (bytes[3] & ~(0x03 << 3)) | (1 << 3);
    final Mp1DecodeResult out = decodeMp1Preview(bytes);
    expect(out.ok, isFalse);
    expect(out.problem, Mp1Problem.unsupportedEncoding);
  });
}
