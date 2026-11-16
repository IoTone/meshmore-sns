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
import 'package:meshmore_sns_app/screens/grid_screen.dart';
import 'package:meshmore_sns_app/screens/sns_cells_view.dart';

import 'package:meshmore_sns_app/shell/horizontal_drag_claim.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

Widget _host(MeshcoreController mc) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<ThemeController>(
              create: (_) => ThemeController()),
        ],
        // In the app the grid is a HomeShell tab; the Scaffold stands
        // in for the shell's.
        child: const Scaffold(body: GridScreen()),
      ),
    );


Widget _hostWithScale(MeshcoreController mc, double scale) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (BuildContext c, Widget? child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
        ],
        child: const Scaffold(body: GridScreen()),
      ),
    );

void main() {
  setUp(() {
    GridScreen.resetSession();
    shellDragClaim.reset();
  });

  testWidgets('empty state when nothing is shown', (t) async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(_host(mc));
    await mc.connect();
    fake.emit(selfInfoFrame()); // → ready, but nobody heard yet
    await t.pump();
    expect(find.text('Radar'), findsOneWidget);
    expect(
        find.textContaining('No nodes in range yet'), findsOneWidget);
    expect(t.takeException(), isNull);
    // Tear down — GridScreen owns a repeating AnimationController; the
    // explicit replacement triggers dispose so it's stopped cleanly.
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  testWidgets('with one node visible, status reads "1 shown"',
      (WidgetTester t) async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(_host(mc));
    await mc.connect();
    fake.emit(selfInfoFrame()); // → ready
    fake.emit(advertFrame(name: 'AdvNode', firstPubByte: 70));
    // Animate a couple of frames; the AnimationController repeats so
    // pumpAndSettle would never settle.
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));

    expect(find.textContaining('1 shown'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  testWidgets('not connected: the radar still paints, empty, with the '
      'message — not the empty text (issue #4)',
      (WidgetTester t) async {
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(mc));
    await t.pump();
    expect(find.text('Not Connected to Mesh'), findsOneWidget);
    expect(find.textContaining('No nodes in range yet'), findsNothing);
    expect(
        find.descendant(
            of: find.byType(GridScreen), matching: find.byType(CustomPaint)),
        findsWidgets);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  testWidgets('not connected: nodes heard earlier are not drawn',
      (WidgetTester t) async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(_host(mc));
    await mc.connect();
    fake.emit(selfInfoFrame());
    fake.emit(advertFrame(name: 'AdvNode', firstPubByte: 70));
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));
    expect(find.textContaining('1 shown'), findsOneWidget);

    await mc.disconnect();
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));
    expect(mc.nodes, isNotEmpty, reason: 'the cache keeps the node…');
    expect(find.textContaining('shown'), findsNothing,
        reason: '…but the offline grid does not show it');
    expect(find.text('Not Connected to Mesh'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  testWidgets('the chosen view outlives the widget and the session',
      (WidgetTester t) async {
    // Tall enough that the whole view menu is on screen.
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(mc));
    await t.pump();
    await t.tap(find.byTooltip('View'));
    // The grid runs a ticker, so pumpAndSettle cannot settle here.
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Weather').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Weather'), findsOneWidget);

    // Leave the tab (the PageView disposes it) and come back.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(_host(mc));
    await t.pump();
    expect(find.text('Weather'), findsOneWidget);
    expect(find.text('Radar'), findsNothing);

    // A restart comes back to the same view: the choice is a preference now,
    // not session state (owner, 2026-11-14).
    await t.pumpWidget(const SizedBox());
    GridScreen.resetSession();
    await t.pumpWidget(_host(mc));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Weather'), findsOneWidget,
        reason: 'the view is remembered across a restart');

    // A fresh install has no saved view, so it opens on the radar.
    await t.pumpWidget(const SizedBox());
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GridScreen.resetSession();
    await t.pumpWidget(_host(mc));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Radar'), findsOneWidget,
        reason: 'nothing saved means the default view');
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });
  testWidgets('a view that pans owns its drags, with no mode to switch',
      (WidgetTester t) async {
    // The Swipe ⇄ Pan toggle is gone by the owner's ruling: a drag on a graph
    // or a heat map is a drag, and a page change is a tap on the strip. What
    // remains to prove is that the claim follows the view and the view is
    // interactive, with no control to press first.
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(mc));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    // Radar: no drag of its own, so no claim.
    expect(find.byKey(const ValueKey<String>('grid-pan-toggle')), findsNothing);
    expect(shellDragClaim.isClaimed, isFalse);

    await t.tap(find.byTooltip('View'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Message heat').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey<String>('grid-pan-toggle')), findsNothing,
        reason: 'there is no mode to toggle');
    expect(t.widget<SnsCellsView>(find.byType(SnsCellsView)).interactive, isTrue,
        reason: 'the view takes the drag because it is the view that pans');
    expect(shellDragClaim.heldBy(GridScreen.dragHolder), isTrue,
        reason: 'the shell must not page while a pannable view shows');
  });

  testWidgets('R91 the transport bar fits a 320dp phone at 2.0x text',
      (WidgetTester t) async {
    // The bar's Row overflowed by 26 px at 320 dp with normal text: play,
    // the interval menu and the range chip together want more than the
    // page. It is a Wrap now, so the range chip can take a second line.
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport(connected: true));
    await t.pumpWidget(_hostWithScale(mc, 2.0));
    await mc.connect();
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull, reason: 'no overflow at 320dp/2.0x');
    // The transport is present and says live, because that is what the
    // view is doing.
    expect(find.byTooltip('Pause updates'), findsOneWidget);
    expect(find.text('Auto'), findsWidgets);
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('W2 the text sizes come from the skin ladder, not literals',
      (WidgetTester t) async {
    // The migration replaced the literals on this screen: the picker's long
    // label (13), the status line (12) and the legend's own row text (12). The
    // legend's "LEGEND" title is gone, because a heading saying legend above a
    // legend is a label for a label. Every preset's typeScale is 1.0, so the
    // resolved sizes must still be the numbers the literals were: a migration
    // that moves a pixel fails here instead of passing review.
    // The legend strip is tall; the default 800x600 test surface clips it,
    // which is the pre-existing layout (the real screen is 900+ dp tall).
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final MmType type = mmSkinFor(MmThemePreset.seele).type;
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(_host(mc));
    await mc.connect();
    fake.emit(selfInfoFrame());
    fake.emit(advertFrame(name: 'AdvNode', firstPubByte: 70));
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));

    Text picker() => t.widget<Text>(find.text('Radar'));
    expect(picker().style?.fontSize, type.sizeBodyLg);
    expect(picker().style?.fontSize, 13);
    expect(picker().style?.fontWeight, FontWeight.w600);

    Text status() =>
        t.widget<Text>(find.textContaining('1 shown'));
    expect(status().style?.fontSize, type.sizeBody);
    expect(status().style?.fontSize, 12);

    await t.tap(find.byTooltip('Show legend'));
    await t.pump();
    // The panel starts at its first real line, not at a title above it.
    expect(find.text('LEGEND'), findsNothing);
    expect(
        t.widget<Text>(find.textContaining('Rings are distance bands'))
            .style
            ?.fontSize,
        type.sizeBody);

    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

}
