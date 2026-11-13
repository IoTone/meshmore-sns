// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/shell/boot_overlay.dart';
import 'package:meshmore_sns_app/shell/boot_surface.dart';
import 'package:meshmore_sns_app/splash/branded_splash_screen.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

/// A launch is one screen.
///
/// It used to be two: a centred logo with a version readout held for two and a
/// bit seconds while preferences loaded, then a different design — brackets and
/// a dial — while the radio came up. Two shapes in a row reads as two apps, and
/// it is the thing "the loading screen does not work properly" meant.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Widget host(Widget child, {MmThemePreset preset = kDefaultPreset}) =>
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<MeshcoreController>(
              create: (_) => MeshcoreController()),
          ChangeNotifierProvider<ThemeController>(
              create: (_) => ThemeController()..setPreset(preset)),
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

  testWidgets('the preferences splash is the same surface as the radio wait',
      (WidgetTester t) async {
    await t.pumpWidget(host(const BrandedSplashScreen()));
    await t.pump();
    expect(find.byType(MmBootSurface), findsOneWidget,
        reason: 'the splash has its own design again');
    // Nothing to skip while preferences load: the wait is milliseconds.
    expect(find.byKey(const ValueKey<String>('boot-skip')), findsNothing);
  });

  testWidgets('the radio wait wears the same surface, and offers the way out',
      (WidgetTester t) async {
    await t.pumpWidget(
        host(BootOverlay(child: const Scaffold(body: Text('shell')))));
    await t.pump();
    expect(find.byType(MmBootSurface), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('boot-skip')), findsOneWidget);
  });

  testWidgets('every preset launches in its own palette',
      (WidgetTester t) async {
    // Colours come from the skin inside the surface, so a preset that cannot
    // read them shows as a build failure rather than as a launch in the wrong
    // palette.
    for (final MmThemePreset p in MmThemePreset.values) {
      await t.pumpWidget(host(const BrandedSplashScreen(), preset: p));
      await t.pump();
      expect(t.takeException(), isNull, reason: '$p could not launch');
      expect(find.byType(MmBootSurface), findsOneWidget);
    }
  });
}
