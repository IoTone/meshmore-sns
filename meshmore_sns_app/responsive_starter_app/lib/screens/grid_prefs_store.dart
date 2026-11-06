// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../util/prefs.dart';

/// Persisted last-used preferences for the hyperlocal grid screen, so the
/// chosen scale and refresh cadence survive leaving and
/// re-opening the grid (the screen is recreated on each navigation) and
/// app restarts. The chosen *view* is deliberately not here: it lasts
/// only for the session, and every launch opens on the radar (issue #4).
/// Old saves still carry a `mode` key; it is ignored.
class GridPrefs {
  const GridPrefs({
    this.scaleIndex = -1, // -1 = use the screen's default
    this.live = false,
    this.intervalSec = 15,
  });

  final int scaleIndex;
  // `north` is still written by older builds; the radar has no orientation
  // any more, so it is ignored rather than migrated.
  final bool live;
  final int intervalSec;

  Map<String, Object?> toJson() => <String, Object?>{
        'scale': scaleIndex,
        'live': live,
        'iv': intervalSec,
      };

  static GridPrefs fromJson(Map<String, dynamic> j) => GridPrefs(
        scaleIndex: (j['scale'] as num?)?.toInt() ?? -1,
        live: j['live'] as bool? ?? false,
        intervalSec: (j['iv'] as num?)?.toInt() ?? 15,
      );
}

abstract final class GridPrefsStore {
  static const String _kKey = 'mm.gridPrefs.v1';

  static Future<GridPrefs?> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(_kKey);
    if (raw == null) return null;
    try {
      return GridPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(GridPrefs prefs) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setString(p, _kKey, jsonEncode(prefs.toJson()));
  }
}
