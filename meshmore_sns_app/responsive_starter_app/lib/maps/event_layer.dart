// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// R61 — an event map: a GeoJSON file fetched once from a URL (a
/// festival's street plan, a race course, a camp layout) and drawn
/// over the basemap. The app ships no event data; the user brings
/// the URL, and the publisher's terms travel with it.
class EventLayer {
  EventLayer({
    required this.id,
    required this.name,
    required this.url,
    required this.addedMs,
    required this.updatedMs,
    required this.bytes,
    required this.features,
    this.keepDays = 0,
    this.visible = true,
  });

  final String id;
  String name;
  final String url;
  final int addedMs;
  int updatedMs;
  int bytes;
  int features;

  /// Delete this many days after the last download; 0 = keep.
  int keepDays;
  bool visible;

  int? get expiresAtMs =>
      keepDays == 0 ? null : updatedMs + Duration(days: keepDays).inMilliseconds;

  Map<String, Object> toJson() => <String, Object>{
        'id': id,
        'name': name,
        'url': url,
        'added': addedMs,
        'updated': updatedMs,
        'bytes': bytes,
        'features': features,
        'keep': keepDays,
        'visible': visible,
      };

  static EventLayer fromJson(Map<String, Object?> j) => EventLayer(
        id: j['id']! as String,
        name: j['name']! as String,
        url: j['url']! as String,
        addedMs: (j['added']! as num).toInt(),
        updatedMs: (j['updated']! as num).toInt(),
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
        features: (j['features'] as num?)?.toInt() ?? 0,
        keepDays: (j['keep'] as num?)?.toInt() ?? 0,
        visible: j['visible'] != false,
      );
}

/// A labelled point.
class GeoPoint {
  const GeoPoint(this.at, this.label);
  final LatLng at;
  final String? label;
}

/// GeoJSON flattened into what a map draws.
class GeoShapes {
  GeoShapes();
  final List<GeoPoint> points = <GeoPoint>[];
  final List<List<LatLng>> lines = <List<LatLng>>[];
  final List<List<LatLng>> polygons = <List<LatLng>>[];

  int get count => points.length + lines.length + polygons.length;
}

/// Parse GeoJSON text; null when it isn't GeoJSON. Polygon holes are
/// dropped (outer rings only) — an overlay, not a GIS.
GeoShapes? parseGeoJson(String text) {
  final Object? root;
  try {
    root = jsonDecode(text);
  } catch (_) {
    return null;
  }
  if (root is! Map<String, Object?>) return null;
  final GeoShapes out = GeoShapes();
  final String? type = root['type'] as String?;
  if (type == 'FeatureCollection') {
    final Object? fs = root['features'];
    if (fs is! List) return null;
    for (final Object? f in fs) {
      if (f is Map<String, Object?>) _feature(f, out);
    }
  } else if (type == 'Feature') {
    _feature(root, out);
  } else if (type != null) {
    _geometry(root, null, out);
  } else {
    return null;
  }
  return out;
}

String? _labelOf(Map<String, Object?>? props) {
  if (props == null) return null;
  for (final String k in const <String>['name', 'Name', 'NAME', 'label', 'title']) {
    final Object? v = props[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

void _feature(Map<String, Object?> f, GeoShapes out) {
  final Object? g = f['geometry'];
  if (g is Map<String, Object?>) {
    _geometry(g, _labelOf(f['properties'] as Map<String, Object?>?), out);
  }
}

LatLng? _pt(Object? c) {
  if (c is! List || c.length < 2) return null;
  final Object? lon = c[0];
  final Object? lat = c[1];
  if (lon is! num || lat is! num) return null;
  if (lat.abs() > 90 || lon.abs() > 180) return null;
  return LatLng(lat.toDouble(), lon.toDouble());
}

List<LatLng> _ring(Object? c) => c is List
    ? c.map(_pt).whereType<LatLng>().toList()
    : const <LatLng>[];

void _geometry(Map<String, Object?> g, String? label, GeoShapes out) {
  final Object? c = g['coordinates'];
  switch (g['type']) {
    case 'Point':
      final LatLng? p = _pt(c);
      if (p != null) out.points.add(GeoPoint(p, label));
    case 'MultiPoint':
      for (final LatLng p in _ring(c)) {
        out.points.add(GeoPoint(p, label));
      }
    case 'LineString':
      final List<LatLng> l = _ring(c);
      if (l.length >= 2) out.lines.add(l);
    case 'MultiLineString':
      if (c is List) {
        for (final Object? part in c) {
          final List<LatLng> l = _ring(part);
          if (l.length >= 2) out.lines.add(l);
        }
      }
    case 'Polygon':
      if (c is List && c.isNotEmpty) {
        final List<LatLng> r = _ring(c.first);
        if (r.length >= 3) out.polygons.add(r);
      }
    case 'MultiPolygon':
      if (c is List) {
        for (final Object? poly in c) {
          if (poly is List && poly.isNotEmpty) {
            final List<LatLng> r = _ring(poly.first);
            if (r.length >= 3) out.polygons.add(r);
          }
        }
      }
    case 'GeometryCollection':
      final Object? gs = g['geometries'];
      if (gs is List) {
        for (final Object? sub in gs) {
          if (sub is Map<String, Object?>) _geometry(sub, label, out);
        }
      }
  }
}
