// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:avif_native/avif_native.dart';
import 'package:flutter/foundation.dart';

import '../util/mesh_log.dart';
import 'media_photo.dart';

/// Why the codec could not encode or decode.
enum MediaCodecFailure {
  /// The build has no codec for this direction, or the native library did not
  /// load. Named separately from a decode failure because the answer is
  /// "rebuild", not "resend".
  unavailable,

  /// The bytes are not an image this codec can read.
  decodeFailed,

  /// The encoder refused the request (bad geometry, or a build without the
  /// encoder profile).
  encodeFailed,
}

/// A codec failure with the detail a log line needs and a caller can switch on.
final class MediaCodecException implements Exception {
  const MediaCodecException(this.failure, this.detail);

  final MediaCodecFailure failure;
  final String detail;

  @override
  String toString() => 'MediaCodecException(${failure.name}: $detail)';
}

/// The seam between the app and the one image codec it ships.
///
/// There is exactly one format on the wire, so there is exactly one
/// implementation in production; the interface exists so that tests can run
/// without native code, and so that a codec swap touches one file.
abstract interface class MediaCodec {
  /// True when this build can encode and decode.
  bool get isAvailable;

  /// A picture as AVIF bytes, fitted inside [MediaPhoto.floorWidth] ×
  /// [MediaPhoto.floorHeight] and quantised until it fits [byteBudget].
  ///
  /// [byteBudget] is a target, not a promise: the quantiser ladder stops at the
  /// lowest quality it is willing to ship, and a picture that still exceeds the
  /// budget at that point is returned with [EncodedPhoto.withinBudget] false so
  /// the caller can say so before spending airtime.
  Future<EncodedPhoto> encode(MediaPhoto photo, {required int byteBudget});

  /// The first frame of an AVIF payload as a picture.
  Future<MediaPhoto> decode(Uint8List bytes);
}

/// The result of an encode: the bytes and how they landed against the budget.
final class EncodedPhoto {
  const EncodedPhoto({
    required this.bytes,
    required this.width,
    required this.height,
    required this.byteBudget,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int byteBudget;

  bool get withinBudget => bytes.length <= byteBudget;

  @override
  String toString() =>
      'EncodedPhoto($width x $height, $byteBudget B budget, ${bytes.length} B encoded)';
}

/// AVIF through libavif, dav1d and libaom, via the package's native-asset hook.
///
/// One library does both directions, which is why there is no second native
/// dependency: a second one would be a second copy of libavif with a second
/// set of licences attached, and it would have to be kept in step with this one
/// for no gain. The format is unchanged by that choice: one AV1-class image
/// type on the wire.
final class AvifMediaCodec implements MediaCodec {
  const AvifMediaCodec({this.speed = 5});

  /// Encoder effort, 0–10, where 0 is the slowest encoder and the largest file
  /// saving (D11.4, 2026-11-08).
  ///
  /// Measured on this tree with the bundled libavif/libaom, a 320×240 gradient
  /// photo, quantiser 18 (the ladder's first step):
  ///
  /// | speed | bytes | encode |
  /// | --- | --- | --- |
  /// | 9 (was the default) | 1390 | 7 ms |
  /// | 6 | 887 | 22 ms |
  /// | **5** | **784** | **90 ms** |
  /// | 4 | 796 | 131 ms |
  /// | 0 | 749 | 818 ms |
  ///
  /// The curve has a knee at 5: it is 44 % smaller than the old default, and
  /// the remaining 35 bytes to speed 0 cost nine times the CPU and a frame that
  /// would freeze on a phone. Airtime is what this buys: 1390 bytes is ten
  /// datagrams (3.5 s of channel time at the sender's 350 ms pacing), 784 is
  /// five (1.75 s).
  ///
  /// The numbers are content-dependent — a high-entropy photo lands near the
  /// ladder's ceiling where every speed produces about the same bytes — so this
  /// is the effort setting, not a promise about any one picture. What it must
  /// never do is block the frame: the encode is synchronous, so the M1 protocol
  /// (median encode at most a third of the transfer time) is also the gate that
  /// keeps this number honest on a phone.
  final int speed;

  /// How long the last encode's native call took, in milliseconds.
  ///
  /// The M1 protocol asks for the median encode against the transfer time it
  /// buys, and there was no way to read it: the encode is synchronous inside
  /// this class and nothing timed it. This is the number, taken around the
  /// native call rather than around a Dart future, because that is the part
  /// that blocks the frame.
  static int lastEncodeMillis = 0;

  /// Every encode this process ran, for a median rather than a single reading.
  static final List<int> encodeMillis = <int>[];

  /// The quantiser ladder, worst case last.
  ///
  /// libavif's quantiser is 0–63. Below about 20 the container overhead and the
  /// AV1 headers dominate, and above about 50 a 320×240 photo stops being a
  /// photo. The ladder walks up from the good end until the bytes fit, so the
  /// first attempt is also the best-looking one that can possibly fit.
  static const List<(int, int)> quantiserLadder = <(int, int)>[
    (18, 30),
    (26, 38),
    (32, 44),
    (38, 50),
    (44, 56),
    (50, 63),
  ];

  @override
  bool get isAvailable =>
      avifNativeCapabilities.canEncode && avifNativeCapabilities.canDecode;

  @override
  Future<EncodedPhoto> encode(MediaPhoto photo,
      {required int byteBudget}) async {
    if (!avifNativeCapabilities.canEncode) {
      throw const MediaCodecException(
        MediaCodecFailure.unavailable,
        'this build has no AVIF encoder',
      );
    }
    final MediaPhoto fitted = photo.fittedToFloor();
    EncodedPhoto? smallest;
    for (final (int minQ, int maxQ) in quantiserLadder) {
      final Uint8List bytes;
      final Stopwatch watch = Stopwatch()..start();
      try {
        bytes = encodeAvifFrames(
          width: fitted.width,
          height: fitted.height,
          frames: <AvifEncodeFrame>[AvifEncodeFrame(rgba: fitted.rgba)],
          options: AvifEncodeOptions(
            speed: speed,
            minQuantizer: minQ,
            maxQuantizer: maxQ,
            minQuantizerAlpha: minQ,
            maxQuantizerAlpha: maxQ,
          ),
        );
      } on AvifEncodeException catch (e) {
        throw MediaCodecException(MediaCodecFailure.encodeFailed, e.message);
      } on UnsupportedError catch (e) {
        throw MediaCodecException(MediaCodecFailure.unavailable, '$e');
      } finally {
        watch.stop();
        lastEncodeMillis = watch.elapsedMilliseconds;
        encodeMillis.add(lastEncodeMillis);
        if (encodeMillis.length > 64) encodeMillis.removeAt(0);
        if (kDebugMode) {
          meshLog('media',
              'encode ${fitted.width}x${fitted.height} speed $speed q$minQ-$maxQ: '
              '${watch.elapsedMilliseconds} ms (M1: median ${_medianMillis()} ms '
              'over ${encodeMillis.length})');
        }
      }
      final EncodedPhoto candidate = EncodedPhoto(
        bytes: bytes,
        width: fitted.width,
        height: fitted.height,
        byteBudget: byteBudget,
      );
      if (smallest == null || bytes.length < smallest.bytes.length) {
        smallest = candidate;
      }
      if (candidate.withinBudget) return candidate;
    }
    return smallest!;
  }

  /// The median of the encodes this process has run, for the M1 threshold.
  static int _medianMillis() {
    if (encodeMillis.isEmpty) return 0;
    final List<int> sorted = List<int>.of(encodeMillis)..sort();
    return sorted[sorted.length ~/ 2];
  }

  @override
  Future<MediaPhoto> decode(Uint8List bytes) async {
    if (!avifNativeCapabilities.canDecode) {
      throw const MediaCodecException(
        MediaCodecFailure.unavailable,
        'this build has no AVIF decoder',
      );
    }
    final AvifImageData image;
    try {
      image = decodeAvif(bytes);
    } on AvifDecodeException catch (e) {
      throw MediaCodecException(MediaCodecFailure.decodeFailed, e.message);
    } on UnsupportedError catch (e) {
      throw MediaCodecException(MediaCodecFailure.unavailable, '$e');
    }
    if (image.frames.isEmpty) {
      throw const MediaCodecException(
        MediaCodecFailure.decodeFailed,
        'the payload carried no frame',
      );
    }
    final AvifFrame frame = image.frames.first;
    return MediaPhoto(
      width: frame.width,
      height: frame.height,
      rgba: frame.rgba,
    );
  }
}

/// A codec that produces no image data at all.
///
/// Tests that exercise the send and receive paths care about chunk counts,
/// pacing and copy, not pixels, and they must run on a host with no native
/// library. This codec returns bytes of a requested size and a picture of the
/// requested geometry, deterministically.
final class FakeMediaCodec implements MediaCodec {
  FakeMediaCodec({
    this.encodedBytes = 900,
    this.width = MediaPhoto.floorWidth,
    this.height = MediaPhoto.floorHeight,
  });

  /// Bytes the fake "encoder" produces, so a test can pick a chunk count.
  final int encodedBytes;
  final int width;
  final int height;

  int encodeCalls = 0;
  int decodeCalls = 0;

  /// Every budget a caller asked for, in order, so a test can assert the
  /// projection was computed before the encode.
  final List<int> budgets = <int>[];

  @override
  bool get isAvailable => true;

  @override
  Future<EncodedPhoto> encode(MediaPhoto photo,
      {required int byteBudget}) async {
    encodeCalls++;
    budgets.add(byteBudget);
    return EncodedPhoto(
      bytes: Uint8List.fromList(
          List<int>.generate(encodedBytes, (int i) => i & 0xFF)),
      width: width,
      height: height,
      byteBudget: byteBudget,
    );
  }

  @override
  Future<MediaPhoto> decode(Uint8List bytes) async {
    decodeCalls++;
    return MediaPhoto(
      width: width,
      height: height,
      rgba: Uint8List(width * height * 4),
    );
  }
}
