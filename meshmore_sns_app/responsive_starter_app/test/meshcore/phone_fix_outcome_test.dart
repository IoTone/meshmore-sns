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

  test('currentFix and requestFix agree (one platform round-trip each)',
      () async {
    // `currentFix` is the compatibility shim the background paths still
    // use; it must be the same request, not a second platform call.
    final NoopLocationService loc = NoopLocationService(
      next: const PhoneFix(latitude: 1, longitude: 2),
    );
    expect(await loc.currentFix(), isNotNull);
    expect(loc.callCount, 1);

    final NoopLocationService denied =
        NoopLocationService(failure: LocationFailure.timeout);
    expect(await denied.currentFix(), isNull);
    expect(denied.callCount, 1);
  });
}