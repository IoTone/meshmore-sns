// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../util/geo.dart';

/// One corner of a polygon fence, in degrees.
///
/// A fence used to be a circle and nothing else, which cannot follow a property
/// line, a trailhead, a base perimeter or a parking row — the shapes a crew
/// actually cares about. A polygon is the same idea with the shape left to the
/// reader, so the corner is the smallest thing worth naming.
@immutable
final class FencePoint {
  const FencePoint(this.lat, this.lon);

  final double lat;
  final double lon;

  bool get isValid =>
      lat.isFinite && lon.isFinite && lat.abs() <= 90 && lon.abs() <= 180;

  Map<String, Object?> toJson() => <String, Object?>{'lat': lat, 'lon': lon};

  static FencePoint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? la = raw['lat'];
    final Object? lo = raw['lon'];
    if (la is! num || lo is! num) return null;
    final FencePoint p = FencePoint(la.toDouble(), lo.toDouble());
    return p.isValid ? p : null;
  }

  @override
  bool operator ==(Object other) =>
      other is FencePoint && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'FencePoint($lat, $lon)';
}

/// Metres per degree of latitude, the constant the rest of the app's geometry
/// uses. A fence spans kilometres at most, so a local flat projection around the
/// polygon's own first corner is accurate to a few parts in ten thousand — far
/// below the accuracy of the fix that feeds it.
const double _metresPerDegLat = 111320.0;

/// A point in the polygon's local metre frame.
({double x, double y}) _project(FencePoint origin, double lat, double lon) {
  final double cos = math.cos(origin.lat * math.pi / 180).abs();
  final double mPerDegLon = _metresPerDegLat * (cos < 0.01 ? 0.01 : cos);
  return (
    x: (lon - origin.lon) * mPerDegLon,
    y: (lat - origin.lat) * _metresPerDegLat,
  );
}

/// How close to an edge counts as "on" it.
///
/// A fix that lands exactly on the line is inside, because a boundary you are
/// standing on is a boundary you are in. Without this the ray cast decides by
/// floating-point luck, and a reader walking the line would see the state flip.
const double _onEdgeMeters = 0.05;

/// Whether [lat], [lon] is inside [polygon].
///
/// Ray casting on the projected metres, not a bounding box: a bounding box says
/// "inside" for the gap in a horseshoe, which is exactly the shape a fence
/// around a building with a driveway has.
bool polygonContains(List<FencePoint> polygon, double lat, double lon) {
  if (polygon.length < 3) return false;
  if (polygonEdgeDistanceMeters(polygon, lat, lon) <= _onEdgeMeters) return true;
  final FencePoint origin = polygon.first;
  final ({double x, double y}) p = _project(origin, lat, lon);
  bool inside = false;
  for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final ({double x, double y}) a = _project(origin, polygon[i].lat, polygon[i].lon);
    final ({double x, double y}) b = _project(origin, polygon[j].lat, polygon[j].lon);
    final bool straddles = (a.y > p.y) != (b.y > p.y);
    if (!straddles) continue;
    final double xAtY = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x;
    if (p.x < xAtY) inside = !inside;
  }
  return inside;
}

/// Distance in metres from [lat], [lon] to the nearest edge of [polygon].
///
/// This is what the hysteresis band is measured against: a circle's band is a
/// fraction of its radius, and a polygon has no radius, so the band is a
/// distance from the line itself.
double polygonEdgeDistanceMeters(
    List<FencePoint> polygon, double lat, double lon) {
  if (polygon.length < 2) return double.infinity;
  final FencePoint origin = polygon.first;
  final ({double x, double y}) p = _project(origin, lat, lon);
  double best = double.infinity;
  for (int i = 0; i < polygon.length; i++) {
    final FencePoint a = polygon[i];
    final FencePoint b = polygon[(i + 1) % polygon.length];
    final ({double x, double y}) pa = _project(origin, a.lat, a.lon);
    final ({double x, double y}) pb = _project(origin, b.lat, b.lon);
    final double d = _pointToSegment(p, pa, pb);
    if (d < best) best = d;
  }
  return best;
}

double _pointToSegment(({double x, double y}) p, ({double x, double y}) a,
    ({double x, double y}) b) {
  final double dx = b.x - a.x;
  final double dy = b.y - a.y;
  final double lengthSq = dx * dx + dy * dy;
  if (lengthSq <= 0) {
    final double ex = p.x - a.x;
    final double ey = p.y - a.y;
    return math.sqrt(ex * ex + ey * ey);
  }
  double t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSq;
  t = t.clamp(0.0, 1.0);
  final double ex = p.x - (a.x + t * dx);
  final double ey = p.y - (a.y + t * dy);
  return math.sqrt(ex * ex + ey * ey);
}

/// The centre of a polygon and the radius that contains it.
///
/// The centre is the vertex average rather than the area centroid: for the
/// shapes people draw they are within a few metres of each other, and the
/// average cannot divide by a zero area the way a degenerate ring can. The
/// radius is the distance to the farthest corner, so a circle of it around the
/// centre contains the whole polygon — which is what the map's label anchor and
/// the "show all" camera both need.
({double lat, double lon, double radiusMeters}) polygonCentre(
    List<FencePoint> polygon) {
  if (polygon.isEmpty) return (lat: 0, lon: 0, radiusMeters: 0);
  double lat = 0;
  double lon = 0;
  for (final FencePoint p in polygon) {
    lat += p.lat;
    lon += p.lon;
  }
  lat /= polygon.length;
  lon /= polygon.length;
  double radius = 0;
  for (final FencePoint p in polygon) {
    final double d = haversineMeters(lat, lon, p.lat, p.lon);
    if (d > radius) radius = d;
  }
  return (lat: lat, lon: lon, radiusMeters: radius);
}

/// A geofence with a hysteresis band (`meshmore-feature-register.md` §5: ±5 %
/// margin, once per continuous stay).
///
/// The margin exists because a boundary is not a place: a person standing on
/// the line produces a stream of crossings, and each one would fire an alert.
/// Entering requires being inside `radius × 0.95`; leaving requires being
/// outside `radius × 1.05`; between the two, nothing changes. The state is
/// therefore sticky, and "once per continuous stay" falls out of it rather
/// than needing a separate debounce.
///
/// A polygon fence keeps the same idea with the band measured from the line
/// instead of from a radius: entering is being inside, and leaving is being
/// outside by more than [polygonBandMeters]. Standing on the line is inside, so
/// walking along it does not chatter.
final class Geofence {
  Geofence({
    required this.id,
    required this.lat,
    required this.lon,
    required this.radiusMeters,
    this.polygon,
  });

  /// Margin on each side of the radius, as the register decided it.
  static const double hysteresis = 0.05;

  final String id;

  /// The centre. For a polygon this is [polygonCentre]'s vertex average, which
  /// is where the map puts the name.
  final double lat;
  final double lon;

  /// The radius. For a polygon this is the distance to its farthest corner, so
  /// a circle of it contains the shape.
  final double radiusMeters;

  /// The corners, in draw order, open (the first point is not repeated). Null
  /// for a circle.
  final List<FencePoint>? polygon;

  bool get isPolygon => polygon != null && polygon!.length >= 3;

  double get enterRadius => radiusMeters * (1 - hysteresis);
  double get leaveRadius => radiusMeters * (1 + hysteresis);

  /// The hysteresis band for a polygon, in metres.
  ///
  /// The same fraction of the fence's own size that a circle uses, with a floor
  /// of two metres: a fix is good to a few metres, and a band narrower than that
  /// would fire on GPS noise rather than on walking.
  double get polygonBandMeters => math.max(2.0, hysteresis * radiusMeters);
}

/// What a position sample did to a fence's state.
enum GeofenceEvent { entered, left, unchanged, noPosition }

/// The state one fence keeps between samples.
///
/// Kept apart from [Geofence] so the same fence definition can be watched twice
/// (two sessions, two devices) without the second overwriting the first's
/// inside/outside state.
final class GeofenceWatch {
  GeofenceWatch(this.fence, {bool inside = false}) : _inside = inside;

  Geofence fence;

  bool _inside;
  int _entries = 0;

  bool get isInside => _inside;

  /// How many continuous stays have begun. Used by the alert path so it can say
  /// "3rd time today" without re-deriving the state.
  int get entries => _entries;

  /// Point this watch at an edited fence without losing where we stand.
  ///
  /// An edit is the same fence with a new name or a new radius, so the state
  /// stays: a reader who renames a fence they are standing in has not left it,
  /// and re-deriving from "outside" would fire an entry on the next sample for
  /// a crossing that never happened. If the new radius excludes us, the next
  /// sample reports the leave, which is true and is what a shrink means.
  void rebase(Geofence next) {
    fence = next;
  }

  /// Feeds one position. A sample with no fix changes nothing and says so:
  /// treating "no position" as "outside" would fire a leave on every GPS gap.
  GeofenceEvent update({double? lat, double? lon}) {
    if (lat == null || lon == null) return GeofenceEvent.noPosition;
    if (fence.isPolygon) return _updatePolygon(fence.polygon!, lat, lon);
    final double d = haversineMeters(lat, lon, fence.lat, fence.lon);
    if (!_inside && d <= fence.enterRadius) {
      _inside = true;
      _entries++;
      return GeofenceEvent.entered;
    }
    if (_inside && d >= fence.leaveRadius) {
      _inside = false;
      return GeofenceEvent.left;
    }
    return GeofenceEvent.unchanged;
  }

  GeofenceEvent _updatePolygon(
      List<FencePoint> polygon, double lat, double lon) {
    final bool inside = polygonContains(polygon, lat, lon);
    if (!_inside && inside) {
      _inside = true;
      _entries++;
      return GeofenceEvent.entered;
    }
    // Leaving needs to be clear of the line by the band, so a step over the
    // boundary and back is not two events.
    if (_inside &&
        !inside &&
        polygonEdgeDistanceMeters(polygon, lat, lon) >=
            fence.polygonBandMeters) {
      _inside = false;
      return GeofenceEvent.left;
    }
    return GeofenceEvent.unchanged;
  }
}
