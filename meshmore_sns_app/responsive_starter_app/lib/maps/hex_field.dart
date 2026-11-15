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

/// The sphere the map's own projection uses.
///
/// The lattice is laid out in the projection's metres, not in ground metres.
/// Ground metres need a scale per place — metres per degree of longitude is a
/// cosine of the latitude — and taking that cosine at the centre of the box made
/// the cell size a property of the *camera*: nudge the box by a ten-thousandth
/// of a degree, as a window resize or returning from the app switcher does, and
/// every hexagon moved by a fraction of a cell. The projection's metres are the
/// same at every latitude, so the lattice is the same field over the same ground
/// for every box that covers it, and a cell is a regular hexagon on screen at
/// every zoom and every latitude.
const double kMercatorRadiusMetres = 6378137.0;

/// Web Mercator, the projection the tiles and the screen share.
double mercatorX(double lon) => lon * math.pi / 180 * kMercatorRadiusMetres;

double mercatorY(double lat) {
  final double c = lat.clamp(-85.05112878, 85.05112878);
  return math.log(math.tan(math.pi / 4 + c * math.pi / 360)) *
      kMercatorRadiusMetres;
}

double mercatorLon(double x) => x / kMercatorRadiusMetres * 180 / math.pi;

double mercatorLat(double y) =>
    (2 * math.atan(math.exp(y / kMercatorRadiusMetres)) - math.pi / 2) *
    180 /
    math.pi;

/// How many ground metres one projection metre is worth at [lat].
///
/// The projection stretches as the secant of the latitude, so a cell that is `R`
/// projection metres across covers `R·cos(lat)` metres of ground. A cell is a
/// size on the glass; this is what that size means under it.
double groundPerProjectionMetre(double lat) =>
    math.cos(lat * math.pi / 180).abs().clamp(0.0, 1.0);

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
  // glass. Snapping the origin to a whole number of cells in the projection's
  // own metres makes the lattice a property of the ground: pan by less than one
  // cell and the hexagons stay put.
  final double originX = (mercatorX(box.west) / width).floorToDouble() * width;
  final double originY =
      (mercatorY(box.north) / pitchY).floorToDouble() * pitchY;

  ({double x, double y}) toMetres(double lat, double lon) => (
        x: mercatorX(lon) - originX,
        // The row index counts south, so the projection's northward metres are
        // negated once here rather than at every use.
        y: originY - mercatorY(lat),
      );

  (int, int) cellOf(double lat, double lon) {
    final ({double x, double y}) m = toMetres(lat, lon);
    // The cell whose **centre** is nearest, not "round the row, then round the
    // column". Those are not the same lattice assignment: a row is 0.75·H from
    // its neighbours, so a point near the top of one hexagon is nearest to a
    // centre in the row above and half a column across. Rounding each axis
    // independently put real nodes in cells they were not drawn inside — the
    // owner's "do repeaters fall between the hexagons?" — so nine candidates
    // (three rows by three columns) are compared and the nearest wins. Nine
    // distance comparisons per node is nothing next to the work of drawing the
    // field, and it makes the assignment and the shapes agree by construction.
    final int rowNear = (m.y / pitchY).round();
    int bestCol = 0;
    int bestRow = 0;
    double bestDist = double.infinity;
    for (int row = rowNear - 1; row <= rowNear + 1; row++) {
      final double offset = row.isOdd ? width / 2 : 0;
      final int colNear = ((m.x - offset) / width).round();
      for (int col = colNear - 1; col <= colNear + 1; col++) {
        final double dx = m.x - (col * width + offset);
        final double dy = m.y - row * pitchY;
        final double d = dx * dx + dy * dy;
        if (d < bestDist) {
          bestDist = d;
          bestCol = col;
          bestRow = row;
        }
      }
    }
    return (bestCol, bestRow);
  }

  final Map<(int, int), List<String>> buckets = <(int, int), List<String>>{};

  // The whole lattice over the box, not only the occupied cells: the owner asked
  // for a *field* — a continuous mesh at a uniform distance that you read across —
  // and a handful of floating hexagons is not that. Empty cells are drawn at the
  // faintest step of the same ramp, so density reads as a shape rather than as a
  // scatter.
  int latticeRows = 0;
  int latticeCols = 0;
  if (includeEmpty) {
    final int cols =
        ((mercatorX(box.east) - mercatorX(box.west)).abs() / width).ceil() + 2;
    final int rows =
        ((mercatorY(box.north) - mercatorY(box.south)).abs() / pitchY)
                .ceil() +
            2;
    latticeRows = rows;
    latticeCols = cols;
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
  //
  // The row-major order used to be produced by sorting every key with a
  // comparator closure — an O(n log n) sort of ~1,600 keys per rebuild, for an
  // order the lattice already has. Walking the rows instead costs nothing.
  final List<HexCell> out = <HexCell>[];
  if (includeEmpty) {
    for (int row = -1; row <= latticeRows; row++) {
      for (int col = -1; col <= latticeCols; col++) {
        final List<String>? held = buckets[(col, row)];
        if (held == null) continue;
        if (out.length >= maxCells) return out;
        out.add(_cellAt(col, row, held, circumradiusMetres, originX, originY,
            width, pitchY));
      }
    }
    return out;
  }
  final List<(int, int)> keys = buckets.keys.toList()
    ..sort((a, b) => buckets[b]!.length.compareTo(buckets[a]!.length));
  for (final (int, int) k in keys) {
    if (out.length >= maxCells) break;
    out.add(_cellAt(k.$1, k.$2, buckets[k]!, circumradiusMetres, originX,
        originY, width, pitchY));
  }
  return out;
}

/// One cell, from one projection point.
///
/// The centre and the six corners all derive from the same `(x, y)` in the
/// projection's metres. The angles are symmetric, so six corners hold only four
/// distinct latitudes and three distinct longitudes: asking `mercatorLat` for
/// each of the six separately was twelve transcendental calls per cell, i.e.
/// ~19,000 for one screen of field, which is why the lattice arrived a beat after
/// the map had drawn.
HexCell _cellAt(int col, int row, List<String> points, double radius,
    double originX, double originY, double width, double pitchY) {
  final double x = col * width + (row.isOdd ? width / 2 : 0);
  final double px = originX + x;
  final double py = originY - row * pitchY;
  // 0.866025… is sin 60: the east offset of a corner of a pointy-top hexagon.
  const double east = 0.8660254037844386;
  final double latNorth = mercatorLat(py + radius);
  final double latHalfNorth = mercatorLat(py + radius * 0.5);
  final double latHalfSouth = mercatorLat(py - radius * 0.5);
  final double latSouth = mercatorLat(py - radius);
  final double lonCentre = mercatorLon(px);
  final double lonEast = mercatorLon(px + radius * east);
  final double lonWest = mercatorLon(px - radius * east);
  return HexCell(
    col: col,
    row: row,
    centre: LatLng(mercatorLat(py), lonCentre),
    points: List<String>.unmodifiable(points),
    corners: <LatLng>[
      LatLng(latNorth, lonCentre),
      LatLng(latHalfNorth, lonEast),
      LatLng(latHalfSouth, lonEast),
      LatLng(latSouth, lonCentre),
      LatLng(latHalfSouth, lonWest),
      LatLng(latHalfNorth, lonWest),
    ],
  );
}

/// The six corners of a cell centred at the projection point `(x, y)`.
///
/// Built in the projection's own metres, which is what makes a cell a regular
/// hexagon on screen: the projection is conformal, so a regular shape in its
/// metres is a regular shape in its pixels.
List<LatLng> _cornersAt(double x, double y, double circumradiusMetres) {
  final List<LatLng> out = <LatLng>[];
  for (int i = 0; i < 6; i++) {
    final double a = 60 * i * math.pi / 180;
    final double north = math.cos(a) * circumradiusMetres;
    final double east = math.sin(a) * circumradiusMetres;
    out.add(LatLng(mercatorLat(y + north), mercatorLon(x + east)));
  }
  return out;
}

/// The six corners of a hexagon centred on [centre], in draw order.
///
/// Pointy-top, so the corners sit at the top and bottom rather than the sides,
/// and the width is `√3·R` — the ratio a flattened field gets wrong.
List<LatLng> hexCorners(LatLng centre, double circumradiusMetres) =>
    // 60·i degrees clockwise *from north*, so the first corner points up and the
    // hexagon stands on a point: the width is √3·R and the height 2R.
    _cornersAt(mercatorX(centre.longitude), mercatorY(centre.latitude),
        circumradiusMetres);

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
/// The projection's metres per pixel at [zoom].
///
/// This is what a cell size must be derived from once the lattice lives in the
/// projection's frame: ground metres per pixel carry the latitude, and a cell
/// size that carries the latitude is the defect this replaced.
double hexMetresPerPixel(double zoom) {
  if (!zoom.isFinite) return 156543.03392;
  return 156543.03392 / math.pow(2, zoom).toDouble();
}

/// The cell radius for [zoom], quantised as a pinch needs.
double hexRadiusForZoomLevel(double zoom, {double radiusPx = kHexRadiusPx}) {
  if (radiusPx <= 0) return quantiseHexRadius(kDefaultHexCircumradiusMetres);
  return quantiseHexRadius(radiusPx * hexMetresPerPixel(zoom));
}

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
