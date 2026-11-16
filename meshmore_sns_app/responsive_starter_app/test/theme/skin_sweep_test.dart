// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:meshmore_sns_app/app/demo_mode.dart';
import 'package:meshmore_sns_app/docs/docs_repository.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/meshcore/auto_publish_controller.dart';
import 'package:meshmore_sns_app/peer/peer_profiles.dart';
import 'package:meshmore_sns_app/perms/location_service.dart';
import 'package:meshmore_sns_app/ui/mm_collapse_controller.dart';
import 'package:meshmore_sns_app/app_state_model.dart';
import 'package:meshmore_sns_app/bot/bot_controller.dart';
import 'package:meshmore_sns_app/cue/cue_service.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/legal/terms_controller.dart';
import 'package:meshmore_sns_app/main.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/perms/first_run_controller.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/chat/channel_read_store.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/meshcore/pair_scanner.dart';
import 'package:meshmore_sns_app/sos/sos_controller.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tools/tools_controller.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';

/// The seven-skin sweep: every primary surface is built once per preset.
///
/// The per-feature waves each prove their own seven-preset rendering (places
/// layer, type ladder, SOS, check-in, pairing). What was missing is the other
/// direction: a surface added after its wave could regress under one skin and
/// no test would notice. This walks the six shell views in each of the seven
/// presets and fails on any exception (a `RenderFlex` overflow and a missing
/// provider are both exceptions in a widget test, so the assertion is
/// `takeException`). It does not cover the routed feature screens, which keep
/// their own sweeps.
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

List<SingleChildWidget> _providers(ThemeController theme) =>
    <SingleChildWidget>[
      ChangeNotifierProvider<AppState>(create: (_) => AppState()),
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<TtsController>(
          create: (_) => TtsController(speaker: _SilentSpeaker())),
      Provider<CueService>(
          create: (BuildContext ctx) =>
              CueService(theme: ctx.read<ThemeController>())),
      ChangeNotifierProvider<BotController>(create: (_) => BotController()),
      ChangeNotifierProvider<MeshcoreController>(
          create: (_) => MeshcoreController()),
      Provider<PermissionsService>(create: (_) => NoopPermissionsService()),
      ChangeNotifierProvider<FirstRunController>(
          create: (_) => FirstRunController.preloaded(done: true)),
      ChangeNotifierProvider<LocaleController>(
          create: (_) => LocaleController(initial: const Locale('en'))..load()),
      ChangeNotifierProvider<TermsController>(
          create: (_) => TermsController.accepted()),
      ChangeNotifierProvider<DemoMode>(
          create: (_) => DemoMode.preloaded(enabled: false)),
      ChangeNotifierProvider<MmCollapseController>(
          create: (_) => MmCollapseController()),
      ChangeNotifierProvider<PeerProfiles>(create: (_) => PeerProfiles()),
      ChangeNotifierProvider<ToolsController>(
          create: (BuildContext ctx) =>
              ToolsController(ctx.read<MeshcoreController>())),
      Provider<DocsRepository>(create: (_) => DocsRepository()),
      ChangeNotifierProvider<MapsController>(
          create: (_) => MapsController(appVersion: () => '1.0.0')),
      ChangeNotifierProvider<AutoPublishController>(
          create: (BuildContext ctx) => AutoPublishController(
                mc: ctx.read<MeshcoreController>(),
                location: const GeolocatorLocationService(),
              )),
      // R109 places: the map tab and the chat echo read these, so every
      // harness that builds the shell needs them (as `home_shell_test` does).
      ChangeNotifierProvider<PlaceStore>(create: (_) => PlaceStore()),
      // The SOS and check-in screens read one app-scoped controller, exactly
      // as main.dart registers it; a route in this list without it fails on a
      // missing provider rather than on a layout.
      ChangeNotifierProvider<SosController>(
          create: (BuildContext ctx) =>
              SosController(mc: ctx.read<MeshcoreController>())),
      // The pairing screen's seam: the real scanner is the platform's BLE and
      // cannot run under a widget test, so this harness registers a scanner
      // that reports an adapter that is simply switching on.
      Provider<PairScanner?>.value(value: _OffScanner()),
      ChangeNotifierProvider<BlockStore>(create: (_) => BlockStore()),
      ChangeNotifierProvider<ChannelReadStore?>.value(value: null),
      Provider<PlaceReportBudget>(
          create: (_) => PlaceReportBudget(clock: DateTime.now)),
    ];

/// The pairing screen's seam: the real scanner is the platform's BLE and cannot
/// run under a widget test, so this harness registers a scanner that reports an
/// adapter that is simply off.
class _OffScanner implements PairScanner {
  const _OffScanner();

  @override
  Future<AdapterState> adapterNow() async => AdapterState.off;

  @override
  Stream<AdapterState> get adapter =>
      Stream<AdapterState>.value(AdapterState.off);

  @override
  Stream<List<PairHit>> scan({Duration? timeout}) =>
      Stream<List<PairHit>>.value(const <PairHit>[]);

  @override
  Future<void> stopScan() async {}
}

Future<void> _drain(WidgetTester t) async {
  await t.pump(const Duration(seconds: 4));
}

/// Mounts the shell under one preset. The boot overlay and the first page
/// settle in the same 35 frames the accessibility floor test uses.
Future<void> _pumpShell(WidgetTester t, ThemeController theme) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: _providers(theme),
    child: const MyApp(),
  ));
  for (int i = 0; i < 35; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  const List<String> views = <String>[
    'Dashboard',
    'Chat',
    'Nodes',
    'Hyperlocal grid',
    'Map',
    'Settings',
  ];

  for (final MmThemePreset preset in MmThemePreset.values) {
    testWidgets('${preset.name}: every view builds', (WidgetTester t) async {
      final ThemeController theme = ThemeController();
      await theme.setPreset(preset);
      addTearDown(theme.dispose);

      await _pumpShell(t, theme);
      expect(t.takeException(), isNull,
          reason: '${preset.name}: the shell threw while mounting');

      for (final String view in views) {
        if (view != 'Dashboard') {
          await t.tap(find.byTooltip(view));
          for (int i = 0; i < 8; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }
        expect(t.takeException(), isNull,
            reason: '${preset.name}: $view threw where the other skins do not');
      }
      await _drain(t);
    });
  }
}
