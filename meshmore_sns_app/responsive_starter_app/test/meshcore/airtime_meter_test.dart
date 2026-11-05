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
}
