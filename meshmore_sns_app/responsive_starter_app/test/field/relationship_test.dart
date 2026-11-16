// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/field/relationship.dart';

final DateTime t0 = DateTime.utc(2026, 11, 5, 12);

void main() {
  test('the first reading claims no direction, because it has nothing to '
      'compare against', () {
    final RelationshipTracker t = RelationshipTracker();
    final RelationshipReading r = t.update('a', 400, t0);
    expect(r.trend, RelationshipTrend.steady);
    expect(r.hasTrend, isFalse);
    expect(r.previousDistanceMeters, isNull);
  });

  test('a nearer reading is closing, a further one is opening', () {
    final RelationshipTracker t = RelationshipTracker();
    t.update('a', 400, t0);
    final RelationshipReading nearer =
        t.update('a', 300, t0.add(const Duration(seconds: 30)));
    expect(nearer.trend, RelationshipTrend.closing);
    expect(nearer.previousDistanceMeters, 400);
    final RelationshipReading further =
        t.update('a', 500, t0.add(const Duration(minutes: 1)));
    expect(further.trend, RelationshipTrend.opening);
  });

  test('movement inside the dead band is steady, so a wobbling position does '
      'not narrate', () {
    final RelationshipTracker t = RelationshipTracker(deadBandMeters: 10);
    t.update('a', 400, t0);
    expect(t.update('a', 395, t0.add(const Duration(seconds: 30))).trend,
        RelationshipTrend.steady);
    expect(t.update('a', 399, t0.add(const Duration(seconds: 40))).trend,
        RelationshipTrend.steady);
  });

  test('a repeat inside the window is the same observation, not a new one', () {
    final RelationshipTracker t = RelationshipTracker(minInterval: const Duration(seconds: 5));
    final RelationshipReading first = t.update('a', 400, t0);
    final RelationshipReading again =
        t.update('a', 200, t0.add(const Duration(seconds: 2)));
    expect(identical(first, again), isTrue);
    expect(t.readingFor('a')!.distanceMeters, 400);
  });

  test('two nodes keep their own histories', () {
    final RelationshipTracker t = RelationshipTracker();
    t.update('a', 400, t0);
    t.update('b', 50, t0);
    expect(t.update('a', 350, t0.add(const Duration(seconds: 10))).trend,
        RelationshipTrend.closing);
    expect(t.update('b', 80, t0.add(const Duration(seconds: 10))).trend,
        RelationshipTrend.opening);
  });

  test('a non-finite distance never becomes a direction', () {
    final RelationshipTracker t = RelationshipTracker();
    t.update('a', 400, t0);
    expect(t.update('a', double.nan, t0.add(const Duration(seconds: 30))).trend,
        RelationshipTrend.steady);
  });

  test('the haversine helper is the same arithmetic, not a second copy', () {
    final RelationshipTracker t = RelationshipTracker();
    final RelationshipReading r = t.updateBetween(
      'a',
      fromLat: 51.5,
      fromLon: -0.12,
      toLat: 51.5,
      toLon: -0.12,
      at: t0,
    );
    expect(r.distanceMeters, lessThan(1));
  });
}
