// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'media_photo.dart';
import 'image_format.dart';

/// Why a file the user chose could not become a picture.
enum PhotoDecodeFailure {
  /// An empty file, or one whose magic number is not an image at all.
  empty,

  /// A container this build cannot decode. HEIC is the one a phone camera
  /// actually produces, and the answer is a different file, not a retry.
  unsupportedFormat,

  /// The container is one this build reads, but the data is damaged.
  corrupt,
}

/// A decode that failed, with the container named so the copy can be specific.
final class PhotoDecodeException implements Exception {
  const PhotoDecodeException(this.failure, this.detail, {this.format});

  final PhotoDecodeFailure failure;
  final String detail;
  final MediaImageFormat? format;

  @override
  String toString() =>
      'PhotoDecodeException(${failure.name}${format == null ? '' : ', ${format!.name}'}: $detail)';
}

/// Encoded file bytes to the RGBA picture the encoder takes.
///
/// A seam for the same reason the codec is one: the platform decoders are
/// reached through the engine, and the composer's behaviour has to be provable
/// on a host.
abstract interface class PhotoDecoder {
  Future<MediaPhoto> decode(Uint8List bytes);
}

/// Decoding through the engine's own image decoders.
///
/// JPEG, PNG, GIF, BMP and WebP are decoded by the engine itself, so the app
/// carries no second native library for the camera's formats. Two measured
/// facts this implementation depends on, both pinned by tests in
/// `test/media/photo_decoder_test.dart`:
///
///  * The engine applies the EXIF orientation tag, so a portrait photo stored
///    landscape arrives 480x640 rather than 640x480 and needs no rotation here.
///  * The engine has no HEIF or AV1 decoder, so a HEIC fails. The container is
///    sniffed first so that failure is reported as `unsupportedFormat`, which
///    the copy turns into "pick a JPEG", instead of as a broken file.
final class SystemPhotoDecoder implements PhotoDecoder {
  const SystemPhotoDecoder({this.targetWidth = MediaPhoto.floorWidth * 2});

  /// Width the decoder asks for, so a 12 MP photo is scaled inside the decoder
  /// rather than decoded to 48 MB and box-filtered down afterwards.
  ///
  /// Twice the floor keeps a little detail for the encoder to choose from; the
  /// final fit to `MediaPhoto.floorWidth` x `floorHeight` happens in
  /// [MediaPhoto.fittedToFloor].
  final int targetWidth;

  @override
  Future<MediaPhoto> decode(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw const PhotoDecodeException(
        PhotoDecodeFailure.empty,
        'the file is empty',
        format: MediaImageFormat.unknown,
      );
    }
    final MediaImageFormat format = sniffImageFormat(bytes);
    if (!engineDecodes(format)) {
      throw PhotoDecodeException(
        PhotoDecodeFailure.unsupportedFormat,
        'this build has no decoder for ${format.name}',
        format: format,
      );
    }
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
      final ui.FrameInfo frame = await codec.getNextFrame();
      image = frame.image;
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        throw PhotoDecodeException(
          PhotoDecodeFailure.corrupt,
          'the decoder produced no pixels',
          format: format,
        );
      }
      return MediaPhoto(
        width: image.width,
        height: image.height,
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ).fittedToFloor();
    } on PhotoDecodeException {
      rethrow;
    } catch (e) {
      throw PhotoDecodeException(
        PhotoDecodeFailure.corrupt,
        '$e',
        format: format,
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}
