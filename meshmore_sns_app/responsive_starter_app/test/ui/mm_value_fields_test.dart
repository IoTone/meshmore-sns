// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/mm_components.dart';

/// A technical value breaks where its fields break.
///
/// "38.91996, -104.77315 · alt 2041 m · device" is four facts. Wrapped on its
/// own it breaks wherever the width runs out — with the tracking the skins
/// apply, often mid-number, so a reader has to reassemble a coordinate. It fits
/// on one line when it fits, and each field takes its own line when it does not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const List<String> fields = <String>[
    '38.91996, -104.77315',
    'alt 2041 m',
    'device',
  ];

  Future<void> pump(
    WidgetTester t, {
    required MmThemePreset preset,
    required double width,
    required double textScale,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ThemeController tc = ThemeController();
    await tc.setPreset(preset);
    t.view.physicalSize = Size(width, 780);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<ThemeController>.value(
      value: tc,
      child: MaterialApp(
        theme: tc.theme,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SizedBox(
              width: width,
              child: const MmValueFields(fields: fields),
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('wide: one line, separators intact', (WidgetTester t) async {
    await pump(t,
        preset: MmThemePreset.studioLight, width: 900, textScale: 1.0);
    expect(find.text('38.91996, -104.77315 · alt 2041 m · device'),
        findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final MmThemePreset preset in <MmThemePreset>[
    MmThemePreset.studioLight,
    MmThemePreset.studio,
  ]) {
    testWidgets('${preset.name} at 320 dp and 200 %: one field per line',
        (WidgetTester t) async {
      await pump(t, preset: preset, width: 320, textScale: 2.0);
      for (final String f in fields) {
        expect(find.text(f), findsOneWidget,
            reason: 'each field takes its own line');
      }
      expect(find.textContaining(' · '), findsNothing,
          reason: 'no line carries a separator when it has wrapped');
      expect(t.takeException(), isNull,
          reason: 'no overflow at the floor');
    });
  }
}
