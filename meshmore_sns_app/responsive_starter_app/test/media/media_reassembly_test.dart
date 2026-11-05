// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/media/media_chunk.dart';
import 'package:meshmore_sns_app/media/media_reassembly.dart';

MediaChunk chunk(int id, int index, int count,
        {int attempt = 0, MediaKind kind = MediaKind.image, int fill = 1}) =>
    MediaChunk(
      payloadId: id,
      kind: kind,
      index: index,
      count: count,
      attempt: attempt,
      data: Uint8List.fromList(<int>[fill, index & 0xFF]),
    );

void main() {
  final DateTime t0 = DateTime.utc(2026, 11, 5, 12);

  test('chunks arriving out of order complete once the last hole is filled',
      () {
    final MediaReassembler r = MediaReassembler();
    expect(r.add(chunk(1, 2, 3), now: t0), isNull);
    expect(r.add(chunk(1, 0, 3), now: t0), isNull);
    final MediaTransfer? done = r.add(chunk(1, 1, 3), now: t0);
    expect(done, isNotNull);
    expect(done!.assemble(), <int>[1, 0, 1, 1, 1, 2]);
  });

  test('a duplicate is refused by name and does not disturb the transfer', () {
    final MediaReassembler r = MediaReassembler();
    r.add(chunk(1, 0, 2), now: t0);
    expect(r.add(chunk(1, 0, 2, attempt: 4), now: t0), isNull);
    expect(r.lastRefusal, MediaReassemblyRefusal.duplicate);
    expect(r.transfer(1)!.received, 1);
  });

  test('the missing list is exactly the holes, ascending', () {
    final MediaReassembler r = MediaReassembler();
    r.add(chunk(1, 3, 5), now: t0);
    r.add(chunk(1, 1, 5), now: t0);
    expect(r.transfer(1)!.missing, <int>[0, 2, 4]);
  });

  test('a chunk of a different kind for the same id is a conflict', () {
    final MediaReassembler r = MediaReassembler();
    r.add(chunk(1, 0, 2), now: t0);
    r.add(chunk(1, 1, 2, kind: MediaKind.voice), now: t0);
    expect(r.lastRefusal, MediaReassemblyRefusal.conflictingTransfer);
    expect(r.transfer(1)!.received, 1);
  });

  test('a seventeenth transfer evicts the one quiet longest', () {
    final MediaReassembler r = MediaReassembler();
    for (int id = 1; id <= 16; id++) {
      r.add(chunk(id, 0, 2), now: t0);
    }
    // Touch transfer 1 so transfer 2 becomes the quietest.
    r.add(chunk(1, 1, 2), now: t0.add(const Duration(seconds: 1)));
    r.add(chunk(17, 0, 2), now: t0.add(const Duration(seconds: 2)));
    expect(r.transfer(2), isNull);
    expect(r.evicted, <int>[2]);
    expect(r.transfer(1), isNotNull);
    expect(r.transfer(17), isNotNull);
  });

  test('a replayed chunk after completion cannot re-arm the payload', () {
    final MediaReassembler r = MediaReassembler();
    r.add(chunk(1, 0, 1), now: t0);
    r.forget(1);
    expect(r.add(chunk(1, 0, 1), now: t0), isNull);
    expect(r.lastRefusal, MediaReassemblyRefusal.duplicate);
    expect(r.transfer(1), isNull,
        reason: 'the dedupe window outlives the transfer, by design');
  });

  test('the dedupe window keeps the last 160 slots, not all of them', () {
    final MediaReassembler r = MediaReassembler(dedupeWindow: 160);
    // 160 distinct fills of one transfer slot set, one chunk each.
    for (int i = 0; i < 161; i++) {
      r.add(
        MediaChunk(
          payloadId: i,
          kind: MediaKind.image,
          index: 0,
          count: 1,
          attempt: 0,
          data: Uint8List(1),
        ),
        now: t0,
      );
      r.forget(i);
    }
    // Slot 0 fell out of the 160-long window, so it can be seen again.
    expect(r.hasSeen(0, 0), isFalse);
    expect(r.hasSeen(160, 0), isTrue);
  });

  test('an FEC-restored chunk completes through the same path', () {
    final MediaReassembler r = MediaReassembler();
    r.add(chunk(1, 0, 2), now: t0);
    final MediaTransfer t = r.transfer(1)!;
    t.restore(1, Uint8List.fromList(<int>[1, 1]), now: t0);
    expect(t.complete, isTrue);
    expect(t.assemble(), <int>[1, 0, 1, 1]);
  });
}
