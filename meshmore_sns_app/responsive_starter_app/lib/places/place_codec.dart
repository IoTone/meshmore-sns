// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
/// The place report as one line of channel text
/// (`meshmore-places-spec.md` §3).
///
/// ```
/// [PLACE]<lat>,<lon> <label> [<type>] [TTL:<duration>]
/// ```
///
/// Anchored, right to left: the TTL is last and exactly once, the type token
/// is immediately before it (or last when there is no TTL), the label is
/// everything between the coordinate pair and the type token, and a bracketed
/// word anywhere else is part of the label — the rule that keeps "the old
/// [ford]" intact.
///
/// A suffix is safe only because the tag is new: no other client parses
/// `[PLACE]`, so a trailing `[TTL:6h]` cannot corrupt a label the way it would
/// inside the existing waypoint tag. A message that is not a well-formed place
/// is simply not a place — the renderer shows ordinary text and nothing is
/// lost.
library;

// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';

import 'place.dart';
import 'place_id.dart';



/// Maximum label length, in characters (spec §3).
const int placeMaxLabelRunes = 60;

/// The tag every report starts with.
/// The tag this build writes.
///
/// The version is part of the tag rather than a token after the coordinates,
/// because the tag is the one part of the grammar every client must agree on
/// before it can parse anything, and a reader that does not know `[PLACE1]`
/// falls back to showing the line as ordinary text — which is the safe failure.
/// It was `[PLACE]` for the first two releases and that spelling is still read
/// (see [placeTagsRead]), so a message sent by an older build is not lost.
const String placeTag = '[PLACE1]';

/// The older spelling, still accepted. One tag cost one byte in a 160-byte
/// text and saved a compatibility break.
const String legacyPlaceTag = '[PLACE]';

/// Every tag this build can read, longest first so `[PLACE1]` is not mistaken
/// for `[PLACE]` followed by a stray `1`.
const List<String> placeTagsRead = <String>[placeTag, legacyPlaceTag];

/// Why a message is not a usable place report.
enum PlaceParseFailure {
  /// The text does not begin with the tag, or spans more than one line.
  notAPlace,

  /// The coordinate pair is missing, unseparated, has no decimal point, has
  /// more than six places, or leaves the ±90 / ±180 range.
  badCoordinates,

  /// A coordinate pair with no words after it is a location, not a place.
  emptyLabel,

  /// The label is longer than [placeMaxLabelRunes] characters.
  labelTooLong,

  /// A `[TTL:…]` token that is not one of the ten stops. The message is then
  /// ordinary text: guessing a life would put a pin on the map that outlives
  /// what its sender typed.
  unknownDuration,

  /// A `[TTL:…]` token that is not the last token.
  misplacedTtl,

  /// Two TTL tokens, or two type tokens in the type position, so the message
  /// says two different things about one place.
  duplicateToken,

  /// No key and no name means the id cannot be derived.
  missingReporter,
}

/// The result of reading one message: the place, or the reason there is none.
@immutable
final class PlaceParseOutcome {
  const PlaceParseOutcome.place(Place this.place) : failure = null;

  const PlaceParseOutcome.rejected(PlaceParseFailure this.failure)
      : place = null;

  final Place? place;
  final PlaceParseFailure? failure;

  bool get isPlace => place != null;
}

/// Reads `[PLACE]…` out of one message.
///
/// [receivedAt] is the clock every row needs and the text does not carry: the
/// text form has no timestamp field (see the report note in the wave record),
/// so `sentAt` is the receive time and `sentAtFromSender` is false. That also
/// means the spec's clock clamp cannot fire here — a received time is never in
/// the future or a month stale.
///
/// [reporterName] and [reporterKey] come from the surrounding message, not from
/// the place text: channel text carries a display name, a direct message
/// carries the packet's key.
PlaceParseOutcome parsePlace(
  String text, {
  required DateTime receivedAt,
  String reporterName = '',
  List<int>? reporterKey,
  PlaceProvenance provenance = PlaceProvenance.received,
}) {
  final String trimmed = text.trim();
  final String? tag = placeTagsRead
      .where((String t) => trimmed.startsWith(t))
      .firstOrNull;
  if (tag == null) {
    return const PlaceParseOutcome.rejected(PlaceParseFailure.notAPlace);
  }
  if (trimmed.contains('\n')) {
    return const PlaceParseOutcome.rejected(PlaceParseFailure.notAPlace);
  }
  if ((reporterKey == null || reporterKey.isEmpty) && reporterName.isEmpty) {
    return const PlaceParseOutcome.rejected(
        PlaceParseFailure.missingReporter);
  }

  String body = trimmed.substring(tag.length).trimLeft();

  // 1. TTL: last token, exactly once.
  PlaceTtl? ttl;
  final int ttlAt = body.indexOf('[TTL:');
  if (ttlAt >= 0) {
    if (!body.endsWith(']')) {
      return const PlaceParseOutcome.rejected(PlaceParseFailure.misplacedTtl);
    }
    final String token = body.substring(ttlAt + 5, body.length - 1);
    if (token.contains('[') || token.contains(']')) {
      return const PlaceParseOutcome.rejected(PlaceParseFailure.misplacedTtl);
    }
    ttl = PlaceTtl.byToken(token);
    if (ttl == null) {
      return const PlaceParseOutcome.rejected(
          PlaceParseFailure.unknownDuration);
    }
    if (body.substring(0, ttlAt).contains('[TTL:')) {
      return const PlaceParseOutcome.rejected(PlaceParseFailure.duplicateToken);
    }
    body = body.substring(0, ttlAt).trimRight();
  }

  // 2. Type: a bracketed word in the last position. It is consumed as the type
  // even when it is not in the set, because the position is what makes it a
  // type; the unknown word stays in the row for the detail sheet.
  String? typeToken;
  final RegExp bracketed = RegExp(r'\[([^\[\]\s]+)\]$');
  Match? bracket = bracketed.firstMatch(body);
  if (bracket != null) {
    typeToken = bracket.group(1)!;
    body = body.substring(0, bracket.start).trimRight();
    bracket = bracketed.firstMatch(body);
    if (bracket != null && PlaceType.isKnownToken(bracket.group(1)!)) {
      return const PlaceParseOutcome.rejected(PlaceParseFailure.duplicateToken);
    }
  }

  // 3. Coordinates: decimal point mandatory, comma between, no spaces, at most
  // six places (truncated, never rounded).
  final RegExp pair =
      RegExp(r'^(-?\d{1,3}\.\d{1,6}),(-?\d{1,3}\.\d{1,6})(?=\s|$)');
  final Match? coords = pair.firstMatch(body);
  if (coords == null) {
    return const PlaceParseOutcome.rejected(PlaceParseFailure.badCoordinates);
  }
  final String latText = coords.group(1)!;
  final String lonText = coords.group(2)!;
  final int latE6 = _toE6(latText);
  final int lonE6 = _toE6(lonText);
  if (latE6 < -90000000 || latE6 > 90000000) {
    return const PlaceParseOutcome.rejected(PlaceParseFailure.badCoordinates);
  }
  if (lonE6 < -180000000 || lonE6 > 180000000) {
    return const PlaceParseOutcome.rejected(PlaceParseFailure.badCoordinates);
  }

  // 4. Label: what is left, trimmed.
  final String label = body.substring(coords.end).trim();
  if (label.isEmpty) {
    return const PlaceParseOutcome.rejected(PlaceParseFailure.emptyLabel);
  }
  if (label.runes.length > placeMaxLabelRunes) {
    return const PlaceParseOutcome.rejected(PlaceParseFailure.labelTooLong);
  }

  final String effectiveToken = typeToken ?? PlaceType.other.token;
  final PlaceType type = typeToken == null
      ? PlaceType.other
      : PlaceType.byToken(typeToken);
  final PlaceTtl life = ttl ?? type.defaultTtl;
  // The pair's precision is the coarser of the two coordinates: a report with
  // six places of latitude and two of longitude is a two-place point.
  final int latDecimals = _decimals(latText);
  final int lonDecimals = _decimals(lonText);
  final int decimals =
      latDecimals < lonDecimals ? latDecimals : lonDecimals;

  final String id = placeIdFor(
    reporterKey: reporterKey,
    reporterName: reporterName,
    latE6: latE6,
    lonE6: lonE6,
    typeToken: effectiveToken,
  );

  return PlaceParseOutcome.place(Place(
    id: id,
    reporterKey: reporterKey == null ? null : Uint8List.fromList(reporterKey),
    reporterName: reporterName,
    type: type,
    typeToken: effectiveToken,
    label: label,
    latE6: latE6,
    lonE6: lonE6,
    decimals: decimals,
    provenance: provenance,
    ttl: life,
    sentAt: receivedAt,
    sentAtFromSender: false,
    expiresAt: receivedAt.add(life.life),
    lastSeen: receivedAt,
  ));
}

/// Writes the canonical line for [place].
///
/// The type and the TTL are always emitted: a sender always knows both, and an
/// omitted token is only something a receiver has to tolerate. Structural
/// impossibilities throw instead of being silently rewritten — a label that
/// carries a TTL token would make the line read as two different places, so the
/// composer validates the label first with [placeLabelProblem].
String encodePlace(Place place) {
  final String label = place.label.trim();
  final PlaceLabelProblem? problem = placeLabelProblem(label);
  if (problem != null) {
    throw ArgumentError.value(label, 'label', problem.message);
  }
  final String token =
      place.typeToken.isEmpty ? place.type.token : place.typeToken;
  final String coords =
      '${_formatE6(place.latE6, place.decimals)},${_formatE6(place.lonE6, place.decimals)}';
  return '$placeTag$coords $label [$token] [TTL:${place.ttl.token}]';
}

/// What is wrong with a label a user typed, or null when it can travel.
enum PlaceLabelProblem {
  empty,
  tooLong,
  carriesTtl;

  String get message => switch (this) {
        PlaceLabelProblem.empty => 'a place needs a few words',
        PlaceLabelProblem.tooLong =>
          'a label is at most $placeMaxLabelRunes characters',
        PlaceLabelProblem.carriesTtl =>
          'a label cannot contain a [TTL:] token',
      };
}

/// Validates a label before it is encoded or sent (spec §3).
PlaceLabelProblem? placeLabelProblem(String label) {
  final String trimmed = label.trim();
  if (trimmed.isEmpty) return PlaceLabelProblem.empty;
  if (trimmed.runes.length > placeMaxLabelRunes) return PlaceLabelProblem.tooLong;
  if (trimmed.contains('[TTL:')) return PlaceLabelProblem.carriesTtl;
  return null;
}

/// Truncates a decimal coordinate string to six places, as an integer at 1e6.
///
/// Done on the digits rather than through a double so that `51.500740` is
/// exactly `51500740` and never one micro-degree low, which would change the id
/// for a receiver that parses the same text.
int _toE6(String text) {
  final bool negative = text.startsWith('-');
  final String unsigned = negative ? text.substring(1) : text;
  final int dot = unsigned.indexOf('.');
  final String whole = unsigned.substring(0, dot);
  final String fraction = unsigned.substring(dot + 1);
  final int micros =
      int.parse(whole) * 1000000 + int.parse(fraction.padRight(6, '0'));
  return negative ? -micros : micros;
}

int _decimals(String text) => text.length - text.indexOf('.') - 1;

String _formatE6(int e6, int decimals) {
  final bool negative = e6 < 0;
  final int value = e6.abs();
  int divisor = 1;
  for (int i = 0; i < 6 - decimals; i++) {
    divisor *= 10;
  }
  int scale = 1;
  for (int i = 0; i < decimals; i++) {
    scale *= 10;
  }
  final int truncated = value ~/ divisor;
  final int whole = truncated ~/ scale;
  final int fraction = truncated % scale;
  return '${negative ? '-' : ''}$whole.'
      '${fraction.toString().padLeft(decimals, '0')}';
}
