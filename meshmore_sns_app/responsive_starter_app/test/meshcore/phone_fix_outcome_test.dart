// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_connection.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/own_location.dart';
import 'package:meshmore_sns_app/perms/location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MeshcoreController controllerWith(NoopLocationService loc) =>
      MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport(connected: true),
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
        locationService: loc,
      );

  test('a denied location permission is reported as a denial, not as "no fix"',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final NoopLocationService loc =
        NoopLocationService(failure: LocationFailure.permissionDenied);
    final MeshcoreController ctrl = controllerWith(loc);

    final LocationOutcome outcome = await ctrl.requestPhoneLocationFixOutcome();
    expect(outcome.isOk, isFalse);
    expect(outcome.failure, LocationFailure.permissionDenied);
    expect(outcome.fix, isNull);

    expect(await ctrl.requestPhoneLocationFix(), isFalse);
    expect(ctrl.phoneLocationFix, isNull,
        reason: 'a failed request must not cache anything');
    ctrl.dispose();
  });

  test('every failure reason survives the trip out to the caller', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    for (final LocationFailure f in <LocationFailure>[
      LocationFailure.servicesDisabled,
      LocationFailure.permissionDenied,
      LocationFailure.permissionDeniedForever,
      LocationFailure.timeout,
      LocationFailure.failed,
    ]) {
      final MeshcoreController ctrl =
          controllerWith(NoopLocationService(failure: f));
      final LocationOutcome outcome = await ctrl.requestPhoneLocationFixOutcome();
      expect(outcome.failure, f,
          reason: '$f must reach the UI, which words each one differently');
      ctrl.dispose();
    }
  });

  test('a successful request caches the fix as the phone own-location',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final NoopLocationService loc = NoopLocationService(
      next: const PhoneFix(
          latitude: 38.920045, longitude: -104.772826, altitudeMeters: 2000),
    );
    final MeshcoreController ctrl = controllerWith(loc);

    expect(await ctrl.requestPhoneLocationFix(), isTrue);
    final OwnLocation? own = ctrl.phoneLocationFix;
    expect(own, isNotNull);
    expect(own!.latitude, closeTo(38.920045, 1e-9));
    expect(own.longitude, closeTo(-104.772826, 1e-9));
    expect(own.altitudeMeters, 2000);
    expect(own.source, OwnLocationSource.phoneFix);
    ctrl.dispose();
  });

  test('the interactive path prompts, the background path never does',
      () async {
    // `currentFix` is the timer/stream entry point used by auto-publish.
    // It must not prompt: the periodic publish runs with no UI, and an
    // unattended Android request is either suppressed or re-shown on
    // every tick. `requestFix` is the interactive path and must prompt.
    final NoopLocationService loc = NoopLocationService(
      next: const PhoneFix(latitude: 1, longitude: 2),
    );
    expect(await loc.currentFix(), isNotNull);
    expect(loc.callCount, 1);
    expect(loc.promptCount, 0,
        reason: 'currentFix must never ask for the permission');

    expect((await loc.requestFix()).isOk, isTrue);
    expect(loc.callCount, 2);
    expect(loc.promptCount, 1, reason: 'requestFix is the one that prompts');

    // Explicit opt-out also works, and is what a timer path can use to
    // get the reason without a dialog.
    expect((await loc.requestFix(prompt: false)).isOk, isTrue);
    expect(loc.promptCount, 1);
  });

  test('a background request reports the denial instead of prompting',
      () async {
    final NoopLocationService loc =
        NoopLocationService(failure: LocationFailure.permissionDenied);
    expect(await loc.currentFix(), isNull);
    expect(loc.promptCount, 0);
    final LocationOutcome o = await loc.requestFix(prompt: false);
    expect(o.failure, LocationFailure.permissionDenied);
    expect(loc.promptCount, 0);
  });
}