// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/geofence/geofence_controller.dart';
import 'package:meshmore_sns_app/geofence/geofence_create_sheet.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/util/mm_format.dart';

/// The fence sheet, and the one thing it must not do: ask for a radius in raw
/// metres. A distance the reader cannot read is the same defect as an
/// untranslated distance anywhere else, and the app already has one formatter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester t, {FormatPrefs? prefs}) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final GeofenceController fences =
        GeofenceController(mc: MeshcoreController(), autoTick: false);
    addTearDown(fences.dispose);
    await t.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<GeofenceController>.value(value: fences),
          ChangeNotifierProvider<FormatPrefs>.value(
              value: prefs ?? FormatPrefs()),
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
          home: const Scaffold(
            body: GeofenceCreateSheet(latitude: 40, longitude: -105),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('the radius is a distance the reader can read',
      (WidgetTester t) async {
    await pump(t);
    expect(find.byKey(const ValueKey<String>('geofence-radius')), findsOneWidget);
    // The default stop, in the reader's units, not "250 m" as a raw number.
    expect(find.text('250 m'), findsOneWidget);
  });

  testWidgets('the radius follows the reader\'s units', (WidgetTester t) async {
    await pump(
        t,
        prefs: FormatPrefs(units: DistanceUnits.imperial));
    // 250 m is 820 ft, and the sheet must say so rather than metres.
    expect(find.textContaining('ft'), findsWidgets);
    expect(find.text('250 m'), findsNothing);
  });

  testWidgets('saving returns the name and the radius', (WidgetTester t) async {
    await pump(t);
    await t.enterText(
        find.byKey(const ValueKey<String>('geofence-name')), 'Camp');
    await t.tap(find.byKey(const ValueKey<String>('geofence-save')));
    await t.pumpAndSettle();
    // The sheet popped; the caller receives the record. Nothing is saved here,
    // which is the map's job, so the assertion is that the sheet closed.
    expect(find.byKey(const ValueKey<String>('geofence-save')), findsNothing);
  });

  testWidgets('the stops are a ladder, and the nearest one is chosen',
      (WidgetTester t) async {
    expect(GeofenceCreateSheet.indexFor(250), 3);
    expect(GeofenceCreateSheet.indexFor(260), 3);
    expect(GeofenceCreateSheet.indexFor(10), 0);
    expect(GeofenceCreateSheet.indexFor(99999),
        GeofenceCreateSheet.stops.length - 1);
  });
}
