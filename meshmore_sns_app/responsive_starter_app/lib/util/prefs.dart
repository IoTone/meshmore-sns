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

  static void _note() => dropped.value = dropped.value + 1;

  @visibleForTesting
  static void reset() => dropped.value = 0;
}
