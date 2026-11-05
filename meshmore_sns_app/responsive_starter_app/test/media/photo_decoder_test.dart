// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/media/image_format.dart';
import 'package:meshmore_sns_app/media/media_photo.dart';
import 'package:meshmore_sns_app/media/photo_decoder.dart';

/// Real files rather than synthesised bytes, because the question this decoder
/// answers is what the engine does with a camera's output, and a fixture made
/// by the test proves only what the test wrote.
Uint8List _fixture(String name) =>
    File('test/media/fixtures/$name').readAsBytesSync();

void main() {
  const SystemPhotoDecoder decoder = SystemPhotoDecoder();

  group('container sniffing', () {
    test('names the format a camera or a gallery actually produces', () {
      expect(sniffImageFormat(_fixture('photo_640x480.jpg')),
          MediaImageFormat.jpeg);
      expect(sniffImageFormat(_fixture('photo_small.png')),
          MediaImageFormat.png);
      expect(sniffImageFormat(_fixture('photo.heic')), MediaImageFormat.heic);
      expect(sniffImageFormat(Uint8List.fromList('not an image'.codeUnits)),
          MediaImageFormat.unknown);
    });

    test('the engine decodes the formats a phone shares', () {
      expect(engineDecodes(MediaImageFormat.jpeg), isTrue);
      expect(engineDecodes(MediaImageFormat.png), isTrue);
      expect(engineDecodes(MediaImageFormat.webp), isTrue);
      expect(engineDecodes(MediaImageFormat.heic), isFalse);
      expect(engineDecodes(MediaImageFormat.avif), isFalse);
    });
  });

  group('decoding', () {
    test('a camera JPEG lands at the mesh floor, aspect preserved', () async {
      final MediaPhoto photo = await decoder.decode(_fixture('photo_640x480.jpg'));
      expect(photo.isWellFormed, isTrue);
      expect(photo.width, MediaPhoto.floorWidth);
      expect(photo.height, MediaPhoto.floorHeight);
      expect(photo.withinFloor, isTrue);
    });

    test('a picture already inside the floor is not touched up', () async {
      final MediaPhoto photo = await decoder.decode(_fixture('photo_small.png'));
      expect(photo.width, 96);
      expect(photo.height, 64);
    });

    // The engine applies the EXIF tag itself. This is the fact the decoder
    // leans on, so it is pinned rather than assumed: the stored pixels are
    // 640x480 landscape and the tag says rotate 90, so a portrait photo has to
    // come back taller than it is wide.
    test('an EXIF-tagged portrait photo comes out upright', () async {
      final MediaPhoto upright = await decoder.decode(_fixture('photo_upright.jpg'));
      final MediaPhoto rotated = await decoder.decode(_fixture('photo_exif6.jpg'));
      expect(upright.width, greaterThan(upright.height));
      expect(rotated.height, greaterThan(rotated.width),
          reason: 'the tag says portrait, so the picture must be portrait');
      expect(rotated.withinFloor, isTrue);
    });

    test('a half-turn tag keeps the geometry and moves the pixels', () async {
      final MediaPhoto upright = await decoder.decode(_fixture('photo_upright.jpg'));
      final MediaPhoto halfTurn = await decoder.decode(_fixture('photo_exif3.jpg'));
      expect(halfTurn.width, upright.width);
      expect(halfTurn.height, upright.height);
      final int uprightTopLeft = upright.rgba[0] << 16 |
          upright.rgba[1] << 8 |
          upright.rgba[2];
      final int halfTurnTopLeft =
          halfTurn.rgba[0] << 16 | halfTurn.rgba[1] << 8 | halfTurn.rgba[2];
      expect(halfTurnTopLeft, isNot(uprightTopLeft),
          reason: 'a 180 degree rotation must not return the same pixels');
    });

    test('a damaged JPEG is a named failure, not an exception', () async {
      final Uint8List whole = _fixture('photo_640x480.jpg');
      final Uint8List truncated = Uint8List.sublistView(whole, 0, 200);
      await expectLater(
        decoder.decode(truncated),
        throwsA(isA<PhotoDecodeException>().having(
            (PhotoDecodeException e) => e.failure,
            'failure',
            PhotoDecodeFailure.corrupt)),
      );
    });

    // The one a phone actually produces and this build cannot read. It must be
    // reported as unsupported, because the answer is a different file, not a
    // retry of the same one.
    test('a HEIC is refused by name', () async {
      await expectLater(
        decoder.decode(_fixture('photo.heic')),
        throwsA(isA<PhotoDecodeException>()
            .having((PhotoDecodeException e) => e.failure, 'failure',
                PhotoDecodeFailure.unsupportedFormat)
            .having((PhotoDecodeException e) => e.format, 'format',
                MediaImageFormat.heic)),
      );
    });

    test('an empty file is refused before the decoder is asked', () async {
      await expectLater(
        decoder.decode(Uint8List(0)),
        throwsA(isA<PhotoDecodeException>().having(
            (PhotoDecodeException e) => e.failure,
            'failure',
            PhotoDecodeFailure.empty)),
      );
    });
  });
}
