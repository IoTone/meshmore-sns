// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_connection.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/grid_screen.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

Widget _host(MeshcoreController mc, {void Function(int)? onSwipePastEnd}) =>
    MaterialApp(
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
        child: Scaffold(body: GridScreen(onSwipePastEnd: onSwipePastEnd)),
      ),
    );

void main() {
  setUp(GridScreen.resetSession);

  testWidgets('empty state when nothing is in fabric', (t) async {
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
    expect(find.text('Radial'), findsOneWidget);
    expect(
        find.textContaining('No fabric in range yet'), findsOneWidget);
    expect(t.takeException(), isNull);
    // Tear down — GridScreen owns a repeating AnimationController; the
    // explicit replacement triggers dispose so it's stopped cleanly.
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  testWidgets('with one node visible, status reads "1 in fabric"',
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

    expect(find.textContaining('1 in fabric'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  testWidgets('not connected: the radar still paints, empty, with the '
      'message — not the empty-fabric text (issue #4)',
      (WidgetTester t) async {
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(mc));
    await t.pump();
    expect(find.text('Not Connected to Mesh'), findsOneWidget);
    expect(find.textContaining('No fabric in range yet'), findsNothing);
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
    expect(find.textContaining('1 in fabric'), findsOneWidget);

    await mc.disconnect();
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));
    expect(mc.nodes, isNotEmpty, reason: 'the cache keeps the node…');
    expect(find.textContaining('in fabric'), findsNothing,
        reason: '…but the offline grid does not show it');
    expect(find.text('Not Connected to Mesh'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  testWidgets('the chosen view outlives the widget, not the session',
      (WidgetTester t) async {
    // Tall enough that the whole view menu is on screen.
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(mc));
    await t.pump();
    await t.tap(find.byTooltip('Switch map view'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Weather (environment)').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Weather (environment)'), findsOneWidget);

    // Leave the tab (the PageView disposes it) and come back.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(_host(mc));
    await t.pump();
    expect(find.text('Weather (environment)'), findsOneWidget);
    expect(find.text('Radial'), findsNothing);

    // A fresh launch starts on the radar again.
    await t.pumpWidget(const SizedBox());
    GridScreen.resetSession();
    await t.pumpWidget(_host(mc));
    await t.pump();
    expect(find.text('Radial'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  // Issue #4 follow-up: inside the shell the grid must still be able
  // to reach every map by swiping, and a pan/zoom map must be able to
  // take the drag back from the swipe — and give it back again.
  group('swipe between maps, Swipe ⇄ Pan', () {
    final Finder swipeArea = find.byKey(const ValueKey<String>('grid-swipe'));
    final Finder toggle = find.byKey(const ValueKey<String>('grid-pan-toggle'));

    Future<void> swipe(WidgetTester t, double dx) async {
      await t.fling(swipeArea, Offset(dx, 0), 1000);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
    }

    testWidgets('left steps forward through the maps, right steps back, '
        'and past the first map the shell is handed the swipe',
        (WidgetTester t) async {
      final List<int> handedOff = <int>[];
      final MeshcoreController mc = MeshcoreController(
          transportFactory: () async => FakeMeshcoreTransport());
      await t.pumpWidget(_host(mc, onSwipePastEnd: handedOff.add));
      await t.pump();
      expect(find.text('Radial'), findsOneWidget);
      // The radar does not pan, so it has no toggle.
      expect(toggle, findsNothing);

      await swipe(t, -300);
      expect(find.text('Globe'), findsOneWidget);
      await swipe(t, -300);
      expect(find.text('Equal grid'), findsOneWidget);
      await swipe(t, 300);
      expect(find.text('Globe'), findsOneWidget);
      await swipe(t, 300);
      expect(find.text('Radial'), findsOneWidget);
      expect(handedOff, isEmpty);

      // Past the first map: the grid stays put, the shell pages back.
      await swipe(t, 300);
      expect(find.text('Radial'), findsOneWidget);
      expect(handedOff, <int>[-1]);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      mc.dispose();
    });

    testWidgets('a pan/zoom map toggles into pan mode (map owns the drag, '
        'shell locked) and back into swipe mode', (WidgetTester t) async {
      final MeshcoreController mc = MeshcoreController(
          transportFactory: () async => FakeMeshcoreTransport());
      await t.pumpWidget(_host(mc));
      await t.pump();
      await swipe(t, -300);
      expect(find.text('Globe'), findsOneWidget);

      // Arriving: swipe mode. The map is held still, the hint says how
      // to pan, and the shell is not locked.
      expect(toggle, findsOneWidget);
      expect(find.text('Swipe ← → for other maps · tap ✋ to pan & zoom'),
          findsOneWidget);
      expect(GridScreen.capturesHorizontalDrag.value, isFalse);

      // Into pan mode: the shell locks and a swipe no longer changes map.
      await t.tap(toggle);
      await t.pump();
      expect(GridScreen.capturesHorizontalDrag.value, isTrue);
      expect(find.text('Pan & zoom · tap ⇆ to swipe between maps'),
          findsOneWidget);
      await swipe(t, -300);
      expect(find.text('Globe'), findsOneWidget);

      // Back to swipe mode: the shell is free and swiping works again.
      await t.tap(toggle);
      await t.pump();
      expect(GridScreen.capturesHorizontalDrag.value, isFalse);
      await swipe(t, -300);
      expect(find.text('Equal grid'), findsOneWidget);

      // Pan mode does not outlive the visit: leaving and coming back
      // lands in swipe mode, so arriving can never trap the swipe.
      await t.tap(toggle);
      await t.pump();
      expect(GridScreen.capturesHorizontalDrag.value, isTrue);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(GridScreen.capturesHorizontalDrag.value, isFalse);
      await t.pumpWidget(_host(mc));
      await t.pump();
      expect(find.text('Equal grid'), findsOneWidget);
      expect(find.text('Swipe ← → for other maps · tap ✋ to pan & zoom'),
          findsOneWidget);
      await swipe(t, 300);
      expect(find.text('Globe'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      mc.dispose();
    });
  });
}
