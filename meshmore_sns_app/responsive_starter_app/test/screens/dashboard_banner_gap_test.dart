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
import 'package:meshmore_sns_app/screens/dashboards/dashboard_degraded_banner.dart';
import 'package:meshmore_sns_app/screens/dashboards/dashboard_host.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// A banner with nothing to say must not take up space.
///
/// `DashboardDegradedBanner` returns `SizedBox.shrink()` when nothing is
/// degraded, but the host reserved `padScreen.top` for it anyway: 41 px of empty
/// space above the dashboard's first row on a healthy screen, while the row
/// below kept only its own small margin. That asymmetry is what the owner
/// reported as "more space above the Retry button than below it" — the band's
/// own padding was already equal.
void main() {
  testWidgets('an idle banner leaves no gap above the first row',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await t.binding.setSurfaceSize(const Size(411, 950));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final ThemeController theme = ThemeController()
      ..setPreset(MmThemePreset.studio);
    await t.pumpWidget(MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
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
    ));
    await t.pump();
    await mc.connect();
    await t.pumpAndSettle();

    // Nothing is degraded on a healthy, connected screen, so the banner draws
    // nothing and must contribute no height at all.
    final Rect banner = t.getRect(find.byType(DashboardDegradedBanner));
    expect(banner.height, 0.0,
        reason: 'an idle banner took ${banner.height} dp above the first row');

    await mc.disconnect();
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 40));
  });
}
