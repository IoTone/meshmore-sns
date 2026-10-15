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
}
