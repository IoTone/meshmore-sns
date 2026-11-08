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
  })  : _mc = mc,
        _clock = clock ?? DateTime.now;

  final MeshcoreController _mc;
  final DateTime Function() _clock;

  /// False in tests that sample by hand; a real timer would race assertions.
  final bool autoTick;

  Timer? _ticker;

  final List<StoredGeofence> _fences = <StoredGeofence>[];
  final Map<String, GeofenceWatch> _watches = <String, GeofenceWatch>{};
  final List<GeofenceAlert> _alerts = <GeofenceAlert>[];

  /// Alerts kept for the screen. A walk that crosses three fences produces
  /// three lines; the cap only stops a stuck GPS from growing a list forever.
  static const int alertCapacity = 50;

  List<StoredGeofence> get fences => List<StoredGeofence>.unmodifiable(_fences);

  List<GeofenceAlert> get alerts => List<GeofenceAlert>.unmodifiable(_alerts);

  bool isInside(String fenceId) => _watches[fenceId]?.isInside ?? false;

  Future<void> load() async {
    _fences
      ..clear()
      ..addAll(await GeofenceStore.load());
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
    if (raised.isEmpty) return const <GeofenceAlert>[];
    _alerts.addAll(raised);
    if (_alerts.length > alertCapacity) {
      _alerts.removeRange(0, _alerts.length - alertCapacity);
    }
    notifyListeners();
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

  Future<void> removeFence(String id) async {
    _fences.removeWhere((StoredGeofence f) => f.id == id);
    _watches.remove(id);
    _alerts.removeWhere((GeofenceAlert a) => a.fence.id == id);
    await GeofenceStore.save(_fences);
    notifyListeners();
  }

  void _rebuildWatches() {
    _watches
      ..clear()
      ..addEntries(<MapEntry<String, GeofenceWatch>>[
        for (final StoredGeofence f in _fences)
          MapEntry<String, GeofenceWatch>(f.id, GeofenceWatch(f.toEngine())),
      ]);
  }
}
