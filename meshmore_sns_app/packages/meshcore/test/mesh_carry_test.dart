// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
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

/// Runs a vector's encoder by name. Kept a plain switch so an unknown
/// name fails loudly rather than silently skipping a vector.
Uint8List _encode(String name, Map<String, Object?> a) {
  switch (name) {
    case 'sendBinaryReq':
      return MeshCarryCodec.sendBinaryReq(
        pubKey: _hex(a['pubKey']! as String),
        appData: _hex(a['appData']! as String),
      );
    case 'lengthPrefixedRecord':
      return MeshCarryCodec.lengthPrefixedRecord(
        _hex(a['record']! as String),
      );
    case 'sendRawData':
      return MeshCarryCodec.sendRawData(
        path: _hex(a['path']! as String),
        payload: _hex(a['payload']! as String),
      );
    case 'sendRawPacket':
      return MeshCarryCodec.sendRawPacket(
        priority: a['priority']! as int,
        packet: _hex(a['packet']! as String),
      );
    default:
      fail('unknown encoder "$name"');
  }
}

void main() {
  group('M5 carry vectors (vectors/m5_carry_frames.json)', () {
    final Map<String, Object?> doc = jsonDecode(
            File('test/vectors/m5_carry_frames.json').readAsStringSync())
        as Map<String, Object?>;

    for (final Object? raw in doc['encode']! as List<Object?>) {
      final Map<String, Object?> c = raw! as Map<String, Object?>;
      test('encode: ${c['name']}', () {
        final Uint8List got =
            _encode(c['encoder']! as String, c['args']! as Map<String, Object?>);
        expect(_toHex(got), c['hex']! as String);
      });
    }

    for (final Object? raw in doc['decode']! as List<Object?>) {
      final Map<String, Object?> c = raw! as Map<String, Object?>;
      test('decode: ${c['name']}', () {
        final Uint8List frame = _hex(c['hex']! as String);
        final Map<String, Object?> want =
            c['expect']! as Map<String, Object?>;
        switch (c['decoder']! as String) {
          case 'decodeSendResult':
            final MeshSendResult? got =
                MeshCarryCodec.decodeSendResult(frame);
            expect(got, isNotNull);
            expect(got!.flood, want['flood']);
            expect(got.tag, want['tag']);
            expect(got.estTimeoutMs, want['estTimeoutMs']);
          case 'decodeBinaryResponse':
            final MeshBinaryResponse? got =
                MeshCarryCodec.decodeBinaryResponse(frame);
            expect(got, isNotNull);
            expect(got!.tag, want['tag']);
            expect(_toHex(got.data), want['data']);
          case 'decodeError':
            final MeshcoreErrorCode? got = MeshCarryCodec.decodeError(frame);
            expect(got, isNotNull);
            expect(got!.code, want['code']);
            expect(got.name, want['name']);
          default:
            fail('unknown decoder "${c['decoder']}"');
        }
      });
    }
  });

  group('upload budgets (three caps, smallest binds)', () {
    test('binary request payload maximum is 143', () {
      expect(MeshCarryLimits.binaryReqAppDataMax, 143);
      expect(
        MeshCarryCodec.sendBinaryReq(
          pubKey: List<int>.filled(kPubKeySize, 0),
          appData: List<int>.filled(143, 0),
        ).length,
        MeshCarryLimits.maxFrameSize,
      );
    });

    test('a 144-byte payload is refused, not truncated', () {
      expect(
        () => MeshCarryCodec.sendBinaryReq(
          pubKey: List<int>.filled(kPubKeySize, 0),
          appData: List<int>.filled(144, 0),
        ),
        throwsA(isA<MeshCarryLengthError>()),
      );
    });

    test('a record maximum is 142, leaving room for the length byte', () {
      expect(MeshCarryLimits.binaryReqRecordMax, 142);
      expect(MeshCarryCodec.lengthPrefixedRecord(List<int>.filled(142, 0)).length,
          143);
      expect(
        () => MeshCarryCodec.lengthPrefixedRecord(List<int>.filled(143, 0)),
        throwsA(isA<MeshCarryLengthError>()),
      );
    });

    test('raw data payload shrinks by one byte per path hop', () {
      expect(MeshCarryLimits.rawDataPayloadMax(0), 174);
      expect(MeshCarryLimits.rawDataPayloadMax(3), 171);
      expect(
        MeshCarryCodec.sendRawData(
          path: List<int>.filled(3, 0x11),
          payload: List<int>.filled(171, 0x22),
        ).length,
        MeshCarryLimits.maxFrameSize,
      );
      expect(
        () => MeshCarryCodec.sendRawData(
          path: List<int>.filled(3, 0x11),
          payload: List<int>.filled(172, 0x22),
        ),
        throwsA(isA<MeshCarryLengthError>()),
      );
    });

    test('raw data below the 4-byte firmware floor is refused', () {
      expect(
        () => MeshCarryCodec.sendRawData(path: const <int>[], payload: const <int>[1, 2, 3]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a 175-byte raw packet is refused', () {
      expect(
        () => MeshCarryCodec.sendRawPacket(
          priority: 0,
          packet: List<int>.filled(175, 0),
        ),
        throwsA(isA<MeshCarryLengthError>()),
      );
    });
  });

  group('decoders are total', () {
    test('an empty frame decodes to null everywhere', () {
      final Uint8List empty = Uint8List(0);
      expect(MeshCarryCodec.decodeSendResult(empty), isNull);
      expect(MeshCarryCodec.decodeBinaryResponse(empty), isNull);
      expect(MeshCarryCodec.decodeError(empty), isNull);
    });

    test('a wrong opcode decodes to null', () {
      final Uint8List frame = _hex('8c000a0b0c0d01020304');
      expect(MeshCarryCodec.decodeSendResult(frame), isNull);
      expect(MeshCarryCodec.decodeBinaryResponse(frame), isNotNull);
      expect(MeshCarryCodec.decodeError(frame), isNull);
    });

    test('a truncated send result decodes to null', () {
      expect(
        MeshCarryCodec.decodeSendResult(_hex('06014 4332211'.replaceAll(' ', ''))),
        isNull,
      );
    });

    test('a binary response with no payload decodes to null', () {
      // Exactly the header, no data: the firmware never pushes this.
      expect(
        MeshCarryCodec.decodeBinaryResponse(_hex('8c000a0b0c0d')),
        isNull,
      );
    });

    test('a tag of 0 is reported unusable, because 0 is the idle sentinel',
        () {
      final MeshSendResult? got =
          MeshCarryCodec.decodeSendResult(_hex('06000000000000000000'));
      expect(got, isNotNull);
      expect(got!.tag, 0);
      expect(got.tagUsable, isFalse);
    });
  });
}
