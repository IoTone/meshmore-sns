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

/// A group header is a label under one rule, never a band.
///
/// R77 gave the dark skins a filled header (one tonal step above the page)
/// and closed the group with a hairline. Between two groups that drew the
/// boundary twice, because the previous group's closing rule sat immediately
/// above the next group's fill, and a folded group read as a box bounded above
/// and below. On paper the same fill was a beige band across the width, so
/// every section became one more rectangle on a page that was already a stack
/// of them.
///
/// R116 states the answer once for every screen that uses this widget and for
/// all eight presets: the group starts at one rule in the border tier, the
/// header carries no fill, and the group draws nothing at its end. One
/// boundary, one line, on every ground.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester t, MmThemePreset preset,
      {int sections = 1}) async {
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
            body: Column(children: <Widget>[
              for (int i = 0; i < sections; i++)
                MmCollapsibleSection(
                  id: i == 0 ? MmGroupIds.dashRadio : MmGroupIds.dashLocation,
                  title: i == 0 ? 'Radio' : 'Location',
                  initiallyExpanded: false,
                  children: const <Widget>[Text('body')],
                ),
            ]),
          ),
        ),
      ),
    ));
    await t.pump();
  }

  /// The rules this widget draws. A rule is a square-cornered, full-width
  /// `Container` no taller than a hairline; the header itself is a `Material`,
  /// so the two can never be confused.
  List<Container> rules(WidgetTester t) => t
      .widgetList<Container>(find.byType(Container))
      .where((Container c) =>
          c.constraints?.maxHeight != null && c.constraints!.maxHeight <= 1.0)
      .toList();

  testWidgets('paper: a border-tier rule above the label, and no fill',
      (WidgetTester t) async {
    final MmSkin skin = mmSkinFor(MmThemePreset.studioLight);
    await pump(t, MmThemePreset.studioLight);
    final Material header = t.widget<Material>(find.byType(Material).last);
    expect(header.color, Colors.transparent,
        reason: 'a band on paper is a box, not a header');
    expect(find.byKey(const ValueKey<String>('group-open-rule')),
        findsOneWidget);
    expect(rules(t).single.color, skin.color.line,
        reason: 'the opening rule is the border tier');
  });

  testWidgets('dark: the same rule above the label, and still no fill',
      (WidgetTester t) async {
    final MmSkin skin = mmSkinFor(MmThemePreset.studio);
    await pump(t, MmThemePreset.studio);
    final Material header = t.widget<Material>(find.byType(Material).last);
    expect(header.color, Colors.transparent,
        reason: 'a tinted header is a boundary drawn twice, on any ground');
    expect(find.byKey(const ValueKey<String>('group-open-rule')),
        findsOneWidget);
    expect(rules(t).single.color, skin.color.line);
  });

  testWidgets('every preset marks a group the same way', (WidgetTester t) async {
    for (final MmThemePreset preset in MmThemePreset.values) {
      final MmSkin skin = mmSkinFor(preset);
      await pump(t, preset);
      final Material header = t.widget<Material>(find.byType(Material).last);
      expect(header.color, Colors.transparent, reason: '$preset fills a header');
      expect(find.byKey(const ValueKey<String>('group-open-rule')),
          findsOneWidget,
          reason: '$preset draws no opening rule');
      expect(rules(t).single.color, skin.color.line,
          reason: '$preset draws the rule outside the border tier');
    }
  });

  // One boundary, one line. Between two groups there is exactly one rule: the
  // second group's opening rule. A closing rule as well would put two lines a
  // few dp apart between every pair of sections, which is the doubled border
  // seen on the dashboard, and a folded group would be bounded above and below.
  testWidgets('two groups draw one line between them, on both grounds',
      (WidgetTester t) async {
    for (final MmThemePreset preset in <MmThemePreset>[
      MmThemePreset.studioLight,
      MmThemePreset.studio,
    ]) {
      await pump(t, preset, sections: 2);
      expect(find.byKey(const ValueKey<String>('group-open-rule')),
          findsNWidgets(2));
      expect(find.byKey(const ValueKey<String>('group-close-rule')),
          findsNothing,
          reason: 'a closing rule would draw the boundary twice');
      expect(rules(t).length, 2,
          reason: '$preset: one rule per boundary, not two');
    }
  });

  // A group closed by the user builds no content, so nothing sits between its
  // header and the next group's rule: the boundary is still one line, not a
  // line and an empty box.
  testWidgets('a folded group builds no content', (WidgetTester t) async {
    await pump(t, MmThemePreset.studio);
    expect(find.text('body'), findsNothing);
    expect(rules(t).length, 1);
  });
}
