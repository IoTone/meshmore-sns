// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/places/place.dart';

void main() {
  test('the ladder is the ten stops the wire carries', () {
    expect(PlaceTtl.values.map((PlaceTtl t) => t.token).toList(),
        <String>['15m', '30m', '1h', '3h', '6h', '12h', '24h', '2d', '3d', '7d']);
  });

  test('the floor is 15 m and the ceiling is 7 d', () {
    expect(PlaceTtl.m15.life, const Duration(minutes: 15));
    expect(PlaceTtl.d7.life, const Duration(days: 7));
  });

  test('tokens match exactly, never case-insensitively or with spaces', () {
    expect(PlaceTtl.byToken('6h'), PlaceTtl.h6);
    expect(PlaceTtl.byToken('6H'), isNull);
    expect(PlaceTtl.byToken(' 6h'), isNull);
    expect(PlaceTtl.byToken('6 h'), isNull);
    expect(PlaceTtl.byToken('72h'), isNull);
  });

  test('a step is chosen unchanged', () {
    final PlaceTtlFit fit = PlaceTtl.fit(const Duration(hours: 6));
    expect(fit.accepted, isTrue);
    expect(fit.ttl, PlaceTtl.h6);
    expect(fit.raisedFrom, isNull);
  });

  test('a shorter-than-floor request is raised to 15 m, and says so', () {
    final PlaceTtlFit fit = PlaceTtl.fit(const Duration(seconds: 30));
    expect(fit.accepted, isTrue);
    expect(fit.ttl, PlaceTtl.m15);
    expect(fit.raisedFrom, const Duration(seconds: 30));
  });

  test('a longer-than-ceiling request is refused', () {
    final PlaceTtlFit fit = PlaceTtl.fit(const Duration(days: 8));
    expect(fit.accepted, isFalse);
    expect(fit.ttl, isNull);
    expect(fit.problem, PlaceTtlProblem.aboveMaximum);
  });

  test('a duration that is not a stop is refused, never rounded', () {
    final PlaceTtlFit fit = PlaceTtl.fit(const Duration(hours: 2));
    expect(fit.accepted, isFalse);
    expect(fit.problem, PlaceTtlProblem.notALadderStep);
  });

  test('a zero or negative life is refused', () {
    expect(PlaceTtl.fit(Duration.zero).problem, PlaceTtlProblem.aboveMaximum);
    expect(PlaceTtl.fit(const Duration(minutes: -5)).problem,
        PlaceTtlProblem.aboveMaximum);
  });

  test('every type carries the default life the spec assigns', () {
    expect(PlaceType.hazard.defaultTtl, PlaceTtl.h6);
    expect(PlaceType.water.defaultTtl, PlaceTtl.d2);
    expect(PlaceType.fuel.defaultTtl, PlaceTtl.d2);
    expect(PlaceType.med.defaultTtl, PlaceTtl.h12);
    expect(PlaceType.rally.defaultTtl, PlaceTtl.h12);
    expect(PlaceType.view.defaultTtl, PlaceTtl.d7);
    expect(PlaceType.camp.defaultTtl, PlaceTtl.d3);
    expect(PlaceType.look.defaultTtl, PlaceTtl.h1);
    expect(PlaceType.other.defaultTtl, PlaceTtl.h24);
  });

  test('the type set is closed at nine and an unknown word is other', () {
    expect(PlaceType.values.length, 9);
    expect(PlaceType.byToken('shelter'), PlaceType.other);
    expect(PlaceType.isKnownToken('shelter'), isFalse);
    expect(PlaceType.isKnownToken('med'), isTrue);
    expect(PlaceType.byToken('MED'), PlaceType.other);
  });

  group('precision', () {
    test('exact keeps the fix; snapping rounds before it travels', () {
      expect(PlacePrecision.exact.snap(51.500741), 51.500741);
      expect(PlacePrecision.snapped100m.snap(51.500741), 51.501);
      expect(PlacePrecision.snapped1km.snap(51.500741), 51.5);
      expect(PlacePrecision.snapped100m.snap(-0.124596), -0.125);
    });

    test('the integer that travels is the snapped point at 1e6', () {
      expect(PlacePrecision.snapped100m.convertE6(51.500741), 51501000);
      expect(PlacePrecision.snapped1km.convertE6(-0.124596), -120000);
      expect(PlacePrecision.exact.convertE6(51.500741), 51500741);
    });

    test('a decimal count maps back to its choice, or to none', () {
      expect(PlacePrecision.fromDecimals(6), PlacePrecision.exact);
      expect(PlacePrecision.fromDecimals(3), PlacePrecision.snapped100m);
      expect(PlacePrecision.fromDecimals(2), PlacePrecision.snapped1km);
      expect(PlacePrecision.fromDecimals(4), isNull);
    });
  });
}
