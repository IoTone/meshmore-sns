// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/screens/tools/tool_widgets.dart';

/// `ToolChoice` is the value slot of a `ToolField` row (label 104dp, then an
/// `Expanded` slot). It used to size to its widest menu item, so a long
/// choice at large text overflowed the slot (57px at 320dp x 2.0 on the
/// "Download a region" source picker). It now fills the slot, like the
/// text fields on the same pages.
Future<void> _bundledFonts() async {
  for (final MapEntry<String, String> e in <String, String>{
    'Saira': 'assets/fonts/Saira.ttf',
    'JetBrains Mono': 'assets/fonts/JetBrainsMono.ttf',
  }.entries) {
    final FontLoader fl = FontLoader(e.key)
      ..addFont(Future<ByteData>.value(
          ByteData.sublistView(File(e.value).readAsBytesSync())));
    await fl.load();
  }
}

Future<void> _pump(WidgetTester t, {required double w, required double scale}) async {
  t.view.physicalSize = Size(w, 700);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (BuildContext c, Widget? child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: <Widget>[
          ToolField(
            label: 'Source',
            child: ToolChoice<String>(
              value: 'a',
              values: const <String>['a', 'b'],
              label: (String s) => s == 'a'
                  ? 'OpenStreetMap Humanitarian vector service'
                  : 'USGS Topo',
              onChanged: (_) {},
            ),
          ),
        ]),
      ),
    ),
  ));
  await t.pump();
}

void main() {
  setUpAll(_bundledFonts);

  testWidgets('fills the value slot at 393dp, 1.0x', (WidgetTester t) async {
    await _pump(t, w: 393, scale: 1.0);
    expect(t.takeException(), isNull);
    final Rect dd = t.getRect(find.byType(DropdownButton<String>));
    // slot = page padding 16 + label 104 .. 393 - 16
    expect(dd.left, 16 + 104);
    expect(dd.right, 393 - 16);
  });

  testWidgets('fills the value slot at 600dp, 1.0x', (WidgetTester t) async {
    await _pump(t, w: 600, scale: 1.0);
    expect(t.takeException(), isNull);
    final Rect dd = t.getRect(find.byType(DropdownButton<String>));
    expect(dd.left, 16 + 104);
    expect(dd.right, 600 - 16);
  });

  testWidgets('a long choice does not overflow at 320dp, 2.0x',
      (WidgetTester t) async {
    await _pump(t, w: 320, scale: 2.0);
    expect(t.takeException(), isNull);
    final Rect dd = t.getRect(find.byType(DropdownButton<String>));
    expect(dd.right, lessThanOrEqualTo(320 - 16));
  });
}
