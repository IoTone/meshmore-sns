// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/meshcore/secure/sealed_document.dart';

import 'package:meshmore_sns_app/geofence/geofence_controller.dart';
import 'package:meshmore_sns_app/geofence/geofence_engine.dart';
import 'package:meshmore_sns_app/geofence/geofence_store.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/own_location.dart';

final DateTime t0 = DateTime.utc(2026, 11, 5, 12);

OwnLocation _at(double lat, double lon) => OwnLocation(
      latitude: lat,
      longitude: lon,
      source: OwnLocationSource.phoneFix,
    );

void main() {
  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Fences are sealed now: a persistence test needs the store's own seams
    // rather than a preferences mock.
    dir = Directory.systemTemp.createTempSync('mm_fence_test');
    SealedDocument.cipherOverride = MemoryRecordCipher.random();
    SealedDocument.directoryOverride = dir;
  });

  tearDown(() {
    SealedDocument.cipherOverride = null;
    SealedDocument.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a fence fires once on the way in and once on the way out', () async {
    final GeofenceController g = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await g.load();
    await g.addFence(
        label: 'Camp', latitude: 0, longitude: 0, radiusMeters: 100);
    final String id = g.fences.single.id;

    // 94 m north: inside the 95 m entry radius.
    final List<GeofenceAlert> inAlerts = g.sample(_at(94 / 111320.0, 0));
    expect(inAlerts.length, 1);
    expect(inAlerts.single.isEntry, isTrue);
    expect(g.isInside(id), isTrue);

    // Standing on the boundary: nothing fires.
    expect(g.sample(_at(100 / 111320.0, 0)), isEmpty);
    expect(g.sample(_at(103 / 111320.0, 0)), isEmpty);

    // 106 m: outside the 105 m leave radius.
    final List<GeofenceAlert> outAlerts = g.sample(_at(106 / 111320.0, 0));
    expect(outAlerts.length, 1);
    expect(outAlerts.single.isEntry, isFalse);
    expect(g.isInside(id), isFalse);
    expect(g.alerts.length, 2);
  });

  test('no fix is not "outside": a GPS gap fires nothing', () async {
    final GeofenceController g = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await g.load();
    await g.addFence(
        label: 'Camp', latitude: 0, longitude: 0, radiusMeters: 100);
    expect(g.sample(_at(94 / 111320.0, 0)).length, 1);
    expect(g.sample(_at(500 / 111320.0, 0)).length, 1);
    // The watch is outside now; a sample with no fix must not re-enter.
    expect(g.sample(_at(double.nan, double.nan)), isEmpty);
    expect(g.fences.length, 1);
  });

  test('deleting a fence removes it, its watch and its events', () async {
    final GeofenceController g = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await g.load();
    await g.addFence(
        label: 'Camp', latitude: 0, longitude: 0, radiusMeters: 100);
    final String id = g.fences.single.id;
    g.sample(_at(94 / 111320.0, 0));
    await g.removeFence(id);
    expect(g.fences, isEmpty);
    expect(g.alerts, isEmpty);
    expect(g.isInside(id), isFalse);
  });

  test('fences survive a restart', () async {
    final GeofenceController first = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await first.load();
    await first.addFence(
        label: 'Trailhead', latitude: 51.5, longitude: -0.12, radiusMeters: 500);

    final GeofenceController second = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await second.load();
    expect(second.fences.single.label, 'Trailhead');
    expect(second.fences.single.radiusMeters, 500);
  });

  test('a crossing is announced to the caller, not only recorded', () async {
    // The fence screen was the only reader of `alerts`, which meant a crossing
    // fired exactly when nobody was looking at it. onRaised is what lets the app
    // make a crossing heard.
    final List<List<GeofenceAlert>> heard = <List<GeofenceAlert>>[];
    final GeofenceController g = GeofenceController(
      mc: MeshcoreController(),
      clock: () => t0,
      autoTick: false,
      onRaised: heard.add,
    );
    await g.load();
    await g.addFence(
        label: 'Camp', latitude: 0, longitude: 0, radiusMeters: 100);

    g.sample(_at(94 / 111320.0, 0));
    expect(heard, hasLength(1));
    expect(heard.single.single.isEntry, isTrue);
    // Standing still inside raises nothing further.
    expect(g.sample(_at(95 / 111320.0, 0)), isEmpty);
    expect(heard, hasLength(1));
    // Leaving is a second announcement.
    g.sample(_at(106 / 111320.0, 0));
    expect(heard, hasLength(2));
    expect(heard.last.single.isEntry, isFalse);
  });
  test('a crossing survives a restart, and the log is capped', () async {
    final GeofenceController first = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await first.load();
    await first.addFence(
        label: 'Camp', latitude: 0, longitude: 0, radiusMeters: 100);
    first.sample(_at(94 / 111320.0, 0));
    first.sample(_at(106 / 111320.0, 0));
    // The write is not awaited by sample, so give it the microtask it needs.
    await Future<void>.delayed(Duration.zero);
    expect(first.alerts, hasLength(2));

    // A second controller stands in for the next launch: it reads only from the
    // store, exactly as a cold start does.
    final GeofenceController next = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await next.load();
    expect(next.alerts, hasLength(2),
        reason: 'the log is the point: what happened last night');
    expect(next.alerts.first.isEntry, isTrue);
    expect(next.alerts.last.isEntry, isFalse);
    // Compared as instants, not as representations: the log round-trips through
    // an epoch millisecond, which comes back in the local zone.
    expect(next.alerts.first.at.millisecondsSinceEpoch,
        t0.millisecondsSinceEpoch);
    expect(next.alerts.first.fence.label, 'Camp');
  });

  test('deleting a fence deletes its crossings, on disk as well', () async {
    final GeofenceController g = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await g.load();
    await g.addFence(
        label: 'Camp', latitude: 0, longitude: 0, radiusMeters: 100);
    final String id = g.fences.single.id;
    g.sample(_at(94 / 111320.0, 0));
    await Future<void>.delayed(Duration.zero);
    await g.removeFence(id);
    expect(g.alerts, isEmpty);
    final GeofenceController next = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await next.load();
    expect(next.alerts, isEmpty,
        reason: 'a history that outlives deleting its fence is not consent');
  });


  group('editing a fence', () {
    test('a rename keeps the id, the crossings and the inside state', () async {
      final GeofenceController g = GeofenceController(
          mc: MeshcoreController(), clock: () => t0, autoTick: false);
      await g.load();
      await g.addFence(
          label: 'Camp', latitude: 0, longitude: 0, radiusMeters: 100);
      final String id = g.fences.single.id;
      // Walk in, so there is a crossing and a state to preserve.
      g.sample(_at(94 / 111320.0, 0));
      await Future<void>.delayed(Duration.zero);
      expect(g.isInside(id), isTrue);
      expect(g.alerts, hasLength(1));

      await g.updateFence(id: id, label: 'Base camp');

      expect(g.fences.single.id, id, reason: 'the id is the fence');
      expect(g.fences.single.label, 'Base camp');
      expect(g.fences.single.radiusMeters, 100);
      expect(g.isInside(id), isTrue,
          reason: 'a rename is not a crossing');
      expect(g.alerts, hasLength(1),
          reason: 'the crossing stays filed under the same fence');
    });

    test('a resize keeps the watch, and a shrink reports the leave', () async {
      final GeofenceController g = GeofenceController(
          mc: MeshcoreController(), clock: () => t0, autoTick: false);
      await g.load();
      await g.addFence(
          label: 'Camp', latitude: 0, longitude: 0, radiusMeters: 100);
      final String id = g.fences.single.id;
      g.sample(_at(94 / 111320.0, 0));
      await Future<void>.delayed(Duration.zero);
      expect(g.isInside(id), isTrue);

      // Grow it: still inside, and no second entry.
      await g.updateFence(id: id, radiusMeters: 400);
      expect(g.fences.single.radiusMeters, 400);
      expect(g.sample(_at(94 / 111320.0, 0)), isEmpty);

      // Shrink it below where we stand: the next sample says we left, which is
      // true, and it is the only honest reading of a fence that no longer
      // contains us.
      await g.updateFence(id: id, radiusMeters: 50);
      final List<GeofenceAlert> left = g.sample(_at(94 / 111320.0, 0));
      expect(left, hasLength(1));
      expect(left.single.isEntry, isFalse);
    });

    test('an edit survives a reload', () async {
      final GeofenceController g = GeofenceController(
          mc: MeshcoreController(), clock: () => t0, autoTick: false);
      await g.load();
      await g.addFence(
          label: 'Camp', latitude: 0, longitude: 0, radiusMeters: 100);
      final String id = g.fences.single.id;
      await g.updateFence(id: id, label: 'Base camp', radiusMeters: 600);

      final GeofenceController next = GeofenceController(
          mc: MeshcoreController(), clock: () => t0, autoTick: false);
      await next.load();
      expect(next.fences.single.id, id);
      expect(next.fences.single.label, 'Base camp');
      expect(next.fences.single.radiusMeters, 600);
    });

    test('an empty name is refused rather than blanking the fence', () async {
      final GeofenceController g = GeofenceController(
          mc: MeshcoreController(), clock: () => t0, autoTick: false);
      await g.load();
      await g.addFence(
          label: 'Camp', latitude: 0, longitude: 0, radiusMeters: 100);
      final String id = g.fences.single.id;
      await g.updateFence(id: id, label: '   ');
      expect(g.fences.single.label, 'Camp');
    });

    test('an unknown id changes nothing', () async {
      final GeofenceController g = GeofenceController(
          mc: MeshcoreController(), clock: () => t0, autoTick: false);
      await g.load();
      await g.addFence(
          label: 'Camp', latitude: 0, longitude: 0, radiusMeters: 100);
      await g.updateFence(id: 'nope', label: 'Other');
      expect(g.fences.single.label, 'Camp');
    });
  });


  test('a drawn fence is stored with its shape and its derived centre',
      () async {
    final GeofenceController g = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await g.load();
    const List<FencePoint> corners = <FencePoint>[
      FencePoint(39.0, -105.0),
      FencePoint(39.0, -104.99),
      FencePoint(39.001, -104.99),
    ];
    await g.addPolygonFence(label: 'Yard', polygon: corners);
    expect(g.fences, hasLength(1));
    final StoredGeofence f = g.fences.single;
    expect(f.isPolygon, isTrue);
    expect(f.polygon, corners);
    expect(f.label, 'Yard');
    // The centre is the vertex average and the radius reaches the farthest
    // corner, so the map's label and "show all" work without knowing the shape.
    expect(f.latitude, closeTo(39.000333, 0.0005));
    expect(f.radiusMeters, greaterThan(0));

    // And it survives a reload, which is the point of storing it.
    final GeofenceController next = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await next.load();
    expect(next.fences.single.isPolygon, isTrue);
    expect(next.fences.single.polygon, corners);
  });

  test('a drawn fence fires on a crossing like a circle does', () async {
    final GeofenceController g = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await g.load();
    await g.addPolygonFence(label: 'Yard', polygon: const <FencePoint>[
      FencePoint(39.0, -105.0),
      FencePoint(39.0, -104.99),
      FencePoint(39.001, -104.99),
      FencePoint(39.001, -105.0),
    ]);
    // Inside the square.
    expect(g.sample(_at(39.0005, -104.995)), hasLength(1));
    expect(g.isInside(g.fences.single.id), isTrue);
    // Standing still is not a second crossing.
    expect(g.sample(_at(39.0005, -104.995)), isEmpty);
    // Well outside it.
    expect(g.sample(_at(39.01, -104.995)), hasLength(1));
    expect(g.isInside(g.fences.single.id), isFalse);
  });

  test('renaming a drawn fence keeps its shape', () async {
    final GeofenceController g = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await g.load();
    const List<FencePoint> corners = <FencePoint>[
      FencePoint(39.0, -105.0),
      FencePoint(39.0, -104.99),
      FencePoint(39.001, -104.99),
    ];
    await g.addPolygonFence(label: 'Yard', polygon: corners);
    final String id = g.fences.single.id;
    await g.updateFence(id: id, label: 'Back yard');
    expect(g.fences.single.label, 'Back yard');
    expect(g.fences.single.id, id);
    expect(g.fences.single.polygon, corners,
        reason: 'a rename must not turn a drawn fence into a circle');
  });

  test('a polygon with fewer than three corners is not added', () async {
    final GeofenceController g = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await g.load();
    await g.addPolygonFence(label: 'Line', polygon: const <FencePoint>[
      FencePoint(39.0, -105.0),
      FencePoint(39.0, -104.99),
    ]);
    expect(g.fences, isEmpty);
  });

  group('reshape', _reshapeTests);
}

/// Reshaping a drawn fence.
///
/// A fence could be renamed and re-radiused and nothing else: the corners were
/// what the reader drew and the app offered no way to move one, so a fence
/// drawn slightly wrong had to be deleted and drawn again, losing its crossing
/// log with it. `updatePolygon` replaces the corners and keeps the identity.
void _reshapeTests() {
  List<FencePoint> square(double dx) => <FencePoint>[
        FencePoint(0.001 + dx, 0.001),
        FencePoint(0.001 + dx, 0.003),
        FencePoint(0.003 + dx, 0.003),
        FencePoint(0.003 + dx, 0.001),
      ];

  test('a reshape keeps the id, the name and the log, and moves the corners',
      () async {
    final GeofenceController g = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    addTearDown(g.dispose);
    await g.load();
    await g.addPolygonFence(label: 'Yard', polygon: square(0));
    final String id = g.fences.single.id;

    await g.updatePolygon(id: id, polygon: square(0.01));

    final StoredGeofence after = g.fences.single;
    expect(after.id, id, reason: 'a reshape is not a new fence');
    expect(after.label, 'Yard');
    expect(after.polygon!.first.lat, closeTo(0.011, 1e-9),
        reason: 'the corners are the ones that were dragged');
    expect(g.fences, hasLength(1));
  });

  test('the reshape survives a relaunch', () async {
    final GeofenceController g = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    await g.load();
    await g.addPolygonFence(label: 'Yard', polygon: square(0));
    final String id = g.fences.single.id;
    await g.updatePolygon(id: id, polygon: square(0.01));
    g.dispose();

    final GeofenceController next = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    addTearDown(next.dispose);
    await next.load();
    expect(next.fences.single.polygon!.first.lat, closeTo(0.011, 1e-9));
  });

  test('two corners are refused, because they are not a fence', () async {
    final GeofenceController g = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    addTearDown(g.dispose);
    await g.load();
    await g.addPolygonFence(label: 'Yard', polygon: square(0));
    final String id = g.fences.single.id;

    await g.updatePolygon(id: id, polygon: square(0).take(2).toList());

    expect(g.fences.single.polygon, hasLength(4),
        reason: 'a refused reshape leaves the fence as it was');
  });

  test('the crossing log is not the shape, so it stays', () async {
    final GeofenceController g = GeofenceController(
        mc: MeshcoreController(), clock: () => t0, autoTick: false);
    addTearDown(g.dispose);
    await g.load();
    await g.addPolygonFence(label: 'Yard', polygon: square(0));
    final String id = g.fences.single.id;
    g.sample(OwnLocation(
      latitude: 0.002,
      longitude: 0.002,
      source: OwnLocationSource.phoneFix,
    ));
    expect(g.alerts, hasLength(1), reason: 'standing inside is an entry');

    await g.updatePolygon(id: id, polygon: square(0.01));

    expect(g.alerts, hasLength(1),
        reason: 'moving a boundary is not a crossing');
  });
}
