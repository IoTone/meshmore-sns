// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/media/media_journal.dart';

/// L10 — a transfer the process killed mid-send is reported on the next launch
/// instead of vanishing with no trace.
void main() {
  setUp(MediaJournal.reset);
  tearDown(MediaJournal.reset);

  test('a started transfer that never finished is reported as interrupted',
      () async {
    MediaJournal.override = <int>{};
    await MediaJournal.markStarted(41);
    await MediaJournal.markStarted(42);
    await MediaJournal.markFinished(42);

    expect(await MediaJournal.interrupted(), <int>[41]);
  });

  test('a finished transfer leaves nothing behind', () async {
    MediaJournal.override = <int>{};
    await MediaJournal.markStarted(7);
    await MediaJournal.markFinished(7);

    expect(await MediaJournal.interrupted(), isEmpty);
  });

  test('reading does not clear the record, acknowledging does', () async {
    MediaJournal.override = <int>{9};
    expect((await MediaJournal.interrupted()).length, 1);
    expect((await MediaJournal.interrupted()).length, 1,
        reason: 'the caller decides when the notice has been shown');

    await MediaJournal.forget(<int>[9]);
    expect(await MediaJournal.interrupted(), isEmpty);
  });

  test('the notifier counts, and clears on acknowledge', () async {
    final MediaInterruptions notice =
        MediaInterruptions(initial: <int>{1, 2});
    expect(notice.any, isTrue);
    expect(notice.count, 2);

    MediaJournal.override = <int>{1, 2};
    await notice.acknowledge();
    expect(notice.any, isFalse);
    expect(await MediaJournal.interrupted(), isEmpty);
  });
}
