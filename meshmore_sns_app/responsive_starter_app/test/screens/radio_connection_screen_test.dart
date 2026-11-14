// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/radio_connection_screen.dart';
import 'package:meshmore_sns_app/tools/tools_controller.dart';

import '../meshcore/fake_transport.dart';

/// The reader-facing half of what used to be one page.
///
/// `diagnostics_screen.dart` led with these facts and then went on for six
/// hundred lines about raw frames, fixture exports and the M6 interop closure. A
/// reader who tapped "Radio connection" in Settings landed on the console. These
/// cases hold the split: the facts and the four actions are here, and no
/// developer control is.
void main() {
  Future<(MeshcoreController, FakeMeshcoreTransport, GoRouter)> pump(
      WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final GoRouter router = GoRouter(
      initialLocation: '/settings/connection',
      routes: <RouteBase>[
        GoRoute(
            path: '/settings/connection',
            builder: (_, __) => const RadioConnectionScreen()),
        GoRoute(
            path: '/settings/diagnostics',
            builder: (_, __) => const Scaffold(body: Text('console'))),
        GoRoute(path: '/connect', builder: (_, __) => const Scaffold(body: Text('connect'))),
      ],
    );
    await t.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<MeshcoreController>.value(value: ctrl),
          ChangeNotifierProvider<ToolsController>(
              create: (_) => ToolsController(ctrl)),
        ],
        child: MaterialApp.router(
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
        ),
      ),
    );
    return (ctrl, fake, router);
  }

  testWidgets('states the link and offers the one action that changes it',
      (WidgetTester t) async {
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake, GoRouter _) =
        await pump(t);

    expect(find.textContaining('State: disconnected'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('diag-connect')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey<String>('diag-connect')));
    await t.pumpAndSettle();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    expect(find.textContaining('State: ready'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    ctrl.dispose();
    fake.close();
  });

  testWidgets('carries no developer control', (WidgetTester t) async {
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake, GoRouter _) =
        await pump(t);
    await t.tap(find.byKey(const ValueKey<String>('diag-connect')));
    await t.pumpAndSettle();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    // The console's own surfaces: the raw-record sender, the M6 fixture export,
    // the soak counters and the frame log. None of them belongs on a screen a
    // reader reaches from Settings.
    expect(find.text('Send a raw record'), findsNothing);
    expect(find.textContaining('M6 interop'), findsNothing);
    expect(find.text('DEVELOPER'), findsNothing);
    ctrl.dispose();
    fake.close();
  });

  testWidgets('the row at the bottom opens the console', (WidgetTester t) async {
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake, GoRouter _) =
        await pump(t);
    // The title is longer now ("MeshCore radio connection"), so at 200 % text
    // the row is below the fold and a lazy list has not built it. A reader
    // scrolls, and so does the test.
    await t.scrollUntilVisible(
      find.byKey(const ValueKey<String>('connection-diagnostics-row')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('connection-diagnostics-row')));
    await t.pumpAndSettle();
    expect(find.text('console'), findsOneWidget);
    ctrl.dispose();
    fake.close();
  });

  testWidgets('a paired radio can be forgotten, and the confirmation is a question',
      (WidgetTester t) async {
    // The action row moved with the facts, so the destructive one has to work
    // here: it drops the paired record, the OS bond and the history entry.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mm.paired.id': 'AA:BB:CC',
      'mm.paired.name': 'T1000-E',
    });
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<MeshcoreController>.value(value: ctrl),
          ChangeNotifierProvider<ToolsController>(
              create: (_) => ToolsController(ctrl)),
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
          home: const RadioConnectionScreen(),
        ),
      ),
    );
    await ctrl.autoConnectIfPaired();
    await t.pumpAndSettle();
    expect(ctrl.hasPairedDevice, isTrue);

    await t.tap(find.byKey(const ValueKey<String>('diag-forget')));
    await t.pumpAndSettle();
    expect(find.text('Forget this radio?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(ctrl.hasPairedDevice, isTrue);
    ctrl.dispose();
    fake.close();
  });

  testWidgets('fits a 320 dp phone at 200 % text', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake, GoRouter _) =
        await pump(t);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    // The facts are still readable at the floor rather than clipped to nothing.
    expect(find.textContaining('State:'), findsOneWidget);
    // The title is longer now ("MeshCore radio connection"), so at 200 % text
    // the row is below the fold and a lazy list has not built it. A reader
    // scrolls, and so does the test.
    await t.scrollUntilVisible(
      find.byKey(const ValueKey<String>('connection-diagnostics-row')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    ctrl.dispose();
    fake.close();
  });
}
