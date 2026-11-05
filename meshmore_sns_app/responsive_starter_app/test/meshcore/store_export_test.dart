// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/secure/store_export.dart';

/// APP-E3 / D8.8 — the export is the one supported way history leaves the
/// device, and it is encrypted with a passphrase the user chooses because the
/// device key cannot be exported.
void main() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));
  final Map<String, Uint8List> records = <String, Uint8List>{
    'chat': b('[{"text":"hello mesh"}]'),
    'places': b('[]'),
  };

  // A test-sized cost: the point is the format, not the wall clock.
  const int iterations = 1500;

  test('a record map round-trips through the passphrase', () {
    final Uint8List file =
        StoreExport.encode(records, 'correct horse', iterations: iterations);
    final Map<String, Uint8List> back =
        StoreExport.decode(file, 'correct horse');
    expect(back.keys.toSet(), records.keys.toSet());
    expect(utf8.decode(back['chat']!), utf8.decode(records['chat']!));
  });

  test('the header carries the KDF and its parameters', () {
    final Uint8List file =
        StoreExport.encode(records, 'pw', iterations: iterations);
    expect(file.sublist(0, 4), StoreExport.magic);
    expect(file[4], StoreExport.formatVersion);
    expect(file[5], StoreExport.kdfPbkdf2HmacSha256);
    final int written =
        (file[6] << 24) | (file[7] << 16) | (file[8] << 8) | file[9];
    expect(written, iterations,
        reason: 'an import years later must derive the same key');
  });

  test('the file is not readable as text', () {
    final Uint8List file = StoreExport.encode(records, 'pw', iterations: iterations);
    expect(utf8.decode(file, allowMalformed: true), isNot(contains('hello mesh')));
  });

  test('a wrong passphrase is refused as a named outcome, not a throw', () {
    final Uint8List file =
        StoreExport.encode(records, 'right', iterations: iterations);
    expect(
      () => StoreExport.decode(file, 'wrong'),
      throwsA(isA<ExportRefused>().having(
          (ExportRefused e) => e.reason, 'reason', contains('wrong passphrase'))),
    );
  });

  test('an altered byte is refused', () {
    final Uint8List file =
        StoreExport.encode(records, 'pw', iterations: iterations);
    final Uint8List tampered = Uint8List.fromList(file);
    tampered[tampered.length - 1] ^= 0xFF;
    expect(() => StoreExport.decode(tampered, 'pw'),
        throwsA(isA<ExportRefused>()));
  });

  test('a truncated file is refused before any key derivation', () {
    final Uint8List file =
        StoreExport.encode(records, 'pw', iterations: iterations);
    expect(() => StoreExport.decode(file.sublist(0, 10), 'pw'),
        throwsA(isA<ExportRefused>().having(
            (ExportRefused e) => e.reason, 'reason', contains('header'))));
  });

  test('a foreign file is refused', () {
    expect(() => StoreExport.decode(b('MMS1not an export at all'), 'pw'),
        throwsA(isA<ExportRefused>()));
  });

  test('an implausible iteration count is refused rather than run', () {
    final Uint8List file =
        StoreExport.encode(records, 'pw', iterations: iterations);
    final Uint8List forged = Uint8List.fromList(file);
    // 2^31 iterations: a file like this must not hang the app.
    forged[6] = 0x80;
    forged[7] = 0;
    forged[8] = 0;
    forged[9] = 0;
    expect(() => StoreExport.decode(forged, 'pw'),
        throwsA(isA<ExportRefused>()));
  });

  test('an empty passphrase is refused at export', () {
    expect(() => StoreExport.encode(records, '   ', iterations: iterations),
        throwsA(isA<ExportRefused>()));
  });

  test('the default iteration count is what the format promises', () {
    expect(StoreExport.defaultIterations, greaterThanOrEqualTo(200000));
    expect(StoreExport.saltBytes, 16);
  });
}
