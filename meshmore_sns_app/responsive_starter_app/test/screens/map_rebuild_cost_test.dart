// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/geofence/geofence_controller.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/maps/hex_field.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/own_location.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/map_screen.dart';

import '../meshcore/fake_transport.dart';

/// What the map costs to rebuild, and why it used to cost too much.
///
/// The owner reported the app running out of memory and then Android saying it
/// was not responding, on the map page. Two things were rebuilding the whole
/// screen for reasons that had nothing to do with the picture:
///
///  * `GeofenceController` ticks once a second and notifies on every sample, and
///    the map watched it, so the entire build — the hex field, a polygon per
///    cell, six corners per polygon, the vector layer and its tile provider —
///    ran once a second for ever, whether or not a fence existed.
///  * The field itself was recomputed on every build, so any other rebuild
///    driver (a fading message bubble, a skin change, a poll) paid the same
///    price.
///
/// These cases hold both fixes: a sample that changes nothing rebuilds nothing,
/// and a rebuild that changes nothing reuses the field it already has.
class _Net {
  Future<FetchResult> call(Uri url,
          {String? etag, int? ifModifiedSinceMs}) async =>
      FetchResult(FetchStatus.ok,
          bytes: Uint8List(1000), maxAge: const Duration(hours: 1));
}

OwnLocation _at(double lat, double lon) => OwnLocation(
      latitude: lat,
      longitude: lon,
      source: OwnLocationSource.phoneFix,
    );

/// The polygons the density layer is drawing right now.
List<Polygon<HexCell>> _hexPolygons(WidgetTester t) {
  final PolygonLayer<HexCell> layer = t.widget<PolygonLayer<HexCell>>(
      find.byType(PolygonLayer<HexCell>));
  return layer.polygons;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // The street map subscribes to the compass; without a handler the missing
    // plugin throws into the test zone.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('meshmore/compass'), (MethodCall c) async => null);
  });

  Future<(MapsController, MeshcoreController, GeofenceController)> pump(
      WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    late final Directory dir;
    late final MapsController maps;
    await t.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('mapcost');
      maps = MapsController(
        rootDir: () async => dir,
        fetcher: _Net().call,
        prefsKey: 'maps.cost.test.v1',
        pace: Duration.zero,
      );
      await maps.load();
    });
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
    );
    final GeofenceController fences =
        GeofenceController(mc: mc, autoTick: false);
    await t.pumpWidget(MaterialApp(
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
          ChangeNotifierProvider<MapsController>.value(value: maps),
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<GeofenceController>.value(value: fences),
          ChangeNotifierProvider<PlaceStore>.value(value: PlaceStore()),
          Provider<PlaceReportBudget>(
              create: (_) => PlaceReportBudget(clock: DateTime.now)),
        ],
        child: const Scaffold(body: MapScreen()),
      ),
    ));
    await t.pump();
    return (maps, mc, fences);
  }

  testWidgets('a geofence sample that changes nothing rebuilds nothing',
      (WidgetTester t) async {
    final (MapsController maps, MeshcoreController mc, GeofenceController fences) =
        await pump(t);
    await fences.addFence(
        label: 'Camp', latitude: 40.0, longitude: -105.0, radiusMeters: 200);
    await t.pump();

    // Walk in: the inside-state flips, so the map must redraw the fence.
    fences.sample(_at(40.0, -105.0));
    await t.pump();
    final List<Polygon<HexCell>> afterEntry = _hexPolygons(t);

    // Standing still: the controller notifies again, and the map must not care.
    // This is the once-a-second rebuild that ran the heap out.
    fences.sample(_at(40.0, -105.0));
    await t.pump();
    expect(identical(_hexPolygons(t), afterEntry), isTrue,
        reason: 'a sample that changed no fence rebuilt the whole map');

    mc.dispose();
    maps.dispose();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a rebuild that changes nothing reuses the field',
      (WidgetTester t) async {
    final (MapsController maps, MeshcoreController mc, GeofenceController fences) =
        await pump(t);
    final List<Polygon<HexCell>> first = _hexPolygons(t);

    // A skin change rebuilds the map and does change the field's colours, so it
    // is not the case under test. A plain rebuild is: the same nodes, the same
    // box, the same cell size.
    await t.pump();
    expect(identical(_hexPolygons(t), first), isTrue,
        reason: 'the field was rebuilt for a rebuild that changed nothing');

    mc.dispose();
    maps.dispose();
    fences.dispose();
    await t.pumpWidget(const SizedBox());
  });
}
