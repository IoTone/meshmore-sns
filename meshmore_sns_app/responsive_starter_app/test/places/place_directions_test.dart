// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_directions.dart';

final class _Probe implements DirectionsProbe {
  _Probe(this.supported);

  final Set<String> supported;
  final List<Uri> opened = <Uri>[];

  @override
  Future<bool> canOpen(Uri uri) async =>
      supported.contains(uri.scheme) || supported.contains(uri.host);

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

Place _place() => Place(
      id: 'abcd1234',
      reporterName: 'Ana',
      type: PlaceType.water,
      typeToken: 'water',
      label: 'Water at the ford',
      latE6: 51500741,
      lonE6: -124596,
      decimals: 6,
      provenance: PlaceProvenance.received,
      ttl: PlaceTtl.d2,
      sentAt: DateTime(2026, 11, 5, 12),
      expiresAt: DateTime(2026, 11, 7, 12),
      lastSeen: DateTime(2026, 11, 5, 12),
    );

void main() {
  test('the ladder tries the generic intent first', () async {
    final _Probe probe = _Probe(<String>{'geo', 'osmand', 'https'});
    final DirectionsTarget? target =
        await PlaceDirections.of(_place()).firstAvailable(probe);
    expect(target?.labelKey, DirectionsTargetName.genericGeo);
    expect(target!.uri.toString(),
        'geo:51.500741,-0.124596?q=51.500741,-0.124596(Water%20at%20the%20ford)');
  });

  test('without a geo handler the order is OsmAnd, Organic, Google, Apple',
      () async {
    expect(
        (await PlaceDirections.of(_place())
                .firstAvailable(_Probe(<String>{'osmand', 'https'})))!
            .labelKey,
        DirectionsTargetName.osmand);
    final _Probe organic = _Probe(<String>{'om'});
    expect(
        (await PlaceDirections.of(_place()).firstAvailable(organic))!.labelKey,
        DirectionsTargetName.organic);
    final _Probe google = _Probe(<String>{'www.google.com'});
    expect((await PlaceDirections.of(_place()).firstAvailable(google))!.labelKey,
        DirectionsTargetName.google);
    final _Probe apple = _Probe(<String>{'maps.apple.com'});
    expect((await PlaceDirections.of(_place()).firstAvailable(apple))!.labelKey,
        DirectionsTargetName.apple);
  });

  test('a target that opens is the outcome', () async {
    final _Probe probe = _Probe(<String>{'osmand'});
    final DirectionsOutcome outcome =
        await PlaceDirections.of(_place()).open(probe);
    expect(outcome.copied, isFalse);
    expect(outcome.target, DirectionsTargetName.osmand);
    expect(probe.opened.single.scheme, 'osmand');
  });

  test('with nothing installed the coordinates are copied instead of failing',
      () async {
    String? copied;
    final DirectionsOutcome outcome = await PlaceDirections.of(_place()).open(
      _Probe(<String>{}),
      copy: (String text) async => copied = text,
    );
    expect(outcome.copied, isTrue);
    expect(outcome.target, isNull);
    expect(copied, '51.500741,-0.124596');
  });
}
