// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../util/prefs.dart';

/// Persisted opt-in for the Android background keep-alive foreground
/// service (R17 / U8). Default **on** — the user accepted the
/// persistent notification as the cost of reliable background
/// delivery; users can still turn it off in App settings.
abstract final class BackgroundKeepalivePrefs {
  static const String _kEnabled = 'mm.bg.keepalive';

  static Future<bool> enabled() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return p.getBool(_kEnabled) ?? true;
  }

  static Future<void> setEnabled(bool v) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setBool(p, _kEnabled, v);
  }
}

/// Persisted opt-in for the background peer-telemetry poller — the
/// controller politely cycles through synced contacts requesting
/// telemetry so temperature / altitude populate across the fabric
/// without the user tapping each node. Default **on** but
/// airtime-conscious (one request per ~10 s, capped attempts, then
/// quiet). Toggle in App settings.
abstract final class TelemetryPollPrefs {
  static const String _kEnabled = 'mm.telemetryPoll';

  static Future<bool> enabled() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return p.getBool(_kEnabled) ?? true;
  }

  static Future<void> setEnabled(bool v) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setBool(p, _kEnabled, v);
  }
}

/// R62 — opt-in for the **periodic position-bearing self-advert**.
///
/// While connected the controller used to send a zero-hop self-advert
/// every 60 s (to coax a fresh GPS read into SelfInfo). That is real
/// over-the-air traffic that stock companion firmware never emits, and
/// it publishes the node's position on a schedule the user never chose.
/// Default **off**; see `MeshcoreController.periodicAdvertEnabled`.
abstract final class PeriodicAdvertPrefs {
  static const String _kEnabled = 'mm.advert.periodicBeacon';

  static Future<bool> enabled() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return p.getBool(_kEnabled) ?? false;
  }

  static Future<void> setEnabled(bool v) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setBool(p, _kEnabled, v);
  }
}

/// R54 — per-channel opt-in for **place names in messages**: when on for a
/// channel, a message on it that names a place gets one line under the row
/// offering to report that place, and nothing is placed on a map. Stored as
/// a JSON map of `channelIdx → bool` of *explicit* overrides; channels with
/// no override fall back to the default, which is **on only for the public
/// channel** (index [publicChannelIndex]) and off elsewhere.
abstract final class PlaceInferencePrefs {
  static const String _kMap = 'mm.placeInfer.channels';
  static const int publicChannelIndex = 0;

  /// The effective default when a channel has no explicit override.
  static bool defaultFor(int channelIdx) => channelIdx == publicChannelIndex;

  /// Load the explicit per-channel overrides.
  static Future<Map<int, bool>> overrides() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(_kMap);
    if (raw == null || raw.isEmpty) return <int, bool>{};
    try {
      final Map<String, dynamic> m = jsonDecode(raw) as Map<String, dynamic>;
      return <int, bool>{
        for (final MapEntry<String, dynamic> e in m.entries)
          if (int.tryParse(e.key) != null) int.parse(e.key): e.value == true,
      };
    } catch (_) {
      return <int, bool>{};
    }
  }

  static Future<void> save(Map<int, bool> overrides) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setString(p, 
      _kMap,
      jsonEncode(<String, bool>{
        for (final MapEntry<int, bool> e in overrides.entries)
          '${e.key}': e.value,
      }),
    );
  }
}

/// The place suggestions a user has already said no to.
///
/// A suggestion is computed from the words of a message, so it is keyed by a
/// hash of those words rather than by a message id: the same sentence offers
/// the same suggestion wherever it arrives, and a message restored from an
/// export has a new id but the same text. Keys are a hash, not the text, because the
/// text is message content and this file is not sealed.
///
/// The list is bounded. A dismissal is a small opinion about a sentence, and
/// keeping every one forever would slowly turn a preference into a transcript.
abstract final class PlaceSuggestionDismissals {
  static const String _kMap = 'mm.placeSuggest.dismissed';
  static const int cap = 200;

  /// The stable key for one message's suggestion.
  static String keyFor(int channelIdx, String text) =>
      '$channelIdx:${_fnv1a(text)}';

  static Future<Set<String>> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return <String>{...p.getStringList(_kMap) ?? const <String>[]};
  }

  /// Persist [keys], dropping the oldest when the list is over [cap].
  ///
  /// Insertion order is the order they were dismissed, which is the order
  /// shared_preferences keeps, so the first entries are the oldest.
  static Future<void> save(Set<String> keys) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final List<String> all = keys.toList();
    final List<String> kept =
        all.length <= cap ? all : all.sublist(all.length - cap);
    await Prefs.setStringList(p, _kMap, kept);
  }

  /// FNV-1a over the UTF-16 units. Stable across runs and machines, which
  /// `Object.hash` is not: a dismissal has to survive the process.
  static String _fnv1a(String s) {
    int h = 0x811c9dc5;
    for (final int unit in s.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
