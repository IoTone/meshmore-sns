// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/dashboard_screen.dart';
import 'package:meshmore_sns_app/screens/dashboards/dashboard_host.dart';
import 'package:meshmore_sns_app/screens/dashboards/forest_dashboard.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// The LDMUX looks get layouts of their own, and each one is recognisable by a
/// single element rather than by a recolour.
///
/// Forest is the first: it answers "how deep" where every other skin answers
/// "how many", so the depth bar is the thing these tests hold. A layout that
/// renders but shows the same four numbers as the monolith would pass a
/// "does it build" test and fail the owner's actual complaint.
Future<ThemeController> _pump(
  WidgetTester t,
  MeshcoreController mc,
  MmThemePreset preset, {
  double textScale = 1,
}) async {
  final ThemeController tc = ThemeController();
  await tc.setPreset(preset);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<ThemeController>.value(value: tc),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
      ],
      child: Builder(
        builder: (BuildContext c) => MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: MaterialApp(
          theme: c.read<ThemeController>().theme,
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
      ),
    ),
  );
  return tc;
}

MeshcoreController _mc(FakeMeshcoreTransport fake) => MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );

Future<void> _drain(WidgetTester t, MeshcoreController mc) async {
  mc.dispose();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('Forest has its own dashboard, not the SEELE monolith',
      (WidgetTester t) async {
    final MeshcoreController mc = _mc(FakeMeshcoreTransport(connected: true));
    await _pump(t, mc, MmThemePreset.forest);
    expect(find.byType(ForestDashboard), findsOneWidget);
    expect(find.byType(DashboardScreen), findsNothing);
    await _drain(t, mc);
  });

  testWidgets('with no learned route the bar says so instead of drawing nothing',
      (WidgetTester t) async {
    final MeshcoreController mc = _mc(FakeMeshcoreTransport(connected: true));
    await _pump(t, mc, MmThemePreset.forest);
    expect(find.byKey(const ValueKey<String>('forest-depth-empty')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('forest-depth-bar')), findsNothing);
    await _drain(t, mc);
  });

  testWidgets('a learned route draws the bar, one segment per depth',
      (WidgetTester t) async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _mc(fake);
    await _pump(t, mc, MmThemePreset.forest);
    await mc.connect();
    fake.emit(selfInfoFrame());
    // Two peers one hop away and one two hops away: the bar must have two
    // segments, and the empty label must be gone.
    fake.emit(contactFrame(name: 'Near A', firstPubByte: 70, outPathLen: 1, path: <int>[0x46]));
    fake.emit(contactFrame(name: 'Near B', firstPubByte: 90, outPathLen: 1, path: <int>[0x47]));
    fake.emit(contactFrame(
        name: 'Far', firstPubByte: 110, outPathLen: 2, path: <int>[0x46, 0x48]));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('forest-depth-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('forest-depth-empty')), findsNothing);
    await _drain(t, mc);
  });

  testWidgets('Forest survives 320 dp at 200 % text', (WidgetTester t) async {
    // The a11y floor test pumps the Dashboard view for the default preset only,
    // so each new layout has to prove its own floor.
    t.view.physicalSize = const Size(320, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final MeshcoreController mc = _mc(FakeMeshcoreTransport(connected: true));
    await _pump(t, mc, MmThemePreset.forest, textScale: 2);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await _drain(t, mc);
  });
}
