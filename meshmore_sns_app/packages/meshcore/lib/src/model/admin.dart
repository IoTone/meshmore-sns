// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import '../codec/constants.dart';

/// A MeshCore `path_len` byte: top 2 bits = hash size − 1, low 6 bits =
/// hop count (`src/Packet.cpp:20-30`, `Packet::writePath`).
class PathLen {
  const PathLen(this.raw);

  final int raw;

  int get hashSize => (raw >> 6) + 1;
  int get hopCount => raw & kPathHopMask;

  /// Bytes of path data that follow the length byte.
  int get byteLength => hashSize * hopCount;

  /// The firmware refuses to write a path longer than `MAX_PATH_SIZE`
  /// (`Packet.cpp:24-27`) and emits zero bytes instead.
  bool get isValid => byteLength <= kMaxPathSize;

  @override
  String toString() => 'PathLen($hopCount hop × $hashSize B)';
}

/// Decoded `RESP_CODE_ADVERT_PATH` (0x16), `MyMesh.cpp:1864-1869`.
///
/// ```
/// [16][recv_timestamp u32 LE][path_len][path hashes]
/// ```
class AdvertPath {
  const AdvertPath({
    required this.receivedAt,
    required this.pathLen,
    required this.path,
  });

  /// Device clock, seconds, when the advert was received.
  final int receivedAt;
  final PathLen pathLen;
  final Uint8List path;
}

/// Decoded `RESP_CODE_TUNING_PARAMS` (0x17), `MyMesh.cpp:1443-1450`.
///
/// ```
/// [17][rx_delay_base ×1000 u32 LE][airtime_factor ×1000 u32 LE]
/// ```
class TuningParams {
  const TuningParams({
    required this.rxDelayBaseSeconds,
    required this.airtimeFactor,
  });

  final double rxDelayBaseSeconds;

  /// Airtime factor `af`: the radio may transmit `1 / (1 + af)` of the
  /// time (`src/Dispatcher.cpp:25-27`). 0 = no limit.
  final double airtimeFactor;

  @override
  String toString() =>
      'TuningParams(rx=${rxDelayBaseSeconds}s, af=$airtimeFactor)';
}

/// Decoded `RESP_CODE_AUTOADD_CONFIG` (0x19), `MyMesh.cpp:1988-1993`.
///
/// ```
/// [19][flags][max_hops]
/// ```
class AutoAddConfig {
  const AutoAddConfig({required this.flags, required this.maxHops});

  final int flags;

  /// 0 = no limit, 1 = direct only, N = up to N−1 hops (`NodePrefs.h:41`).
  final int maxHops;

  bool get overwriteOldest => flags & kAutoAddOverwriteOldest != 0;
  bool get chat => flags & kAutoAddChat != 0;
  bool get repeater => flags & kAutoAddRepeater != 0;
  bool get roomServer => flags & kAutoAddRoomServer != 0;
  bool get sensor => flags & kAutoAddSensor != 0;

  @override
  String toString() => 'AutoAddConfig(flags=0x${flags.toRadixString(16)}, '
      'maxHops=$maxHops)';
}

/// Decoded `PUSH_CODE_LOGIN_SUCCESS` (0x85) or `PUSH_CODE_LOGIN_FAIL`
/// (0x86), `MyMesh.cpp:677-707`.
///
/// ```
/// success (new):    [85][permissions][pub6][server_ts u32][acl][fw_level]
/// success (legacy): [85][0][pub6]
/// fail:             [86][0][pub6]
/// ```
class LoginResult {
  const LoginResult({
    required this.success,
    required this.permissions,
    required this.pubKeyPrefix,
    this.serverTimestamp,
    this.aclPermissions,
    this.firmwareLevel,
  });

  final bool success;

  /// `data[6]` of the server reply (e.g. admin bit). 0 for a failure.
  final int permissions;
  final Uint8List pubKeyPrefix;

  /// Present only for the new-format success frame.
  final int? serverTimestamp;
  final int? aclPermissions;
  final int? firmwareLevel;

  /// True for a legacy repeater "OK" reply, which carries no extras.
  bool get isLegacy => success && serverTimestamp == null;
}

/// Decoded `PUSH_CODE_PATH_DISCOVERY_RESPONSE` (0x8D), `MyMesh.cpp:762-771`.
///
/// ```
/// [8D][0][pub6][out_path_len][out_path][in_path_len][in_path]
/// ```
class PathDiscoveryResult {
  const PathDiscoveryResult({
    required this.pubKeyPrefix,
    required this.outPathLen,
    required this.outPath,
    required this.inPathLen,
    required this.inPath,
  });

  final Uint8List pubKeyPrefix;
  final PathLen outPathLen;
  final Uint8List outPath;
  final PathLen inPathLen;
  final Uint8List inPath;
}
