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
import 'package:meshmore_sns_app/theme/mm_tokens.dart' show MmThemePreset;
import 'package:meshmore_sns_app/ui/mm_pixel_icon.dart';

import '../meshcore/fake_transport.dart';

/// Two answers, and the state that changes what they can do.
void main() {
  ChatMessage message({
    double? snrDb,
    int? hopCount,
    List<String> pathHashes = const <String>[],
  }) =>
      ChatMessage(
        channelIdx: 0,
        text: 'MikeP: hey there',
        outgoing: false,
        snrDb: snrDb,
        hopCount: hopCount,
        pathHashes: pathHashes,
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

  testWidgets('a measured row offers a friendly ack, and an unmeasured one does not',
      (WidgetTester t) async {
    // The line states numbers this radio measured, so the action appears only
    // when there are numbers to state.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await mc.connect();
    fake.emit(selfInfoFrame());
    Future<void> show(ChatMessage m) async {
      await t.pumpWidget(MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
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
          home: Builder(
            builder: (BuildContext c) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showChatActions(c, m),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    const ValueKey<String> ackKey =
        ValueKey<String>('chat-action-friendly-ack');
    await show(message(snrDb: 12.5, hopCount: 3,
        pathHashes: <String>['4490', 'DF7C']));
    expect(find.byKey(ackKey), findsOneWidget);
    expect(find.text('Friendly ack'), findsOneWidget);
    // A row with nothing measured says so by not offering it at all.
    await t.tapAt(const Offset(4, 4));
    await t.pumpAndSettle();
    await show(message());
    expect(find.byKey(ackKey), findsNothing);
    await drain(t, mc);
  });

  testWidgets('DR Pop draws its own signal glyph, the other skins a Material one',
      (WidgetTester t) async {
    // The DR Pop chat rows are Mondrian blocks with a five-by-five invader
    // sprite, so a Material glyph beside them reads as a different application.
    // The friendly-ack row carries the skin's own drawing instead.
    Future<MeshcoreController> openWith(MmThemePreset preset) async {
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
          ChangeNotifierProvider<ThemeController>.value(
              value: ThemeController()..setPreset(preset)),
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
                      message(
                          snrDb: 12.5,
                          hopCount: 3,
                          pathHashes: <String>['4490', 'DF7C'])),
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

    final MeshcoreController pop = await openWith(MmThemePreset.drPop);
    expect(find.byType(PixelBarsIcon), findsOneWidget);
    expect(find.byIcon(Icons.wifi_tethering), findsNothing);
    await t.tapAt(const Offset(4, 4));
    await t.pumpAndSettle();
    await drain(t, pop);

    final MeshcoreController studio = await openWith(MmThemePreset.studio);
    expect(find.byIcon(Icons.wifi_tethering), findsOneWidget);
    expect(find.byType(PixelBarsIcon), findsNothing);
    await t.tapAt(const Offset(4, 4));
    await t.pumpAndSettle();
    await drain(t, studio);
  });

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
