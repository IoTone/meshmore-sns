// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_store.dart';

/// B7/B11 — a corrupt document is kept as evidence, and a clock that moves
/// backwards cannot resurrect a place that already expired.
void main() {
  const String key = 'mm.places.v1';
  const String badKey = 'mm.places.v1.bad';
  const String markKey = 'mm.places.highWater';

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a corrupt document is set aside instead of erased', () async {
    const String raw = '{"v":1,"rows":[{"id":"abcd1234",';
    SharedPreferences.setMockInitialValues(<String, Object>{key: raw});

    final PlaceStore store = PlaceStore(clock: () => DateTime(2026, 11, 5));
    addTearDown(store.dispose);
    await store.load();

    expect(store.all, isEmpty);
    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(p.getString(badKey), raw,
        reason: 'the unparsable bytes are the only copy a person could recover');
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

    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(p.getInt(markKey), isNotNull,
        reason: 'the mark is what makes expiry monotonic across launches');
  });
}
