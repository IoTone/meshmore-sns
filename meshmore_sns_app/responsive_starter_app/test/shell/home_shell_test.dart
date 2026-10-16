// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/app_state_model.dart';
import 'package:meshmore_sns_app/cue/cue_service.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/main.dart';
import 'package:meshmore_sns_app/screens/map_screen.dart';
import 'package:meshmore_sns_app/shell/home_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meshmore_sns_app/bot/bot_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/perms/first_run_controller.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/screens/grid_screen.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';

/// No-op speech backend so the shell tests never touch the
/// `flutter_tts` platform channel.
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

Future<void> _pumpApp(WidgetTester tester,
    {MmThemePreset? preset}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>(create: (_) => AppState()),
        ChangeNotifierProvider<ThemeController>(
          create: (_) {
            final ThemeController tc = ThemeController();
            if (preset != null) tc.setPreset(preset);
            return tc;
          },
        ),
        ChangeNotifierProvider<TtsController>(
          create: (_) => TtsController(speaker: _SilentSpeaker()),
        ),
        Provider<CueService>(
          create: (BuildContext ctx) =>
              CueService(theme: ctx.read<ThemeController>()),
        ),
        // R59 — HomeShell builds a BotBridge, so the bot must be
        // above it exactly as in main.dart.
        ChangeNotifierProvider<BotController>(
          create: (_) => BotController(),
        ),
        ChangeNotifierProvider<MeshcoreController>(
          create: (_) => MeshcoreController(),
        ),
        Provider<PermissionsService>(
          create: (_) => NoopPermissionsService(),
        ),
        ChangeNotifierProvider<FirstRunController>(
          create: (_) => FirstRunController.preloaded(done: true),
        ),
        ChangeNotifierProvider<LocaleController>(
          create: (_) =>
              LocaleController(initial: const Locale('en'))..load(),
        ),
      ],
      child: const MyApp(),
    ),
  );
  if (preset == null) {
    await tester.pumpAndSettle();
  } else {
    // Some skins animate on the dashboard forever (scanlines etc.), so
    // pumpAndSettle would never return; timed pumps instead, long enough
    // to clear the 2.2 s branded splash.
    for (int i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

void main() {
  testWidgets('shell starts on Dashboard (R8 home)', (WidgetTester t) async {
    await _pumpApp(t);
    expect(find.widgetWithText(AppBar, 'Dashboard'), findsOneWidget);
  });

  testWidgets('the view strip jumps views (R11, R64)',
      (WidgetTester t) async {
    await _pumpApp(t);
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
    // Settings hub shows the three sub-screen entries.
    expect(find.text('Device configuration'), findsOneWidget);
    expect(find.text('App settings'), findsOneWidget);
    expect(find.text('Profile & personalization'), findsOneWidget);
  });

  testWidgets('there is no switcher menu, only the strip (R64)',
      (WidgetTester t) async {
    await _pumpApp(t);
    expect(find.byIcon(Icons.menu_open), findsNothing);
    expect(find.bySemanticsLabel('Quick navigation'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    final AppBar bar = t.widget<AppBar>(find.byType(AppBar));
    expect(bar.leading, isNull);
  });

  testWidgets('the strip is the accessible path: one labelled 48dp button '
      'per view, current one selected (R64)', (WidgetTester t) async {
    final SemanticsHandle h = t.ensureSemantics();
    await _pumpApp(t);
    for (final MmView v in MmView.values) {
      final String label = const <MmView, String>{
        MmView.dashboard: 'Dashboard',
        MmView.chat: 'Chat',
        MmView.nodes: 'Nodes',
        MmView.grid: 'Hyperlocal grid',
        MmView.map: 'Map',
        MmView.settings: 'Settings',
        MmView.docs: 'Docs',
        MmView.about: 'About',
      }[v]!;
      final Finder tip = find.byTooltip(label);
      expect(tip, findsOneWidget, reason: '$label has a strip button');
      final Size size = t.getSize(tip);
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
    }
    SemanticsNode node(String tip) => t.getSemantics(find.byTooltip(tip));
    expect(node('Dashboard').label, 'Dashboard');
    // ignore: deprecated_member_use
    expect(node('Dashboard').hasFlag(SemanticsFlag.isButton), isTrue);
    // ignore: deprecated_member_use
    expect(node('Dashboard').hasFlag(SemanticsFlag.isSelected), isTrue);
    // ignore: deprecated_member_use
    expect(node('Chat').hasFlag(SemanticsFlag.isSelected), isFalse);
    h.dispose();
  });

  testWidgets('the strip fits a 320dp-wide phone by scrolling, and keeps '
      'the current view in sight (R64)', (WidgetTester t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await _pumpApp(t);
    expect(t.takeException(), isNull, reason: 'no overflow at 320dp');
    await t.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await t.pumpAndSettle();
    await t.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Nodes'), findsOneWidget);
    final Rect r = t.getRect(find.byTooltip('Nodes'));
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(320));
  });

  testWidgets('horizontal swipe pages between views (R11)',
      (WidgetTester t) async {
    await _pumpApp(t);
    expect(find.widgetWithText(AppBar, 'Dashboard'), findsOneWidget);
    await t.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Chat'), findsOneWidget);
  });

  testWidgets('Back from a non-Dashboard tab returns to Dashboard '
      '(no root-pop crash)', (WidgetTester t) async {
    await _pumpApp(t);
    await t.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Chat'), findsOneWidget);

    // System Back: PopScope must consume it (not pop the root) and
    // route us back to the Dashboard.
    final bool handled = await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.widgetWithText(AppBar, 'Dashboard'), findsOneWidget);
    expect(t.takeException(), isNull); // no root-pop exception
  });

  testWidgets('app resume drives the lifecycle hook without crashing '
      '(R17)', (WidgetTester t) async {
    await _pumpApp(t);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.widgetWithText(AppBar, 'Dashboard'), findsOneWidget);
  });

  // The grid tab runs a repeating animation, so once it is on screen
  // these use timed pumps — pumpAndSettle would never settle.
  Future<void> settle(WidgetTester t) async {
    for (int i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the hyperlocal grid is the tab after Nodes, and shows '
      'offline as an empty radar (issue #4)', (WidgetTester t) async {
    GridScreen.resetSession();
    await _pumpApp(t);
    await t.tap(find.byTooltip('Nodes'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Nodes'), findsOneWidget);
    // The old entry point is gone from Nodes.
    expect(find.widgetWithIcon(IconButton, Icons.radar), findsNothing);

    await t.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await settle(t);
    expect(find.widgetWithText(AppBar, 'Hyperlocal grid'), findsOneWidget);
    expect(find.text('Not Connected to Mesh'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a panning grid view locks the shell swipe; the radar '
      'does not', (WidgetTester t) async {
    GridScreen.resetSession();
    await _pumpApp(t);
    await t.tap(find.byTooltip('Hyperlocal grid'));
    await settle(t);
    expect(find.widgetWithText(AppBar, 'Hyperlocal grid'), findsOneWidget);

    // Stand in for picking a pannable view (street map, globe, …).
    GridScreen.capturesHorizontalDrag.value = true;
    await t.pump();
    await t.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await settle(t);
    expect(find.widgetWithText(AppBar, 'Hyperlocal grid'), findsOneWidget);

    GridScreen.capturesHorizontalDrag.value = false;
    await t.pump();
    await t.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await settle(t);
    // The tab after the grid is Map (R61), then Settings.
    expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget);
    // Leaving the tab frees the swipe for everyone else.
    expect(GridScreen.capturesHorizontalDrag.value, isFalse);
  });

  Future<void> openFromStrip(WidgetTester t, String label) async {
    await t.tap(find.byTooltip(label));
    await settle(t);
  }

  testWidgets('Map is a swipe page right after the grid, in every skin '
      '(R61)', (WidgetTester t) async {
    // The shell never reads the skin to build its pages, so each preset
    // gets the same seven-plus-one views; prove it per preset rather
    // than assume it.
    expect(MmView.values, <MmView>[
      MmView.dashboard,
      MmView.chat,
      MmView.nodes,
      MmView.grid,
      MmView.map,
      MmView.settings,
      MmView.docs,
      MmView.about,
    ]);
    for (final MmThemePreset preset in MmThemePreset.values) {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      GridScreen.resetSession();
      // Unmount the previous skin's tree, or Provider keeps its controller.
      await t.pumpWidget(const SizedBox());
      await _pumpApp(t, preset: preset);
      expect(t.element(find.byType(HomeShell)).read<ThemeController>().preset,
          preset,
          reason: 'the skin under test is actually applied');
      await openFromStrip(t, 'Hyperlocal grid');
      await t.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await settle(t);
      expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget,
          reason: '${preset.name}: swipe from the grid lands on Map');
      expect(find.byType(MapScreen), findsOneWidget);
      expect(find.byTooltip('Offline maps'), findsOneWidget,
          reason: 'the pack manager is one tap from the map');
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('the Map tab owns horizontal drags; Back and the '
      'view strip still leave it (R61)', (WidgetTester t) async {
    GridScreen.resetSession();
    await _pumpApp(t);
    await openFromStrip(t, 'Map');
    expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget);

    // The lock is unconditional: no notifier needs to be flipped.
    expect(GridScreen.capturesHorizontalDrag.value, isFalse);
    await t.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await settle(t);
    expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget,
        reason: 'a left swipe must not leave the map');
    await t.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await settle(t);
    expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget,
        reason: 'nor a right swipe');

    // The strip leaves.
    await openFromStrip(t, 'Settings');
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);

    // The swipe is free again off the map.
    await t.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await settle(t);
    expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget);

    // Back from the map returns to the Dashboard.
    final bool handled = await t.binding.handlePopRoute();
    await settle(t);
    expect(handled, isTrue);
    expect(find.widgetWithText(AppBar, 'Dashboard'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
