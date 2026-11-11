// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/chat_screen.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';

import '../meshcore/fake_transport.dart';

/// The send time is revealed, not printed.
///
/// A channel thread where every line carries `16:07` reads as a log file, and
/// on a busy channel the stamps are most of the ink. The stamp appears when the
/// reader asks for it — hold the row, or open its actions — and stays for that
/// row, because hiding it again under the reader's eyes is its own hostility.
class _Silent implements TtsSpeaker {
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

// The terminal log puts the direction glyph beside the stamp ("16:07 »"),
// so the matcher cannot be anchored.
final RegExp stamp = RegExp(r'\d\d:\d\d');

Future<MeshcoreController> _pump(WidgetTester t, MmThemePreset preset) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await t.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
  final MeshcoreController mc = MeshcoreController(
    transportFactory: () async => fake,
    connection: MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  final ThemeController theme = ThemeController()..setPreset(preset);
  await t.pumpWidget(MultiProvider(
    providers: <SingleChildWidget>[
      ChangeNotifierProvider<MeshcoreController>.value(value: mc),
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<TtsController>(
          create: (_) => TtsController(speaker: _Silent())),
      ChangeNotifierProvider<PlaceStore>(create: (_) => PlaceStore()),
      Provider<PlaceReportBudget>(
          create: (_) => PlaceReportBudget(clock: DateTime.now)),
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
      home: Scaffold(body: ChatScreen(isCurrent: true)),
    ),
  ));
  await mc.connect();
  fake.emit(selfInfoFrame());
  await t.pumpAndSettle();
  fake.emit(channelMsgFrame(text: 'MikeP: a long line of ordinary prose'));
  await t.pumpAndSettle();
  return mc;
}

void main() {
  for (final MmThemePreset preset in <MmThemePreset>[
    MmThemePreset.seele,
    MmThemePreset.studio,
    MmThemePreset.hyperlocal,
    MmThemePreset.drPop,
  ]) {
    testWidgets('${preset.name}: no stamp until asked, then it is there',
        (WidgetTester t) async {
      final MeshcoreController mc = await _pump(t, preset);
      expect(find.textContaining(stamp), findsNothing,
          reason: '${preset.name} printed a time nobody asked for');

      // The actions button on the row is one of the two ways in.
      // Two ways in, and both must work: the actions button where the row has
      // one, and the hold everywhere.
      final Finder actions = find.byTooltip('Message actions');
      if (actions.evaluate().isNotEmpty) {
        await t.tap(actions.first);
        await t.pumpAndSettle();
      } else {
        // The bubble and block rows carry no visible actions button: the hold
        // is the affordance they have, and it reveals the same stamp.
        await t.longPress(
            find.text('a long line of ordinary prose').first);
        await t.pumpAndSettle();
      }
      // The sheet is open over the row; the stamp is on the row behind it.
      expect(find.textContaining(stamp), findsWidgets,
          reason: '${preset.name} did not reveal the stamp from its actions');

      // Dismiss the sheet and confirm the stamp stays for that row.
      await t.tapAt(const Offset(210, 40));
      await t.pumpAndSettle();
      expect(find.textContaining(stamp), findsWidgets,
          reason: '${preset.name} hid the stamp again after showing it');
      mc.dispose();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 30));
    });
  }
}
