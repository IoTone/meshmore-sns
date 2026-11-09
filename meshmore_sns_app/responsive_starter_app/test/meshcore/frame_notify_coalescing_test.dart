// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// A burst of frames must not rebuild the UI once per frame.
///
/// Forty-three widgets watch the whole controller, and every inbound frame used
/// to notify all of them. A contact sync of 350 nodes therefore meant 350
/// rebuilds of every mounted watcher in a few seconds, which is the jank a user
/// reads as "the app is busy". The controller notifies on the leading edge of a
/// burst and then at most once per 50 ms window, with a trailing notify so the
/// final state still renders.
///
/// The exception is a frame somebody is *waiting* on: a command answer, a send
/// confirmation, the self-info handshake. Those notify synchronously, because a
/// listener (the SOS watchdog, the CLI path) reacts to them and a 50 ms delay
/// would be the app looking slower than it is. That halves the rule into two
/// cases, and both are asserted below.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
      'a hundred frames in one burst notify a handful of times, and the last '
      'one still lands', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    int notifications = 0;
    mc.addListener(() => notifications++);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);
    expect(notifications, greaterThanOrEqualTo(1),
        reason:
            'a single frame must notify immediately, not wait for a window');
    final int afterFirst = notifications;

    // 100 battery pushes back to back: one burst, so they share a window.
    for (int mv = 3000; mv < 3100; mv++) {
      fake.emit(batteryFrame(mv));
    }
    await Future<void>.delayed(Duration.zero);
    final int burstNotifications = notifications - afterFirst;
    expect(burstNotifications, lessThan(20),
        reason: 'coalesced: 100 frames must not mean 100 rebuilds');

    // The trailing notify carries the last state.
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(mc.batteryMillivolts, 3099,
        reason: 'the final frame is still applied');
    expect(notifications, greaterThan(afterFirst),
        reason: 'the burst ends with a notify, so the last state renders');
    mc.dispose();
  });

  test('a frame somebody is waiting on notifies even mid-burst', () async {
    // The battery stream is coalesced; an ERR is not. A burst must not delay
    // the frame a caller is blocked on.
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    int notifications = 0;
    mc.addListener(() => notifications++);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);
    for (int mv = 3000; mv < 3010; mv++) {
      fake.emit(batteryFrame(mv));
    }
    await Future<void>.delayed(Duration.zero);
    final int duringBurst = notifications;
    fake.emit(Uint8List.fromList(<int>[0x01, 3])); // ERR, immediately
    await Future<void>.delayed(Duration.zero);
    expect(notifications, greaterThan(duringBurst),
        reason: 'a command answer must not wait for the burst window');
    expect(mc.framesDropped, 0);
    mc.dispose();
  });

  test('a single frame after a quiet window notifies at once', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    int notifications = 0;
    mc.addListener(() => notifications++);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final int before = notifications;
    fake.emit(batteryFrame(3300));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(notifications, before + 1,
        reason: 'nothing is coalesced when nothing is in flight, and one frame '
            'is one rebuild');
    mc.dispose();
  });
}
