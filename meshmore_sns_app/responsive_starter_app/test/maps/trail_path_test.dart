// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:meshmore_sns_app/screens/street_map_view.dart';

/// A trail is a walk, not a join-the-dots.
///
/// One bad fix — a stale or transposed position — used to be joined to the rest,
/// which drew a line straight across the map. The owner saw that as a green line
/// extending out of the marker, with nothing saying it was a sample and not a
/// route.
void main() {
  List<({double latitude, double longitude, int unixSec})> path(
          List<(double, double)> pts) =>
      <({double latitude, double longitude, int unixSec})>[
        for (int i = 0; i < pts.length; i++)
          (latitude: pts[i].$1, longitude: pts[i].$2, unixSec: 1000 + i),
      ];

  test('a walk is kept whole', () {
    final List<LatLng> trail = StreetMapView.trailPathFor(
      path(<(double, double)>[
        (39.0000, -105.0000),
        (39.0004, -105.0004),
        (39.0008, -105.0008),
      ]),
    );
    expect(trail, hasLength(3));
  });

  test('a far sample starts a new run instead of being joined', () {
    // 0.5 degrees of latitude is ~55 km: a stale or transposed fix.
    final List<LatLng> trail = StreetMapView.trailPathFor(
      path(<(double, double)>[
        (39.0000, -105.0000),
        (39.0004, -105.0004),
        (39.5000, -105.0000),
        (39.5004, -105.0004),
        (39.5008, -105.0008),
      ]),
    );
    expect(trail, hasLength(3),
        reason: 'only the run after the gap is drawn');
    expect(trail.first.latitude, greaterThan(39.4),
        reason: 'the dropped half is the history before the jump');
  });

  test('the live fix is not joined across a gap either', () {
    final List<LatLng> trail = StreetMapView.trailPathFor(
      path(<(double, double)>[
        (39.0000, -105.0000),
        (39.0004, -105.0004),
        (39.0008, -105.0008),
      ]),
      selfLat: 39.6,
      selfLon: -105.0,
    );
    // One point is not a trail, so nothing is drawn at all — which is right: a
    // lone dot beside the marker reads as clutter, not as a route.
    expect(trail, isEmpty,
        reason: 'one point after the gap is not a trail, so nothing is drawn');
  });

  test('a live fix at the end of a walk extends it', () {
    final List<LatLng> trail = StreetMapView.trailPathFor(
      path(<(double, double)>[
        (39.0000, -105.0000),
        (39.0004, -105.0004),
      ]),
      selfLat: 39.0008,
      selfLon: -105.0008,
    );
    expect(trail, hasLength(3));
  });
}
