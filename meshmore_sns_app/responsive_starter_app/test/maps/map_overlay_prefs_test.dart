// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/maps/map_overlay_prefs.dart';

/// The map's display choices are preferences, and a preference that does not
/// survive the process is a bug that reads as forgetfulness: a reader who turned
/// the hexagon field on found it off again on the next launch.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('nothing stored means the documented defaults', () async {
    final MapOverlayPrefs p = await MapOverlayPrefsStore.load();
    expect(p, MapOverlayPrefs.defaults);
    expect(p.density, isFalse,
        reason: 'the density field is a reading to ask for, not one to dismiss');
  });

  test('a choice survives the process', () async {
    await MapOverlayPrefsStore.save(
        const MapOverlayPrefs(density: true));
    // A second load stands in for the next launch: it reads only the store.
    final MapOverlayPrefs next = await MapOverlayPrefsStore.load();
    expect(next.density, isTrue);
  });

  test('turning it back off is stored, not just forgotten', () async {
    await MapOverlayPrefsStore.save(const MapOverlayPrefs(density: true));
    await MapOverlayPrefsStore.save(const MapOverlayPrefs(density: false));
    expect((await MapOverlayPrefsStore.load()).density, isFalse);
  });

  test('copyWith changes one field and keeps the rest', () {
    const MapOverlayPrefs p = MapOverlayPrefs(density: true);
    expect(p.copyWith(density: false), const MapOverlayPrefs());
    // The point of copyWith rather than a constructor call: a second overlay
    // added later must not be reset by a write to this one.
    expect(p.copyWith(), p);
  });

  test('a record from a wider build is read for what it holds', () {
    // A newer build wrote a field this one has never heard of. It must not make
    // the whole record unreadable, which is the reason the format is a map.
    final MapOverlayPrefs p = MapOverlayPrefs.fromJson(<String, Object?>{
      'density': true,
      'somethingLater': 'yes',
    });
    expect(p.density, isTrue);
  });

  test('a malformed record falls back to the defaults', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mm.mapOverlays.v1': 'not json',
    });
    expect(await MapOverlayPrefsStore.load(), MapOverlayPrefs.defaults);
  });

  test('a wrong-typed field falls back to that field\'s default', () {
    final MapOverlayPrefs p = MapOverlayPrefs.fromJson(<String, Object?>{
      'density': 'true',
    });
    expect(p.density, isFalse, reason: 'a string is not an answer');
  });

  test('what is written is a map, so it can grow', () async {
    await MapOverlayPrefsStore.save(
        const MapOverlayPrefs(density: true));
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Object? decoded = jsonDecode(prefs.getString('mm.mapOverlays.v1')!);
    expect(decoded, isA<Map<String, Object?>>());
    expect((decoded! as Map<String, Object?>)['density'], isTrue);
  });

  test('clear puts the next launch back to defaults', () async {
    await MapOverlayPrefsStore.save(const MapOverlayPrefs(density: true));
    await MapOverlayPrefsStore.clear();
    expect(await MapOverlayPrefsStore.load(), MapOverlayPrefs.defaults);
  });
}
