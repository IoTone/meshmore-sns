// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';

/// Airtime nobody asked for.
///
/// The telemetry poller asked every eligible peer for readings every ten
/// seconds whenever the app was *foregrounded* — the chat tab included — and each
/// answer costs channel time on a mesh everybody shares. Interest is a screen
/// saying it is showing readings, not the app being open.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// Only the frames the poller sends. The connect handshake (app start, contact
  /// and channel probes) is still landing when the test starts, so asserting on
  /// the whole outbox would be asserting on the connect path instead.
  List<List<int>> telemetryRequests(FakeMeshcoreTransport fake) => <List<int>>[
        for (final Uint8List f in fake.sent)
          if (f.isNotEmpty && f[0] == 0x27) f.toList(),
      ];

  Future<(MeshcoreController, FakeMeshcoreTransport)> ready() async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await mc.connect();
    fake.emit(selfInfoFrame());
    // Let the connect path finish its own frames — app start, contact and
    // channel probes, and the one self-telemetry ask — so what the test counts
    // afterwards is the poller's traffic and nothing else.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    fake.sent.clear();
    return (mc, fake);
  }

  test('no interest means no telemetry request, however long the app is open',
      () async {
    final (MeshcoreController mc, FakeMeshcoreTransport fake) = await ready();
    // Drive the poller's tick directly: the timer is a minute now, and a test
    // that waits a minute is a test nobody runs.
    mc.debugStepTelemetryPoll();
    await Future<void>.delayed(Duration.zero);
    expect(telemetryRequests(fake), isEmpty,
        reason: 'the app was open and nothing on screen showed readings');
    mc.dispose();
  });

  test('interest makes it ask, and releasing the interest stops it', () async {
    final (MeshcoreController mc, FakeMeshcoreTransport fake) = await ready();
    // A *contact* with a learned route: an advert has no path, so the poller
    // correctly refuses to poll it (tier -1). One hop at one byte per hop is
    // tier 1, the cheapest tier, which is what gets asked first.
    fake.emit(contactFrame(
        name: 'R1', firstPubByte: 40, outPathLen: 1, path: <int>[0x40]));
    // The contact has to be in the node table before the poller looks.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    mc.holdTelemetryInterest();
    mc.debugStepTelemetryPoll();
    // The request is fired and not awaited, so the frame lands a microtask
    // later; asserting before it would test the scheduler, not the poller.
    await Future<void>.delayed(Duration.zero);
    expect(telemetryRequests(fake), isNotEmpty,
        reason: 'a screen showing readings may ask for them');
    fake.sent.clear();
    mc.releaseTelemetryInterest();
    mc.debugStepTelemetryPoll();
    await Future<void>.delayed(Duration.zero);
    expect(telemetryRequests(fake), isEmpty,
        reason: 'the readings screen went away');
    mc.dispose();
  });

  test('nested interests are refcounted', () async {
    final (MeshcoreController mc, FakeMeshcoreTransport fake) = await ready();
    mc.holdTelemetryInterest();
    mc.holdTelemetryInterest();
    mc.releaseTelemetryInterest();
    expect(mc.telemetryInterest, isTrue,
        reason: 'one holder still wants readings');
    mc.releaseTelemetryInterest();
    expect(mc.telemetryInterest, isFalse);
    fake.sent.clear();
    mc.debugStepTelemetryPoll();
    await Future<void>.delayed(Duration.zero);
    expect(telemetryRequests(fake), isEmpty);
    mc.dispose();
  });
}
