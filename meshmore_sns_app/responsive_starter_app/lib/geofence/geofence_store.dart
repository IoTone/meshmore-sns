// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'geofence_engine.dart';
import '../meshcore/secure/sealed_document.dart';

/// A fence the user drew: a centre, a radius, and a name to say out loud.
///
/// A fence is either a circle or a polygon. The circle is the original shape and
/// every record written before polygons existed is one, so the polygon is an
/// optional field rather than a second type: an old record has no `poly` key and
/// loads as a circle, and a record with one ignores the radius for evaluation
/// while still carrying a centre and a radius for the map's label and the
/// "show all" camera.
final class StoredGeofence {
  const StoredGeofence({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.polygon,
  });

  final String id;
  final String label;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  /// The corners, in draw order, open. Null for a circle.
  final List<FencePoint>? polygon;

  bool get isPolygon => polygon != null && polygon!.length >= 3;

  Geofence toEngine() => Geofence(
        id: id,
        lat: latitude,
        lon: longitude,
        radiusMeters: radiusMeters,
        polygon: polygon,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'label': label,
        'lat': latitude,
        'lon': longitude,
        'radius': radiusMeters,
        if (polygon != null)
          'poly': <Object?>[for (final FencePoint p in polygon!) p.toJson()],
      };

  static StoredGeofence? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? id = raw['id'];
    final Object? lat = raw['lat'];
    final Object? lon = raw['lon'];
    final Object? r = raw['radius'];
    if (id is! String || lat is! num || lon is! num || r is! num) return null;
    final double la = lat.toDouble();
    final double lo = lon.toDouble();
    final double radius = r.toDouble();
    if (la.abs() > 90 || lo.abs() > 180 || !radius.isFinite || radius <= 0) {
      return null;
    }
    // A polygon that cannot be a polygon is refused rather than quietly turned
    // into a circle around its own centre: a two-corner "fence" is a bug in
    // whatever wrote it, and a circle would be a shape the reader never drew.
    List<FencePoint>? polygon;
    final Object? poly = raw['poly'];
    if (poly != null) {
      if (poly is! List) return null;
      final List<FencePoint> points = <FencePoint>[
        for (final Object? e in poly)
          if (FencePoint.fromJson(e) case final FencePoint p) p,
      ];
      if (points.length < 3 || points.length != poly.length) return null;
      polygon = List<FencePoint>.unmodifiable(points);
    }
    final Object? label = raw['label'];
    return StoredGeofence(
      id: id,
      label: label is String && label.isNotEmpty ? label : id,
      latitude: la,
      longitude: lo,
      radiusMeters: radius,
      polygon: polygon,
    );
  }
}


/// One crossing, as it is kept between sessions.
///
/// An alert is the only part of a fence that is evidence of anything: the fence
/// itself is a circle the user drew, and the crossing is the moment it mattered.
/// It was in-memory only, capped at fifty and lost on the first restart, so the
/// one question a fence raises — "what happened last night" — had no answer.
final class StoredGeofenceAlert {
  const StoredGeofenceAlert({
    required this.fenceId,
    required this.label,
    required this.entered,
    required this.at,
  });

  final String fenceId;

  /// The fence's name as it was at the crossing, so deleting the fence does not
  /// turn its history into rows of nothing.
  final String label;
  final bool entered;
  final DateTime at;

  Map<String, Object?> toJson() => <String, Object?>{
        'f': fenceId,
        'l': label,
        'e': entered,
        't': at.millisecondsSinceEpoch,
      };

  static StoredGeofenceAlert? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? f = raw['f'];
    final Object? l = raw['l'];
    final Object? e = raw['e'];
    final Object? t = raw['t'];
    if (f is! String || l is! String || e is! bool || t is! int) return null;
    return StoredGeofenceAlert(
      fenceId: f,
      label: l,
      entered: e,
      at: DateTime.fromMillisecondsSinceEpoch(t),
    );
  }
}

/// Fences are the user's own construction, so they are stored: a fence that
/// does not survive a restart watches nothing, and the point of a fence is to
/// still be there tomorrow.
final class GeofenceStore {
  GeofenceStore._();

  static const String _kKey = 'mm.geofences.v1';

  /// A backstop, not a working limit: twenty fences is already more than
  /// anyone watches, and every one costs a haversine per position sample.
  static const int capacity = 20;

  /// Record name in the app's sealed store: a fence names a place the user
  /// cares about, which is the same kind of fact as the trail beside it.
  static const String recordName = 'geofences';

  /// Set when the sealed store could not be opened, so the fences are
  /// session-only.
  static final ValueNotifier<bool> sealedUnreadable = ValueNotifier<bool>(false);

  static Future<List<StoredGeofence>> load() async {
    final String? raw = await SealedDocument.read(recordName,
        legacyKey: _kKey, sealedUnreadable: sealedUnreadable);
    return decode(raw);
  }

  static List<StoredGeofence> decode(String? raw) {
    if (raw == null || raw.isEmpty) return <StoredGeofence>[];
    try {
      final Object? doc = jsonDecode(raw);
      if (doc is! List) return <StoredGeofence>[];
      final List<StoredGeofence> rows = <StoredGeofence>[
        for (final Object? e in doc)
          if (StoredGeofence.fromJson(e) case final StoredGeofence g) g,
      ];
      return rows.length > capacity ? rows.sublist(0, capacity) : rows;
    } on FormatException {
      return <StoredGeofence>[];
    }
  }

  static String encode(List<StoredGeofence> fences) =>
      jsonEncode(<Object?>[for (final StoredGeofence f in fences) f.toJson()]);

  static Future<void> save(List<StoredGeofence> fences) async {
    final bool ok = await SealedDocument.write(recordName, encode(fences));
    sealedUnreadable.value = !ok;
  }

  /// The crossing log, in its own record so the fence list keeps its shape and
  /// an old build reading `mm.geofences.v1` still parses.
  static const String alertsRecordName = 'geofence-events';

  /// How many crossings are kept. A morning after, a week away, a season of
  /// walks: this is a log, not a database, and the trail beside it holds the
  /// detail the log points at.
  static const int alertCapacity = 200;

  static Future<List<StoredGeofenceAlert>> loadAlerts() async {
    final String? raw = await SealedDocument.read(alertsRecordName,
        sealedUnreadable: sealedUnreadable);
    return decodeAlerts(raw);
  }

  static List<StoredGeofenceAlert> decodeAlerts(String? raw) {
    if (raw == null || raw.isEmpty) return <StoredGeofenceAlert>[];
    try {
      final Object? doc = jsonDecode(raw);
      if (doc is! List) return <StoredGeofenceAlert>[];
      final List<StoredGeofenceAlert> rows = <StoredGeofenceAlert>[
        for (final Object? e in doc)
          if (StoredGeofenceAlert.fromJson(e) case final StoredGeofenceAlert a)
            a,
      ];
      return rows.length > alertCapacity
          ? rows.sublist(rows.length - alertCapacity)
          : rows;
    } on FormatException {
      return <StoredGeofenceAlert>[];
    }
  }

  static String encodeAlerts(List<StoredGeofenceAlert> alerts) =>
      jsonEncode(<Object?>[for (final StoredGeofenceAlert a in alerts) a.toJson()]);

  static Future<void> saveAlerts(List<StoredGeofenceAlert> alerts) async {
    final bool ok =
        await SealedDocument.write(alertsRecordName, encodeAlerts(alerts));
    sealedUnreadable.value = !ok;
  }

  static Future<void> clear() =>
      SealedDocument.clear(recordName, legacyKey: _kKey);
}
