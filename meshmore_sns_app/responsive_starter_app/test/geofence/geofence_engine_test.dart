// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/geofence/geofence_engine.dart';

void main() {
  // A fence of radius 100 m at a point; one degree of latitude is about
  // 111,320 m, so the tests place a sample by its distance in metres.
  const double lat = 39.7392;
  const double lon = -104.9903;
  const double metresPerDegreeLat = 111320.0;

  GeofenceWatch watch({double radius = 100}) => GeofenceWatch(Geofence(
        id: 'fence-1',
        lat: lat,
        lon: lon,
        radiusMeters: radius,
      ));

  double latAt(double metres) => lat + metres / metresPerDegreeLat;

  test('entering fires once, and staying inside does not fire again', () {
    final GeofenceWatch w = watch();
    expect(w.update(lat: latAt(0), lon: lon), GeofenceEvent.entered);
    expect(w.isInside, isTrue);
    expect(w.entries, 1);
    for (int i = 0; i < 10; i++) {
      expect(w.update(lat: latAt(10), lon: lon), GeofenceEvent.unchanged);
    }
    expect(w.entries, 1, reason: 'one continuous stay is one entry');
  });

  test('the margin at 100 m is 95 m in and 105 m out', () {
    final GeofenceWatch w = watch();
    expect(w.update(lat: latAt(0), lon: lon), GeofenceEvent.entered);
    // 97 m out is inside the leave radius (105 m): no leave yet.
    expect(w.update(lat: latAt(97), lon: lon), GeofenceEvent.unchanged);
    expect(w.isInside, isTrue);
    // 106 m out is past it.
    expect(w.update(lat: latAt(106), lon: lon), GeofenceEvent.left);
    expect(w.isInside, isFalse);
    // 97 m out is outside the enter radius (95 m): no re-entry yet.
    expect(w.update(lat: latAt(97), lon: lon), GeofenceEvent.unchanged);
    expect(w.isInside, isFalse);
    expect(w.update(lat: latAt(94), lon: lon), GeofenceEvent.entered);
    expect(w.entries, 2);
  });

  test('a sample that oscillates inside the margin never fires', () {
    final GeofenceWatch w = watch();
    w.update(lat: latAt(0), lon: lon); // inside
    for (int i = 0; i < 40; i++) {
      // Between the enter and leave radii the state is sticky in both
      // directions: this is what stops boundary chatter.
      final double d = 100 + (i.isEven ? 3.0 : -3.0);
      expect(w.update(lat: latAt(d), lon: lon), GeofenceEvent.unchanged);
    }
    expect(w.entries, 1);
  });

  test('a reverse crossing just past the inner radius does not fire', () {
    final GeofenceWatch w = watch();
    w.update(lat: latAt(0), lon: lon);
    w.update(lat: latAt(106), lon: lon); // left
    for (int i = 0; i < 20; i++) {
      // Hovering between 95 and 105 m outside: still not in.
      final double d = i.isEven ? 96.0 : 104.0;
      expect(w.update(lat: latAt(d), lon: lon), GeofenceEvent.unchanged);
    }
    expect(w.isInside, isFalse);
    expect(w.entries, 1);
  });

  test('no fix changes nothing and does not count as leaving', () {
    final GeofenceWatch w = watch();
    w.update(lat: latAt(0), lon: lon);
    expect(w.update(lat: null, lon: null), GeofenceEvent.noPosition);
    expect(w.isInside, isTrue);
    expect(w.entries, 1);
  });

  test('a zero radius still has a band, and it is degenerate but honest', () {
    final GeofenceWatch w = watch(radius: 0);
    expect(w.update(lat: lat, lon: lon), GeofenceEvent.entered);
    expect(w.update(lat: latAt(1), lon: lon), GeofenceEvent.left);
  });
}
