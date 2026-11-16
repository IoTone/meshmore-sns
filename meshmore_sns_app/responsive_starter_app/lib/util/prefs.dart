// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preference reads that survive a value they did not expect.
///
/// A key's type can change between releases (an int becoming a double, a
/// string becoming a list), and a file can be edited by hand or restored from
/// another build. `getDouble` on an int throws a type error inside a load path,
/// where nothing catches it: the screen never paints. These readers coerce what
/// they can, fall back otherwise, and count what they dropped so a support
/// question has an answer.
abstract final class Prefs {
  /// Values this launch had to drop or coerce. Diagnostics reads it; a
  /// non-zero count is the difference between "the setting did not save" and
  /// "the setting was never readable".
  static final ValueNotifier<int> dropped = ValueNotifier<int>(0);

  static int readInt(SharedPreferences p, String key, {int fallback = 0}) {
    final Object? v = p.get(key);
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) {
      final int? parsed = int.tryParse(v);
      if (parsed != null) return parsed;
    }
    if (v != null) _note();
    return fallback;
  }

  static double readDouble(SharedPreferences p, String key,
      {double fallback = 0}) {
    final Object? v = p.get(key);
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) {
      final double? parsed = double.tryParse(v);
      if (parsed != null) return parsed;
    }
    if (v != null) _note();
    return fallback;
  }

  static bool readBool(SharedPreferences p, String key, {bool fallback = false}) {
    final Object? v = p.get(key);
    if (v is bool) return v;
    if (v is String) {
      if (v == 'true') return true;
      if (v == 'false') return false;
    }
    if (v != null) _note();
    return fallback;
  }

  static String? readString(SharedPreferences p, String key) {
    final Object? v = p.get(key);
    if (v == null) return null;
    if (v is String) return v;
    _note();
    return null;
  }

  /// True when a write this launch did not land: a full disk, a quota, or a
  /// platform refusal. `SharedPreferences.set*` returns a bool that every call
  /// site in the app used to discard, so "my setting did not stick" had no
  /// explanation anywhere. The dashboard's degraded state reads this.
  static final ValueNotifier<bool> writeFailed = ValueNotifier<bool>(false);

  static Future<bool> setString(SharedPreferences p, String k, String v) =>
      _write(p.setString(k, v));

  static Future<bool> setBool(SharedPreferences p, String k, bool v) =>
      _write(p.setBool(k, v));

  static Future<bool> setInt(SharedPreferences p, String k, int v) =>
      _write(p.setInt(k, v));

  static Future<bool> setDouble(SharedPreferences p, String k, double v) =>
      _write(p.setDouble(k, v));

  static Future<bool> setStringList(
      SharedPreferences p, String k, List<String> v) =>
      _write(p.setStringList(k, v));

  static Future<bool> _write(Future<bool> pending) async {
    bool ok;
    try {
      ok = await pending;
    } catch (_) {
      ok = false;
    }
    // Sticky for the session: a write that failed once means the device is out
    // of room, and retrying every later write would only add noise.
    if (!ok) writeFailed.value = true;
    return ok;
  }

  /// Test seam: the platform's write result, without a platform. A real
  /// `SharedPreferences` in a test always reports success, so the failure path
  /// would never run.
  @visibleForTesting
  static Future<bool> probeWrite(Future<bool> pending) => _write(pending);

  static void _note() => dropped.value = dropped.value + 1;

  @visibleForTesting
  static void reset() {
    dropped.value = 0;
    writeFailed.value = false;
  }
}
