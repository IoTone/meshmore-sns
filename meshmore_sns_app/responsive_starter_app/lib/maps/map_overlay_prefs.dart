// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../util/prefs.dart';

/// What the map is asked to draw on top of its basemap.
///
/// The basemap was remembered, the camera was remembered, and each event
/// layer's switch was remembered with the layer — but everything the map's own
/// overlays sheet owned was session-only. The hexagon field is the clearest
/// case: a reader who turned it on to read the mesh's density found it off
/// again on the next launch, and turned it on again, and the app never said
/// why. A display choice is a preference, and a preference that does not
/// survive the process is a bug that looks like forgetfulness.
///
/// This is deliberately one small record rather than a preference per toggle.
/// A flag added here becomes a stored flag for free, and the decoder ignores
/// keys it does not know, so a build that adds one does not have to migrate
/// what an older build wrote.
class MapOverlayPrefs {
  const MapOverlayPrefs({
    this.density = false,
  });

  /// The hexagon field: node density per cell, drawn as a continuous lattice.
  ///
  /// Off by default. It is a *reading about the mesh* rather than a record of
  /// it, so it is something a reader asks for; once they have asked, the answer
  /// stays given.
  final bool density;

  /// The defaults, which are also what an unreadable or absent record means.
  static const MapOverlayPrefs defaults = MapOverlayPrefs();

  MapOverlayPrefs copyWith({bool? density}) =>
      MapOverlayPrefs(density: density ?? this.density);

  Map<String, Object?> toJson() => <String, Object?>{
        'density': density,
      };

  /// Reads what it can and defaults the rest.
  ///
  /// No exception escapes: a record written by a build with a different shape
  /// is a record whose unknown fields are dropped, which is the whole reason
  /// the format is a map rather than a packed value.
  static MapOverlayPrefs fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    return MapOverlayPrefs(
      density: raw['density'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MapOverlayPrefs && other.density == density;

  @override
  int get hashCode => density.hashCode;

  @override
  String toString() => 'MapOverlayPrefs(density: $density)';
}

abstract final class MapOverlayPrefsStore {
  static const String _kKey = 'mm.mapOverlays.v1';

  static Future<MapOverlayPrefs> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(_kKey);
    if (raw == null || raw.isEmpty) return MapOverlayPrefs.defaults;
    try {
      return MapOverlayPrefs.fromJson(jsonDecode(raw));
    } on FormatException {
      return MapOverlayPrefs.defaults;
    }
  }

  static Future<void> save(MapOverlayPrefs prefs) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setString(p, _kKey, jsonEncode(prefs.toJson()));
  }

  /// Forget the record, so the next launch is back to defaults. Used by tests
  /// and by anything that resets the map's display.
  static Future<void> clear() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
  }
}
