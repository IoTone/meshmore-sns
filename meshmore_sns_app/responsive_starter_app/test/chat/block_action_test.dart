// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/chat/block_actions.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Blocking a key had no way in.
///
/// `BlockStore.block` had no caller in `lib/`: the blocked-keys screen could only
/// *unblock*, and its empty state explained a feature the app could not reach. The
/// offer lives on the message action sheet and on the node sheet now, and both go
/// through this one confirmation — which is also the only place that says what a
/// block actually does, because the radio keeps receiving either way.
Widget _host(BlockStore store, {void Function(bool)? onDone}) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ChangeNotifierProvider<BlockStore?>.value(
        value: store,
        child: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final bool ok = await confirmAndBlock(ctx,
                      pubKeyHex: 'a' * 64, name: 'Mallory');
                  onDone?.call(ok);
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferencesTestShim.install());

  testWidgets('a confirmed block adds the key, and says it is local',
      (WidgetTester t) async {
    final BlockStore store = BlockStore();
    await t.pumpWidget(_host(store));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();

    // The sentence is the point: a reader who blocks expecting the traffic to
    // stop has been misled by their own app.
    expect(find.textContaining('The radio still receives and relays'),
        findsOneWidget);
    expect(find.textContaining('Mallory'), findsOneWidget);

    await t.tap(find.text('Block'));
    // The confirm's own callback is async (it awaits the store's write), so a
    // settle is not enough: pump the frame the write lands on.
    // The write goes through the sealed store, which a widget test has no
    // Keystore for, so let the real event loop run for it rather than fake time.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(store.isBlocked('a' * 64), isTrue);
    expect(store.isBlocked('a' * 64), isTrue);
  });

  testWidgets('cancelling blocks nothing', (WidgetTester t) async {
    final BlockStore store = BlockStore();
    await t.pumpWidget(_host(store));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 100));
    expect(store.isBlocked('a' * 64), isFalse);
  });
}

/// `BlockStore` persists through `shared_preferences`; the default mock
/// initial values make the first read resolve to an empty list.
abstract final class SharedPreferencesTestShim {
  static void install() =>
      SharedPreferences.setMockInitialValues(<String, Object>{});
}
