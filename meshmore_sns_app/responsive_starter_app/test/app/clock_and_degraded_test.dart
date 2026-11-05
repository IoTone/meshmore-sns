// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/app/degraded_state.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/util/clock_model.dart';

/// APP-N3 / APP-N4 — the three clocks are kept apart, and the four degraded
/// states are named rather than discovered.
void main() {
  final AppLocalizations l = lookupAppLocalizations(const Locale('en'));
  final DateTime now = DateTime(2026, 11, 5, 12);

  group('time model', () {
    test('a radio that never had its clock set reads as unknown', () {
      final ClockReading r = ClockReading.radio(0);
      expect(r.unset, isTrue);
      expect(r.isUsable, isFalse);
      expect(clockText(l, r, now: now), l.clockUnknown);
    });

    test('a radio power cycle resets the clock and the time goes unknown', () {
      expect(clockText(l, ClockReading.radio(0), now: now), l.clockUnknown);
      // The same radio after the app sets the clock again reads as a time.
      final ClockReading set =
          ClockReading.radio(now.millisecondsSinceEpoch ~/ 1000);
      expect(clockText(l, set, now: now), l.clockJustNow);
    });

    test('a phone clock that jumped backwards shows an age, not a future date',
        () {
      final ClockReading r = ClockReading.message(
        now.add(const Duration(minutes: 30)),
        now: now,
      );
      expect(r.allowsAbsolute, isFalse);
      expect(clockText(l, r, now: now), contains('30'));
    });

    test('relative ages are rendered from the reader clock', () {
      expect(clockText(l, ClockReading.message(now.subtract(const Duration(minutes: 9)), now: now), now: now), contains('9'));
      expect(clockText(l, ClockReading.message(now.subtract(const Duration(hours: 3)), now: now), now: now), contains('3'));
      expect(clockText(l, ClockReading.message(now.subtract(const Duration(days: 2)), now: now), now: now), contains('2'));
    });

    test('only a reading that agrees with the phone may be shown as absolute',
        () {
      expect(ClockReading.phone(now).allowsAbsolute, isTrue);
      expect(
          ClockReading.message(now.add(const Duration(minutes: 5)), now: now)
              .allowsAbsolute,
          isFalse);
      expect(ClockReading.radio(0).allowsAbsolute, isFalse);
    });
  });

  group('degraded states', () {
    test('a healthy app has no banner', () {
      final DegradedState s = DegradedState.observe(
        connected: true,
        radioAnswering: true,
        storageFull: false,
        clockUnset: false,
        batteryMilliVolts: 4100,
      );
      expect(s.isDegraded, isFalse);
      expect(s.text(l), isEmpty);
    });

    test('each state has its own sentence and keeps the rest usable', () {
      final Map<DegradedMode, String> copy = <DegradedMode, String>{
        for (final DegradedMode m in DegradedMode.values)
          m: DegradedState(<DegradedMode>{m}).text(l),
      };
      for (final String t in copy.values) {
        expect(t.trim(), isNotEmpty);
      }
      expect(copy.values.toSet().length, DegradedMode.values.length,
          reason: 'two states share one sentence');
      expect(copy[DegradedMode.radioDown], contains('stays readable'));
      expect(copy[DegradedMode.storageFull], contains('Nothing was deleted'));
    });

    test('all four can be active at once, most consequential first', () {
      final DegradedState s = DegradedState.observe(
        connected: false,
        radioAnswering: false,
        storageFull: true,
        clockUnset: true,
        batteryMilliVolts: kCriticalBatteryMilliVolts,
      );
      expect(s.modes.length, 4);
      final String text = s.text(l);
      expect(text.indexOf(l.degradedRadioDown),
          lessThan(text.indexOf(l.degradedStorageFull)));
      expect(text.indexOf(l.degradedStorageFull),
          lessThan(text.indexOf(l.degradedClockUnset)));
    });

    test('an unreported battery is not a critical battery', () {
      expect(
          DegradedState.observe(
            connected: true,
            radioAnswering: true,
            storageFull: false,
            clockUnset: false,
            batteryMilliVolts: 0,
          ).modes,
          isEmpty);
      expect(
          DegradedState.observe(
            connected: true,
            radioAnswering: true,
            storageFull: false,
            clockUnset: false,
            batteryMilliVolts: null,
          ).modes,
          isEmpty);
    });
  });
}
