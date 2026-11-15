// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/chat/draft_store.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/notifications/notification_focus.dart';
import 'package:meshmore_sns_app/screens/dm_screen.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

Widget _host(MeshcoreController mc, String peer, [TtsController? tts]) =>
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          // R58 — the DM header's speech tri-state reads this.
          ChangeNotifierProvider<TtsController>(
            create: (_) =>
                tts ?? TtsController(speaker: _SilentSpeaker()),
          ),
        ],
        child: DmScreen(peerPubKeyHex: peer),
      ),
    );

class _SilentSpeaker implements TtsSpeaker {
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> setVoice(TtsVoice? voice) async {}
  @override
  Future<List<TtsVoice>> listVoices() async => const <TtsVoice>[];
  @override
  Future<bool> isLanguageAvailable(String locale) async => false;
}

void main() {
  testWidgets('DM history renders + compose+send emits 0x02',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    // Deterministic peer hex (full 64) — the full inbound prefix→
    // node match is covered by the controller test.
    const String peer =
        'aabbccddeeff' '00000000000000000000000000'
        '00000000000000000000000000';

    // Pump FIRST (testWidgets' fake clock advances only via pump;
    // bare `Future.delayed` inside the test callback hangs).
    await t.pumpWidget(_host(mc, peer));
    await t.pump();
    // Without a radio the composer is the state and its way out, not a
    // disabled field.
    // The empty thread is one line, and it names the state rather than
    // instructing a tap.
    expect(find.textContaining('No messages yet'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('composer-connect')),
        findsOneWidget);

    await mc.connect();
    fake.emit(selfInfoFrame()); // → ready
    await t.pumpAndSettle();

    // Compose + send a DM (outgoing path).
    await t.enterText(find.byType(TextField), 'reply to peer');
    await t.pump();
    await t.tap(find.byIcon(Icons.send));
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));

    expect(fake.sent.any((f) => f.isNotEmpty && f[0] == 0x02), isTrue);
    expect(find.text('reply to peer'), findsOneWidget);
    mc.dispose();
  });

  testWidgets('the thread holds 320 dp at 200 % text on paper',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final ThemeController theme = ThemeController();
    await theme.setPreset(MmThemePreset.air);
    await t.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<TtsController>(
            create: (_) => TtsController(speaker: _SilentSpeaker())),
      ],
      child: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const DmScreen(
            peerPubKeyHex:
                'aabbccddeeff00000000000000000000000000000000000000000000000000',
          ),
        ),
      ),
    ));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    mc.dispose();
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('R58: the DM header sets the per-peer speech tri-state',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const String peer = 'aabbccddeeff00112233445566778899';
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    final TtsController tts = TtsController(speaker: _SilentSpeaker());
    await t.pumpWidget(_host(mc, peer, tts));
    await t.pumpAndSettle();

    expect(tts.peerSpeechMode(peer), PeerSpeechMode.inherit);
    // Inherit + global off → silent, so the header reads muted.
    expect(find.byIcon(Icons.voice_over_off), findsOneWidget);

    await t.tap(find.byIcon(Icons.voice_over_off));
    await t.pumpAndSettle();
    await t.tap(find.text('Always speak'));
    await t.pumpAndSettle();

    expect(tts.peerSpeechMode(peer), PeerSpeechMode.always);
    expect(tts.peerSpeaks(peer), isTrue,
        reason: 'always outranks the global switch');
    expect(find.byIcon(Icons.record_voice_over), findsOneWidget);
    mc.dispose();
  });

  testWidgets('APP-E7: a thread keeps its own unsent text',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const String peer = 'aabbccddeeff00112233445566778899';
    final _MemoryDrafts sink = _MemoryDrafts();
    DraftStore.sinkOverride = sink;
    addTearDown(() => DraftStore.sinkOverride = null);

    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    await t.pumpWidget(_host(mc, peer));
    await t.pump();
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pump();
    await t.pump(const Duration(milliseconds: 10));

    // The radio has now answered, so the thread's draft lives in its
    // namespace; seeding it here exercises the recall, not the save.
    final String key = DraftStore.keyFor(
        DraftStore.radioScope(mc.selfInfo?.publicKey),
        peerHex: peer);
    sink.text[key] = 'half typed';
    // A fresh State so initState recalls what is stored.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(_host(mc, peer));
    await t.pump();
    await t.pump(const Duration(milliseconds: 10));

    expect(find.text('half typed'), findsOneWidget,
        reason: 'the thread hands back what was left in it');

    await t.enterText(find.byType(TextField), 'still typing');
    await t.pump();
    // One write per pause: nothing before the debounce, one after it.
    expect(sink.saves, 0);
    await t.pump(DraftStore.debounce + const Duration(milliseconds: 1));
    expect(sink.saves, 1);
    expect(sink.text[key], 'still typing');
    mc.dispose();
  });
  testWidgets('the claimed thread follows the route stack, not the widget',
      (WidgetTester t) async {
    const String a = 'aa11bb22cc33dd44ee55';
    const String b = '11aa22bb33cc44dd55ee';
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final NotificationFocus focus = NotificationFocus();
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<TtsController>(
            create: (_) => TtsController(speaker: _SilentSpeaker())),
        Provider<NotificationFocus>.value(value: focus),
      ],
      child: MaterialApp(
        navigatorKey: nav,
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const DmScreen(peerPubKeyHex: a),
      ),
    ));
    await t.pump();
    expect(focus.openPeer, a,
        reason: 'the thread on screen is the one being read');

    nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const DmScreen(peerPubKeyHex: b)));
    await t.pumpAndSettle();
    expect(focus.openPeer, b,
        reason: 'the second thread covers the first, so it is the visible one');

    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(focus.openPeer, a,
        reason: 'back on the first thread, its messages must not be announced');
    mc.dispose();
  });
}

/// In-memory stand-in for the sealed file, so the debounce runs in fake time.
class _MemoryDrafts implements DraftSink {
  final Map<String, String> text = <String, String>{};
  int saves = 0;

  @override
  Future<String> read(String key) async => text[key] ?? '';

  @override
  Future<void> save(String key, String value) async {
    // Blank is a removal in the real store, not a row: counting it here would
    // make an emptied composer look like a typed one.
    if (value.trim().isEmpty) {
      text.remove(key);
      return;
    }
    saves++;
    text[key] = value;
  }

  @override
  Future<void> clear(String key) async => text.remove(key);

}

