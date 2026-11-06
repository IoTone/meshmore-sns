// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:meshcore/meshcore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/own_location.dart';
import 'tile_math.dart';

/// The map view the user left, so reopening the map puts them back where they
/// were instead of somewhere the app chose.
///
/// This is a preference, not cached data: losing it costs one pan, so it is
/// stored plainly rather than versioned.
class SavedMapView {
  const SavedMapView({
    required this.latitude,
    required this.longitude,
    required this.zoom,
  });

  final double latitude;
  final double longitude;
  final double zoom;

  LatLng get centre => LatLng(latitude, longitude);

  Map<String, Object> toJson() => <String, Object>{
        'lat': latitude,
        'lon': longitude,
        'z': zoom,
      };

  /// A saved view is usable only if every field is a finite number in range:
  /// a corrupt or hand-edited preference must not decide where the camera
  /// goes.
  static SavedMapView? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? lat = raw['lat'];
    final Object? lon = raw['lon'];
    final Object? z = raw['z'];
    if (lat is! num || lon is! num || z is! num) return null;
    final double la = lat.toDouble();
    final double lo = lon.toDouble();
    final double zo = z.toDouble();
    if (!la.isFinite || !lo.isFinite || !zo.isFinite) return null;
    if (la.abs() > 90 || lo.abs() > 180 || zo < 0 || zo > 22) return null;
    return SavedMapView(latitude: la, longitude: lo, zoom: zo);
  }
}

abstract final class MapViewPrefs {
  static const String _kKey = 'mm.mapview.v1';

  static Future<SavedMapView?> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? v = p.getString(_kKey);
    if (v == null || v.isEmpty) return null;
    try {
      return SavedMapView.fromJson(jsonDecode(v));
    } on FormatException {
      return null;
    }
  }

  static Future<void> save(SavedMapView view) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_kKey, jsonEncode(view.toJson()));
  }
}

/// Where the camera starts, and which source decided it.
enum MapCentreSource {
  /// The phone's own position. The closest thing to "centre on me".
  phone,

  /// The radio's reported position: the phone has none but the radio does.
  radio,

  /// The view the user left last time, so the map reopens where they were.
  lastView,

  /// Nothing is known: the widest useful view, stated as such rather than
  /// pretending to be centred on anybody.
  world,
}

/// A resolved starting camera.
class MapCentre {
  const MapCentre({
    required this.centre,
    required this.zoom,
    required this.source,
  });

  final LatLng centre;
  final double zoom;
  final MapCentreSource source;

  /// The zoom a personal view starts at: metro. Close enough to see the
  /// neighbourhood, wide enough that a node a kilometre away is on screen.
  static const double personalZoom = 14.0;

  /// The world view's zoom, used only when no source knows anything.
  static const double worldZoom = 2.0;

  /// The centre of the world view. A shipping convention for "whole world",
  /// not a claim about the user.
  static const LatLng worldCentre = LatLng(20.0, 0.0);

  /// The centring ladder, in order: the phone's position, the radio's own
  /// position, the view the user left, and then the world.
  ///
  /// A downloaded region pack is deliberately NOT a rung. A pack says which
  /// map this device holds, not where the user is, and centring on it would
  /// put a place on screen under the same heading as a real fix. With no
  /// position the honest answer is the world view, which says so.
  static MapCentre resolve({
    OwnLocation? phone,
    SelfInfo? radio,
    SavedMapView? last,
  }) {
    if (phone != null && _usable(phone.latitude, phone.longitude)) {
      return MapCentre(
        centre: LatLng(phone.latitude, phone.longitude),
        zoom: personalZoom,
        source: MapCentreSource.phone,
      );
    }
    if (radio != null && _usable(radio.latitude, radio.longitude)) {
      return MapCentre(
        centre: LatLng(radio.latitude, radio.longitude),
        zoom: personalZoom,
        source: MapCentreSource.radio,
      );
    }
    if (last != null) {
      return MapCentre(
        centre: last.centre,
        zoom: last.zoom,
        source: MapCentreSource.lastView,
      );
    }
    return const MapCentre(
      centre: worldCentre,
      zoom: worldZoom,
      source: MapCentreSource.world,
    );
  }

  /// The widest zoom that still frames [region] on a phone-width viewport.
  ///
  /// 360 degrees of longitude fills a 256 px world tile, so the zoom that fits
  /// a span s in about 360 px is log2(360 / s). Clamped to the range a phone
  /// map is usable in, and floored at the world zoom so a very large region
  /// does not push past it.
  static double zoomToFit(GeoBox region) {
    double span = (region.east - region.west).abs();
    // A region crossing the antimeridian spans almost the whole world; a box
    // that already covers the globe spans all of it.
    if (span >= 360) return worldZoom;
    if (span > 180) span = 360 - span;
    if (!span.isFinite || span <= 0) return personalZoom;
    final double z = math.log(360 / span) / math.ln2;
    return z.clamp(worldZoom, personalZoom);
  }

  /// A radio that has not been asked yet reports (0, 0), which is a real
  /// place in the Gulf of Guinea and not a position anybody is at.
  static bool _usable(double lat, double lon) {
    if (!lat.isFinite || !lon.isFinite) return false;
    if (lat.abs() > 90 || lon.abs() > 180) return false;
    return !(lat.abs() < 1e-9 && lon.abs() < 1e-9);
  }
}
