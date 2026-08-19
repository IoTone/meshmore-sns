// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:shared_preferences/shared_preferences.dart';

/// R58 — whether inbound DMs from one peer are spoken aloud.
///
/// Tri-state rather than a bool so "follow the global switch" stays
/// expressible: a peer the user has never thought about must keep
/// tracking the global setting, while an explicit choice outranks it
/// in **both** directions (same shape as R24's per-channel
/// overrides).
enum PeerSpeechMode {
  /// No opinion — follow `TtsController.enabled`. The default, and
  /// the state of every peer the user has not configured.
  inherit,

  /// Speak this peer even when the global switch is off. This is the
  /// point of the feature: one favourite radio you always hear.
  always,

  /// Never speak this peer, even when the global switch is on.
  never;

  static PeerSpeechMode fromId(String? id) => switch (id) {
        'always' => PeerSpeechMode.always,
        'never' => PeerSpeechMode.never,
        _ => PeerSpeechMode.inherit,
      };

  String get id => name;
}

/// Persisted per-peer [PeerSpeechMode], keyed by node pubkey hex.
///
/// Only peers with an explicit override are stored — an override is
/// an act of attention (like a favourite), so `inherit` is expressed
/// by absence rather than by a row. Keying on pubkey means the
/// choice survives a peer being deleted and re-added (R56).
///
/// Wire format is a `StringList` of `<pubKeyHex>|<mode>`, matching
/// how `FavoriteStore` keeps its set.
abstract final class PeerSpeechStore {
  static const String _kKey = 'mm.tts.peerSpeech.v1';

  static Future<Map<String, PeerSpeechMode>> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final List<String>? rows = p.getStringList(_kKey);
    if (rows == null) return <String, PeerSpeechMode>{};
    final Map<String, PeerSpeechMode> out = <String, PeerSpeechMode>{};
    for (final String row in rows) {
      final int sep = row.indexOf('|');
      if (sep <= 0) continue; // malformed — drop rather than throw
      final PeerSpeechMode m =
          PeerSpeechMode.fromId(row.substring(sep + 1));
      if (m == PeerSpeechMode.inherit) continue; // never stored
      out[row.substring(0, sep).toLowerCase()] = m;
    }
    return out;
  }

  static Future<void> save(Map<String, PeerSpeechMode> modes) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final List<String> rows = <String>[
      for (final MapEntry<String, PeerSpeechMode> e in modes.entries)
        if (e.value != PeerSpeechMode.inherit) '${e.key}|${e.value.id}',
    ];
    if (rows.isEmpty) {
      await p.remove(_kKey);
      return;
    }
    await p.setStringList(_kKey, rows);
  }

  static Future<void> clear() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
  }
}
