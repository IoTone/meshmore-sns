// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

/// Packs Codec 2 frames bit-contiguously, most significant bit first.
///
/// Codec 2's own frame buffer is rounded up to whole bytes: 700C produces 28
/// bits in a 4-byte buffer and 1300 produces 52 bits in 7, so four bits of
/// every frame are padding. Concatenating those buffers ships the padding:
/// 25 frames of a 700C second would be 100 bytes instead of 88, which is
/// twelve bytes — nearly one whole datagram — spent on nothing, on a link
/// whose entire cost is bytes.
///
/// The stream therefore carries no frame length and no frame count: the width
/// comes from the mode and the count comes from the length, so a receiver
/// knows both without a header. That is only sound because a stream is always
/// decoded at the mode it was encoded at, which is what the transfer's kind and
/// the mode's own width give us.
///
/// A frame is [bytesPerFrame] bytes in memory and [bitsPerFrame] bits on the
/// wire. [pack] reads only the meaningful bits and [unpack] zero-fills the
/// padding, so a frame decoded from a packed stream is byte-identical to the
/// frame that was packed: Codec 2 never reads those four bits.
abstract final class VoiceFramePacker {
  /// Bits a frame of [bitsPerFrame] occupies on the wire.
  static int packedBits(int frameCount, int bitsPerFrame) =>
      frameCount * bitsPerFrame;

  /// Bytes a stream of [frameCount] frames occupies, rounded up.
  static int packedBytes(int frameCount, int bitsPerFrame) =>
      (packedBits(frameCount, bitsPerFrame) + 7) ~/ 8;

  /// Packs [frames], each [bytesPerFrame] bytes carrying [bitsPerFrame] bits.
  ///
  /// Returns an empty list for no frames; throws [ArgumentError] when a frame
  /// is the wrong size or the widths are impossible, because a silently
  /// truncated stream is a decoder reading speech out of an off-by-one
  /// alignment for the rest of the recording.
  static Uint8List pack(
    List<Uint8List> frames, {
    required int bitsPerFrame,
    required int bytesPerFrame,
  }) {
    _checkWidths(bitsPerFrame, bytesPerFrame);
    if (frames.isEmpty) return Uint8List(0);
    final Uint8List out = Uint8List(packedBytes(frames.length, bitsPerFrame));
    int bit = 0;
    for (final Uint8List frame in frames) {
      if (frame.length != bytesPerFrame) {
        throw ArgumentError.value(frame.length, 'frames',
            'each frame must be $bytesPerFrame bytes for $bitsPerFrame bits');
      }
      for (int i = 0; i < bitsPerFrame; i++) {
        // Drop the padding bits after `bitsPerFrame`, then re-lay the rest.
        final int source = (frame[i >> 3] >> (7 - (i & 7))) & 1;
        if (source == 1) out[bit >> 3] |= 1 << (7 - (bit & 7));
        bit++;
      }
    }
    return out;
  }

  /// How many whole frames [packed] carries at this width.
  static int frameCountOf(Uint8List packed, {required int bitsPerFrame}) {
    if (bitsPerFrame <= 0) {
      throw ArgumentError.value(bitsPerFrame, 'bitsPerFrame', 'must be > 0');
    }
    return (packed.length * 8) ~/ bitsPerFrame;
  }

  /// Bits left over past the last whole frame.
  ///
  /// A packed stream always ends on a byte boundary, so this is 0–7 for a
  /// stream [pack] produced. Eight or more means the stream was cut inside a
  /// frame, and [unpack] refuses it: decoding from a cut stream is four bits of
  /// alignment error for every frame after the cut.
  static int trailingBits(Uint8List packed, {required int bitsPerFrame}) {
    final int bits = packed.length * 8;
    return bits - (bits ~/ bitsPerFrame) * bitsPerFrame;
  }

  /// Unpacks [packed] into frames of [bytesPerFrame] bytes.
  ///
  /// A trailing partial frame is refused rather than decoded: it means the
  /// stream was cut short, and half a frame of speech is four bits of
  /// alignment error for everything after it.
  static List<Uint8List> unpack(
    Uint8List packed, {
    required int bitsPerFrame,
    required int bytesPerFrame,
  }) {
    _checkWidths(bitsPerFrame, bytesPerFrame);
    if (packed.isEmpty) return const <Uint8List>[];
    // The last byte is padded to a byte boundary, so 0–7 trailing bits are the
    // packer's own padding. Eight or more cannot come from [pack] and means the
    // stream was cut inside a frame.
    final int trailing = trailingBits(packed, bitsPerFrame: bitsPerFrame);
    if (trailing >= 8) {
      throw ArgumentError.value(packed.length, 'packed',
          'ends mid-frame: $trailing trailing bits at $bitsPerFrame per frame');
    }
    final int count = (packed.length * 8) ~/ bitsPerFrame;
    final List<Uint8List> frames = <Uint8List>[
      for (int i = 0; i < count; i++) Uint8List(bytesPerFrame),
    ];
    int bit = 0;
    for (int f = 0; f < count; f++) {
      final Uint8List frame = frames[f];
      for (int i = 0; i < bitsPerFrame; i++) {
        final int source = (packed[bit >> 3] >> (7 - (bit & 7))) & 1;
        if (source == 1) frame[i >> 3] |= 1 << (7 - (i & 7));
        bit++;
      }
    }
    return frames;
  }

  static void _checkWidths(int bitsPerFrame, int bytesPerFrame) {
    if (bitsPerFrame <= 0) {
      throw ArgumentError.value(bitsPerFrame, 'bitsPerFrame', 'must be > 0');
    }
    if (bytesPerFrame * 8 < bitsPerFrame) {
      throw ArgumentError.value(bytesPerFrame, 'bytesPerFrame',
          'must hold at least $bitsPerFrame bits');
    }
  }
}
