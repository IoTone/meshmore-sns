// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_connection.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/dashboards/dashboard_host.dart';
import 'package:meshmore_sns_app/screens/dashboards/my_pubkey_line.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

Future<ThemeController> _pump(WidgetTester t, MeshcoreController mc) async {
  final ThemeController tc = ThemeController();
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: tc),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
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
        home: const Scaffold(body: DashboardHost()),
      ),
    ),
  );
  return tc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // Every skin gets a bespoke dashboard, and the pubkey is INFORMATION
  // rather than decoration -- it is the identifier another operator
  // needs before their DMs can route to you. Adding it to one skin and
  // calling the feature done is exactly the mistake this guards: it
  // shipped visible only under SEELE, while the user was on DR Pop.
  testWidgets('every skin surfaces my own pubkey', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(1100, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final ThemeController tc = await _pump(t, mc);
    // SelfInfo carries the key, and SEELE only renders its radio block
    // once it lands -- so a disconnected fixture would prove nothing.
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pump();

    for (final MmThemePreset p in MmThemePreset.values) {
      await tc.setPreset(p);
      // Not pumpAndSettle: several skins animate continuously (the
      // Hyperlocal radar sweep), so settling never happens.
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byType(MyPubkeyLine), findsWidgets,
          reason: 'preset $p shows no pubkey line');
    }
    // Dispose in-body, not in teardown: connect() starts the battery
    // poll timer, and a pending periodic timer fails the test before
    // teardown gets a chance to cancel it.
    mc.dispose();
    await t.pump();
  });

  testWidgets('host shows the SEELE monolith by default, NERV when selected',
      (WidgetTester t) async {
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final ThemeController tc = await _pump(t, mc);

    // Default preset (SEELE) → the monolith dashboard (no NERV brand bar).
    expect(find.text('PEERS IN RANGE'), findsOneWidget);
    expect(find.text('MESHMORE // NERV'), findsNothing);

    // Switch to NERV → the telemetry-grid re-imagining (brand bar +
    // chamfered panels appear).
    await tc.setPreset(MmThemePreset.nerv);
    await t.pumpAndSettle();
    expect(find.text('MESHMORE // NERV'), findsOneWidget);

    // Back to SEELE → brand bar gone again.
    await tc.setPreset(MmThemePreset.seele);
    await t.pumpAndSettle();
    expect(find.text('MESHMORE // NERV'), findsNothing);
    expect(find.text('PEERS IN RANGE'), findsOneWidget);
  });

  testWidgets('host shows the Hyperlocal radar when selected',
      (WidgetTester t) async {
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final ThemeController tc = await _pump(t, mc);
    // Reduce-motion stops the radar sweep so the tree can settle (the
    // sweep is an infinite animation otherwise).
    await tc.setReduceMotion(true);
    await tc.setPreset(MmThemePreset.hyperlocal);
    await t.pumpAndSettle();

    // Radar dashboard: the empty-field prompt + the PEERS status rail,
    // and none of the other skins' signatures.
    expect(find.text('Listening for nodes…'), findsOneWidget);
    expect(find.textContaining('PEERS', findRichText: true),
        findsOneWidget); // status rail
    expect(find.text('MESHMORE // NERV'), findsNothing);
    expect(find.text('PEERS IN RANGE'), findsNothing);
  });

  testWidgets('host shows the AG-HUD gauges when selected',
      (WidgetTester t) async {
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final ThemeController tc = await _pump(t, mc);
    // Reduce-motion stops the gauge sweep so the tree can settle.
    await tc.setReduceMotion(true);
    await tc.setPreset(MmThemePreset.agHud);
    await t.pumpAndSettle();

    // AG-HUD signature: the brand bar + the SIGNAL gauge label.
    expect(find.text('MESHMORE // AG'), findsOneWidget);
    expect(find.text('SIGNAL'), findsOneWidget);
    expect(find.text('MESHMORE // NERV'), findsNothing);
  });

  testWidgets('host shows the DR Pop colour blocks when selected',
      (WidgetTester t) async {
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final ThemeController tc = await _pump(t, mc);
    await tc.setPreset(MmThemePreset.drPop);
    await t.pumpAndSettle();

    // DR Pop signature: the MESHMORE brand bar + a PHASE code.
    expect(find.text('MESHMORE'), findsOneWidget);
    expect(find.textContaining('PHASE_'), findsOneWidget);
    expect(find.text('MESHMORE // AG'), findsNothing);
  });

  testWidgets('host shows the Recon codec readout when selected',
      (WidgetTester t) async {
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final ThemeController tc = await _pump(t, mc);
    // Reduce-motion stops the compass sweep so the tree can settle.
    await tc.setReduceMotion(true);
    await tc.setPreset(MmThemePreset.recon);
    await t.pumpAndSettle();

    // Recon signature: the codec header + the contacts band.
    expect(find.text('MESHMORE · RECON'), findsOneWidget);
    expect(find.textContaining('CONTACTS'), findsOneWidget);
    expect(find.text('MESHMORE™'), findsNothing);
  });
}
