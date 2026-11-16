// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import '../util/geo.dart';

/// Which way a distance is going between two readings.
enum RelationshipTrend {
  /// Nearer than the previous reading by more than the dead band.
  closing,

  /// Further by more than the dead band.
  opening,

  /// Within the dead band, or only one reading so far.
  steady,
}

/// One distance reading with the trend it had against the previous one.
///
/// The dead band exists because a distance is computed from two positions that
/// both wobble by a few metres: without it, a parked node "closes" and "opens"
/// every sample, and the line is noise dressed as intelligence.
final class RelationshipReading {
  const RelationshipReading({
    required this.key,
    required this.distanceMeters,
    required this.trend,
    required this.at,
    this.previousDistanceMeters,
  });

  /// Node identity the reading belongs to.
  final String key;
  final double distanceMeters;
  final RelationshipTrend trend;
  final DateTime at;
  final double? previousDistanceMeters;

  /// A trend is only claimed when there is something to compare against.
  bool get hasTrend => previousDistanceMeters != null;
}

/// Tracks the distance between us and each node, and says which way it is
/// going (`meshmore-feature-register.md` §5: "A is 400 m from B and closing").
///
/// Deliberately separate from the node list: a trend is not a property of a
/// node, it is a property of the last two *measurements*, and keeping it here
/// means the node model stays a snapshot of the mesh rather than a store of
/// history.
final class RelationshipTracker {
  RelationshipTracker({this.deadBandMeters = 10.0, this.minInterval = const Duration(seconds: 5)});

  /// Movement smaller than this is position jitter, not travel.
  final double deadBandMeters;

  /// Ignore repeats inside this window: one frame arriving twice is not two
  /// observations.
  final Duration minInterval;

  final Map<String, RelationshipReading> _last = <String, RelationshipReading>{};

  RelationshipReading? readingFor(String key) => _last[key];

  /// Records [distanceMeters] for [key] and returns the reading with its
  /// trend. A repeat inside [minInterval] returns the previous reading
  /// unchanged rather than inventing a second observation.
  RelationshipReading update(
    String key,
    double distanceMeters,
    DateTime at,
  ) {
    final RelationshipReading? prev = _last[key];
    if (prev != null && at.difference(prev.at) < minInterval) return prev;
    final RelationshipTrend trend;
    if (prev == null || !distanceMeters.isFinite) {
      trend = RelationshipTrend.steady;
    } else {
      final double delta = prev.distanceMeters - distanceMeters;
      if (delta.abs() < deadBandMeters) {
        trend = RelationshipTrend.steady;
      } else {
        trend = delta > 0
            ? RelationshipTrend.closing
            : RelationshipTrend.opening;
      }
    }
    final RelationshipReading next = RelationshipReading(
      key: key,
      distanceMeters: distanceMeters,
      trend: trend,
      at: at,
      previousDistanceMeters: prev?.distanceMeters,
    );
    _last[key] = next;
    return next;
  }

  /// Convenience for the caller that has both positions: feeds [update] from
  /// a haversine distance, so no caller re-implements the arithmetic.
  RelationshipReading updateBetween(
    String key, {
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required DateTime at,
  }) =>
      update(key, haversineMeters(fromLat, fromLon, toLat, toLon), at);

  void clear() => _last.clear();
}
