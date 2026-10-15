// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
//
// R60 Tools — frames built byte-by-byte from the firmware's own memcpy
// sequences (companion_radio/MyMesh.cpp, simple_repeater/MyMesh.h).
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:test/test.dart';

Uint8List _hex(String s) {
  final String t = s.replaceAll(' ', '');
  final Uint8List out = Uint8List(t.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(t.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(Uint8List b) =>
    b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

final Uint8List _key = Uint8List.fromList(List<int>.generate(32, (i) => i));

void main() {
  group('encoders', () {
    test('getStats', () {
      expect(_toHex(MeshcoreFrameCodec.getStats(kStatsTypeRadio)), '3801');
    });

    test('sendStatusReq / resetPath carry the full key', () {
      final Uint8List s = MeshcoreFrameCodec.sendStatusReq(_key);
      expect(s.length, 33);
      expect(s[0], 0x1B);
      expect(s.sublist(1), _key);
      final Uint8List r = MeshcoreFrameCodec.resetPath(_key);
      expect(r[0], 0x0D);
      expect(r.sublist(1), _key);
    });

    test('sendTracePath: tag, auth, flags, then the hashes', () {
      final Uint8List f = MeshcoreFrameCodec.sendTracePath(
          tag: 0x11223344, path: <int>[0xa1, 0x7f, 0xa1]);
      expect(_toHex(f), '24' '44332211' '00000000' '00' 'a17fa1');
      // Firmware requires len > 10 — one hop is the minimum.
      expect(f.length, greaterThan(10));
    });

    test('sendDiscoverReq: control packet straight after the opcode', () {
      final Uint8List f =
          MeshcoreFrameCodec.sendDiscoverReq(tag: 0xdeadbeef);
      expect(_toHex(f), '37' '80' '04' 'efbeadde');
      final Uint8List p = MeshcoreFrameCodec.sendDiscoverReq(
          tag: 1, prefixOnly: true, since: 2);
      expect(_toHex(p), '37' '81' '04' '01000000' '02000000');
    });
  });

  group('decoders', () {
    test('PUSH_CODE_SEND_CONFIRMED keeps the round-trip ms', () {
      final MeshcoreInbound f =
          MeshcoreFrameCodec.decode(_hex('82 78563412 e8030000'));
      expect(f, isA<AckFrame>());
      expect((f as AckFrame).ackCrc, 0x12345678);
      expect(f.roundTripMs, 1000);
      // Older firmware: tag only.
      final AckFrame short =
          MeshcoreFrameCodec.decode(_hex('82 78563412')) as AckFrame;
      expect(short.roundTripMs, isNull);
    });

    test('stats: core', () {
      final StatsFrame f = MeshcoreFrameCodec.decode(
          _hex('18 00 6810 10270000 0300 02')) as StatsFrame;
      expect(f.core!.batteryMilliVolts, 4200);
      expect(f.core!.uptimeSecs, 10000);
      expect(f.core!.errFlags, 3);
      expect(f.core!.queueLen, 2);
    });

    test('stats: radio — signed noise floor and SNR×4', () {
      // noise -110 (0xff92), rssi -90 (0xa6), snr -7.5 (-30 = 0xe2)
      final StatsFrame f = MeshcoreFrameCodec.decode(
          _hex('18 01 92ff a6 e2 3c000000 58020000')) as StatsFrame;
      expect(f.radio!.noiseFloorDbm, -110);
      expect(f.radio!.lastRssi, -90);
      expect(f.radio!.lastSnrDb, -7.5);
      expect(f.radio!.txAirSecs, 60);
      expect(f.radio!.rxAirSecs, 600);
    });

    test('stats: packets, with and without receive errors', () {
      final String six =
          '0a000000 05000000 03000000 02000000 06000000 04000000';
      final StatsFrame withErr = MeshcoreFrameCodec.decode(
          _hex('18 02 $six 07000000')) as StatsFrame;
      expect(withErr.packets!.received, 10);
      expect(withErr.packets!.sentDirect, 2);
      expect(withErr.packets!.receiveErrors, 7);
      final StatsFrame without =
          MeshcoreFrameCodec.decode(_hex('18 02 $six')) as StatsFrame;
      expect(without.packets!.receiveErrors, isNull);
    });

    test('stats: an unknown sub-type is kept, not guessed', () {
      expect(MeshcoreFrameCodec.decode(_hex('18 09 0000')),
          isA<UnsupportedFrame>());
    });

    test('status response: the RepeaterStats struct', () {
      final String stats = '6810' // batt 4200
          '0100' // queue 1
          '92ff' // noise -110
          'b5ff' // rssi -75
          '64000000' // recv 100
          '32000000' // sent 50
          '0a000000' // air 10
          '100e0000' // uptime 3600
          '01000000 02000000 03000000 04000000' // flood/direct
          '0000' // err
          '1c00' // snr 7.0 (28)
          '0000 0000' // dups
          '05000000' // rx air
          '00000000'; // rx errors
      final StatusResponseFrame f = MeshcoreFrameCodec.decode(
              _hex('87 00 a1a2a3a4a5a6 $stats')) as StatusResponseFrame;
      expect(f.pubKeyPrefix, _hex('a1a2a3a4a5a6'));
      final RepeaterStatus s = f.status!;
      expect(s.batteryMilliVolts, 4200);
      expect(s.noiseFloorDbm, -110);
      expect(s.lastRssi, -75);
      expect(s.uptimeSecs, 3600);
      expect(s.receivedDirect, 4);
      expect(s.lastSnrDb, 7.0);
      expect(s.rxAirTimeSecs, 5);
      expect(s.receiveErrors, 0);
    });

    test('status response: an old, short struct still decodes', () {
      final StatusResponseFrame f = MeshcoreFrameCodec.decode(_hex(
              '87 00 a1a2a3a4a5a6 6810 0000 92ff b5ff '
              '64000000 32000000 0a000000 100e0000')) as StatusResponseFrame;
      expect(f.status!.uptimeSecs, 3600);
      expect(f.status!.lastSnrDb, isNull);
    });

    test('trace data: per-hop SNR plus the final hop to us', () {
      // 3 one-byte hops a1 7f a1; snrs 6.0, -2.5, 4.25; final 5.5
      final TraceDataFrame f = MeshcoreFrameCodec.decode(_hex(
              '89 00 03 00 44332211 00000000 a17fa1 18 f6 11 16'))
          as TraceDataFrame;
      expect(f.trace.tag, 0x11223344);
      expect(f.trace.hashSize, 1);
      expect(f.trace.pathHashes, _hex('a17fa1'));
      expect(f.trace.hopSnrsDb, <double>[6.0, -2.5, 4.25]);
      expect(f.trace.finalSnrDb, 5.5);
    });

    test('trace data: two-byte hashes halve the hop count', () {
      final TraceDataFrame f = MeshcoreFrameCodec.decode(_hex(
              '89 00 04 01 01000000 00000000 a1b27f80 08 0c 10'))
          as TraceDataFrame;
      expect(f.trace.hashSize, 2);
      expect(f.trace.hopSnrsDb, <double>[2.0, 3.0]);
      expect(f.trace.finalSnrDb, 4.0);
    });

    test('control data: a discover response, SNR both ways', () {
      final String key = _toHex(_key);
      final ControlDataFrame f = MeshcoreFrameCodec.decode(
              _hex('8e 14 a6 00 92 f8 efbeadde $key')) as ControlDataFrame;
      expect(f.snrDb, 5.0);
      expect(f.rssi, -90);
      final DiscoverResponse d = f.discover!;
      expect(d.nodeType, kAdvTypeRepeater);
      expect(d.tag, 0xdeadbeef);
      expect(d.theirSnrDb, -2.0);
      expect(d.ourSnrDb, 5.0);
      expect(d.publicKey, _key);
    });

    test('control data: prefix-only discover response', () {
      final ControlDataFrame f = MeshcoreFrameCodec.decode(_hex(
              '8e 14 a6 00 92 f8 efbeadde 0001020304050607'))
          as ControlDataFrame;
      expect(f.discover!.publicKey.length, 8);
    });

    test('control data: other control packets are kept raw', () {
      final ControlDataFrame f =
          MeshcoreFrameCodec.decode(_hex('8e 14 a6 00 80 04 01000000'))
              as ControlDataFrame;
      expect(f.discover, isNull);
      expect(f.payload.length, 6);
    });

    test('truncated trace is a decode failure, not a throw', () {
      expect(MeshcoreFrameCodec.decode(_hex('89 00 03 00 4433')),
          isA<DecodeFailure>());
    });
  });
}
