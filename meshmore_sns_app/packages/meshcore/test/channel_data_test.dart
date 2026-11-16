// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:test/test.dart';

Uint8List _hex(String s) {
  final Uint8List out = Uint8List(s.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(List<int> b) =>
    b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

/// `CMD_SEND_CHANNEL_DATA` (0x3E) — the carrier every media and place
/// payload will travel in.
///
/// The two budgets are the point of this file. The radio refuses an
/// over-long blob with `ERR_CODE_TABLE_FULL`, the same code it uses for a
/// full packet table, so the client has to refuse first and say which limit
/// bound: the datagram's own 162 bytes, or what the send's path leaves of
/// the 176-byte frame.
void main() {
  group('M6 channel-datagram vectors', () {
    final Map<String, Object?> doc = jsonDecode(
            File('test/vectors/m6_channel_data_frames.json').readAsStringSync())
        as Map<String, Object?>;

    for (final Object? raw in doc['encode']! as List<Object?>) {
      final Map<String, Object?> c = raw! as Map<String, Object?>;
      test('encode: ${c['name']}', () {
        final Map<String, Object?> a = c['args']! as Map<String, Object?>;
        final Uint8List got = MeshcoreFrameCodec.sendChannelData(
          channelIdx: a['channelIdx']! as int,
          dataType: a['dataType']! as int,
          blob: (a['blob']! as List<Object?>).cast<int>(),
          pathLen: (a['pathLen'] as int?) ?? kPathLenFlood,
          path: (a['path'] as List<Object?>?)?.cast<int>() ?? const <int>[],
        );
        expect(_toHex(got), c['hex']! as String);
      });
    }

    for (final Object? raw in doc['decode']! as List<Object?>) {
      final Map<String, Object?> c = raw! as Map<String, Object?>;
      test('decode: ${c['name']}', () {
        final MeshcoreInbound got =
            MeshcoreFrameCodec.decode(_hex(c['hex']! as String));
        expect(got, isA<ChannelDataFrame>());
        final Map<String, Object?> e = c['expect']! as Map<String, Object?>;
        final ChannelDataFrame d = got as ChannelDataFrame;
        expect(d.snrDb, e['snrDb']);
        expect(d.channelIndex, e['channelIndex']);
        expect(d.pathLen, e['pathLen']);
        expect(d.dataType, e['dataType']);
        expect(d.via.name, e['via']);
        expect(_toHex(d.data), e['data']);
      });
    }
  });

  group('channel-datagram budgets', () {
    test('a 162-byte blob is the last one that fits, and the frame is 167', () {
      final Uint8List ok = MeshcoreFrameCodec.sendChannelData(
        channelIdx: 0,
        dataType: 0xFF01,
        blob: List<int>.filled(ChannelDataLimits.maxBlob, 0xAB),
      );
      expect(ChannelDataLimits.maxBlob, 162);
      expect(ok.length, ChannelDataLimits.headerBytes + 162);
      expect(ok.sublist(5), everyElement(0xAB));
      // The firmware's own frame cap is 167 (`MAX_CHANNEL_DATA_LENGTH`),
      // which is exactly what a full blob plus the type fields costs.
      expect(ok.length, ChannelDataLimits.firmwareFramePayloadMax);
    });

    test('a 163-byte blob is refused as too long for the datagram', () {
      expect(
        () => MeshcoreFrameCodec.sendChannelData(
          channelIdx: 0,
          dataType: 0xFF01,
          blob: List<int>.filled(163, 0),
        ),
        throwsA(isA<ChannelDataException>()
            .having((ChannelDataException e) => e.refusal, 'refusal',
                ChannelDataRefusal.blobTooLongForDatagram)
            .having((ChannelDataException e) => e.maximum, 'maximum', 162)),
      );
    });

    test('path bytes are spent from the same frame budget', () {
      // 176 - 5 header - 10 path = 161, one less than the datagram alone.
      expect(ChannelDataLimits.blobMaxForPath(10), 161);
      expect(ChannelDataLimits.blobMaxForPath(0), 162);
      // A long path binds before the datagram does.
      expect(ChannelDataLimits.blobMaxForPath(30), 141);
      expect(
        () => MeshcoreFrameCodec.sendChannelData(
          channelIdx: 0,
          dataType: 0xFF01,
          blob: List<int>.filled(162, 0),
          pathLen: 10,
          path: List<int>.filled(10, 1),
        ),
        throwsA(isA<ChannelDataException>().having(
            (ChannelDataException e) => e.refusal,
            'refusal',
            ChannelDataRefusal.blobTooLongForFrame)),
      );
    });

    test('the largest legal send is exactly one frame', () {
      final Uint8List frame = MeshcoreFrameCodec.sendChannelData(
        channelIdx: 0,
        dataType: 0xFF01,
        blob: List<int>.filled(ChannelDataLimits.blobMaxForPath(9), 0),
        pathLen: 9,
        path: List<int>.filled(9, 2),
      );
      expect(frame.length, MeshcoreBle.maxFrameSize);
    });

    test('DATA_TYPE_RESERVED is refused, as the radio refuses it', () {
      expect(
        () => MeshcoreFrameCodec.sendChannelData(
          channelIdx: 0,
          dataType: kChannelDataTypeReserved,
          blob: const <int>[1],
        ),
        throwsA(isA<ChannelDataException>().having(
            (ChannelDataException e) => e.refusal,
            'refusal',
            ChannelDataRefusal.reservedType)),
      );
    });

    test('a reserved hash size is refused before the radio reads the path '
        'from the middle of the data type', () {
      // hash-size code 3 is reserved (Packet.cpp:17-22).
      expect(
        () => MeshcoreFrameCodec.sendChannelData(
          channelIdx: 0,
          dataType: 0xFF01,
          blob: const <int>[1],
          pathLen: 0xC1,
          path: const <int>[1, 2, 3, 4],
        ),
        throwsA(isA<ChannelDataException>().having(
            (ChannelDataException e) => e.refusal,
            'refusal',
            ChannelDataRefusal.invalidPathLen)),
      );
      expect(const PathLen(0xC1).isValid, isFalse);
    });

    test('path bytes that do not match the packed length are refused', () {
      expect(
        () => MeshcoreFrameCodec.sendChannelData(
          channelIdx: 0,
          dataType: 0xFF01,
          blob: const <int>[1],
          pathLen: 0x02, // two hops of one-byte hashes = two bytes
          path: const <int>[9],
        ),
        throwsA(isA<ChannelDataException>().having(
            (ChannelDataException e) => e.refusal,
            'refusal',
            ChannelDataRefusal.pathLengthMismatch)),
      );
    });

    test('flood means flood: path bytes with 0xFF are refused', () {
      expect(
        () => MeshcoreFrameCodec.sendChannelData(
          channelIdx: 0,
          dataType: 0xFF01,
          blob: const <int>[1],
          path: const <int>[7],
        ),
        throwsA(isA<ChannelDataException>().having(
            (ChannelDataException e) => e.refusal,
            'refusal',
            ChannelDataRefusal.pathLengthMismatch)),
      );
    });

    test('a channel index or data type outside its field is refused', () {
      expect(
        () => MeshcoreFrameCodec.sendChannelData(
            channelIdx: 256, dataType: 1, blob: const <int>[]),
        throwsA(isA<ChannelDataException>().having(
            (ChannelDataException e) => e.refusal,
            'refusal',
            ChannelDataRefusal.channelOutOfRange)),
      );
      expect(
        () => MeshcoreFrameCodec.sendChannelData(
            channelIdx: 0, dataType: 0x10000, blob: const <int>[]),
        throwsA(isA<ChannelDataException>().having(
            (ChannelDataException e) => e.refusal,
            'refusal',
            ChannelDataRefusal.dataTypeOutOfRange)),
      );
    });

    test('airtime bytes count the frame without its opcode', () {
      // The radio re-wraps the payload, so the opcode is not on air.
      expect(ChannelDataLimits.airtimeBytesFor(162), 166);
    });
  });

  group('path length rules from the firmware', () {
    test('every hop count and hash size the firmware accepts', () {
      for (int hashCode = 0; hashCode < 3; hashCode++) {
        final int hashSize = hashCode + 1;
        for (int hops = 0; hops <= kPathHopMask; hops++) {
          final int raw = (hashCode << kPathHashSizeShift) | hops;
          final PathLen p = PathLen(raw);
          expect(p.hashSize, hashSize, reason: 'raw $raw');
          expect(p.hopCount, hops, reason: 'raw $raw');
          expect(p.isValid, hops * hashSize <= kMaxPathSize, reason: 'raw $raw');
        }
      }
    });

    test('hash size 4 is reserved at every hop count', () {
      for (int hops = 0; hops <= kPathHopMask; hops++) {
        final int raw = (kPathHashSizeReservedCode << kPathHashSizeShift) | hops;
        expect(PathLen(raw).isValid, isFalse, reason: 'raw $raw');
      }
    });
  });
}
