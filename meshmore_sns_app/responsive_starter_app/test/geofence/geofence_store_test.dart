// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/geofence/geofence_engine.dart';
import 'package:meshmore_sns_app/geofence/geofence_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/meshcore/secure/sealed_document.dart';

void main() {
  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Fences are sealed now: this needs the store's own seams, not a
    // preferences mock.
    dir = Directory.systemTemp.createTempSync('mm_fence_store');
    SealedDocument.cipherOverride = MemoryRecordCipher.random();
    SealedDocument.directoryOverride = dir;
  });

  tearDown(() {
    SealedDocument.cipherOverride = null;
    SealedDocument.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a fence survives a save and a load', () async {
    await GeofenceStore.save(const <StoredGeofence>[
      StoredGeofence(
        id: 'gf1',
        label: 'Camp',
        latitude: 51.5,
        longitude: -0.12,
        radiusMeters: 250,
      ),
    ]);
    final List<StoredGeofence> rows = await GeofenceStore.load();
    expect(rows.length, 1);
    expect(rows.single.label, 'Camp');
    expect(rows.single.radiusMeters, 250);
  });

  test('a corrupt row is dropped, not thrown', () {
    expect(
      GeofenceStore.decode('[{"id":"a","lat":"x","lon":1,"radius":2}]'),
      isEmpty,
    );
    expect(GeofenceStore.decode('not json'), isEmpty);
    expect(GeofenceStore.decode(null), isEmpty);
  });

  test('a fence with no radius or an impossible one is not a fence', () {
    expect(
      GeofenceStore.decode('[{"id":"a","lat":1,"lon":1,"radius":0}]'),
      isEmpty,
    );
    expect(
      GeofenceStore.decode('[{"id":"a","lat":1,"lon":1,"radius":-5}]'),
      isEmpty,
    );
    expect(
      GeofenceStore.decode('[{"id":"a","lat":91,"lon":1,"radius":5}]'),
      isEmpty,
    );
  });

  test('the engine refuses boundary chatter: one event per continuous stay',
      () {
    final Geofence fence = Geofence(
        id: 'f', lat: 0, lon: 0, radiusMeters: 100);
    final GeofenceWatch watch = GeofenceWatch(fence);
    // 94 m: inside the 95 m entry radius.
    expect(_feed(watch, 94), GeofenceEvent.entered);
    // 102 m: inside the 105 m leave radius, so nothing fires.
    expect(_feed(watch, 102), GeofenceEvent.unchanged);
    expect(_feed(watch, 99), GeofenceEvent.unchanged);
    // 106 m: outside the leave radius.
    expect(_feed(watch, 106), GeofenceEvent.left);
    expect(_feed(watch, 104), GeofenceEvent.unchanged);
    expect(_feed(watch, 94), GeofenceEvent.entered);
    expect(watch.entries, 2);
  });

  test('a fence that is never reached fires nothing', () {
    final GeofenceWatch watch =
        GeofenceWatch(Geofence(id: 'f', lat: 0, lon: 0, radiusMeters: 100));
    expect(_feed(watch, 400), GeofenceEvent.unchanged);
    expect(_feed(watch, 200), GeofenceEvent.unchanged);
    expect(watch.entries, 0);
  });

  test('a sample with no fix changes nothing', () {
    final GeofenceWatch watch =
        GeofenceWatch(Geofence(id: 'f', lat: 0, lon: 0, radiusMeters: 100));
    expect(watch.update(lat: null, lon: null), GeofenceEvent.noPosition);
    expect(watch.isInside, isFalse);
  });
  test('a drawn fence survives a save and a load', () async {
    const List<FencePoint> corners = <FencePoint>[
      FencePoint(51.5, -0.12),
      FencePoint(51.5, -0.11),
      FencePoint(51.51, -0.11),
      FencePoint(51.51, -0.12),
    ];
    await GeofenceStore.save(const <StoredGeofence>[
      StoredGeofence(
        id: 'gf2',
        label: 'Yard',
        latitude: 51.505,
        longitude: -0.115,
        radiusMeters: 700,
        polygon: corners,
      ),
    ]);
    final List<StoredGeofence> rows = await GeofenceStore.load();
    expect(rows.single.isPolygon, isTrue);
    expect(rows.single.polygon, corners);
    expect(rows.single.label, 'Yard');
  });

  test('a record written before polygons existed is still a circle', () {
    // The exact shape an older build wrote: no `poly` key at all.
    final List<StoredGeofence> rows = GeofenceStore.decode(
        '[{"id":"a","label":"Camp","lat":51.5,"lon":-0.12,"radius":250}]');
    expect(rows.single.isPolygon, isFalse);
    expect(rows.single.polygon, isNull);
    expect(rows.single.radiusMeters, 250);
  });

  test('a polygon with fewer than three corners is refused, not rounded', () {
    // A two-corner "fence" is a bug in whatever wrote it. Turning it into a
    // circle would be a shape the reader never drew.
    expect(
        GeofenceStore.decode(
            '[{"id":"a","lat":51.5,"lon":-0.12,"radius":250,'
            '"poly":[{"lat":51.5,"lon":-0.12},{"lat":51.5,"lon":-0.11}]}]'),
        isEmpty);
  });

  test('a polygon with a malformed corner is refused whole', () {
    expect(
        GeofenceStore.decode(
            '[{"id":"a","lat":51.5,"lon":-0.12,"radius":250,'
            '"poly":[{"lat":51.5,"lon":-0.12},{"lat":51.5,"lon":-0.11},'
            '{"lat":"x","lon":-0.10}]}]'),
        isEmpty);
  });

  test('a circle and a polygon live in one record list', () {
    final List<StoredGeofence> rows = GeofenceStore.decode(
        '[{"id":"a","label":"Camp","lat":51.5,"lon":-0.12,"radius":250},'
        '{"id":"b","label":"Yard","lat":51.5,"lon":-0.12,"radius":250,'
        '"poly":[{"lat":51.5,"lon":-0.12},{"lat":51.5,"lon":-0.11},'
        '{"lat":51.51,"lon":-0.11}]}]');
    expect(rows, hasLength(2));
    expect(rows[0].isPolygon, isFalse);
    expect(rows[1].isPolygon, isTrue);
  });
}

/// Feeds a point [northMeters] north of the fence centre.
GeofenceEvent _feed(GeofenceWatch watch, double northMeters) {
  const double metresPerDegreeLat = 111320.0;
  return watch.update(lat: northMeters / metresPerDegreeLat, lon: 0);

}
