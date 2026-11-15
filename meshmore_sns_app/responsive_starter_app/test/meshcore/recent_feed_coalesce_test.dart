// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/mesh_event.dart';
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

    test('two state kinds that alternate still collapse', () async {
      // The radio polls battery and self-info on the same timer, so on the
      // handset the feed alternated and no two CONSECUTIVE rows were identical:
      // the consecutive-only collapse never fired and the feed read as a poll
      // log. Matching on the last row of the same kind fixes it.
      final int before = ctrl.recentEvents.length;
      for (int i = 0; i < 3; i++) {
        fake.emit(batteryFrame(4030));
        await Future<void>.delayed(Duration.zero);
        fake.emit(selfInfoFrame());
        await Future<void>.delayed(Duration.zero);
      }
      // At most one new row per kind, whatever the order they arrive in.
      expect(ctrl.recentEvents.length, lessThanOrEqualTo(before + 2),
          reason: 'a repeating pair is two lines, not six');
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
    test('a contact sync is one line, not one per contact', () async {
      // The radio streams its whole table on connect, one frame per contact, so
      // a 350-entry table wrote 350 rows in the same second and buried every
      // message the feed exists to show.
      final int before = ctrl.recentEvents.length;
      for (int i = 0; i < 6; i++) {
        fake.emit(contactFrame(name: 'Node $i'));
        await Future<void>.delayed(Duration.zero);
      }
      final int added = ctrl.recentEvents.length - before;
      expect(added, lessThanOrEqualTo(1),
          reason: 'six contacts in a row is one line about the table');
      final List<MeshEvent> feed = ctrl.recentEvents;
      if (added == 1) {
        expect(feed.first.kind, MeshEventKind.contactBatch);
        expect(feed.first.args['count'], '6');
      }
    });
  });
}

