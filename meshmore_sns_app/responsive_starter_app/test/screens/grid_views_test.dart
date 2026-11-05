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
import 'package:meshmore_sns_app/screens/fabric_survey_view.dart';
import 'package:meshmore_sns_app/screens/globe_view.dart';
import 'package:meshmore_sns_app/screens/grid_screen.dart';
import 'package:meshmore_sns_app/screens/mesh_tree_view.dart';
import 'package:meshmore_sns_app/screens/meshbook_view.dart';
import 'package:meshmore_sns_app/screens/sns_cells_view.dart';
import 'package:meshmore_sns_app/screens/weather_view.dart';
import 'package:meshmore_sns_app/shell/horizontal_drag_claim.dart';
import 'package:meshmore_sns_app/shell/shell_view_request.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

Widget _host(MeshcoreController mc, {ShellViewRequest? request}) => MaterialApp(
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
        child: const Scaffold(body: GridScreen()),
      ),
    );

Future<void> _openView(WidgetTester t, String label,
    {bool more = false}) async {
  await t.tap(find.byTooltip('View'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  if (more) {
    await t.tap(find.text('More views').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }
  await t.tap(find.text(label).last);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    GridScreen.resetSession();
    shellDragClaim.reset();
  });

  testWidgets('the picker leads with three views, the map hand-off and one '
      'level down', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(mc));
    await t.pump();

    await t.tap(find.byTooltip('View'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    // The three that suit a small mesh, in order. "Radial" appears twice: the
    // toolbar shows the current view's name and the sheet lists it.
    expect(find.text('Radial'), findsNWidgets(2));
    expect(find.text('Coverage'), findsOneWidget);
    expect(find.text('Weather (environment)'), findsOneWidget);
    // The map is a hand-off, not a seventh view of the same widget.
    expect(find.text('Open the map'), findsOneWidget);
    expect(find.text('More views'), findsOneWidget);
    // R117: the street map is the Map tab's widget, and the equal grid was
    // deleted with it — neither may appear as a view of this tab.
    expect(find.text('Street map'), findsNothing);
    expect(find.text('Equal grid'), findsNothing);

    // The parked views are one step down, and still reachable.
    await t.tap(find.text('More views').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Globe'), findsOneWidget);
    expect(find.text('Mesh tree'), findsOneWidget);
    expect(find.text('Altitude'), findsOneWidget);
    expect(find.text('Meshbook (channel activity)'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  });

  testWidgets('the map row asks the shell for the map tab',
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
    await t.tap(find.text('Open the map').last);
    await t.pump();
    expect(request.seq, greaterThan(before));
    expect(request.view, RequestedView.map);
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

    // Primary views.
    await _openView(t, 'Coverage');
    expect(find.byType(FabricSurveyView), findsOneWidget);
    await _openView(t, 'Weather (environment)');
    expect(find.byType(WeatherView), findsOneWidget);

    // Parked views, one level down.
    await _openView(t, 'Globe', more: true);
    expect(find.byType(GlobeView), findsOneWidget);
    await _openView(t, 'Mesh tree', more: true);
    expect(find.byType(MeshTreeView), findsOneWidget);
    await _openView(t, 'Altitude', more: true);
    expect(find.byType(ElevationProfileView), findsOneWidget);
    await _openView(t, 'Meshbook (channel activity)', more: true);
    expect(find.byType(MeshbookView), findsOneWidget);
    // SNS cells is the ninth row in More views.
    await _openView(t, 'SNS cells (heat)', more: true);
    expect(find.byType(SnsCellsView), findsOneWidget);

    // No radio: every one of them says so instead of showing a blank canvas.
    expect(find.text('Not Connected to Mesh'), findsWidgets);
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
