// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/sos/checkin.dart';
import 'package:meshmore_sns_app/sos/sos_message.dart';

void main() {
  final DateTime raisedAt = DateTime.utc(2026, 11, 5, 12);
  final DateTime until = raisedAt.add(const Duration(hours: 3));
  final List<int> key = List<int>.generate(32, (int i) => i);

  Checkin checkin({DateTime? fixAt}) => Checkin(
        id: 'a1b2c3',
        nonce: List<int>.filled(16, 4),
        callsign: 'W1ABC',
        raisedAt: raisedAt,
        until: until,
        lat: 39.7392,
        lon: -104.9903,
        fixAt: fixAt ?? raisedAt,
      );

  test('one send: the text is built once and carries the deadline', () {
    DateTime now = raisedAt;
    final CheckinWatch w =
        CheckinWatch(checkin: checkin(), clock: () => now);
    final ({String? text, SosMessageRefusal? refusal}) t = w.text();
    expect(t.refusal, isNull);
    expect(t.text, startsWith('[CHK:a1b2c3] 39.7392,-104.9903 W1ABC until '));
    expect(w.state, CheckinState.pending);
    w.markSent();
    expect(w.state, CheckinState.watching);
    // A second markSent cannot send again: the state machine has no path from
    // watching back to pending.
    w.markSent();
    expect(w.state, CheckinState.watching);
  });

  test('the app marks it overdue at the deadline, not before', () {
    DateTime now = raisedAt;
    final CheckinWatch w =
        CheckinWatch(checkin: checkin(), clock: () => now)..markSent();
    now = until.subtract(const Duration(seconds: 1));
    w.tick();
    expect(w.state, CheckinState.watching);
    now = until;
    w.tick();
    expect(w.state, CheckinState.overdue);
  });

  test('an answer before the deadline closes it', () {
    DateTime now = raisedAt;
    final CheckinWatch w =
        CheckinWatch(checkin: checkin(), clock: () => now)..markSent();
    expect(w.recordAnswer(direct: true, fromKey: key), CheckinState.answered);
    expect(w.answer, CheckinAnswer.directKey);
    expect(w.answerKey, key);
    now = until.add(const Duration(minutes: 1));
    w.tick();
    expect(w.state, CheckinState.answered, reason: 'an answer is not re-lost');
  });

  test('an answer after the deadline is recorded over an overdue row', () {
    DateTime now = raisedAt;
    final CheckinWatch w =
        CheckinWatch(checkin: checkin(), clock: () => now)..markSent();
    now = until.add(const Duration(minutes: 5));
    w.tick();
    expect(w.state, CheckinState.overdue);
    w.recordAnswer(direct: false);
    expect(w.answer, CheckinAnswer.claimedOnChannel);
    expect(w.state, CheckinState.overdue,
        reason: 'the deadline passed; an answer later does not un-pass it');
  });

  test('a stale fix sends NOFIX, so a late responder is not sent to it', () {
    DateTime now = raisedAt.add(const Duration(hours: 2));
    final CheckinWatch w = CheckinWatch(
      checkin: checkin(fixAt: raisedAt.subtract(const Duration(minutes: 90))),
      clock: () => now,
    );
    final ({String? text, SosMessageRefusal? refusal}) t = w.text();
    expect(t.text, contains('NOFIX'));
    expect(t.text, isNot(contains('39.7392')));
    expect(t.text, contains('until '));
  });

  test('a check-in whose deadline is already past cannot be answered as a live one', () {
    DateTime now = raisedAt;
    final CheckinWatch w = CheckinWatch(
      checkin: Checkin(
        id: 'a1b2c3',
        nonce: List<int>.filled(16, 4),
        callsign: 'W1ABC',
        raisedAt: raisedAt,
        until: raisedAt.subtract(const Duration(minutes: 1)),
      ),
      clock: () => now,
    )..markSent();
    now = raisedAt;
    w.tick();
    expect(w.state, CheckinState.overdue);
  });
}
