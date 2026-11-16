// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/geofence/geofence_engine.dart';

/// A fence that is a shape rather than a circle.
///
/// A circle cannot follow a property line, a trailhead, a base perimeter or a
/// parking row, which are the shapes a crew actually cares about. The geometry
/// is the part that has to be right: a bounding box would call the gap in a
/// horseshoe "inside", and a fence that fires when you are standing in the
/// driveway it was drawn around is worse than no fence.
void main() {
  const double lat0 = 39.7392;
  const double lon0 = -104.9903;
  const double mPerDegLat = 111320.0;

  /// A point [north] and [east] metres from the origin, in degrees.
  FencePoint at(double north, double east) {
    final double cos = (lat0 * 3.141592653589793 / 180).abs();
    final double mPerDegLon = mPerDegLat * (cos < 0.01 ? 0.01 : cos);
    return FencePoint(lat0 + north / mPerDegLat, lon0 + east / mPerDegLon);
  }

  /// A 200 m square with a 100 m notch cut into its north edge: the horseshoe.
  ///
  /// The notch is the case a bounding box gets wrong, and it is the shape of a
  /// fence drawn around a building with a driveway.
  final List<FencePoint> horseshoe = <FencePoint>[
    at(0, 0),
    at(0, 200),
    at(100, 200),
    at(100, 150),
    at(50, 150),
    at(50, 50),
    at(100, 50),
    at(100, 0),
  ];

  group('point in polygon', () {
    test('a point inside a concave polygon is inside', () {
      expect(polygonContains(horseshoe, at(25, 25).lat, at(25, 25).lon), isTrue);
    });

    test('a point in the notch is outside', () {
      // The notch is the gap between the two arms: x 50..100, y 50..150.
      final FencePoint p = at(100, 75);
      expect(polygonContains(horseshoe, p.lat, p.lon), isFalse,
          reason: 'a bounding box would call the driveway inside the fence');
    });

    test('a point on an edge is inside', () {
      // Exactly on the west edge, half way up.
      final FencePoint p = at(50, 0);
      expect(polygonContains(horseshoe, p.lat, p.lon), isTrue,
          reason: 'a boundary you are standing on is a boundary you are in');
    });

    test('a point far away is outside', () {
      final FencePoint p = at(5000, 5000);
      expect(polygonContains(horseshoe, p.lat, p.lon), isFalse);
    });

    test('a triangle is a polygon', () {
      final List<FencePoint> tri = <FencePoint>[
        at(0, 0),
        at(0, 100),
        at(100, 50),
      ];
      expect(polygonContains(tri, at(30, 50).lat, at(30, 50).lon), isTrue);
      expect(polygonContains(tri, at(90, 5).lat, at(90, 5).lon), isFalse);
    });

    test('fewer than three corners is not a shape', () {
      expect(polygonContains(<FencePoint>[at(0, 0), at(0, 10)], lat0, lon0),
          isFalse);
    });
  });

  group('edge distance', () {
    test('is zero on the line and grows away from it', () {
      final FencePoint on = at(0, 100);
      expect(polygonEdgeDistanceMeters(horseshoe, on.lat, on.lon),
          lessThan(0.1));
      final FencePoint inside = at(20, 100);
      expect(polygonEdgeDistanceMeters(horseshoe, inside.lat, inside.lon),
          closeTo(20, 1));
    });
  });

  group('a polygon fence fires like a circle does', () {
    GeofenceWatch watch() => GeofenceWatch(Geofence(
          id: 'poly',
          lat: lat0,
          lon: lon0,
          radiusMeters: 200,
          polygon: horseshoe,
        ));

    test('walking in fires once, and standing still does not fire again', () {
      final GeofenceWatch w = watch();
      final FencePoint inside = at(25, 25);
      expect(w.update(lat: inside.lat, lon: inside.lon), GeofenceEvent.entered);
      expect(w.isInside, isTrue);
      expect(w.entries, 1);
      for (int i = 0; i < 5; i++) {
        expect(w.update(lat: inside.lat, lon: inside.lon),
            GeofenceEvent.unchanged);
      }
      expect(w.entries, 1, reason: 'one continuous stay is one entry');
    });

    test('standing on the line does not chatter', () {
      final GeofenceWatch w = watch();
      final FencePoint inside = at(25, 25);
      w.update(lat: inside.lat, lon: inside.lon);
      // Walk to the west edge and sit on it.
      final FencePoint onEdge = at(25, 0);
      for (int i = 0; i < 5; i++) {
        expect(w.update(lat: onEdge.lat, lon: onEdge.lon),
            GeofenceEvent.unchanged);
      }
      expect(w.isInside, isTrue);
    });

    test('a step just outside the line is not a leave', () {
      final GeofenceWatch w = watch();
      final FencePoint inside = at(25, 25);
      w.update(lat: inside.lat, lon: inside.lon);
      // Two metres outside the west edge: inside the band, so no event.
      final FencePoint justOut = at(25, -2);
      expect(w.update(lat: justOut.lat, lon: justOut.lon),
          GeofenceEvent.unchanged);
      expect(w.isInside, isTrue);
    });

    test('walking out past the band fires one leave', () {
      final GeofenceWatch w = watch();
      final FencePoint inside = at(25, 25);
      w.update(lat: inside.lat, lon: inside.lon);
      // The band is 5 % of the fence's own size, floored at two metres; 200 m
      // across gives ten metres, so twenty metres out is clear of it.
      final FencePoint out = at(25, -20);
      expect(w.update(lat: out.lat, lon: out.lon), GeofenceEvent.left);
      expect(w.isInside, isFalse);
      expect(w.update(lat: out.lat, lon: out.lon), GeofenceEvent.unchanged);
    });

    test('a sample with no fix changes nothing', () {
      final GeofenceWatch w = watch();
      final FencePoint inside = at(25, 25);
      w.update(lat: inside.lat, lon: inside.lon);
      expect(w.update(), GeofenceEvent.noPosition);
      expect(w.isInside, isTrue);
    });
  });

  group('the centre and the radius that contains the shape', () {
    test('are derived from the corners', () {
      final ({double lat, double lon, double radiusMeters}) c =
          polygonCentre(horseshoe);
      // The vertex average of the horseshoe sits inside its bounding box.
      expect(c.lat, closeTo(lat0 + 50 / mPerDegLat, 0.0005));
      // The radius reaches the farthest corner, so a circle of it contains the
      // whole shape.
      for (final FencePoint p in horseshoe) {
        final double d = polygonEdgeDistanceMeters(
            <FencePoint>[FencePoint(c.lat, c.lon), p], c.lat, c.lon);
        expect(d, lessThanOrEqualTo(c.radiusMeters + 1));
      }
    });

    test('an empty polygon has no centre', () {
      final ({double lat, double lon, double radiusMeters}) c =
          polygonCentre(const <FencePoint>[]);
      expect(c.radiusMeters, 0);
    });
  });
}
