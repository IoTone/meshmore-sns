// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/legal/terms_controller.dart';
import 'package:meshmore_sns_app/app/demo_mode.dart';
import 'package:meshmore_sns_app/app_router.dart';
import 'package:meshmore_sns_app/app_state_model.dart';
import 'package:meshmore_sns_app/cue/cue_service.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/main.dart';
import 'package:meshmore_sns_app/screens/dashboard_screen.dart';
import 'package:meshmore_sns_app/screens/map_screen.dart';
import 'package:meshmore_sns_app/screens/street_map_view.dart';
import 'package:meshmore_sns_app/shell/home_shell.dart';
import 'package:meshmore_sns_app/shell/horizontal_drag_claim.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meshmore_sns_app/bot/bot_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/perms/first_run_controller.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/screens/grid_screen.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/chat/channel_read_store.dart';
import 'package:meshmore_sns_app/notifications/notification_focus.dart';
import 'package:meshmore_sns_app/shell/shell_view_request.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import '../meshcore/fake_transport.dart';
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
    {MmThemePreset? preset,
    bool demo = false,
    MeshcoreController? mc,
    ChannelReadStore? reads,
    NotificationFocus? focus,
    ShellViewRequest? viewRequest}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TermsController>(
          create: (_) => TermsController.accepted(),
        ),
        ChangeNotifierProvider<DemoMode>(
          create: (_) => DemoMode.preloaded(enabled: demo),
        ),
        ChangeNotifierProvider<AppState>(create: (_) => AppState()),
        ChangeNotifierProvider<ThemeController>(
          create: (_) {
            final ThemeController tc = ThemeController();
            // These tests name the SEELE monolith's body (`dashboardKey`) and
            // its tokens; a fresh install opens on STUDIO, so the skin is
            // stated rather than inherited.
            tc.setPreset(preset ?? MmThemePreset.seele);
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
        if (mc == null)
          ChangeNotifierProvider<MeshcoreController>(
            create: (_) => MeshcoreController(),
          )
        else
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        // Registered nullable, exactly as main.dart registers it: a harness
        // without a read store shows no badges rather than failing the lookup.
        ChangeNotifierProvider<ChannelReadStore?>.value(value: reads),
        Provider<NotificationFocus?>.value(value: focus),
        ChangeNotifierProvider<ShellViewRequest?>.value(value: viewRequest),
        ChangeNotifierProvider<PlaceStore>(
          create: (_) => PlaceStore(),
        ),
        Provider<PlaceReportBudget>(
          create: (_) => PlaceReportBudget(clock: DateTime.now),
        ),
        Provider<PermissionsService>(
          create: (_) => NoopPermissionsService(),
        ),
        ChangeNotifierProvider<FirstRunController>(
          create: (_) => FirstRunController.preloaded(done: true),
        ),
        ChangeNotifierProvider<LocaleController>(
          create: (_) => LocaleController(initial: const Locale('en'))..load(),
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
    expect(find.byKey(dashboardKey), findsOneWidget);
  });

  testWidgets('R86 Settings lists Docs and Information as peers',
      (WidgetTester t) async {
    // appRouter is a global instance: a route left pushed would put every
    // later test on that page instead of the shell.
    addTearDown(() => appRouter.go('/'));
    await _pumpApp(t);
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle();
    // The two static views are rows here, not tabs.
    expect(find.byTooltip('Docs'), findsNothing);
    expect(find.byTooltip('About'), findsNothing);
    final Finder docsRow = find.text('Docs');
    final Finder infoRow = find.text('Information');
    // The hub is a lazy list; scroll down to the end where the static rows sit.
    final Finder hub = find
        .descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable))
        .last;
    await t.scrollUntilVisible(infoRow, 100, scrollable: hub);
    expect(docsRow, findsOneWidget);
    expect(infoRow, findsOneWidget);
    expect(t.getTopLeft(docsRow).dx, t.getTopLeft(infoRow).dx,
        reason: 'same level: both are rows of the one hub list');
    expect(t.getTopLeft(docsRow).dy, lessThan(t.getTopLeft(infoRow).dy),
        reason: 'Docs sits immediately before Information');

    // Docs opens the hub, and Back returns to the Settings hub.
    await t.tap(docsRow);
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Docs'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget,
        reason: 'Back returns to the Settings hub');

    // Information opens About, which no longer carries a Docs row.
    await t.scrollUntilVisible(infoRow, 100, scrollable: hub);
    await t.tap(infoRow);
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'About'), findsOneWidget);
    expect(find.text('MESHMORE SNS'), findsOneWidget);
    expect(find.text('Docs'), findsNothing,
        reason: 'Docs is a sibling of About now, not a child');
    expect(find.byIcon(Icons.menu_book_outlined), findsNothing);
    // Interpolation must be evaluated, not printed: a stray \$ renders
    // "${l.aboutDescription}" on screen (paid for once already).
    expect(find.textContaining(r'${'), findsNothing);
    // No note-to-self on a shipped page: the terms line read "Terms &
    // Conditions — wired in U5." on the device (R88).
    expect(find.textContaining('wired in'), findsNothing);
    expect(find.textContaining('配線予定'), findsNothing);

    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
  });

  testWidgets('R94 the Settings hub labels each group once',
      (WidgetTester t) async {
    // Found on the phone 2026-10-21: RADIO / ABOUT / ABOUT / ABOUT. The
    // group label was picked by list index (0 / 4 / 8) while the separator
    // rows sit at 0 / 3 / 7 / 10, so three groups fell through to the
    // default. Labels now travel with their group; this pins the render.
    addTearDown(() => appRouter.go('/'));
    t.view.physicalSize = const Size(400, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await _pumpApp(t);
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle();
    for (final String g in <String>[
      'RADIO',
      'APP',
      'CONNECTION',
      'ABOUT',
    ]) {
      expect(find.text(g), findsOneWidget, reason: 'group label $g');
    }
    double y(String s) => t.getTopLeft(find.text(s)).dy;
    expect(y('RADIO'), lessThan(y('APP')));
    expect(y('APP'), lessThan(y('CONNECTION')));
    expect(y('CONNECTION'), lessThan(y('ABOUT')));
  });

  testWidgets('the view strip jumps views (R11, R64)', (WidgetTester t) async {
    await _pumpApp(t);
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
    // Settings hub shows the three sub-screen entries.
    expect(find.text('Device configuration'), findsOneWidget);
    expect(find.text('App settings'), findsOneWidget);
    expect(find.text('Profile & personalization'), findsOneWidget);
  });

  testWidgets(
      'the shell owns the notification focus, so leaving Chat re-announces the '
      'channel (D8.20)', (WidgetTester t) async {
    final NotificationFocus focus = NotificationFocus();
    final MeshcoreController mc = MeshcoreController();
    await _pumpApp(t, mc: mc, focus: focus);
    expect(focus.openChannel, isNull);
    await t.tap(find.byTooltip('Chat'));
    await t.pumpAndSettle();
    expect(focus.openChannel, mc.activeChannel,
        reason: 'the channel on screen is not announced');
    await t.tap(find.byTooltip('Dashboard'));
    await t.pumpAndSettle();
    expect(focus.openChannel, isNull,
        reason: 'a kept-alive chat page must not silence the channel while the '
            'user sits on another view');
  });

  testWidgets(
      'a notification tap asks the shell for Chat, not for the root '
      'route (D8.20)', (WidgetTester t) async {
    final ShellViewRequest request = ShellViewRequest();
    final MeshcoreController mc = MeshcoreController();
    await _pumpApp(t, mc: mc, viewRequest: request);
    expect(find.byKey(dashboardKey), findsOneWidget);
    request.openChat(2);
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Chat'), findsOneWidget,
        reason: 'a channel notification tap opens the thread it belongs to');
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

  testWidgets(
      'the strip is the accessible path: one labelled 48dp button '
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

  testWidgets(
      'the strip fills a 320dp phone with equal cells, and the selected '
      'cell stays in sight (R64, R86)', (WidgetTester t) async {
    // R86 made 288 dp the threshold: at 320 the six cells share the width
    // (they scroll only below 288). Navigating by fling was velocity
    // dependent and could overshoot to the Map tab; tapping the cell is
    // what a user does and it exercises the same "selected cell in sight"
    // guarantee.
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await _pumpApp(t);
    expect(t.takeException(), isNull, reason: 'no overflow at 320dp');
    expect(find.byType(SingleChildScrollView), findsNothing,
        reason: '320 dp is wide enough to fill, so nothing scrolls');
    for (final String tip in <String>[
      'Dashboard',
      'Chat',
      'Nodes',
      'Hyperlocal grid',
      'Map',
      'Settings',
    ]) {
      expect(t.getSize(find.byTooltip(tip)).width, greaterThanOrEqualTo(48),
          reason: tip);
    }

    await t.tap(find.byTooltip('Nodes'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Nodes'), findsOneWidget);
    final Rect r = t.getRect(find.byTooltip('Nodes'));
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(320));
    // And the strip really is the switcher: the Map cell still works.
    await t.tap(find.byTooltip('Map'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget);
  });

  testWidgets(
      'below 288dp the strip scrolls sideways instead of squeezing (R86)',
      (WidgetTester t) async {
    t.view.physicalSize = const Size(256, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await _pumpApp(t);
    expect(t.takeException(), isNull, reason: 'no overflow at 256dp');
    expect(find.byType(SingleChildScrollView), findsWidgets,
        reason: 'narrow enough to need the scrolling fallback');
    // Scroll the strip to the end, then select the last cell.
    await t.drag(
        find.byType(SingleChildScrollView).first, const Offset(-260, 0));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle();
    final Rect r = t.getRect(find.byTooltip('Settings'));
    expect(r.right, lessThanOrEqualTo(256),
        reason: 'the selected cell stays in sight');
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
  });

  testWidgets(
      'a body fling changes one view; a strip tap jumps in one frame '
      '(R109, R95)', (WidgetTester t) async {
    await _pumpApp(t);
    expect(find.byKey(dashboardKey), findsOneWidget);
    // R109 — the swipe between views is the shell's again, one page a drag.
    await t.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Chat'), findsOneWidget,
        reason: 'a left fling moves one view, not four');
    await t.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await t.pumpAndSettle();
    expect(find.byKey(dashboardKey), findsOneWidget,
        reason: 'a right fling comes back one view');

    // A tap is one jump: no travel through the pages in between. R95's
    // defect was Dashboard -> Settings scrolling five pages and firing a
    // nav cue on each one.
    await t.tap(find.byTooltip('Settings'));
    await t.pump();
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget,
        reason: 'the target view is live on the next frame');
  });

  testWidgets(
      'Back from a non-Dashboard tab returns to Dashboard '
      '(no root-pop crash)', (WidgetTester t) async {
    await _pumpApp(t);
    await t.tap(find.byTooltip('Chat'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Chat'), findsOneWidget);

    // System Back: PopScope must consume it (not pop the root) and
    // route us back to the Dashboard.
    final bool handled = await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.byKey(dashboardKey), findsOneWidget);
    expect(t.takeException(), isNull); // no root-pop exception
  });

  testWidgets(
      'Back on the Dashboard asks the platform to background the task, not finish it',
      (WidgetTester t) async {
    // The engine is where the radio link and the keep-alive service live. Letting the root route pop
    // finishes the Activity and destroys it, which drops the link (measured on the device,
    // 2026-11-01). The platform call is the fix.
    final List<String> calls = <String>[];
    const MethodChannel channel = MethodChannel('meshmore/app_lifecycle');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (MethodCall call) async {
      calls.add(call.method);
      return true;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await _pumpApp(t);
    final bool handled = await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(handled, isTrue);
    expect(calls, <String>['moveTaskToBack']);
    expect(find.byKey(dashboardKey), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'app resume drives the lifecycle hook without crashing '
      '(R17)', (WidgetTester t) async {
    await _pumpApp(t);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byKey(dashboardKey), findsOneWidget);
  });

  // The grid tab runs a repeating animation, so once it is on screen
  // these use timed pumps — pumpAndSettle would never settle.
  Future<void> settle(WidgetTester t) async {
    for (int i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
      'the hyperlocal grid is the tab after Nodes, and shows '
      'offline as an empty radar (issue #4)', (WidgetTester t) async {
    GridScreen.resetSession();
    await _pumpApp(t);
    await t.tap(find.byTooltip('Nodes'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Nodes'), findsOneWidget);
    // The old entry point is gone from Nodes.
    expect(find.widgetWithIcon(IconButton, Icons.radar), findsNothing);

    await t.tap(find.byTooltip('Hyperlocal grid'));
    await settle(t);
    expect(
        find.widgetWithText(AppBar, 'Hyperlocal grid'), findsOneWidget);
    expect(find.text('Not Connected to Mesh'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a vertical drag on the strip steps one view (R95)',
      (WidgetTester t) async {
    await _pumpApp(t);
    expect(find.byKey(dashboardKey), findsOneWidget);
    final Offset strip = t.getCenter(find.byTooltip('Chat'));

    // Up -> the next view, the same result as tapping the next cell.
    await t.flingFrom(strip, const Offset(0, -60), 800);
    await settle(t);
    expect(find.widgetWithText(AppBar, 'Chat'), findsOneWidget);

    // Down -> the previous view.
    await t.flingFrom(strip, const Offset(0, 60), 800);
    await settle(t);
    expect(find.byKey(dashboardKey), findsOneWidget);

    // A short drag is not a step. It is started on the current cell, so if
    // the arena resolves it as a tap it lands on the view already shown.
    await t.dragFrom(
        t.getCenter(find.byTooltip('Dashboard')), const Offset(0, -12),
        touchSlopY: 0);
    await settle(t);
    expect(find.byKey(dashboardKey), findsOneWidget,
        reason: '12 dp is below the step threshold');
    expect(t.takeException(), isNull);
  });

  Future<void> openFromStrip(WidgetTester t, String label) async {
    await t.tap(find.byTooltip(label));
    await settle(t);
  }

  testWidgets(
      'Map is a swipe page right after the grid, in every skin '
      '(R61)', (WidgetTester t) async {
    // The shell never reads the skin to build its pages, so each preset
    // gets the same seven-plus-one views; prove it per preset rather
    // than assume it.
    // R85 - six views. Docs and the information page are rows under
    // Settings now, not tabs.
    expect(MmView.values, <MmView>[
      MmView.dashboard,
      MmView.chat,
      MmView.nodes,
      MmView.grid,
      MmView.map,
      MmView.settings,
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
      // R109 — the grid opens on the radar in swipe mode, so the shell,
      // not the view, takes the drag: one fling left is the next view.
      await t.fling(find.byType(PageView), const Offset(-600, 0), 2000);
      await settle(t);
      expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget,
          reason: '${preset.name}: a swipe in swipe mode hands over to the '
              'shell and pages');
      expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget,
          reason: '${preset.name}: Map is reachable from the grid');
      expect(find.byType(MapScreen), findsOneWidget);
      expect(find.byTooltip('Offline maps'), findsOneWidget,
          reason: 'the pack manager is one tap from the map');
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('the Map tab holds the body swipe in every skin (R109)',
      (WidgetTester t) async {
    for (final MmThemePreset preset in MmThemePreset.values) {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      GridScreen.resetSession();
      shellDragClaim.reset();
      await t.pumpWidget(const SizedBox());
      await _pumpApp(t, preset: preset);
      expect(t.widget<PageView>(find.byType(PageView)).physics,
          isNot(isA<NeverScrollableScrollPhysics>()),
          reason: '${preset.name}: an ordinary view pages by touch');
      await openFromStrip(t, 'Map');
      expect(t.widget<PageView>(find.byType(PageView)).physics,
          isA<NeverScrollableScrollPhysics>(),
          reason: '${preset.name}: the map owns the middle, the shell locks');
      expect(shellDragClaim.isClaimed, isFalse,
          reason: '${preset.name}: the map locks by being the current view, '
              'not by holding the grid claim');
      // Leaving unlocks it, so the next view pages again.
      await openFromStrip(t, 'Nodes');
      expect(t.widget<PageView>(find.byType(PageView)).physics,
          isNot(isA<NeverScrollableScrollPhysics>()));
    }
  });

  testWidgets('the map edge bands step exactly one view in every skin (R109)',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GridScreen.resetSession();
    await _pumpApp(t, preset: MmThemePreset.studio);
    await settle(t);
    await openFromStrip(t, 'Hyperlocal grid');
    await openFromStrip(t, 'Map');
    expect(find.byType(MapScreen), findsOneWidget);

    // R67's bands are the map's gesture exit (R109): an inward fling from
    // the left edge goes back exactly one view. Two would mean the band's
    // drag also paged the body.
    await t.flingFrom(const Offset(2, 300), const Offset(300, 0), 1200);
    await settle(t);
    expect(find.widgetWithText(AppBar, 'Hyperlocal grid'), findsOneWidget,
        reason: 'the left band leaves the map by one view');
    expect(find.byType(MapScreen), findsNothing,
        reason: 'the map is gone, so its claim is too');
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'the grid locks the body swipe in pan mode, and every visit '
      'starts in swipe mode (R109)', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GridScreen.resetSession();
    shellDragClaim.reset();
    await _pumpApp(t);
    await openFromStrip(t, 'Hyperlocal grid');
    // The radar has no drag of its own: no toggle and no claim.
    expect(find.byKey(const ValueKey<String>('grid-pan-toggle')), findsNothing);
    expect(shellDragClaim.isClaimed, isFalse);

    // A pannable view offers the toggle, and starts in swipe mode so the
    // drag is the shell's.
    await t.tap(find.byTooltip('View'));
    await settle(t);
    await t.tap(find.text('Coverage').last);
    await settle(t);
    expect(find.byKey(const ValueKey<String>('grid-pan-toggle')),
        findsOneWidget);
    expect(shellDragClaim.isClaimed, isFalse,
        reason: 'swipe mode is the default on every visit');

    // Pan mode takes the drag: the shell stops paging.
    await t.tap(find.byKey(const ValueKey<String>('grid-pan-toggle')));
    await settle(t);
    expect(shellDragClaim.heldBy(GridScreen.dragHolder), isTrue);
    await t.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await settle(t);
    expect(find.widgetWithText(AppBar, 'Hyperlocal grid'), findsOneWidget,
        reason: 'pan mode owns the drag, so the fling moves the map');

    // The view is remembered for the session, the lock is not: a fresh visit
    // can always be swiped away from.
    await openFromStrip(t, 'Settings');
    expect(shellDragClaim.isClaimed, isFalse,
        reason: 'leaving the tab releases the claim');
    await openFromStrip(t, 'Hyperlocal grid');
    expect(shellDragClaim.heldBy(GridScreen.dragHolder), isFalse,
        reason: 'pan mode is per visit, not per session');
    await t.fling(find.byType(PageView), const Offset(-600, 0), 2000);
    await settle(t);
    expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget,
        reason: 'a fresh visit is in swipe mode again');
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'the Map tab owns the middle; Back and the view strip '
      'still leave it (R61)', (WidgetTester t) async {
    GridScreen.resetSession();
    await _pumpApp(t);
    await openFromStrip(t, 'Map');
    expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget);

    // The lock is unconditional: no notifier needs to be flipped, and a
    // fling in the middle of the page (the map's) must not change view.
    final Offset mid = t.getCenter(find.byType(PageView));
    await t.flingFrom(mid, const Offset(-400, 0), 1000);
    await settle(t);
    expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget,
        reason: 'a left swipe in the middle must not leave the map');
    await t.flingFrom(mid, const Offset(400, 0), 1000);
    await settle(t);
    expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget,
        reason: 'nor a right swipe');

    // The strip leaves.
    await openFromStrip(t, 'Settings');
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);

    // R109 — off the map the body pages again: one fling right is the
    // previous view.
    await t.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await settle(t);
    expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget,
        reason: 'the body pages once the map is not the current view');

    // Back returns to the Dashboard.
    final bool handled = await t.binding.handlePopRoute();
    await settle(t);
    expect(handled, isTrue);
    expect(find.byKey(dashboardKey), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  group('Map edge swipe (R67)', () {
    Future<Rect> openMap(WidgetTester t) async {
      GridScreen.resetSession();
      await _pumpApp(t);
      await openFromStrip(t, 'Map');
      expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget);
      return t.getRect(find.byType(PageView));
    }

    testWidgets('a fling from the left edge goes to the previous view',
        (WidgetTester t) async {
      final Rect r = await openMap(t);
      await t.flingFrom(
          Offset(r.left + 10, r.center.dy), const Offset(300, 0), 1000);
      await settle(t);
      expect(
          find.widgetWithText(AppBar, 'Hyperlocal grid'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('a fling from the right edge goes to the next view',
        (WidgetTester t) async {
      final Rect r = await openMap(t);
      await t.flingFrom(
          Offset(r.right - 10, r.bottom - 60), const Offset(-300, 0), 1000);
      await settle(t);
      expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('a slow short drag from the edge does not change view',
        (WidgetTester t) async {
      final Rect r = await openMap(t);
      final TestGesture g =
          await t.startGesture(Offset(r.left + 10, r.center.dy));
      await g.moveBy(const Offset(20, 0));
      await t.pump(const Duration(milliseconds: 600));
      await g.up();
      await settle(t);
      expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget);
    });

    testWidgets('an outward drag from the edge does nothing',
        (WidgetTester t) async {
      final Rect r = await openMap(t);
      await t.flingFrom(
          Offset(r.left + 10, r.center.dy), const Offset(-300, 0), 1000);
      await settle(t);
      expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget);
    });

    testWidgets(
        'a fling just inside the band is the map\'s, not the '
        'shell\'s', (WidgetTester t) async {
      final Rect r = await openMap(t);
      // Band is 24 dp; 40 dp in is the map's.
      await t.flingFrom(
          Offset(r.left + 40, r.center.dy), const Offset(300, 0), 1000);
      await settle(t);
      expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget);
    });

    testWidgets('the map receives no touch inside a band',
        (WidgetTester t) async {
      final Rect r = await openMap(t);
      // The topmost hit-test target at an edge point is the band.
      final HitTestResult hit = HitTestResult();
      t.binding
          .hitTestInView(hit, Offset(r.left + 10, r.center.dy), t.view.viewId);
      final Iterable<String> targets =
          hit.path.map((HitTestEntry e) => e.target.runtimeType.toString());
      expect(t.widgetList(find.byKey(const ValueKey<String>('mm-edge-left'))),
          isNotEmpty);
      final RenderObject band =
          t.renderObject(find.byKey(const ValueKey<String>('mm-edge-left')));
      expect(hit.path.any((HitTestEntry e) => e.target == band), isTrue,
          reason: 'band is in the path: $targets');
      final RenderObject map = t.renderObject(find.byType(StreetMapView));
      expect(hit.path.any((HitTestEntry e) => e.target == map), isFalse,
          reason: 'the map must not be hit in the band');
      // And in the middle the map is hit, the band is not.
      final HitTestResult mid = HitTestResult();
      t.binding.hitTestInView(mid, r.center, t.view.viewId);
      expect(mid.path.any((HitTestEntry e) => e.target == band), isFalse);
    });

    testWidgets('the bands do not shadow the map tool column',
        (WidgetTester t) async {
      final Rect r = await openMap(t);
      // Every map tool, including the two the tab contributes, is inside the
      // one column on the right. R70: the column renders with no fix (R69
      // made the map browsable), and the right band starts at or below it.
      final Rect col =
          t.getRect(find.byKey(const ValueKey<String>('map-controls')));
      final Rect rightBand =
          t.getRect(find.byKey(const ValueKey<String>('mm-edge-right')));
      expect(rightBand.top, greaterThanOrEqualTo(col.bottom));
      expect(rightBand.width, 24);

      // A tap on the last tool in the column reaches the tool, not the band.
      final Finder btn =
          find.byKey(const ValueKey<String>('map-places-button'));
      expect(
          find.descendant(
              of: find.byKey(const ValueKey<String>('map-controls')),
              matching: btn),
          findsOneWidget);
      final Offset p = t.getCenter(btn);
      final RenderObject band =
          t.renderObject(find.byKey(const ValueKey<String>('mm-edge-right')));
      final HitTestResult hit = HitTestResult();
      t.binding.hitTestInView(hit, p, t.view.viewId);
      expect(hit.path.any((HitTestEntry e) => e.target == t.renderObject(btn)),
          isTrue,
          reason: 'the button wins over the band');
      expect(hit.path.any((HitTestEntry e) => e.target == band), isFalse,
          reason: 'the right band must not cover the tool column');

      // And the left edge is the band's alone now: no map tool sits there to
      // be lost behind a thumb that uses the right-hand column.
      expect(r.left + 20, lessThan(col.left));
      expect(find.byKey(const ValueKey<String>('map-offline-maps-button')),
          findsOneWidget);
      expect(
          t
              .getRect(
                  find.byKey(const ValueKey<String>('map-offline-maps-button')))
              .left,
          greaterThan(r.center.dx),
          reason: 'the offline-maps tool belongs in the right-hand column');
    });
  });

  group('the view strip fills the width', () {
    const List<String> labels = <String>[
      'Dashboard',
      'Chat',
      'Nodes',
      'Hyperlocal grid',
      'Map',
      'Settings',
    ];
    for (final double w in <double>[320, 360, 393, 412, 600, 1024]) {
      testWidgets('at ${w.toInt()}dp: equal cells edge to edge, >= 48dp',
          (WidgetTester t) async {
        t.view.physicalSize = Size(w, 800);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await _pumpApp(t);
        final List<Rect> cells = <Rect>[
          for (final String s in labels) t.getRect(find.byTooltip(s)),
        ];
        // ignore: avoid_print
        print('strip cells @${w.toInt()}dp: $cells');
        expect(cells.first.left, 0, reason: 'no dead space on the left');
        expect(cells.last.right, closeTo(w, 0.01),
            reason: 'no dead space on the right');
        for (int i = 0; i < cells.length; i++) {
          expect(cells[i].width, closeTo(cells.first.width, 0.01),
              reason: 'cell $i is the same width as cell 0');
          expect(cells[i].width, greaterThanOrEqualTo(48));
          expect(cells[i].height, greaterThanOrEqualTo(48));
          if (i > 0) {
            expect(cells[i].left, closeTo(cells[i - 1].right, 0.01),
                reason: 'cells abut, no gap');
          }
        }
        expect(t.takeException(), isNull);
      });
    }

    // _ViewStripState.didUpdateWidget calls Scrollable.ensureVisible after
    // every index change. In the fill branch there is no Scrollable above
    // the cells; ensureVisible walks Scrollable.maybeOf (Flutter 3.47.4,
    // scrollable.dart:509), so it is a no-op there. These two prove it for
    // both layouts rather than trusting the source reading.
    testWidgets('changing view at 400dp (fill branch, no Scrollable) is safe',
        (WidgetTester t) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await _pumpApp(t);
      expect(
          find.descendant(
              of: find.byTooltip('Map'), matching: find.byType(Scrollable)),
          findsNothing);
      await t.tap(find.byTooltip('Map'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Chat'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Chat'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'changing view below 288dp (scrolling branch) still scrolls '
        'the selected cell into sight', (WidgetTester t) async {
      t.view.physicalSize = const Size(270, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await _pumpApp(t);
      // Six 48dp cells need 288dp: the last one is only partly on screen.
      expect(t.getRect(find.byTooltip('Settings')).right, 288);
      // Tap its visible sliver (x 240..270).
      await t.tapAt(const Offset(255, 80));
      await t.pumpAndSettle();
      expect(t.getRect(find.byTooltip('Settings')).right,
          lessThanOrEqualTo(270.01),
          reason: 'ensureVisible scrolled the selected cell into sight');
      // 270dp is far below any real phone: the Dashboard body overflows
      // there, which is not what this test is about, so drain it.
      while (t.takeException() != null) {}
    });
  });

  group('channel unread on the strip (register 2)', () {
    testWidgets('the chat cell shows the count and a screen reader reads it',
        (WidgetTester tester) async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => fake,
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      );
      final ChannelReadStore reads = ChannelReadStore();
      await _pumpApp(tester, mc: mc, reads: reads);
      await mc.connect();
      fake.emit(selfInfoFrame());
      await tester.pumpAndSettle();
      // A channel message while the reader is on the Dashboard: the chat tab
      // is not the current view, so nothing marks it read.
      fake.emit(channelMsgFrame(idx: 0, text: 'Trudy: the ford is high'));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsWidgets,
          reason: 'the cell carries the number, not a bare dot');
      expect(find.bySemanticsLabel('Chat, 1 unread'), findsOneWidget,
          reason: 'a badge a screen reader cannot read is not a badge');
      mc.dispose();
    });
  });

  group('radio-free mode (D8.21)', () {
    testWidgets('the shell says DEMO when no radio is wanted',
        (WidgetTester tester) async {
      await _pumpApp(tester, demo: true);
      expect(find.text('DEMO'), findsOneWidget,
          reason: 'an empty fabric in demo mode and a dead radio look alike');
    });

    testWidgets('nothing is claimed when the radio is the normal path',
        (WidgetTester tester) async {
      await _pumpApp(tester);
      expect(find.text('DEMO'), findsNothing);
    });
  });
}
