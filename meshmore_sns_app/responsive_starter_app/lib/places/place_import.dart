// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

import 'place_codec.dart';

/// Why a shared place could not be read back.
enum PlaceImportRefusal {
  /// Nothing but whitespace.
  empty,

  /// No coordinate pair and no map link anywhere in the text.
  noCoordinates,

  /// A coordinate pair that is not on the earth: latitude past 90 or
  /// longitude past 180. A shared place is untrusted input, and a pin at
  /// 91 degrees north is a typo or a different coordinate system, not a place.
  outOfRange,
}

/// A place read out of text somebody shared.
///
/// [label] may be empty: a bare coordinate pair is a place with no name, and
/// the create sheet asks for one rather than inventing it.
final class ImportedPlace {
  const ImportedPlace({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.labelTruncated,
  });

  final String label;
  final double latitude;
  final double longitude;

  /// True when the shared label was longer than a report can carry and was cut
  /// to [placeMaxLabelRunes]. The sheet says so, because a silently shortened
  /// name is a name the reader did not write.
  final bool labelTruncated;
}

/// The outcome of reading a shared place.
final class PlaceImportResult {
  const PlaceImportResult.place(ImportedPlace this.place) : refusal = null;

  const PlaceImportResult.refused(PlaceImportRefusal this.refusal)
      : place = null;

  final ImportedPlace? place;
  final PlaceImportRefusal? refusal;

  bool get ok => place != null;
}

/// The reverse of [placeShareText]: reads a place back out of text.
///
/// Sharing a place writes three lines — the label, `lat, lon`, and an
/// OpenStreetMap link — and nothing read them back, so a place that arrived in
/// a message, a note or a chat with somebody else had to be retyped by hand.
///
/// The parser is deliberately forgiving about *where* the coordinates are and
/// strict about *what* they are:
///
///  * the OSM link wins, because it is the form another app is most likely to
///    have kept intact, and its `mlat`/`mlon` parameters are read by name so
///    extra parameters (a tracking tag, a layer, a marker) do not confuse it;
///  * the `#map=17/lat/lon` fragment is the fallback for a link whose query was
///    stripped;
///  * a bare `lat, lon` pair on any line is the last resort, which is what a
///    person pastes out of a map app;
///  * the label is the first line that is neither a coordinate pair nor a URL.
///
/// Nothing is guessed. A text with no coordinates is refused rather than
/// placed at zero degrees, and a pair outside the earth is refused rather than
/// clamped, because a clamped pin is a wrong place that looks right.
PlaceImportResult parsePlaceShareText(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const PlaceImportResult.refused(PlaceImportRefusal.empty);
  }
  final List<String> lines = <String>[
    for (final String line in trimmed.split(RegExp(r'\r?\n')))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  double? lat;
  double? lon;
  int? coordinateLine;

  // 1. The link, by parameter name.
  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i];
    if (!_looksLikeLink(line)) continue;
    final RegExpMatch? mlat = RegExp(r'[?&]mlat=(-?\d+(?:\.\d+)?)').firstMatch(line);
    final RegExpMatch? mlon = RegExp(r'[?&]mlon=(-?\d+(?:\.\d+)?)').firstMatch(line);
    if (mlat != null && mlon != null) {
      lat = double.tryParse(mlat.group(1)!);
      lon = double.tryParse(mlon.group(1)!);
      coordinateLine = i;
      break;
    }
    // 2. The fragment, for a link whose query was stripped.
    final RegExpMatch? fragment =
        RegExp(r'#map=[\d.]*/(-?\d+(?:\.\d+)?)/(-?\d+(?:\.\d+)?)').firstMatch(line);
    if (fragment != null) {
      lat = double.tryParse(fragment.group(1)!);
      lon = double.tryParse(fragment.group(2)!);
      coordinateLine = i;
      break;
    }
  }

  // 3. A bare pair on any line.
  if (lat == null || lon == null) {
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      if (_looksLikeLink(line)) continue;
      final RegExpMatch? pair =
          RegExp(r'^(-?\d{1,3}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)$')
              .firstMatch(line);
      if (pair == null) continue;
      lat = double.tryParse(pair.group(1)!);
      lon = double.tryParse(pair.group(2)!);
      coordinateLine = i;
      break;
    }
  }

  if (lat == null || lon == null) {
    return const PlaceImportResult.refused(PlaceImportRefusal.noCoordinates);
  }
  if (lat.isNaN || lon.isNaN || lat.abs() > 90 || lon.abs() > 180) {
    return const PlaceImportResult.refused(PlaceImportRefusal.outOfRange);
  }

  // 4. The label: the first line that is neither the coordinates nor a link.
  String label = '';
  for (int i = 0; i < lines.length; i++) {
    if (i == coordinateLine) continue;
    final String line = lines[i];
    if (_looksLikeLink(line)) continue;
    if (RegExp(r'^-?\d{1,3}(?:\.\d+)?\s*,\s*-?\d{1,3}(?:\.\d+)?$')
        .hasMatch(line)) {
      continue;
    }
    label = line;
    break;
  }

  final List<int> runes = label.runes.toList();
  final bool truncated = runes.length > placeMaxLabelRunes;
  if (truncated) {
    label = String.fromCharCodes(runes.take(placeMaxLabelRunes));
  }

  return PlaceImportResult.place(ImportedPlace(
    label: label,
    latitude: lat,
    longitude: lon,
    labelTruncated: truncated,
  ));
}

bool _looksLikeLink(String line) =>
    line.startsWith('http://') ||
    line.startsWith('https://') ||
    line.startsWith('geo:') ||
    line.startsWith('www.');
