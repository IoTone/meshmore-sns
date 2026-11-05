// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/mm_pin_card.dart';

Widget _host(
  ThemeController tc, {
  required bool expanded,
  required VoidCallback onToggle,
  Widget? detail,
  VoidCallback? onOpen,
  List<Widget> editActions = const <Widget>[],
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
            title: 'Places',
            summary: '3 live places',
            trailing: '3',
            expanded: expanded,
            onToggle: onToggle,
            detail: detail ?? const Text('detail'),
            onOpen: onOpen,
            openLabel: 'Open places',
            editActions: editActions,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a closed card is exactly the collapsed height and builds no '
      'detail', (WidgetTester t) async {
    final ThemeController tc = ThemeController();
    int toggles = 0;
    await t.pumpWidget(_host(tc, expanded: false, onToggle: () => toggles++));

    final Finder card = find.byType(MmPinCard);
    // The card is the fixed row plus the hairline that closes it, which is a
    // skin token (1 or 2 px), never more.
    expect(t.getSize(card).height,
        inInclusiveRange(kPinCardCollapsedHeight, kPinCardCollapsedHeight + 4));
    expect(find.text('detail'), findsNothing);

    await t.tap(card);
    expect(toggles, 1);
  });

  testWidgets('an open card builds its detail and reports the fold to a '
      'screen reader', (WidgetTester t) async {
    final ThemeController tc = ThemeController();
    await t.pumpWidget(_host(tc, expanded: true, onToggle: () {}));

    expect(find.text('detail'), findsOneWidget);
    // The fold is announced: the header is a button that reports its
    // expanded state, and the summary is part of its label.
    final Semantics semantics = t.widget<Semantics>(
      find
          .descendant(
              of: find.byType(MmPinCard), matching: find.byType(Semantics))
          .first,
    );
    expect(semantics.properties.button, isTrue);
    expect(semantics.properties.expanded, isTrue);
    expect(semantics.properties.label, contains('Places'));
  });

  testWidgets('the tap-through appears only while open', (WidgetTester t) async {
    final ThemeController tc = ThemeController();
    await t.pumpWidget(_host(tc,
        expanded: false, onToggle: () {}, onOpen: () {}));
    expect(find.text('Open places'), findsNothing);

    await t.pumpWidget(_host(tc,
        expanded: true, onToggle: () {}, onOpen: () {}));
    expect(find.text('Open places'), findsOneWidget);
  });

  testWidgets('edit mode replaces the fold control with the edit actions',
      (WidgetTester t) async {
    final ThemeController tc = ThemeController();
    await t.pumpWidget(_host(
      tc,
      expanded: false,
      onToggle: () {},
      editActions: <Widget>[
        IconButton(
          key: const ValueKey<String>('remove'),
          onPressed: () {},
          icon: const Icon(Icons.close),
        ),
      ],
    ));
    expect(find.byKey(const ValueKey<String>('remove')), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });

  testWidgets('the card renders in all seven skins and survives 320 dp at '
      '200 % text', (WidgetTester t) async {
    for (final MmThemePreset preset in MmThemePreset.values) {
      final ThemeController tc = ThemeController()..setPreset(preset);
      t.view.physicalSize = const Size(320, 780);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: _host(tc, expanded: true, onToggle: () {}),
        ),
      );
      await t.pump();
      expect(t.takeException(), isNull, reason: preset.name);
      expect(find.text('Places'), findsOneWidget, reason: preset.name);
    }
  });
}
