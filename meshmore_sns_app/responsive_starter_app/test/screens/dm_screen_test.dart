// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_connection.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/dm_screen.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';

import '../meshcore/fake_transport.dart';

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
    expect(find.text('— no messages yet —'), findsOneWidget);

    await mc.connect();
    fake.emit(selfInfoFrame()); // → ready
    await t.pump();
    await t.pump(const Duration(milliseconds: 10));

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
}
