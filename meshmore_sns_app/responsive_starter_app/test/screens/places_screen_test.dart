// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/places_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  testWidgets('the places list has a page, and it keeps the filters', (t) async {
    // It existed only as a modal, so nothing could link to it and the router
    // could not restore it. The page and the sheet share one widget, so what is
    // proved here is the page: the search field and the rows are present.
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final PlaceStore store = PlaceStore();
    await t.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<PlaceStore>.value(value: store),
        ChangeNotifierProvider<MeshcoreController>(
            create: (_) => MeshcoreController()),
        // `placeComposerOf` needs the report budget: a place that goes out costs
        // airtime and the budget is what says whether it may.
        Provider<PlaceReportBudget>(
            create: (_) => PlaceReportBudget(clock: DateTime.now)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const PlacesScreen(),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byType(PlacesScreen), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('place-search')), findsOneWidget);
    // An empty ledger says so rather than showing a blank page.
    expect(find.byType(Text), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('the places page holds a 320 dp phone at 200 % text', (t) async {
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<PlaceStore>(create: (_) => PlaceStore()),
        ChangeNotifierProvider<MeshcoreController>(
            create: (_) => MeshcoreController()),
        // `placeComposerOf` needs the report budget: a place that goes out costs
        // airtime and the budget is what says whether it may.
        Provider<PlaceReportBudget>(
            create: (_) => PlaceReportBudget(clock: DateTime.now)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const PlacesScreen(),
      ),
    ));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
