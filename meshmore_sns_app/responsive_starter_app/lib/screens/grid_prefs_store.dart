// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../util/prefs.dart';

/// Persisted last-used preferences for the hyperlocal grid screen, so the
/// chosen view, scale, refresh cadence and legend state survive leaving and
/// re-opening the grid (the screen is recreated on each navigation) and app
/// restarts.
///
/// The view used to be session-only, on the reasoning that every launch should
/// open on the radar. The owner asked for the opposite on 2026-11-14: a reader
/// who works in the mesh tree or the heat map should come back to it. A fresh
/// install still opens on the radar, because that is the default when nothing
/// has been saved.
class GridPrefs {
  const GridPrefs({
    this.scaleIndex = -1, // -1 = use the screen's default
    this.intervalSec = 15,
    this.mode,
    this.legendVisible = false,
  });

  final int scaleIndex;

  /// The view the reader left the grid on, by enum name, or null for a fresh
  /// install (which opens on the radar).
  final String? mode;

  /// Whether the legend was open. It is a reading aid, not a mode, so it is
  /// remembered separately from the view.
  final bool legendVisible;

  /// The play interval, in seconds.
  ///
  /// The play/pause state itself is deliberately not stored: a saved "playing"
  /// would start polling the radio on a screen nobody chose to open. `live`
  /// used to be written here and read by nothing, which is worse than either
  /// choice — a field that looks like state and is not.
  final int intervalSec;

  Map<String, Object?> toJson() => <String, Object?>{
        'scale': scaleIndex,
        'iv': intervalSec,
        if (mode != null) 'mode': mode,
        'legend': legendVisible,
      };

  static GridPrefs fromJson(Map<String, dynamic> j) => GridPrefs(
        scaleIndex: (j['scale'] as num?)?.toInt() ?? -1,
        intervalSec: (j['iv'] as num?)?.toInt() ?? 15,
        mode: j['mode'] as String?,
        legendVisible: j['legend'] as bool? ?? false,
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
