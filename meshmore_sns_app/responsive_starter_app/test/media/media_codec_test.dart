// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/media/media_codec.dart';
import 'package:meshmore_sns_app/media/media_photo.dart';

MediaPhoto photo(int width, int height) => MediaPhoto(
      width: width,
      height: height,
      rgba: Uint8List.fromList(
          List<int>.generate(width * height * 4, (int i) => (i * 7) & 0xFF)),
    );

void main() {
  group('the floor fits a picture instead of refusing it', () {
    test('a picture already inside the floor is untouched', () {
      final MediaPhoto p = photo(320, 240);
      expect(p.withinFloor, isTrue);
      expect(identical(p.fittedToFloor(), p), isTrue);
    });

    test('a larger picture is downscaled, aspect preserved, never refused', () {
      final MediaPhoto p = photo(1000, 500).fittedToFloor();
      expect(p.width, MediaPhoto.floorWidth);
      expect(p.height, lessThanOrEqualTo(MediaPhoto.floorHeight));
      expect(p.width, 320);
      expect(p.height, 160, reason: '1000x500 keeps its 2:1 shape');
      expect(p.isWellFormed, isTrue);
    });

    test('a tall picture is bounded by height, not width', () {
      final MediaPhoto p = photo(300, 900).fittedToFloor();
      expect(p.height, MediaPhoto.floorHeight);
      expect(p.width, lessThanOrEqualTo(MediaPhoto.floorWidth));
      expect(p.isWellFormed, isTrue);
    });

    test('a tiny picture is never upscaled', () {
      final MediaPhoto p = photo(40, 30).fittedToFloor();
      expect(p.width, 40);
      expect(p.height, 30);
    });

    test('the downscale averages, so a black/white split stays grey', () {
      final Uint8List rgba = Uint8List.fromList(<int>[
        0, 0, 0, 255, 255, 255, 255, 255, //
        0, 0, 0, 255, 255, 255, 255, 255,
      ]);
      final MediaPhoto out = MediaPhoto(width: 2, height: 2, rgba: rgba)
          .scaledTo(maxWidth: 1, maxHeight: 1);
      expect(out.width, 1);
      expect(out.rgba.sublist(0, 3), <int>[127, 127, 127]);
    });
  });

  group('premultiplication is the renderer\'s form', () {
    test('alpha 255 is untouched, alpha 0 goes to black', () {
      final MediaPhoto p = MediaPhoto(
        width: 2,
        height: 1,
        rgba: Uint8List.fromList(<int>[200, 100, 50, 255, 200, 100, 50, 0]),
      );
      final MediaPhoto out = p.premultiplied();
      expect(out.rgba.sublist(0, 4), <int>[200, 100, 50, 255]);
      expect(out.rgba.sublist(4, 8), <int>[0, 0, 0, 0]);
    });
  });

  group('the seam takes a fake, so the paths need no native code', () {
    test('a fake encode honours the budget and reports it', () async {
      final FakeMediaCodec codec = FakeMediaCodec(encodedBytes: 700);
      final EncodedPhoto out = await codec.encode(photo(320, 240), byteBudget: 2000);
      expect(out.withinBudget, isTrue);
      expect(out.bytes, hasLength(700));
      expect(codec.budgets, <int>[2000]);
      expect(codec.encodeCalls, 1);
    });

    test('an over-budget fake says so rather than pretending', () async {
      final FakeMediaCodec codec = FakeMediaCodec(encodedBytes: 5000);
      final EncodedPhoto out = await codec.encode(photo(320, 240), byteBudget: 1000);
      expect(out.withinBudget, isFalse);
    });
  });
}
