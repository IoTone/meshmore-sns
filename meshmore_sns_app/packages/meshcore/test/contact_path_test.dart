// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:test/test.dart';

Contact _c(int outPathLen, List<int> path) => Contact(
      publicKey: Uint8List(32),
      type: 1,
      flags: 0,
      outPathLen: outPathLen,
      outPath: Uint8List(64)..setRange(0, path.length, path),
      name: 'x',
      lastAdvertTimestamp: 0,
      latitudeMicros: 0,
      longitudeMicros: 0,
      lastMod: 0,
    );

void main() {
  group('Contact.activePath decodes out_path_len (Packet.cpp:20-30)', () {
    test('one-byte hashes: hop count is the byte count', () {
      expect(_c(3, <int>[1, 2, 3, 9]).activePath, <int>[1, 2, 3]);
    });

    test('zero hops is an empty path (a direct neighbour)', () {
      expect(_c(0, <int>[]).activePath, isEmpty);
    });

    test('0xFF is "no path", not a 64-byte chain', () {
      expect(_c(0xFF, List<int>.filled(64, 7)).activePath, isEmpty);
    });

    test('two-byte hashes: 3 hops are 6 bytes', () {
      // 0x40 | 3: hash size 2, 3 hops.
      expect(_c(0x43, <int>[1, 2, 3, 4, 5, 6, 9, 9]).activePath,
          <int>[1, 2, 3, 4, 5, 6]);
    });

    test('three-byte hashes: 2 hops are 6 bytes', () {
      expect(_c(0x82, <int>[1, 2, 3, 4, 5, 6, 9]).activePath,
          <int>[1, 2, 3, 4, 5, 6]);
    });

    test('an impossible length is clamped to the buffer, never thrown', () {
      // 3-byte hashes x 63 hops = 189 > 64.
      expect(_c(0x80 | 63, List<int>.filled(64, 1)).activePath, hasLength(64));
    });
  });
}
