// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'geofence_engine.dart';
import '../meshcore/secure/sealed_document.dart';

/// A fence the user drew: a centre, a radius, and a name to say out loud.
final class StoredGeofence {
  const StoredGeofence({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final String id;
  final String label;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  Geofence toEngine() => Geofence(
        id: id,
        lat: latitude,
        lon: longitude,
        radiusMeters: radiusMeters,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'label': label,
        'lat': latitude,
        'lon': longitude,
        'radius': radiusMeters,
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
    final Object? label = raw['label'];
    return StoredGeofence(
      id: id,
      label: label is String && label.isNotEmpty ? label : id,
      latitude: la,
      longitude: lo,
      radiusMeters: radius,
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

  static Future<void> clear() =>
      SealedDocument.clear(recordName, legacyKey: _kKey);
}
