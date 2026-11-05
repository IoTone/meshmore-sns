// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'radio_config_transaction.dart';
import '../util/prefs.dart';

/// Remembers the operating point a radio was running before the app changed
/// it, so a mistake can be taken back once.
///
/// The record is written **before** the first frame of the transaction leaves
/// the phone: if the phone dies, the app is killed, or the link drops halfway,
/// the value to come back to is already on disk. The revert is single-use on
/// purpose — it restores a remembered point, and applying it twice would
/// rewrite the radio with stale values if the user has since moved on
/// deliberately.
abstract final class RadioSafetyStore {
  /// JSON of the point the radio ran before the last transaction.
  static const String _kArmed = 'mm.radio.safety.armed';

  /// The key the radio's identity is stored under, so a different radio does
  /// not inherit another one's revert target. A changed key is a new radio
  /// (D8.7), and its previous operating point is unknown.
  static const String _kArmedFor = 'mm.radio.safety.armedFor';

  static Future<void> arm(String radioKey, RadioOperatingPoint previous) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setString(p, _kArmed, jsonEncode(previous.toJson()));
    await Prefs.setString(p, _kArmedFor, radioKey);
  }

  /// The point [arm] recorded for [radioKey], or null. Read-only: the record
  /// stays until [consume] or [clear], so the caller can decide.
  static Future<RadioOperatingPoint?> armed(String radioKey) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    if (p.getString(_kArmedFor) != radioKey) return null;
    final String? raw = p.getString(_kArmed);
    if (raw == null) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      return RadioOperatingPoint.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  /// Takes the recorded point and forgets it in the same step, so a second
  /// revert cannot happen: the record is removed before the caller writes
  /// anything, and a failed revert leaves the radio on its current values
  /// rather than arming a second attempt.
  static Future<RadioOperatingPoint?> consume(String radioKey) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    if (p.getString(_kArmedFor) != radioKey) return null;
    final String? raw = p.getString(_kArmed);
    await clear();
    if (raw == null) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      return RadioOperatingPoint.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  static Future<void> clear() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.remove(_kArmed);
    await p.remove(_kArmedFor);
  }
}
