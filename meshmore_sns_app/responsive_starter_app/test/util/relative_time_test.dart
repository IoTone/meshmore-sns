// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/util/relative_time.dart';

/// One ladder, six screens.
///
/// The thresholds here were copied between six widgets, and one of the copies
/// was not localized at all. These cases pin the boundaries as facts rather
/// than as whatever the copy in front of you happens to do, and pin that each
/// family still speaks in its own words.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Duration s = Duration(seconds: 1);
  const Duration min = Duration(minutes: 1);
  const Duration h = Duration(hours: 1);
  const Duration d = Duration(days: 1);

  group('readAge', () {
    test('a fresh age is seconds, counted whole', () {
      expect(readAge(Duration.zero), const AgeReading(AgeBand.seconds, 0));
      expect(readAge(s * 59), const AgeReading(AgeBand.seconds, 59));
    });

    test('a minute starts at sixty seconds, not before', () {
      expect(readAge(s * 59), const AgeReading(AgeBand.seconds, 59));
      expect(readAge(s * 60), const AgeReading(AgeBand.minutes, 1));
      expect(readAge(min * 59 + s * 59), const AgeReading(AgeBand.minutes, 59));
    });

    test('an hour starts at sixty minutes, and a day at twenty-four hours', () {
      expect(readAge(min * 60), const AgeReading(AgeBand.hours, 1));
      expect(readAge(h * 23 + min * 59), const AgeReading(AgeBand.hours, 23));
      expect(readAge(h * 24), const AgeReading(AgeBand.days, 1));
      expect(readAge(d * 7), const AgeReading(AgeBand.days, 7));
    });

    test(
        'a fold turns the first ninety seconds into now, and nothing past '
        'that', () {
      const Duration fold = Duration(seconds: 90);
      expect(readAge(Duration.zero, nowUnder: fold),
          const AgeReading(AgeBand.now, 0));
      expect(readAge(s * 89, nowUnder: fold), const AgeReading(AgeBand.now, 0));
      // 90 s is the fold's boundary, and it is already a minute.
      expect(readAge(s * 90, nowUnder: fold),
          const AgeReading(AgeBand.minutes, 1));
    });

    test('a clock that ran backwards reads as now, never as a negative count',
        () {
      expect(readAge(-s * 30), const AgeReading(AgeBand.now, 0));
      expect(readAge(-d * 3, nowUnder: const Duration(seconds: 90)),
          const AgeReading(AgeBand.now, 0));
      expect(compactAgo(-s * 30), '0s');
    });
  });

  group('families', () {
    late AppLocalizations l;
    setUpAll(() async {
      l = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('the device family folds a moment into now and speaks in minutes', () {
      expect(deviceAgo(l, s * 10), 'just now');
      expect(deviceAgo(l, min * 5), '5 min ago');
      expect(deviceAgo(l, h * 2), '2 h ago');
      expect(deviceAgo(l, d * 3), '3 d ago');
    });

    test('the node family keeps whole seconds', () {
      expect(nodeAgo(l, s * 12), '12s ago');
      expect(nodeAgo(l, min * 5), '5 min ago');
    });

    test('the docs family has no seconds band: anything under a minute is now',
        () {
      expect(docsAgo(l, null), 'just now');
      expect(docsAgo(l, s * 12), 'just now');
      expect(docsAgo(l, min * 5), '5m ago');
    });

    test(
        'the weather family stops at hours, because a reading older than a '
        'day is stale rather than old', () {
      expect(weatherAgo(l, s * 12), '12s ago');
      expect(weatherAgo(l, min * 5), '5m ago');
      expect(weatherAgo(l, h * 2), '2h ago');
      expect(weatherAgo(l, d * 2), '48h ago');
    });

    test('the compact form is the row glyph, and it has no English in it', () {
      expect(compactAgo(s * 12), '12s');
      expect(compactAgo(min * 3), '3m');
      expect(compactAgo(h * 2), '2h');
      expect(compactAgo(d * 2), '2d');
    });
  });

  test('ageSinceUnix treats the firmware\'s zero as an age, not as 1970', () {
    final DateTime now = DateTime.fromMillisecondsSinceEpoch(1000000 * 1000);
    expect(ageSinceUnix(0, now: now), Duration.zero);
    expect(ageSinceUnix(-5, now: now), Duration.zero);
    expect(ageSinceUnix(1000000 - 3600, now: now), const Duration(hours: 1));
  });
}
