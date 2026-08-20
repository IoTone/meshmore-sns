// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/bot/bot_guards.dart';

final DateTime t0 = DateTime.utc(2026, 1, 1, 12);

void main() {
  group('R59 machine output is labelled', () {
    test('the marker goes on the wire, not just in our transcript', () {
      // The human on the other end must be able to tell what a machine
      // wrote, and they are not reading our UI.
      expect(labelAsBot('pong 1'), '[bot] pong 1');
    });

    test('labelled traffic is recognised, including with leading space', () {
      expect(looksLikeBot('[bot] hello'), isTrue);
      expect(looksLikeBot('   [bot] hello'), isTrue);
      expect(looksLikeBot('hello'), isFalse);
      expect(looksLikeBot('this is not a [bot] message'), isFalse);
    });

    // The loop breaker is the marker: two bots each see the other's
    // label and both decline, so the ping-pong cannot start.
    test('a bot recognises its own output shape', () {
      expect(looksLikeBot(labelAsBot('anything')), isTrue);
    });
  });

  group('R59 airtime guards', () {
    test('the first reply is always allowed', () {
      final BotThrottle th = BotThrottle();
      expect(th.checkAt(t0), isNull);
    });

    test('a reply inside the minimum interval is refused', () {
      final BotThrottle th = BotThrottle(
          limit: const BotRateLimit(minInterval: Duration(seconds: 10)));
      th.recordAt(t0);
      expect(th.checkAt(t0.add(const Duration(seconds: 9))),
          BotSuppression.minInterval);
      expect(th.checkAt(t0.add(const Duration(seconds: 10))), isNull);
    });

    test('the window budget is enforced, then recovers as it slides', () {
      final BotThrottle th = BotThrottle(
        limit: const BotRateLimit(
          minInterval: Duration.zero,
          maxPerWindow: 3,
          window: Duration(minutes: 10),
        ),
      );
      for (int i = 0; i < 3; i++) {
        expect(th.checkAt(t0.add(Duration(seconds: i))), isNull);
        th.recordAt(t0.add(Duration(seconds: i)));
      }
      expect(th.checkAt(t0.add(const Duration(seconds: 4))),
          BotSuppression.windowBudget);

      // Once the oldest reply falls out of the window, budget returns.
      expect(th.checkAt(t0.add(const Duration(minutes: 10, seconds: 1))),
          isNull);
    });

    // A bot that has gone quiet should be able to say why, rather than
    // leaving the operator to read logs.
    test('remaining budget is visible and never negative', () {
      final BotThrottle th = BotThrottle(
        limit: const BotRateLimit(
            minInterval: Duration.zero, maxPerWindow: 2),
      );
      expect(th.remainingAt(t0), 2);
      th.recordAt(t0);
      expect(th.remainingAt(t0), 1);
      th.recordAt(t0);
      expect(th.remainingAt(t0), 0);
      th.recordAt(t0); // over budget
      expect(th.remainingAt(t0), 0, reason: 'clamped, not negative');
    });

    test('minInterval and windowBudget are distinguishable', () {
      final BotThrottle th = BotThrottle(
        limit: const BotRateLimit(
          minInterval: Duration(seconds: 30),
          maxPerWindow: 1,
        ),
      );
      th.recordAt(t0);
      // Inside the interval AND over budget — interval is reported
      // first because it is the one that will clear soonest.
      expect(th.checkAt(t0.add(const Duration(seconds: 1))),
          BotSuppression.minInterval);
      expect(th.checkAt(t0.add(const Duration(minutes: 1))),
          BotSuppression.windowBudget);
    });

    test('reset clears history', () {
      final BotThrottle th = BotThrottle(
          limit: const BotRateLimit(maxPerWindow: 1));
      th.recordAt(t0);
      expect(th.remainingAt(t0), 0);
      th.reset();
      expect(th.remainingAt(t0), 1);
    });
  });

  group('R59 soak counters', () {
    // The difference between "no replies because nothing arrived" and
    // "no replies because the budget was spent" has to be readable
    // after the fact, or a soak run is a vibe rather than evidence.
    test('each suppression reason lands in its own bucket', () {
      final BotCounters c = BotCounters();
      c.countSuppression(BotSuppression.ownMessage);
      c.countSuppression(BotSuppression.loopBreaker);
      c.countSuppression(BotSuppression.minInterval);
      c.countSuppression(BotSuppression.windowBudget);
      c.countSuppression(BotSuppression.noMatch);

      expect(c.suppressedOwn, 1);
      expect(c.suppressedLoop, 1);
      expect(c.suppressedRate, 2, reason: 'both rate reasons share a bucket');
      expect(c.noMatch, 1);
    });

    test('counters round-trip for export', () {
      final BotCounters c = BotCounters()
        ..received = 10
        ..replied = 7
        ..suppressedOwn = 1
        ..suppressedLoop = 1
        ..suppressedRate = 1;
      final BotCounters back = BotCounters.fromJson(c.toJson());
      expect(back.toJson(), c.toJson());
    });

    test('a missing field reads as zero, not a crash', () {
      final BotCounters back =
          BotCounters.fromJson(<String, Object?>{'received': 3});
      expect(back.received, 3);
      expect(back.replied, 0);
    });

    test('reset zeroes everything', () {
      final BotCounters c = BotCounters()
        ..received = 5
        ..replied = 5;
      c.reset();
      expect(c.toJson().values, everyElement(0));
    });
  });
}
