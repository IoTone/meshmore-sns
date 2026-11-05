// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/own_location.dart';
import '../util/geo.dart';

/// One recorded position: where we were, when, and what said so.
///
/// Only *our own* fixes are recorded. A peer's advertised position is used
/// while it is live and is never written to disk: a third party's whereabout
/// is not ours to keep, and the privacy page promises that what stays on the
/// device is what the user made (`lib/screens/terms_screen.dart`).
final class PositionSample {
  const PositionSample({
    required this.latitude,
    required this.longitude,
    required this.at,
    required this.source,
    this.altitudeMeters,
  });

  final double latitude;
  final double longitude;
  final DateTime at;
  final OwnLocationSource source;
  final double? altitudeMeters;

  Map<String, Object?> toJson() => <String, Object?>{
        'lat': latitude,
        'lon': longitude,
        'at': at.millisecondsSinceEpoch,
        if (altitudeMeters != null) 'alt': altitudeMeters,
        'src': source.name,
      };

  static PositionSample? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? lat = raw['lat'];
    final Object? lon = raw['lon'];
    final Object? at = raw['at'];
    if (lat is! num || lon is! num || at is! num) return null;
    final double la = lat.toDouble();
    final double lo = lon.toDouble();
    // A stored row outside the coordinate ranges is corruption, not a fix at
    // the pole: drop it rather than plot it.
    if (!la.isFinite || !lo.isFinite || la.abs() > 90 || lo.abs() > 180) {
      return null;
    }
    if (la.abs() < 1e-9 && lo.abs() < 1e-9) return null;
    final Object? alt = raw['alt'];
    return PositionSample(
      latitude: la,
      longitude: lo,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      source: OwnLocationSource.values.firstWhere(
        (OwnLocationSource s) => s.name == raw['src'],
        orElse: () => OwnLocationSource.deviceReported,
      ),
      altitudeMeters: alt is num ? alt.toDouble() : null,
    );
  }
}

/// The recorded trail, bounded in both age and count.
///
/// Retention is seven days *and* 2000 points, whichever binds first: a day of
/// walking is a few hundred points, so the count only bites for someone who
/// records continuously, and the age only bites for someone who records
/// occasionally. A trail older than a week is not worth the disk, and a trail
/// unbounded in count is a way to fill a phone by leaving the app open.
final class PositionHistoryStore {
  PositionHistoryStore._();

  static const String _kKey = 'mm.trail.v1';

  /// Newest-first eviction past this many points.
  static const int capacity = 2000;

  /// Points older than this are dropped on load and on append.
  static const Duration retention = Duration(days: 7);

  /// Movement below this is GPS jitter, not travel: a stationary phone would
  /// otherwise log a point every sample and make the trail a cloud.
  static const double minMoveMeters = 10.0;

  static Future<List<PositionSample>> load({DateTime Function()? clock}) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return decode(p.getString(_kKey), clock: clock);
  }

  /// Parses a stored document. Split out so the retention and corruption rules
  /// are testable without a platform store.
  static List<PositionSample> decode(String? raw,
      {DateTime Function()? clock}) {
    if (raw == null || raw.isEmpty) return <PositionSample>[];
    final DateTime now = (clock ?? DateTime.now)();
    final List<PositionSample> rows = <PositionSample>[];
    try {
      final Object? doc = jsonDecode(raw);
      if (doc is! List) return <PositionSample>[];
      for (final Object? entry in doc) {
        final PositionSample? s = PositionSample.fromJson(entry);
        if (s == null) continue;
        rows.add(s);
      }
    } on FormatException {
      return <PositionSample>[];
    }
    rows.sort((PositionSample a, PositionSample b) => a.at.compareTo(b.at));
    return prune(rows, now: now);
  }

  /// Drops expired points and any point dated in the future by more than a
  /// minute — a clock that jumped backwards would otherwise keep a future row
  /// at the front of the trail for a week.
  static List<PositionSample> prune(List<PositionSample> rows,
      {required DateTime now}) {
    final DateTime floor = now.subtract(retention);
    final DateTime ceiling = now.add(const Duration(minutes: 1));
    final List<PositionSample> kept = <PositionSample>[
      for (final PositionSample s in rows)
        if (!s.at.isBefore(floor) && !s.at.isAfter(ceiling)) s,
    ]..sort((PositionSample a, PositionSample b) => a.at.compareTo(b.at));
    if (kept.length <= capacity) return kept;
    return kept.sublist(kept.length - capacity);
  }

  /// Appends [own] when it is worth a point: a real fix, at least
  /// [minMoveMeters] from the last one, and not a duplicate timestamp.
  ///
  /// Returns the new list; the caller persists it. A no-move sample returns
  /// the same list unchanged, so a stationary phone costs nothing.
  static List<PositionSample> append(
    List<PositionSample> rows,
    OwnLocation own, {
    required DateTime now,
  }) {
    if (rows.isNotEmpty) {
      final PositionSample last = rows.last;
      if (!now.isAfter(last.at)) return rows;
      if (haversineMeters(last.latitude, last.longitude, own.latitude,
              own.longitude) <
          minMoveMeters) {
        return rows;
      }
    }
    final List<PositionSample> next = <PositionSample>[
      ...rows,
      PositionSample(
        latitude: own.latitude,
        longitude: own.longitude,
        at: now,
        source: own.source,
        altitudeMeters: own.altitudeMeters,
      ),
    ];
    return prune(next, now: now);
  }

  static String encode(List<PositionSample> rows) => jsonEncode(
      <Object?>[for (final PositionSample s in rows) s.toJson()]);

  static Future<void> save(List<PositionSample> rows) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_kKey, encode(rows));
  }

  static Future<void> clear() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
  }
}

/// Records the trail as fixes arrive, and keeps it in memory for the map and
/// an export.
///
/// Driven by the app's one-second tick rather than a location stream: the
/// controller owns the fix (radio GPS first, phone fallback) and already
/// notifies listeners when it changes, so sampling [MeshcoreController
/// .ownLocation] costs nothing extra and needs no new platform permission.
final class PositionRecorder {
  PositionRecorder({DateTime Function()? clock, this.persist = true})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final bool persist;

  List<PositionSample> _rows = <PositionSample>[];
  bool _loaded = false;
  DateTime? _lastPersist;
  static const Duration _persistEvery = Duration(seconds: 30);

  List<PositionSample> get rows => List<PositionSample>.unmodifiable(_rows);

  bool get isEmpty => _rows.isEmpty;

  Future<void> load() async {
    _rows = persist
        ? await PositionHistoryStore.load(clock: _clock)
        : <PositionSample>[];
    _loaded = true;
  }

  bool get loaded => _loaded;

  /// Samples [own] if it is new enough to be a point. Returns true when the
  /// trail changed, so a caller can repaint only then.
  bool record(OwnLocation? own) {
    if (own == null) return false;
    final DateTime now = _clock();
    final List<PositionSample> next =
        PositionHistoryStore.append(_rows, own, now: now);
    // `append` returns the same list when the fix did not move us; the last
    // sample's time is the cheap way to tell, and a pruned tail cannot hide a
    // new point because the new one is always last.
    if (next.isEmpty ||
        (_rows.isNotEmpty && next.last.at == _rows.last.at)) {
      return false;
    }
    _rows = next;
    _maybePersist(now);
    return true;
  }

  /// Writes at most every thirty seconds: a per-sample write would put a
  /// flash write behind every GPS tick, and a lost thirty seconds of trail is
  /// not worth that.
  void _maybePersist(DateTime now) {
    if (!persist) return;
    final DateTime? last = _lastPersist;
    if (last != null && now.difference(last) < _persistEvery) return;
    _lastPersist = now;
    // Fire and forget: the trail is not worth blocking a fix on, and a failed
    // write leaves the in-memory rows intact for the next attempt.
    PositionHistoryStore.save(_rows);
  }

  Future<void> clear() async {
    _rows = <PositionSample>[];
    _lastPersist = null;
    if (persist) await PositionHistoryStore.clear();
  }
}
