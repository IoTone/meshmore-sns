// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:meshmore_sns_app/geofence/geofence_engine.dart';
import 'package:meshmore_sns_app/geofence/geofence_store.dart';
import 'package:meshmore_sns_app/maps/geofence_fit.dart';

StoredGeofence _fence(String id, double lat, double lon, double radius) =>
    StoredGeofence(
      id: id,
      label: id,
      latitude: lat,
      longitude: lon,
      radiusMeters: radius,
    );

void main() {
  test('nothing to show leaves the camera alone', () {
    expect(fitGeofences(const <StoredGeofence>[], viewportPx: 400), isNull);
  });

  test('a nonsense viewport is refused rather than producing a NaN zoom', () {
    final List<StoredGeofence> fences = <StoredGeofence>[
      _fence('a', 39, -105, 250),
    ];
    expect(fitGeofences(fences, viewportPx: 0), isNull);
    expect(fitGeofences(fences, viewportPx: double.nan), isNull);
  });

  test('the centre is the middle of the extent, radii included', () {
    // Two fences a degree apart with different radii: the centre is pulled
    // toward the larger one's edge, because that is what has to fit.
    final List<StoredGeofence> fences = <StoredGeofence>[
      _fence('a', 39.0, -105.0, 250),
      _fence('b', 40.0, -105.0, 5000),
    ];
    final ({LatLng centre, double zoom}) fit =
        fitGeofences(fences, viewportPx: 400)!;
    expect(fit.centre.latitude, greaterThan(39.5),
        reason: 'the big fence at the north end has to be inside the box');
    expect(fit.centre.latitude, inInclusiveRange(39.0, 40.0));
  });

  test('the zoom contains the fences, not only their centres', () {
    // If the radius is left out, the outermost fence is cut in half by the
    // frame, which is the bug this function exists to not have.
    final List<StoredGeofence> fences = <StoredGeofence>[
      _fence('a', 39.0, -105.0, 1000),
      _fence('b', 39.02, -105.0, 1000),
    ];
    final ({LatLng centre, double zoom}) fit =
        fitGeofences(fences, viewportPx: 400)!;
    // Ground metres under the viewport at that zoom must exceed the extent,
    // which is about 2.2 km between the far edges.
    final double metresPerPixel = 156543.03392 *
        (fit.centre.latitude * 3.141592653589793 / 180).abs().clamp(0.01, 1.0) /
        (1 << fit.zoom.round());
    expect(metresPerPixel * 400, greaterThan(2200));
  });

  test('a wider view is a lower zoom', () {
    final ({LatLng centre, double zoom}) near = fitGeofences(
        <StoredGeofence>[_fence('a', 39, -105, 200), _fence('b', 39.01, -105, 200)],
        viewportPx: 400)!;
    final ({LatLng centre, double zoom}) far = fitGeofences(
        <StoredGeofence>[_fence('a', 39, -105, 200), _fence('b', 39.5, -105, 200)],
        viewportPx: 400)!;
    expect(far.zoom, lessThan(near.zoom));
  });

  test('one fence centres on it and shows the whole circle', () {
    final ({LatLng centre, double zoom}) fit = fitGeofences(
        <StoredGeofence>[_fence('a', 39.5, -104.25, 300)],
        viewportPx: 400)!;
    expect(fit.centre.latitude, closeTo(39.5, 1e-9));
    expect(fit.centre.longitude, closeTo(-104.25, 1e-9));
    expect(fit.zoom, greaterThan(10),
        reason: 'a single 300 m circle is a street-scale view');
  });

  test('the zoom never leaves the map\'s own range', () {
    final ({LatLng centre, double zoom}) world = fitGeofences(
        <StoredGeofence>[
          _fence('a', -70, -170, 250000),
          _fence('b', 70, 170, 250000),
        ],
        viewportPx: 400)!;
    expect(world.zoom, greaterThanOrEqualTo(2));
    final ({LatLng centre, double zoom}) tiny = fitGeofences(
        <StoredGeofence>[_fence('a', 39, -105, 1)], viewportPx: 400)!;
    expect(tiny.zoom, lessThanOrEqualTo(17));
  });

  test('a drawn fence is fitted by its corners, not by a circle round it', () {
    // A long thin fence: its stored radius is the distance to the farthest
    // corner, so a circle of it is much wider than the shape. Fitting the
    // corners is what puts the boundary itself in frame.
    final StoredGeofence poly = StoredGeofence(
      id: 'p',
      label: 'p',
      latitude: 39.0,
      longitude: -105.0,
      radiusMeters: 2000,
      polygon: const <FencePoint>[
        FencePoint(39.0, -105.0),
        FencePoint(39.0, -104.99),
        FencePoint(39.001, -104.99),
        FencePoint(39.001, -105.0),
      ],
    );
    final ({LatLng centre, double zoom})? fit =
        fitGeofences(<StoredGeofence>[poly], viewportPx: 400);
    expect(fit, isNotNull);
    // The centre of the corners, not of a 2 km circle around them.
    expect(fit!.centre.latitude, closeTo(39.0005, 0.0005));
    expect(fit.centre.longitude, closeTo(-104.995, 0.0005));
    // A ~90 m shape at 400 px is a street zoom, not a city one.
    expect(fit.zoom, greaterThan(13));
  });

  test('a circle and a drawn fence fit together', () {
    final List<StoredGeofence> fences = <StoredGeofence>[
      _fence('a', 39.0, -105.0, 250),
      StoredGeofence(
        id: 'p',
        label: 'p',
        latitude: 39.02,
        longitude: -105.0,
        radiusMeters: 300,
        polygon: const <FencePoint>[
          FencePoint(39.02, -105.0),
          FencePoint(39.02, -104.99),
          FencePoint(39.021, -104.99),
        ],
      ),
    ];
    final ({LatLng centre, double zoom})? fit =
        fitGeofences(fences, viewportPx: 400);
    expect(fit, isNotNull);
    // Both are inside the frame: the centre sits between them.
    expect(fit!.centre.latitude, greaterThan(39.0));
    expect(fit.centre.latitude, lessThan(39.021));
  });
}
