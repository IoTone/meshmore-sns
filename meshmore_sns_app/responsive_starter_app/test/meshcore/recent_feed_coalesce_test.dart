// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';

void main() {
  group('the recent feed reads as state, not as a poll log', () {
    late FakeMeshcoreTransport fake;
    late MeshcoreController ctrl;

    setUp(() async {
      fake = FakeMeshcoreTransport(connected: true);
      ctrl = MeshcoreController(transportFactory: () async => fake);
      await ctrl.connect();
      fake.emit(selfInfoFrame());
      for (int i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    });

    tearDown(() => ctrl.dispose());

    test('an unchanged battery reading refreshes one row instead of adding one',
        () async {
      final int before = ctrl.recentEvents.length;
      fake.emit(batteryFrame(4030));
      await Future<void>.delayed(Duration.zero);
      final int afterFirst = ctrl.recentEvents.length;
      expect(afterFirst, greaterThan(before),
          reason: 'the first reading is news');
      fake.emit(batteryFrame(4030));
      await Future<void>.delayed(Duration.zero);
      fake.emit(batteryFrame(4030));
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.recentEvents.length, afterFirst,
          reason: 'the same reading three times is one line');
    });

    test('a changed reading is a new row', () async {
      fake.emit(batteryFrame(4030));
      await Future<void>.delayed(Duration.zero);
      final int first = ctrl.recentEvents.length;
      fake.emit(batteryFrame(3990));
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.recentEvents.length, first + 1,
          reason: 'a battery that dropped is a fact worth a new row');
    });
  });
}
