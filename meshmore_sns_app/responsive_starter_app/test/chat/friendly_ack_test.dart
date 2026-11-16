// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart' show ChannelTextLimits;
import 'package:meshmore_sns_app/chat/friendly_ack.dart';

/// A friendly acknowledgement is a plain text line in a format other clients
/// parse, so its exact shape is a compatibility surface rather than a style.
///
/// The reference line, taken from a real report in the public channel and from
/// the shape the Colorado Mesh client parses:
///
///     ack: SNR 12.5 dB, RSSI -38 dBm, 3 hops via 4490, DF7C, 7F47
void main() {
  String line({
    String? sender = 'Half Live',
    double? snr = 12.5,
    int? rssi = -38,
    int? hops = 3,
    List<String> path = const <String>['4490', 'DF7C', '7F47'],
    bool flood = false,
    int maxBytes = 160,
  }) =>
      friendlyAckLine(
        sender: sender,
        snrDb: snr,
        rssiDbm: rssi,
        hopCount: hops,
        pathHashes: path,
        isFlood: flood,
        maxBytes: maxBytes,
      );

  test('the full report matches the format the ecosystem reads', () {
    expect(line(),
        '@[Half Live] ack: SNR 12.5 dB, RSSI -38 dBm, 3 hops via 4490, DF7C, 7F47');
  });

  test('a direct message carries no mention, because it already says who sent it',
      () {
    expect(line(sender: null),
        'ack: SNR 12.5 dB, RSSI -38 dBm, 3 hops via 4490, DF7C, 7F47');
  });

  test('one hop is not "1 hops"', () {
    expect(line(sender: null, hops: 1, path: <String>['4490']),
        'ack: SNR 12.5 dB, RSSI -38 dBm, 1 hop via 4490');
  });

  test('a flood with no captured path says flood rather than a made-up count', () {
    expect(line(sender: null, hops: null, path: const <String>[], flood: true),
        'ack: SNR 12.5 dB, RSSI -38 dBm, flood');
  });

  test('the route is dropped as a whole before the measurements are', () {
    // A long name and three 3-byte hashes do not fit a channel message: the
    // report keeps its numbers and loses the route, which is the order the other
    // clients drop things in.
    final String tight = line(maxBytes: 70);
    expect(tight, isNot(contains('via')));
    expect(tight, contains('SNR 12.5 dB'));
    expect(tight, contains('RSSI -38 dBm'));
    expect(ChannelTextLimits.bytesOf(tight), lessThanOrEqualTo(70));
  });

  test('RSSI goes before SNR, and the receipt is the floor', () {
    // 45 bytes holds the mention and the SNR but not the RSSI clause.
    final String noRssi = line(maxBytes: 45);
    expect(noRssi, isNot(contains('RSSI')));
    expect(noRssi, contains('SNR'));
    expect(ChannelTextLimits.bytesOf(noRssi), lessThanOrEqualTo(45));

    // Nothing measurable at all: the line says only that it was received.
    expect(line(sender: null, snr: null, rssi: null, hops: null, path: const <String>[]),
        'ack: received');
  });

  test('every candidate fits the byte budget it was given', () {
    for (int budget = 5; budget <= 160; budget += 5) {
      final String l = line(maxBytes: budget);
      expect(ChannelTextLimits.bytesOf(l), lessThanOrEqualTo(budget),
          reason: 'at $budget bytes the line was ${ChannelTextLimits.bytesOf(l)}');
    }
  });

  test('a row with nothing measured is not offered the action', () {
    expect(
        canFriendlyAck(
            outgoing: false, snrDb: null, hopCount: null, pathHashes: const <String>[]),
        isFalse);
    // Our own rows are never answered: we did not receive them.
    expect(
        canFriendlyAck(
            outgoing: true, snrDb: 12, hopCount: 2, pathHashes: const <String>['4490']),
        isFalse);
    expect(
        canFriendlyAck(
            outgoing: false, snrDb: 12, hopCount: null, pathHashes: const <String>[]),
        isTrue);
    expect(
        canFriendlyAck(
            outgoing: false, snrDb: null, hopCount: 3, pathHashes: const <String>[]),
        isTrue);
  });
}
