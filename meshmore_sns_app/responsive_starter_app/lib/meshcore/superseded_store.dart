// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:shared_preferences/shared_preferences.dart';
import '../util/prefs.dart';

/// Persisted set of **superseded** node public keys (hex) — old keys the
/// user reconciled away when a contact returned under a new key (R56).
///
/// `CMD_REMOVE_CONTACT` (0x0F) does exist and `reconcileIdentity` sends it, so
/// the radio stops holding the dead key. This set covers the window before the
/// radio drops it, and the case where the frame never landed: a reconnect that
/// still syncs the old contact has to know it is superseded rather than let the
/// reconciled-away identity reappear as a confusing duplicate.
abstract final class SupersededStore {
  static const String _kKey = 'mm.superseded.v1';

  static Future<Set<String>> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final List<String>? v = p.getStringList(_kKey);
    return v == null ? <String>{} : v.toSet();
  }

  static Future<void> save(Set<String> pubKeyHexes) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setStringList(p, _kKey, pubKeyHexes.toList(growable: false));
  }
}
