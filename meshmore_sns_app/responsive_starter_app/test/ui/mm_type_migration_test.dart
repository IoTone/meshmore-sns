// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/auto_publish_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/perms/location_service.dart';
import 'package:meshmore_sns_app/screens/docs_hub_screen.dart';
import 'package:meshmore_sns_app/screens/location_settings_screen.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

/// W2 — the two pattern-setter screens read the type scale instead of a number,
/// and this is the proof that nothing moved: every migrated size resolves to
/// the literal it replaced.
class _NoFixLocation implements LocationService {
  @override
  Future<PhoneFix?> currentFix({Duration timeLimit = const Duration(seconds: 15)}) async =>
      null;

  @override
  Future<LocationOutcome> requestFix({
    Duration timeLimit = const Duration(seconds: 15),
    bool prompt = true,
  }) async =>
      const LocationOutcome.error(LocationFailure.servicesDisabled);

  @override
  Stream<PhoneFix> positionStream({required int distanceFilterMeters}) =>
      const Stream<PhoneFix>.empty();
}

Widget _host(Widget screen, {MeshcoreController? mc}) {
  final MeshcoreController controller = mc ?? MeshcoreController();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
      ChangeNotifierProvider<MeshcoreController>.value(value: controller),
      ChangeNotifierProvider<AutoPublishController>(
        create: (_) => AutoPublishController(
            mc: controller, location: _NoFixLocation()),
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
      home: screen,
    ),
  );
}

double? _sizeOf(WidgetTester t, Finder f) =>
    t.widget<Text>(f).style?.fontSize;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('docs hub keeps its 12 and 10.5 px prose', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController();
    addTearDown(mc.dispose);
    await t.pumpWidget(_host(const DocsHubScreen(), mc: mc));
    await t.pumpAndSettle();
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(DocsHubScreen)));

    expect(_sizeOf(t, find.text(l.docsHubSubtitle)), 12);
    expect(_sizeOf(t, find.text(l.docsHubFooter)), 10.5);
  });

  testWidgets('location settings keeps its 12 and 11 px prose',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController();
    addTearDown(mc.dispose);
    await t.pumpWidget(_host(const LocationSettingsScreen(), mc: mc));
    await t.pumpAndSettle();
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(LocationSettingsScreen)));

    expect(_sizeOf(t, find.text(l.locHelp)), 12);
    expect(_sizeOf(t, find.text(l.locBatteryHint)), 11);
  });
}
