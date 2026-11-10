// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/elevation_profile_view.dart';
import 'package:meshmore_sns_app/screens/grid_screen.dart';
import 'package:meshmore_sns_app/screens/mesh_tree_view.dart';
import 'package:meshmore_sns_app/screens/sns_cells_view.dart';
import 'package:meshmore_sns_app/screens/weather_view.dart';
import 'package:meshmore_sns_app/shell/horizontal_drag_claim.dart';
import 'package:meshmore_sns_app/shell/shell_view_request.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

Widget _host(MeshcoreController mc,
        {ShellViewRequest? request, TextScaler textScaler = TextScaler.noScaling}) =>
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
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<ThemeController>(
              create: (_) => ThemeController()),
          ChangeNotifierProvider<ShellViewRequest?>.value(value: request),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: const Scaffold(body: GridScreen()),
        ),
      ),
    );

/// Opens the view picker and chooses [label]. One level: every view this tab
/// ships is in the same list.
Future<void> _openView(WidgetTester t, String label) async {
  await t.tap(find.byTooltip('View'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.tap(find.text(label).last);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    GridScreen.resetSession();
    shellDragClaim.reset();
  });

  testWidgets('the picker lists every view at one level, and no map hand-off',
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

    // Every view in one list. "Radar" appears twice: the toolbar shows the
    // current view's name and the sheet lists it.
    expect(find.text('Radar'), findsNWidgets(2));
    expect(find.text('Weather'), findsOneWidget);
    expect(find.text('Mesh tree'), findsOneWidget);
    expect(find.text('Altitude'), findsOneWidget);
    expect(find.text('Message heat'), findsOneWidget);
    // The tab does not route to another tab: the map is the Map tab's job,
    // and there is no hand-off row here.
    expect(find.text('Open the map'), findsNothing);
    // A second level hid four working views behind a menu. It is gone.
    expect(find.text('More views'), findsNothing);
    // R117: the street map is the Map tab's widget, and the equal grid was
    // deleted with it — neither may appear as a view of this tab.
    expect(find.text('Street map'), findsNothing);
    expect(find.text('Equal grid'), findsNothing);
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  testWidgets('every view says what it answers, in one line', (
      WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(mc));
    await t.pump();

    const Map<String, String> purposes = <String, String>{
      'Weather':
          'Temperature, humidity and pressure, from nodes that report them.',
    };
    for (final MapEntry<String, String> e in purposes.entries) {
      await _openView(t, e.key);
      expect(find.text(e.value), findsOneWidget,
          reason: '${e.key} must say what it answers, not only its name');
    }
    // A narrower view carries its line too.
    await _openView(t, 'Mesh tree');
    expect(
        find.text('How nodes reach each other, from the routes they '
            'advertise.'),
        findsOneWidget);
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  testWidgets('the tab offers no way to another tab',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    final ShellViewRequest request = ShellViewRequest();
    await t.pumpWidget(_host(mc, request: request));
    await t.pump();
    final int before = request.seq;
    await t.tap(find.byTooltip('View'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Open the map'), findsNothing,
        reason: 'the grid is a destination, not a router');
    expect(request.seq, before);
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  testWidgets('every surviving view renders and degrades without a radio',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(mc));
    await t.pump();

    await _openView(t, 'Weather');
    expect(find.byType(WeatherView), findsOneWidget);
    await _openView(t, 'Mesh tree');
    expect(find.byType(MeshTreeView), findsOneWidget);
    await _openView(t, 'Altitude');
    expect(find.byType(ElevationProfileView), findsOneWidget);
    await _openView(t, 'Message heat');
    expect(find.byType(SnsCellsView), findsOneWidget);

    // No radio: every one of them says so instead of showing a blank canvas.
    expect(find.text('Not Connected to Mesh'), findsWidgets);
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  // The accessibility floor applies to every view this tab ships, not only to
  // the three the primary list used to show. A RenderFlex overflow is an
  // exception in a widget test, so `takeException` is the assertion.
  testWidgets('every view holds 320 dp at 200 % text', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(mc, textScaler: const TextScaler.linear(2.0)));
    await t.pump();
    expect(t.takeException(), isNull, reason: 'the tab itself overflowed');

    for (final String label in <String>[
      'Weather',
      'Mesh tree',
      'Altitude',
      'Message heat',
      'Radar',
    ]) {
      await _openView(t, label);
      expect(t.takeException(), isNull,
          reason: '$label overflowed at 320 dp and 200 % text');
    }
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  testWidgets('the legend is a key; the prose is behind one tap',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(mc));
    await t.pump();

    await t.tap(find.byTooltip('Show legend'));
    await t.pump();
    // Every visible line in the panel is a glyph and two words, not a
    // sentence about an animation.
    for (final Text text in t.widgetList<Text>(find.byType(Text))) {
      final String? data = text.data;
      if (data == null || data.isEmpty) continue;
      expect(data.length, lessThanOrEqualTo(60),
          reason: 'legend line too long: "$data"');
    }
    // The sentences are still one tap away.
    await t.tap(find.text('Full legend'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Rings are distance bands'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  testWidgets('a node without a position is a signal marker, not a bearing',
      (WidgetTester t) async {
    // The radar draws a marker hollow when it has no reported position, because
    // the angle it sits at is a placeholder and not a direction.
    expect(
        gridMarkerSourceFor(nodeHasLocation: true, selfHasLocation: true),
        GridMarkerSource.position);
    expect(
        gridMarkerSourceFor(nodeHasLocation: false, selfHasLocation: true),
        GridMarkerSource.signal);
    expect(
        gridMarkerSourceFor(nodeHasLocation: true, selfHasLocation: false),
        GridMarkerSource.signal,
        reason: 'without our own fix there is no bearing to measure from');
  });
}
