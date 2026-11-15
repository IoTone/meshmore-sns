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
    required this.corners,
  });

  /// Lattice coordinates. Column steps east, row steps south.
  final int col;
  final int row;

  final LatLng centre;

  /// Node keys inside this hexagon, in the order they were given.
  final List<String> points;

  /// The six corners, drawn with the same longitude scale the lattice laid the
  /// cells out with.
  ///
  /// [hexCorners] recomputes metres-per-degree-longitude at the *cell's own*
  /// latitude. A cell away from the box centre then measures a different width
  /// from the pitch that placed it, so at a world view columns separate by up to
  /// forty percent (cos 50 / cos 40 is 0.84, cos 60 / cos 30 is 0.58). The error
  /// is under 0.02 % at street zoom, which is why it survived this long. The
  /// lattice had one scale, so it must draw with one scale.
  final List<LatLng> corners;

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
  // The lattice is anchored to the ground, not to the camera.
  //
  // It used to start at the box's own north-west corner, so every pan moved the
  // origin, every cell moved with it, and the hexagons therefore held their
  // screen position while the ground slid underneath — a field pinned to the
  // glass. Snapping the origin to a whole number of cells in a global metre
  // frame makes the lattice a property of the ground: pan by less than one cell
  // and the hexagons stay put.
  final double anchorX =
      ((box.west * metresPerLon) / width).floorToDouble() * width;
  final double anchorY =
      (((90 - box.north) * kMetresPerDegLatHex) / pitchY).floorToDouble() *
          pitchY;
  final double originLat = 90 - anchorY / kMetresPerDegLatHex;
  final double originLon = anchorX / metresPerLon;

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
  // A field is read as a whole, so it is emitted row by row rather than sorted:
  // sorting by count and then capping gave an arbitrary scatter of hexagons near
  // the top of the screen. Only the occupied-only mode wants "the busiest ones".
  final List<(int, int)> keys = buckets.keys.toList()
    ..sort(includeEmpty
        ? ((a, b) => a.$2 == b.$2 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2))
        : ((a, b) => buckets[b]!.length.compareTo(buckets[a]!.length)));
  return <HexCell>[
    for (final (int, int) k in keys.take(maxCells))
      HexCell(
        col: k.$1,
        row: k.$2,
        centre: toLatLng(k.$1, k.$2),
        points: List<String>.unmodifiable(buckets[k]!),
        corners: _cornersAt(toLatLng(k.$1, k.$2), circumradiusMetres,
            metresPerLon),
      ),
  ];
}

/// The six corners, with an explicit longitude scale.
///
/// The scale is a parameter here because the lattice owns it: a cell must be
/// drawn at the width its own column pitch assumed, not at the width its
/// latitude would give (see [HexCell.corners]).
List<LatLng> _cornersAt(
    LatLng centre, double circumradiusMetres, double metresPerLon) {
  final List<LatLng> out = <LatLng>[];
  for (int i = 0; i < 6; i++) {
    final double a = 60 * i * math.pi / 180;
    final double north = math.cos(a) * circumradiusMetres;
    final double east = math.sin(a) * circumradiusMetres;
    out.add(LatLng(centre.latitude + north / kMetresPerDegLatHex,
        centre.longitude + east / (metresPerLon < 1 ? 1 : metresPerLon)));
  }
  return out;
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

/// The hexagon radius for a zoom: the same size on the glass at every scale.
///
/// The field used to solve for a target cell count over the viewport and then
/// snap the radius to a 1/2/5 ladder. That kept the count bounded and the ground
/// area constant inside a band. What it did not keep constant was the size the
/// reader sees: at every ladder boundary the hexagons jumped by up to two and a
/// half times, so zooming out made the field breathe instead of leaving it
/// alone. A density field is a grid of bins, and a bin that changes size while
/// you zoom is describing a different place each time it does.
///
/// So the radius is [radiusPx] pixels converted to ground metres at this zoom.
/// The cell is the same size on the glass at every scale, the count is the same
/// at every scale by construction, and what changes is how much ground one cell
/// covers — which the map states in its own cell-size chip, so the field never
/// silently changes meaning.
/// The radius a cell is drawn at, in logical pixels.
///
/// Named rather than defaulted at the call site, because the screen needs the
/// same number to know how many cells its viewport holds: a bound on the field
/// that does not agree with the size the cells are drawn at either truncates the
/// field or reserves room for cells that cannot exist.
const double kHexRadiusPx = 18.0;

double hexRadiusForZoom({
  required double metresPerPixel,
  double radiusPx = kHexRadiusPx,
}) {
  if (!metresPerPixel.isFinite || metresPerPixel <= 0 || radiusPx <= 0) {
    return kDefaultHexCircumradiusMetres;
  }
  return radiusPx * metresPerPixel;
}

/// The cell size a pinch actually uses.
///
/// [hexRadiusForZoom] is continuous, so a pinch changes it on every frame, and
/// the field is memoised on it: every frame of a zoom rebuilt the whole lattice
/// and re-anchored it, which is why the hexagons lagged the ground and the
/// newly exposed edges were bare until the next frame's field landed. Rounding
/// the radius to a ladder of half-octaves means a pinch crosses a step at most
/// twice per doubling, and between steps the cells simply scale with the map —
/// they stay on the ground they were drawn on.
///
/// The ladder is √2, the same ratio as half a zoom level, so a step is a
/// visible change in cell size and never a jitter.
double quantiseHexRadius(double metres) {
  if (!metres.isFinite || metres <= 0) return kDefaultHexCircumradiusMetres;
  const double step = 1.4142135623730951; // √2
  final double exponent = math.log(metres) / math.log(step);
  return math.pow(step, exponent.round()).toDouble();
}

/// How far the field is built past the viewport, as a fraction of its size.
///
/// A field built exactly to the visible box has no cells outside it, so the
/// moment a zoom-out or a pan exposes new ground the edge is bare until the
/// next field is built. A third of a screen of margin means the common gesture
/// lands inside cells that already exist.
const double kHexFieldPad = 0.34;

/// The number of cells a viewport of [width] by [height] pixels can hold, at
/// [radiusPx].
///
/// A pointy-top hexagon is `√3·R` wide and pitched `1.5·R` row to row, so this is
/// the lattice's own arithmetic rather than a guess. Two extra columns and rows
/// cover the half-cell offsets at the edges. A field that emits more cells than
/// this is truncated by `hexField`'s `maxCells`, and the cells it drops are the
/// last rows — which on a tablet looked like the bottom of the map had no nodes.
int hexCellsForViewport({
  required double width,
  required double height,
  double radiusPx = kHexRadiusPx,
}) {
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    return 400;
  }
  final double r = radiusPx <= 0 ? kHexRadiusPx : radiusPx;
  final int cols = (width / (math.sqrt(3) * r)).ceil() + 2;
  final int rows = (height / (1.5 * r)).ceil() + 2;
  return cols * rows;
}
