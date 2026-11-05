// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'mesh_network.dart';

/// Persisted list of [MeshNetwork]s.
///
/// Radio numbers and public keys only, so SharedPreferences is appropriate:
/// nothing here is a secret. Anything secret — a credential, a key — must not
/// be stored this way (`meshmore-sns-architecture-audit.md` D5).
abstract final class MeshNetworkStore {
  static const String _kKey = 'mm.networks.v1';

  /// Entries that fail to parse are skipped, never fatal.
  static Future<List<MeshNetwork>> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(_kKey);
    if (raw == null) return <MeshNetwork>[];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return <MeshNetwork>[];
    }
    if (decoded is! List<dynamic>) return <MeshNetwork>[];
    return <MeshNetwork>[
      for (final Object? e in decoded)
        if (MeshNetwork.tryFromJson(e) case final MeshNetwork n) n,
    ];
  }

  /// Replaces the stored list. Ids must be unique.
  static Future<void> save(List<MeshNetwork> networks) async {
    final Set<String> ids = networks.map((MeshNetwork n) => n.id).toSet();
    if (ids.length != networks.length) {
      throw ArgumentError('duplicate network id');
    }
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(
      _kKey,
      jsonEncode(<Map<String, Object?>>[
        for (final MeshNetwork n in networks) n.toJson(),
      ]),
    );
  }

  static Future<void> clear() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
  }
}
