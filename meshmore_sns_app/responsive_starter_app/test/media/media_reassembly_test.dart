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
    // Named for what it is: the payload is done, not merely seen twice.
    expect(r.lastRefusal, MediaReassemblyRefusal.alreadyCompleted);
    expect(r.transfer(1), isNull,
        reason: 'the completion memory outlives the transfer, by design');
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

  test('a replay after the window moved on is refused, not reassembled twice',
      () {
    final MediaReassembler r = MediaReassembler();
    expect(r.add(chunk(1, 0, 1), now: t0), isNotNull);
    r.forget(1);
    // Push the completed payload's slot out of the dedupe window.
    for (int i = 2; i <= 200; i++) {
      r.add(chunk(i, 0, 1), now: t0);
      r.forget(i);
    }
    expect(r.hasSeen(1, 0), isFalse,
        reason: 'the window has moved on, which is the whole problem');
    final int before = r.completions;
    expect(r.add(chunk(1, 0, 1), now: t0), isNull);
    expect(r.lastRefusal, MediaReassemblyRefusal.alreadyCompleted);
    expect(r.completions, before,
        reason: 'the payload completed once, not twice');
    expect(r.transfer(1), isNull);
  });

  test('a count larger than the pool can hold is refused by name', () {
    final MediaReassembler r = MediaReassembler();
    expect(r.add(chunk(1, 0, MediaReassembler.maxChunks + 1), now: t0), isNull);
    expect(r.lastRefusal, MediaReassemblyRefusal.countTooLarge);
    expect(r.transfers, isEmpty,
        reason: 'an untrusted count must not size the pool');
    expect(r.add(chunk(1, 0, MediaReassembler.maxChunks), now: t0), isNull);
    expect(r.transfer(1), isNotNull);
  });

  test('the completion memory is bounded, and the bound is the stated one', () {
    final MediaReassembler r = MediaReassembler();
    for (int id = 1; id <= MediaReassembler.completedMemory; id++) {
      r.add(chunk(id, 0, 1), now: t0);
      r.forget(id);
    }
    // The newest completion is still remembered, so its replay is refused.
    expect(r.add(chunk(MediaReassembler.completedMemory, 0, 1), now: t0), isNull);
    expect(r.lastRefusal, MediaReassemblyRefusal.alreadyCompleted);
    // One more completion pushes the oldest out: that is the documented bound,
    // and it is why the memory is sized for a session rather than a moment.
    r.add(chunk(MediaReassembler.completedMemory + 1, 0, 1), now: t0);
    expect(r.add(chunk(1, 0, 1), now: t0), isNotNull,
        reason: 'past the memory, a replay is new traffic again');
  });

  test('evictions are remembered, and the remembered list is bounded', () {
    final MediaReassembler r = MediaReassembler();
    // 56 transfers through a 16-slot pool is 40 evictions.
    for (int id = 1; id <= 56; id++) {
      r.add(chunk(id, 0, 2), now: t0);
    }
    expect(r.evictions, 40);
    expect(r.evicted.length, MediaReassembler.evictionMemory);
    expect(r.evicted.last, 40, reason: 'the list keeps the most recent');
    expect(r.transfers.length, 16);
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
