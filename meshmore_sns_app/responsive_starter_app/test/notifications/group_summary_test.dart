// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/gen/app_localizations_en.dart';
import 'package:meshmore_sns_app/gen/app_localizations_ja.dart';
import 'package:meshmore_sns_app/notifications/local_notifier.dart';

/// The group summary is the row a thumb hits on a busy mesh. Before this it was
/// Android's auto-summary, which carries no payload, so a tap landed on whatever
/// thread was last open: measured on the phone by tapping "2 · Message on
/// Public" and arriving in #cos.
void main() {
  final AppLocalizationsEn en = AppLocalizationsEn();

  test('a summary tap carries the newest message, not nothing', () {
    final ({int count, String payload, String body}) s = groupSummaryFor(
      recentPayloads: <String>['ch:1', 'dm:aa', 'ch:2'],
      newestPayload: 'ch:2',
      newestBody: 'St. Joseph: Good morning!',
      strings: en,
    );
    expect(s.payload, 'ch:2', reason: 'the message the summary just described');
    expect(s.count, 3);
    expect(s.body, contains('3 messages'));
    expect(s.body, contains('St. Joseph: Good morning!'));
  });

  test('one message reads as one message, not "1 messages"', () {
    final ({int count, String payload, String body}) s = groupSummaryFor(
      recentPayloads: const <String>['ch:4'],
      newestPayload: 'ch:4',
      newestBody: 'Morning',
      strings: en,
    );
    expect(s.count, 1);
    expect(s.body, '1 message · Morning');
  });

  test('an empty history still yields a usable summary', () {
    // The first message of a session arrives after the app restarted, so the
    // recent list can be empty while the summary is being written.
    final ({int count, String payload, String body}) s = groupSummaryFor(
      recentPayloads: const <String>[],
      newestPayload: 'ch:9',
      newestBody: 'Hello',
      strings: en,
    );
    expect(s.count, 1);
    expect(s.payload, 'ch:9');
    expect(s.body, contains('Hello'));
  });

  test('the summary follows the device language', () {
    final AppLocalizationsJa ja = AppLocalizationsJa();
    final ({int count, String payload, String body}) s = groupSummaryFor(
      recentPayloads: const <String>['ch:1', 'ch:2'],
      newestPayload: 'ch:2',
      newestBody: 'おはよう',
      strings: ja,
    );
    expect(s.body, contains('2 件'));
    expect(s.body, contains('おはよう'));
    expect(s.body, isNot(contains('messages')));
  });

  test('the notifier posts the summary under its own id', () {
    // The id must sit outside the per-message range the controller picks, or a
    // summary would replace a message's notification.
    expect(LocalNotifier.summaryId, 0);
    expect(LocalNotifier.summaryId, lessThan(1));
  });
}
