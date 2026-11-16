// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/media/media_fetch.dart';

/// The fetch plane: a request that names the requester, and records that fit
/// one raw frame.
void main() {
  group('the request names the requester', () {
    test('round trips an id and a key', () {
      const String key =
          'aabbccdd11223344556677889900aabbccddeeff00112233445566778899aabb';
      final String line = MediaFetchRequest.encode(42, key);
      expect(line, '[IMG1:42:aabbccdd11223344]');
      final ({int id, String requesterHex})? out =
          MediaFetchRequest.decode(line);
      expect(out, isNotNull);
      expect(out!.id, 42);
      expect(out.requesterHex, 'aabbccdd11223344');
    });

    test('an ordinary channel message is not a request', () {
      expect(MediaFetchRequest.decode('morning!'), isNull);
      expect(MediaFetchRequest.decode('[IMG1:1]'), isNull);
      expect(MediaFetchRequest.decode('[IMG1:x:aabbccdd11223344]'), isNull);
      expect(MediaFetchRequest.decode('[IMG1:1:nothex!!]'), isNull);
      expect(MediaFetchRequest.decode('[IMG1:99999:aabbccdd11223344]'), isNull);
    });
  });

  group('records fit one raw frame and carry enough to place them', () {
    test('a record is one channel datagram at most', () {
      final List<Uint8List> records = MediaFetchCodec.split(
          id: 9, payload: Uint8List(MediaFetchCodec.sliceBytes));
      expect(records.single.length, lessThanOrEqualTo(163),
          reason: 'the same record has to fit a channel datagram and a raw '
              'record, so it is sized for the smaller of the two');
    });

    test('the framing is MeshPix\'s chunk packet', () {
      final List<Uint8List> records = MediaFetchCodec.split(
          id: 0x1234, payload: Uint8List(400));
      expect(records.length, greaterThan(1));
      expect(records.first[0], 0x4D, reason: "'M'");
      expect(records.first[1], 0x50, reason: "'P'");
      expect(records.first[2], 1, reason: 'version');
      expect(records.first[3] & 0x07, 1, reason: 'chunk kind');
      expect(records.first[4], 0x34, reason: 'transfer id low');
      expect(records.first[5], 0x12, reason: 'transfer id high');
      expect(records.first[6], 0, reason: 'sequence number');
      expect(records.first[7], records.length, reason: 'total');
    });

    test('splitting a payload produces records that reassemble exactly', () {
      final Uint8List payload = Uint8List.fromList(
          List<int>.generate(1000, (int i) => i & 0xFF));
      final List<Uint8List> records =
          MediaFetchCodec.split(id: 7, payload: payload);
      expect(records.length,
          (1000 + MediaFetchCodec.sliceBytes - 1) ~/ MediaFetchCodec.sliceBytes);

      final MediaFetchInbox inbox =
          MediaFetchInbox(id: 7, total: records.length);
      // Out of order and with a duplicate, which is what a mesh delivers.
      for (final Uint8List r in records.reversed) {
        final ({int id, int index, int total, Uint8List slice})? f =
            MediaFetchCodec.decode(r);
        expect(f, isNotNull);
        inbox.take(f!.index, f.slice);
      }
      final ({int id, int index, int total, Uint8List slice})? first =
          MediaFetchCodec.decode(records.first);
      expect(inbox.take(first!.index, first.slice), isFalse,
          reason: 'a duplicate costs nothing');
      expect(inbox.complete, isTrue);
      expect(inbox.assemble(), payload);
    });

    test('a gap is stated as indices, not as a restart', () {
      final MediaFetchInbox inbox = MediaFetchInbox(id: 3, total: 4);
      inbox.take(0, Uint8List(4));
      inbox.take(2, Uint8List(4));
      expect(inbox.missing, <int>[1, 3]);
      expect(inbox.complete, isFalse);
      expect(() => inbox.assemble(), throwsStateError);
    });

    test('a foreign record is refused, not mis-read', () {
      expect(MediaFetchCodec.decode(Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8])),
          isNull);
      expect(MediaFetchCodec.decode(Uint8List.fromList(<int>[0x4D, 0x46, 1, 0, 1, 0, 1])),
          isNull,
          reason: 'a record needs a slice after its header');
    });
  });
}
