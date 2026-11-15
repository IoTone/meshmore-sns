// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../meshcore/meshcore_controller.dart';
import '../meshcore/own_location.dart';
import 'geofence_engine.dart';
import 'geofence_store.dart';
import '../util/safe_notifier.dart';

/// One fence event worth telling the user about.
final class GeofenceAlert {
  const GeofenceAlert({
    required this.fence,
    required this.event,
    required this.at,
  });

  final StoredGeofence fence;
  final GeofenceEvent event;
  final DateTime at;

  bool get isEntry => event == GeofenceEvent.entered;
}

/// Watches the user's fences against their own position.
///
/// Sampling happens on a one-second tick rather than per frame: a fence is
/// crossed by walking, and a sample per inbound frame would re-run a haversine
/// for every message on a busy channel. The hysteresis lives in
/// [GeofenceWatch], so this class only has to decide which samples to feed.
final class GeofenceController extends ChangeNotifier with SafeNotifier {
  GeofenceController({
    required MeshcoreController mc,
    DateTime Function()? clock,
    this.autoTick = true,
    this.onRaised,
  })  : _mc = mc,
        _clock = clock ?? DateTime.now;

  final MeshcoreController _mc;
  final DateTime Function() _clock;

  /// False in tests that sample by hand; a real timer would race assertions.
  final bool autoTick;

  /// Told about the crossings this sample raised, so something outside this
  /// class can make them heard.
  ///
  /// Until this existed a fence crossing was recorded and nothing else: the
  /// only reader of `alerts` was the fence screen itself, which meant a fence
  /// fired exactly when nobody was looking at it and stayed silent. A fence is
  /// an alert, and an alert that waits for the screen is not one.
  final void Function(List<GeofenceAlert> raised)? onRaised;

  Timer? _ticker;

  final List<StoredGeofence> _fences = <StoredGeofence>[];
  final Map<String, GeofenceWatch> _watches = <String, GeofenceWatch>{};
  final List<GeofenceAlert> _alerts = <GeofenceAlert>[];

  /// Alerts kept for the screen and in the log. A walk that crosses three
  /// fences produces three lines, and the store keeps the last
  /// [GeofenceStore.alertCapacity] across restarts so the morning after has an
  /// answer.
  static const int alertCapacity = GeofenceStore.alertCapacity;

  List<StoredGeofence> get fences => List<StoredGeofence>.unmodifiable(_fences);

  List<GeofenceAlert> get alerts => List<GeofenceAlert>.unmodifiable(_alerts);

  bool isInside(String fenceId) => _watches[fenceId]?.isInside ?? false;

  Future<void> load() async {
    _fences
      ..clear()
      ..addAll(await GeofenceStore.load());
    _alerts
      ..clear()
      ..addAll(<GeofenceAlert>[
        for (final StoredGeofenceAlert a in await GeofenceStore.loadAlerts())
          GeofenceAlert(
            // The fence a crossing belongs to may have been deleted since. The
            // label travels with the alert, so the log keeps its meaning and the
            // row simply has no fence to open.
            fence: StoredGeofence(
              id: a.fenceId,
              label: a.label,
              latitude: 0,
              longitude: 0,
              radiusMeters: 0,
            ),
            event: a.entered ? GeofenceEvent.entered : GeofenceEvent.left,
            at: a.at,
          ),
      ]);
    _rebuildWatches();
    notifyListeners();
  }

  void start() {
    if (!autoTick || _ticker != null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => sample());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  /// Feeds the current fix to every fence and records what changed.
  ///
  /// Returns the alerts raised by this sample, so a caller can react to them
  /// without waiting for a notification.
  List<GeofenceAlert> sample([OwnLocation? own]) {
    final OwnLocation? fix = own ?? _mc.ownLocation;
    if (fix == null) {
      // No fix is not "outside": feeding null leaves every watch's state
      // exactly as it was (see [GeofenceWatch.update]).
      return const <GeofenceAlert>[];
    }
    final DateTime now = _clock();
    final List<GeofenceAlert> raised = <GeofenceAlert>[];
    for (final StoredGeofence fence in _fences) {
      final GeofenceWatch? watch = _watches[fence.id];
      if (watch == null) continue;
      final GeofenceEvent e = watch.update(
        lat: fix.latitude,
        lon: fix.longitude,
      );
      if (e == GeofenceEvent.entered || e == GeofenceEvent.left) {
        raised.add(GeofenceAlert(fence: fence, event: e, at: now));
      }
    }
    // The inside state is part of the fence now, so a restart resumes where the
    // reader actually is. Written whenever it changed, not only on a crossing:
    // a fence that was entered before the app closed and left while it was
    // closed is a leave the next sample reports, and the state has to match.
    bool stateChanged = false;
    for (int i = 0; i < _fences.length; i++) {
      final StoredGeofence f = _fences[i];
      final bool now = _watches[f.id]?.isInside ?? false;
      if (now != f.inside) {
        _fences[i] = f.copyWith(inside: now);
        stateChanged = true;
      }
    }
    if (stateChanged) unawaited(GeofenceStore.save(_fences));
    if (raised.isEmpty) return const <GeofenceAlert>[];
    _alerts.addAll(raised);
    if (_alerts.length > alertCapacity) {
      _alerts.removeRange(0, _alerts.length - alertCapacity);
    }
    notifyListeners();
    // Written after the listeners so the screen updates at once and the disk
    // catches up behind it. A crossing is evidence, so it is persisted rather
    // than kept in a list that dies with the process.
    unawaited(_saveAlerts());
    // After the listeners, so the screen is already showing the new line by the
    // time the cue plays for it.
    onRaised?.call(raised);
    return raised;
  }

  Future<void> addFence({
    required String label,
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    if (_fences.length >= GeofenceStore.capacity) return;
    final String id = 'gf${_clock().millisecondsSinceEpoch}';
    final StoredGeofence fence = StoredGeofence(
      id: id,
      label: label,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
    _fences.add(fence);
    _watches[id] = GeofenceWatch(fence.toEngine());
    await GeofenceStore.save(_fences);
    notifyListeners();
  }

  /// Add a fence the reader drew as a polygon.
  ///
  /// The centre and the radius are derived rather than asked for: the centre is
  /// where the map puts the name, and the radius is the distance to the farthest
  /// corner, so a circle of it contains the shape. Both are stored so the label
  /// anchor, the "show all" camera and an older build reading the record all
  /// keep working without knowing what a polygon is.
  Future<void> addPolygonFence({
    required String label,
    required List<FencePoint> polygon,
  }) async {
    if (_fences.length >= GeofenceStore.capacity) return;
    if (polygon.length < 3) return;
    final ({double lat, double lon, double radiusMeters}) centre =
        polygonCentre(polygon);
    if (centre.radiusMeters <= 0) return;
    final String id = 'gf${_clock().millisecondsSinceEpoch}';
    final StoredGeofence fence = StoredGeofence(
      id: id,
      label: label,
      latitude: centre.lat,
      longitude: centre.lon,
      radiusMeters: centre.radiusMeters,
      polygon: List<FencePoint>.unmodifiable(polygon),
    );
    _fences.add(fence);
    _watches[id] = GeofenceWatch(fence.toEngine());
    await GeofenceStore.save(_fences);
    notifyListeners();
  }

  /// Change a fence's name or its radius, keeping everything else.
  ///
  /// The id is the fence: it is what its crossings are filed under and what the
  /// map's label opens, so an edit rewrites the record in place rather than
  /// deleting one fence and adding another. A rename therefore keeps its history,
  /// and a resize keeps the watch's own state (see [GeofenceWatch.rebase]).
  ///
  /// Moving a fence is deliberately not part of this. A centre is where the
  /// reader drew it, and "move" needs a gesture on the map that does not exist
  /// yet; a sheet that silently moved a fence would be worse than the delete and
  /// redraw it takes today.
  Future<void> updateFence({
    required String id,
    String? label,
    double? radiusMeters,
  }) async {
    final int at = _fences.indexWhere((StoredGeofence f) => f.id == id);
    if (at < 0) return;
    final StoredGeofence old = _fences[at];
    final double radius = radiusMeters ?? old.radiusMeters;
    if (!radius.isFinite || radius <= 0) return;
    final String wanted = (label ?? old.label).trim();
    final StoredGeofence next = StoredGeofence(
      id: old.id,
      label: wanted.isEmpty ? old.label : wanted,
      latitude: old.latitude,
      longitude: old.longitude,
      radiusMeters: radius,
      // A rename must not turn a drawn fence into a circle. The shape is the
      // fence; only its name and its radius are editable here.
      polygon: old.polygon,
    );
    if (next.label == old.label && next.radiusMeters == old.radiusMeters) return;
    _fences[at] = next;
    _watches[id]?.rebase(next.toEngine());
    await GeofenceStore.save(_fences);
    notifyListeners();
  }

  /// Replace a drawn fence's corners, keeping its identity.
  ///
  /// A reshape is not a new fence: the id, the name and the crossing log stay,
  /// because the reader moved a boundary rather than drawing a second one. The
  /// watch keeps its inside state for the same reason a rename does: if the new
  /// boundary excludes the reader, the next sample reports the leave, which is
  /// true and is what moving the boundary means. Re-deriving from "outside"
  /// would fire an entry for a crossing that never happened.
  Future<void> updatePolygon({
    required String id,
    required List<FencePoint> polygon,
  }) async {
    if (polygon.length < 3) return;
    final int at = _fences.indexWhere((StoredGeofence f) => f.id == id);
    if (at < 0) return;
    final StoredGeofence old = _fences[at];
    final StoredGeofence next = StoredGeofence(
      id: old.id,
      label: old.label,
      latitude: old.latitude,
      longitude: old.longitude,
      radiusMeters: old.radiusMeters,
      polygon: polygon,
    );
    _fences[at] = next;
    _watches[id]?.rebase(next.toEngine());
    await GeofenceStore.save(_fences);
    notifyListeners();
  }

  /// Forget every crossing, on disk and in memory.
  ///
  /// A log you cannot clear is a log you did not agree to. Deleting a fence
  /// clears its own crossings; this is the other door, for the history of
  /// fences that are still there.
  Future<void> clearAlerts() async {
    if (_alerts.isEmpty) return;
    _alerts.clear();
    notifyListeners();
    await _saveAlerts();
  }

  /// The crossing log as the store keeps it.
  Future<void> _saveAlerts() => GeofenceStore.saveAlerts(<StoredGeofenceAlert>[
        for (final GeofenceAlert a in _alerts)
          StoredGeofenceAlert(
            fenceId: a.fence.id,
            label: a.fence.label,
            entered: a.isEntry,
            at: a.at,
          ),
      ]);

  Future<void> removeFence(String id) async {
    _fences.removeWhere((StoredGeofence f) => f.id == id);
    _watches.remove(id);
    // Deleting a fence deletes its crossings too, and the persisted log with
    // them. That is the promise the fence screen already made and a test holds
    // it: a history you cannot delete from the surface that owns it is a history
    // that outlives your consent. The log's own cap and the "clear" action are
    // the other two ways it ends.
    _alerts.removeWhere((GeofenceAlert a) => a.fence.id == id);
    await GeofenceStore.save(_fences);
    await _saveAlerts();
    notifyListeners();
  }

  void _rebuildWatches() {
    _watches
      ..clear()
      ..addEntries(<MapEntry<String, GeofenceWatch>>[
        for (final StoredGeofence f in _fences)
          MapEntry<String, GeofenceWatch>(
              f.id, GeofenceWatch(f.toEngine(), inside: f.inside)),
      ]);
  }
}
