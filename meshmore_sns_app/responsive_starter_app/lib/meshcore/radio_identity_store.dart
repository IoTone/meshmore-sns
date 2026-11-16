// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:shared_preferences/shared_preferences.dart';

/// Which radio this app last talked to, by its own public key.
///
/// The paired-device record is a BLE identity (a remote id and a name), which
/// the phone can hand out again after a radio is reflashed. The radio's key is
/// the one thing that changes when the device behind the link is replaced, so
/// it is what the app compares to notice that its history belongs to a
/// different node (D8.7).
abstract final class RadioIdentityStore {
  static const String _kKey = 'mm.radio.key';

  static Future<String?> read() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? v = p.getString(_kKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> save(String publicKeyHex) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_kKey, publicKeyHex);
  }

  static Future<void> clear() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
  }
}
