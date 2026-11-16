// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/media/aeic/aeic_chunk.dart';

Uint8List _bytes(int n, {int seed = 7}) =>
    Uint8List.fromList(List<int>.generate(n, (int i) => (i * 31 + seed) & 0xFF));

void main() {
  group('the numbers the format is built on', () {
    test('a blob is 163 bytes and the header is 4 of them', () {
      expect(kAeicChunkBlobBytes, 163);
      expect(kAeicChunkHeaderBytes, 4);
      expect(kAeicChunkBodyBytes, 158);
      expect(kAeicFirstChunkCapacity, 157);
      expect(kAeicChunkCapacity, 158);
    });

    test('the shipping rate point fits one or two chunks', () {
      // The measured corpus: 110 to 209 bytes, mean 155.8.
      expect(aeicDataChunkCount(110), 1);
      expect(aeicDataChunkCount(156), 1);
      expect(aeicDataChunkCount(157), 1);
      expect(aeicDataChunkCount(158), 2);
      expect(aeicDataChunkCount(209), 2);
      expect(aeicDataChunkCount(kAeicMaxPayloadBytes), kAeicMaxDataChunks);
    });

    test('the canopy is fifteen data chunks', () {
      expect(kAeicMaxPayloadBytes,
          kAeicFirstChunkCapacity + 14 * kAeicChunkCapacity);
      expect(() => buildAeicChunks(
            payload: _bytes(kAeicMaxPayloadBytes + 1),
            metadata: const AeicStreamMetadata(rate: AeicRate.standard),
            senderPrefix: 1,
            imageId: 1,
          ), throwsArgumentError);
    });
  });

  group('the metadata byte', () {
    test('round-trips every rate, size and aspect the format can name', () {
      for (final AeicRate rate in AeicRate.values) {
        for (final int size in kAeicResolutionCodes) {
          for (int aspect = 0; aspect < 16; aspect++) {
            final AeicStreamMetadata m = AeicStreamMetadata(
                rate: rate, squareSize: size, aspectCode: aspect);
            expect(AeicStreamMetadata.decode(m.encode()), m,
                reason: '${rate.name} $size $aspect');
          }
        }
      }
    });

    test('a code this build cannot name decodes to null, not to a guess', () {
      // The rate field is two bits, so 2 and 3 are not rates.
      expect(AeicStreamMetadata.decode(0x02), isNull);
      expect(AeicStreamMetadata.decode(0x03), isNull);
    });

    test('a size outside the table is refused rather than truncated', () {
      expect(
          () => const AeicStreamMetadata(rate: AeicRate.standard, squareSize: 999)
              .encode(),
          throwsArgumentError);
    });

    test('an aspect snaps to the nearest shape, and gives up when it cannot',
        () {
      expect(aeicAspectCodeFor(512, 512), 0);
      expect(kAeicAspectCodes[aeicAspectCodeFor(4000, 3000)], <int>[4, 3]);
      expect(kAeicAspectCodes[aeicAspectCodeFor(3000, 4000)], <int>[3, 4]);
      expect(kAeicAspectCodes[aeicAspectCodeFor(1920, 1080)], <int>[16, 9]);
      // A panorama is not one of the shapes, and guessing 21:9 would letterbox
      // it wrongly.
      expect(aeicAspectCodeFor(3000, 400), kAeicAspectUnknown);
      expect(aeicAspectCodeFor(0, 0), kAeicAspectUnknown);
    });
  });

  group('chunks on the air', () {
    test('a one-chunk picture is two blobs with parity', () {
      final Uint8List payload = _bytes(120);
      final AeicChunkSet set = buildAeicChunks(
        payload: payload,
        metadata: const AeicStreamMetadata(rate: AeicRate.standard),
        senderPrefix: 0xBEEF,
        imageId: 9,
      );
      expect(set.dataChunkCount, 1);
      expect(set.blobs.length, 2);
      expect(set.blobs.first.length, 4 + 1 + 120);
      // The header is the sender, the id and index/total in one byte.
      expect(set.blobs.first.sublist(0, 4), <int>[0xBE, 0xEF, 9, 0x01]);
      expect(set.blobs.last.sublist(0, 4), <int>[0xBE, 0xEF, 9, 0x11]);
      // Every blob fits what the radio carries.
      for (final Uint8List b in set.blobs) {
        expect(b.length, lessThanOrEqualTo(kAeicChunkBlobBytes));
      }
    });

    test('a picture that needs two data chunks says so in every header', () {
      final AeicChunkSet set = buildAeicChunks(
        payload: _bytes(300),
        metadata: const AeicStreamMetadata(rate: AeicRate.standard),
        senderPrefix: 1,
        imageId: 2,
        parity: false,
      );
      expect(set.dataChunkCount, 2);
      expect(set.blobs.length, 2);
      expect(set.blobs[0][3], 0x02); // index 0 of 2
      expect(set.blobs[1][3], 0x12); // index 1 of 2
    });
  });

  group('reassembly', () {
    test('the picture comes back byte for byte, with its metadata', () {
      final Uint8List payload = _bytes(300, seed: 3);
      const AeicStreamMetadata metadata = AeicStreamMetadata(
          rate: AeicRate.standard, aspectCode: 5);
      final AeicChunkSet set = buildAeicChunks(
        payload: payload,
        metadata: metadata,
        senderPrefix: 0x1234,
        imageId: 4,
        parity: false,
      );
      final AeicReassembler r = AeicReassembler();
      AeicChunkStatus status = AeicChunkStatus.incomplete;
      for (final Uint8List blob in set.blobs) {
        status = r.accept(
            blob: blob, channelIndex: 0, ownSenderPrefix: 0xFFFF);
      }
      expect(status, AeicChunkStatus.completed);
      expect(r.lastPicture!.bytes, payload);
      expect(r.lastPicture!.metadata, metadata);
      expect(r.lastPicture!.recovered, isFalse);
      expect(r.pendingCount, 0);
    });

    test('one lost chunk is rebuilt from the parity blob', () {
      final Uint8List payload = _bytes(300, seed: 11);
      final AeicChunkSet set = buildAeicChunks(
        payload: payload,
        metadata: const AeicStreamMetadata(rate: AeicRate.standard),
        senderPrefix: 0x2222,
        imageId: 7,
      );
      // Drop the first data chunk, the one that carries the metadata byte.
      final List<Uint8List> received = <Uint8List>[
        set.blobs[1],
        set.blobs[2],
      ];
      final AeicReassembler r = AeicReassembler();
      AeicChunkStatus status = AeicChunkStatus.incomplete;
      for (final Uint8List blob in received) {
        status = r.accept(
            blob: blob, channelIndex: 3, ownSenderPrefix: 0xFFFF);
      }
      expect(status, AeicChunkStatus.parityMatched);
      expect(r.lastPicture!.bytes, payload);
      expect(r.lastPicture!.recovered, isTrue);
    });

    test('our own transmission is ignored', () {
      final AeicChunkSet set = buildAeicChunks(
        payload: _bytes(50),
        metadata: const AeicStreamMetadata(rate: AeicRate.standard),
        senderPrefix: 0xABCD,
        imageId: 1,
        parity: false,
      );
      final AeicReassembler r = AeicReassembler();
      expect(
          r.accept(
              blob: set.blobs.first,
              channelIndex: 0,
              ownSenderPrefix: 0xABCD),
          AeicChunkStatus.refused);
      expect(r.pendingCount, 0);
    });

    test('two senders on one channel do not mix', () {
      final Uint8List a = _bytes(200, seed: 1);
      final Uint8List b = _bytes(200, seed: 2);
      final AeicChunkSet sa = buildAeicChunks(
        payload: a,
        metadata: const AeicStreamMetadata(rate: AeicRate.standard),
        senderPrefix: 0x1111,
        imageId: 5,
        parity: false,
      );
      final AeicChunkSet sb = buildAeicChunks(
        payload: b,
        metadata: const AeicStreamMetadata(rate: AeicRate.standard),
        senderPrefix: 0x2222,
        imageId: 5,
        parity: false,
      );
      final AeicReassembler r = AeicReassembler();
      for (final Uint8List blob in sa.blobs) {
        r.accept(blob: blob, channelIndex: 1, ownSenderPrefix: 0xFFFF);
      }
      final AeicPicture? first = r.lastPicture;
      for (final Uint8List blob in sb.blobs) {
        r.accept(blob: blob, channelIndex: 1, ownSenderPrefix: 0xFFFF);
      }
      expect(first!.bytes, a);
      expect(r.lastPicture!.bytes, b);
    });

    test('a stale half-picture is abandoned rather than held forever', () {
      final AeicChunkSet set = buildAeicChunks(
        payload: _bytes(300),
        metadata: const AeicStreamMetadata(rate: AeicRate.standard),
        senderPrefix: 0x3333,
        imageId: 8,
        parity: false,
      );
      final AeicReassembler r = AeicReassembler();
      final DateTime t0 = DateTime(2026, 11, 16, 12);
      r.accept(
          blob: set.blobs.first,
          channelIndex: 0,
          ownSenderPrefix: 0xFFFF,
          now: t0);
      expect(r.pendingCount, 1);
      r.accept(
          blob: set.blobs.last,
          channelIndex: 0,
          ownSenderPrefix: 0xFFFF,
          now: t0.add(kAeicReassemblyTtl + const Duration(seconds: 1)));
      // The old half was evicted, so this chunk starts a new picture that is
      // still incomplete.
      expect(r.pendingCount, 1);
      expect(r.lastPicture, isNull);
    });

    test('a header that cannot describe a chunk is refused', () {
      final AeicReassembler r = AeicReassembler();
      expect(
          r.accept(
              blob: Uint8List.fromList(<int>[1, 2]),
              channelIndex: 0,
              ownSenderPrefix: 0),
          AeicChunkStatus.refused);
      // total 0 is not a chunk.
      expect(
          r.accept(
              blob: Uint8List.fromList(<int>[1, 2, 3, 0x00]),
              channelIndex: 0,
              ownSenderPrefix: 0),
          AeicChunkStatus.refused);
      // index 5 of 4: there is no such chunk.
      expect(
          r.accept(
              blob: Uint8List.fromList(<int>[1, 2, 3, 0x54]),
              channelIndex: 0,
              ownSenderPrefix: 0),
          AeicChunkStatus.refused);
    });
  });
}
