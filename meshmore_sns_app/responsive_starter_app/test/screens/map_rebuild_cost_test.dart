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
import 'package:meshmore_sns_app/maps/hex_field_layer.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshcore/meshcore.dart';
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
          {String? etag, int? ifModifiedSinceMs, int? maxBytes}) async =>
      FetchResult(FetchStatus.ok,
          bytes: Uint8List(1000), maxAge: const Duration(hours: 1));
}

OwnLocation _at(double lat, double lon) => OwnLocation(
      latitude: lat,
      longitude: lon,
      source: OwnLocationSource.phoneFix,
    );

/// The cells the density layer is drawing right now.
List<HexCell> _hexPolygons(WidgetTester t) {
  final HexFieldLayer layer =
      t.widget<HexFieldLayer>(find.byType(HexFieldLayer));
  return layer.cells;
}


/// The markers the pin layer is drawing right now, node pins only.
List<Marker> _nodePins(WidgetTester t) {
  for (final MarkerLayer layer in t.widgetList<MarkerLayer>(
      find.byType(MarkerLayer))) {
    if (layer.markers.any((Marker m) => m.width == 32)) return layer.markers;
  }
  return const <Marker>[];
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

  Future<
      (
        MapsController,
        MeshcoreController,
        GeofenceController,
        FakeMeshcoreTransport
      )> pump(WidgetTester t) async {
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
      // The field is drawn only over ground the map has drawn; a test has no
      // tiles, so it says the ground is there.
      maps.assumeTilesReady = true;
    });
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
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
    // The field is a reading of the nodes, so there have to be some, with
    // positions, or the layer is not built at all.
    await mc.connect();
    fake.emit(selfInfoFrameAt(lat: 39.0, lon: -105.0));
    fake.emit(advertFrameAt(lat: 39.0001, lon: -104.9999, name: 'N1'));
    fake.emit(advertFrameAt(
        lat: 39.0002, lon: -104.9998, name: 'N2', firstPubByte: 40));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    // The density field is off until it is asked for, and it is the layer whose
    // cost this file is about.
    await t.tap(find.byKey(const ValueKey<String>('map-overlays-button')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('map-density-toggle')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.tapAt(const Offset(20, 20));
    await t.pumpAndSettle();
    return (maps, mc, fences, fake);
  }

  testWidgets('a geofence sample that changes nothing rebuilds nothing',
      (WidgetTester t) async {
    final (
      MapsController maps,
      MeshcoreController mc,
      GeofenceController fences,
      FakeMeshcoreTransport _
    ) = await pump(t);
    // The store writes a sealed document, which is real file I/O: it has to run
    // outside the fake-async zone or the await never completes.
    await t.runAsync(() => fences.addFence(
        label: 'Camp', latitude: 40.0, longitude: -105.0, radiusMeters: 200));
    await t.pump();

    // Walk in: the inside-state flips, so the map must redraw the fence.
    fences.sample(_at(40.0, -105.0));
    await t.pump();
    final List<HexCell> afterEntry = _hexPolygons(t);

    // Standing still: the controller notifies again, and the map must not care.
    // This is the once-a-second rebuild that ran the heap out.
    fences.sample(_at(40.0, -105.0));
    await t.pump();
    expect(identical(_hexPolygons(t), afterEntry), isTrue,
        reason: 'a sample that changed no fence rebuilt the whole map');

    mc.dispose();
    maps.dispose();
    fences.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
    // The vector renderer cancels its in-flight tile jobs when the layer goes
    // away, and reports the cancellation through the image resource service.
    // That is teardown noise, not a failure of the thing under test.
    t.takeException();
  });

  testWidgets('a rebuild that changes nothing reuses the field',
      (WidgetTester t) async {
    final (
      MapsController maps,
      MeshcoreController mc,
      GeofenceController fences,
      FakeMeshcoreTransport _
    ) = await pump(t);
    final List<HexCell> first = _hexPolygons(t);

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
    await t.pump(const Duration(seconds: 30));
    t.takeException();
  });

  testWidgets('a notify that moves no node keeps the pins', (WidgetTester t) async {
    final (
      MapsController maps,
      MeshcoreController mc,
      GeofenceController fences,
      FakeMeshcoreTransport fake
    ) = await pump(t);
    final List<Marker> first = _nodePins(t);
    expect(first, isNotEmpty, reason: 'two nodes with positions, so there are pins');

    // A plain rebuild: same nodes, same box, same skin. The pins are the
    // expensive part of the map's build, so they are kept rather than rebuilt
    // for a reason that changes none of their inputs.
    await t.pump();
    expect(identical(_nodePins(t), first), isTrue,
        reason: 'the pins were rebuilt for a rebuild that changed nothing');

    // A new node is a real change, so the pins must be built again.
    fake.emit(advertFrameAt(
        lat: 39.0003, lon: -104.9997, name: 'N3', firstPubByte: 41));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(identical(_nodePins(t), first), isFalse,
        reason: 'a new node must appear on the map');

    mc.dispose();
    maps.dispose();
    fences.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
    t.takeException();
  });
}
