// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/chat/export_passphrase_dialog.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

/// Dialogs are the surfaces the route sweep cannot reach, and they are where the
/// narrow floor bites hardest: two actions and a field in a box that cannot
/// scroll. Each is rendered in every preset at 320 dp and 200 % text.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final MmThemePreset preset in MmThemePreset.values) {
    testWidgets('the passphrase dialog holds the floor on ${preset.name}',
        (WidgetTester t) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ThemeController tc = ThemeController();
      await tc.setPreset(preset);
      t.view.physicalSize = const Size(320, 780);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChangeNotifierProvider<ThemeController>.value(
        value: tc,
        child: MaterialApp(
          theme: tc.theme,
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(builder: (BuildContext ctx) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showDialog<String>(
                    context: ctx,
                    builder: (BuildContext inner) => ExportPassphraseDialog(
                      l: AppLocalizations.of(inner),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            );
          }),
        ),
      ));
      await t.pump();
      await t.tap(find.text('open'));
      for (int i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull,
          reason: 'the passphrase dialog overflowed on ${preset.name}');
    });
  }
}
