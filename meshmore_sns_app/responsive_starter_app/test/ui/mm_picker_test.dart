// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/ui/mm_components.dart';

void main() {
  Future<String?> open(WidgetTester t, {String? current}) async {
    String? picked;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext c) => Center(
            child: TextButton(
              onPressed: () async {
                picked = await showMmPicker<String>(
                  context: c,
                  title: 'Pick one',
                  current: current,
                  items: const <MmPickerItem<String>>[
                    MmPickerItem<String>.header('Group A'),
                    MmPickerItem<String>.option('a', 'Alpha'),
                    MmPickerItem<String>.option('b', 'Beta'),
                    MmPickerItem<String>.header('Group B'),
                    MmPickerItem<String>.option('c', 'Gamma'),
                    MmPickerItem<String>.option('d', 'Delta'),
                  ],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    return picked;
  }

  testWidgets('R104 every row is laid out inside the sheet and tappable',
      (WidgetTester t) async {
    String? picked;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext c) => TextButton(
            onPressed: () async {
              picked = await showMmPicker<String>(
                context: c,
                title: 'Pick one',
                current: 'a',
                items: const <MmPickerItem<String>>[
                  MmPickerItem<String>.header('Group A'),
                  MmPickerItem<String>.option('a', 'Alpha'),
                  MmPickerItem<String>.option('b', 'Beta'),
                  MmPickerItem<String>.header('Group B'),
                  MmPickerItem<String>.option('c', 'Gamma'),
                  MmPickerItem<String>.option('d', 'Delta'),
                ],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(find.text('Group A'), findsOneWidget);
    expect(find.text('Group B'), findsOneWidget);
    // The last row must be inside the sheet's visible rect, not merely built:
    // an earlier Column+Flexible layout built the rows with a zero-height
    // viewport, so a tap on this label hit the scrim instead.
    final Rect sheet = t.getRect(find.byType(BottomSheet));
    final Rect last = t.getRect(find.text('Delta'));
    expect(sheet.contains(last.center), isTrue);

    await t.tap(find.text('Delta'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(picked, 'd');
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('R104 the current value is ticked', (WidgetTester t) async {
    final String? picked = await open(t, current: 'b');
    expect(picked, isNull);
    final Finder ticks = find.byIcon(Icons.check);
    expect(ticks, findsOneWidget, reason: 'one check for one current value');
  });
}
