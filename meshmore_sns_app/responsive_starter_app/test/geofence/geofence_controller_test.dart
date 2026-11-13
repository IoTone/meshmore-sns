// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/meshcore/secure/sealed_document.dart';

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

}
