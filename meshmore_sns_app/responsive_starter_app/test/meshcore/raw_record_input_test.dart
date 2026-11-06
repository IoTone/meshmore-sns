// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/raw_record_input.dart';

/// The typed-hex side of the raw-record tool.
///
/// Nothing here reaches a radio, and that is the point: every refusal is
/// decided before a frame exists, so a typo cannot become a command.
void main() {
  group('accepted shapes', () {
    test('space-separated pairs decode', () {
      final RawRecordInput r = parseRawRecord('01 02 ab cd');
      expect(r.ok, isTrue);
      expect(r.bytes, Uint8List.fromList(<int>[0x01, 0x02, 0xAB, 0xCD]));
      expect(r.length, 4);
    });

    test('one continuous run decodes to the same bytes', () {
      final RawRecordInput r = parseRawRecord('0102abcd');
      expect(r.bytes, Uint8List.fromList(<int>[0x01, 0x02, 0xAB, 0xCD]));
    });

    test('a mixed run decodes, so a pasted capture works', () {
      final RawRecordInput r = parseRawRecord('01 02ab\ncd');
      expect(r.bytes, Uint8List.fromList(<int>[0x01, 0x02, 0xAB, 0xCD]));
    });

    test('upper case is the same byte', () {
      expect(parseRawRecord('AB CD EF 01').bytes,
          parseRawRecord('ab cd ef 01').bytes);
    });
  });

  group('refusals', () {
    test('nothing typed is its own refusal', () {
      expect(parseRawRecord('').refusal, RawRecordRefusal.empty);
      expect(parseRawRecord('   \n ').refusal, RawRecordRefusal.empty);
      expect(parseRawRecord('').bytes, isNull);
    });

    test('an odd run is not hex, because it cannot be pairs', () {
      expect(parseRawRecord('010').refusal, RawRecordRefusal.notHex);
    });

    test('a non-hex character is not hex', () {
      expect(parseRawRecord('0x0102').refusal, RawRecordRefusal.notHex);
      expect(parseRawRecord('01 02 zz 04').refusal, RawRecordRefusal.notHex);
    });

    test('a refusal still reports the byte count that was typed', () {
      // The counter beside the field has to say something for bad input too.
      expect(parseRawRecord('01 02 ab').length, 3);
    });

    test('under the raw-data minimum is too short, not too long', () {
      final RawRecordInput r = parseRawRecord('01 02 ab');
      expect(r.refusal, RawRecordRefusal.tooShort);
      expect(r.bytes, isNull);
      // The firmware's handler needs 4 bytes; the constant is the authority.
      expect(MeshCarryLimits.rawDataMinPayload, 4);
    });

    test('the minimum itself is accepted', () {
      expect(parseRawRecord('01 02 03 04').ok, isTrue);
    });
  });

  group('the budget boundary', () {
    String hexOf(int n) =>
        List<int>.filled(n, 0x5A).map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

    test('the frame ceiling is the frame, not the record, and it is a constant',
        () {
      expect(MeshCarryLimits.maxFrameSize, 176);
      expect(parseRawRecord(hexOf(176)).ok, isTrue);
      expect(parseRawRecord(hexOf(177)).refusal, RawRecordRefusal.tooLong);
    });

    test('a contact budget one byte over is refused at that budget', () {
      final int max = MeshCarryLimits.rawDataPayloadMax(2); // 172 for a 2-byte path
      expect(parseRawRecord(hexOf(max), maxBytes: max).ok, isTrue);
      expect(parseRawRecord(hexOf(max + 1), maxBytes: max).refusal,
          RawRecordRefusal.tooLong);
    });
  });
}
