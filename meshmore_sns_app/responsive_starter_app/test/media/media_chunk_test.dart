// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';

import 'package:meshmore_sns_app/media/media_chunk.dart';

void main() {
  group('the chunk header is the wire layout', () {
    test('a chunk is 12 bytes of header and the rest is payload', () {
      final Uint8List blob = MediaChunkCodec.encode(
        payloadId: 0x01020304,
        kind: MediaKind.image,
        index: 2,
        count: 5,
        data: List<int>.generate(4, (int i) => 0xA0 + i),
      );
      expect(blob.length, MediaChunkCodec.headerBytes + 4);
      expect(blob[0], (MediaChunkCodec.version << 4) | 0);
      expect(blob[1], MediaKind.image.code);
      expect(blob.sublist(2, 6), <int>[0x01, 0x02, 0x03, 0x04]);
      expect(blob.sublist(6, 8), <int>[0x00, 0x02]);
      expect(blob.sublist(8, 10), <int>[0x00, 0x05]);
      // CRC over the payload only, so the attempt nibble can salt a resend
      // without invalidating the check.
      expect(blob.sublist(10, 12),
          <int>[MediaChunkCodec.crc16(blob.sublist(12)) >> 8,
               MediaChunkCodec.crc16(blob.sublist(12)) & 0xFF]);
    });

    test('the data budget is what one datagram leaves', () {
      expect(MediaChunkCodec.maxDataBytes,
          ChannelDataLimits.maxBlob - MediaChunkCodec.headerBytes);
      expect(MediaChunkCodec.maxDataBytes, 150);
    });

    test('split produces the smallest count that holds the payload', () {
      final List<Uint8List> chunks = MediaChunkCodec.split(
        List<int>.filled(301, 7),
        payloadId: 9,
        kind: MediaKind.voice,
      );
      expect(chunks.length, 3);
      expect(chunks.first.length, MediaChunkCodec.headerBytes + 150);
      expect(chunks.last.length, MediaChunkCodec.headerBytes + 1);
    });
  });

  group('parse refuses by name, not by guess', () {
    test('a short datagram is tooShort', () {
      expect(
          MediaChunkCodec.parse(<int>[0x10, 1, 0]).refusal,
          MediaChunkRefusal.tooShort);
    });

    test('a future layout is unknownVersion', () {
      final Uint8List blob = MediaChunkCodec.encode(
          payloadId: 1, kind: MediaKind.image, index: 0, count: 1, data: <int>[1]);
      blob[0] = (MediaChunkCodec.version + 1) << 4;
      expect(MediaChunkCodec.parse(blob).refusal,
          MediaChunkRefusal.unknownVersion);
    });

    test('an unknown kind is refused rather than shown as an image', () {
      final Uint8List blob = MediaChunkCodec.encode(
          payloadId: 1, kind: MediaKind.image, index: 0, count: 1, data: <int>[1]);
      blob[1] = 9;
      expect(MediaChunkCodec.parse(blob).refusal,
          MediaChunkRefusal.unknownKind);
    });

    test('an index that cannot exist is refused', () {
      final Uint8List blob = MediaChunkCodec.encode(
          payloadId: 1, kind: MediaKind.image, index: 0, count: 1, data: <int>[1]);
      blob[9] = 3; // count = 3
      blob[7] = 3; // index = 3, outside a three-chunk payload
      expect(MediaChunkCodec.parse(blob).refusal,
          MediaChunkRefusal.indexOutOfRange);
    });

    test('a flipped payload byte is a crcMismatch, not a silent wrong frame',
        () {
      final Uint8List blob = MediaChunkCodec.encode(
          payloadId: 1,
          kind: MediaKind.image,
          index: 0,
          count: 1,
          data: <int>[10, 20, 30]);
      blob[13] ^= 0x01;
      expect(
          MediaChunkCodec.parse(blob).refusal, MediaChunkRefusal.crcMismatch);
    });
  });

  group('a resend is salted', () {
    test('the attempt nibble changes the packet and nothing else', () {
      final Uint8List first = MediaChunkCodec.encode(
          payloadId: 77,
          kind: MediaKind.image,
          index: 1,
          count: 2,
          data: <int>[5, 6, 7]);
      final Uint8List again = MediaChunkCodec.encode(
          payloadId: 77,
          kind: MediaKind.image,
          index: 1,
          count: 2,
          data: <int>[5, 6, 7],
          attempt: 3);
      expect(first[0] != again[0], isTrue,
          reason: 'the radio drops an identical packet, so a resend must differ');
      expect(first.sublist(1), again.sublist(1));
      expect(MediaChunkCodec.parse(again).chunk!.attempt, 3);
      expect(MediaChunkCodec.parse(again).chunk!.isResend, isTrue);
      expect(MediaChunkCodec.parse(first).chunk!.isResend, isFalse);
    });

    test('the attempt field refuses a sixteenth resend', () {
      expect(
          () => MediaChunkCodec.encode(
              payloadId: 1,
              kind: MediaKind.image,
              index: 0,
              count: 1,
              data: <int>[1],
              attempt: MediaChunkCodec.maxAttempt + 1),
          throwsArgumentError);
    });
  });
}
