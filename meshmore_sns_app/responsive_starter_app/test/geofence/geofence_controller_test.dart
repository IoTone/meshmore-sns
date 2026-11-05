// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/geofence/geofence_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/own_location.dart';

final DateTime t0 = DateTime.utc(2026, 11, 5, 12);

OwnLocation _at(double lat, double lon) => OwnLocation(
      latitude: lat,
      longitude: lon,
      source: OwnLocationSource.phoneFix,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

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
}
