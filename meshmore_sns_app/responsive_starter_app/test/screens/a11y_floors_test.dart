// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:meshmore_sns_app/app/demo_mode.dart';
import 'package:meshmore_sns_app/app_router.dart';
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
import 'package:meshmore_sns_app/notifications/channel_notification_prefs.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/chat/channel_read_store.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/geofence/geofence_controller.dart';
import 'package:meshmore_sns_app/telemetry/coverage_session.dart';
import 'package:meshmore_sns_app/meshcore/pair_scanner.dart';
import 'package:meshmore_sns_app/sos/sos_controller.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tools/tools_controller.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';

/// APP-K2: the product honours text up to 200 %, and the shell has to survive
/// it at the narrowest width the app claims to support (320 dp).
///
/// A RenderFlex overflow is an exception in a widget test, so `takeException`
/// is the assertion: any surface that clips its own content fails here rather
/// than on a user's phone. Six views, one test each, at 320 dp and 2.0 text.
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

List<SingleChildWidget> _providers() => <SingleChildWidget>[
      ChangeNotifierProvider<AppState>(create: (_) => AppState()),
      ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
      ChangeNotifierProvider<TtsController>(
          create: (_) => TtsController(speaker: _SilentSpeaker())),
      Provider<CueService>(
          create: (BuildContext ctx) =>
              CueService(theme: ctx.read<ThemeController>())),
      ChangeNotifierProvider<BotController>(create: (_) => BotController()),
      // App settings reads the per-channel notification store for its Public
      // channel switch, so the floor sweep has to provide it as the app does.
      ChangeNotifierProvider<NotificationPrefs>(
          create: (_) => NotificationPrefs()),
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
      // Fences sample on a one-second tick; a real timer would race the
      // harness, so this one samples by hand like the alarm's own harness.
      ChangeNotifierProvider<GeofenceController>(
          create: (BuildContext ctx) => GeofenceController(
                mc: ctx.read<MeshcoreController>(),
                autoTick: false,
              )),
      // Coverage is session state with no radio under a widget test: the
      // screen has to render its "not started" state, which is the state a
      // user meets first anyway.
      ChangeNotifierProvider<CoverageSession>(
          create: (BuildContext ctx) =>
              CoverageSession(mc: ctx.read<MeshcoreController>())),
      // The pairing screen's seam: the real scanner is the platform's BLE and
      // cannot run under a widget test, so this harness registers a scanner
      // that reports an adapter that is simply switching on.
      Provider<PairScanner?>.value(value: _OffScanner()),
      ChangeNotifierProvider<BlockStore>(create: (_) => BlockStore()),
      ChangeNotifierProvider<ChannelReadStore?>.value(value: null),
      Provider<PlaceReportBudget>(
          create: (_) => PlaceReportBudget(clock: DateTime.now)),
    ];

/// The street map's tile layer arms a three-second timer when it mounts.
/// A widget test that ends with it pending fails on the harness invariant,
/// not on anything the app did, so every case drains fake time first.
Future<void> _drain(WidgetTester t) async {
  await t.pump(const Duration(seconds: 4));
}

Future<void> _pumpShell(WidgetTester t) async {
  t.view.physicalSize = const Size(320, 780);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: _providers(),
    // The app multiplies the OS scale by the user scale; 2.0 here is the
    // floor the product promises, not a decorative setting.
    child: const MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
      child: MyApp(),
    ),
  ));
  for (int i = 0; i < 35; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  const List<String> views = <String>[
    'Dashboard',
    'Chat',
    'Nodes',
    'Hyperlocal grid',
    'Map',
    'Settings',
  ];

  for (final String view in views) {
    testWidgets('$view survives 320 dp at 200 % text', (WidgetTester t) async {
      await _pumpShell(t);
      if (view != 'Dashboard') {
        await t.tap(find.byTooltip(view));
        for (int i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }
      expect(t.takeException(), isNull,
          reason: '$view overflowed at the accessibility floor');
      await _drain(t);
    });
  }

  // R115 — the floor is a property of the layout, not of one skin: every
  // preset is built at the same width and scale. A light ground changes
  // contrast and the Material brightness, so it is exactly the case that
  // regresses spacing if a surface assumes dark paint.
  testWidgets('every preset holds 320 dp at 200 % text',
      (WidgetTester t) async {
    await _pumpShell(t);
    final ThemeController tc = Provider.of<ThemeController>(
        t.element(find.byType(MyApp)),
        listen: false);
    for (final MmThemePreset preset in MmThemePreset.values) {
      await tc.setPreset(preset);
      await t.pump();
      for (final String view in views) {
        // Every view is TAPPED, the dashboard included: skipping it left the
        // view from the previous iteration on screen, so after the first preset
        // the dashboard was never measured again — which is how three overflow
        // bugs in one skin's dashboard survived this test.
        await t.tap(find.byTooltip(view));
        for (int i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull,
            reason: '${preset.name} $view overflowed at the floor');
      }
    }
    await _drain(t);
  });

  // APP-K1 — a control with no text needs a name. The shell's two icon-only
  // surfaces are the strip cells and the link chip; both carry one, and this
  // pins it so a restyle cannot drop it.
  testWidgets('every strip cell is a named, selected-aware button',
      (WidgetTester t) async {
    final SemanticsHandle handle = t.ensureSemantics();
    await _pumpShell(t);
    for (final String view in views) {
      expect(find.bySemanticsLabel(view), findsAtLeastNWidgets(1),
          reason: '$view has no semantics label on the strip');
    }
    expect(
        t.getSemantics(find.byTooltip('Dashboard')),
        matchesSemantics(
          label: 'Dashboard',
          isButton: true,
          isSelected: true,
          hasTapAction: true,
          hasSelectedState: true,
        ));
    await _drain(t);
    handle.dispose();
  });

  testWidgets('the link chip names its state for a screen reader',
      (WidgetTester t) async {
    final SemanticsHandle handle = t.ensureSemantics();
    await _pumpShell(t);
    expect(
        find.byWidgetPredicate((Widget w) =>
            w is Semantics &&
            (w.properties.label ?? '').isNotEmpty &&
            w.properties.button == true),
        findsAtLeastNWidgets(1),
        reason: 'the app-bar link chip lost its semantics');
    await _drain(t);
    handle.dispose();
  });

  // The Settings sub-screens are one tap away; a floor that only holds on the
  // six primary views is not a floor. Each is opened through the real router.
  const List<String> routes = <String>[
    '/settings/blocks',
    '/chat/search',
    '/settings/device',
    '/settings/channels',
    '/settings/app',
    '/settings/profile',
    '/settings/location',
    '/settings/diagnostics',
    '/connect',
    '/settings/networks',
    '/settings/battery',
    '/settings/about',
    '/settings/docs',
    '/settings/terms',
    '/settings/maps',
    '/settings/maps/new',
    '/settings/maps/selftest',
    '/settings/tools',
    // One route per tool: the sub-screens are separate layouts and two of
    // them (stats, range) carry the widest readouts in the app.
    '/settings/tools/stats',
    '/settings/tools/ping',
    '/settings/tools/trace',
    '/settings/tools/discover',
    '/settings/tools/soak',
    '/settings/tools/range',
    '/settings/voice',
    '/settings/location',
    '/settings/geofences',
    '/settings/coverage',
    // The docs reader renders long prose; it is the one route where a
    // heading and a paragraph share a row.
    '/docs/protocol',
    '/docs/firmware',
    '/docs/app',
    '/docs/devices',
    // A direct-message thread: a fixed-height chrome row and a composer sit
    // under a long, unbroken public key.
    '/dm/0000000000000000000000000000000000000000000000000000000000000000',
    // The three screens added by the field-operations and pairing waves. SOS
    // matters most here: it is used one-handed, under stress, often at 200 %.
    '/sos',
    '/checkin',
    '/pair',
  ];
  // The routes a user reaches least often are the ones nobody re-reads on a new
  // skin, and two of them are prose on paper. Each is rendered in every preset
  // at the floor, with the transition settled before the assertion: a route
  // measured mid-animation reports the outgoing screen's constraints.
  const List<String> deepRoutes = <String>[
    '/docs/protocol',
    '/settings/networks',
    '/settings/about',
    '/settings/docs',
    // The tool screens carry the widest readouts in the app: a table of RTTs,
    // a noise floor, a hop trace.
    '/settings/tools/stats',
    '/settings/tools/ping',
    '/settings/tools/range',
    '/settings/tools/soak',
    // The three used one-handed, outdoors, often at 200 %.
    '/sos',
    '/checkin',
    '/pair',
  ];
  // The deep routes are checked once per *layout shape* rather than once per
  // skin. What can overflow a sheet is the skin's geometry — corner style,
  // control shape, whether headings are upper-cased, the type scale — and eleven
  // presets share about four of those between them; the other seven differ in
  // colour, which the contrast tests own. Sweeping all eleven over twenty-odd
  // routes was most of this file's fifty seconds and found nothing the four
  // shapes do not.
  final List<MmThemePreset> shapes = <MmThemePreset>[];
  final Set<String> seenShapes = <String>{};
  for (final MmThemePreset preset in MmThemePreset.values) {
    final MmSkin skin = mmSkinFor(preset);
    final String signature = <Object>[
      skin.shape.corner,
      skin.shape.squareControls,
      skin.type.upperHeadings,
      skin.type.sizeBody,
      skin.type.monoFamily,
    ].join('|');
    if (seenShapes.add(signature)) shapes.add(preset);
  }

  for (final String route in deepRoutes) {
    testWidgets('$route holds the floor on every layout shape',
        (WidgetTester t) async {
      addTearDown(() => appRouter.go('/'));
      for (final MmThemePreset preset in shapes) {
        await _pumpShell(t);
        final ThemeController tc = Provider.of<ThemeController>(
            t.element(find.byType(MyApp)),
            listen: false);
        await tc.setPreset(preset);
        for (int i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        appRouter.go(route);
        for (int i = 0; i < 16; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull,
            reason: '$route overflowed at 320 dp / 200 % on ${preset.name}');
        appRouter.go('/');
        for (int i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }
    });
  }

  for (final String route in routes) {
    testWidgets('$route survives 320 dp at 200 % text', (WidgetTester t) async {
      addTearDown(() => appRouter.go('/'));
      await _pumpShell(t);
      appRouter.go(route);
      for (int i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull,
          reason: '$route overflowed at the accessibility floor');
      await _drain(t);
    });
  }
}

/// A scanner the accessibility floor can build: nothing is found and the
/// adapter waits, which is one of the screen's real states.
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
