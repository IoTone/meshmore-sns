// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/maps/cardinal_click.dart';

/// A click at each quarter turn, and never at a wobble.
///
/// The owner's phrasing was exact: fire as the phone turns *across* a 90° mark,
/// not while a hand sits on one and not on a full rotation. Both halves are the
/// same question — a click is a statement that the bearing has changed quarter —
/// so the interesting cases are the boundaries, not the middles.
void main() {
  test('a settled reading is not a crossing', () {
    final CardinalClick c = CardinalClick();
    expect(c.update(0), isFalse, reason: 'the first reading is the start');
    expect(c.update(1), isFalse);
    expect(c.update(2), isFalse);
  });

  test('crossing north fires once, past the mark', () {
    final CardinalClick c = CardinalClick();
    c.update(350); // quarter 3
    expect(c.update(355), isFalse);
    expect(c.update(359), isFalse, reason: 'still inside the hysteresis band');
    expect(c.update(2), isFalse, reason: 'two degrees past — too close to call');
    expect(c.update(6), isTrue, reason: 'now plainly in the new quarter');
    expect(c.update(10), isFalse, reason: 'a crossing fires once');
  });

  test('a hand that wobbles on a mark fires nothing', () {
    final CardinalClick c = CardinalClick();
    c.update(80);
    for (final double h in <double>[89, 90, 91, 90, 89, 88, 89.5, 90.5]) {
      expect(c.update(h), isFalse, reason: 'wobble at $h deg must be silent');
    }
  });

  test('each quarter fires as it is crossed', () {
    final CardinalClick c = CardinalClick();
    c.update(0);
    final List<double> headings = <double>[20, 60, 96, 130, 186, 240, 276, 330];
    final List<bool> fired = <bool>[
      for (final double h in headings) c.update(h),
    ];
    expect(fired,
        <bool>[false, false, true, false, true, false, true, false],
        reason: 'east, south and west each fired once as they were crossed');
  });

  test('turning back the other way fires too', () {
    final CardinalClick c = CardinalClick();
    c.update(0);
    expect(c.update(86), isFalse, reason: 'east is at 90, and not yet crossed');
    expect(c.update(94), isTrue, reason: 'east, going clockwise');
    expect(c.update(86), isTrue, reason: 'back across east, anticlockwise');
    expect(c.update(6), isFalse, reason: 'north is at 0/360, not crossed yet');
    expect(c.update(354), isTrue, reason: 'and back across north');
  });

  test('a full rotation fires at each mark it passes', () {
    final CardinalClick c = CardinalClick();
    c.update(0);
    int clicks = 0;
    for (double h = 0; h <= 360; h += 1) {
      if (c.update(h)) clicks++;
    }
    // Three, not four: a turn that starts on north has already passed north, so
    // the marks it crosses are east, south and west.
    expect(clicks, 3);

    // Started a quarter turn in, a full circle crosses all four.
    final CardinalClick d = CardinalClick();
    d.update(45);
    int again = 0;
    for (double h = 45; h <= 405; h += 1) {
      if (d.update(h)) again++;
    }
    expect(again, 4);
  });

  test('a heading is normalised, so negatives work', () {
    final CardinalClick c = CardinalClick();
    c.update(-10); // 350°, which is quarter 3
    expect(c.update(6), isTrue, reason: 'crossed north into quarter 0');
    expect(c.update(40), isFalse, reason: '40° is the same quarter as 6°');
    expect(c.update(-86), isTrue,
        reason: '-86° is 274°, which is a quarter after 40° and back across '
            'north and west');
  });
}
