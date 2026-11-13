// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/splash/branded_splash_screen.dart';

/// R75: the splash subtitle was a hardcoded Japanese literal, so an
/// English device showed Japanese copy even though `appSubtitle` has an
/// English value. These tests pin the lookup rather than the copy.
Future<void> _pump(WidgetTester t, Locale locale) async {
  await t.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const BrandedSplashScreen(),
    ),
  );
  await t.pump();
}

void main() {
  const String kJapanese = 'ラジオでつながるメッシュ通信';

  testWidgets('English splash shows the English subtitle, not Japanese',
      (WidgetTester t) async {
    await _pump(t, const Locale('en'));
    // The surface sets the companion line in the skin's label case, so the
    // lookup is matched the way the launch screen renders it.
    expect(find.text('Mesh messaging over radio'.toUpperCase()), findsOneWidget);
    expect(find.text(kJapanese), findsNothing,
        reason: 'the Japanese literal was hardcoded before R75');
    expect(find.text('Meshmore SNS'), findsOneWidget,
        reason: 'the brand name stays untranslated');
  });

  testWidgets('Japanese splash shows the Japanese subtitle',
      (WidgetTester t) async {
    await _pump(t, const Locale('ja'));
    expect(find.text(kJapanese.toUpperCase()), findsOneWidget);
    expect(find.text('Mesh messaging over radio'.toUpperCase()), findsNothing);
  });
}
