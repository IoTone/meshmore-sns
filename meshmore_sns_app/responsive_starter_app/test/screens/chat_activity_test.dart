// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/chat_screen.dart';
import 'package:meshmore_sns_app/screens/meshbook_view.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';

import '../meshcore/fake_transport.dart';

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
  Future<bool> isLanguageAvailable(String locale) async => true;
}

/// The channel's activity report lives on the channel, not in the grid's view
/// picker: one tap from the strip that names the channel it describes, in a
/// sheet, in every skin and at the accessibility floor.
Widget _host(MeshcoreController mc, TtsController tts, ThemeController theme) =>
    MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<TtsController>.value(value: tts),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
      ],
      child: Builder(
        builder: (BuildContext c) => MaterialApp(
          theme: c.read<ThemeController>().theme,
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: ChatScreen()),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('the chat strip opens the channel activity report',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final TtsController tts = TtsController(speaker: _SilentSpeaker());
    final ThemeController theme = ThemeController();
    await t.pumpWidget(_host(mc, tts, theme));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    // One tap, not two: the report is about the selected channel, so it has
    // its own control beside the strip's overflow rather than a row inside a
    // menu where actions hide.
    await t.tap(find.byKey(const ValueKey<String>('chat-activity-visible')));
    await t.pumpAndSettle();

    expect(find.byType(MeshbookView), findsOneWidget);
    expect(find.text('MESHBOOK'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    // Disposed inside the body: the controller's battery poll is a periodic
    // timer, and the harness checks for pending timers before tear-downs run.
    mc.dispose();
  });

  testWidgets('the report holds in every skin at 320 dp and 200 % text',
      (WidgetTester t) async {
    // The narrowest width the app claims, at the largest text scale it
    // promises: a sheet is its own route, so it needs its own floor check.
    t.view.physicalSize = const Size(320, 780);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final TtsController tts = TtsController(speaker: _SilentSpeaker());
    final ThemeController theme = ThemeController();
    await mc.connect();
    fake.emit(selfInfoFrame());

    for (final MmThemePreset preset in MmThemePreset.values) {
      await theme.setPreset(preset);
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: _host(mc, tts, theme),
      ));
      await t.pumpAndSettle();
      // Straight to the report. Opening the strip's overflow menu first left
      // its barrier over the button, so the second tap dismissed the menu and
      // the sheet never opened — the test passed only while the overflow
      // control happened to be scrolled off the 320 dp viewport.
      await t.tap(
          find.byKey(const ValueKey<String>('chat-activity-visible')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'preset ${preset.name}');
      expect(find.byType(MeshbookView), findsOneWidget,
          reason: 'preset ${preset.name}');
      await t.pumpWidget(const SizedBox());
    }
    mc.dispose();
  });
}
