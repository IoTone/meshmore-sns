// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart';

import 'record_cipher.dart';

/// The export does not open: wrong passphrase, truncated, or not an export.
class ExportRefused implements Exception {
  const ExportRefused(this.reason);
  final String reason;
  @override
  String toString() => 'ExportRefused($reason)';
}

/// Export and import of the sealed store with a **user passphrase** — the one
/// supported way off the device, because the device key cannot leave the
/// Keystore and a backup of the ciphertext would be useless anywhere else.
///
/// Format: `MMEX` | format version u8 | KDF id u8 | iterations u32 big-endian |
/// salt 16 | AES-GCM sealed payload (nonce 12 | ciphertext | tag 16). The
/// parameters travel with the file so an import years later derives the same
/// key, and so a future KDF change is a version bump rather than a guess.
///
/// KDF id 1 = PBKDF2-HMAC-SHA256. The iteration count is written, not assumed:
/// raising it must not orphan old exports.
abstract final class StoreExport {
  static const List<int> magic = <int>[0x4D, 0x4D, 0x45, 0x58]; // 'MMEX'
  static const int formatVersion = 1;
  static const int kdfPbkdf2HmacSha256 = 1;

  /// Deliberately slow: a passphrase a person can remember is a small search
  /// space, and the only defence is making each guess cost this much.
  static const int defaultIterations = 210000;
  static const int saltBytes = 16;

  /// The most iterations an import will honour: four times what this build
  /// writes. The count travels in the file, so a crafted header claiming ten
  /// million would be minutes of key stretching on the UI thread — a denial of
  /// service, not a passphrase.
  static const int maxAcceptedIterations = defaultIterations * 4;

  static Uint8List encode(Map<String, Uint8List> records,
      String passphrase,
      {int iterations = defaultIterations}) {
    if (passphrase.trim().isEmpty) {
      throw const ExportRefused('a passphrase is required');
    }
    final Random r = Random.secure();
    final Uint8List salt =
        Uint8List.fromList(List<int>.generate(saltBytes, (_) => r.nextInt(256)));
    final Uint8List key = _derive(passphrase, salt, iterations);
    final Uint8List plain = Uint8List.fromList(utf8.encode(jsonEncode(
        <String, String>{
      for (final MapEntry<String, Uint8List> e in records.entries)
        e.key: base64Encode(e.value),
    })));
    final Uint8List sealed = _seal(key, plain);
    return Uint8List.fromList(<int>[
      ...magic,
      formatVersion,
      kdfPbkdf2HmacSha256,
      ..._u32(iterations),
      ...salt,
      ...sealed,
    ]);
  }

  static Map<String, Uint8List> decode(Uint8List bytes, String passphrase) {
    const int header = 4 + 1 + 1 + 4 + saltBytes;
    if (bytes.length <= header) {
      throw const ExportRefused('shorter than an export header');
    }
    for (int i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) {
        throw const ExportRefused('not a MeshMore export');
      }
    }
    final int version = bytes[4];
    if (version != formatVersion) {
      throw ExportRefused('format version $version');
    }
    final int kdf = bytes[5];
    if (kdf != kdfPbkdf2HmacSha256) {
      throw ExportRefused('unknown key derivation $kdf');
    }
    final int iterations =
        (bytes[6] << 24) | (bytes[7] << 16) | (bytes[8] << 8) | bytes[9];
    if (iterations < 1000 || iterations > maxAcceptedIterations) {
      throw ExportRefused('implausible iteration count $iterations');
    }
    final Uint8List salt = bytes.sublist(10, 10 + saltBytes);
    final Uint8List key = _derive(passphrase, salt, iterations);
    final Uint8List plain;
    try {
      plain = _open(key, bytes.sublist(header));
    } on SealedDataCorrupt {
      // A wrong passphrase and an altered file are the same failure to the
      // format, and saying which would tell an attacker whether they guessed.
      throw const ExportRefused('wrong passphrase, or the file was altered');
    }
    try {
      final Object? decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map<String, Object?>) {
        throw const ExportRefused('payload is not a record map');
      }
      return <String, Uint8List>{
        for (final MapEntry<String, Object?> e in decoded.entries)
          e.key: base64Decode(e.value! as String),
      };
    } on FormatException {
      throw const ExportRefused('payload is not decodable');
    } on TypeError {
      throw const ExportRefused('payload has a non-string value');
    }
  }

  /// The same work off the UI isolate: the KDF is deliberately slow, and a
  /// slow call on the frame thread is a frozen app (an ANR on a low-end
  /// phone), whether it takes a second or a minute.
  static Future<Uint8List> encodeAsync(Map<String, Uint8List> records,
          String passphrase,
          {int iterations = defaultIterations}) =>
      Isolate.run(() => encode(records, passphrase, iterations: iterations));

  static Future<Map<String, Uint8List>> decodeAsync(
          Uint8List bytes, String passphrase) =>
      Isolate.run(() => decode(bytes, passphrase));

  static Uint8List _derive(String passphrase, Uint8List salt, int iterations) {
    final PBKDF2KeyDerivator d =
        PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
          ..init(Pbkdf2Parameters(salt, iterations, 32));
    return d.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  static Uint8List _seal(Uint8List key, Uint8List plain) {
    final Random r = Random.secure();
    final Uint8List nonce = Uint8List.fromList(
        List<int>.generate(MemoryRecordCipher.nonceBytes, (_) => r.nextInt(256)));
    final GCMBlockCipher c = GCMBlockCipher(AESEngine())
      ..init(
          true,
          AEADParameters(
              KeyParameter(key), MemoryRecordCipher.tagBits, nonce, Uint8List(0)));
    return Uint8List.fromList(<int>[...nonce, ...c.process(plain)]);
  }

  static Uint8List _open(Uint8List key, Uint8List sealed) {
    if (sealed.length <
        MemoryRecordCipher.nonceBytes + MemoryRecordCipher.tagBits ~/ 8) {
      throw const ExportRefused('shorter than a nonce and a tag');
    }
    final Uint8List nonce =
        sealed.sublist(0, MemoryRecordCipher.nonceBytes);
    final GCMBlockCipher c = GCMBlockCipher(AESEngine())
      ..init(
          false,
          AEADParameters(
              KeyParameter(key), MemoryRecordCipher.tagBits, nonce, Uint8List(0)));
    try {
      return c.process(sealed.sublist(MemoryRecordCipher.nonceBytes));
    } on InvalidCipherTextException {
      throw const SealedDataCorrupt('tag mismatch');
    }
  }

  static List<int> _u32(int v) =>
      <int>[(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
}
