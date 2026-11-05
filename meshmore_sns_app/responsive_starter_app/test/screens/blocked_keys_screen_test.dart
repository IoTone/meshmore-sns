// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/screens/blocked_keys_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// APP-F1..F3 - the list is keyed, unblocking restores the rows, and the copy
/// says what a block cannot stop.
void main() {
  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = Directory.systemTemp.createTempSync('blocked_keys_screen_test');
    BlockStore.cipherOverride = MemoryRecordCipher.random();
    BlockStore.directoryOverride = dir;
  });

  tearDown(() {
    BlockStore.cipherOverride = null;
    BlockStore.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget host(BlockStore store) => MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ChangeNotifierProvider<BlockStore>.value(
          value: store,
          child: const BlockedKeysScreen(),
        ),
      );

  BlockStore seeded() => BlockStore(seed: <String, BlockedKey>{
        'a' * 64: BlockedKey(
          pubKeyHex: 'a' * 64,
          sinceMs: DateTime.now().millisecondsSinceEpoch,
          name: 'Mallory',
        ),
        'b' * 64: BlockedKey(
          pubKeyHex: 'b' * 64,
          sinceMs: DateTime.now().millisecondsSinceEpoch - 1000,
        ),
      });

  testWidgets('the list names what it knows and shortens what it does not',
      (WidgetTester t) async {
    await t.pumpWidget(host(seeded()));
    await t.pumpAndSettle();
    expect(find.text('Mallory'), findsOneWidget);
    expect(find.text('No name known'), findsOneWidget);
    expect(find.textContaining('2 keys blocked'), findsOneWidget);
    expect(find.textContaining('still receives and relays'), findsOneWidget,
        reason: 'APP-F3: the copy must say what a block cannot stop');
  });

  testWidgets('unblocking removes the row and says so', (WidgetTester t) async {
    final BlockStore store = seeded();
    await t.pumpWidget(host(store));
    await t.pumpAndSettle();

    await t.tap(find.descendant(
      of: find.byKey(ValueKey<String>('blocked-${'a' * 64}')),
      matching: find.text('Unblock'),
    ));
    // Two pumps, not pumpAndSettle: the snack bar's own dismissal timer would
    // run out inside a settle and the assertion would race it.
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    expect(store.isBlocked('a' * 64), isFalse);
    expect(find.text('Mallory'), findsNothing);
    expect(find.text('Mallory is unblocked. Their messages appear again.'),
        findsOneWidget);
    expect(find.text('No name known'), findsOneWidget,
        reason: 'the other key is untouched');
  });

  testWidgets('an empty list explains what a block does instead of a blank',
      (WidgetTester t) async {
    await t.pumpWidget(host(BlockStore()));
    await t.pumpAndSettle();
    expect(find.textContaining('No key is blocked'), findsWidgets);
    expect(find.textContaining('hides what it sends'), findsOneWidget);
  });
}
