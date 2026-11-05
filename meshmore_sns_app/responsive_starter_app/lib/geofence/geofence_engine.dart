// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import '../util/geo.dart';

/// A geofence with a hysteresis band (`meshmore-feature-register.md` §5: ±5 %
/// margin, once per continuous stay).
///
/// The margin exists because a boundary is not a place: a person standing on
/// the line produces a stream of crossings, and each one would fire an alert.
/// Entering requires being inside `radius × 0.95`; leaving requires being
/// outside `radius × 1.05`; between the two, nothing changes. The state is
/// therefore sticky, and "once per continuous stay" falls out of it rather
/// than needing a separate debounce.
final class Geofence {
  Geofence({
    required this.id,
    required this.lat,
    required this.lon,
    required this.radiusMeters,
  });

  /// Margin on each side of the radius, as the register decided it.
  static const double hysteresis = 0.05;

  final String id;
  final double lat;
  final double lon;
  final double radiusMeters;

  double get enterRadius => radiusMeters * (1 - hysteresis);
  double get leaveRadius => radiusMeters * (1 + hysteresis);
}

/// What a position sample did to a fence's state.
enum GeofenceEvent { entered, left, unchanged, noPosition }

/// The state one fence keeps between samples.
///
/// Kept apart from [Geofence] so the same fence definition can be watched twice
/// (two sessions, two devices) without the second overwriting the first's
/// inside/outside state.
final class GeofenceWatch {
  GeofenceWatch(this.fence);

  final Geofence fence;

  bool _inside = false;
  int _entries = 0;

  bool get isInside => _inside;

  /// How many continuous stays have begun. Used by the alert path so it can say
  /// "3rd time today" without re-deriving the state.
  int get entries => _entries;

  /// Feeds one position. A sample with no fix changes nothing and says so:
  /// treating "no position" as "outside" would fire a leave on every GPS gap.
  GeofenceEvent update({double? lat, double? lon}) {
    if (lat == null || lon == null) return GeofenceEvent.noPosition;
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
}
