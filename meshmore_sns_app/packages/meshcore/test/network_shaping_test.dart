// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
//
// MeshCore's own network-shaping commands. These are what makes a network
// separate from the public mesh — no custom layer. Wire formats transcribed
// from the firmware at companion-v1.17.1 (d929643):
//
//   CMD_SET_FLOOD_SCOPE_KEY        54  MyMesh.cpp:1936-1945
//   CMD_GET_ALLOWED_REPEAT_FREQ    60  MyMesh.cpp:1994-2002
//   CMD_SET_PATH_HASH_MODE         61  MyMesh.cpp:1466-1473
//   CMD_SET_DEFAULT_FLOOD_SCOPE    63  MyMesh.cpp:1947-1963
//   CMD_GET_DEFAULT_FLOOD_SCOPE    64  MyMesh.cpp:1964-1973
//
// All five also exist at the package's pin (companion-v1.15.0), so these do
// not require a pin bump: the only commands added between the two tags are
// CMD_DEVICE_QUERY (22) and CMD_SEND_RAW_PACKET (65).

import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:test/test.dart';

String _hex(Uint8List b) =>
    b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('setPathHashMode (0x3D)', () {
    test('sizes 1..3 map to wire modes 0..2', () {
      expect(_hex(MeshcoreFrameCodec.setPathHashMode(1)), '3d0000');
      expect(_hex(MeshcoreFrameCodec.setPathHashMode(2)), '3d0001');
      expect(_hex(MeshcoreFrameCodec.setPathHashMode(3)), '3d0002');
    });

    test('out-of-range is refused here, not rejected on the air', () {
      // The firmware answers ERR_CODE_ILLEGAL_ARG for mode >= 3; sending a
      // request we already know is invalid wastes a round trip on a link
      // whose round trip can cost ten seconds.
      expect(() => MeshcoreFrameCodec.setPathHashMode(0), throwsArgumentError);
      expect(() => MeshcoreFrameCodec.setPathHashMode(4), throwsArgumentError);
    });
  });

  group('setFloodScopeKey (0x36)', () {
    test('null or empty clears the override', () {
      expect(_hex(MeshcoreFrameCodec.setFloodScopeKey(null)), '3600');
      expect(_hex(MeshcoreFrameCodec.setFloodScopeKey(<int>[])), '3600');
    });

    test('a 16-byte key is appended verbatim', () {
      final Uint8List key =
          Uint8List.fromList(List<int>.generate(16, (int i) => i));
      expect(_hex(MeshcoreFrameCodec.setFloodScopeKey(key)),
          '3600000102030405060708090a0b0c0d0e0f');
    });

    test('any other key length is refused', () {
      expect(() => MeshcoreFrameCodec.setFloodScopeKey(<int>[1, 2, 3]),
          throwsArgumentError);
    });

    test('unscoped floods are a distinct 2-byte frame', () {
      expect(_hex(MeshcoreFrameCodec.sendUnscopedFlood()), '3601');
    });
  });

  group('setDefaultFloodScope (0x3F)', () {
    test('no name clears the stored default with a bare opcode', () {
      expect(_hex(MeshcoreFrameCodec.setDefaultFloodScope(null, null)), '3f');
      expect(_hex(MeshcoreFrameCodec.setDefaultFloodScope('', null)), '3f');
    });

    test('name is a zero-padded 31-byte field followed by the 16-byte key', () {
      final Uint8List key = Uint8List(16)..fillRange(0, 16, 0xAB);
      final Uint8List f = MeshcoreFrameCodec.setDefaultFloodScope('home', key);
      expect(f.length, 1 + 31 + 16, reason: 'firmware requires len >= 48');
      expect(String.fromCharCodes(f.sublist(1, 5)), 'home');
      expect(f.sublist(5, 32), everyElement(0), reason: 'NUL padded');
      expect(f.sublist(32, 48), everyElement(0xAB));
    });

    test('a 31+ char name and a wrong-length key are refused', () {
      final Uint8List key = Uint8List(16);
      expect(() => MeshcoreFrameCodec.setDefaultFloodScope('x' * 31, key),
          throwsArgumentError);
      expect(() => MeshcoreFrameCodec.setDefaultFloodScope('home', <int>[1, 2]),
          throwsArgumentError);
    });
  });

  group('decodeDefaultFloodScope (0x1C)', () {
    test('a bare response code means the scope is unset', () {
      expect(
          MeshcoreFrameCodec.decodeDefaultFloodScope(
              Uint8List.fromList(<int>[0x1C])),
          isNull);
    });

    test('name and key round-trip through the wire layout', () {
      final Uint8List key = Uint8List(16)..fillRange(0, 16, 0x11);
      final Uint8List f = MeshcoreFrameCodec.setDefaultFloodScope('home', key);
      // Build the reply the firmware would send: code + 31 + 16.
      final Uint8List reply = Uint8List(1 + 31 + 16)
        ..[0] = 0x1C
        ..setRange(1, 32, f.sublist(1, 32))
        ..setRange(32, 48, key);
      final ({String name, Uint8List key})? got =
          MeshcoreFrameCodec.decodeDefaultFloodScope(reply);
      expect(got, isNotNull);
      expect(got!.name, 'home');
      expect(got.key, key);
    });

    test('a wrong response code is not mistaken for a scope', () {
      expect(
          MeshcoreFrameCodec.decodeDefaultFloodScope(
              Uint8List.fromList(<int>[0x00, 1, 2, 3])),
          isNull);
    });
  });

  group('decodeAllowedRepeatFreq (0x1A)', () {
    test('packs (lower, upper) kHz pairs', () {
      final ByteData d = ByteData(1 + 24);
      d.setUint8(0, 0x1A);
      final List<List<int>> ranges = <List<int>>[
        <int>[433000, 433000],
        <int>[869495, 869495],
        <int>[918000, 918000],
      ];
      for (int i = 0; i < ranges.length; i++) {
        d.setUint32(1 + i * 8, ranges[i][0], Endian.little);
        d.setUint32(5 + i * 8, ranges[i][1], Endian.little);
      }
      final List<({int lowerKhz, int upperKhz})> out =
          MeshcoreFrameCodec.decodeAllowedRepeatFreq(d.buffer.asUint8List());
      expect(out.length, 3);
      expect(out[0].lowerKhz, 433000);
      expect(out[1].lowerKhz, 869495);
      expect(out[2].upperKhz, 918000);
    });

    test('a bare code yields no ranges', () {
      expect(
          MeshcoreFrameCodec.decodeAllowedRepeatFreq(
              Uint8List.fromList(<int>[0x1A])),
          isEmpty);
    });
  });
}
