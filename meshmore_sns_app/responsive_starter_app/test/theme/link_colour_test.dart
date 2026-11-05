// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/shell/home_shell.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/fake_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('R97 the link colour is actually green in every preset', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      final Color c = kMmPresets[p]!.link;
      final HSVColor hsv = HSVColor.fromColor(c);
      expect(hsv.hue, inInclusiveRange(90, 165), reason: '${p.name}: hue');
      expect(hsv.saturation, greaterThan(0.30),
          reason: '${p.name}: saturation');
      // R115 — a light ground carries a dark green, so the rule cannot be a
      // brightness floor. What must hold everywhere is that the link reads as
      // text on the preset's own ground.
      final double linkLum = c.computeLuminance();
      final double baseLum = kMmPresets[p]!.base.computeLuminance();
      final double ratio = (math.max(linkLum, baseLum) + 0.05) /
          (math.min(linkLum, baseLum) + 0.05);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: '${p.name}: link on its own ground');
    }
  });

  test('R97 a live link is not the per-preset ok token', () {
    // The defect: `ok` is beige in SEELE, cyan in AG-HUD, amber in Recon.
    expect(kMmPresets[MmThemePreset.seele]!.link,
        isNot(kMmPresets[MmThemePreset.seele]!.ok));
    expect(kMmPresets[MmThemePreset.recon]!.link,
        isNot(kMmPresets[MmThemePreset.recon]!.ok));
  });

  for (final MmThemePreset preset in <MmThemePreset>[
    MmThemePreset.seele,
    MmThemePreset.studio,
    MmThemePreset.nerv,
  ]) {
    testWidgets('R97 the app-bar chip paints the link green (${preset.name})',
        (WidgetTester t) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ThemeController theme = ThemeController()..setPreset(preset);
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc =
          MeshcoreController(transportFactory: () async => fake);
      await mc.connect();
      fake.emit(selfInfoFrame()); // handshake complete
      await t.pump();
      expect(mc.isReady, isTrue);
      final MmSkin skin = mmSkinFor(preset);

      await t.pumpWidget(MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ],
        child: MaterialApp(
          theme: buildMmTheme(skin.color, shape: skin.shape),
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Center(child: RadioLinkIndicator())),
        ),
      ));
      await t.pump();

      final Container dot = t.widget<Container>(find
          .descendant(
              of: find.byType(RadioLinkIndicator),
              matching: find.byType(Container))
          .first);
      final BoxDecoration d = dot.decoration! as BoxDecoration;
      expect(d.color, skin.color.link);
      expect(t.takeException(), isNull);
      mc.dispose(); // cancel the battery-poll timer before the test ends
    });
  }
}
