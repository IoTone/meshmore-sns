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
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// The status band's content sits centred in its height.
///
/// It has no vertical padding of its own: a `minHeight: 56` and a centring Row
/// do the work, so a 48 dp control lands 4 dp from each edge. Verified here
/// because the owner reported the space above the Retry button as larger than
/// the space below it — and measuring from the app bar's hairline rather than
/// from the band's own top edge produced exactly that false reading. The real
/// cause was the degraded banner reserving its inset while saying nothing; that
/// is `dashboard_banner_gap_test.dart`.
void main() {
  testWidgets('equal space above and below the band content',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await t.binding.setSurfaceSize(const Size(411, 950));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
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
        home: const Scaffold(body: DashboardScreen()),
      ),
    ));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    // The band is the first row of the dashboard's list. Its own Padding is the
    // one that owns the vertical insets.
    final Finder bandPadding = find
        .ancestor(
            of: find.textContaining('LINKED').first,
            matching: find.byType(Padding))
        .first;
    final Rect band = t.getRect(bandPadding);
    final Rect dot = t.getRect(find.byType(Container).first);
    final double above = dot.top - band.top;
    final double below = band.bottom - dot.bottom;
    expect((above - below).abs(), lessThanOrEqualTo(2.0),
        reason: 'the band padded $above above and $below below the content');
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
