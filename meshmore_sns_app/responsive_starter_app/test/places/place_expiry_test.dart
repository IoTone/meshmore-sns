// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A place leaves the map on its own clock.
///
/// The layer, the count on the map's pin button and the list all read "live"
/// against `now`, and nothing was watching that clock: a pin whose hour had run
/// out stayed on screen, and the button went on counting it, until some
/// unrelated write happened to notify. The badge promised a third place while
/// the list showed two, and the missing one was simply expired.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the count follows the clock, not the last write', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // The real clock, because the mechanism under test is a timer: a store
    // armed for the moment a row ends has to fire then, and a frozen clock
    // would only prove the arithmetic.
    final DateTime wall = DateTime.now();
    final PlaceStore store = PlaceStore();
    store.upsert(Place(
      id: 'aaaaaaaa',
      type: PlaceType.look,
      typeToken: 'look',
      label: 'Short lived',
      latE6: 39000000,
      lonE6: -105000000,
      decimals: 5,
      reporterName: 'Tester',
      provenance: PlaceProvenance.received,
      ttl: PlaceTtl.h1,
      sentAt: wall,
      expiresAt: wall.add(const Duration(milliseconds: 300)),
      lastSeen: wall,
    ));
    expect(store.live().length, 1);

    int notified = 0;
    store.addListener(() => notified++);

    // The timer the store armed for the expiry is what tells the screen, and
    // the row is still kept afterwards: the history keeps it.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(notified, greaterThan(0),
        reason: 'the map has to hear that a pin went away');
    expect(store.live(), isEmpty);
    expect(store.all.length, 1, reason: 'the history keeps the row');
    store.dispose();
  });
}
