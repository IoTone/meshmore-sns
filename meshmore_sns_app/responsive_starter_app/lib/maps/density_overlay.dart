// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../util/mm_format.dart';

/// Node density per equal area, as map polygons.
///
/// This is the property the deleted equal-area grid held and nothing else did:
/// cells of the same ground area, so a count per cell compares like with like.
/// The radar is radial with a saturating clamp and the pins are points, so
/// neither can say "eleven nodes in this square kilometre".
///
/// The grid is kilometre squares aligned to the operator's own fix, with the
/// longitude span corrected by `cos(latitude)` at the anchor. Over the extent a
/// mesh spans (tens of kilometres) the cosine changes by less than half a
/// percent, so every cell covers the same ground area to within that. A global
/// grid would need an equal-area projection to do better, and it would then look
/// wrong on the Mercator basemap it is drawn on.
///
/// Pure, so the geometry and the ramp are testable without a map.

/// One cell of the density grid.
///
/// [pubKeys] are the nodes whose positions fall inside it, so a tap can name
/// them rather than only count them.
class DensityCell {
  const DensityCell({
    required this.ix,
    required this.iy,
    required this.pubKeys,
    required this.bounds,
  });

  /// Cell index east of the anchor grid, and north of it.
  final int ix;
  final int iy;

  final List<String> pubKeys;

  /// The square, drawn in this order: south-west, south-east, north-east,
  /// north-west.
  final List<LatLng> bounds;

  int get count => pubKeys.length;

  LatLng get centre => LatLng(
        (bounds[0].latitude + bounds[2].latitude) / 2,
        (bounds[0].longitude + bounds[2].longitude) / 2,
      );

  /// Stable identity for a widget key or a rebuild comparison.
  String get id => '$ix:$iy';

  /// The same cell drawn as a pointy-top hexagon, inscribed in the square.
  ///
  /// A hexagon says "this is a cell of a survey, not a pixel of a picture", and
  /// six edges read as a lattice where four read as a spreadsheet. The hexagon
  /// is *inscribed* in the cell's own box rather than replacing the lattice:
  /// the addresses, the areas and the tap rule are all still the square's, so
  /// nothing about what a cell means changes — only how it is drawn. Neighbours
  /// therefore leave a small gap, which is honest: these cells are not a
  /// tessellation of the ground, they are samples of it.
  List<LatLng> get hexagon {
    final double latC = centre.latitude;
    final double lonC = centre.longitude;
    final double halfLat = (bounds[2].latitude - bounds[0].latitude) / 2;
    final double halfLon = (bounds[1].longitude - bounds[0].longitude) / 2;
    // Pointy-top: vertices at the top and bottom, flat sides east and west.
    return <LatLng>[
      LatLng(latC + halfLat, lonC),
      LatLng(latC + halfLat / 2, lonC + halfLon),
      LatLng(latC - halfLat / 2, lonC + halfLon),
      LatLng(latC - halfLat, lonC),
      LatLng(latC - halfLat / 2, lonC - halfLon),
      LatLng(latC + halfLat / 2, lonC - halfLon),
    ];
  }
}

/// The smallest a square may be drawn, in logical pixels, before its count is
/// dropped.
///
/// A count needs about this much room to be readable, and past that a map is
/// better off as a tint than as a page of clipped numbers. The rule is the
/// square's own size rather than how many squares there are: a metro view has
/// three hundred squares and none of them can hold a digit, while a street view
/// has four and every one of them can.
const double kDensityLabelMinPx = 28.0;

/// Whether a square this many logical pixels across can hold its count.
bool densityLabelsFit(double cellPx) => cellPx >= kDensityLabelMinPx;

/// The sizes a cell may take, in metres. A ladder rather than a computed
/// number, so the label always reads as a round distance and two views can be
/// compared without arithmetic.
const List<double> kDensityCellLadder = <double>[
  50, 100, 250, 500, 1000, 2000, 5000, 10000, 25000, 50000, 100000,
];

/// The cell size to use at a zoom, so cells stay readable at every scale.
///
/// A fixed 250 m is right at one zoom and useless at the others: at metro zoom
/// it is a three-pixel smudge, and at street zoom a single square fills the
/// screen. The ladder picks the smallest size whose square is at least
/// [targetPx] on screen, so the read stays comparable at any zoom and the count
/// stays readable without the rule that followed the number of squares.
///
/// The scale is passed in rather than recomputed: `StreetMapView.metersPerPixel`
/// already owns the Web-Mercator relation, and a second copy of it would drift.
double densityCellMetresFor({
  required double metresPerPixel,
  double targetPx = 48.0,
}) {
  if (metresPerPixel <= 0) return kDensityCellLadder.last;
  for (final double metres in kDensityCellLadder) {
    if (metres / metresPerPixel >= targetPx) return metres;
  }
  return kDensityCellLadder.last;
}

/// The cell size written the way a person reads it: "250 m", "1 km", "25 km".
String densityCellLabel(double metres, {FormatPrefs? prefs}) {
  // A reader in miles reads the cell's width in feet or miles too: the chip and
  // the hexagons it labels must not disagree about the unit.
  if (prefs != null) return MmFormat.step(metres, prefs: prefs);
  if (metres >= 1000) {
    final double km = metres / 1000;
    return km == km.roundToDouble()
        ? '${km.round()} km'
        : '${km.toStringAsFixed(1)} km';
  }
  return '${metres.round()} m';
}

/// A node's position and the key that names it.
typedef DensityPoint = ({double lat, double lon, String pubKey});

/// Metres per degree of latitude, at the accuracy a mesh grid needs.
const double kMetresPerDegLat = 111320.0;

/// The default cell: 250 m squares, which is roughly a city block and small
/// enough that a street-level mesh separates into more than one cell.
///
/// The grid is anchored to the operator's fix, which is where the `cos(latitude)`
/// correction is evaluated. Moving further than a cell re-anchors it, so the
/// squares step rather than crawl; the areas stay equal because the anchor's
/// latitude is the one used for the longitude span.
const double kDensityCellMetres = 250.0;

/// Groups [points] into equal-area cells of [cellMetres] squares.
///
/// The grid is anchored to [anchor] so it stays put while the operator moves and
/// pans: cells are a property of the ground, not of the viewport. Only cells
/// with at least one node are returned, so an empty mesh draws nothing rather
/// than a lattice over the whole map.
List<DensityCell> densityCells({
  required Iterable<DensityPoint> points,
  required LatLng anchor,
  double cellMetres = kDensityCellMetres,
}) {
  if (cellMetres <= 0) {
    throw ArgumentError.value(cellMetres, 'cellMetres', 'must be positive');
  }
  final double metresPerDegLon =
      kMetresPerDegLat * math.cos(anchor.latitude * math.pi / 180).abs();
  if (metresPerDegLon < 1) {
    // Within a few hundred metres of a pole a longitude degree spans nothing,
    // so a lat/lon grid cannot hold an area at all. Better to draw nothing than
    // a sliver.
    return <DensityCell>[];
  }
  final double latSpan = cellMetres / kMetresPerDegLat;
  final double lonSpan = cellMetres / metresPerDegLon;

  final Map<String, List<String>> byCell = <String, List<String>>{};
  final Map<String, (int, int)> index = <String, (int, int)>{};
  for (final DensityPoint p in points) {
    final int ix =
        ((p.lon - anchor.longitude) * metresPerDegLon / cellMetres).floor();
    final int iy = ((p.lat - anchor.latitude) * kMetresPerDegLat / cellMetres)
        .floor();
    final String id = '$ix:$iy';
    index[id] = (ix, iy);
    (byCell[id] ??= <String>[]).add(p.pubKey);
  }

  final List<DensityCell> out = <DensityCell>[];
  byCell.forEach((String id, List<String> keys) {
    final (int ix, int iy) = index[id]!;
    final double south = anchor.latitude + iy * latSpan;
    final double west = anchor.longitude + ix * lonSpan;
    out.add(DensityCell(
      ix: ix,
      iy: iy,
      pubKeys: keys,
      bounds: <LatLng>[
        LatLng(south, west),
        LatLng(south, west + lonSpan),
        LatLng(south + latSpan, west + lonSpan),
        LatLng(south + latSpan, west),
      ],
    ));
  });
  // Deterministic order so a rebuild does not reshuffle the layer.
  out.sort((DensityCell a, DensityCell b) =>
      a.iy != b.iy ? a.iy.compareTo(b.iy) : a.ix.compareTo(b.ix));
  return out;
}

/// Whether [point] falls inside [cell].
///
/// The map's own tap handler uses this rather than a polygon hit test, because
/// a cell's centre is where its nodes are: a hit test would open the node sheet
/// for the pin standing in the middle of the square and never the square.
bool cellContains(DensityCell cell, LatLng point) {
  final LatLng sw = cell.bounds[0];
  final LatLng ne = cell.bounds[2];
  return point.latitude >= sw.latitude &&
      point.latitude <= ne.latitude &&
      point.longitude >= sw.longitude &&
      point.longitude <= ne.longitude;
}

/// How strongly a cell is filled, from its count against the busiest cell.
///
/// The square root, not the count: with a linear ramp a cell of one node among
/// forty is invisible, which hides most of a mesh. With the root, one node is a
/// third of full strength and the gradient still reads as more-is-darker.
double densityAlpha(int count, int maxCount) {
  if (count <= 0 || maxCount <= 0) return 0;
  final double t = math.sqrt(count / maxCount).clamp(0.0, 1.0);
  // A faint fill, because the pins on this map are themselves pale squares and
  // a strong fill made a cell look like a node. The border carries the grid and
  // the fill carries the count.
  return 0.16 + 0.30 * t;
}

/// The density cells as map polygons, coloured by count.
///
/// Typed to [DensityCell] so a tap on a square hands back the cell itself
/// through the layer's hit notifier, rather than a polygon whose index the
/// caller has to line up with a parallel list.
List<Polygon<DensityCell>> densityPolygons({
  required Iterable<DensityCell> cells,
  required Color color,
}) {
  final List<DensityCell> list = cells.toList();
  int maxCount = 0;
  for (final DensityCell c in list) {
    if (c.count > maxCount) maxCount = c.count;
  }
  return <Polygon<DensityCell>>[
    for (final DensityCell c in list)
      Polygon<DensityCell>(
        points: c.hexagon,
        hitValue: c,
        color: color.withValues(alpha: densityAlpha(c.count, maxCount)),
        borderColor: color.withValues(alpha: 0.80),
        borderStrokeWidth: 1.2,
      ),
  ];
}
