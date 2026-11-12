// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/media/media_chunk.dart';
import 'package:meshmore_sns_app/media/media_codec.dart';
import 'package:meshmore_sns_app/media/media_sender.dart';
import 'package:meshmore_sns_app/media/media_transfer.dart';

/// D11.4: the encoder spends CPU to buy airtime.
///
/// A photo is 320×240 and the wire is one LoRa channel shared with every node in
/// range, paced at one datagram every 350 ms. The encoder's effort knob is
/// therefore the cheapest lever the app has: encoding once at speed 0 costs a
/// bounded amount of one phone's CPU, and every kilobyte it removes is about
/// seven datagrams of everybody's channel time. The default used to be 9, which
/// optimised the resource this app has most of and spent the one it has least.
/// The measured curve, and why 5 is the knee rather than 0, are in
/// `media_codec.dart` beside the setting itself.
///
/// These cases pin the decision and the arithmetic behind it, so a change to the
/// pacing, the payload size or the encoder default has to come with a re-read of
/// the reasoning rather than a silent drift.
void main() {
  test('the encoder effort sits at the knee of the measured curve', () {
    const AvifMediaCodec codec = AvifMediaCodec();
    expect(codec.speed, 5,
        reason: 'measured on this tree: speed 9 produced 1390 bytes for 7 ms, '
            'speed 5 produces 784 (44 % smaller) for 90 ms, and speed 0 '
            'produces 749 for 818 ms, so the last 35 bytes cost nine times the '
            'CPU and a frame that would freeze on a phone');
  });

  test(
      'the quantiser ladder walks from the good end to the ceiling and never '
      'past it', () {
    final List<(int, int)> ladder = AvifMediaCodec.quantiserLadder;
    expect(ladder.length, greaterThan(1));
    expect(ladder.first.$1, 18,
        reason: 'below about 20 the container and the AV1 headers dominate the '
            'file, so a smaller quantiser buys bytes that are not pixels');
    expect(ladder.last.$2, 63,
        reason:
            'libavif quantises 0-63, and the ceiling is the worst a picture '
            'may be made before it stops being one');
    for (int i = 0; i < ladder.length; i++) {
      final (int minQ, int maxQ) = ladder[i];
      expect(minQ, lessThanOrEqualTo(maxQ),
          reason: 'a step with max below min asks libavif for an impossible '
              'range');
      expect(maxQ, lessThanOrEqualTo(63));
      if (i > 0) {
        expect(minQ, greaterThan(ladder[i - 1].$1),
            reason: 'each step must cost quality, or the ladder cannot make '
                'progress towards fitting the budget');
      }
    }
  });

  test('the airtime arithmetic the encoder decision rests on still holds', () {
    // One datagram every 350 ms, `maxDataBytes` of payload each — the sender's
    // default pacing and the chunk geometry below are what the comment in
    // `media_codec.dart` counts with.
    final MediaSender sender =
        MediaSender(chunks: <Uint8List>[], clock: _clock);
    expect(sender.pacing, const Duration(milliseconds: 350));
    expect(MediaChunkCodec.maxDataBytes, 150);

    // The default send size, not the largest one: the budget the app actually
    // spends is the number this comment is about.
    final int datagrams =
        MediaSendSize.standard.budgetBytes ~/ MediaChunkCodec.maxDataBytes;
    final Duration airtime = sender.pacing * datagrams;
    expect(datagrams, 10);
    expect(airtime.inSeconds, 3,
        reason: 'a default photo is about three seconds of channel time at the '
            'sender pacing, against nine for the old 4096-byte budget');
    // And the largest size stays as large as it was, so a reader who needs the
    // detail can still ask for it.
    expect(MediaSendSize.full.budgetBytes, 4096);
  });
}

DateTime _clock() => DateTime.utc(2026);
