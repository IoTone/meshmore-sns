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
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// The dashboard at the accessibility floor, in every radio state.
///
/// This screen was the one the owner saw striped: at 200 % text a 320 dp tile
/// put an icon, a sentence and a text button on one Row, and the button's
/// intrinsic width left the Expanded sentence nothing, so the row overflowed
/// by 55 px. The a11y floor sweep covered the six views and the Settings
/// routes but not this state, which is why it shipped.
void main() {
  Widget host(MeshcoreController mc, double scale) => MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: MultiProvider(
            providers: <ChangeNotifierProvider<ChangeNotifier>>[
              ChangeNotifierProvider<MeshcoreController>.value(value: mc),
              ChangeNotifierProvider<ThemeController>(
                  create: (_) => ThemeController()),
            ],
            child: const Scaffold(body: DashboardScreen()),
          ),
        ),
      );

  for (final double scale in <double>[1.0, 1.3, 1.5, 2.0]) {
    testWidgets('the dashboard holds 320 dp at ${scale}x text, offline and '
        'linked', (WidgetTester t) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport();
      final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => fake,
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      );
      await t.pumpWidget(host(mc, scale));
      await t.pump();
      expect(t.takeException(), isNull,
          reason: 'the offline slab overflowed at ${scale}x');

      // Linked: the slab now carries the radio's name and "SYNCING…" beside
      // two 48 dp buttons, which is the widest that row ever gets.
      await mc.connect();
      fake.emit(selfInfoFrame());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull,
          reason: 'the linked slab overflowed at ${scale}x');

      // Link lost: the retry button replaces connect, so the same row carries
      // the same load with the alert colours.
      await fake.close();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull,
          reason: 'the lost-link slab overflowed at ${scale}x');
      mc.dispose();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });
  }
}
