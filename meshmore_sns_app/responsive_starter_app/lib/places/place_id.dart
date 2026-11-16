// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'place.dart';

/// The identity of a place report (`meshmore-places-spec.md` §5): the first
/// eight hex characters of `sha256(reporter ‖ latE6 ‖ lonE6 ‖ type)`.
///
/// **Time is deliberately absent.** A renewal is the same place re-reported
/// with a new timestamp, so a time bucket would turn every renewal into a new
/// pin — exactly the duplicate the id exists to prevent. Reversal is expensive
/// because ids are persisted.
///
/// The coordinate integers are the digits that travel, not the receiver's
/// idea of them: both sides hash the same 1e6-scaled integers, which is why
/// snapping happens before this call and a receiver never re-snaps.
///
/// A channel report carries a display name and no key, so the name's bytes
/// stand in and the caller marks the row unkeyed. The id is still
/// deterministic, but two reporters who share a name collide; the app says
/// "identity is a name on a channel" instead of pretending otherwise.
String placeIdFor({
  required List<int>? reporterKey,
  required String reporterName,
  required int latE6,
  required int lonE6,
  required String typeToken,
}) {
  if (latE6 < -90000000 || latE6 > 90000000) {
    throw ArgumentError.value(latE6, 'latE6', 'outside ±90° at 1e6');
  }
  if (lonE6 < -180000000 || lonE6 > 180000000) {
    throw ArgumentError.value(lonE6, 'lonE6', 'outside ±180° at 1e6');
  }

  // The key is the identity when there is one. Otherwise the name exactly as
  // the channel delivered it — every receiver sees that same spelling, so no
  // normalisation is applied here that another implementation might not apply.
  final List<int> identity = (reporterKey != null && reporterKey.isNotEmpty)
      ? reporterKey
      : utf8.encode(reporterName);
  if (identity.isEmpty) {
    throw ArgumentError('a place id needs a reporter key or a reporter name');
  }

  final ByteData coords = ByteData(8)
    ..setInt32(0, latE6, Endian.big)
    ..setInt32(4, lonE6, Endian.big);

  final Digest digest = sha256.convert(<int>[
    ...identity,
    ...coords.buffer.asUint8List(),
    ...utf8.encode(typeToken),
  ]);
  return digest.toString().substring(0, 8);
}

/// [Place.id]'s derivation, applied to a row's own fields.
String placeIdOf(Place place) => placeIdFor(
      reporterKey: place.reporterKey,
      reporterName: place.reporterName,
      latE6: place.latE6,
      lonE6: place.lonE6,
      typeToken: place.typeToken,
    );
