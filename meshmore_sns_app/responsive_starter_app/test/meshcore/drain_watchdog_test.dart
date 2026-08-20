// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // The step cap only advances when frames ARRIVE. If the radio goes
  // quiet after a SYNC — link wedged, firmware busy, unit carried out
  // of range mid-drain — nothing calls back and `_draining` would stay
  // true forever. That silently mutes advert cues and stops R59's bot
  // answering, with no visible symptom.
  testWidgets('a drain that stalls is timed out, not left running',
      (WidgetTester t) async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pump();

    fake.emit(msgsWaitingFrame());
    await t.pump();
    expect(mc.isDraining, isTrue);

    // The radio says nothing more, ever.
    await t.pump(const Duration(seconds: 25));
    expect(mc.isDraining, isFalse,
        reason: 'the watchdog must end a stalled drain');

    mc.dispose();
  });

  testWidgets('the stall window is silence since the last SYNC',
      (WidgetTester t) async {
    // A long but healthy drain must not be cut short: each answered
    // SYNC re-arms the timer.
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pump();

    fake.emit(msgsWaitingFrame());
    await t.pump();

    for (int i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 15)); // under the window
      fake.emit(channelMsgFrame(idx: 1, text: 'queued $i'));
      await t.pump();
      expect(mc.isDraining, isTrue,
          reason: 'still answering, so still draining (step $i)');
    }

    fake.emit(noMoreMessagesFrame());
    await t.pump();
    expect(mc.isDraining, isFalse);

    mc.dispose();
  });

  testWidgets('a completed drain leaves no timer behind',
      (WidgetTester t) async {
    // A live timer at teardown fails the test, which is the assertion
    // here: the watchdog must be cancelled when the queue empties.
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pump();

    fake.emit(msgsWaitingFrame());
    await t.pump();
    fake.emit(noMoreMessagesFrame());
    await t.pump();

    expect(mc.isDraining, isFalse);
    mc.dispose();
    await t.pump();
  });
}
