// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/media/media_composer.dart';
import 'package:meshmore_sns_app/media/media_photo.dart';
import 'package:meshmore_sns_app/media/photo_decoder.dart';
import 'package:meshmore_sns_app/media/photo_source.dart';

Uint8List _fixture(String name) =>
    File('test/media/fixtures/$name').readAsBytesSync();

/// A picker that returns a fixed answer, so the source's own job (decide what
/// the failure means) is what is under test rather than the plugin.
PhotoPicking _picks(Uint8List? bytes, {MediaPhotoOrigin? expected}) =>
    (MediaPhotoOrigin origin) async {
  if (expected != null) expect(origin, expected);
  return bytes;
};

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('it reports itself available on the platforms that have a picker', () {
    const PlatformMediaPhotoSource source = PlatformMediaPhotoSource();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(source.isAvailable, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(source.isAvailable, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(source.isAvailable, isFalse);
  });

  test('a chosen JPEG becomes a picture at the mesh floor', () async {
    final PlatformMediaPhotoSource source = PlatformMediaPhotoSource(
      picking: _picks(_fixture('photo_640x480.jpg'),
          expected: MediaPhotoOrigin.gallery),
    );
    final MediaPhoto? photo = await source.pick();
    expect(photo, isNotNull);
    expect(photo!.width, MediaPhoto.floorWidth);
    expect(photo.height, MediaPhoto.floorHeight);
  });

  test('the camera origin is what the camera action asks for', () async {
    final PlatformMediaPhotoSource source = PlatformMediaPhotoSource(
      picking:
          _picks(_fixture('photo_small.png'), expected: MediaPhotoOrigin.camera),
    );
    final MediaPhoto? photo = await source.pick(origin: MediaPhotoOrigin.camera);
    expect(photo?.width, 96);
  });

  test('backing out is nothing, not a failure', () async {
    final PlatformMediaPhotoSource source =
        PlatformMediaPhotoSource(picking: _picks(null));
    expect(await source.pick(), isNull);
  });

  test('a container the engine cannot read is an unsupported format', () async {
    final PlatformMediaPhotoSource source =
        PlatformMediaPhotoSource(picking: _picks(_fixture('photo.heic')));
    await expectLater(
      source.pick(),
      throwsA(isA<MediaPhotoSourceFailure>().having(
          (MediaPhotoSourceFailure e) => e.problem,
          'problem',
          MediaPhotoSourceProblem.unsupportedFormat)),
    );
  });

  test('a damaged file is an unreadable photo', () async {
    final Uint8List whole = _fixture('photo_640x480.jpg');
    final PlatformMediaPhotoSource source = PlatformMediaPhotoSource(
        picking: _picks(Uint8List.sublistView(whole, 0, 200)));
    await expectLater(
      source.pick(),
      throwsA(isA<MediaPhotoSourceFailure>().having(
          (MediaPhotoSourceFailure e) => e.problem,
          'problem',
          MediaPhotoSourceProblem.unreadable)),
    );
  });

  test('a decoder without a codec still refuses by name', () async {
    final PlatformMediaPhotoSource source = PlatformMediaPhotoSource(
      picking: _picks(_fixture('photo_640x480.jpg')),
      decoder: _NoDecoder(),
    );
    await expectLater(
      source.pick(),
      throwsA(isA<MediaPhotoSourceFailure>().having(
          (MediaPhotoSourceFailure e) => e.problem,
          'problem',
          MediaPhotoSourceProblem.unsupportedFormat)),
    );
  });
}

final class _NoDecoder implements PhotoDecoder {
  @override
  Future<MediaPhoto> decode(Uint8List bytes) async =>
      throw const PhotoDecodeException(
          PhotoDecodeFailure.unsupportedFormat, 'no codec');
}
