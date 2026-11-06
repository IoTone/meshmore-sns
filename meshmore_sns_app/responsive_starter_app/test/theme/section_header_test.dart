// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/mm_collapse_controller.dart';
import 'package:meshmore_sns_app/ui/mm_collapsible.dart';

/// A group header is a label and an edge, not a box.
///
/// On the dark grounds the header takes a tonal step, which reads as grouping
/// because the ground is already dark. On paper the same fill is a beige band
/// across the width, so every collapsible section became one more rectangle and
/// the page read as a stack of them. The rule below states the answer once for
/// every screen that uses this widget: a tinted header starts where its fill
/// starts, and an untinted one starts at a rule in the border tier.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester t, MmThemePreset preset) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ThemeController tc = ThemeController();
    await tc.setPreset(preset);
    final MmCollapseController store = MmCollapseController();
    await t.pumpWidget(ChangeNotifierProvider<ThemeController>.value(
      value: tc,
      child: ChangeNotifierProvider<MmCollapseController>.value(
        value: store,
        child: MaterialApp(
          theme: tc.theme,
          home: Scaffold(
            body: MmCollapsibleSection(
              id: MmGroupIds.dashRadio,
              title: 'Radio',
              initiallyExpanded: false,
              children: const <Widget>[Text('body')],
            ),
          ),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('paper: no fill, and a border-tier rule above the label',
      (WidgetTester t) async {
    final MmSkin skin = mmSkinFor(MmThemePreset.studioLight);
    await pump(t, MmThemePreset.studioLight);
    final Material header = t.widget<Material>(find.byType(Material).last);
    expect(header.color, Colors.transparent,
        reason: 'a beige band on paper is a box, not a header');
    final List<Container> rules = t
        .widgetList<Container>(find.byType(Container))
        .where((Container c) => c.constraints?.maxHeight != null &&
            c.constraints!.maxHeight <= 1.0)
        .toList();
    expect(rules.length, 2, reason: 'one rule opens the group, one closes it');
    expect(rules.first.color, skin.color.line,
        reason: 'the opening rule is the border tier');
    expect(rules.last.color, skin.color.hairline,
        reason: 'the closing rule stays subordinate');
  });

  testWidgets('dark: the header is still the tonal step, with no opening rule',
      (WidgetTester t) async {
    final MmSkin skin = mmSkinFor(MmThemePreset.studio);
    await pump(t, MmThemePreset.studio);
    final Material header = t.widget<Material>(find.byType(Material).last);
    expect(header.color, skin.color.raised,
        reason: 'the dark skins group by tone, as before');
    final List<Container> rules = t
        .widgetList<Container>(find.byType(Container))
        .where((Container c) => c.constraints?.maxHeight != null &&
            c.constraints!.maxHeight <= 1.0)
        .toList();
    expect(rules.length, 1, reason: 'only the closing rule');
  });
}
