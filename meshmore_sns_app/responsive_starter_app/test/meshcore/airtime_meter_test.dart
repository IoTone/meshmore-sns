// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/meshcore/airtime.dart';
import 'package:meshmore_sns_app/meshcore/airtime_meter.dart';

/// A clock a test can move, so an hour costs microseconds.
final class _Clock {
  _Clock(this.now);
  DateTime now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  group('the rolling window', () {
    test('a charge is spent and room shrinks by it', () {
      final _Clock c = _Clock(DateTime.utc(2026, 11, 5, 12));
      final AirtimeMeter m = AirtimeMeter(clock: () => c.now);
      expect(m.budget, const Duration(seconds: 36));
      expect(m.spent, Duration.zero);

      m.charge(const Duration(seconds: 10));

      expect(m.spent, const Duration(seconds: 10));
      expect(m.remaining, const Duration(seconds: 26));
    });

    test('a charge falls out of the window after an hour, and not before', () {
      final _Clock c = _Clock(DateTime.utc(2026, 11, 5, 12));
      final AirtimeMeter m = AirtimeMeter(clock: () => c.now);
      m.charge(const Duration(seconds: 10));

      c.advance(const Duration(minutes: 59));
      expect(m.spent, const Duration(seconds: 10),
          reason: 'a charge made 59 minutes ago is still inside the hour');

      c.advance(const Duration(minutes: 1));
      expect(m.spent, Duration.zero,
          reason: 'the window is the last 3600 s, not a calendar hour');
    });

    test('a backwards clock cannot strand a charge in the future', () {
      final _Clock c = _Clock(DateTime.utc(2026, 11, 5, 12));
      final AirtimeMeter m = AirtimeMeter(clock: () => c.now);
      m.charge(const Duration(seconds: 5));
      c.advance(const Duration(minutes: -30));

      expect(m.spent, Duration.zero);
      expect(m.remaining, const Duration(seconds: 36));
    });

    test('an unlimited policy still measures but never refuses', () {
      final AirtimeMeter m = AirtimeMeter(initialPolicy: AirtimePolicy.ownedChannel);
      final AirtimeSpend s = m.quote(const Duration(minutes: 5));
      expect(s.allowed, isTrue);
      expect(s.budget, isNull);
      expect(s.remaining, isNull);
      m.charge(const Duration(minutes: 5));
      expect(m.spent, const Duration(minutes: 5),
          reason: 'ownedChannel means no cap, not no measurement');
    });
  });

  group('a burst that exhausts the window', () {
    test('the frame that does not fit is refused, with the numbers', () {
      final _Clock c = _Clock(DateTime.utc(2026, 11, 5, 12));
      final AirtimeMeter m = AirtimeMeter(clock: () => c.now);

      // 36 s of allowance, 4 s per frame: nine fit, the tenth does not.
      for (int i = 0; i < 9; i++) {
        final AirtimeSpend q = m.quote(const Duration(seconds: 4));
        expect(q.allowed, isTrue, reason: 'frame ${i + 1} of nine fits');
        m.charge(q.needed);
      }

      final AirtimeSpend tenth = m.quote(const Duration(seconds: 4));
      expect(tenth.allowed, isFalse);
      expect(tenth.remaining, Duration.zero,
          reason: 'the refusal says how much room is left, which is none');
      expect(m.spent, const Duration(seconds: 36),
          reason: 'a refused frame is never charged');

      c.advance(const Duration(hours: 1));
      expect(m.quote(const Duration(seconds: 4)).allowed, isTrue,
          reason: 'the window resets by itself an hour later');
    });

    test('a refund undoes a charge for a write that threw', () {
      final AirtimeMeter m = AirtimeMeter();
      m.charge(const Duration(seconds: 2));
      m.refund(const Duration(seconds: 2));
      expect(m.spent, Duration.zero);
    });
  });

  group('the per-radio estimator', () {
    test('a decoded self-info gives the exact LoRa estimate', () {
      final AirtimeEstimator? e = loraEstimator(
          bandwidthKhz: 62.5, spreadingFactor: 8, codingRate: 8);
      expect(e, isNotNull);
      // A 176-byte record on 62.5 kHz / SF8 / CR8 is ~1.65 s.
      expect(e!.forBytes(176).inMilliseconds, greaterThan(1400));
    });

    test('an implausible parameter is refused rather than guessed', () {
      expect(loraEstimator(bandwidthKhz: 0, spreadingFactor: 8, codingRate: 5),
          isNull);
      expect(loraEstimator(bandwidthKhz: 62.5, spreadingFactor: 3, codingRate: 5),
          isNull);
      expect(loraEstimator(bandwidthKhz: 62.5, spreadingFactor: 8, codingRate: 9),
          isNull);
    });

    test('the fallback is the documented flat figure', () {
      final AirtimeEstimator e = airtimeEstimatorFor(null);
      expect(e.forBytes(176), const Duration(milliseconds: 704));
    });
  });

  group('the rolling hour survives a restart', () {
    test('a snapshot restores the same window, not a fresh one', () {
      final _Clock c = _Clock(DateTime.utc(2026, 11, 5, 12));
      final AirtimeMeter first = AirtimeMeter(clock: () => c.now)
        ..charge(const Duration(seconds: 12))
        ..charge(const Duration(seconds: 5));
      final String snap = first.snapshot();
      expect(snap, isNotEmpty);

      // A second process, same clock, reads the file back.
      final AirtimeMeter second = AirtimeMeter(clock: () => c.now);
      expect(second.restore(snap), 0, reason: 'nothing malformed');
      expect(second.spent, const Duration(seconds: 17));
      expect(second.remaining, const Duration(seconds: 19));
      // And it keeps charging on top rather than starting again.
      second.charge(const Duration(seconds: 1));
      expect(second.spent, const Duration(seconds: 18));
    });

    test('a snapshot from hours ago restores as nothing', () {
      final _Clock c = _Clock(DateTime.utc(2026, 11, 5, 12));
      final AirtimeMeter old = AirtimeMeter(clock: () => c.now)
        ..charge(const Duration(seconds: 30));
      final String snap = old.snapshot();
      // Two hours later the window has moved on entirely.
      c.advance(const Duration(hours: 2));
      final AirtimeMeter fresh = AirtimeMeter(clock: () => c.now);
      expect(fresh.restore(snap), 0);
      expect(fresh.spent, Duration.zero);
    });

    test('a malformed part is counted and skipped, never guessed at', () {
      final _Clock c = _Clock(DateTime.utc(2026, 11, 5, 12));
      final int minute = c.now.millisecondsSinceEpoch ~/ 60000;
      final AirtimeMeter m = AirtimeMeter(clock: () => c.now);
      final int dropped = m.restore('nonsense,:12,$minute:1500,$minute:2500,9:-4');
      expect(dropped, 3);
      expect(m.spent, const Duration(milliseconds: 4000),
          reason: 'two good parts for one minute add up');
    });

    test('an empty or absent snapshot is an empty window', () {
      final AirtimeMeter m = AirtimeMeter(clock: () => DateTime.utc(2026, 11, 5));
      expect(m.restore(null), 0);
      expect(m.spent, Duration.zero);
      expect(m.snapshot(), isEmpty);
    });
  });

  group('the policy a band\'s own rule calls for', () {
    test('902-928 MHz has no duty cycle, so the default caps nothing', () {
      // The US/Canada preset sits here. A courtesy cap applied over a band with
      // no rule refuses sends the firmware permits, which is the defect the
      // other radio project removed on 2026-11-08.
      expect(AirtimePolicy.defaultForBand(910.525),
          AirtimePolicy.ownedChannel);
      expect(AirtimePolicy.defaultForBand(902.0),
          AirtimePolicy.ownedChannel);
      expect(AirtimePolicy.defaultForBand(928.0),
          AirtimePolicy.ownedChannel);
      expect(AirtimePolicy.defaultForBand(927.9),
          AirtimePolicy.ownedChannel);
    });

    test('the EU/UK sub-bands keep the voluntary one percent', () {
      expect(AirtimePolicy.defaultForBand(868.1),
          AirtimePolicy.onePercentDutyCycle);
      expect(AirtimePolicy.defaultForBand(869.525),
          AirtimePolicy.onePercentDutyCycle);
      expect(AirtimePolicy.defaultForBand(433.5),
          AirtimePolicy.onePercentDutyCycle);
      // Just outside the US band is not the US band.
      expect(AirtimePolicy.defaultForBand(901.9),
          AirtimePolicy.onePercentDutyCycle);
      expect(AirtimePolicy.defaultForBand(928.1),
          AirtimePolicy.onePercentDutyCycle);
    });

    test('no radio yet means the stricter answer', () {
      expect(AirtimePolicy.defaultForBand(null),
          AirtimePolicy.onePercentDutyCycle);
    });

    test('a capped policy still measures, and an uncapped one still counts', () {
      final _Clock c = _Clock(DateTime.utc(2026, 11, 5, 12));
      final AirtimeMeter m = AirtimeMeter(
          clock: () => c.now, initialPolicy: AirtimePolicy.ownedChannel);
      expect(m.budget, isNull);
      expect(m.remaining, isNull);
      expect(m.quote(const Duration(minutes: 5)).allowed, isTrue);
      m.charge(const Duration(seconds: 20));
      expect(m.spent, const Duration(seconds: 20),
          reason: 'no cap is not no meter');
    });
  });
}
