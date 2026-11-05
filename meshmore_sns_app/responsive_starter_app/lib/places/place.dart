// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';

/// The place report vocabulary and its value type (`meshmore-places-spec.md`
/// §3–§8).
///
/// Three things are closed sets on purpose: the nine type tokens, the ten
/// lives, and the form of the coordinates. A place travels as one line of
/// ordinary channel text, so every extra degree of freedom is a byte the
/// label cannot have and one more way for two receivers to disagree about
/// what arrived.

/// The nine type tokens (spec §4). Short forms are a budget decision: `[med]`
/// costs 5 bytes of a 160-byte text, `[medical]` costs 9.
enum PlaceType {
  hazard('hazard', PlaceTtl.h6),
  water('water', PlaceTtl.d2),
  fuel('fuel', PlaceTtl.d2),
  med('med', PlaceTtl.h12),
  rally('rally', PlaceTtl.h12),
  view('view', PlaceTtl.d7),
  camp('camp', PlaceTtl.d3),
  look('look', PlaceTtl.h1),
  other('other', PlaceTtl.h24);

  const PlaceType(this.token, this.defaultTtl);

  /// The wire spelling, lowercase ASCII, no spaces.
  final String token;

  /// The life a receiver applies when the sender gave no TTL, and the life
  /// the composer offers first. A life that arrived is never changed.
  final PlaceTtl defaultTtl;

  /// The token's type, or [other] when it is not in the set. The caller keeps
  /// the unknown token in the row so the detail sheet can show it (spec §3).
  static PlaceType byToken(String token) {
    for (final PlaceType t in PlaceType.values) {
      if (t.token == token) return t;
    }
    return PlaceType.other;
  }

  /// True when the token is one of the nine, so callers can tell "the sender
  /// meant `other`" from "the sender used a word we cannot draw".
  static bool isKnownToken(String token) =>
      PlaceType.values.any((PlaceType t) => t.token == token);
}

/// The ten lives a place may carry (spec §3, §7), matched by exact string.
///
/// A duration grammar would cost characters in a 160-byte text and give two
/// receivers something to disagree about. The ladder is also the clamp: the
/// floor is 15 m and the ceiling is 7 d, so "expires within" filters and the
/// composer's picker share one set of stops.
enum PlaceTtl {
  m15('15m', Duration(minutes: 15)),
  m30('30m', Duration(minutes: 30)),
  h1('1h', Duration(hours: 1)),
  h3('3h', Duration(hours: 3)),
  h6('6h', Duration(hours: 6)),
  h12('12h', Duration(hours: 12)),
  h24('24h', Duration(hours: 24)),
  d2('2d', Duration(days: 2)),
  d3('3d', Duration(days: 3)),
  d7('7d', Duration(days: 7));

  const PlaceTtl(this.token, this.life);

  /// The wire spelling, exactly as it travels.
  final String token;

  /// What the token means, applied to the report's own timestamp.
  final Duration life;

  /// Exact match only: an unknown duration means the message is not a place.
  static PlaceTtl? byToken(String token) {
    for (final PlaceTtl t in PlaceTtl.values) {
      if (t.token == token) return t;
    }
    return null;
  }

  /// Fits a requested life onto the ladder (spec §7).
  ///
  /// A request shorter than the floor is **raised** to 15 m, which the spec
  /// allows explicitly. A request above the ceiling, or one that is not a
  /// ladder step, is **refused**: the wire cannot express it, and silently
  /// sending a different life than the one chosen is worse than saying no.
  static PlaceTtlFit fit(Duration requested) {
    if (requested > d7.life) {
      return const PlaceTtlFit.refused(PlaceTtlProblem.aboveMaximum);
    }
    if (requested <= Duration.zero) {
      return const PlaceTtlFit.refused(PlaceTtlProblem.aboveMaximum);
    }
    if (requested < m15.life) {
      return PlaceTtlFit.raised(m15, requested);
    }
    for (final PlaceTtl t in PlaceTtl.values) {
      if (t.life == requested) return PlaceTtlFit.chosen(t);
    }
    return const PlaceTtlFit.refused(PlaceTtlProblem.notALadderStep);
  }
}

/// Why a requested life could not travel unchanged.
enum PlaceTtlProblem {
  /// Longer than the seven-day ceiling.
  aboveMaximum,

  /// Inside the bounds but not one of the ten stops, so the wire has no
  /// spelling for it.
  notALadderStep,
}

/// The outcome of [PlaceTtl.fit]: a stop, or the reason there is none.
@immutable
final class PlaceTtlFit {
  const PlaceTtlFit.chosen(PlaceTtl this.ttl)
      : problem = null,
        raisedFrom = null;

  const PlaceTtlFit.raised(PlaceTtl this.ttl, this.raisedFrom)
      : problem = null;

  const PlaceTtlFit.refused(this.problem)
      : ttl = null,
        raisedFrom = null;

  /// The stop that will travel, or null when the request was refused.
  final PlaceTtl? ttl;

  /// Why it was refused, or null when it was accepted.
  final PlaceTtlProblem? problem;

  /// Set when the floor raised the request: the composer tells the user the
  /// pin will live 15 m rather than the shorter life they asked for.
  final Duration? raisedFrom;

  bool get accepted => ttl != null;
}

/// Where a report's point came from (spec §8). It drives the copy — "from the
/// sender's GPS", "from their phone", "placed by hand" — and nothing on the
/// wire.
enum PlaceProvenance { gps, phone, pinned, received, inferred }

/// How far a point was moved before it was sent (spec §9).
///
/// Precision is the user's choice and snapping is the privacy default: a pin
/// at your exact feet is a pin at your home. Snapping happens **before** the
/// id is computed, so the id and the digits that travel agree; a receiver must
/// never re-snap, because that would change the id and defeat merging.
enum PlacePrecision {
  exact(6),
  snapped100m(3),
  snapped1km(2);

  const PlacePrecision(this.decimals);

  /// Decimal places the point travels with: six means exact, three means
  /// about 110 m, two means about 1.1 km.
  final int decimals;

  /// The point as it will be transmitted: rounded for a snapped choice,
  /// unchanged for exact (the codec truncates at six places).
  double snap(double degrees) {
    if (this == PlacePrecision.exact) return degrees;
    final double factor = _pow10(decimals).toDouble();
    return (degrees * factor).round() / factor;
  }

  /// The snapped point as the integer that travels: snap, then scale to 1e6.
  /// The id is derived from this integer, so snapping has to happen first.
  int convertE6(double degrees) => (snap(degrees) * 1000000).round();

  /// The precision a received decimal count implies, or null when it is not
  /// one of the three choices (a report may arrive at any 1–6 places).
  static PlacePrecision? fromDecimals(int decimals) {
    for (final PlacePrecision p in PlacePrecision.values) {
      if (p.decimals == decimals) return p;
    }
    return null;
  }
}

int _pow10(int n) {
  int v = 1;
  for (int i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}

/// One place: a claim with a coordinate, a type and a life (`meshmore-places-spec.md`
/// §8).
///
/// The row is immutable; a renewal is a new report with the same id and a new
/// timestamp, not a mutation, because the wire is stateless and the seen table
/// is happy with that. Confirmation counts are not a field: a confirmation is
/// weight kept beside the row (`PlaceConfirmationTally`), and it never extends
/// the life.
@immutable
final class Place {
  const Place({
    required this.id,
    required this.type,
    required this.typeToken,
    required this.label,
    required this.latE6,
    required this.lonE6,
    required this.decimals,
    required this.reporterName,
    required this.provenance,
    required this.ttl,
    required this.sentAt,
    required this.expiresAt,
    required this.lastSeen,
    this.reporterKey,
    this.description,
    this.sentAtFromSender = false,
    this.kept = false,
  });

  /// Eight lowercase hex characters, derived by [placeIdFor] from the
  /// reporter and the digits that travel — never from time (spec §5).
  final String id;

  /// The reporter's 32-byte key when the report arrived as a direct message.
  /// Channel text carries a name and no key, so this is null there and the
  /// row says "identity is a name on a channel".
  final Uint8List? reporterKey;

  /// Display name of the reporter, always present.
  final String reporterName;

  final PlaceType type;

  /// The token as it travelled. Equal to [type]'s token for a known type; an
  /// unknown word is kept here while [type] is [PlaceType.other], so the
  /// detail sheet can show what the sender meant (spec §3).
  final String typeToken;

  /// The words, at most 60 characters, never empty.
  final String label;

  /// Longer text from the binary form; channel text carries only the label.
  final String? description;

  /// Latitude and longitude truncated to six decimal places and held as
  /// integers, so every receiver hashes the same digits.
  ///
  /// The spec calls these `latE7`/`lonE7` while describing them as "the
  /// truncated coordinate at six decimal places"; the operative rule is that
  /// the id is computed from the digits that travel, which is a 1e6 scale.
  final int latE6;
  final int lonE6;

  /// Decimal places the point travelled with, 1–6.
  final int decimals;

  final PlaceProvenance provenance;

  /// The life the sender chose; [expiresAt] is [sentAt] plus this.
  final PlaceTtl ttl;

  /// The sender's clock when the report carried one. The text form carries no
  /// timestamp, so the codec stamps the receive time and clears
  /// [sentAtFromSender]; a sender clock in the future or older than the
  /// ceiling is clamped and flagged, and the UI shows "time unknown" rather
  /// than accusing a peer of staleness (spec §8).
  final DateTime sentAt;
  final bool sentAtFromSender;

  /// Absolute end of life. Final: only a deliberate renewal (a new report with
  /// the same id) moves it, and a confirmation never does.
  final DateTime expiresAt;

  /// When this device last received a report of this id — our clock, not the
  /// sender's claim.
  final DateTime lastSeen;

  /// Pinned on this device only; does not extend the wire life.
  final bool kept;

  double get latitude => latE6 / 1e6;
  double get longitude => lonE6 / 1e6;

  /// True when the id was derived from a name because there was no key.
  bool get isUnkeyed => reporterKey == null;

  /// The precision choice the digits imply, or null when the report arrived
  /// at a precision we do not offer (spec §9: a receiver never re-snaps).
  PlacePrecision? get precision => PlacePrecision.fromDecimals(decimals);

  /// Radius to draw the accuracy circle at, in metres, or null when the point
  /// is exact.
  int? get accuracyMeters => switch (decimals) {
        6 => null,
        3 => 110,
        2 => 1100,
        _ => null,
      };

  bool isLiveAt(DateTime now) => now.isBefore(expiresAt);

  /// Time left before the pin leaves the layer; never negative.
  Duration remainingAt(DateTime now) {
    final Duration left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  Place copyWith({
    PlaceType? type,
    String? typeToken,
    String? label,
    String? description,
    int? latE6,
    int? lonE6,
    int? decimals,
    String? reporterName,
    PlaceProvenance? provenance,
    PlaceTtl? ttl,
    DateTime? sentAt,
    bool? sentAtFromSender,
    DateTime? expiresAt,
    DateTime? lastSeen,
    bool? kept,
  }) {
    return Place(
      id: id,
      reporterKey: reporterKey,
      reporterName: reporterName ?? this.reporterName,
      type: type ?? this.type,
      typeToken: typeToken ?? this.typeToken,
      label: label ?? this.label,
      description: description ?? this.description,
      latE6: latE6 ?? this.latE6,
      lonE6: lonE6 ?? this.lonE6,
      decimals: decimals ?? this.decimals,
      provenance: provenance ?? this.provenance,
      ttl: ttl ?? this.ttl,
      sentAt: sentAt ?? this.sentAt,
      sentAtFromSender: sentAtFromSender ?? this.sentAtFromSender,
      expiresAt: expiresAt ?? this.expiresAt,
      lastSeen: lastSeen ?? this.lastSeen,
      kept: kept ?? this.kept,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Place &&
        other.id == id &&
        _sameBytes(other.reporterKey, reporterKey) &&
        other.reporterName == reporterName &&
        other.type == type &&
        other.typeToken == typeToken &&
        other.label == label &&
        other.description == description &&
        other.latE6 == latE6 &&
        other.lonE6 == lonE6 &&
        other.decimals == decimals &&
        other.provenance == provenance &&
        other.ttl == ttl &&
        other.sentAt == sentAt &&
        other.sentAtFromSender == sentAtFromSender &&
        other.expiresAt == expiresAt &&
        other.lastSeen == lastSeen &&
        other.kept == kept;
  }

  @override
  int get hashCode => Object.hash(
        id,
        reporterName,
        type,
        typeToken,
        label,
        latE6,
        lonE6,
        decimals,
        ttl,
        sentAt,
        expiresAt,
        lastSeen,
        kept,
        reporterKey == null ? null : Object.hashAll(reporterKey!),
      );

  @override
  String toString() =>
      'Place($id $typeToken "$label" $latE6,$lonE6 ${ttl.token})';
}

bool _sameBytes(Uint8List? a, Uint8List? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
