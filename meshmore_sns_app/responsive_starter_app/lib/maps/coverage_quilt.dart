// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../meshcore/coverage_store.dart';

/// The reception quilt, as map polygons.
///
/// This was the whole of the grid tab's Coverage view: a basemap, peer pins, a
/// reach circle per peer and this layer. The map tab already draws the basemap,
/// the pins and the reach circles, so the view was two tabs doing one job. The
/// layer is the part no other tab had, and it belongs on the map rather than
/// inside a second map of its own.
///
/// A cell is a square of `CoverageStore.cellDeg` degrees and its key is the
/// lat/lon bucket pair, so the polygon is the bucket's own corner. Recency is
/// the only ordering the data has, and it is the one that matters: a cell heard
/// from an hour ago is a different claim from one heard a week ago, and the
/// alpha says which.
///
/// Pure, so the geometry and the ramp are testable without a map.
List<Polygon> coveragePolygons({
  required Map<String, int> cells,
  required int nowUnix,
  required Color color,
}) {
  final List<Polygon> out = <Polygon>[];
  cells.forEach((String key, int unixSec) {
    final ({int latBucket, int lonBucket})? b = CoverageStore.parseKey(key);
    if (b == null) return;
    final double lat = b.latBucket * CoverageStore.cellDeg;
    final double lon = b.lonBucket * CoverageStore.cellDeg;
    final double recency = coverageRecency(nowUnix - unixSec);
    out.add(Polygon(
      points: <LatLng>[
        LatLng(lat, lon),
        LatLng(lat + CoverageStore.cellDeg, lon),
        LatLng(lat + CoverageStore.cellDeg, lon + CoverageStore.cellDeg),
        LatLng(lat, lon + CoverageStore.cellDeg),
      ],
      // Fill carries the reading; the border keeps adjacent cells legible as
      // cells rather than as one smeared region.
      color: color.withValues(alpha: 0.30 + 0.55 * recency),
      borderColor: color.withValues(alpha: 0.50 + 0.40 * recency),
      borderStrokeWidth: 0.8,
    ));
  });
  return out;
}

/// How strongly a cell is drawn, from how long ago it was heard.
///
/// Four steps rather than a continuous fade: the difference between an hour and
/// a day is a fact about the survey, and a continuum would suggest a precision
/// the samples do not have. Under an hour is full strength, a day is three
/// quarters, a week is under half, and anything older is a ghost.
double coverageRecency(int ageSeconds) {
  if (ageSeconds < 3600) return 1.0;
  if (ageSeconds < 86400) return 0.75;
  if (ageSeconds < 604800) return 0.45;
  return 0.2;
}
