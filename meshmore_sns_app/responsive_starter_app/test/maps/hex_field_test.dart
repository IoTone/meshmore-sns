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

  test('a hexagon is regular on the screen, at any latitude', () {
    // Measured in the projection's metres, because that is the plane the map
    // draws in: a regular shape there is a regular shape on the glass. The
    // lattice used to be laid out in ground metres, which is the same thing near
    // the box's centre and a stretch away from it.
    const double r = 200;
    for (final double lat in <double>[0, 39, 47.61, 60, -33]) {
      final LatLng centre = LatLng(lat, -122.335);
      final List<LatLng> corners = hexCorners(centre, r);
      expect(corners.length, 6);

      final double cx = mercatorX(centre.longitude);
      final double cy = mercatorY(centre.latitude);
      final List<double> toCorners = <double>[
        for (final LatLng c in corners)
          math.sqrt(math.pow(mercatorX(c.longitude) - cx, 2) +
              math.pow(mercatorY(c.latitude) - cy, 2)),
      ];
      for (final double d in toCorners) {
        expect(d, closeTo(r, 0.01),
            reason: 'at $lat degrees every corner is one radius away');
      }

      // The bounding box: width sqrt(3)·R, height 2R.
      final Iterable<double> ys = corners.map((LatLng c) => mercatorY(c.latitude));
      final Iterable<double> xs = corners.map((LatLng c) => mercatorX(c.longitude));
      final double height = ys.reduce((double a, double b) => a > b ? a : b) -
          ys.reduce((double a, double b) => a < b ? a : b);
      final double width = xs.reduce((double a, double b) => a > b ? a : b) -
          xs.reduce((double a, double b) => a < b ? a : b);
      expect(height, closeTo(2 * r, 0.02));
      expect(width, closeTo(math.sqrt(3) * r, 0.02),
          reason: 'a hexagon wider or narrower than √3·R reads as squashed');
    }
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
    // Measured in the projection's metres, which is the plane the cells are laid
    // out and drawn in. Degrees of latitude would disagree between rows because
    // Mercator stretches with latitude, not because the cells differ.
    final Set<double> heights = <double>{
      for (final HexCell c in cells)
        (mercatorY(hexCorners(c.centre, r).last.latitude) -
                mercatorY(hexCorners(c.centre, r).first.latitude))
            .abs(),
    };
    // Within a hundredth of a millimetre: the same size, allowing for the
    // rounding of a projected coordinate near the pole end of a degree.
    final double one = heights.first;
    for (final double h in heights) {
      expect(h, closeTo(one, 1e-4),
          reason: 'a cell is drawn at a different size: $heights');
    }
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
        points: points, box: box, circumradiusMetres: 250, maxCells: 1);
    expect(cells.length, 1);
    expect(cells.single.count, 9,
        reason: 'nine points a few metres apart share one cell at 250 m');
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

    test('a resize cannot move the lattice', () {
      // The owner saw the hexagons a hair off from where they were after
      // swiping up to the app switcher and coming back. The cause was the cell
      // size: it came from ground metres under the camera, so metres per degree
      // of longitude — a cosine of the box's centre latitude — was part of the
      // frame. A ten-thousandth of a degree of latitude, which a window resize
      // or an app switch can produce, rescaled the frame and slid every cell
      // about a hundredth of a cell.
      HexCell cellAt(GeoBox b) => hexField(
            points: const <DensityPoint>[(lat: 38.92, lon: -104.79, pubKey: 'p')],
            box: b,
            circumradiusMetres: 250,
          ).single;

      const GeoBox a =
          GeoBox(south: 38.90, west: -104.80, north: 38.95, east: -104.75);
      const GeoBox b = GeoBox(
          south: 38.9001, west: -104.7999, north: 38.9501, east: -104.7499);
      final HexCell ca = cellAt(a);
      final HexCell cb = cellAt(b);
      expect(cb.centre.latitude, ca.centre.latitude,
          reason: 'the cell under a fixed point moved north');
      expect(cb.centre.longitude, ca.centre.longitude,
          reason: 'the cell under a fixed point moved east');

      // And the corners come along with it, so the drawn field is unmoved.
      for (int i = 0; i < 6; i++) {
        expect(cb.corners[i].latitude, ca.corners[i].latitude);
        expect(cb.corners[i].longitude, ca.corners[i].longitude);
      }
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
        final double east = c.corners
            .map((LatLng p) => mercatorX(p.longitude))
            .reduce((double a, double b) => a > b ? a : b);
        final double west = c.corners
            .map((LatLng p) => mercatorX(p.longitude))
            .reduce((double a, double b) => a < b ? a : b);
        return east - west;
      }

      // Every cell must measure the same width in the plane the lattice is laid
      // out in, √3·R, whichever row it is on — including a box whose cells are
      // thirty degrees apart, which is where a per-cell scale used to separate
      // the columns by forty percent.
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

  group('no node falls between cells', () {
    test('every node lands inside the hexagon it was counted in', () {
      // The owner's question: can a repeater sit in a gap, with no hexagon under
      // it? The lattice assigns a point to the *nearest* cell centre, and the
      // hexagons are the Voronoi regions of those centres, so there should be no
      // gap — but "should" is not a measurement, and a lattice whose pitch and
      // whose drawn corners disagree would leave exactly that: a node counted in
      // a cell it is not drawn inside.
      const double r = 250;
      final List<DensityPoint> points = <DensityPoint>[
        for (int i = 0; i < 300; i++)
          (
            // A deterministic spread over the box, including its edges.
            lat: box.south + (box.north - box.south) * ((i * 37) % 300) / 300,
            lon: box.west + (box.east - box.west) * ((i * 71) % 300) / 300,
            pubKey: 'n$i',
          ),
      ];
      final List<HexCell> cells = hexField(
        points: points,
        box: box,
        circumradiusMetres: r,
        includeEmpty: true,
      );
      int counted = 0;
      for (final HexCell c in cells) {
        for (final String key in c.points) {
          counted++;
          final DensityPoint p = points.firstWhere((DensityPoint q) => q.pubKey == key);
          expect(hexContains(c.centre, r, LatLng(p.lat, p.lon)), isTrue,
              reason: '$key is counted in cell ${c.id} but not drawn inside it');
        }
      }
      expect(counted, points.length,
          reason: 'every node was counted exactly once');
    });

    test('a node on a cell boundary is counted once, not twice', () {
      // A point equidistant from two centres belongs to one cell: the assignment
      // rounds, so it cannot be counted twice and cannot be dropped.
      final List<DensityPoint> pts = <DensityPoint>[
        (lat: 47.61, lon: -122.335, pubKey: 'a'),
        (lat: 47.61, lon: -122.3349999, pubKey: 'b'),
      ];
      final List<HexCell> cells =
          hexField(points: pts, box: box, circumradiusMetres: 250);
      final int total =
          cells.fold(0, (int n, HexCell c) => n + c.points.length);
      expect(total, 2);
    });
  });
}
