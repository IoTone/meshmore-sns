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

/// The send time is in the message's own sheet, and nowhere else.
///
/// A channel thread where every line carries `16:07` reads as a log file, and on
/// a busy channel the stamps are most of the ink. An earlier version revealed
/// the stamp on the row when it was held, which widened a column mid-thread and
/// moved every line sideways under the reader's finger as they reached for the
/// menu. The time is a property of the message, so it is the first line of the
/// sheet you open to act on that message.
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
    testWidgets('${preset.name}: the stamp is in the sheet, not on the row',
        (WidgetTester t) async {
      final MeshcoreController mc = await _pump(t, preset);
      expect(find.textContaining(stamp), findsNothing,
          reason: '${preset.name} printed a time nobody asked for');

      // Open the message's actions. The sheet's first line is the time, with
      // whatever else the row has no space for.
      final Finder actions = find.byTooltip('Message actions');
      if (actions.evaluate().isNotEmpty) {
        await t.tap(actions.first);
      } else {
        await t.longPress(find.text('a long line of ordinary prose').first);
      }
      await t.pumpAndSettle();
      expect(find.textContaining(stamp), findsOneWidget,
          reason: '${preset.name} did not put the stamp in the sheet');

      // Close the sheet: the stamp goes with it, and the row never grew one.
      await t.tapAt(const Offset(210, 40));
      await t.pumpAndSettle();
      expect(find.textContaining(stamp), findsNothing,
          reason: '${preset.name} left a stamp on the row');
      mc.dispose();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 30));
    });
  }
}
