// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:meshcore_host/meshcore_host.dart';
import 'package:test/test.dart';

void main() {
  group('encodeSerialFrame', () {
    test('writes <, little-endian length, then payload', () {
      final Uint8List out = encodeSerialFrame(<int>[0x16, 0x01]);
      expect(out, <int>[0x3C, 0x02, 0x00, 0x16, 0x01]);
    });

    test('accepts the firmware ceiling and refuses one more', () {
      expect(encodeSerialFrame(List<int>.filled(176, 0)).length, 179);
      expect(
        () => encodeSerialFrame(List<int>.filled(177, 0)),
        throwsArgumentError,
      );
    });

    test('refuses an empty frame', () {
      expect(() => encodeSerialFrame(const <int>[]), throwsArgumentError);
    });
  });

  group('SerialFrameDecoder', () {
    test('decodes a frame split across three reads', () {
      final SerialFrameDecoder d = SerialFrameDecoder();
      expect(d.add(<int>[0x3E]), isEmpty);
      expect(d.add(<int>[0x03, 0x00]), isEmpty);
      final List<Uint8List> frames = d.add(<int>[0x01, 0x02, 0x03]);
      expect(frames, hasLength(1));
      expect(frames.single, <int>[0x01, 0x02, 0x03]);
    });

    test('decodes back-to-back frames in one read', () {
      final SerialFrameDecoder d = SerialFrameDecoder();
      final List<Uint8List> frames = d.add(<int>[
        0x3E, 0x01, 0x00, 0xAA, //
        0x3E, 0x02, 0x00, 0xBB, 0xCC,
      ]);
      expect(frames, hasLength(2));
      expect(frames[0], <int>[0xAA]);
      expect(frames[1], <int>[0xBB, 0xCC]);
    });

    test('discards bytes before a header', () {
      final SerialFrameDecoder d = SerialFrameDecoder();
      final List<Uint8List> frames =
          d.add(<int>[0x00, 0xFF, 0x3E, 0x01, 0x00, 0x7F]);
      expect(frames.single, <int>[0x7F]);
    });

    test('a length above the firmware ceiling is fatal and sticky', () {
      final SerialFrameDecoder d = SerialFrameDecoder();
      expect(
        () => d.add(<int>[0x3E, 0xC0, 0x00]),
        throwsA(isA<SerialFramingError>()),
      );
      expect(d.hasFailed, isTrue);
      expect(d.add(<int>[0x3E, 0x01, 0x00, 0x01]), isEmpty);
    });

    test('a zero-length frame is a false header, not a frame', () {
      final SerialFrameDecoder d = SerialFrameDecoder();
      final List<Uint8List> frames =
          d.add(<int>[0x3E, 0x00, 0x00, 0x3E, 0x01, 0x00, 0x42]);
      expect(frames.single, <int>[0x42]);
    });

    test('the firmware ceiling is a legal frame', () {
      final SerialFrameDecoder d = SerialFrameDecoder();
      final Uint8List payload = Uint8List(176);
      final List<Uint8List> frames =
          d.add(<int>[0x3E, 0xB0, 0x00, ...payload]);
      expect(frames.single, hasLength(176));
    });
  });
}
