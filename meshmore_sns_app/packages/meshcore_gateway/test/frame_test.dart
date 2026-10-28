// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:test/test.dart';

Uint8List _hex(String s) {
  if (s.isEmpty) return Uint8List(0);
  final Uint8List out = Uint8List(s.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(List<int> b) =>
    b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  opsLeftTests();
  group('framing', () {
    test('a HELLO encodes to the documented bytes', () {
      // MG | version 01 | type 01 | flags 00 | length 0200 (LE) | 01 00
      final Frame f = GatewayMessages.hello(capabilities: 0);
      expect(_toHex(f.encode()), '4d47010100020001 00'.replaceAll(' ', ''));
    });

    test('round-trips through the stream decoder', () {
      final Frame original = GatewayMessages.hello(capabilities: 0x03);
      final FrameDecoder d = FrameDecoder();
      final List<Frame> out = d.add(original.encode());
      expect(out, hasLength(1));
      expect(out.single.type, FrameType.hello);
      expect(_toHex(out.single.payload), '0103');
    });

    test('a frame split across chunk boundaries decodes once', () {
      final Uint8List bytes =
          GatewayMessages.status(
            radioState: RadioState.connected,
            rssi: -71,
            batteryPercent: 88,
            txAirtimeTenthsThisHour: 360,
          ).encode();
      final FrameDecoder d = FrameDecoder();
      final List<Frame> got = <Frame>[];
      for (final int b in bytes) {
        got.addAll(d.add(<int>[b]));
      }
      expect(got, hasLength(1));
      final ({
        RadioState radioState,
        int rssi,
        int batteryPercent,
        int txAirtimeTenthsThisHour,
      })? st = GatewayMessages.readStatus(got.single);
      expect(st, isNotNull);
      expect(st!.radioState, RadioState.connected);
      expect(st.rssi, -71);
      expect(st.batteryPercent, 88);
      expect(st.txAirtimeTenthsThisHour, 360);
    });

    test('two frames in one chunk decode in order', () {
      final FrameDecoder d = FrameDecoder();
      final List<Frame> out = d.add(<int>[
        ...GatewayMessages.pairOk().encode(),
        ...GatewayMessages.sendResult(seq: 3, outcome: SendOutcome.sentDirect).encode(),
      ]);
      expect(out.map((Frame f) => f.type),
          <FrameType>[FrameType.pairOk, FrameType.sendResult]);
    });

    test('a bad magic is fatal, not skipped', () {
      final FrameDecoder d = FrameDecoder();
      d.add(_hex('4d47010100020001 00'.replaceAll(' ', '')));
      expect(d.error, isNull);
      d.reset();
      d.add(_hex('4d58'));
      // Still short: nothing decoded, no error yet.
      expect(d.error, isNull);
      d.add(_hex('0100010000'));
      expect(d.error, FrameDecodeError.badMagic);
    });

    test('a future version is reported before the length is trusted', () {
      final FrameDecoder d = FrameDecoder();
      d.add(_hex('4d47020100020001 00'.replaceAll(' ', '')));
      expect(d.error, FrameDecodeError.badVersion);
    });

    test('an oversized length is refused without allocating', () {
      final FrameDecoder d = FrameDecoder();
      d.add(_hex('4d47010100ffff'));
      expect(d.error, FrameDecodeError.lengthTooLarge);
    });

    test('non-zero flags are refused', () {
      final FrameDecoder d = FrameDecoder();
      d.add(_hex('4d4701010102000100'));
      expect(d.error, FrameDecodeError.badFlags);
    });

    test('an unknown frame type is delivered, not fatal', () {
      final FrameDecoder d = FrameDecoder();
      final List<Frame> out = d.add(_hex('4d47017f00010000'));
      expect(d.error, isNull);
      expect(out, hasLength(1));
      expect(out.single.type.code, 0x7F);
      expect(out.single.type.name, 'unknown_0x7f');
    });
  });

  group('payload limits', () {
    test('a record above the carrier ceiling is refused', () {
      expect(
        () => GatewayMessages.record(
          seq: 0,
          opaqueRecord: List<int>.filled(GatewayLimits.recordMax + 1, 0),
        ),
        throwsA(isA<FrameLengthError>()),
      );
    });

    test('the carrier promises a record, not what a record is made of', () {
      // 172 is the only number the carrier owes. A session layer may reserve
      // bytes inside it; if this package ever learns that layout, the carrier
      // is no longer blind and the two products are coupled again.
      expect(GatewayLimits.recordMax, 172);
      expect(GatewayLimits.recordFloor, 160);
    });

    test('the discovery ceiling leaves room for the length prefix', () {
      expect(GatewayLimits.discoveryRecordMax, 142);
      expect(GatewayLimits.discoveryRecordMax + 1,
          lessThanOrEqualTo(143));
    });

    test('a frame payload above the contract maximum is refused', () {
      expect(
        () => Frame(type: FrameType.record,
            payload: List<int>.filled(GatewayLimits.maxPayload + 1, 0)),
        throwsA(isA<FrameLengthError>()),
      );
    });

    test('a pairing token of the wrong size is refused', () {
      expect(
        () => GatewayMessages.pair(List<int>.filled(15, 0)),
        throwsA(isA<FrameLengthError>()),
      );
      expect(
        _toHex(GatewayMessages.pair(List<int>.filled(16, 0xAB)).payload),
        'ab' * 16,
      );
    });
  });

  group('the sequence number makes a refusal attributable', () {
    test('RECORD carries seq then the opaque record', () {
      final Frame f = GatewayMessages.record(seq: 9, opaqueRecord: _hex('aabb'));
      expect(_toHex(f.payload), '09aabb');
      final ({int seq, Uint8List record})? r = GatewayMessages.readRecord(f);
      expect(r, isNotNull);
      expect(r!.seq, 9);
      expect(_toHex(r.record), 'aabb');
    });

    test('SEND_RESULT echoes the same seq', () {
      final Frame f =
          GatewayMessages.sendResult(seq: 9, outcome: SendOutcome.errTooLong);
      expect(_toHex(f.payload), '0905');
      final ({int seq, SendOutcome outcome})? r =
          GatewayMessages.readSendResult(f);
      expect(r!.seq, 9);
      expect(r.outcome, SendOutcome.errTooLong);
      expect(r.outcome.name, 'err_too_long');
    });

    test('a RECORD with no payload byte is refused as malformed', () {
      expect(
        GatewayMessages.readRecord(Frame(type: FrameType.record, payload: <int>[1])),
        isNull,
      );
    });
  });

  group('capacity is advertised, not assumed', () {
    test('BIND_OK reports the real uplink limit', () {
      final Frame f = GatewayMessages.bindOk(uplinkRecordMax: 168);
      expect(_toHex(f.payload), '00a8');
      final ({int capabilities, int uplinkRecordMax})? r =
          GatewayMessages.readBindOk(f);
      expect(r!.uplinkRecordMax, 168);
    });

    test('a capacity above the absolute ceiling is refused', () {
      expect(
        () => GatewayMessages.bindOk(uplinkRecordMax: GatewayLimits.recordMax + 1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the floor still fits a 14-hop path', () {
      // 174 - path_len >= recordFloor  =>  path_len <= 14
      expect(174 - GatewayLimits.recordFloor, 14);
    });
  });

  group('pairing token comparison is constant time in shape', () {
    test('equal tokens match', () {
      expect(
        pairingTokenMatches(
          presented: List<int>.filled(16, 7),
          stored: List<int>.filled(16, 7),
        ),
        isTrue,
      );
    });

    test('a single-byte difference fails, at any position', () {
      for (int pos = 0; pos < 16; pos++) {
        final List<int> presented = List<int>.filled(16, 7);
        presented[pos] = 8;
        expect(
          pairingTokenMatches(presented: presented, stored: List<int>.filled(16, 7)),
          isFalse,
          reason: 'difference at $pos should fail',
        );
      }
    });

    test('a short token fails without a content short-circuit', () {
      expect(
        pairingTokenMatches(presented: const <int>[], stored: List<int>.filled(16, 0)),
        isFalse,
      );
    });
  });
}

void opsLeftTests() {
  group('STATUS opsLeftThisHour (additive sixth byte)', () {
    test('is carried, and a five-byte reader still decodes the rest', () {
      final Frame f = GatewayMessages.status(
        radioState: RadioState.connected,
        rssi: -71,
        batteryPercent: 88,
        txAirtimeTenthsThisHour: 360,
        opsLeftThisHour: 42,
      );
      expect(f.payload, hasLength(6));
      expect(f.payload[5], 42);
      expect(GatewayMessages.readOpsLeft(f), 42);
      expect(GatewayMessages.readStatus(f)!.txAirtimeTenthsThisHour, 360);
    });

    test('an older five-byte STATUS reads as unknown, not zero', () {
      final Frame f = GatewayMessages.status(
        radioState: RadioState.connected,
        rssi: -71,
        batteryPercent: 88,
        txAirtimeTenthsThisHour: 360,
      );
      expect(f.payload, hasLength(5));
      expect(GatewayMessages.readOpsLeft(f), isNull);
    });

    test('out of range is refused locally', () {
      expect(
        () => GatewayMessages.status(
          radioState: RadioState.connected,
          rssi: 0,
          batteryPercent: 0,
          txAirtimeTenthsThisHour: 0,
          opsLeftThisHour: 256,
        ),
        throwsArgumentError,
      );
    });

    test('the governor derives it from remaining budget and clamps', () {
      final Governor g = Governor(budget: const Duration(seconds: 36));
      expect(g.opsLeft(const Duration(milliseconds: 613)), 58);
      expect(g.opsLeft(const Duration(milliseconds: 10)), 255);
      g.charge(const Duration(seconds: 10));
      expect(g.opsLeft(const Duration(milliseconds: 613)), 42);
      g.charge(const Duration(seconds: 30));
      expect(g.opsLeft(const Duration(milliseconds: 613)), 0);
      expect(g.opsLeft(Duration.zero), 0);
    });
  });
}
