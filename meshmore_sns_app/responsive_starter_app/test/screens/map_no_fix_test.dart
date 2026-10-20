// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_connection.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/map_screen.dart';
import 'package:meshmore_sns_app/screens/street_map_view.dart';

import '../meshcore/fake_transport.dart';

/// R69 — the Map tab is browsable with no position fix; the grid's
/// street-map mode keeps its empty state.
Future<MeshcoreController> _pump(WidgetTester t, Widget body,
    {Locale locale = const Locale('en')}) async {
  await t.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final MeshcoreController ctrl = MeshcoreController(
    transportFactory: () async => FakeMeshcoreTransport(connected: true),
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await t.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ChangeNotifierProvider<MeshcoreController>.value(
        value: ctrl,
        child: Scaffold(body: body),
      ),
    ),
  );
  await t.pump();
  return ctrl;
}

void main() {
  const String en =
      'No position fix yet. This is a world view, not centred on you.';

  testWidgets('Map tab with no fix renders a map and the banner',
      (WidgetTester t) async {
    final MeshcoreController c = await _pump(t, const MapScreen());
    expect(find.byType(FlutterMap), findsOneWidget,
        reason: 'a map, not just text');
    expect(find.text(en), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('map-no-fix-banner')),
        findsOneWidget);
    final FlutterMap fm = t.widget(find.byType(FlutterMap));
    expect(fm.options.initialZoom, StreetMapView.browseZoom);
    expect(fm.options.initialCenter, StreetMapView.browseCentre);
    expect(find.byTooltip('Offline maps'), findsOneWidget);
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('the banner is Japanese in the ja locale',
      (WidgetTester t) async {
    final MeshcoreController c =
        await _pump(t, const MapScreen(), locale: const Locale('ja'));
    expect(find.textContaining('世界地図'), findsOneWidget);
    expect(find.text(en), findsNothing);
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('a bare StreetMapView (the grid mode) keeps its empty state',
      (WidgetTester t) async {
    final MeshcoreController c = await _pump(t, const StreetMapView());
    expect(find.byType(FlutterMap), findsNothing);
    expect(
        find.byKey(const ValueKey<String>('map-no-fix-banner')), findsNothing);
    expect(find.textContaining('waiting for a GPS fix'), findsOneWidget);
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('R70: the credit line is not covered by the no-fix banner',
      (WidgetTester t) async {
    final MeshcoreController c = await _pump(t, const MapScreen());
    final Finder credit = find.text('© OpenStreetMap contributors');
    expect(credit, findsOneWidget);
    final Rect banner = t.getRect(
        find.byKey(const ValueKey<String>('map-no-fix-banner')));
    expect(t.getRect(credit).bottom, lessThanOrEqualTo(banner.top),
        reason: 'attribution sits above the banner, not under it');
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('R70: controls are 48dp and the right band starts below them',
      (WidgetTester t) async {
    final MeshcoreController c = await _pump(t, const MapScreen());
    final Rect col =
        t.getRect(find.byKey(const ValueKey<String>('map-controls')));
    expect(col.width, greaterThanOrEqualTo(48));
    expect(col.height, greaterThanOrEqualTo(5 * 48),
        reason: 'five controls, 48dp each');
    final Rect band =
        t.getRect(find.byKey(const ValueKey<String>('mm-edge-right')));
    expect(band.top, greaterThanOrEqualTo(col.bottom),
        reason: 'the band must not overlap any control');
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
