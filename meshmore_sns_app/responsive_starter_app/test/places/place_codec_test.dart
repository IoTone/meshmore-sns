// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_codec.dart';

/// The parse table is the spec's own examples
/// (`meshmore-places-spec.md` §15), because a wire grammar that only round-trips
/// against its own encoder proves nothing about what arrives from another
/// client.
final DateTime _received = DateTime.utc(2026, 11, 5, 12);

Place _parse(String text, {String name = 'W1ABC'}) {
  final PlaceParseOutcome outcome =
      parsePlace(text, receivedAt: _received, reporterName: name);
  expect(outcome.isPlace, isTrue,
      reason: 'expected a place, got ${outcome.failure}');
  return outcome.place!;
}

PlaceParseFailure? _reject(String text) =>
    parsePlace(text, receivedAt: _received, reporterName: 'W1ABC').failure;

void main() {
  group('the spec examples', () {
    test('water at the ford', () {
      final Place p =
          _parse('[PLACE]51.500741,-0.124596 Water at the ford [water] [TTL:2d]');
      expect(p.type, PlaceType.water);
      expect(p.typeToken, 'water');
      expect(p.label, 'Water at the ford');
      expect(p.ttl, PlaceTtl.d2);
      expect(p.latE6, 51500741);
      expect(p.lonE6, -124596);
      expect(p.decimals, 6);
      expect(p.expiresAt, _received.add(const Duration(days: 2)));
      expect(p.sentAtFromSender, isFalse);
      expect(p.lastSeen, _received);
    });

    test('hazard with a comma in the label', () {
      final Place p = _parse(
          '[PLACE]51.500741,-0.124596 Bridge out, do not cross [hazard] [TTL:6h]');
      expect(p.type, PlaceType.hazard);
      expect(p.label, 'Bridge out, do not cross');
      expect(p.ttl, PlaceTtl.h6);
    });

    test('a bracketed word inside the label survives (spec test 2)', () {
      final Place p = _parse(
          '[PLACE]51.5,-0.12 Old [ford] marker [look] [TTL:12h]');
      expect(p.type, PlaceType.look);
      expect(p.typeToken, 'look');
      expect(p.label, 'Old [ford] marker');
      expect(p.ttl, PlaceTtl.h12);
    });

    test('an unknown word in the type position is other, and kept (spec test 3)',
        () {
      final Place p =
          _parse('[PLACE]51.5,-0.12 Meeting [shelter] [TTL:1h]');
      expect(p.type, PlaceType.other);
      expect(p.typeToken, 'shelter');
      expect(p.label, 'Meeting');
    });

    test('a trailing bracketed word is the type even with no TTL', () {
      final Place p = _parse('[PLACE]51.5,-0.12 Old [ford]');
      expect(p.type, PlaceType.other);
      expect(p.typeToken, 'ford');
      expect(p.label, 'Old');
    });

    test('no TTL takes the type default', () {
      final Place p = _parse('[PLACE]51.5,-0.12 Spring [water]');
      expect(p.ttl, PlaceTtl.d2);
      expect(p.expiresAt, _received.add(const Duration(days: 2)));
    });

    test('no type and no TTL is a plain place, 24 h', () {
      final Place p = _parse('[PLACE]51.5,-0.12 A marker');
      expect(p.type, PlaceType.other);
      expect(p.typeToken, 'other');
      expect(p.ttl, PlaceTtl.h24);
    });
  });

  group('every type round-trips, with and without a TTL (spec test 1)', () {
    for (final PlaceType type in PlaceType.values) {
      test('${type.token} with a TTL', () {
        final String text =
            '[PLACE]-33.868800,151.209300 Track closed [${type.token}] [TTL:${type.defaultTtl.token}]';
        final Place p = _parse(text);
        expect(p.type, type);
        expect(p.ttl, type.defaultTtl);
        expect(p.latE6, -33868800);
        expect(p.lonE6, 151209300);
      });

      test('${type.token} without a TTL', () {
        final Place p = _parse('[PLACE]47.606200,-122.332100 Marker [${type.token}]');
        expect(p.type, type);
        expect(p.ttl, type.defaultTtl);
      });
    }
  });

  group('coordinates', () {
    test('a decimal point is mandatory', () {
      expect(_reject('[PLACE]51,-0.12 Marker [look]'), PlaceParseFailure.badCoordinates);
    });

    test('more than six places is refused, never rounded', () {
      expect(_reject('[PLACE]51.5007411,-0.124596 Marker [look]'),
          PlaceParseFailure.badCoordinates);
    });

    test('a missing comma is refused', () {
      expect(_reject('[PLACE]51.5 -0.12 Marker [look]'),
          PlaceParseFailure.badCoordinates);
    });

    test('a latitude past the pole is refused', () {
      expect(_reject('[PLACE]91.0,-0.12 Marker [look]'),
          PlaceParseFailure.badCoordinates);
      expect(_reject('[PLACE]-90.5,-0.12 Marker [look]'),
          PlaceParseFailure.badCoordinates);
    });

    test('a longitude past the antimeridian is refused', () {
      expect(_reject('[PLACE]51.5,181.0 Marker [look]'),
          PlaceParseFailure.badCoordinates);
    });

    test('negative zero keeps its value', () {
      final Place p = _parse('[PLACE]-0.000001,-0.000001 Marker [look]');
      expect(p.latE6, -1);
      expect(p.lonE6, -1);
    });

    test('the pair\'s precision is the coarser coordinate', () {
      final Place p = _parse('[PLACE]51.500741,-0.12 Marker [look]');
      expect(p.latE6, 51500741);
      expect(p.decimals, 2);
      expect(p.precision, PlacePrecision.snapped1km);
    });

    test('an arrived precision of four places is none of our three choices', () {
      final Place p = _parse('[PLACE]51.5007,-0.1245 Marker [look]');
      expect(p.precision, isNull);
      expect(p.accuracyMeters, isNull);
    });
  });

  group('the label', () {
    test('empty is a location, not a place', () {
      expect(_reject('[PLACE]51.5,-0.12 [look]'), PlaceParseFailure.emptyLabel);
      expect(_reject('[PLACE]51.5,-0.12   '), PlaceParseFailure.emptyLabel);
    });

    test('60 characters travel, 61 do not', () {
      final String sixty = List<String>.filled(60, 'x').join();
      expect(_parse('[PLACE]51.5,-0.12 $sixty [look]').label, sixty);
      expect(_reject('[PLACE]51.5,-0.12 ${List<String>.filled(61, 'x').join()} [look]'),
          PlaceParseFailure.labelTooLong);
    });

    test('a multiline message is not a place', () {
      expect(_reject('[PLACE]51.5,-0.12 one\n[PLACE]51.5,-0.12 two'),
          PlaceParseFailure.notAPlace);
    });

    test('the tag must start the message', () {
      expect(_reject('see [PLACE]51.5,-0.12 Marker [look]'),
          PlaceParseFailure.notAPlace);
      expect(_reject('[WAY]51.5,-0.12 Marker'), PlaceParseFailure.notAPlace);
    });
  });

  group('the TTL position', () {
    test('a TTL that is not last is refused', () {
      expect(_reject('[PLACE]51.5,-0.12 [TTL:6h] Marker [look]'),
          PlaceParseFailure.misplacedTtl);
    });

    test('an unknown duration means the message is ordinary text', () {
      expect(_reject('[PLACE]51.5,-0.12 Marker [look] [TTL:5h]'),
          PlaceParseFailure.unknownDuration);
      expect(_reject('[PLACE]51.5,-0.12 Marker [look] [TTL:hours]'),
          PlaceParseFailure.unknownDuration);
      expect(_reject('[PLACE]51.5,-0.12 Marker [look] [TTL:8d]'),
          PlaceParseFailure.unknownDuration);
    });

    test('two TTL tokens say two things and are refused', () {
      final PlaceParseFailure? failure =
          _reject('[PLACE]51.5,-0.12 Marker [look] [TTL:6h] [TTL:1h]');
      expect(failure, isNotNull);
      expect(
          failure,
          anyOf(PlaceParseFailure.misplacedTtl,
              PlaceParseFailure.duplicateToken));
    });

    test('two type tokens in the type position are refused', () {
      expect(_reject('[PLACE]51.5,-0.12 Marker [water] [look]'),
          PlaceParseFailure.duplicateToken);
    });
  });

  test('an unnamed, unkeyed sender cannot derive an id', () {
    expect(
        parsePlace('[PLACE]51.5,-0.12 Marker [look]', receivedAt: _received)
            .failure,
        PlaceParseFailure.missingReporter);
  });

  group('encoding', () {
    test('a place encodes to the canonical line and reads back', () {
      final Place p = _parse(
          '[PLACE]51.500741,-0.124596 Water at the ford [water] [TTL:2d]');
      expect(encodePlace(p),
          '[PLACE]51.500741,-0.124596 Water at the ford [water] [TTL:2d]');
      final Place again = _parse(encodePlace(p));
      expect(again.id, p.id);
      expect(again.label, p.label);
      expect(again.type, p.type);
      expect(again.ttl, p.ttl);
      expect(again.latE6, p.latE6);
      expect(again.lonE6, p.lonE6);
      expect(again.decimals, p.decimals);
    });

    test('every type encodes with its own token and reads back', () {
      for (final PlaceType type in PlaceType.values) {
        final Place p = _parse('[PLACE]12.345678,98.765432 A place [${type.token}]');
        final Place again = _parse(encodePlace(p));
        expect(again.type, type);
        expect(again.id, p.id);
      }
    });

    test('a snapped point transmits the digits it was snapped to', () {
      final Place exact = _parse('[PLACE]51.500741,-0.124596 A place [look]');
      final Place snapped = exact.copyWith(
        latE6: PlacePrecision.snapped100m.convertE6(51.500741),
        lonE6: PlacePrecision.snapped100m.convertE6(-0.124596),
        decimals: 3,
      );
      expect(encodePlace(snapped), '[PLACE]51.501,-0.125 A place [look] [TTL:1h]');
      final Place again = _parse(encodePlace(snapped));
      expect(again.latE6, snapped.latE6);
      expect(again.lonE6, snapped.lonE6);
    });

    test('a label that cannot travel is refused, not rewritten', () {
      final Place p = _parse('[PLACE]51.5,-0.12 Marker [look]');
      expect(() => encodePlace(p.copyWith(label: '   ')), throwsArgumentError);
      expect(() => encodePlace(p.copyWith(label: List<String>.filled(61, 'x').join())),
          throwsArgumentError);
      expect(
          () => encodePlace(p.copyWith(label: 'Marker [TTL:6h]')),
          throwsArgumentError);
    });

    test('the label validator names each problem', () {
      expect(placeLabelProblem('  '), PlaceLabelProblem.empty);
      expect(placeLabelProblem(List<String>.filled(61, 'x').join()), PlaceLabelProblem.tooLong);
      expect(placeLabelProblem('a [TTL:6h] b'), PlaceLabelProblem.carriesTtl);
      expect(placeLabelProblem('A place'), isNull);
    });
  });
}
