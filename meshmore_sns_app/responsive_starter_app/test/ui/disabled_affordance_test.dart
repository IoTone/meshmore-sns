// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/mm_components.dart';

/// A control that is off is still a control.
///
/// On a dark ground a half-strength border and Material's 38 % disabled ink
/// dissolve into the background and nobody notices, because the ground is
/// already dark. On paper the same values composite to 1.4:1 and 1.8:1: the
/// shape disappears and the row's own sentence goes with it, which reads as
/// "this is not a control" rather than "this control is off". These assertions
/// hold on every preset, and on the light one they are the difference between
/// a usable screen and a smudge.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  double ratio(Color a, Color b) {
    final double la = a.computeLuminance();
    final double lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  Future<void> pump(
    WidgetTester t,
    MmThemePreset preset,
    Widget child,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ThemeController tc = ThemeController();
    await tc.setPreset(preset);
    await t.pumpWidget(ChangeNotifierProvider<ThemeController>.value(
      value: tc,
      child: MaterialApp(
        theme: tc.theme,
        home: Scaffold(body: Center(child: child)),
      ),
    ));
    await t.pump();
  }

  testWidgets('a disabled MmAction keeps a visible outline on every preset',
      (WidgetTester t) async {
    for (final MmThemePreset preset in MmThemePreset.values) {
      final MmSkin skin = mmSkinFor(preset);
      await pump(t, preset, const MmAction(label: 'Revert', onPressed: null));
      final Container box = t.widgetList<Container>(find.byType(Container)).first;
      final ShapeDecoration deco = box.decoration! as ShapeDecoration;
      final BorderSide side = (deco.shape as OutlinedBorder).side;
      expect(side.color, skin.color.fgDisabled,
          reason: '${preset.name}: the outline is the disabled ink tier');
      expect(side.width, greaterThan(0));
      expect(ratio(side.color, skin.color.base), greaterThanOrEqualTo(3.0),
          reason: '${preset.name}: an outline nobody can see is not an outline');
    }
  });

  testWidgets('a disabled MmPickerTile keeps its words', (WidgetTester t) async {
    for (final MmThemePreset preset in MmThemePreset.values) {
      final MmSkin skin = mmSkinFor(preset);
      await pump(
        t,
        preset,
        MmPickerTile(
          title: 'Repeat',
          value: 'Off',
          hint: 'How often the alarm repeats itself.',
          enabled: false,
          onTap: null,
        ),
      );
      final Text title = t.widget<Text>(find.text('Repeat'));
      final Text hint = t.widget<Text>(
          find.text('How often the alarm repeats itself.'));
      expect(title.style!.color, skin.color.fgDisabled,
          reason: '${preset.name}: the row title keeps a readable tier');
      expect(hint.style!.color, skin.color.fgDisabled,
          reason: '${preset.name}: …and so does its explanation');
      expect(ratio(title.style!.color!, skin.color.base), greaterThanOrEqualTo(3.0),
          reason: '${preset.name}');
    }
  });
}
