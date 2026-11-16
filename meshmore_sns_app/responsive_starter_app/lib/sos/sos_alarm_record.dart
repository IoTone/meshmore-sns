// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'sos_engine.dart';

/// The on-disk form of a running alarm.
///
/// `SosEngine.snapshot()`/`restore()` exist because `meshmore-sos-spec.md`
/// §13.10 requires an alarm to either resume with fresh sends or tell the user
/// it stopped — never silently neither. The engine half was written and
/// tested; nothing wrote a snapshot, so a process death ended the alarm in
/// silence (safety audit SOS-2). This is the missing half: a versioned,
/// self-describing record with no dependence on the app's models.
///
/// The record is deliberately tolerant on read. A snapshot written by an older
/// build, a truncated string or a hand-edited preference all decode to `null`,
/// and the caller clears the key rather than failing to start.
const int _recordVersion = 1;

/// Three decimals: about 110 m of latitude, which is a search area rather than a
/// doorstep.
double? _coarse(double? v) => v == null ? null : (v * 1000).round() / 1000;

Map<String, Object?>? alarmToJson(SosSnapshot? snapshot) {
  if (snapshot == null) return null;
  final SosRaise r = snapshot.raise;
  return <String, Object?>{
    'v': _recordVersion,
    'state': snapshot.state.name,
    'id': r.id,
    'nonce': base64Encode(r.nonce),
    'raisedAt': r.raisedAt.toUtc().toIso8601String(),
    'callsign': r.callsign,
    'words': r.words,
    'channelId': r.targets.channelId,
    'keys': <String>[
      for (final List<int> k in r.targets.contactKeys) base64Encode(k),
    ],
    // Coarsened to three decimals, about 110 m. The live alarm keeps the exact
    // fix in memory and sends that; what is *at rest* on the disk is only ever
    // needed to resume after a process death, and a snapshot carrying a
    // metre-accurate position beside the operator's own words is the most
    // sensitive unencrypted record the app holds. A search area survives the
    // rounding; a pinpoint does not.
    'lat': _coarse(r.lat),
    'lon': _coarse(r.lon),
    'fixAt': r.fixAt?.toUtc().toIso8601String(),
    'issued': snapshot.issued.toList(growable: false),
  };
}

/// Reads a record, or null when it is absent, foreign or unreadable.
SosSnapshot? alarmFromJson(Map<String, Object?>? json) {
  if (json == null) return null;
  if (json['v'] != _recordVersion) return null;
  final SosState? state = _stateByName(json['state']);
  final String? id = json['id'] as String?;
  final String? nonce = json['nonce'] as String?;
  final String? raisedAt = json['raisedAt'] as String?;
  if (state == null || id == null || nonce == null || raisedAt == null) {
    return null;
  }
  final DateTime? raised = DateTime.tryParse(raisedAt);
  if (raised == null) return null;
  final List<int> nonceBytes;
  try {
    nonceBytes = base64Decode(nonce);
  } on FormatException {
    return null;
  }
  if (nonceBytes.isEmpty) return null;
  final List<List<int>> keys = <List<int>>[];
  for (final Object? k in (json['keys'] as List<Object?>?) ?? const <Object?>[]) {
    if (k is! String) return null;
    try {
      final List<int> bytes = base64Decode(k);
      if (bytes.length != 32) return null;
      keys.add(bytes);
    } on FormatException {
      return null;
    }
  }
  final Set<String> issued = <String>{
    for (final Object? s in (json['issued'] as List<Object?>?) ?? const <Object?>[])
      if (s is String) s,
  };
  return SosSnapshot(
    state: state,
    raise: SosRaise(
      id: id,
      nonce: nonceBytes,
      raisedAt: raised,
      callsign: (json['callsign'] as String?) ?? '',
      words: (json['words'] as String?) ?? '',
      targets: SosTargets(
        channelId: json['channelId'] as String?,
        contactKeys: keys,
      ),
      lat: (json['lat'] as num?)?.toDouble(),
      lon: (json['lon'] as num?)?.toDouble(),
      fixAt: json['fixAt'] is String ? DateTime.tryParse(json['fixAt']! as String) : null,
    ),
    issued: issued,
  );
}

SosState? _stateByName(Object? name) {
  for (final SosState s in SosState.values) {
    if (s.name == name) return s;
  }
  return null;
}

/// The lowercase hex of [bytes], the form the controller compares with.
String hexOfKey(List<int> bytes) =>
    <String>[for (final int b in bytes) b.toRadixString(16).padLeft(2, '0')]
        .join();
