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
import 'package:meshmore_sns_app/perms/location_service.dart';
import 'package:meshmore_sns_app/screens/elevation_profile_view.dart';
import 'package:meshmore_sns_app/screens/grid_screen.dart';
import 'package:meshmore_sns_app/screens/mesh_tree_view.dart';
import 'package:meshmore_sns_app/shell/horizontal_drag_claim.dart';
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

  // The hop strip is a readout plus a control, and the readout now carries a
  // count: "≤3 hops · 12 routed". It used to sit in a fixed 96 dp box, which
  // clipped that to nothing useful, so the label now takes a share of the strip
  // and the slider keeps the rest. A readout may never eat the control.
  for (final (double width, double scale) in <(double, double)>[
    (320, 2.0),
    (320, 1.3),
    (411, 2.0),
  ]) {
    testWidgets('the hop strip keeps a draggable slider at ${width}dp ${scale}x',
        (WidgetTester t) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await t.binding.setSurfaceSize(Size(width, 720));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => fake,
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      );
      await t.pumpWidget(host(const MeshTreeView(), mc, scale));
      await mc.connect();
      fake.emit(selfInfoFrame());
      // A contact with a learned two-hop route, so the ladder has a depth to
      // limit and the slider is offered: with no learned routes the stop cannot
      // be applied to anything and the strip says so instead.
      fake.emit(contactFrame(
          name: 'A', firstPubByte: 0x81, outPathLen: 2, path: <int>[3, 7]));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));

      final Rect slider = t.getRect(find.byType(Slider));
      expect(slider.width, greaterThanOrEqualTo(120),
          reason: 'the label squeezed the slider to ${slider.width} dp at '
              '${width}dp / ${scale}x');
      // And the label is actually on screen rather than clipped away.
      final Iterable<Text> labels = t
          .widgetList<Text>(find.byType(Text))
          .where((Text w) => (w.data ?? '').contains('hops') ||
              (w.data ?? '') == 'Flood / All' ||
              (w.data ?? '') == 'Direct');
      expect(labels, isNotEmpty, reason: 'the strip names its stop');
      for (final Text w in labels) {
        final Rect r = t.getRect(find.text(w.data!).first);
        expect(r.width, greaterThan(0));
      }
      mc.dispose();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });
  }

  testWidgets('the altitude profile keeps a sideways drag, so it cannot page',
      (WidgetTester t) async {
    // A diagram: paging the app sideways while the reader traces a summit is
    // the worst of both. The view claims the drag, so the gesture is inert
    // instead of changing the view under their finger.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await t.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(host(const GridScreen(), mc, 1.3));
    await mc.connect();
    fake.emit(selfInfoFrame());
    for (int i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // The radar does not claim: a drag on a dial means nothing, so paging is
    // harmless there.
    expect(shellDragClaim.isClaimed, isFalse);

    await t.tap(find.byTooltip('View'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Altitude').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(shellDragClaim.isClaimed, isTrue,
        reason: 'the altitude profile must not page under a sideways drag');

    // Back to a view that does not claim, so the shell pages again.
    await t.tap(find.byTooltip('View'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Radar').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(shellDragClaim.isClaimed, isFalse);

    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

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
    fake.emit(contactFrame(
        name: 'A', firstPubByte: 0x81, outPathLen: 2, path: <int>[3, 7]));
    fake.emit(contactFrame(
        name: 'B', firstPubByte: 0x82, outPathLen: 1, path: <int>[5]));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    final Finder slider = find.byType(Slider);
    expect(slider, findsOneWidget, reason: 'the hop slider is on the strip');

    // Recenter only exists once the view has been taken off auto-fit, so pan
    // first — that is also the state in which it used to be painted under the
    // slider.
    // The tree runs a force-simulation ticker, so `pumpAndSettle` never
    // settles here: pump fixed frames instead.
    final Offset centre = t.getCenter(find.byType(InteractiveViewer));
    await t.dragFrom(centre, const Offset(-80, -60));
    for (int i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }

    final Finder recenter = find.text('Recenter');
    if (recenter.evaluate().isNotEmpty) {
      // Every grid view's reset lives in the top-right corner: the heat map had
      // it there and the tree did not, which is how the two came to differ. It
      // used to sit above the hop strip, after both were found sharing
      // `bottom: 12`.
      final Rect r = t.getRect(recenter);
      final Rect strip = t.getRect(slider);
      expect(r.bottom, lessThan(strip.top),
          reason: 'Recenter must never touch the hop strip');
      expect(r.center.dx, greaterThan(180),
          reason: 'and it lives on the right-hand side, with the others');
    }
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });

  // The chart states where its heights come from, and stops calling itself
  // Fuji. Both were live defects: the header read "MESHMORE :: FUJIさん" in the
  // English bundle, a stray honorific from an earlier name for the view, and
  // nothing on screen said that a peer's height is its own telemetry while our
  // line is the phone's GPS fix, which is the difference that decides how much
  // the chart can be trusted.
  testWidgets('the altitude view states where each height came from',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    // The chart draws nothing without an altitude anywhere, and the only
    // altitude it can have for itself is the phone's GPS. That is also the
    // provenance the legend has to state, so the fix is what puts the chart on
    // screen in the first place.
    final NoopLocationService loc = NoopLocationService(
        next: PhoneFix(
            latitude: 47.6, longitude: -122.3, altitudeMeters: 92));
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      locationService: loc,
    );
    await t.pumpWidget(host(const ElevationProfileView(), mc, 1.0));
    await mc.connect();
    fake.emit(selfInfoFrame());
    fake.emit(advertFrame(name: 'NeedsAlt', firstPubByte: 0x71));
    // The view asks for its own fix in its first frame, which is the path the
    // test lets do the work rather than calling the controller twice.
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(ElevationProfileView)));
    expect(find.text(l.elevationAltitudesFrom), findsOneWidget);
    expect(find.textContaining('さん'), findsNothing,
        reason: 'the English bundle still carries the old Japanese honorific');

    mc.dispose();
    await t.pumpWidget(const SizedBox());
    // Two timers outlive the frame: the view's own poll indicator runs for two
    // seconds, and a phone fix records a coverage cell whose own timer runs for
    // five. Let both land before the tree goes away, or the harness reports a
    // pending timer.
    await t.pump(const Duration(seconds: 7));
  });
}
