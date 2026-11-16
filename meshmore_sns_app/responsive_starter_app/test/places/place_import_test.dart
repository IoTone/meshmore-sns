// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_codec.dart';
import 'package:meshmore_sns_app/places/place_import.dart';
import 'package:meshmore_sns_app/places/place_ui.dart';

/// Sharing a place writes a label, a coordinate pair and a map link. Nothing
/// read that back, so a place somebody sent had to be retyped by hand. These
/// are the cases the parser has to get right, and the ones it has to refuse.
void main() {
  final DateTime now = DateTime(2026, 11, 5, 12);

  Place place({
    String label = 'Water at the ford',
    int latE6 = 51500741,
    int lonE6 = -124596,
  }) =>
      Place(
        id: 'abcd1234',
        reporterName: 'Ana',
        type: PlaceType.water,
        typeToken: PlaceType.water.token,
        label: label,
        latE6: latE6,
        lonE6: lonE6,
        decimals: 5,
        provenance: PlaceProvenance.pinned,
        ttl: PlaceTtl.h1,
        sentAt: now,
        expiresAt: now.add(PlaceTtl.h1.life),
        lastSeen: now,
      );

  group('a shared place reads back', () {
    test('the text placeShareText writes round trips', () {
      final PlaceImportResult result =
          parsePlaceShareText(placeShareText(place()));
      expect(result.ok, isTrue);
      final ImportedPlace read = result.place!;
      expect(read.label, 'Water at the ford');
      expect(read.latitude, closeTo(51.50074, 1e-9));
      expect(read.longitude, closeTo(-0.12460, 1e-9));
      expect(read.labelTruncated, isFalse);
    });

    test('a link with extra parameters is read by parameter name', () {
      final PlaceImportResult result = parsePlaceShareText(
        'https://www.openstreetmap.org/?utm_source=chat&mlon=-0.1246'
        '&mlat=51.50074&layer=mapnik#map=17/51.50074/-0.1246',
      );
      expect(result.ok, isTrue);
      expect(result.place!.latitude, closeTo(51.50074, 1e-9));
      expect(result.place!.longitude, closeTo(-0.1246, 1e-9));
      // No label line, so the sheet asks for one rather than inventing it.
      expect(result.place!.label, isEmpty);
    });

    test('a link whose query was stripped still reads from the fragment', () {
      final PlaceImportResult result = parsePlaceShareText(
        'https://www.openstreetmap.org/#map=17/51.50074/-0.12460',
      );
      expect(result.ok, isTrue);
      expect(result.place!.latitude, closeTo(51.50074, 1e-9));
      expect(result.place!.longitude, closeTo(-0.12460, 1e-9));
    });

    test('a bare pair on its own line is a place with no name', () {
      final PlaceImportResult result =
          parsePlaceShareText('  51.50074, -0.12460  ');
      expect(result.ok, isTrue);
      expect(result.place!.label, isEmpty);
      expect(result.place!.latitude, closeTo(51.50074, 1e-9));
    });

    test('the label is the first line that is not coordinates or a link', () {
      final PlaceImportResult result = parsePlaceShareText(
        'https://www.openstreetmap.org/?mlat=51.5&mlon=-0.12\n'
        'Ford is out\n'
        '51.5, -0.12',
      );
      expect(result.ok, isTrue);
      expect(result.place!.label, 'Ford is out');
    });

    test('a label longer than a report can carry is cut and flagged', () {
      final String long = 'x' * (placeMaxLabelRunes + 12);
      final PlaceImportResult result =
          parsePlaceShareText('$long\n51.5, -0.12');
      expect(result.ok, isTrue);
      expect(result.place!.label.runes.length, placeMaxLabelRunes);
      expect(result.place!.labelTruncated, isTrue);
    });
  });

  group('a shared place that is not one is refused', () {
    test('empty text', () {
      expect(parsePlaceShareText('   \n  ').refusal, PlaceImportRefusal.empty);
    });

    test('a link with only half a coordinate pair', () {
      expect(
        parsePlaceShareText('https://www.openstreetmap.org/?mlat=51.5')
            .refusal,
        PlaceImportRefusal.noCoordinates,
      );
    });

    test('a truncated link', () {
      expect(
        parsePlaceShareText('https://www.openstreetmap.org/?mlat=51.5&mlon=')
            .refusal,
        PlaceImportRefusal.noCoordinates,
      );
    });

    test('prose with no coordinates', () {
      expect(parsePlaceShareText('meet at the ford').refusal,
          PlaceImportRefusal.noCoordinates);
    });

    test('a pair that is not on the earth is refused, not clamped', () {
      expect(parsePlaceShareText('91.5, -0.12').refusal,
          PlaceImportRefusal.outOfRange);
      expect(parsePlaceShareText('51.5, 181.2').refusal,
          PlaceImportRefusal.outOfRange);
    });
  });
}
