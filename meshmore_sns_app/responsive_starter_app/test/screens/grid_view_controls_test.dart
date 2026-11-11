// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/elevation_profile_view.dart';
import 'package:meshmore_sns_app/screens/mesh_tree_view.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// The grid views' controls, at sizes and text scales the screenshots never
/// reached.
///
/// Two of these were only wrong on a phone: the mesh tree's Recenter button was
/// painted under the hop slider (both at `bottom: 12`), and the altitude view
/// placed its chip and its ask button at `top: 56` and `top: 132`, offsets
/// measured at one text size, so at 1.3x the button was drawn over the chip.
/// Both are layout facts, so both are testable.
void main() {
  Widget host(Widget view, MeshcoreController mc, double scale) => MediaQuery(
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
            providers: <SingleChildWidget>[
              ChangeNotifierProvider<MeshcoreController>.value(value: mc),
              ChangeNotifierProvider<ThemeController>(
                  create: (_) => ThemeController()),
            ],
            child: Scaffold(body: view),
          ),
        ),
      );

  for (final double scale in <double>[1.0, 1.3, 1.5, 2.0]) {
    testWidgets('the altitude view stacks its chip and its action at ${scale}x',
        (WidgetTester t) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => fake,
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      );
      await t.pumpWidget(host(const ElevationProfileView(), mc, scale));
      await mc.connect();
      // Our own altitude is enough to draw; a peer with no altitude is what
      // makes the ask action appear.
      fake.emit(selfInfoFrame());
      fake.emit(advertFrame(name: 'NeedsAlt', firstPubByte: 0x71));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));

      expect(t.takeException(), isNull,
          reason: 'the altitude view overflowed at ${scale}x');

      final Finder ask = find.byKey(const ValueKey<String>('elevation-ask-nodes'));
      if (ask.evaluate().isNotEmpty) {
        // The action must sit below the chip, never on top of it. "On top" is
        // any vertical overlap, which is what the hardcoded offsets produced.
        final Finder chip = find.text(AppLocalizations.of(
                t.element(find.byType(ElevationProfileView)))
            .elevationSelfTelemetry);
        expect(chip, findsOneWidget);
        expect(t.getRect(ask).top,
            greaterThanOrEqualTo(t.getRect(chip).bottom - 1),
            reason: 'the ask action overlaps the self chip at ${scale}x');
      }
      mc.dispose();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });
  }

  testWidgets('the mesh tree keeps Recenter clear of the hop slider',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await t.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection: MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(host(const MeshTreeView(), mc, 1.3));
    await mc.connect();
    fake.emit(selfInfoFrame());
    fake.emit(advertFrame(name: 'A', firstPubByte: 0x81));
    fake.emit(advertFrame(name: 'B', firstPubByte: 0x82));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    final Finder recenter = find.byTooltip('Recenter');
    final Finder slider = find.byType(Slider);
    expect(slider, findsOneWidget, reason: 'the hop slider is on the strip');
    if (recenter.evaluate().isNotEmpty) {
      final Rect r = t.getRect(recenter);
      final Rect s = t.getRect(slider);
      final bool overlaps = r.left < s.right &&
          r.right > s.left &&
          r.top < s.bottom &&
          r.bottom > s.top;
      expect(overlaps, isFalse,
          reason: 'Recenter is painted under the slider, so it cannot be tapped');
    }
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
