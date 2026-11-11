// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/screens/dashboards/hyperlocal_dashboard.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';

/// The radar's own text used to ignore text size entirely.
///
/// The callouts drew at a literal 11.5 and the north letter at a literal 10, so
/// the in-app font setting and the Android scale both passed them by: at 2.0
/// text every label around the dial grew while the dial's own names stayed put.
/// The width was also a character-count estimate, which put the ellipsis in the
/// wrong place for any glyph that was not average.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TextPainter painter(String text, double size, {double? maxWidth}) =>
      radarCalloutPainter(
        text: text,
        size: size,
        monoFamily: 'monospace',
        color: const Color(0xFFFFFFFF),
        maxWidth: maxWidth,
      );

  test('the size it is given is the size it draws at', () {
    // The skin's steps, which is what the painter now receives.
    for (final double size in <double>[10, 11, 14.3, 22]) {
      final TextPainter tp = painter('HELTEC', size);
      expect(tp.text!.style!.fontSize, size);
    }
  });

  test('a name wider than the gutter is cut at the gutter, not by a guess', () {
    const double gutter = 40;
    final TextPainter tp = painter('A-VERY-LONG-REPEATER-NAME', 11,
        maxWidth: gutter);
    expect(tp.width, lessThanOrEqualTo(gutter),
        reason: 'the callout overran the gutter it was given');
    expect(tp.didExceedMaxLines, isTrue,
        reason: 'a name too long for the gutter must be ellipsised');
  });

  test('a name that fits is left alone', () {
    final TextPainter tp = painter('B2', 11, maxWidth: 120);
    expect(tp.didExceedMaxLines, isFalse);
    expect(tp.width, lessThanOrEqualTo(120));
  });

  test('a larger text step makes the same name wider', () {
    // Which is the whole point: the callout now tracks the scale instead of
    // standing still while everything around it grows.
    final double small = painter('REPEATER-1', 11).width;
    final double large = painter('REPEATER-1', 22).width;
    expect(large, greaterThan(small * 1.5));
  });

  test("the dial draws its own text at the skin's steps, not a literal", () {
    // 11.5 and 10 were the literals; sizeSm/sizeMicro are the roles. A skin
    // that multiplies its whole scale moves the radar with it.
    const MmType base = MmType(monoFamily: 'monospace');
    final ({double callout, double north}) plain = radarLabelSizes(base);
    expect(plain.callout, base.sizeSm);
    expect(plain.north, base.sizeMicro);

    const MmType scaled = MmType(monoFamily: 'monospace', typeScale: 1.4);
    final ({double callout, double north}) big = radarLabelSizes(scaled);
    expect(big.callout, greaterThan(plain.callout));
    expect(big.north, greaterThan(plain.north));
  });
}
