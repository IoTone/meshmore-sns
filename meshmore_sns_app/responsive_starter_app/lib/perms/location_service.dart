// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// R22 / U13 — small interface for the **one-shot phone-GPS fix**
/// used as a fallback when the MeshCore device has no GPS. Behind
/// an interface so tests don't reach `geolocator`'s platform plugin
/// (which can't run in a vm/widget test).
///
/// Concrete impls: [GeolocatorLocationService] (real); [NoopLocationService]
/// (test fake — returns whatever was injected).
class PhoneFix {
  const PhoneFix({
    required this.latitude,
    required this.longitude,
    this.altitudeMeters,
    this.fixAt,
  });
  final double latitude;
  final double longitude;

  /// When the platform says it measured this, or null when it does not say.
  ///
  /// `Geolocator` answers with its cached position when the chip has not had a
  /// new fix, and without this the app could not tell "you are here" from "this
  /// is where you were when the phone last knew": a reader saw a position from
  /// two days ago presented as their current one.
  final DateTime? fixAt;

  /// Altitude above the WGS-84 reference ellipsoid, in meters.
  /// Null when the platform didn't report a usable altitude (no
  /// barometric / GPS-derived altitude available).
  final double? altitudeMeters;
}

/// Why a one-shot fix request produced no position.
///
/// `GeolocatorLocationService` used to collapse every one of these into
/// a bare `null` from `catch (_)`, so a caller could not tell "the user
/// never granted location" from "cold GPS indoors" — and the call sites
/// that never asked for the permission themselves got nothing, with no
/// prompt and no explanation.
enum LocationFailure {
  /// Location is switched off in the OS settings. No permission level
  /// can produce a fix until the user turns it back on.
  servicesDisabled,

  /// The user declined the runtime permission (the OS may still prompt
  /// again later).
  permissionDenied,

  /// The user declined and chose "don't ask again" — only the OS
  /// settings page can change this.
  permissionDeniedForever,

  /// No fix inside `timeLimit` (indoors, cold start).
  timeout,

  /// The platform threw something else.
  failed,
}

/// A one-shot fix request that reports *why* it failed. Exactly one of
/// [fix] / [failure] is non-null.
class LocationOutcome {
  const LocationOutcome.ok(PhoneFix this.fix) : failure = null;
  const LocationOutcome.error(LocationFailure this.failure) : fix = null;

  final PhoneFix? fix;
  final LocationFailure? failure;

  bool get isOk => fix != null;
}

abstract class LocationService {
  /// Returns a single fix, or `null` if the device says it can't
  /// produce one. Convenience over [requestFix] for callers that
  /// cannot explain the failure anyway; prefer [requestFix] when they
  /// can. Never prompts — this is the background/periodic entry point.
  Future<PhoneFix?> currentFix({Duration timeLimit});

  /// R22 / U13 — a single fix, reporting *why* it produced none.
  ///
  /// With [prompt] (the default) the runtime location permission is
  /// requested just-in-time when the user has not decided yet. The
  /// request lives here rather than at the call sites: a one-shot fix
  /// that cannot ask is not usable, every caller would have to
  /// remember to ask first, and most did not (the region suggester and
  /// the elevation profile just called `currentFix` and treated the
  /// resulting null as "no GPS").
  ///
  /// Pass `prompt: false` from paths with no UI. A periodic timer
  /// cannot show a dialog, and an unattended request on Android is
  /// suppressed or re-shown on every tick. Those callers get
  /// [LocationFailure.permissionDenied] instead of a prompt.
  Future<LocationOutcome> requestFix({Duration timeLimit, bool prompt});

  /// A long-running stream of fixes that emits only when the user
  /// has moved more than [distanceFilterMeters] from the last
  /// emitted point. Returns an empty stream on platforms or test
  /// fakes that can't deliver it. Used by R36 auto-publish's
  /// "smart broadcast" mode. Callers must cancel the subscription
  /// when done.
  Stream<PhoneFix> positionStream({required int distanceFilterMeters});
}

/// Real implementation backed by `geolocator`. Uses high accuracy
/// with a default 15 s cap; callers can override.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<PhoneFix?> currentFix(
          {Duration timeLimit = const Duration(seconds: 15)}) async =>
      (await requestFix(timeLimit: timeLimit, prompt: false)).fix;

  @override
  Future<LocationOutcome> requestFix({
    Duration timeLimit = const Duration(seconds: 15),
    bool prompt = true,
  }) async {
    try {
      // Service-enabled check (location off in OS settings → no fix
      // is possible no matter how many perms we have).
      final bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        return const LocationOutcome.error(
            LocationFailure.servicesDisabled);
      }
      // Just-in-time permission. Android reports plain `denied` while
      // the user has not been asked yet, so this is the one place the
      // prompt appears; `deniedForever` is only returned once they
      // have said no permanently, and we must not re-prompt then.
      // `prompt: false` (background callers) skips the ask and reports
      // the denial instead.
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && prompt) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        return const LocationOutcome.error(
            LocationFailure.permissionDeniedForever);
      }
      if (perm == LocationPermission.denied) {
        return const LocationOutcome.error(
            LocationFailure.permissionDenied);
      }
      final Position p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeLimit,
        ),
      );
      // Only treat altitude as meaningful when the platform reports
      // a non-zero altitudeAccuracy — otherwise we'd surface 0 m
      // for users whose GPS chips don't supply altitude data.
      final double? alt =
          p.altitudeAccuracy > 0 ? p.altitude : null;
      return LocationOutcome.ok(PhoneFix(
        latitude: p.latitude,
        longitude: p.longitude,
        altitudeMeters: alt,
        fixAt: p.timestamp.isUtc ? p.timestamp : p.timestamp.toUtc(),
      ));
    } on TimeoutException {
      // Geolocator throws TimeoutException when `timeLimit` elapses.
      return const LocationOutcome.error(LocationFailure.timeout);
    } catch (_) {
      return const LocationOutcome.error(LocationFailure.failed);
    }
  }

  @override
  Stream<PhoneFix> positionStream({required int distanceFilterMeters}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        // `medium` accuracy is plenty for distance-filter
        // triggering and dramatically cheaper than `high`.
        accuracy: LocationAccuracy.medium,
        distanceFilter: distanceFilterMeters,
      ),
    ).map((Position p) {
      final double? alt =
          p.altitudeAccuracy > 0 ? p.altitude : null;
      return PhoneFix(
        latitude: p.latitude,
        longitude: p.longitude,
        altitudeMeters: alt,
      );
    });
  }
}

/// Test/default fake — never touches the platform layer. Set
/// [next] to control what the next call returns. Tests can also
/// emit synthetic stream events via [emit].
class NoopLocationService implements LocationService {
  NoopLocationService({
    this.next,
    this.failure = LocationFailure.servicesDisabled,
  });

  /// The fix the next call returns. When null, [failure] is returned.
  PhoneFix? next;

  /// Why the next call has no fix. Ignored while [next] is set.
  LocationFailure failure;

  int callCount = 0;
  int? lastDistanceFilter;

  /// How many of the [callCount] requests would have shown the OS
  /// permission prompt. Lets a test assert that a background path
  /// (`currentFix`) never asks while an interactive one does.
  int promptCount = 0;

  final StreamController<PhoneFix> _streamCtrl =
      StreamController<PhoneFix>.broadcast();

  @override
  Future<PhoneFix?> currentFix({Duration? timeLimit}) async =>
      (await requestFix(timeLimit: timeLimit, prompt: false)).fix;

  @override
  Future<LocationOutcome> requestFix(
      {Duration? timeLimit, bool prompt = true}) async {
    callCount++;
    if (prompt) promptCount++;
    final PhoneFix? f = next;
    if (f != null) return LocationOutcome.ok(f);
    return LocationOutcome.error(failure);
  }

  @override
  Stream<PhoneFix> positionStream({required int distanceFilterMeters}) {
    lastDistanceFilter = distanceFilterMeters;
    return _streamCtrl.stream;
  }

  /// Push a synthetic fix through the stream — tests use this to
  /// simulate the user moving past the distance filter.
  void emit(PhoneFix fix) => _streamCtrl.add(fix);
}
