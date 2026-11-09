// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/bundled_fonts.dart';

import 'package:meshmore_sns_app/screens/tools/soak_screen.dart';
import 'package:meshmore_sns_app/screens/tools/tool_widgets.dart';

/// Device finding (motorola edge 2024, 387dp, system font scale 1.15): the
/// Soak page's "CONVERSATION" label broke mid-word as "CONVERSATIO / N"
/// because every ToolField label column was a fixed 104dp. Soak now gives
/// its rows a wider column; every other page keeps 104.

Future<void> _pump(WidgetTester t, double labelWidth) async {
  t.view.physicalSize = const Size(387, 700);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(fontFamily: 'Saira'),
    builder: (BuildContext c, Widget? child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.15)),
        child: child!),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: <Widget>[
          ToolField(
              labelWidth: labelWidth,
              label: 'CONVERSATION',
              child: const SizedBox(height: 40)),
          ToolField(
              labelWidth: labelWidth,
              label: 'COUNT',
              child: const SizedBox(height: 40)),
        ]),
      ),
    ),
  ));
  await t.pump();
}

void main() {
  setUpAll(loadBundledFonts);

  testWidgets('the default 104dp column breaks CONVERSATION at 1.15x',
      (WidgetTester t) async {
    await _pump(t, ToolField.defaultLabelWidth);
    final double one = t.getSize(find.text('COUNT')).height;
    expect(t.getSize(find.text('CONVERSATION')).height, greaterThan(one * 1.5),
        reason: 'two lines: the bug the Soak page had');
  });

  testWidgets("Soak's label column keeps CONVERSATION on one line at 1.15x",
      (WidgetTester t) async {
    await _pump(t, SoakScreen.labelWidth);
    final double one = t.getSize(find.text('COUNT')).height;
    expect(t.getSize(find.text('CONVERSATION')).height, one);
    // both rows share the column, so their controls still line up
    final List<Rect> boxes = t
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((SizedBox b) => b.height == 40)
        .map((SizedBox b) => t.getRect(find.byWidget(b)))
        .toList();
    expect(boxes.length, 2);
    expect(boxes[0].left, boxes[1].left);
    expect(boxes[0].left, 16 + SoakScreen.labelWidth);
  });

  test('every other ToolField keeps the 104dp column', () {
    expect(ToolField.defaultLabelWidth, 104);
  });
}
