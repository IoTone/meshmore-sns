// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/chat/history_unreadable_notice.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/chat_store.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

/// B1 — a sealed history this device cannot open says so, above the thread,
/// instead of reading as a conversation that never happened.
void main() {
  setUp(ChatStore.resetStatus);
  tearDown(ChatStore.resetStatus);

  Widget host() => ChangeNotifierProvider<ThemeController>(
        create: (_) => ThemeController(),
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: HistoryUnreadableNotice()),
        ),
      );

  testWidgets('an openable history renders nothing at all', (WidgetTester t) async {
    await t.pumpWidget(host());
    expect(find.textContaining('cannot be opened'), findsNothing);
  });

  testWidgets('a lost key says the messages are still saved here',
      (WidgetTester t) async {
    ChatStore.unreadable.value = true;
    await t.pumpWidget(host());
    await t.pump();
    expect(find.textContaining('cannot be opened'), findsOneWidget);
    expect(find.textContaining('still saved here'), findsOneWidget);
  });
}
