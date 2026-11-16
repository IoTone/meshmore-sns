// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_codec.dart';
import 'package:meshmore_sns_app/places/place_id.dart';

final Uint8List _key =
    Uint8List.fromList(List<int>.generate(32, (int i) => i));

String _id({
  List<int>? key,
  String name = 'W1ABC',
  int latE6 = 51500741,
  int lonE6 = -124596,
  String typeToken = 'water',
}) =>
    placeIdFor(
      reporterKey: key,
      reporterName: name,
      latE6: latE6,
      lonE6: lonE6,
      typeToken: typeToken,
    );

void main() {
  test('the id is eight lowercase hex characters', () {
    expect(_id(key: _key), matches(RegExp(r'^[0-9a-f]{8}$')));
  });

  test('the same inputs give the same id across calls (spec test 4)', () {
    expect(_id(key: _key), _id(key: _key));
    expect(_id(key: _key), _id(key: Uint8List.fromList(_key)));
  });

  test('time is not an input, so a renewal keeps the id (spec test 5)', () {
    final DateTime first = DateTime.utc(2026, 11, 5, 12);
    final DateTime later = first.add(const Duration(hours: 6));
    final Place a = parsePlace('[PLACE1]51.500741,-0.124596 Ford [water]',
            receivedAt: first, reporterName: 'W1ABC')
        .place!;
    final Place b = parsePlace('[PLACE1]51.500741,-0.124596 Ford [water]',
            receivedAt: later, reporterName: 'W1ABC')
        .place!;
    expect(b.id, a.id);
    expect(b.lastSeen, isNot(a.lastSeen));
    expect(b.expiresAt, later.add(PlaceType.water.defaultTtl.life));
  });

  test('changing only the type changes the id (spec test 5)', () {
    expect(_id(key: _key, typeToken: 'water'),
        isNot(_id(key: _key, typeToken: 'hazard')));
  });

  test('changing the transmitted precision changes the id (spec test 5)', () {
    final Place exact = parsePlace('[PLACE1]51.500741,-0.124596 Ford [water]',
            receivedAt: DateTime.utc(2026), reporterName: 'W1ABC')
        .place!;
    final Place snapped = exact.copyWith(
      latE6: PlacePrecision.snapped100m.convertE6(51.500741),
      lonE6: PlacePrecision.snapped100m.convertE6(-0.124596),
      decimals: 3,
    );
    expect(placeIdOf(snapped), isNot(exact.id));
  });

  test('a key-bound id differs from the name-derived one at the same point',
      () {
    expect(_id(key: _key), isNot(_id()));
  });

  test('a different reporter name gives a different unkeyed id', () {
    expect(_id(), isNot(_id(name: 'W2XYZ')));
  });

  test('an unkeyed report is marked so by the parsed row', () {
    final Place unkeyed = parsePlace('[PLACE1]51.5,-0.12 Ford [water]',
            receivedAt: DateTime.utc(2026), reporterName: 'W1ABC')
        .place!;
    expect(unkeyed.isUnkeyed, isTrue);
    final Place keyed = parsePlace('[PLACE1]51.5,-0.12 Ford [water]',
            receivedAt: DateTime.utc(2026),
            reporterName: 'W1ABC',
            reporterKey: _key)
        .place!;
    expect(keyed.isUnkeyed, isFalse);
    expect(keyed.id, isNot(unkeyed.id));
  });

  test('no key and no name cannot derive an id', () {
    expect(
        () => placeIdFor(
            reporterKey: null,
            reporterName: '',
            latE6: 0,
            lonE6: 0,
            typeToken: 'other'),
        throwsArgumentError);
  });

  test('a coordinate outside its range is refused by the id derivation', () {
    expect(
        () => placeIdFor(
            reporterKey: _key,
            reporterName: 'W1ABC',
            latE6: 90000001,
            lonE6: 0,
            typeToken: 'other'),
        throwsArgumentError);
    expect(
        () => placeIdFor(
            reporterKey: _key,
            reporterName: 'W1ABC',
            latE6: 0,
            lonE6: -180000001,
            typeToken: 'other'),
        throwsArgumentError);
  });
}
