// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/screens/diagnostics_redaction.dart';

/// A copied frame log must not carry anyone's position.
///
/// The copy button is offered for a public issue tracker and the redaction class
/// says a node key and a position must not leave the screen, but only the channel
/// secret was masked. A self-info frame carries the operator's own fix, and a
/// contact or advert frame carries a peer's — both in hex, both meant for strangers.
void main() {
  /// One frame: opcode, then [payload] as hex.
  String frame(int opcode, List<int> payload) =>
      <int>[opcode, ...payload]
          .map((int b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

  List<int> littleEndianMicros(double degrees) {
    final int v = (degrees * 1e6).round();
    return <int>[
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
    ];
  }

  const DiagnosticsRedaction redaction = DiagnosticsRedaction();

  test('a self-info frame loses its own fix and keeps everything else', () {
    final String original = frame(0x05, <int>[
      2, 20, 30, // advType, txPower, maxTxPower
      ...List<int>.filled(32, 0xAB), // public key
      ...littleEndianMicros(38.91996), // latitude
      ...littleEndianMicros(-104.77320), // longitude
      1, 0, 0, 0, // multiAcks, locPolicy, telemetry, manualAdd
      915000000 & 0xFF, 0x8E, 0x8B, 0x36, // frequency
    ]);
    final String masked = redaction.frame(original);

    expect(masked.length, original.length,
        reason: 'the frame stays replayable at the same length');
    expect(masked.startsWith('05'), isTrue);
    // Bytes 36..44 — the two coordinates — are zeroed.
    expect(masked.substring(36 * 2, 44 * 2), '0' * 16);
    // The key and the radio settings are untouched: they are the evidence.
    expect(masked.substring(8, 72), original.substring(8, 72));
    expect(masked.substring(44 * 2), original.substring(44 * 2));
  });

  test('a contact frame loses the peer position and keeps the key', () {
    final String original = frame(0x03, <int>[
      ...List<int>.filled(32, 0x11), // public key
      2, 1, 0, // type, flags, pathLen
      ...List<int>.filled(64, 0x22), // out path
      ...List<int>.filled(32, 0x00), // name
      0x10, 0x20, 0x30, 0x40, // advert timestamp
      ...littleEndianMicros(47.61), // latitude
      ...littleEndianMicros(-122.33), // longitude
      9, 9, 9, 9, // lastMod
    ]);
    final String masked = redaction.frame(original);
    expect(masked.substring(136 * 2, 144 * 2), '0' * 16);
    expect(masked.substring(0, 136 * 2), original.substring(0, 136 * 2));
    expect(masked.substring(144 * 2), original.substring(144 * 2));
  });

  test('a frame with no position is left alone', () {
    final String original = frame(0x19, <int>[1, 2, 3, 4]);
    expect(redaction.frame(original), original);
  });

  test('a truncated frame is not mangled', () {
    // A self-info header with no room for coordinates: leave it as captured
    // rather than slicing past the end.
    final String short = frame(0x05, List<int>.filled(20, 0x00));
    expect(redaction.frame(short), short);
  });
}
