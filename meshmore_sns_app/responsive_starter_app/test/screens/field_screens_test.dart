// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/field/position_history.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/geofence/geofence_controller.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/coverage_screen.dart';
import 'package:meshmore_sns_app/screens/geofences_screen.dart';
import 'package:meshmore_sns_app/sos/sos_controller.dart';
import 'package:meshmore_sns_app/telemetry/coverage_session.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

/// The two new field surfaces under every skin, because a bottom sheet or a
/// screen is its own route with its own theme lookups, and a token that does
/// not resolve under one preset fails only there.
Widget _host(Widget child, MmThemePreset preset) {
  final ThemeController theme = ThemeController()..setPreset(preset);
  return MultiProvider(
    providers: <SingleChildWidget>[
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<MeshcoreController>(
          create: (_) => MeshcoreController()),
      ChangeNotifierProvider<GeofenceController>(
        create: (BuildContext ctx) => GeofenceController(
            mc: ctx.read<MeshcoreController>(), autoTick: false),
      ),
      ChangeNotifierProvider<PositionRecorder>(
          create: (_) => PositionRecorder(persist: false, autoTick: false)),
      ChangeNotifierProvider<CoverageSession>(
        create: (BuildContext ctx) =>
            CoverageSession(mc: ctx.read<MeshcoreController>()),
      ),
      ChangeNotifierProvider<PlaceStore>(create: (_) => PlaceStore()),
      Provider<PlaceReportBudget>(
          create: (_) => PlaceReportBudget(clock: DateTime.now)),
      ChangeNotifierProvider<SosController>(
        create: (BuildContext ctx) => SosController(
            mc: ctx.read<MeshcoreController>(), autoTick: false),
      ),
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
      home: child,
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  for (final MmThemePreset preset in MmThemePreset.values) {
    testWidgets('the geofence screen builds under ${preset.name}',
        (WidgetTester t) async {
      await t.pumpWidget(_host(const GeofencesScreen(), preset));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Geofences'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('geofence-explainer')),
          findsOneWidget);
      // No fix in this harness, so the add action must be refused with copy.
      expect(find.byKey(const ValueKey<String>('geofence-needs-fix')),
          findsOneWidget);
    });

    testWidgets('the coverage screen builds under ${preset.name}',
        (WidgetTester t) async {
      await t.pumpWidget(_host(const CoverageScreen(), preset));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey<String>('coverage-before-start')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('coverage-start')),
          findsOneWidget);
    });
  }
}
