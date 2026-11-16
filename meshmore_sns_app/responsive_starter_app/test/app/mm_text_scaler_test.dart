// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/app/mm_text_scaler.dart';

/// L12 — the app's text scale multiplies the platform curve and is capped, so
/// an OS maximum times the in-app 1.6 cannot reach 3.2x.
void main() {
  test('the user multiplier applies on top of the platform scale', () {
    const MmTextScaler scaler =
        MmTextScaler(os: TextScaler.noScaling, user: 1.3);
    expect(scaler.scale(10), closeTo(13, 0.001));
    expect(scaler.scale(14), closeTo(18.2, 0.001));
  });

  test('the platform curve is kept rather than flattened to one factor', () {
    // A curve scales large text less than small text; a linear rebuild from
    // scale(1.0) would make these two ratios equal.
    const TextScaler curve = _HalvingAboveTwenty();
    const MmTextScaler scaler = MmTextScaler(os: curve, user: 1.0);
    expect(scaler.scale(10), 10);
    expect(scaler.scale(40), 30,
        reason: 'the curve, not a single factor, decides the ratio: 0.75 at '
            '40 px against 1.0 at 10 px');
  });

  test('the product is capped at the tested maximum', () {
    const MmTextScaler scaler =
        MmTextScaler(os: TextScaler.linear(2.0), user: 1.6);
    expect(scaler.scale(14), 28,
        reason: '2.0 x 1.6 would be 44.8, which no layout here supports');
  });

  test('a small OS scale with a large user scale stays under the cap', () {
    const MmTextScaler scaler =
        MmTextScaler(os: TextScaler.linear(0.85), user: 1.6);
    expect(scaler.scale(20), closeTo(27.2, 0.001));
  });

  test('equality follows the three inputs, so MediaQuery does not rebuild',
      () {
    const MmTextScaler a =
        MmTextScaler(os: TextScaler.linear(1.2), user: 1.1);
    const MmTextScaler b =
        MmTextScaler(os: TextScaler.linear(1.2), user: 1.1);
    const MmTextScaler c =
        MmTextScaler(os: TextScaler.linear(1.2), user: 1.3);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });

  testWidgets('capped text lays out at 320 dp without overflow',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: MmTextScaler(os: TextScaler.linear(2.0), user: 1.6),
        ),
        child: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(8),
            child: Text('Mesh survey · 12 nodes · 3 in range · 1 h 20 m'),
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
  });
}

/// A platform curve: anything above 20 scales at half rate. Stands in for
/// Android 14's non-linear scaling, which a single factor cannot express.
class _HalvingAboveTwenty extends TextScaler {
  const _HalvingAboveTwenty();

  @override
  double scale(double fontSize) =>
      fontSize <= 20 ? fontSize : 20 + (fontSize - 20) / 2;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => scale(1.0);
}
