// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../geofence/geofence_store.dart';
import '../util/geo.dart';

/// The camera that shows every fence at once.
///
/// A list of fences is a list of places, and a list does not answer "where are
/// they". This is the arithmetic that turns the list into one camera: the
/// centre of what they cover, and the zoom at which all of it fits.
///
/// It is a function rather than a few lines inside the screen because the two
/// numbers are easy to get wrong in ways that look plausible — a zoom that fits
/// the *centres* clips the outermost fence by its own radius, and averaging
/// latitudes west-heavy biases the centre west. Both are tested.
///
/// One fence alone is a special case with no useful mean: it centres on that
/// fence at the closest zoom that shows its whole circle, because "show all"
/// on a single fence must still show the fence.
///
/// Returns null when there is nothing to show, so the caller can leave the
/// camera alone rather than jumping to an arbitrary place.
({LatLng centre, double zoom})? fitGeofences(
  List<StoredGeofence> fences, {
  required double viewportPx,
  double paddingFraction = 0.15,
  double minZoom = 2,
  double maxZoom = 17,
}) {
  if (fences.isEmpty) return null;
  if (!viewportPx.isFinite || viewportPx <= 0) return null;

  // The centre of the bounding box, not the mean: a mesh of fences from the
  // same afternoon would be pulled toward wherever most of them are, and the
  // camera is supposed to contain the *extent* of what the reader drew.
  double south = 90;
  double north = -90;
  double west = 180;
  double east = -180;
  for (final StoredGeofence f in fences) {
    final double dLat = _degreesFor(f.radiusMeters);
    final double cos = math.cos(f.latitude * math.pi / 180).abs();
    final double dLon = _degreesFor(f.radiusMeters) / (cos < 0.01 ? 0.01 : cos);
    south = math.min(south, f.latitude - dLat);
    north = math.max(north, f.latitude + dLat);
    west = math.min(west, f.longitude - dLon);
    east = math.max(east, f.longitude + dLon);
  }
  final LatLng centre =
      LatLng((south + north) / 2, (west + east) / 2);

  // The span in metres, as the larger of the two axes. The shorter axis rides
  // along: a viewport is not square, and fitting the larger one is what keeps
  // everything inside.
  final double spanMeters = math.max(
    haversineMeters(south, centre.longitude, north, centre.longitude),
    haversineMeters(centre.latitude, west, centre.latitude, east),
  );
  if (!spanMeters.isFinite || spanMeters <= 0) {
    // Every fence is a point; there is no extent to fit, so show the pick of
    // them at a street zoom.
    return (centre: centre, zoom: maxZoom);
  }

  final double usable = viewportPx * (1 - paddingFraction * 2);
  if (usable <= 0) return (centre: centre, zoom: minZoom);

  // Web-Mercator ground resolution: 156543.03392 m per pixel at zoom 0 at the
  // equator, halving with every zoom. Solving for the zoom that maps
  // `spanMeters` onto `usable` pixels is the whole of the calculation.
  final double cos = math
      .cos(centre.latitude * math.pi / 180)
      .abs()
      .clamp(0.01, 1.0);
  final double zoom =
      math.log(156543.03392 * cos * usable / spanMeters) / math.ln2;
  return (centre: centre, zoom: zoom.clamp(minZoom, maxZoom));
}

/// Metres per degree of latitude, the same constant the app's other geometry
/// uses, expressed as the inverse because a radius is a distance.
double _degreesFor(double meters) => meters / 111320.0;
