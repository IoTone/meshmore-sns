// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/chat_store.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/storage_use_block.dart';

/// The storage block states what can be measured and nothing else: no map
/// controller in the tree is a sentence, not a zero, and the sealed history's
/// size comes from the store that owns it rather than from a guess here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester t, {bool withMaps = false}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ThemeController tc = ThemeController();
    await tc.setPreset(MmThemePreset.studioLight);
    await t.pumpWidget(ChangeNotifierProvider<ThemeController>.value(
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
        theme: tc.theme,
        home: const Scaffold(body: StorageUseBlock()),
      ),
    ));
    await t.pump();
  }

  testWidgets('without the map open it says so instead of showing zero',
      (WidgetTester t) async {
    await pump(t);
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(StorageUseBlock)));
    expect(find.text(l.storageMapsUnknown), findsOneWidget);
  });

  testWidgets('the sealed history size is published by the store',
      (WidgetTester t) async {
    await pump(t);
    ChatStore.bytes.value = 40 * 1024;
    await t.pump();
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(StorageUseBlock)));
    expect(find.text(l.storageHistory('40')), findsOneWidget,
        reason: 'the number is the store\'s own record size, in KB');
  });

  testWidgets('the block holds the floor on paper', (WidgetTester t) async {
    t.view.physicalSize = const Size(320, 780);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await pump(t);
    expect(t.takeException(), isNull);
  });
}
