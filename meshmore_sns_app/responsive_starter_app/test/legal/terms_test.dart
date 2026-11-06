// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/legal/terms_controller.dart';
import 'package:meshmore_sns_app/screens/terms_screen.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

Widget _app(TermsController terms, {bool gate = true}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TermsController>.value(value: terms),
      ChangeNotifierProvider<ThemeController>(
          create: (_) => ThemeController()),
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
      home: TermsScreen(gate: gate),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('TermsController', () {
    test('nothing is agreed before the stored answer is read', () {
      final TermsController c = TermsController();
      expect(c.loaded, isFalse);
      expect(c.accepted, isFalse);
    });

    test('accepting records the current version and persists it', () async {
      final TermsController c = TermsController();
      await c.load();
      expect(c.accepted, isFalse);
      await c.accept();
      expect(c.accepted, isTrue);
      expect(c.acceptedVersion, TermsController.currentVersion);

      final SharedPreferences p = await SharedPreferences.getInstance();
      expect(p.getInt('mm.legal.acceptedVersion'),
          TermsController.currentVersion);
    });

    test('an older accepted version is not consent to the current text',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mm.legal.acceptedVersion': TermsController.currentVersion - 1,
      });
      final TermsController c = TermsController();
      await c.load();
      expect(c.accepted, isFalse,
          reason: 'changed wording must be shown again before the app opens');
      expect(c.acceptedVersion, TermsController.currentVersion - 1);
    });

    test('a stored current version opens without asking', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mm.legal.acceptedVersion': TermsController.currentVersion,
      });
      final TermsController c = TermsController();
      await c.load();
      expect(c.accepted, isTrue);
    });
  });

  group('TermsScreen', () {
    testWidgets('the gate shows every section and records agreement',
        (WidgetTester t) async {
      final TermsController c = TermsController();
      await c.load();
      await t.pumpWidget(_app(c));
      await t.pump();

      final AppLocalizations l = AppLocalizations.of(
          t.element(find.byType(TermsScreen)));
      expect(find.text(l.termsTitle), findsOneWidget);
      expect(find.text(l.termsAccept), findsOneWidget);

      // Every section is present, walked top to bottom: the list is lazy, so a
      // section below the fold is not built until it is scrolled to. Asserting
      // them all at once only held while the copy was short enough to fit one
      // screen, which is a property of the wording, not of the page.
      final List<(String, String)> sections = <(String, String)>[
        (l.termsSectionLocal, l.termsLocalBody),
        (l.termsSectionLeaves, l.termsLeavesBody),
        (l.termsSectionPermissions, l.termsPermissionsBody),
        (l.termsSectionRetention, l.termsRetentionBody(250)),
        (l.termsSectionChanges, l.termsChangesBody),
      ];
      for (final (String title, String body) in sections) {
        await t.scrollUntilVisible(find.text(title), 200);
        expect(find.text(title), findsOneWidget);
        expect(find.text(body), findsOneWidget);
      }

      await t.tap(find.byKey(const ValueKey<String>('terms-accept')));
      await t.pump();
      expect(c.accepted, isTrue);
    });

    testWidgets('the read-only copy offers no way to agree', (WidgetTester t) async {
      final TermsController c = TermsController.accepted();
      await t.pumpWidget(_app(c, gate: false));
      await t.pump();
      expect(find.byKey(const ValueKey<String>('terms-accept')), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('no overflow at 320 dp and 200 % text', (WidgetTester t) async {
      t.view.physicalSize = const Size(320, 780);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final TermsController c = TermsController();
      await c.load();
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: _app(c),
        ),
      );
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });
}
