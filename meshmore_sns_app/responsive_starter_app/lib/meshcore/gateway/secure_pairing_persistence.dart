// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';

/// The gateway pairing token in platform secure storage (Android Keystore
/// backed encrypted preferences, iOS Keychain).
///
/// Never SharedPreferences: those are backed up and readable off a rooted or
/// backed-up device (`meshmore-sns-architecture-audit.md` D5). Errors from the
/// plugin are NOT swallowed and there is NO fallback store. A failure here
/// stops the gateway from starting; the caller reports it.
class SecurePairingPersistence implements PairingPersistence {
  SecurePairingPersistence({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const String key = 'mm.gateway.pairing_token.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<Uint8List?> load() async {
    final String? raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      final Uint8List bytes = base64Decode(raw);
      // A wrong-sized value is corrupt, not a token. null makes the store
      // issue a fresh one, which is the safe direction (it revokes).
      return bytes.length == GatewayLimits.pairingTokenBytes ? bytes : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(Uint8List token) =>
      _storage.write(key: key, value: base64Encode(token));

  @override
  Future<void> clear() => _storage.delete(key: key);
}
