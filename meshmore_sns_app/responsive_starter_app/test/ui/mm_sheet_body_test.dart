// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/ui/mm_components.dart';

/// A sheet that contains a filter opens the keyboard over itself.
///
/// `showModalBottomSheet(isScrollControlled: true)` anchors to the bottom of the
/// window and ignores `viewInsets`, so the answers a user filtered for end up
/// under the keyboard where no tap can reach them. On the handset the Ping
/// target sheet narrowed to HELTEC-REP and HELTEC-BASE and neither row could be
/// chosen; the sheet looked broken and was only covered. `MmSheetBody` is the
/// one place that lifts a sheet's body above the keyboard, and this is the
/// measurement of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Key bodyKey = ValueKey<String>('sheet-body');

  Future<Rect> pumpBody(
    WidgetTester t, {
    required double keyboard,
    required double childHeight,
  }) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        // No Scaffold: a Scaffold consumes the bottom inset itself, which is
        // exactly what a modal sheet above it does NOT do.
        child: Material(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: MmSheetBody(
              child: SizedBox(key: bodyKey, height: childHeight),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    return t.getRect(find.byKey(bodyKey));
  }

  testWidgets('the body ends where the keyboard starts', (WidgetTester t) async {
    final Rect r = await pumpBody(t, keyboard: 300, childHeight: 200);
    expect(r.bottom, lessThanOrEqualTo(800 - 300),
        reason: 'a row below this line cannot be tapped');
  });

  testWidgets('with no keyboard the body uses the whole screen',
      (WidgetTester t) async {
    final Rect r = await pumpBody(t, keyboard: 0, childHeight: 200);
    expect(r.bottom, 800);
  });

  testWidgets('a tall body is clamped to the space the keyboard leaves',
      (WidgetTester t) async {
    // 70 % of (800 - 300) = 350, not 70 % of the window.
    final Rect r = await pumpBody(t, keyboard: 300, childHeight: 600);
    expect(r.height, 350);
    expect(r.bottom, lessThanOrEqualTo(800 - 300));
  });

  testWidgets('a short body keeps its own height', (WidgetTester t) async {
    final Rect r = await pumpBody(t, keyboard: 300, childHeight: 120);
    expect(r.height, 120, reason: 'the constraint is a ceiling, not a size');
  });
}
