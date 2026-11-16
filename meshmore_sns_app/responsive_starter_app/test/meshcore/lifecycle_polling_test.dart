// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';

import 'package:meshmore_sns_app/field/position_history.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';

/// L7/L8/L9 — the app stops spending wake-ups and airtime while it is not on
/// screen, and picks both up again on resume.
void main() {
  testWidgets('the position recorder samples every five seconds, and not at '
      'all while the app is off screen', (WidgetTester tester) async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport();
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
    );
    final PositionRecorder rec = PositionRecorder(mc: mc, persist: false);

    rec.start();
    await tester.pump(const Duration(seconds: 4));
    expect(rec.ticks, 0, reason: 'one second was the old cadence');

    await tester.pump(const Duration(seconds: 1));
    expect(rec.ticks, 1);
    expect(PositionRecorder.sampleEvery, const Duration(seconds: 5));

    rec.setVisible(false);
    await tester.pump(const Duration(seconds: 30));
    expect(rec.ticks, 1, reason: 'a backgrounded app must not keep waking up');

    rec.setVisible(true);
    await tester.pump(const Duration(seconds: 5));
    expect(rec.ticks, 2);

    rec.dispose();
    mc.dispose();
  });

  testWidgets('battery polling stops while the app is off screen',
      (WidgetTester tester) async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );

    await ctrl.connect();
    fake.emit(selfInfoFrame());
    await tester.pump();

    final Uint8List battery = MeshcoreFrameCodec.getBatteryStorage();
    int batteryFrames() =>
        fake.sent.where((Uint8List f) => _same(f, battery)).length;

    final int atReady = batteryFrames();
    await tester.pump(const Duration(seconds: 61));
    expect(batteryFrames(), greaterThan(atReady),
        reason: 'the poll runs while the app is visible');

    ctrl.setVisible(false);
    final int atPause = batteryFrames();
    await tester.pump(const Duration(seconds: 180));
    expect(batteryFrames(), atPause,
        reason: 'a frame a minute off a shared band, for nobody');

    ctrl.setVisible(true);
    expect(batteryFrames(), greaterThan(atPause),
        reason: 'resuming asks once immediately rather than waiting a minute');

    ctrl.dispose();
    await tester.pump();
  });
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
