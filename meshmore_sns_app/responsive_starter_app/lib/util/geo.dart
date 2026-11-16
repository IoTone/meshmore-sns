// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'mm_format.dart';

/// Great-circle distance (haversine) in **metres** between two
/// WGS-84 points. Inputs are degrees.
double haversineMeters(
    double lat1, double lon1, double lat2, double lon2) {
  const double r = 6371000.0; // Earth radius, m
  final double dLat = _toRad(lat2 - lat1);
  final double dLon = _toRad(lon2 - lon1);
  final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  // `1 - a` can go a hair negative for near-antipodal points, and the square
  // root of that is NaN, which then reaches every geometry path.
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(math.max(0.0, 1 - a)));
}

double _toRad(double d) => d * (math.pi / 180.0);

/// Bearing in radians (0 = north, clockwise) from (lat1,lon1) to
/// (lat2,lon2). Pairs with [haversineMeters] for the grid's polar
/// projection.
double bearingRadians(
    double lat1, double lon1, double lat2, double lon2) {
  final double phi1 = _toRad(lat1);
  final double phi2 = _toRad(lat2);
  final double dLon = _toRad(lon2 - lon1);
  final double y = math.sin(dLon) * math.cos(phi2);
  final double x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
  return math.atan2(y, x);
}

/// Pretty-print a metre distance for chat / nodes lists. Sub-km is
/// rounded to the nearest 10 m; ≥ 1 km uses one decimal of km.
/// Returns `null` for null input so callers can chain `?.`.
String? formatDistance(double? meters, {FormatPrefs? prefs}) {
  if (meters == null) return null;
  if (meters.isNaN || meters.isInfinite) return null;
  // One formatter for the whole app: the reader's units, or the metric default
  // when there is no store above the caller.
  // One formatter for the whole app, with or without a store above the caller.
  // The fallback used to re-implement the metric branch, so a dashboard with no
  // `FormatPrefs` was on a copy of the rule.
  return '≈ ${MmFormat.distance(meters, prefs: prefs)}';
}
