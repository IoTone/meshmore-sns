// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_store.dart';

/// B7/B11 — a corrupt document is kept as evidence, and a clock that moves
/// backwards cannot resurrect a place that already expired.
void main() {
  const String key = 'mm.places.v1';
  const String badKey = 'mm.places.v1.bad';
  const String markKey = 'mm.places.highWater';

  late Directory dir;

  // Places are sealed now: a persistence test needs the store's own seams
  // rather than a preferences mock, and it has to wait for the queued write
  // before removing the directory it wrote into.
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = Directory.systemTemp.createTempSync('mm_places_clock');
    PlaceStore.cipherOverride = MemoryRecordCipher.random();
    PlaceStore.directoryOverride = dir;
  });

  tearDown(() {
    PlaceStore.cipherOverride = null;
    PlaceStore.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a corrupt document is set aside instead of erased', () async {
    const String raw = '{"v":1,"rows":[{"id":"abcd1234",';
    SharedPreferences.setMockInitialValues(<String, Object>{key: raw});

    final PlaceStore store = PlaceStore(clock: () => DateTime(2026, 11, 5));
    addTearDown(store.dispose);
    await store.load();

    expect(store.all, isEmpty);
    // Kept inside the sealed store, not in preferences. The preferences copy
    // was the *decrypted* document — every saved place with its coordinates, in
    // a file the terms text says is encrypted — and nothing ever read it or
    // removed it.
    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(p.getString(badKey), isNull,
        reason: 'a plaintext copy of every place must not be written');
    final Uint8List? kept =
        await PlaceStore.sealedStoreForTest().read('places.bad');
    expect(kept, isNotNull,
        reason: 'the unparsable bytes are the only copy a person could recover');
    expect(utf8.decode(kept!), raw);
  });

  test('a clock that jumps back does not un-expire a place', () async {
    final DateTime t0 = DateTime(2026, 11, 5, 12);
    DateTime clock = t0;
    final PlaceStore store = PlaceStore(clock: () => clock);
    addTearDown(store.dispose);

    await store.load();
    store.upsert(Place(
      id: 'abcd1234',
      reporterName: 'Ana',
      type: PlaceType.water,
      typeToken: PlaceType.water.token,
      label: 'Water at the ford',
      latE6: 51500741,
      lonE6: -124596,
      decimals: 6,
      provenance: PlaceProvenance.received,
      ttl: PlaceTtl.h1,
      sentAt: t0,
      expiresAt: t0.add(PlaceTtl.h1.life),
      lastSeen: t0,
    ));
    await store.settled;

    // Two hours later the place is no longer live, and the store has now seen
    // that time (its row stays as the ledger record it is meant to be).
    clock = t0.add(const Duration(hours: 2));
    await store.load();
    expect(store.live(), isEmpty);
    expect(store.all, hasLength(1));

    // The phone's clock is then set back to the hour the place was made in.
    // Expiry is final: the stored high-water mark keeps it expired.
    clock = t0;
    final PlaceStore reopened = PlaceStore(clock: () => clock);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.live(), isEmpty);

    await reopened.flush();
    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(p.getInt(markKey), isNotNull,
        reason: 'the mark is what makes expiry monotonic across launches');
  });
}
