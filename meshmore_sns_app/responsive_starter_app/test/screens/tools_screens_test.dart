// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/discovered_node.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/meshcore/secure/sealed_document.dart';
import 'package:meshmore_sns_app/screens/tools/discover_screen.dart';
import 'package:meshmore_sns_app/screens/tools/ping_screen.dart';
import 'package:meshmore_sns_app/screens/tools/radio_stats_screen.dart';
import 'package:meshmore_sns_app/screens/tools/range_test_screen.dart';
import 'package:meshmore_sns_app/screens/tools/soak_screen.dart';
import 'package:meshmore_sns_app/screens/tools/tool_history_screen.dart';
import 'package:meshmore_sns_app/screens/tools/tools_hub_screen.dart';
import 'package:meshmore_sns_app/screens/tools/trace_screen.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tools/mesh_tool.dart';
import 'package:meshmore_sns_app/tools/tool_history.dart';
import 'package:meshmore_sns_app/tools/tools_controller.dart';

import '../meshcore/fake_transport.dart';

Widget _host(MeshcoreController mc, ToolsController tools, Widget home,
    {Locale locale = const Locale('en')}) {
  final GoRouter router = GoRouter(routes: <RouteBase>[
    GoRoute(path: '/', builder: (_, __) => home),
    GoRoute(
        path: '/settings/tools/:tool',
        builder: (_, __) => const Scaffold(body: Text('tool page'))),
    // Check-in is reached from this hub now that the alarm screen carries one
    // control only (`sos_screen.dart`).
    GoRoute(
        path: '/checkin', builder: (_, __) => const Scaffold(body: Text('check-in page'))),
  ]);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MeshcoreController>.value(value: mc),
      ChangeNotifierProvider<ToolsController>.value(value: tools),
      ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('hub lists all six tools and says when offline',
      (WidgetTester t) async {
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    final ToolsController tools = ToolsController(mc);
    await t.pumpWidget(_host(mc, tools, const ToolsHubScreen()));
    await t.pumpAndSettle();
    for (final String name in <String>[
      'MeshCore radio stats',
      'Ping',
      'Trace path',
      'Discover nearby',
      'Soak test',
      'Range test',
    ]) {
      // The hub is a list: a row past the fold is still listed. The offline
      // banner grew a line when it started naming the way to fix the state, so
      // the list may or may not scroll at this size; scroll only when it does.
      final Finder scroller = find.byType(Scrollable);
      if (scroller.evaluate().isNotEmpty) {
        await t.scrollUntilVisible(find.text(name), 120,
            scrollable: scroller.first);
      }
      expect(find.text(name), findsOneWidget);
    }
    // Back to the top, where the offline banner lives. The banner's sentence is
    // longer now that it names the radio, so it wraps and the old negative
    // scroll no longer lands on it.
    final Finder topScroller = find.byType(Scrollable);
    if (topScroller.evaluate().isNotEmpty) {
      await t.drag(topScroller.first, const Offset(0, 2000));
      await t.pumpAndSettle();
    }
    expect(find.textContaining('The tools need the MeshCore radio'),
        findsOneWidget);
    await t.tap(find.text('Ping'));
    await t.pumpAndSettle();
    expect(find.text('tool page'), findsOneWidget);
    expect(t.takeException(), isNull);
    tools.dispose();
    mc.dispose();
  });

  testWidgets('check-in is not duplicated in the tools hub',
      (WidgetTester t) async {
    // It lives on Settings -> Safety, which is where a reader in a hurry looks.
    // Two rows to one destination is the duplication the settings audit removed;
    // the alarm screen still carries exactly one control of its own.
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    final ToolsController tools = ToolsController(mc);
    await t.pumpWidget(_host(mc, tools, const ToolsHubScreen()));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('tools-checkin')), findsNothing);
    tools.dispose();
    mc.dispose();
  });

  for (final (String, Widget) s in <(String, Widget)>[
    ('Radio stats', const RadioStatsScreen()),
    ('Ping', const PingScreen()),
    ('Trace path', const TraceScreen()),
    ('Discover nearby', const DiscoverScreen()),
    ('Soak test', const SoakScreen()),
    ('Range test', const RangeTestScreen()),
  ]) {
    for (final Locale loc in const <Locale>[Locale('en'), Locale('ja')]) {
      testWidgets('${s.$1} renders offline (${loc.languageCode}) with Start '
          'disabled', (WidgetTester t) async {
        // Narrow phone width: catches overflow in the setup rows.
        await t.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final MeshcoreController mc = MeshcoreController(
            transportFactory: () async => FakeMeshcoreTransport());
        final ToolsController tools = ToolsController(mc);
        await t.pumpWidget(_host(mc, tools, s.$2, locale: loc));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final Finder start = find.ancestor(
            of: find.byIcon(Icons.play_arrow),
            matching: find.byWidgetPredicate((Widget w) => w is ButtonStyleButton));
        if (start.evaluate().isNotEmpty) {
          expect(t.widget<ButtonStyleButton>(start.first).onPressed, isNull);
        }
        tools.dispose();
        mc.dispose();
      });
    }
  }

  // A tool page passes its rows to `ToolPage` as a function, not as a list.
  // A list was built by the page's own `build`, so the tool's listener re-laid
  // out the same widget instances and every value captured at page-build time
  // stayed frozen: choosing a contact in the Ping target sheet closed the sheet
  // and left the field reading "Choose…" on the phone, which read as a dead
  // picker and a dead Start button.
  testWidgets('a tool page follows the tool as it changes',
      (WidgetTester t) async {
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    final ToolsController tools = ToolsController(mc);
    await t.pumpWidget(_host(mc, tools, const PingScreen()));
    await t.pumpAndSettle();
    expect(find.text('Choose…'), findsOneWidget);

    tools.ping.setTarget(DiscoveredNode(
      pubKeyHex: 'ab' * 32,
      name: 'HELTEC-BASE',
      type: kAdvTypeRepeater,
      lastHeardUnix: 0,
      viaAdvert: true,
    ));
    await t.pump();

    expect(find.text('HELTEC-BASE'), findsOneWidget);
    expect(find.text('Choose…'), findsNothing,
        reason: 'the target line is the tool state, not the page build');
    tools.dispose();
    mc.dispose();
  });

  testWidgets('soak picker lists Public disabled, with the reason',
      (WidgetTester t) async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pump();
    final ToolsController tools = ToolsController(mc);
    await t.pumpWidget(_host(mc, tools, const SoakScreen()));
    await t.pump();
    await t.tap(find.text('Choose…'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Public is refused'), findsOneWidget);
    final ListTile pub = t.widget<ListTile>(find.ancestor(
        of: find.text('#0 Public'), matching: find.byType(ListTile)));
    expect(pub.enabled, isFalse);
    tools.dispose();
    mc.dispose();
  });

  group('tool history screen', _historyTests);
}

void _historyTests() {
  MeshcoreController fakeMc() => MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport(connected: false),
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      );

  testWidgets('the history says what is kept and what an empty one means',
      (WidgetTester t) async {
    // The tools kept nothing before this screen existed, so an empty history is
    // the common first visit. It has to say that a run is only kept when it
    // ends, rather than reading as a broken list.
    final MeshcoreController mc = fakeMc();
    addTearDown(mc.dispose);
    final ToolsController tools = ToolsController(mc);
    addTearDown(tools.dispose);
    await t.pumpWidget(_host(mc, tools, const ToolHistoryScreen()));
    await t.pump();
    final AppLocalizations l = AppLocalizations.of(
        t.element(find.byType(ToolHistoryScreen)));
    expect(find.text(l.toolHistoryEmpty), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a kept run shows its summary and can be copied',
      (WidgetTester t) async {
    // The history seals through the platform store, which a widget test has
    // no key for: the memory cipher and a temp directory are the same seam the
    // store's own suite uses.
    final Directory dir = Directory.systemTemp.createTempSync('mm_tool_runs_ui');
    SealedDocument.cipherOverride = MemoryRecordCipher.random();
    SealedDocument.directoryOverride = dir;
    addTearDown(() {
      SealedDocument.cipherOverride = null;
      SealedDocument.directoryOverride = null;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final MeshcoreController mc = fakeMc();
    addTearDown(mc.dispose);
    final ToolsController tools = ToolsController(mc);
    addTearDown(tools.dispose);
    // `runAsync` because the store seals through real file IO, which the
    // fake clock the rest of this test runs on would never let finish.
    await t.runAsync(() => tools.history.record(ToolRun(
          kind: ToolKind.range,
          startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
          endedAt: DateTime.now().subtract(const Duration(minutes: 2)),
          summary: '4 beacons heard, best 6.5 dB',
          csv: 'seq,snr_db\n1,6.5\n',
        )));
    await t.pumpWidget(_host(mc, tools, const ToolHistoryScreen()));
    await t.pump();
    final AppLocalizations l = AppLocalizations.of(
        t.element(find.byType(ToolHistoryScreen)));
    expect(find.text('4 beacons heard, best 6.5 dB'), findsOneWidget);
    // The count bound is stated, because a reader has to know how much of their
    // own history is being kept.
    expect(find.textContaining('${tools.history.maxRuns}'), findsWidgets);
    expect(find.text(l.toolsCopyReport), findsNothing,
        reason: 'the copy action is an icon with a tooltip, not a button');
    await t.pumpWidget(const SizedBox());
  });
}
