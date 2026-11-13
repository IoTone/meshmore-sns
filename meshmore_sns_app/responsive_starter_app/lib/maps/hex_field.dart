// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'density_overlay.dart' show DensityPoint;
import 'tile_math.dart';

/// A field of hexagons over the ground, for the density layer.
///
/// The grid it replaces grouped nodes into squares of a fixed ground size, which
/// is a fine way to *count* and a poor way to look at: four edges read as a
/// spreadsheet, and only the occupied cells were drawn, so the layer was a
/// scatter of boxes whose apparent size changed with the zoom rather than a field
/// you could read across.
///
/// A hexagon lattice fixes both. Every cell has six neighbours, the field is
/// continuous, and — because the cells are geographic and their size is a
/// distance on the ground rather than a pixel count — a cell covers the same area
/// at every zoom. What changes with the zoom is how many of them are on screen.
///
/// Geometry is pointy-top: the width is `√3 · R` and the height `2R` for a
/// circumradius `R`, which is what stops the field looking flattened, and the
/// rows are offset by half a cell so the hexagons interlock.

/// A constant metres per degree of latitude, near enough at any latitude this
/// app is used at: the meridian is very slightly flattened, and a density cell
/// is not a survey.
const double kMetresPerDegLatHex = 111320.0;

/// One hexagon: where it is, which lattice cell it is, and what fell inside it.
class HexCell {
  const HexCell({
    required this.col,
    required this.row,
    required this.centre,
    required this.points,
  });

  /// Lattice coordinates. Column steps east, row steps south.
  final int col;
  final int row;

  final LatLng centre;

  /// Node keys inside this hexagon, in the order they were given.
  final List<String> points;

  int get count => points.length;

  /// Stable identity for a key or a rebuild comparison.
  String get id => '$col:$row';
}

/// The hexagons covering [box], with the nodes in each.
///
/// [circumradiusMetres] is the distance from a hexagon's centre to a corner, so
/// the ground area of one cell is `3·√3/2 · R²` — at the default 250 m that is
/// about 162,000 m², a little over a sixth of a square kilometre, which is why
/// the density chip says "per 0.16 km²" rather than rounding the shape off.
///
/// [margin] grows the covered box by that many cells on every side, so a cell
/// whose centre is just off screen still draws its half that is on screen. Only
/// cells that have something in them are returned: a field drawn over the whole
/// viewport would be a lattice of empty outlines, which says nothing and costs a
/// polygon per cell.
List<HexCell> hexField({
  required Iterable<DensityPoint> points,
  required GeoBox box,
  double circumradiusMetres = kDefaultHexCircumradiusMetres,
  int margin = 1,
  int maxCells = 400,
  bool includeEmpty = false,
}) {
  if (circumradiusMetres <= 0) return const <HexCell>[];
  final double lat0 = (box.south + box.north) / 2;
  final double metresPerLon =
      kMetresPerDegLatHex * math.cos(lat0 * math.pi / 180).abs();
  if (metresPerLon < 1) return const <HexCell>[];

  // Pointy-top lattice: width = √3·R, vertical pitch = 1.5·R, odd columns
  // pushed down by half a pitch (equivalently odd rows pushed east by half a
  // width — the same lattice, and this way the row index is cheap).
  final double width = math.sqrt(3) * circumradiusMetres;
  final double pitchY = 1.5 * circumradiusMetres;
  final double originLat = box.north;
  final double originLon = box.west;

  ({double x, double y}) toMetres(double lat, double lon) => (
        x: (lon - originLon) * metresPerLon,
        y: (originLat - lat) * kMetresPerDegLatHex,
      );

  LatLng toLatLng(int col, int row) {
    final double x = col * width + (row.isOdd ? width / 2 : 0);
    final double y = row * pitchY;
    return LatLng(originLat - y / kMetresPerDegLatHex,
        originLon + x / metresPerLon);
  }

  (int, int) cellOf(double lat, double lon) {
    final ({double x, double y}) m = toMetres(lat, lon);
    // Nearest row first, then the column within that row's offset.
    final int row = (m.y / pitchY).round();
    final double offset = row.isOdd ? width / 2 : 0;
    final int col = ((m.x - offset) / width).round();
    return (col, row);
  }

  final Map<(int, int), List<String>> buckets = <(int, int), List<String>>{};

  // The whole lattice over the box, not only the occupied cells: the owner asked
  // for a *field* — a continuous mesh at a uniform distance that you read across —
  // and a handful of floating hexagons is not that. Empty cells are drawn at the
  // faintest step of the same ramp, so density reads as a shape rather than as a
  // scatter.
  if (includeEmpty) {
    final int cols =
        ((box.east - box.west).abs() * metresPerLon / width).ceil() + 2;
    final int rows = ((box.north - box.south).abs() *
                kMetresPerDegLatHex /
                pitchY)
            .ceil() +
        2;
    for (int row = -1; row <= rows; row++) {
      for (int col = -1; col <= cols; col++) {
        buckets.putIfAbsent((col, row), () => <String>[]);
      }
    }
  }
  for (final DensityPoint p in points) {
    if (p.lat < box.south ||
        p.lat > box.north ||
        p.lon < box.west ||
        p.lon > box.east) {
      continue;
    }
    final (int col, int row) = cellOf(p.lat, p.lon);
    (buckets[(col, row)] ??= <String>[]).add(p.pubKey);
  }
  if (buckets.isEmpty) return const <HexCell>[];
  // Densest first, so a cap keeps the cells that carry the message.
  final List<(int, int)> keys = buckets.keys.toList()
    ..sort((a, b) => buckets[b]!.length.compareTo(buckets[a]!.length));
  return <HexCell>[
    for (final (int, int) k in keys.take(maxCells))
      HexCell(
        col: k.$1,
        row: k.$2,
        centre: toLatLng(k.$1, k.$2),
        points: List<String>.unmodifiable(buckets[k]!),
      ),
  ];
}

/// The six corners of a hexagon centred on [centre], in draw order.
///
/// Pointy-top, so the corners sit at the top and bottom rather than the sides,
/// and the width is `√3·R` — the ratio a flattened field gets wrong.
List<LatLng> hexCorners(LatLng centre, double circumradiusMetres) {
  final double metresPerLon =
      kMetresPerDegLatHex * math.cos(centre.latitude * math.pi / 180).abs();
  final List<LatLng> out = <LatLng>[];
  for (int i = 0; i < 6; i++) {
    // 60·i degrees clockwise *from north*, so the first corner points up and the
    // hexagon stands on a point: the width is √3·R and the height 2R.
    final double a = 60 * i * math.pi / 180;
    final double north = math.cos(a) * circumradiusMetres;
    final double east = math.sin(a) * circumradiusMetres;
    out.add(LatLng(centre.latitude + north / kMetresPerDegLatHex,
        centre.longitude + east / (metresPerLon < 1 ? 1 : metresPerLon)));
  }
  return out;
}

/// How opaque a cell is drawn, from how many nodes it holds.
///
/// A field of uniform hexagons would be a decoration; the reason to draw it is
/// the count, so an empty-ish cell is a faint outline and a busy one is a filled
/// patch. The curve is a square root because the interesting range is the bottom
/// of it: four nodes in a cell is already "busier than most", and a linear ramp
/// would keep it almost invisible until twelve.
double hexAlpha(int count, {int reference = 6}) {
  if (count <= 0) return 0.04;
  final double t = (count / (reference <= 0 ? 6 : reference)).clamp(0.0, 1.0);
  return 0.16 + 0.42 * math.sqrt(t);
}

/// The hexagon size the density layer uses by default, in metres.
///
/// 250 m across to a corner is about 0.16 km² a cell: a small neighbourhood
/// block, which is the scale at which "how many nodes here" means anything on a
/// phone screen at street zoom.
const double kDefaultHexCircumradiusMetres = 250.0;

/// Whether [point] falls inside the hexagon centred on [centre].
///
/// A flat ray-cross test over the six corners rather than a switch to axial
/// coordinates: the corners are already computed for the drawing, so the test
/// cannot disagree with the shape the reader sees.
bool hexContains(LatLng centre, double circumradiusMetres, LatLng point) {
  final List<LatLng> c = hexCorners(centre, circumradiusMetres);
  bool inside = false;
  for (int i = 0, j = c.length - 1; i < c.length; j = i++) {
    final double xi = c[i].longitude, yi = c[i].latitude;
    final double xj = c[j].longitude, yj = c[j].latitude;
    final bool cross = ((yi > point.latitude) != (yj > point.latitude)) &&
        (point.longitude <
            (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
    if (cross) inside = !inside;
  }
  return inside;
}

/// The hexagon radius for a zoom, in bands.
///
/// Stepwise rather than continuous because a cell that changes size with every
/// pinch is not a field: within a band the ground area is constant, and the band
/// changes only when the cells would otherwise be unreadable. The aim is a
/// hexagon about 34 logical pixels across, which is enough to hold a count.
double hexRadiusForZoom(double pixelsPerMetre) {
  const List<double> radii = <double>[50, 100, 250, 500, 1000, 2500, 5000];
  for (final double r in radii) {
    // Width is sqrt(3)·R, so this is the on-screen width of the cell.
    if (math.sqrt(3) * r * pixelsPerMetre <= 52) return r;
  }
  return radii.last;
}
