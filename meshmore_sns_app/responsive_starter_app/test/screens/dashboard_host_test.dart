// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/dashboard_screen.dart';
import 'package:meshmore_sns_app/screens/dashboards/dashboard_host.dart';
import 'package:meshmore_sns_app/screens/dashboards/nerv_dashboard.dart';
import 'package:meshmore_sns_app/screens/dashboards/studio_dashboard.dart';
import 'package:meshmore_sns_app/screens/dashboards/my_pubkey_line.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

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

  testWidgets('host shows the default skin, then the one selected',
      (WidgetTester t) async {
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final ThemeController tc = await _pump(t, mc);

    // The key answers "is the dashboard showing", so it belongs to the host
    // and holds under every preset. Which layout is showing is a separate
    // question, answered by the layout's own type.
    expect(find.byKey(dashboardKey), findsOneWidget);
    expect(find.byType(StudioDashboard), findsOneWidget,
        reason: 'kDefaultPreset is STUDIO');
    expect(find.byType(NervDashboard), findsNothing);

    // Switch to NERV → the telemetry-grid re-imagining.
    await tc.setPreset(MmThemePreset.nerv);
    await t.pumpAndSettle();
    expect(find.byKey(dashboardKey), findsOneWidget);
    expect(find.byType(NervDashboard), findsOneWidget);
    expect(find.byType(StudioDashboard), findsNothing);
    // The icon-only Bluetooth button is named for screen readers.
    expect(find.byTooltip('Device'), findsOneWidget);

    // Back to SEELE → the monolith again.
    await tc.setPreset(MmThemePreset.seele);
    await t.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsOneWidget);
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
    expect(find.text('NERV'), findsNothing);
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
    expect(find.text('AG-HUD'), findsOneWidget);
    expect(find.text('SIGNAL'), findsOneWidget);
    expect(find.text('NERV'), findsNothing);
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
    expect(find.text('DR POP'), findsOneWidget);
    expect(find.textContaining('PHASE_'), findsOneWidget);
    expect(find.text('AG-HUD'), findsNothing);
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

    // Recon signature: the mono codec readout, not a second name for the
    // screen the strip already names.
    expect(find.text('RECON'), findsNothing);
    expect(find.textContaining('CONTACTS'), findsOneWidget);
    expect(find.text('MESHMORE™'), findsNothing);
  });

  // R64 — the new UX must have location. (R68: Studio now has its own
  // StudioDashboard, which carries a LOCATION section; before R68 it fell
  // through to the SEELE monolith.) This proves it by rendering, and
  // records which presets lack the tile.
  testWidgets('Studio (and SEELE) show the LOCATION tile; the others are '
      'recorded', (WidgetTester t) async {
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
    await tc.setReduceMotion(true);
    await mc.connect();
    fake.emit(selfInfoFrameAt(lat: 38.920045, lon: -104.772826));
    await t.pump();

    final Map<MmThemePreset, bool> hasTile = <MmThemePreset, bool>{};
    for (final MmThemePreset p in MmThemePreset.values) {
      await tc.setPreset(p);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      hasTile[p] = find.text('LOCATION').evaluate().isNotEmpty;
    }
    // Observed when written: only seele and studio render the tile;
    // nerv, agHud, hyperlocal, drPop and recon do not (finding 12, left
    // as-is for the old skins by the owner).
    expect(hasTile[MmThemePreset.studio], isTrue,
        reason: 'the new skin must show location');
    expect(hasTile[MmThemePreset.seele], isTrue);
    expect(find.textContaining('38.92'), findsWidgets,
        reason: 'under Studio the tile carries the fix, not a placeholder');
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    // Drain one-shot timers the dashboards and controller leave behind.
    await t.pump(const Duration(seconds: 30));
  });
}
