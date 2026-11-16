// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';

void main() {
  late DateTime now;
  late PlaceReportBudget budget;

  setUp(() {
    now = DateTime.utc(2026, 11, 5, 12);
    budget = PlaceReportBudget(clock: () => now);
  });

  void send() => budget.take();

  test('six in an hour are allowed', () {
    for (int i = 0; i < 6; i++) {
      expect(budget.take().allowed, isTrue, reason: 'report ${i + 1}');
      now = now.add(const Duration(minutes: 6));
    }
    expect(budget.sentInLastHour, 6);
  });

  test('the seventh in an hour is refused, with the time it frees', () {
    for (int i = 0; i < 6; i++) {
      send();
      now = now.add(const Duration(minutes: 6));
    }
    final DateTime firstSend = DateTime.utc(2026, 11, 5, 12);
    final PlaceReportDecision decision = budget.check();
    expect(decision.allowed, isFalse);
    expect(decision.sentInLastHour, 6);
    expect(decision.allowedAt,
        firstSend.add(PlaceReportBudget.hourWindow));
  });

  test('the third inside five minutes is refused, with the burst time', () {
    final DateTime first = now;
    expect(budget.take().allowed, isTrue);
    now = now.add(const Duration(minutes: 1));
    expect(budget.take().allowed, isTrue);
    now = now.add(const Duration(minutes: 1));
    final PlaceReportDecision third = budget.take();
    expect(third.allowed, isFalse);
    expect(third.allowedAt,
        first.add(PlaceReportBudget.burstWindow));
  });

  test('the burst window slides: the first report leaving it frees one slot',
      () {
    final DateTime first = now;
    send();
    now = now.add(const Duration(minutes: 1));
    send();
    now = first.add(const Duration(minutes: 4, seconds: 59));
    expect(budget.check().allowed, isFalse);
    now = first.add(const Duration(minutes: 5, seconds: 1));
    // One of the two is now outside the burst window, so one is allowed; the
    // hourly count is still 2, far from six.
    expect(budget.check().allowed, isTrue);
  });

  test('the hour window rolls, not the clock hour', () {
    final DateTime first = now;
    for (int i = 0; i < 6; i++) {
      send();
      now = now.add(const Duration(minutes: 9));
    }
    expect(budget.check().allowed, isFalse);
    now = first.add(const Duration(hours: 1, seconds: 1));
    expect(budget.check().allowed, isTrue);
  });

  test('check never spends, take does', () {
    budget.check();
    budget.check();
    expect(budget.sentInLastHour, 0);
    budget.take();
    expect(budget.sentInLastHour, 1);
  });

  test('reset forgets the history', () {
    send();
    send();
    budget.reset();
    expect(budget.sentInLastHour, 0);
    expect(budget.check().allowed, isTrue);
  });
}
