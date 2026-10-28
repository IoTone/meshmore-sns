// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math';
import 'dart:typed_data';

import 'constants.dart';
import 'messages.dart';

/// Where the pairing token survives a restart.
///
/// The app supplies a platform-secure-storage implementation (Android
/// Keystore-backed, iOS Keychain). It must never land in
/// `SharedPreferences`: Android backup rules today exclude only `maps/`
/// (audit D1).
abstract interface class PairingPersistence {
  Future<Uint8List?> load();
  Future<void> save(Uint8List token);
  Future<void> clear();
}

/// [PairingPersistence] that forgets on restart. Tests and previews only.
class InMemoryPairingPersistence implements PairingPersistence {
  Uint8List? _token;

  @override
  Future<Uint8List?> load() async =>
      _token == null ? null : Uint8List.fromList(_token!);

  @override
  Future<void> save(Uint8List token) async =>
      _token = Uint8List.fromList(token);

  @override
  Future<void> clear() async => _token = null;
}

/// The one pairing grant v1 supports.
///
/// Reissue is revocation: a new token is generated and the old one stops
/// matching, with no grace period.
class PairingStore {
  PairingStore({PairingPersistence? persistence, Random? random})
      : _persistence = persistence ?? InMemoryPairingPersistence(),
        _random = random ?? Random.secure() {
    _token = _generate();
  }

  final PairingPersistence _persistence;
  final Random _random;
  late Uint8List _token;

  /// A copy, so a caller cannot mutate the live token.
  Uint8List get token => Uint8List.fromList(_token);

  /// Load the persisted token, or generate and persist one.
  Future<void> load() async {
    final Uint8List? stored = await _persistence.load();
    if (stored != null && stored.length == GatewayLimits.pairingTokenBytes) {
      _token = Uint8List.fromList(stored);
      return;
    }
    _token = _generate();
    await _persistence.save(_token);
  }

  /// Revoke the current token and issue a new one.
  Future<void> reissue() async {
    _token = _generate();
    await _persistence.save(_token);
  }

  /// Forget the persisted token. A fresh one is generated on the next
  /// [load]; the in-memory token is rotated immediately so the old one stops
  /// matching now rather than at the next start.
  Future<void> clear() async {
    await _persistence.clear();
    _token = _generate();
  }

  /// Constant-time comparison. Any presented length is accepted.
  bool verify(List<int> presented) =>
      pairingTokenMatches(presented: presented, stored: _token);

  Uint8List _generate() {
    final Uint8List out = Uint8List(GatewayLimits.pairingTokenBytes);
    for (int i = 0; i < out.length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }
}
