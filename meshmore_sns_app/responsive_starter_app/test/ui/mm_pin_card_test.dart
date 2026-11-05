// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/mm_pin_card.dart';

int _removals = 0;

Widget _host(
  ThemeController tc, {
  required bool expanded,
  required VoidCallback onToggle,
  Widget? detail,
}) {
  return ChangeNotifierProvider<ThemeController>.value(
    value: tc,
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: MmPinCard(
            title: 'Coverage',
            summary: '3 of 4 answered',
            trailing: '3/4',
            expanded: expanded,
            onToggle: onToggle,
            detail: detail ?? const Text('detail'),
            menu: <PinCardMenuEntry>[
              PinCardMenuEntry(
                label: 'Remove from dashboard',
                onSelected: () => _removals++,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => _removals = 0);

  testWidgets('a closed card is one header row tall and builds no block',
      (WidgetTester t) async {
    final ThemeController tc = ThemeController();
    int toggles = 0;
    await t.pumpWidget(_host(tc, expanded: false, onToggle: () => toggles++));

    final Finder card = find.byType(MmPinCard);
    // The card is the fixed row plus the hairline that closes it, a skin
    // token (1 or 2 px), never more.
    expect(t.getSize(card).height,
        inInclusiveRange(kPinCardCollapsedHeight, kPinCardCollapsedHeight + 4));
    expect(find.text('detail'), findsNothing);

    await t.tap(card);
    expect(toggles, 1);
  });

  testWidgets('an open card builds the block and reports the fold',
      (WidgetTester t) async {
    final ThemeController tc = ThemeController();
    await t.pumpWidget(_host(tc, expanded: true, onToggle: () {}));

    expect(find.text('detail'), findsOneWidget);
    final Semantics semantics = t.widget<Semantics>(
      find
          .descendant(
              of: find.byType(MmPinCard), matching: find.byType(Semantics))
          .first,
    );
    expect(semantics.properties.button, isTrue);
    expect(semantics.properties.expanded, isTrue);
    expect(semantics.properties.label, contains('Coverage'));
  });

  testWidgets('the overflow carries the one action: remove from dashboard',
      (WidgetTester t) async {
    await t
        .pumpWidget(_host(ThemeController(), expanded: false, onToggle: () {}));
    await t.tap(find.byKey(const ValueKey<String>('pin-card-menu')));
    await t.pumpAndSettle();
    expect(find.text('Remove from dashboard'), findsOneWidget);
    await t.tap(find.text('Remove from dashboard'));
    await t.pumpAndSettle();
    expect(_removals, 1);
  });

  testWidgets('the card renders in all seven skins at 320 dp and 200 % text',
      (WidgetTester t) async {
    for (final MmThemePreset preset in MmThemePreset.values) {
      t.view.physicalSize = const Size(320, 780);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: _host(ThemeController()..setPreset(preset),
              expanded: true, onToggle: () {}),
        ),
      );
      await t.pump();
      expect(t.takeException(), isNull, reason: preset.name);
      expect(find.text('Coverage'), findsOneWidget, reason: preset.name);
    }
  });
}
