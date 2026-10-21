// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:shared_preferences/shared_preferences.dart';

/// The basemap the user last chose, so relaunching does not silently put the
/// streets back. `null` means the vector basemap (the default); any other
/// value is the id of a raster source, built-in or custom.
///
/// This is a preference, not cached data: losing it costs one tap, so it is
/// stored plainly rather than versioned like `maps.state.v1`.
abstract final class BasemapPrefs {
  static const String _kKey = 'mm.basemap.v1';

  static Future<String?> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? v = p.getString(_kKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> save(String? rasterId) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    if (rasterId == null) {
      await p.remove(_kKey);
    } else {
      await p.setString(_kKey, rasterId);
    }
  }
}
