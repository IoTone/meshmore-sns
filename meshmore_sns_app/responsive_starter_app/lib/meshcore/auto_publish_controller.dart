// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../perms/location_service.dart';
import 'meshcore_controller.dart';
import '../util/prefs.dart';

/// R36 — auto-publish location while moving.
///
/// Owns two background triggers, both optional:
/// - **Periodic** (`intervalSec` > 0): a [Timer.periodic] that
///   ticks every N seconds. Each tick: one-shot phone-GPS fix
///   → `setAdvertLatLon` → `sendSelfAdvert(flood: false)`.
/// - **Smart broadcast** (`minMovementMeters` > 0): a position
///   stream with a distance filter. The stream emits only when
///   the user has moved at least N meters from the previous
///   event — each emission triggers the same publish path.
/// - Both can be on simultaneously; whichever fires first
///   publishes that cycle.
///
/// Settings persisted in `shared_preferences`. Off by default —
/// the user explicitly turns it on under App settings →
/// "Auto-publish location."
class AutoPublishController extends ChangeNotifier {
  AutoPublishController({
    required this.mc,
    required LocationService location,
  }) : _location = location;

  final MeshcoreController mc;
  final LocationService _location;

  static const String _kEnabled = 'mm.autoPublish.enabled';
  static const String _kIntervalSec = 'mm.autoPublish.intervalSec';
  static const String _kMinMovementM = 'mm.autoPublish.minMovementM';

  /// Allowed periodic interval values (seconds). 0 means off.
  static const List<int> intervalOptions = <int>[
    0, 300, 900, 1800, 3600,
  ];

  /// Allowed smart-broadcast movement thresholds (meters). 0 means
  /// off (no stream subscription).
  static const List<int> movementOptions = <int>[
    0, 50, 200, 500, 1000,
  ];

  bool _enabled = false;
  int _intervalSec = 0;
  int _minMovementM = 0;

  Timer? _periodicTimer;
  StreamSubscription<PhoneFix>? _streamSub;

  double? _lastLat;
  double? _lastLon;
  DateTime? _lastPublishedAt;
  String _lastTrigger = '';

  /// Master toggle.
  bool get enabled => _enabled;

  /// Periodic interval in seconds; 0 = off.
  int get intervalSec => _intervalSec;

  /// Smart-broadcast distance threshold in meters; 0 = off.
  int get minMovementMeters => _minMovementM;

  /// Last successful publish (lat, lon, at, trigger). Surfaced on
  /// the settings screen so the user can confirm the loop is
  /// actually firing.
  double? get lastLat => _lastLat;
  double? get lastLon => _lastLon;
  DateTime? get lastPublishedAt => _lastPublishedAt;
  String get lastTrigger => _lastTrigger;

  /// Load persisted settings + start the loops if enabled.
  Future<void> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    _enabled = Prefs.readBool(p, _kEnabled);
    _intervalSec = Prefs.readInt(p, _kIntervalSec);
    _minMovementM = Prefs.readInt(p, _kMinMovementM);
    _restart();
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    if (v == _enabled) return;
    _enabled = v;
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setBool(p, _kEnabled, v);
    _restart();
    notifyListeners();
  }

  Future<void> setIntervalSec(int v) async {
    if (!intervalOptions.contains(v)) return;
    if (v == _intervalSec) return;
    _intervalSec = v;
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setInt(p, _kIntervalSec, v);
    _restart();
    notifyListeners();
  }

  Future<void> setMinMovementMeters(int v) async {
    if (!movementOptions.contains(v)) return;
    if (v == _minMovementM) return;
    _minMovementM = v;
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setInt(p, _kMinMovementM, v);
    _restart();
    notifyListeners();
  }

  /// Tear down + re-arm timers/streams from the current settings.
  /// Idempotent; safe to call after any setter.
  void _restart() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _streamSub?.cancel();
    _streamSub = null;
    if (!_enabled) return;
    if (_intervalSec > 0) {
      _periodicTimer = Timer.periodic(
        Duration(seconds: _intervalSec),
        (_) => unawaited(_publish('periodic')),
      );
    }
    if (_minMovementM > 0) {
      _streamSub = _location
          .positionStream(distanceFilterMeters: _minMovementM)
          .listen(
        (PhoneFix fix) => unawaited(_publish('movement', fix)),
        onError: (Object _) {},
      );
    }
  }

  /// Take a fix → push to device → re-advert. The stream path
  /// already has a fix in hand; the timer path runs a one-shot
  /// request. Returns the [LocationFailure] when there was no fix to
  /// publish, so an interactive caller ("Publish now") can say why
  /// instead of appearing to do nothing. The timer and stream callers
  /// ignore it and retry on the next tick.
  Future<LocationFailure?> _publish(String trigger,
      [PhoneFix? cached]) async {
    if (!mc.isReady) return null;
    PhoneFix? fix = cached;
    if (fix == null) {
      // `prompt: false` — this runs from a timer and from a position
      // stream, both with no UI. The permission is asked for at the
      // settings toggle instead, and a denial comes back as a
      // `LocationFailure` rather than an unattended dialog.
      final LocationOutcome outcome =
          await _location.requestFix(prompt: false);
      fix = outcome.fix;
      if (fix == null) return outcome.failure;
    }
    // R44 follow-up — keep the controller's ownLocation altitude
    // fresh. AutoPublishController is already paying the GPS-read
    // cost; pumping the result back into the controller means the
    // elevation-profile view and any altitude readout get phone
    // GPS altitude on the same cadence the device gets lat/lon.
    mc.cachePhoneFix(fix);
    try {
      // R44 — forward altitude too. Phone GPS reports altitude in
      // metres above the WGS-84 ellipsoid; when the chip didn't
      // produce a confident reading PhoneFix.altitudeMeters is null
      // and we just send lat/lon (codec drops the optional 3rd
      // i32 in that case).
      await mc.setAdvertLatLon(
        latitude: fix.latitude,
        longitude: fix.longitude,
        altitudeMeters: fix.altitudeMeters,
      );
      await mc.sendSelfAdvert(flood: false);
    } catch (_) {
      // Transport hiccup or device-not-ready race — silent. Next
      // tick will retry.
      return null;
    }
    _lastLat = fix.latitude;
    _lastLon = fix.longitude;
    _lastPublishedAt = DateTime.now();
    _lastTrigger = trigger;
    notifyListeners();
    return null;
  }

  /// Force a one-shot publish right now (used by the "Publish now"
  /// button in settings). Honours the master toggle: no-op when
  /// off, and returns null when nothing was wrong to report.
  ///
  /// The returned failure is what lets the button explain itself: this
  /// path used to call `currentFix` with no permission request and
  /// return silently, so a user who had never granted location pressed
  /// "Publish now" and saw absolutely nothing happen.
  Future<LocationFailure?> publishNow() async {
    if (!_enabled) return null;
    return _publish('manual');
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    _streamSub?.cancel();
    super.dispose();
  }
}
