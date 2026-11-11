// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' hide Path;

import 'package:meshmore_sns_app/maps/coverage_quilt.dart';
import 'package:meshmore_sns_app/maps/density_overlay.dart';
import 'package:meshmore_sns_app/meshcore/coverage_store.dart';

/// The two overlays the Map tab gained from the grid's audit: the reception
/// quilt that left with the Coverage view, and the equal-area density grid the
/// deleted view owed. Both are pure so they can be checked here rather than by
/// looking at a map.

void main() {
  group('the reception quilt', () {
    test('a cell key becomes the bucket square it names', () {
      const int latBucket = 1800;
      const int lonBucket = -4500;
      final List<Polygon> polys = coveragePolygons(
        cells: <String, int>{'$latBucket,$lonBucket': 1794300000},
        nowUnix: 1794300000,
        color: const Color(0xFF00FF00),
      );
      expect(polys, hasLength(1));
      final List<LatLng> pts = polys.first.points;
      expect(pts, hasLength(4));
      expect(pts.first.latitude, closeTo(latBucket * CoverageStore.cellDeg, 1e-9));
      expect(pts.first.longitude,
          closeTo(lonBucket * CoverageStore.cellDeg, 1e-9));
      // The square is one cellDeg on a side, closing back onto the first point.
      expect(pts[2].latitude - pts[0].latitude,
          closeTo(CoverageStore.cellDeg, 1e-9));
      expect(pts[2].longitude - pts[0].longitude,
          closeTo(CoverageStore.cellDeg, 1e-9));
    });

    test('a key that is not a bucket pair is skipped, not drawn at zero', () {
      final List<Polygon> polys = coveragePolygons(
        cells: <String, int>{'nonsense': 1794300000, '1': 1794300000},
        nowUnix: 1794300000,
        color: const Color(0xFF00FF00),
      );
      expect(polys, isEmpty);
    });

    test('recency is four steps, not a continuum', () {
      // The difference between an hour and a day is a fact about the survey.
      // A continuous fade would claim a precision the samples do not have.
      expect(coverageRecency(0), 1.0);
      expect(coverageRecency(3599), 1.0);
      expect(coverageRecency(3600), 0.75);
      expect(coverageRecency(86399), 0.75);
      expect(coverageRecency(86400), 0.45);
      expect(coverageRecency(604800), 0.2);
      expect(coverageRecency(const Duration(days: 365).inSeconds), 0.2);
    });

    test('an older cell is drawn fainter than a fresh one', () {
      const Color colour = Color(0xFF0088FF);
      final List<Polygon> fresh = coveragePolygons(
        cells: <String, int>{'0,0': 1794300000},
        nowUnix: 1794300000,
        color: colour,
      );
      final List<Polygon> old = coveragePolygons(
        cells: <String, int>{'0,0': 1794300000 - 86400 * 30},
        nowUnix: 1794300000,
        color: colour,
      );
      expect(fresh.first.color!.a, greaterThan(old.first.color!.a));
    });
  });

  group('the density grid', () {
    const LatLng anchor = LatLng(39.0, -105.0);
    const double cell = 250;

    DensityPoint at(double lat, double lon, [String key = 'a']) =>
        (lat: lat, lon: lon, pubKey: key);

    /// Metres between two points, flat-earth, which is what the grid assumes.
    double metres(LatLng a, LatLng b) {
      final double dy = (b.latitude - a.latitude) * kMetresPerDegLat;
      final double dx = (b.longitude - a.longitude) *
          kMetresPerDegLat *
          math.cos(a.latitude * math.pi / 180);
      return math.sqrt(dx * dx + dy * dy);
    }

    test('nodes inside one square share a cell, and the count says how many',
        () {
      // Three nodes within ~40 m of each other, one 400 m away.
      final List<DensityCell> cells = densityCells(
        points: <DensityPoint>[
          at(39.0001, -104.9999, 'a'),
          at(39.0002, -104.9998, 'b'),
          at(39.0003, -104.9997, 'c'),
          at(39.004, -104.9999, 'd'),
        ],
        anchor: anchor,
        cellMetres: cell,
      );
      expect(cells, hasLength(2));
      expect(cells.map((DensityCell c) => c.count).reduce(math.max), 3);
      // Every node lands in exactly one cell, which is the whole claim of a grid.
      expect(cells.expand((DensityCell c) => c.pubKeys).toSet(),
          <String>{'a', 'b', 'c', 'd'});
    });

    test('every square covers the same ground area', () {
      // The property the deleted equal-area view held and nothing else did:
      // a count per cell compares like with like. The squares are identical, so
      // equal area follows from equal side length.
      final List<DensityCell> cells = densityCells(
        points: <DensityPoint>[
          at(39.0, -105.0),
          at(39.02, -105.03),
          at(38.98, -104.97),
        ],
        anchor: anchor,
        cellMetres: cell,
      );
      for (final DensityCell c in cells) {
        final double eastWest = metres(c.bounds[0], c.bounds[1]);
        expect(eastWest, closeTo(cell, 1.0),
            reason: 'a square is 250 m across on the ground');
        // And the north-south side matches, so it is a square and not a strip.
        expect(metres(c.bounds[0], c.bounds[3]), closeTo(eastWest, 1.0));
      }
    });

    test('the count does not depend on where the viewport is', () {
      final List<DensityPoint> points = <DensityPoint>[
        at(39.001, -105.001, 'a'),
        at(39.001, -105.001, 'b'),
      ];
      final List<DensityCell> one = densityCells(
          points: points, anchor: anchor, cellMetres: cell);
      final List<DensityCell> two = densityCells(
          points: points, anchor: anchor, cellMetres: cell);
      expect(one.single.count, two.single.count);
      expect(one.single.id, two.single.id);
    });

    test('no positions means no cells, not a lattice over the ocean', () {
      expect(
          densityCells(
              points: const <DensityPoint>[], anchor: anchor, cellMetres: cell),
          isEmpty);
    });

    test('a cell size of zero is refused rather than dividing by it', () {
      expect(
          () => densityCells(
              points: <DensityPoint>[at(39, -105)],
              anchor: anchor,
              cellMetres: 0),
          throwsArgumentError);
    });

    test('the ramp keeps a single node visible next to a busy cell', () {
      // Linear would make one node among forty invisible, which hides most of
      // a mesh. The root keeps the low end readable.
      final double alone = densityAlpha(1, 40);
      final double busiest = densityAlpha(40, 40);
      expect(alone, greaterThan(0.15));
      expect(busiest, closeTo(0.46, 1e-9));
      // Faint on purpose: the pins on this map are pale squares too, and a
      // strong fill made a cell read as a node.
      expect(busiest, lessThan(0.5));
      expect(densityAlpha(0, 40), 0.0);
      expect(densityAlpha(5, 0), 0.0);
      // Monotonic, so darker always means more.
      double last = 0;
      for (int n = 1; n <= 40; n++) {
        final double a = densityAlpha(n, 40);
        expect(a, greaterThan(last));
        last = a;
      }
    });

    test('a tapped point belongs to exactly one square, or none of them', () {
      // The map resolves a tap by asking which square contains the point,
      // because a hit test on the polygons loses every tap to the pin standing
      // in the middle of the square.
      final List<DensityCell> cells = densityCells(
        points: <DensityPoint>[at(39.0001, -104.9999, 'a')],
        anchor: anchor,
        cellMetres: cell,
      );
      final DensityCell only = cells.single;
      expect(cellContains(only, only.centre), isTrue);
      expect(cellContains(only, only.bounds[0]), isTrue,
          reason: 'a shared corner counts as inside');
      // A point one cell east is in no drawn square, because empty squares are
      // not drawn at all.
      final LatLng east = LatLng(only.centre.latitude,
          only.bounds[2].longitude + 0.01);
      expect(cellContains(only, east), isFalse);
      for (final DensityCell c in cells) {
        expect(cellContains(c, east), isFalse);
      }
    });

    test('a count is drawn when the square on screen can hold one', () {
      // The rule is the square, not the count of squares: three hundred small
      // ones on a metro view get no numbers, four large ones on a street view
      // get all of theirs.
      expect(densityLabelsFit(215), isTrue);
      expect(densityLabelsFit(kDensityLabelMinPx), isTrue);
      expect(densityLabelsFit(kDensityLabelMinPx - 1), isFalse);
      expect(densityLabelsFit(3), isFalse,
          reason: 'a 3 px square cannot hold a digit');
    });

    test('the cell size follows the zoom, and reads as a distance', () {
      // One zoom's cell size is another zoom's smudge: at 250 m, metro zoom
      // gives a three-pixel square and street zoom one square fills the screen.
      // The ladder keeps a square at least 48 px across at every scale.
      double sizeAt(double metresPerPixel) =>
          densityCellMetresFor(metresPerPixel: metresPerPixel);
      expect(sizeAt(1), 50, reason: 'street zoom: the smallest cell is plenty');
      expect(sizeAt(5.5), 500);
      expect(sizeAt(17), 1000);
      expect(sizeAt(70), 5000);
      expect(sizeAt(300), 25000);
      expect(sizeAt(5000), kDensityCellLadder.last,
          reason: 'past the ladder, the largest cell is the answer');
      // The chosen size always clears the target on screen.
      for (final double mpp in <double>[0.5, 3, 9, 40, 120, 700, 2000]) {
        final double m = sizeAt(mpp);
        expect(m / mpp, greaterThanOrEqualTo(48));
      }
      expect(densityCellMetresFor(metresPerPixel: 0), kDensityCellLadder.last);
    });

    test('the size label is the number a person reads', () {
      expect(densityCellLabel(250), '250 m');
      expect(densityCellLabel(1000), '1 km');
      expect(densityCellLabel(2500), '2.5 km');
      expect(densityCellLabel(25000), '25 km');
    });

    test('the polygons carry the cell, so a tap can name its nodes', () {
      final List<DensityCell> cells = densityCells(
        points: <DensityPoint>[at(39.0, -105.0, 'x'), at(39.0, -105.0, 'y')],
        anchor: anchor,
        cellMetres: cell,
      );
      final List<Polygon<DensityCell>> polys =
          densityPolygons(cells: cells, color: const Color(0xFF00AAFF));
      expect(polys, hasLength(cells.length));
      expect(polys.first.hitValue, same(cells.first));
      expect(polys.first.hitValue!.pubKeys, <String>['x', 'y']);
    });
  });
}
