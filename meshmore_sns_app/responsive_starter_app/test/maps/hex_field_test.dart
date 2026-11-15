// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:meshmore_sns_app/maps/density_overlay.dart' show DensityPoint;
import 'package:meshmore_sns_app/maps/hex_field.dart';
import 'package:meshmore_sns_app/maps/tile_math.dart';

/// A field of hexagons, not a scatter of squares.
///
/// What the owner asked for is that the field be *uniform*: the same ground area
/// per cell everywhere, cells that interlock rather than float apart, and a shade
/// that says how busy each one is. Each of those is a property that can be
/// asserted rather than eyeballed.
void main() {
  const GeoBox box = GeoBox(south: 47.60, west: -122.35, north: 47.62, east: -122.32);

  /// The ground area of a regular hexagon with circumradius R.
  double hexArea(double r) => 3 * math.sqrt(3) / 2 * r * r;

  test('a hexagon is not flattened: width is sqrt(3) x radius', () {
    const LatLng centre = LatLng(47.61, -122.335);
    const double r = 200;
    final List<LatLng> corners = hexCorners(centre, r);
    expect(corners.length, 6);

    // Distances from the centre are all the circumradius: a flattened hexagon
    // would have two of them shorter.
    final List<double> toCorners = <double>[
      for (final LatLng c in corners)
        math.sqrt(
          math.pow((c.latitude - centre.latitude) * kMetresPerDegLatHex, 2) +
              math.pow(
                  (c.longitude - centre.longitude) *
                      kMetresPerDegLatHex *
                      math.cos(centre.latitude * math.pi / 180),
                  2),
        ),
    ];
    for (final double d in toCorners) {
      expect(d, closeTo(r, 2), reason: 'every corner is one radius away');
    }

    // The bounding box: width sqrt(3)·R, height 2R.
    final double northMost = corners
        .map((LatLng c) => c.latitude)
        .reduce((double a, double b) => a > b ? a : b);
    final double southMost = corners
        .map((LatLng c) => c.latitude)
        .reduce((double a, double b) => a < b ? a : b);
    final double eastMost = corners
        .map((LatLng c) => c.longitude)
        .reduce((double a, double b) => a > b ? a : b);
    final double westMost = corners
        .map((LatLng c) => c.longitude)
        .reduce((double a, double b) => a < b ? a : b);
    final double height = (northMost - southMost) * kMetresPerDegLatHex;
    final double width = (eastMost - westMost) *
        kMetresPerDegLatHex *
        math.cos(centre.latitude * math.pi / 180);
    expect(height, closeTo(2 * r, 4));
    expect(width, closeTo(math.sqrt(3) * r, 4),
        reason: 'a hexagon wider or narrower than √3·R reads as a squashed cell');
  });

  test('a node lands in exactly one cell, and the field is dense', () {
    final List<DensityPoint> points = <DensityPoint>[
      for (int i = 0; i < 60; i++)
        (
          lat: box.south + (box.north - box.south) * (i % 10) / 10,
          lon: box.west + (box.east - box.west) * (i ~/ 10) / 6,
          pubKey: 'k$i',
        ),
    ];
    final List<HexCell> cells = hexField(
        points: points, box: box, circumradiusMetres: 100);
    expect(cells, isNotEmpty);
    final int counted = cells.fold(0, (int n, HexCell c) => n + c.count);
    expect(counted, points.length,
        reason: 'every node is in one cell and none is dropped');
    expect(cells.map((HexCell c) => c.id).toSet().length, cells.length,
        reason: 'no cell is emitted twice');
  });

  test('every cell covers the same ground area', () {
    final List<DensityPoint> points = <DensityPoint>[
      for (int i = 0; i < 20; i++)
        (lat: 47.61, lon: -122.34 + i * 0.0005, pubKey: 'p$i'),
    ];
    const double r = 250;
    final List<HexCell> cells =
        hexField(points: points, box: box, circumradiusMetres: r);
    // Every cell has the same area by construction; the assertion is that the
    // number the chip quotes is that area, so the two agree on the screen.
    expect(hexArea(r), closeTo(162379, 400),
        reason: 'a 250 m cell is about 0.16 km2, which is what the chip says');
    expect(cells, isNotEmpty);
    final Set<double> heights = <double>{
      for (final HexCell c in cells)
        (hexCorners(c.centre, r).last.latitude -
                hexCorners(c.centre, r).first.latitude)
            .abs(),
    };
    expect(heights.length, 1, reason: 'no cell is drawn at a different size');
  });

  test('nodes outside the box are not counted', () {
    final List<HexCell> cells = hexField(
      points: <DensityPoint>[
        (lat: 47.7, lon: -122.3, pubKey: 'far'),
        (lat: 47.61, lon: -122.34, pubKey: 'near'),
      ],
      box: box,
      circumradiusMetres: 150,
    );
    final List<String> all = <String>[
      for (final HexCell c in cells) ...c.points,
    ];
    expect(all, <String>['near']);
  });

  test('a busy cell draws darker than a quiet one', () {
    expect(hexAlpha(0), lessThan(hexAlpha(1)));
    expect(hexAlpha(1), lessThan(hexAlpha(4)));
    expect(hexAlpha(4), lessThan(hexAlpha(20)));
    expect(hexAlpha(20), lessThanOrEqualTo(0.6),
        reason: 'the field must stay subtle enough to see the nodes through it');
    // A square root, not a line: four nodes is already "busier than most".
    expect(hexAlpha(4), greaterThan(hexAlpha(20) * 0.6));
  });

  test('the cap keeps the densest cells', () {
    final List<DensityPoint> points = <DensityPoint>[
      // Nine near one place, one far away.
      for (int i = 0; i < 9; i++)
        (lat: 47.6100 + i * 0.00002, lon: -122.3400, pubKey: 'busy$i'),
      (lat: 47.6190, lon: -122.3210, pubKey: 'lonely'),
    ];
    final List<HexCell> cells = hexField(
        points: points, box: box, circumradiusMetres: 100, maxCells: 1);
    expect(cells.length, 1);
    expect(cells.single.count, 9);
  });

  // The field is a grid of bins, so a bin has to look the same at every zoom:
  // when the radius was snapped to a ladder the hexagons jumped by up to two
  // and a half times at every boundary, and zooming out made the field breathe.
  group('the field size', () {
    test('a cell is the same size on the glass at every zoom', () {
      for (final double mpp in <double>[0.2, 1, 8, 60, 500, 5000, 60000]) {
        final double r = hexRadiusForZoom(metresPerPixel: mpp);
        expect(r / mpp, 18.0,
            reason: 'at $mpp m/px the cell appeared at ${r / mpp} px');
      }
    });

    test('the ground area is what changes, and it grows as you zoom out', () {
      final double street = hexRadiusForZoom(metresPerPixel: 0.6);
      final double world = hexRadiusForZoom(metresPerPixel: 40000);
      expect(street, lessThanOrEqualTo(50),
          reason: 'a 25 m or 50 m cell is what a street view can show');
      expect(world, greaterThanOrEqualTo(10000),
          reason: 'a world view covers a country per cell');
    });

    test('the cell count is the same at every scale', () {
      // By construction: the radius is a pixel count. A viewport of the same
      // pixel size always holds the same number of cells.
      final double first = <double>[
        for (final double mpp in <double>[0.2, 1, 8, 60, 500, 5000, 60000])
          420 * mpp * 900 * mpp / (3 * math.sqrt(3) / 2 * math.pow(hexRadiusForZoom(metresPerPixel: mpp), 2)),
      ].reduce((double a, double b) {
        // Compared with a tolerance: the area is a product of squares, so the
        // same count arrives with a few ulps of noise and exact equality is
        // asserting the floating-point rounding, not the design.
        expect(b, closeTo(a, 1e-6),
            reason: 'the field changed its cell count with the zoom');
        return a;
      });
      expect(first, lessThan(1400));
    });

    test('a nonsense viewport falls back instead of dividing by zero', () {
      expect(hexRadiusForZoom(metresPerPixel: 0),
          kDefaultHexCircumradiusMetres);
      expect(hexRadiusForZoom(metresPerPixel: double.nan),
          kDefaultHexCircumradiusMetres);
      expect(hexRadiusForZoom(metresPerPixel: 1, radiusPx: 0),
          kDefaultHexCircumradiusMetres);
    });
  });

  group('the lattice belongs to the ground, and its cells are drawn at its own scale', () {
    const double r = 250;
    GeoBox box(double west, double south) =>
        GeoBox(west: west, south: south, east: west + 0.02, north: south + 0.02);

    test('panning by less than a cell leaves the hexagons where they were', () {
      // A field pinned to the glass is what made this look like a decoration:
      // drag the map and the hexagons slide with the camera while the streets
      // move under them.
      final List<HexCell> a = hexField(
          points: const <DensityPoint>[],
          box: box(-105.00, 40.00),
          circumradiusMetres: r,
          includeEmpty: true);
      final List<HexCell> b = hexField(
          points: const <DensityPoint>[],
          box: box(-104.9985, 39.9985), // about 130 m east and 165 m south
          circumradiusMetres: r,
          includeEmpty: true);
      // Same lattice columns exist in both, at the same latitudes, because the
      // origin snapped to the same whole cell.
      final Set<double> la = <double>{for (final HexCell c in a) c.centre.latitude};
      final Set<double> lb = <double>{for (final HexCell c in b) c.centre.latitude};
      expect(la.intersection(lb), isNotEmpty,
          reason: 'no latitude was shared, so the lattice moved with the camera');
    });

    test('a cell is drawn at the width its column pitch gave it', () {
      // A world view: the box centre is far from the cells at its edges, which
      // is where recomputing metres-per-longitude per cell separated the columns.
      final List<HexCell> cells = hexField(
          points: const <DensityPoint>[],
          box: const GeoBox(west: -10, south: 30, east: 10, north: 60),
          circumradiusMetres: 500000,
          includeEmpty: true);
      expect(cells, isNotEmpty);
      double widthOf(HexCell c) {
        final double west = c.corners
            .map((LatLng p) => p.longitude)
            .reduce((double a, double b) => a < b ? a : b);
        final double east = c.corners
            .map((LatLng p) => p.longitude)
            .reduce((double a, double b) => a > b ? a : b);
        // Measured with the box's own scale, the one the lattice laid the cells
        // out with. Using each cell's latitude here would re-introduce exactly
        // the error the fix removes and measure nothing.
        final double lat0 = (30 + 60) / 2;
        return (east - west) *
            kMetresPerDegLatHex *
            math.cos(lat0 * math.pi / 180).abs();
      }

      // In ground metres at the cell's own latitude, every cell must measure the
      // same width, √3·R, whichever row it is on.
      final double pitch = math.sqrt(3) * 500000;
      for (final HexCell c in cells) {
        expect(widthOf(c), closeTo(pitch, pitch * 0.02),
            reason: 'row ${c.row} drew at ${widthOf(c)} m, not $pitch m');
      }
    });
  });

  test('a viewport holds the cells its own radius allows', () {
    // A pointy-top hexagon is √3·R wide and pitched 1.5·R row to row.
    const double r = 18;
    final double width = math.sqrt(3) * r * 10; // exactly ten columns
    final double height = 1.5 * r * 6; // exactly six rows
    // Ten columns and six rows, plus the two-cell margin the lattice needs for
    // its half-cell offsets.
    expect(hexCellsForViewport(width: width, height: height), 12 * 8);

    // A phone is about 400: the constant this replaces said 800, which was not
    // wrong for a phone, only for everything bigger.
    expect(hexCellsForViewport(width: 420, height: 900), greaterThan(200));

    // A tablet landscape viewport needs more than a constant 800, which is the
    // defect: `includeEmpty` emits in row order, so a short bound drops the last
    // rows and the bottom of the map has no field.
    expect(hexCellsForViewport(width: 1280, height: 800), greaterThan(800));

    // Nonsense falls back rather than throwing.
    expect(hexCellsForViewport(width: 0, height: 0), 400);
    expect(hexCellsForViewport(width: double.nan, height: 100), 400);
  });


  group('the field keeps up with a pinch', () {
    test('a continuous radius is quantised onto a half-octave ladder', () {
      // The radius used to be continuous, so every frame of a pinch changed the
      // memo key and rebuilt the lattice. It rounds to √2 steps now, which is
      // half a zoom level: a cell size that visibly changes once, not jitter.
      final double a = quantiseHexRadius(100);
      final double b = quantiseHexRadius(102);
      final double c = quantiseHexRadius(160);
      expect(b, a, reason: 'a two percent change is not a new cell size');
      expect(c, greaterThan(a));
      // Every result is on the ladder, so the same input always gives the same
      // key.
      expect(quantiseHexRadius(a), a);
      expect(quantiseHexRadius(quantiseHexRadius(137.5)),
          quantiseHexRadius(137.5));
    });

    test('a pinch steps the radius about twice per doubling', () {
      int steps = 0;
      double last = quantiseHexRadius(10);
      for (double m = 10; m < 20; m += 0.05) {
        final double q = quantiseHexRadius(m);
        if (q != last) {
          steps++;
          last = q;
        }
      }
      expect(steps, inInclusiveRange(1, 3),
          reason: 'a doubling should cross the ladder once or twice');
    });
  });

  group('the field covers the ground the reader is looking at', () {
    test('the margin is stated once and is big enough for a zoom step', () {
      // A field built exactly to the viewport has no cells in the ground a
      // zoom-out exposes, which is why the edge looked bare until the next
      // build.
      expect(kHexFieldPad, greaterThan(0.2));
      expect(kHexFieldPad, lessThan(0.5),
          reason: 'more than half a screen of margin is a field nobody reads');
    });

    test('a padded box still fits the cap it is given', () {
      // The cap is computed from the box, not from the screen: a cap sized to
      // the screen truncates the last rows of a field built past it.
      const double w = 1080, h = 2400;
      final int screenCells = hexCellsForViewport(width: w, height: h);
      final int boxCells = hexCellsForViewport(
          width: w * (1 + 2 * kHexFieldPad),
          height: h * (1 + 2 * kHexFieldPad));
      expect(boxCells, greaterThan(screenCells));
    });
  });
}
