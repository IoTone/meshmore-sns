// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/tools/discover_screen.dart';
import 'package:meshmore_sns_app/screens/tools/ping_screen.dart';
import 'package:meshmore_sns_app/screens/tools/radio_stats_screen.dart';
import 'package:meshmore_sns_app/screens/tools/range_test_screen.dart';
import 'package:meshmore_sns_app/screens/tools/soak_screen.dart';
import 'package:meshmore_sns_app/screens/tools/tools_hub_screen.dart';
import 'package:meshmore_sns_app/screens/tools/trace_screen.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tools/tools_controller.dart';

import '../meshcore/fake_transport.dart';

Widget _host(MeshcoreController mc, ToolsController tools, Widget home,
    {Locale locale = const Locale('en')}) {
  final GoRouter router = GoRouter(routes: <RouteBase>[
    GoRoute(path: '/', builder: (_, __) => home),
    GoRoute(
        path: '/settings/tools/:tool',
        builder: (_, __) => const Scaffold(body: Text('tool page'))),
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
      'Radio stats',
      'Ping',
      'Trace path',
      'Discover nearby',
      'Soak test',
      'Range test',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.textContaining('the tools need the radio'), findsOneWidget);
    await t.tap(find.text('Ping'));
    await t.pumpAndSettle();
    expect(find.text('tool page'), findsOneWidget);
    expect(t.takeException(), isNull);
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
}
