// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart' show kPublicChannelPsk;
import 'package:meshmore_sns_app/bot/bot_controller.dart';
import 'package:meshmore_sns_app/bot/bot_guards.dart';
import 'package:meshmore_sns_app/bot/bot_scope.dart';
import 'package:meshmore_sns_app/bot/bot_section.dart';
import 'package:meshmore_sns_app/bot/bot_tag.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<int> privatePsk() =>
    List<int>.generate(kPublicChannelPsk.length, (int i) => (i * 3 + 5) & 0xff);

Widget host(BotController bot, BotScope scope) => ChangeNotifierProvider<
        BotController>.value(
    value: bot,
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SingleChildScrollView(child: BotSection(scope: scope)),
      ),
    ));

BotController make({List<int>? Function(int)? pskFor}) => BotController(
      pskFor: pskFor ?? (int _) => privatePsk(),
      now: () => DateTime.utc(2026, 1, 1, 12),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('off by default, and the switch works on a private slot',
      (WidgetTester t) async {
    final BotController bot = make();
    await t.pumpWidget(host(bot, const ChannelScope(2)));

    final Finder sw = find.byType(SwitchListTile);
    expect(t.widget<SwitchListTile>(sw).value, isFalse);
    expect(t.widget<SwitchListTile>(sw).onChanged, isNotNull);

    await t.tap(sw);
    await t.pumpAndSettle();
    expect(bot.isEnabled(const ChannelScope(2)), isTrue);
  });

  // A control that vanishes teaches nobody why. The spec asks for a
  // structural refusal, not a hidden switch.
  testWidgets('Public shows a disabled switch AND the reason',
      (WidgetTester t) async {
    final BotController bot = make();
    await t.pumpWidget(host(bot, const ChannelScope(0)));

    expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull);
    expect(find.textContaining('Slot 0 is the public channel'),
        findsOneWidget);
  });

  testWidgets('a slot still on the public key says exactly that',
      (WidgetTester t) async {
    final BotController bot = make(pskFor: (int _) => kPublicChannelPsk);
    await t.pumpWidget(host(bot, const ChannelScope(3)));
    expect(find.textContaining('Public under another number'),
        findsOneWidget);
  });

  testWidgets('an unseen key says it is waiting, not that it is refused',
      (WidgetTester t) async {
    final BotController bot = make(pskFor: (int _) => null);
    await t.pumpWidget(host(bot, const ChannelScope(3)));
    expect(find.textContaining("Waiting for this slot's key"),
        findsOneWidget);
  });

  testWidgets('enabling reveals mode, instrumentation and the rules button',
      (WidgetTester t) async {
    final BotController bot = make();
    await bot.setEnabled(const ChannelScope(2), true);
    await t.pumpWidget(host(bot, const ChannelScope(2)));

    expect(find.text('Deterministic'), findsOneWidget);
    expect(find.text('Random'), findsOneWidget);
    expect(find.text('Edit rules'), findsOneWidget);
    // The wire label is disclosed, not buried.
    expect(find.textContaining('[bot] prefix'), findsOneWidget);
  });

  // A "random" run that cannot be replayed from its seed is not
  // evidence, so the seed is shown rather than hidden.
  testWidgets('the seed appears only in random mode',
      (WidgetTester t) async {
    final BotController bot = make();
    await bot.setEnabled(const ChannelScope(2), true);
    await t.pumpWidget(host(bot, const ChannelScope(2)));
    expect(find.widgetWithText(TextField, 'Seed'), findsNothing);

    await t.tap(find.text('Random'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Seed'), findsOneWidget);
  });

  // A bot that has gone quiet should say why without log-reading.
  testWidgets('remaining budget and counters are on screen',
      (WidgetTester t) async {
    final BotController bot = make();
    await bot.setEnabled(const ChannelScope(2), true);
    bot.handleInbound(scope: const ChannelScope(2), text: 'ping');
    await t.pumpWidget(host(bot, const ChannelScope(2)));

    expect(find.textContaining('replies left this window'), findsOneWidget);
    expect(find.textContaining('received 1'), findsOneWidget);
    expect(find.textContaining('replied 1'), findsOneWidget);
  });

  testWidgets('a DM scope is offered with no channel key at all',
      (WidgetTester t) async {
    final BotController bot = make(pskFor: (int _) => null);
    await t.pumpWidget(host(bot, DmScope('ab' * 32)));
    expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNotNull);
  });

  group('R59 transcript labelling', () {
    testWidgets('the tag renders', (WidgetTester t) async {
      await t.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: BotTag()),
      ));
      expect(find.text('BOT'), findsOneWidget);
    });

    // The marker earns its airtime on the wire; in our own transcript
    // the tag says it better, and both would label the row twice.
    test('the marker is stripped for display but kept on the wire', () {
      const String wire = '[bot] pong 1';
      expect(looksLikeBot(wire), isTrue);
      expect(stripBotMarker(wire), 'pong 1');
      expect(labelAsBot('pong 1'), wire);
    });

    test('a message that merely mentions the marker is left alone', () {
      const String human = 'I saw a [bot] earlier';
      expect(looksLikeBot(human), isFalse);
      expect(stripBotMarker(human), human);
    });
  });
}
