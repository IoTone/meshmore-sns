// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/sos/sos_schedule.dart';

void main() {
  final DateTime raisedAt = DateTime.utc(2026, 11, 5, 12);

  group('the SOS schedule', () {
    test('twelve sends, one a minute, from the raise', () {
      final List<SosPacket> plan = SosSchedule.plan(raisedAt: raisedAt);
      final List<SosPacket> sends =
          plan.where((SosPacket p) => p.kind == SosPacketKind.send).toList();
      expect(sends, hasLength(12));
      for (int i = 0; i < 12; i++) {
        expect(sends[i].index, i + 1);
        expect(sends[i].dueAt,
            raisedAt.add(Duration(seconds: 60 * i)),
            reason: 'send ${i + 1} is at t=${60 * i}s');
      }
      // The last send is at 660 s, and the beacons start after it so the two
      // never coincide (this is the arithmetic D8.4's parenthetical missed).
      expect(sends.last.dueAt, raisedAt.add(const Duration(seconds: 660)));
    });

    test('ten beacons every five minutes, starting at 720 s', () {
      final List<SosPacket> beacons = SosSchedule.plan(raisedAt: raisedAt)
          .where((SosPacket p) => p.kind == SosPacketKind.beacon)
          .toList();
      expect(beacons, hasLength(10));
      for (int i = 0; i < 10; i++) {
        expect(beacons[i].index, i + 1);
        expect(beacons[i].dueAt,
            raisedAt.add(Duration(seconds: 720 + 300 * i)),
            reason: 'beacon ${i + 1} is at t=${720 + 300 * i}s');
      }
      expect(beacons.last.dueAt, raisedAt.add(const Duration(seconds: 3420)));
    });

    test('nothing is scheduled at or after the hard stop', () {
      final DateTime stop = SosSchedule.hardStopAt(raisedAt);
      expect(stop, raisedAt.add(const Duration(seconds: 3600)));
      for (final SosPacket p in SosSchedule.plan(raisedAt: raisedAt)) {
        expect(p.dueAt.isBefore(stop), isTrue);
      }
    });

    test('22 packets over 57 minutes, which is the budget the copy quotes', () {
      final List<SosPacket> plan = SosSchedule.plan(raisedAt: raisedAt);
      expect(plan, hasLength(SosSchedule.packetCount));
      expect(SosSchedule.packetCount, 22);
      expect(
        plan.last.dueAt.difference(plan.first.dueAt),
        const Duration(seconds: 3420),
      );
    });

    test('jitter stays inside three seconds and keeps the order', () {
      for (int seed = 0; seed < 20; seed++) {
        final List<SosPacket> plan =
            SosSchedule.plan(raisedAt: raisedAt, random: Random(seed));
        final List<SosPacket> sends =
            plan.where((SosPacket p) => p.kind == SosPacketKind.send).toList();
        for (int i = 0; i < sends.length; i++) {
          final Duration drift = sends[i].dueAt.difference(
              raisedAt.add(Duration(seconds: 60 * i)));
          expect(drift.inSeconds.abs(), lessThanOrEqualTo(3));
          if (i > 0) {
            expect(sends[i].dueAt.isAfter(sends[i - 1].dueAt), isTrue);
          }
        }
        // Beacons are already five minutes apart; they are not jittered.
        final List<SosPacket> beacons =
            plan.where((SosPacket p) => p.kind == SosPacketKind.beacon).toList();
        expect(beacons.first.dueAt,
            raisedAt.add(const Duration(seconds: 720)));
      }
    });

    test('one plan is immutable, so a caller cannot reorder the schedule', () {
      final List<SosPacket> plan = SosSchedule.plan(raisedAt: raisedAt);
      expect(() => plan.add(plan.first), throwsUnsupportedError);
    });
  });
}
