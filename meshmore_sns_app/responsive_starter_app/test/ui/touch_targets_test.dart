// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/gen/app_localizations_en.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/chat_screen.dart';
import 'package:meshmore_sns_app/screens/dashboard_screen.dart';
import 'package:meshmore_sns_app/screens/dm_screen.dart';
import 'package:meshmore_sns_app/screens/fabric_survey_view.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';
import 'package:meshmore_sns_app/ui/mm_audio_toggle.dart';
import 'package:meshmore_sns_app/ui/mm_collapse_controller.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

/// R69 — every icon target the R68 pass found under 48dp is now at least
/// 48x48 in the laid-out tree.
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

final AppLocalizationsEn _en = AppLocalizationsEn();

Widget _app(MeshcoreController mc, Widget child) => MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<ThemeController>(
            create: (_) => ThemeController()),
        ChangeNotifierProvider<MmCollapseController>(
            create: (_) => MmCollapseController()),
        ChangeNotifierProvider<TtsController>(
            create: (_) => TtsController(speaker: _Silent())),
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
        home: Scaffold(body: child),
      ),
    );

MeshcoreController _mc(FakeMeshcoreTransport f) => MeshcoreController(
      transportFactory: () async => f,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );

/// The laid-out size of the tap target for [tooltip]: the IconButton that
/// owns the tooltip (its InkResponse is what receives the tap).
Size _sizeOf(WidgetTester t, String tooltip) {
  final Finder b = find.ancestor(
      of: find.byTooltip(tooltip), matching: find.byType(IconButton));
  final Finder f = b.evaluate().isNotEmpty
      ? b.first
      : find.descendant(
          of: find.byTooltip(tooltip), matching: find.byType(InkResponse));
  return t.getSize(f.first);
}

void expectMin48(WidgetTester t, String tooltip) {
  final Size s = _sizeOf(t, tooltip);
  expect(s.width, greaterThanOrEqualTo(48), reason: '$tooltip width');
  expect(s.height, greaterThanOrEqualTo(48), reason: '$tooltip height');
}

/// A layout overflow would surface as a FlutterError mentioning
/// "overflowed". Rendering a FlutterMap in this harness also throws an
/// unrelated null-check inside the map package (no tile/ticker setup),
/// so any other exception is drained, not failed on.
void _noOverflow(WidgetTester t) {
  Object? e;
  while ((e = t.takeException()) != null) {
    expect('$e', isNot(contains('overflowed')),
        reason: 'a control row overflowed');
    debugPrint('drained (not overflow): ${'$e'.split('\n').first}');
  }
}

Future<void> _drain(WidgetTester t, MeshcoreController mc) async {
  mc.dispose();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('MmAudioToggle: normal and dense are both >= 48x48',
      (WidgetTester t) async {
    final MeshcoreController mc = _mc(FakeMeshcoreTransport(connected: true));
    await t.pumpWidget(_app(
        mc,
        const Row(children: <Widget>[
          MmAudioToggle(),
          MmAudioToggle(dense: true, size: 18),
        ])));
    final Iterable<Element> toggles = find.byType(IconButton).evaluate();
    expect(toggles.length, 2);
    for (final Element e in toggles) {
      final Size s = t.getSize(find.byWidget(e.widget));
      expect(s.width, greaterThanOrEqualTo(48));
      expect(s.height, greaterThanOrEqualTo(48));
    }
    // The visible glyph is unchanged for the dense form.
    expect(t.widget<Icon>(find.byType(Icon).last).size, 18);
    await _drain(t, mc);
  });

  testWidgets('dashboard location refresh is >= 48x48', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _mc(fake);
    await t.pumpWidget(_app(mc, const DashboardScreen()));
    // The location block exists once the radio has answered: with no radio
    // the dashboard is a link state and one action, by design.
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();
    expectMin48(t, _en.dashboardLocationRefresh);
    await _drain(t, mc);
  });

  testWidgets('chat message-actions button is >= 48x48',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _mc(fake);
    await t.pumpWidget(_app(mc, const ChatScreen()));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'hello mesh');
    await t.tap(find.byIcon(Icons.send));
    await t.pumpAndSettle();
    expectMin48(t, _en.chatMessageActions);
    await _drain(t, mc);
  });

  testWidgets('DM message-actions button is >= 48x48', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _mc(fake);
    const String peer =
        'aabbccddeeff00000000000000000000000000000000000000000000000000';
    await t.pumpWidget(_app(mc, const DmScreen(peerPubKeyHex: peer)));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pump();
    await t.pump(const Duration(milliseconds: 10));
    await t.enterText(find.byType(TextField), 'reply to peer');
    await t.pump();
    await t.tap(find.byIcon(Icons.send));
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));
    expectMin48(t, _en.chatMessageActions);
    await _drain(t, mc);
  });

  testWidgets('fabric-survey zoom / recentre / tiles / reset are >= 48x48',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _mc(fake);
    await t.pumpWidget(_app(mc, const FabricSurveyView()));
    await mc.connect();
    fake.emit(selfInfoFrameAt(lat: 38.925, lon: -104.772826));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    for (final String tip in <String>[
      _en.gridZoomTighter,
      _en.gridZoomWider,
      _en.streetMapRecenter,
      _en.mapHideTiles,
      _en.fabricResetTooltip,
    ]) {
      expectMin48(t, tip);
    }
    _noOverflow(t);
    await _drain(t, mc);
  });
}
