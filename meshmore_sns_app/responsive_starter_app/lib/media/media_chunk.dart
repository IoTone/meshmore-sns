// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';

/// One chunk of a media payload, carried in a single `0x3E` channel datagram.
///
/// The blob budget is the firmware's, not this file's: a datagram carries
/// `ChannelDataLimits.maxBlob` (162) bytes and the radio re-wraps it. The
/// header spends 12 of those and leaves 150 for payload, which is the number
/// the reassembler and the FEC block size are built around.
///
/// Layout (big-endian, fixed 12 bytes):
///
/// ```
/// 0      version << 4 | attempt          attempt 0 = original, 1..15 = resend
/// 1      kind                            1 image, 2 voice
/// 2..5   payload id                      random per transfer, not a counter
/// 6..7   chunk index
/// 8..9   chunk count
/// 10..11 data CRC16                      over the payload bytes only
/// ```
///
/// The attempt nibble is the salt: the radio drops an identical packet it has
/// already seen, so a resend has to differ in a byte the receiver does not
/// care about. The CRC covers the data, not the header, so a salted resend
/// still validates the same way.
abstract final class MediaChunkCodec {
  /// Bytes of header in front of every chunk's payload.
  static const int headerBytes = 12;

  /// Payload bytes that fit beside [headerBytes] in one datagram.
  static const int maxDataBytes = ChannelDataLimits.maxBlob - headerBytes;

  /// Bumped only if the layout changes; a receiver refuses what it cannot read
  /// rather than guessing.
  static const int version = 1;

  /// The attempt field is four bits, so a chunk may be resent fifteen times
  /// before its salt space is exhausted. Past that the engine reports the
  /// transfer as unreachable instead of looping identical packets.
  static const int maxAttempt = 15;

  /// Splits [payload] into chunk blobs, [dataBytes] each (default the
  /// datagram's own budget). The last chunk is short; nothing pads it,
  /// because the receiver already knows the count.
  static List<Uint8List> split(
    List<int> payload, {
    required int payloadId,
    required MediaKind kind,
    int dataBytes = maxDataBytes,
  }) {
    if (dataBytes <= 0 || dataBytes > maxDataBytes) {
      throw ArgumentError.value(
          dataBytes, 'dataBytes', 'must be 1..$maxDataBytes');
    }
    if (payload.isEmpty) {
      throw ArgumentError.value(payload, 'payload', 'cannot be empty');
    }
    final int count = (payload.length + dataBytes - 1) ~/ dataBytes;
    return <Uint8List>[
      for (int i = 0; i < count; i++)
        encode(
          payloadId: payloadId,
          kind: kind,
          index: i,
          count: count,
          data: payload.sublist(
              i * dataBytes, (i + 1) * dataBytes > payload.length
                  ? payload.length
                  : (i + 1) * dataBytes),
        ),
    ];
  }

  static Uint8List encode({
    required int payloadId,
    required MediaKind kind,
    required int index,
    required int count,
    required List<int> data,
    int attempt = 0,
  }) {
    if (data.length > maxDataBytes) {
      throw ArgumentError.value(
          data.length, 'data', 'a chunk carries at most $maxDataBytes bytes');
    }
    if (count < 1 || index < 0 || index >= count) {
      throw ArgumentError.value(index, 'index', 'must be within $count');
    }
    if (attempt < 0 || attempt > maxAttempt) {
      throw ArgumentError.value(attempt, 'attempt', 'must be 0..$maxAttempt');
    }
    final Uint8List out = Uint8List(headerBytes + data.length);
    final ByteData view = ByteData.sublistView(out);
    out[0] = (version << 4) | attempt;
    out[1] = kind.code;
    view.setUint32(2, payloadId);
    view.setUint16(6, index);
    view.setUint16(8, count);
    view.setUint16(10, crc16(data));
    out.setRange(headerBytes, out.length, data);
    return out;
  }

  /// Parses one datagram payload. Every rejection is a named outcome: a
  /// chunk from a future layout, a chunk whose index cannot exist, and a
  /// chunk whose bytes do not match its CRC are different problems and must
  /// not collapse into "bad packet".
  static MediaChunkParse parse(List<int> blob) {
    if (blob.length <= headerBytes) {
      return MediaChunkParse.failed(MediaChunkRefusal.tooShort);
    }
    final Uint8List head = Uint8List.fromList(blob.sublist(0, headerBytes));
    final ByteData view = ByteData.sublistView(head);
    final int header = blob[0];
    if (header >> 4 != version) {
      return MediaChunkParse.failed(MediaChunkRefusal.unknownVersion);
    }
    final MediaKind? kind = MediaKind.fromCode(blob[1]);
    if (kind == null) {
      return MediaChunkParse.failed(MediaChunkRefusal.unknownKind);
    }
    final int index = view.getUint16(6);
    final int count = view.getUint16(8);
    if (count == 0 || index >= count) {
      return MediaChunkParse.failed(MediaChunkRefusal.indexOutOfRange);
    }
    final List<int> data = blob.sublist(headerBytes);
    if (crc16(data) != view.getUint16(10)) {
      return MediaChunkParse.failed(MediaChunkRefusal.crcMismatch);
    }
    return MediaChunkParse(MediaChunk(
      payloadId: view.getUint32(2),
      kind: kind,
      index: index,
      count: count,
      attempt: header & 0x0F,
      data: Uint8List.fromList(data),
    ));
  }

  /// CRC-16/CCITT-FALSE. A wrong chunk that lands in the right slot is the
  /// failure the index alone cannot see, so every chunk carries its own check
  /// rather than trusting arrival order.
  static int crc16(List<int> bytes) {
    int crc = 0xFFFF;
    for (final int b in bytes) {
      crc ^= (b & 0xFF) << 8;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0
            ? ((crc << 1) ^ 0x1021) & 0xFFFF
            : (crc << 1) & 0xFFFF;
      }
    }
    return crc;
  }
}

/// What a media payload is. Two, because the app sends images and recorded
/// voice and nothing else this phase.
enum MediaKind {
  image(1),
  voice(2);

  const MediaKind(this.code);

  final int code;

  static MediaKind? fromCode(int code) {
    for (final MediaKind k in MediaKind.values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// Why a datagram did not parse as a media chunk.
enum MediaChunkRefusal {
  tooShort,
  unknownVersion,
  unknownKind,
  indexOutOfRange,
  crcMismatch,
}

/// One parsed chunk.
final class MediaChunk {
  const MediaChunk({
    required this.payloadId,
    required this.kind,
    required this.index,
    required this.count,
    required this.attempt,
    required this.data,
  });

  final int payloadId;
  final MediaKind kind;
  final int index;
  final int count;
  final int attempt;
  final Uint8List data;

  bool get isResend => attempt > 0;

  /// The identity used by the dedupe window: a chunk is the same chunk
  /// whatever its attempt nibble says.
  String get slotKey => '$payloadId:$index';
}

/// Parse result: exactly one of [chunk] and [refusal].
final class MediaChunkParse {
  MediaChunkParse(MediaChunk this.chunk) : refusal = null;
  MediaChunkParse.failed(MediaChunkRefusal this.refusal) : chunk = null;

  final MediaChunk? chunk;
  final MediaChunkRefusal? refusal;

  bool get ok => chunk != null;
}
