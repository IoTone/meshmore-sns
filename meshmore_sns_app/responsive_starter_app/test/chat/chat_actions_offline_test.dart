// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/chat/chat_actions.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// Two answers, and the state that changes what they can do.
void main() {
  ChatMessage message() => ChatMessage(
        channelIdx: 0,
        text: 'MikeP: hey there',
        outgoing: false,
      );

  /// Dispose the controller and let its timers finish before the test ends.
  Future<void> drain(WidgetTester t, MeshcoreController mc) async {
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  }

  Future<MeshcoreController> open(WidgetTester t,
      {required bool ready}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: ready);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    if (ready) {
      await mc.connect();
      fake.emit(selfInfoFrame());
    }
    await t.pumpWidget(MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
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
        home: Builder(
          builder: (BuildContext c) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showChatActions(c, message()),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return mc;
  }

  testWidgets('the sheet offers a reply to the sender and a plain quote',
      (WidgetTester t) async {
    final MeshcoreController mc = await open(t, ready: true);
    // The MeshCore reply addresses the sender by name; the quote does not.
    expect(find.text('Reply to MikeP'), findsOneWidget);
    expect(find.text('Quote this message'), findsOneWidget);
    // Nothing about radios when one is connected.
    expect(find.byKey(const ValueKey<String>('chat-actions-no-radio')),
        findsNothing);
    await drain(t, mc);
  });

  testWidgets('with no radio the sheet says where the reply will wait',
      (WidgetTester t) async {
    // The composer is replaced by the connect row while offline, so a reply
    // would be written into a box the reader cannot see. The actions still
    // work — the text is kept as a draft — but the sheet has to say so, or the
    // tap looks like it did nothing.
    final MeshcoreController mc = await open(t, ready: false);
    expect(find.byKey(const ValueKey<String>('chat-actions-no-radio')),
        findsOneWidget);
    expect(find.text('Reply to MikeP'), findsOneWidget);
    await drain(t, mc);
  });

  testWidgets('a row with no sender name offers no reply, only the quote',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpWidget(MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
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
        home: Builder(
          builder: (BuildContext c) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showChatActions(
                    c,
                    ChatMessage(
                        channelIdx: 0, text: 'no prefix here', outgoing: false)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    // There is nobody to address, so the reply row says why it is off.
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Quote this message'), findsOneWidget);
    final ListTile reply = t.widget<ListTile>(
        find.ancestor(of: find.text('Reply'), matching: find.byType(ListTile)));
    expect(reply.enabled, isFalse);
    await drain(t, mc);
  });
}
