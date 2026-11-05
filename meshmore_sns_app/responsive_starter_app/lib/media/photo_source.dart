// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:image_picker/image_picker.dart';

import 'media_composer.dart';
import 'media_photo.dart';
import 'photo_decoder.dart';

/// The bytes a picker returned, or null when the user backed out.
typedef PhotoPicking = Future<Uint8List?> Function(MediaPhotoOrigin origin);

/// The real photo source: the platform picker, then the engine's decoder.
///
/// The picker is `image_picker` (BSD-3, the Flutter team's own plugin), which
/// is the smallest dependency that covers both camera capture and the gallery
/// on Android and iOS without a file-manager UI of its own. Decoding stays with
/// the engine's decoders (`SystemPhotoDecoder`), so the app gains one plugin
/// and no second image library.
final class PlatformMediaPhotoSource implements MediaPhotoSource {
  const PlatformMediaPhotoSource({
    this.decoder = const SystemPhotoDecoder(),
    this.picking = pickWithPlugin,
  });

  final PhotoDecoder decoder;
  final PhotoPicking picking;

  /// False where there is no platform picker to call, so the composer says the
  /// build cannot read a photo instead of offering a button that fails.
  @override
  bool get isAvailable {
    if (kIsWeb) return false;
    // The platform, not the host: `defaultTargetPlatform` is the value a test
    // can set, so availability is provable without a phone.
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Future<MediaPhoto?> pick(
      {MediaPhotoOrigin origin = MediaPhotoOrigin.gallery}) async {
    final Uint8List? bytes = await picking(origin);
    if (bytes == null) return null;
    try {
      return await decoder.decode(bytes);
    } on PhotoDecodeException catch (e) {
      throw MediaPhotoSourceFailure(
        '${e.failure.name}: ${e.detail}',
        problem: switch (e.failure) {
          PhotoDecodeFailure.unsupportedFormat =>
            MediaPhotoSourceProblem.unsupportedFormat,
          PhotoDecodeFailure.empty ||
          PhotoDecodeFailure.corrupt =>
            MediaPhotoSourceProblem.unreadable,
        },
      );
    }
  }
}

/// The platform picker call itself.
///
/// `requestFullMetadata: false` because the app stores nothing about the
/// photo's provenance: the EXIF orientation is read by the decoder from the
/// file, and the GPS tag is not something this app asks to keep. A cancelled
/// pick returns null, which is not a failure.
Future<Uint8List?> pickWithPlugin(MediaPhotoOrigin origin) async {
  final XFile? file = await ImagePicker().pickImage(
    source: origin == MediaPhotoOrigin.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  return file.readAsBytes();
}
