// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/map_source.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/maps/tile_math.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/maps/maps_screen.dart';
import 'package:meshmore_sns_app/screens/maps/new_pack_screen.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

const String _geo = '{"type":"FeatureCollection","features":[{"type":"Feature",'
    '"properties":{"name":"Center Camp"},"geometry":{"type":"Point",'
    '"coordinates":[-119.2065,40.7861]}}]}';

Widget _host(MeshcoreController mc, MapsController maps, Widget home,
    {Locale locale = const Locale('en')}) {
  final GoRouter router = GoRouter(routes: <RouteBase>[
    GoRoute(path: '/', builder: (_, __) => home),
    GoRoute(
        path: '/settings/maps/new',
        builder: (_, __) => const Scaffold(body: Text('new pack page'))),
  ]);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MeshcoreController>.value(value: mc),
      ChangeNotifierProvider<MapsController>.value(value: maps),
      ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ),
  );
}

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = await Directory.systemTemp.createTemp('maps_screen_test');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<FetchResult> fetch(Uri u, {String? etag, int? ifModifiedSinceMs}) async =>
      u.path.endsWith('.geojson')
          ? FetchResult(FetchStatus.ok,
              bytes: Uint8List.fromList(_geo.codeUnits))
          : FetchResult(FetchStatus.ok, bytes: Uint8List(1000));

  for (final Locale loc in const <Locale>[Locale('en'), Locale('ja')]) {
    testWidgets('maps screen at 360 px with a pack and a layer '
        '(${loc.languageCode})', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final MeshcoreController mc = MeshcoreController(
          transportFactory: () async => FakeMeshcoreTransport());
      // Built inside runAsync: its ready-future must live in the real
      // zone, or awaiting it from runAsync never resolves.
      late final MapsController maps;
      await t.runAsync(() async {
        maps = MapsController(
            rootDir: () async => dir, fetcher: fetch, pace: Duration.zero);
        await maps.load();
        await maps.createPack(
            name: 'Mission District',
            source: kUsgsTopo,
            box: GeoBox.around(37.76, -122.42, 1),
            minZoom: 12,
            maxZoom: 13);
        await maps.idle();
        await maps.addLayer(
            name: 'BRC streets', url: 'https://example.org/brc.geojson');
      });
      await t.pumpWidget(_host(mc, maps, const MapsScreen(), locale: loc));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Mission District'), findsOneWidget);
      expect(find.text('BRC streets'), findsOneWidget);
      // Sources say which ones may be downloaded, and why not.
      await t.scrollUntilVisible(find.text('USGS Imagery'), 200);
      expect(find.text('OpenStreetMap'), findsOneWidget);
      if (loc.languageCode == 'en') {
        expect(find.textContaining('forbids bulk download'), findsNWidgets(2));
        expect(find.text('Offline download allowed (US only)'),
            findsNWidgets(2));
      }
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        maps.dispose();
      });
      mc.dispose();
    });
  }

  testWidgets('new pack: only downloadable sources, live estimate',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    late final MapsController maps;
    await t.runAsync(() async {
      maps = MapsController(
          rootDir: () async => dir, fetcher: fetch, pace: Duration.zero);
      await maps.load();
    });
    await t.pumpWidget(_host(mc, maps, const NewPackScreen()));
    await t.pump();
    expect(t.takeException(), isNull);
    // No own location in the fake: the lat/lon field is offered.
    expect(find.text('No location yet: enter lat, lon'), findsOneWidget);
    expect(find.text('USGS Topo'), findsOneWidget);
    expect(find.text('OpenStreetMap'), findsNothing);
    expect(find.textContaining('tiles · about'), findsNothing);
    await t.enterText(
        find.widgetWithText(TextField, 'lat, lon'), '37.77, -122.42');
    await t.pump();
    expect(find.textContaining('tiles · about'), findsOneWidget);
    // No name yet: the button is off, but no scolding.
    expect(find.text('Give it a name.'), findsNothing);
    final Finder go = find.ancestor(
        of: find.text('Download'),
        matching: find.byWidgetPredicate((Widget w) => w is ButtonStyleButton));
    expect(t.widget<ButtonStyleButton>(go).onPressed, isNull);
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'SF');
    await t.pump();
    expect(t.widget<ButtonStyleButton>(go).onPressed, isNotNull);
    await t.runAsync(() async {
      maps.dispose();
    });
    mc.dispose();
  });
}
