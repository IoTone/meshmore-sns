// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';

import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/own_location.dart';
import 'package:meshmore_sns_app/perms/location_service.dart';

import 'fake_transport.dart';

/// Our own position has to keep moving with the phone.
///
/// The map's anchor, the radar's centre and every distance in the app read
/// `ownLocation`, and the only things that ever wrote it were an on-demand fix
/// and the auto-publish controller — off by default. So a phone carried two
/// kilometres with the map open kept drawing itself where it started, which is
/// the owner's "the location is not updating live".
void main() {
  test('a streamed fix replaces the cached one', () async {
    final NoopLocationService location = NoopLocationService();
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      locationService: location,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    addTearDown(mc.dispose);

    mc.startOwnLocationStream();
    expect(mc.ownLocationStreamRunning, isTrue);

    location.emit(const PhoneFix(latitude: 47.61, longitude: -122.33));
    await Future<void>.delayed(Duration.zero);

    final OwnLocation? own = mc.ownLocation;
    expect(own, isNotNull);
    expect(own!.latitude, closeTo(47.61, 1e-6));
    expect(own.source, OwnLocationSource.phoneFix);

    // A second fix moves it: this is the whole point.
    location.emit(const PhoneFix(latitude: 47.62, longitude: -122.34));
    await Future<void>.delayed(Duration.zero);
    expect(mc.ownLocation!.latitude, closeTo(47.62, 1e-6));
  });

  test('starting twice does not open two streams', () async {
    final NoopLocationService location = NoopLocationService();
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      locationService: location,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    addTearDown(mc.dispose);
    mc.startOwnLocationStream();
    mc.startOwnLocationStream();
    expect(mc.ownLocationStreamRunning, isTrue);
    await mc.stopOwnLocationStream();
    expect(mc.ownLocationStreamRunning, isFalse);
  });

  test('a fix that arrives after disposal is not delivered', () async {
    final NoopLocationService location = NoopLocationService();
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      locationService: location,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    mc.startOwnLocationStream();
    mc.dispose();
    // No throw, no notify on a disposed controller.
    location.emit(const PhoneFix(latitude: 1, longitude: 2));
    await Future<void>.delayed(Duration.zero);
  });
}
