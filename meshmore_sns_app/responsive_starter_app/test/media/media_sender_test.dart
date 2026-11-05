// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';

import 'package:meshmore_sns_app/media/media_chunk.dart';
import 'package:meshmore_sns_app/media/media_send_policy.dart';
import 'package:meshmore_sns_app/media/media_sender.dart';

void main() {
  group('pacing is the clock\'s, not the wall clock\'s', () {
    test('one chunk per 350 ms and no burst', () {
      DateTime now = DateTime.utc(2026, 11, 5, 12);
      final List<Uint8List> chunks = MediaChunkCodec.split(
        List<int>.filled(450, 3),
        payloadId: 1,
        kind: MediaKind.image,
      );
      final MediaSender s = MediaSender(chunks: chunks, clock: () => now);
      expect(s.takeDue().length, 1);
      expect(s.takeDue(), isEmpty,
          reason: 'the interval has not elapsed in the same tick');
      now = now.add(const Duration(milliseconds: 349));
      expect(s.takeDue(), isEmpty);
      now = now.add(const Duration(milliseconds: 1));
      expect(s.takeDue().length, 1);
    });

    test('an accepted chunk leaves the queue, and the receipt accounts for it',
        () {
      DateTime now = DateTime.utc(2026, 11, 5, 12);
      final MediaSender s = MediaSender(
        chunks: MediaChunkCodec.split(List<int>.filled(100, 1),
            payloadId: 2, kind: MediaKind.voice),
        clock: () => now,
      );
      while (!s.complete) {
        for (final MediaSend send in s.takeDue()) {
          s.acknowledge(send.index, MediaSendResult.accepted);
        }
        now = now.add(s.pacing);
      }
      final MediaReceipt? r = s.receipt;
      expect(r, isNotNull);
      expect(r!.chunks, s.chunkCount);
      expect(r.resends, 0);
      expect(r.elapsed, greaterThan(Duration.zero));
    });
  });

  group('the loop knows how long to wait instead of spinning', () {
    test('the wait is the pacing interval that is still to run', () {
      DateTime now = DateTime.utc(2026, 11, 5, 12);
      final MediaSender s = MediaSender(
        chunks: MediaChunkCodec.split(List<int>.filled(450, 3),
            payloadId: 11, kind: MediaKind.image),
        clock: () => now,
      );
      expect(s.waitBeforeDue, Duration.zero,
          reason: 'nothing has gone out, so the first chunk is due now');
      s.takeDue();
      expect(s.waitBeforeDue, s.pacing);
      now = now.add(const Duration(milliseconds: 200));
      expect(s.waitBeforeDue, const Duration(milliseconds: 150));
      now = now.add(const Duration(milliseconds: 150));
      expect(s.waitBeforeDue, Duration.zero);
    });

    test('a full table outranks the pacing: the longer wait wins', () {
      DateTime now = DateTime.utc(2026, 11, 5, 12);
      final MediaSender s = MediaSender(
        chunks: MediaChunkCodec.split(List<int>.filled(200, 1),
            payloadId: 12, kind: MediaKind.image),
        clock: () => now,
      );
      final MediaSend first = s.takeDue().single;
      s.acknowledge(first.index, MediaSendResult.tableFull);
      // 2 s of backoff against 350 ms of pacing: the backoff is what the loop
      // must sleep, or it wakes four times to learn nothing.
      expect(s.waitBeforeDue, s.tableFullBackoff);
    });

    test('a finished transfer has nothing to wait for', () {
      DateTime now = DateTime.utc(2026, 11, 5, 12);
      final MediaSender s = MediaSender(
        chunks: MediaChunkCodec.split(List<int>.filled(30, 1),
            payloadId: 13, kind: MediaKind.image),
        clock: () => now,
      );
      while (!s.complete) {
        for (final MediaSend send in s.takeDue()) {
          s.acknowledge(send.index, MediaSendResult.accepted);
        }
        now = now.add(s.pacing);
      }
      expect(s.waitBeforeDue, Duration.zero);
    });
  });

  group('table full is capacity, not loss', () {
    test('a full table pauses the sender and keeps the chunk', () {
      DateTime now = DateTime.utc(2026, 11, 5, 12);
      final MediaSender s = MediaSender(
        chunks: MediaChunkCodec.split(List<int>.filled(200, 1),
            payloadId: 3, kind: MediaKind.image),
        clock: () => now,
      );
      final MediaSend first = s.takeDue().single;
      s.acknowledge(first.index, MediaSendResult.tableFull);
      expect(s.failed, isFalse);
      expect(s.pending, contains(first.index));
      expect(s.paused, isTrue);
      now = now.add(const Duration(milliseconds: 500));
      expect(s.takeDue(), isEmpty,
          reason: 'still inside the backoff, even though the pacing elapsed');
      now = now.add(const Duration(seconds: 2));
      expect(s.takeDue().single.index, first.index);
      expect(s.complete, isFalse);
    });

    test('a refusal is an attempt: the resend is salted and finite', () {
      DateTime now = DateTime.utc(2026, 11, 5, 12);
      final List<Uint8List> chunks = MediaChunkCodec.split(List<int>.filled(40, 1),
          payloadId: 4, kind: MediaKind.image);
      final MediaSender s = MediaSender(chunks: chunks, clock: () => now);
      final MediaSend first = s.takeDue().single;
      final MediaChunk parsed = MediaChunkCodec.parse(first.blob).chunk!;
      final Uint8List salted =
          s.resendOf(first.index, parsed);
      expect(salted[0] != first.blob[0], isTrue);
      expect(MediaChunkCodec.parse(salted).chunk!.attempt, 1);

      // Past the salt space the chunk is reported lost, never looped.
      for (int i = 0; i <= MediaChunkCodec.maxAttempt; i++) {
        s.acknowledge(first.index, MediaSendResult.refused);
        now = now.add(s.pacing);
      }
      expect(s.failed, isTrue);
      expect(s.lost, contains(first.index));
      expect(
        () => s.resendOf(first.index, parsed),
        throwsStateError,
      );
    });
  });

  group('the paced retry is the salted packet, not the same bytes again', () {
    test('a refused chunk goes back out with a new attempt nibble', () {
      DateTime now = DateTime.utc(2026, 11, 5, 12);
      final MediaSender s = MediaSender(
        chunks: MediaChunkCodec.split(List<int>.filled(300, 1),
            payloadId: 7, kind: MediaKind.image),
        clock: () => now,
      );
      final MediaSend first = s.takeDue().single;
      expect(first.isResend, isFalse);
      s.acknowledge(first.index, MediaSendResult.refused);
      now = now.add(s.pacing);
      final MediaSend retry = s.takeDue().single;
      expect(retry.index, first.index);
      expect(retry.attempt, 1);
      expect(retry.isResend, isTrue);
      // The radio drops a packet it has already seen, so an identical retry is
      // never heard. The header differs; the payload does not.
      expect(retry.blob[0] != first.blob[0], isTrue);
      expect(retry.blob.sublist(1), first.blob.sublist(1));
      final MediaChunk parsed = MediaChunkCodec.parse(retry.blob).chunk!;
      expect(parsed.attempt, 1);
      expect(parsed.payloadId, 7);
      expect(parsed.index, first.index);
    });
  });

  group('media is off on Public, at the send path', () {
    test('the well-known channel is refused by default', () {
      const MediaSendPolicy policy = MediaSendPolicy();
      expect(
        policy.refusalFor(channelPsk: kPublicChannelPsk, payloadBytes: 10),
        MediaSendRefusal.mediaOffOnPublic,
      );
    });

    test('an explicit opt-in allows it, and a private channel never needed one',
        () {
      const MediaSendPolicy on = MediaSendPolicy(mediaOnPublic: true);
      expect(on.refusalFor(channelPsk: kPublicChannelPsk, payloadBytes: 10),
          isNull);
      const MediaSendPolicy off = MediaSendPolicy();
      expect(
          off.refusalFor(
              channelPsk: List<int>.filled(16, 0x42), payloadBytes: 10),
          isNull);
    });

    test('the channel is identified by its secret, not its name', () {
      expect(MediaSendPolicy.isPublicChannel(kPublicChannelPsk), isTrue);
      final List<int> renamed = List<int>.of(kPublicChannelPsk);
      renamed[0] ^= 0xFF;
      expect(MediaSendPolicy.isPublicChannel(renamed), isFalse);
    });

    test('an unknown channel and an empty payload are their own refusals', () {
      const MediaSendPolicy policy = MediaSendPolicy(mediaOnPublic: true);
      expect(policy.refusalFor(channelPsk: null, payloadBytes: 10),
          MediaSendRefusal.channelUnknown);
      expect(policy.refusalFor(channelPsk: kPublicChannelPsk, payloadBytes: 0),
          MediaSendRefusal.payloadUnusable);
    });
  });
}
