// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart';

/// One object that can seal a byte string so only this device can open it
/// again.
///
/// The key is the whole point: [KeystoreRecordCipher] never holds one in
/// Dart. The Android Keystore generates an AES-256 key under an alias, marks
/// it non-exportable, and does the AES-GCM work inside the platform. A backup
/// of the ciphertext is therefore unreadable anywhere else, which is why the
/// store is excluded from Auto Backup rather than merely encrypted.
abstract interface class RecordCipher {
  /// Seals [plain]. The result carries whatever the implementation needs to
  /// open it again (nonce and tag for AES-GCM), so it must be stored whole.
  Future<Uint8List> seal(Uint8List plain);

  /// Opens bytes produced by [seal]. Throws [SealedDataCorrupt] when the
  /// bytes were altered, truncated, or sealed by a different key.
  Future<Uint8List> open(Uint8List sealed);
}

/// The device cannot seal: no platform key, or the platform call failed.
/// Callers keep their data in the place it already was rather than losing it.
class RecordCipherUnavailable implements Exception {
  const RecordCipherUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'RecordCipherUnavailable($reason)';
}

/// The sealed bytes do not open: wrong key, tampered, or truncated.
class SealedDataCorrupt implements Exception {
  const SealedDataCorrupt(this.reason);
  final String reason;
  @override
  String toString() => 'SealedDataCorrupt($reason)';
}

/// The platform holds no key under this store's alias, so the bytes were
/// sealed somewhere else: a restore onto a new device, a credential reset, or
/// a cleared Keystore. The data is intact and unreadable *here*. Kept apart
/// from [SealedDataCorrupt] because the answers differ: corruption is a file
/// that cannot be trusted, this is a file that can.
class RecordCipherKeyLost implements Exception {
  const RecordCipherKeyLost(this.reason);
  final String reason;
  @override
  String toString() => 'RecordCipherKeyLost($reason)';
}

/// AES-256-GCM sealed by the Android Keystore.
///
/// The Dart side only passes bytes over the channel; the key material is
/// generated with `KeyGenParameterSpec` in the platform keystore, is not
/// exportable, and cannot be read back even by this app.
class KeystoreRecordCipher implements RecordCipher {
  const KeystoreRecordCipher();

  static const MethodChannel channel =
      MethodChannel('meshmore/secure_store');

  @override
  Future<Uint8List> seal(Uint8List plain) async {
    try {
      final Uint8List? out =
          await channel.invokeMethod<Uint8List>('seal', <String, Object>{
        'data': plain,
      });
      if (out == null) {
        throw const RecordCipherUnavailable('seal returned nothing');
      }
      return out;
    } on MissingPluginException {
      throw const RecordCipherUnavailable('no platform keystore channel');
    } on PlatformException catch (e) {
      throw RecordCipherUnavailable(e.code);
    }
  }

  @override
  Future<Uint8List> open(Uint8List sealed) async {
    try {
      final Uint8List? out =
          await channel.invokeMethod<Uint8List>('open', <String, Object>{
        'data': sealed,
      });
      if (out == null) {
        throw const SealedDataCorrupt('open returned nothing');
      }
      return out;
    } on MissingPluginException {
      throw const RecordCipherUnavailable('no platform keystore channel');
    } on PlatformException catch (e) {
      if (e.code == 'corrupt') throw SealedDataCorrupt(e.message ?? 'open');
      if (e.code == 'stale_key') throw RecordCipherKeyLost(e.message ?? 'open');
      throw RecordCipherUnavailable(e.code);
    }
  }
}

/// AES-256-GCM with a key in memory. The store's tests and any non-Android
/// host use this; the app on a phone uses [KeystoreRecordCipher].
class MemoryRecordCipher implements RecordCipher {
  MemoryRecordCipher(this.key)
      : assert(key.length == 32, 'AES-256 needs a 32-byte key');

  /// A cipher with a fresh random key, for a test that only needs the round
  /// trip.
  factory MemoryRecordCipher.random() {
    final Random r = Random.secure();
    return MemoryRecordCipher(
        Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256))));
  }

  final Uint8List key;

  static const int nonceBytes = 12;
  static const int tagBits = 128;

  @override
  Future<Uint8List> seal(Uint8List plain) async {
    final Random r = Random.secure();
    final Uint8List nonce =
        Uint8List.fromList(List<int>.generate(nonceBytes, (_) => r.nextInt(256)));
    final GCMBlockCipher c = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), tagBits, nonce, Uint8List(0)));
    final Uint8List body = c.process(plain);
    return Uint8List.fromList(<int>[...nonce, ...body]);
  }

  @override
  Future<Uint8List> open(Uint8List sealed) async {
    if (sealed.length < nonceBytes + tagBits ~/ 8) {
      throw const SealedDataCorrupt('shorter than a nonce and a tag');
    }
    final Uint8List nonce = sealed.sublist(0, nonceBytes);
    final Uint8List body = sealed.sublist(nonceBytes);
    final GCMBlockCipher c = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), tagBits, nonce, Uint8List(0)));
    try {
      return c.process(body);
    } on InvalidCipherTextException {
      throw const SealedDataCorrupt('tag mismatch');
    }
  }
}
