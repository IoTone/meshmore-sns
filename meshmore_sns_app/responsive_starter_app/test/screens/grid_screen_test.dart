// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/fabric_survey_view.dart';
import 'package:meshmore_sns_app/screens/grid_screen.dart';

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
    expect(find.text('Radial'), findsOneWidget);
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

  testWidgets('the chosen view outlives the widget, not the session',
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
  testWidgets('R109 swipe mode drops the drag, not the taps',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(mc));
    await t.pump();
    await t.tap(find.byTooltip('View'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Coverage').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    // Swipe mode: the map does not take the drag, and it is still tappable.
    // Before this, the whole body was inside an IgnorePointer, so a node you
    // could see could not be opened until you switched modes.
    expect(t.widget<FabricSurveyView>(find.byType(FabricSurveyView)).interactive,
        isFalse);
    await t.tap(find.byKey(const ValueKey<String>('grid-pan-toggle')));
    await t.pump();
    expect(t.widget<FabricSurveyView>(find.byType(FabricSurveyView)).interactive,
        isTrue);
  });

  testWidgets('R109 the Swipe ⇄ Pan toggle exists only where the view pans, '
      'and the claim follows it', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(mc));
    await t.pump();

    // Radar: no drag of its own, so no toggle and no claim.
    expect(find.byKey(const ValueKey<String>('grid-pan-toggle')), findsNothing);
    expect(shellDragClaim.isClaimed, isFalse);

    // A pannable view: the toggle, in swipe mode, with the view held still.
    await t.tap(find.byTooltip('View'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Coverage').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(
        find.byKey(const ValueKey<String>('grid-pan-toggle')), findsOneWidget);
    expect(find.byTooltip('Swipe mode: swipe left/right for other screens. '
        'Tap to pan and zoom this map'), findsOneWidget);
    expect(shellDragClaim.isClaimed, isFalse);

    // Pan mode holds the claim; tapping again releases it.
    await t.tap(find.byKey(const ValueKey<String>('grid-pan-toggle')));
    await t.pump();
    expect(shellDragClaim.heldBy(GridScreen.dragHolder), isTrue);
    expect(
        find.byTooltip('Pan & zoom mode: drags move the map. Tap to swipe '
            'between screens again'),
        findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('grid-pan-toggle')));
    await t.pump();
    expect(shellDragClaim.isClaimed, isFalse);

    // The equal grid was deleted with R117: equal-area cells answered the same
    // question the Map tab answers better, and its own doc called it a stage-1
    // skeleton. The picker must not offer it any more.
    await t.tap(find.byTooltip('View'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('More views').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Equal grid'), findsNothing,
        reason: 'the equal grid view is gone, so no picker row may offer it');
    // Close the sheet before the next step: a modal sheet left open swallows
    // the next tap and the assertions after it would test the wrong view.
    await t.tapAt(const Offset(4, 4));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    // A report view draws to fit, so the toggle disappears.
    await t.tap(find.byTooltip('View'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Weather (environment)').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey<String>('grid-pan-toggle')), findsNothing);

    // Disposing the tab in pan mode must not leave the shell locked.
    await t.tap(find.byTooltip('View'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Coverage').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byKey(const ValueKey<String>('grid-pan-toggle')));
    await t.pump();
    expect(shellDragClaim.heldBy(GridScreen.dragHolder), isTrue);
    await t.pumpWidget(const SizedBox());
    expect(shellDragClaim.isClaimed, isFalse,
        reason: 'the tab lets go of the drag when it is disposed');
    mc.dispose();
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
    expect(find.text('Wide'), findsWidgets);
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('W2 the text sizes come from the skin ladder, not literals',
      (WidgetTester t) async {
    // The migration replaced four literals on this screen: the picker's
    // long label (13), the status line (12), the legend's section title (11)
    // and the legend row text (12). Every preset's typeScale is 1.0, so the
    // resolved sizes must still be the numbers the literals were — a
    // migration that moves a pixel fails here instead of passing review.
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

    Text picker() => t.widget<Text>(find.text('Radial'));
    expect(picker().style?.fontSize, type.sizeBodyLg);
    expect(picker().style?.fontSize, 13);
    expect(picker().style?.fontWeight, FontWeight.w600);

    Text status() =>
        t.widget<Text>(find.textContaining('1 shown'));
    expect(status().style?.fontSize, type.sizeBody);
    expect(status().style?.fontSize, 12);

    await t.tap(find.byTooltip('Show legend'));
    await t.pump();
    expect(t.widget<Text>(find.text('LEGEND')).style?.fontSize, type.sizeSm);
    expect(find.text('LEGEND'), findsOneWidget);
    expect(t.widget<Text>(find.text('LEGEND')).style?.fontSize, 11);

    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

}
