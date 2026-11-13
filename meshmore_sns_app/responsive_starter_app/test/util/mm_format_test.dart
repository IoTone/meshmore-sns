// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/util/mm_format.dart';

/// Units and clocks, in one formatter.
///
/// The app had no such setting: distances were metres and kilometres in six
/// places and temperatures were Celsius everywhere, so a reader who thinks in
/// miles converted in their head. The numbers here are the contract the screens
/// rely on, including the rounding a person would say out loud.
void main() {
  final FormatPrefs metric = FormatPrefs();
  final FormatPrefs imperial =
      FormatPrefs(units: DistanceUnits.imperial, celsius: false, clock24: false);

  group('distance', () {
    test('metric rounds to ten metres, then to km', () {
      expect(MmFormat.distance(0, prefs: metric), '0 m');
      expect(MmFormat.distance(1247, prefs: metric), '1.2 km');
      expect(MmFormat.distance(24, prefs: metric), '20 m');
      expect(MmFormat.distance(24999, prefs: metric), '25 km');
    });

    test('imperial is feet, then miles', () {
      expect(MmFormat.distance(30.48, prefs: imperial), '100 ft');
      expect(MmFormat.distance(1609.344, prefs: imperial), '1.0 mi');
      expect(MmFormat.distance(16093.44, prefs: imperial), '10 mi');
    });

    test('nothing sensible to say reads as a dash', () {
      expect(MmFormat.distance(null, prefs: metric), '—');
      expect(MmFormat.distance(double.nan, prefs: metric), '—');
      expect(MmFormat.distance(double.infinity, prefs: metric), '—');
    });

    test('a dial step keeps the number the caller chose', () {
      // A ring label is already a round step; rounding it again to ten would
      // turn 250 m into 250 m and 1500 m into 1 km.
      expect(MmFormat.step(250, prefs: metric), '250 m');
      expect(MmFormat.step(1500, prefs: metric), '1 km');
      expect(MmFormat.step(304.8, prefs: imperial), '1000 ft');
    });
  });

  group('temperature', () {
    test('celsius by default, fahrenheit on request', () {
      expect(MmFormat.temperature(21, prefs: metric), '21 °C');
      expect(MmFormat.temperature(21, prefs: imperial), '70 °F');
      expect(MmFormat.temperature(-40, prefs: imperial), '-40 °F');
      expect(MmFormat.temperature(null, prefs: metric), '—');
    });
  });

  group('clock', () {
    test('24-hour by default, with padded hours', () {
      expect(MmFormat.clock(DateTime(2026, 1, 1, 9, 5), prefs: metric),
          '09:05');
      expect(MmFormat.clock(DateTime(2026, 1, 1, 14, 32), prefs: metric),
          '14:32');
    });

    test('12-hour on request, with midnight and noon named right', () {
      expect(MmFormat.clock(DateTime(2026, 1, 1, 14, 32), prefs: imperial),
          '2:32 PM');
      expect(MmFormat.clock(DateTime(2026, 1, 1, 0, 7), prefs: imperial),
          '12:07 AM');
      expect(MmFormat.clock(DateTime(2026, 1, 1, 12, 0), prefs: imperial),
          '12:00 PM');
    });
  });

  test('the prefs persist what was chosen', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesTestShim.install();
    final FormatPrefs prefs = FormatPrefs();
    await prefs.load();
    expect(prefs.units, DistanceUnits.metric, reason: 'metric is the default');
    expect(prefs.clock24, isTrue);
    await prefs.setUnits(DistanceUnits.imperial);
    await prefs.setClock24(false);
    await prefs.setCelsius(false);
    expect(prefs.units, DistanceUnits.imperial);
    expect(prefs.clock24, isFalse);
    expect(prefs.celsius, isFalse);

    // And a fresh instance reads them back.
    final FormatPrefs again = FormatPrefs();
    await again.load();
    expect(again.units, DistanceUnits.imperial);
    expect(again.clock24, isFalse);
    expect(again.celsius, isFalse);
  });
}

abstract final class SharedPreferencesTestShim {
  static void install() =>
      SharedPreferences.setMockInitialValues(<String, Object>{});
}
