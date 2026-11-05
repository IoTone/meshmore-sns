// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/map_screen.dart';
import 'package:meshmore_sns_app/screens/street_map_view.dart';

import '../meshcore/fake_transport.dart';

/// The Map tab's tool column, and the two rules that stop the map drawing
/// lines that mean nothing.
///
/// The owner's report: the map's tools were split across both edges, so the
/// ones on the left were lost behind the thumb that uses the right column;
/// and two markers a few pixels apart came with a stroke that turned a corner
/// and did not join them. A radio reports a position, not a bearing, so a
/// marker must never imply one, and an estimate too large to fit the screen
/// must not be drawn as an arc through the middle of it.
const ValueKey<String> _controlsKey = ValueKey<String>('map-controls');
const ValueKey<String> _offlineKey = ValueKey<String>('map-offline-maps-button');
const ValueKey<String> _placesKey = ValueKey<String>('map-places-button');
const ValueKey<String> _layersKey = ValueKey<String>('map-layers-menu');

Future<(MapsController, MeshcoreController)> _pump(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => t.binding.setSurfaceSize(null));
  late final Directory dir;
  late final MapsController maps;
  // Real file I/O must run outside the fake-async zone.
  await t.runAsync(() async {
    dir = await Directory.systemTemp.createTemp('mapchrome');
    maps = MapsController(
      rootDir: () async => dir,
      fetcher: (Uri url, {String? etag, int? ifModifiedSinceMs}) async =>
          FetchResult(FetchStatus.ok,
              bytes: Uint8List(100), maxAge: const Duration(hours: 1)),
      prefsKey: 'maps.chrome.test.v1',
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
        ChangeNotifierProvider<PlaceStore>.value(value: PlaceStore()),
        Provider<PlaceReportBudget>(
            create: (_) => PlaceReportBudget(clock: DateTime.now)),
      ],
      child: const Scaffold(body: MapScreen()),
    ),
  ));
  await t.pump();
  return (maps, mc);
}

Future<void> _drain(WidgetTester t, MeshcoreController mc, MapsController m) async {
  mc.dispose();
  m.dispose();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

/// A `Transform` that rotates, as opposed to one that only translates or
/// scales. Matrix4 stores column-major: m[1] and m[4] are the sin terms.
bool _isRotation(Transform t) {
  // Column-major storage: index 1 and index 4 are the two sine terms of a
  // rotation about z.
  final List<double> m = t.transform.storage;
  return m[1].abs() > 0.001 || m[4].abs() > 0.001;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // The street map subscribes to the compass; without a handler the missing
    // plugin throws into the test zone.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('hemanthraj/flutter_compass'),
            (MethodCall call) async => null);
  });

  testWidgets('every map tool is in the one right-hand column',
      (WidgetTester t) async {
    final (MapsController m, MeshcoreController mc) = await _pump(t);
    final Finder controls = find.byKey(_controlsKey);
    expect(controls, findsOneWidget);
    for (final ValueKey<String> k in <ValueKey<String>>[
      _offlineKey,
      _placesKey,
    ]) {
      expect(find.descendant(of: controls, matching: find.byKey(k)),
          findsOneWidget,
          reason: '$k belongs in the map control column');
    }
    // Under the built-in controls, not above them: the column reads zoom,
    // recentre, basemap, layers, then the host's tools.
    final double layersY = t.getTopLeft(find.byKey(_layersKey)).dy;
    expect(t.getTopLeft(find.byKey(_offlineKey)).dy, greaterThan(layersY));
    expect(t.getTopLeft(find.byKey(_placesKey)).dy,
        greaterThan(t.getTopLeft(find.byKey(_offlineKey)).dy));
    await _drain(t, mc, m);
  });

  testWidgets('no marker is drawn with a bearing', (WidgetTester t) async {
    final (MapsController m, MeshcoreController mc) = await _pump(t);
    // The test host has no compass, so the self wedge has no source and is not
    // drawn; peers never carry one at all. Any rotation in the tree is a
    // marker claiming a heading the radio does not report.
    // Scoped to the markers: the Scaffold's FAB transition rotates its own
    // child, which says nothing about the map.
    final List<String> rotatedMarkers = <String>[];
    for (final Element e in find.byType(Transform).evaluate()) {
      if (!_isRotation(e.widget as Transform)) continue;
      bool inMarkerLayer = false;
      e.visitAncestorElements((Element a) {
        if (a.widget is MarkerLayer) inMarkerLayer = true;
        return !inMarkerLayer;
      });
      if (inMarkerLayer) rotatedMarkers.add(e.widget.runtimeType.toString());
    }
    expect(rotatedMarkers, isEmpty,
        reason: 'a radio reports position, not a bearing');
    await _drain(t, mc, m);
  });

  group('the reach ring is an estimate and is drawn only where it reads', () {
    test('a ring inside half the viewport is drawn', () {
      expect(StreetMapView.reachRingReadable(1500, 4000), isTrue);
      expect(StreetMapView.reachRingReadable(1999, 4000), isTrue);
    });
    test('a ring larger than the screen is not', () {
      expect(StreetMapView.reachRingReadable(2001, 4000), isFalse);
      expect(StreetMapView.reachRingReadable(20000, 4000), isFalse);
    });
    test('metres per pixel halves per zoom level and shrinks with latitude', () {
      final double z10 = StreetMapView.metersPerPixel(10, 39.0);
      final double z14 = StreetMapView.metersPerPixel(14, 39.0);
      expect(z10 / z14, closeTo(16.0, 0.001));
      final double equator = StreetMapView.metersPerPixel(14, 0);
      final double denver = StreetMapView.metersPerPixel(14, 39.7);
      expect(denver, lessThan(equator));
      final double expected =
          156543.03392 * math.cos(39.7 * math.pi / 180) / math.pow(2, 14);
      expect(denver, closeTo(expected, 0.5));
    });
  });

  group('the trail is a path or nothing', () {
    ({double latitude, double longitude, int unixSec}) pt(
            double lat, double lon) =>
        (latitude: lat, longitude: lon, unixSec: 0);

    test('two fixes a few metres apart draw nothing', () {
      // One GPS sample plus jitter: the stray segment beside the marker.
      expect(
          StreetMapView.trailPathFor(<({double latitude, double longitude, int unixSec})>[
            pt(39.7000, -104.7000),
            pt(39.70005, -104.70005),
          ]),
          isEmpty);
    });

    test('three fixes over more than twenty metres draw a path', () {
      final List<LatLng> path =
          StreetMapView.trailPathFor(<({double latitude, double longitude, int unixSec})>[
        pt(39.7000, -104.7000),
        pt(39.7010, -104.7000),
        pt(39.7020, -104.7000),
      ]);
      expect(path, hasLength(3));
    });

    test('the live fix closes the path so the line meets the marker', () {
      final List<LatLng> path =
          StreetMapView.trailPathFor(<({double latitude, double longitude, int unixSec})>[
        pt(39.7000, -104.7000),
        pt(39.7010, -104.7000),
      ], selfLat: 39.7020, selfLon: -104.7000);
      expect(path, hasLength(3));
      expect(path.last, const LatLng(39.7020, -104.7000));
    });

    test('a live fix already in the trail is not appended twice', () {
      final List<LatLng> path =
          StreetMapView.trailPathFor(<({double latitude, double longitude, int unixSec})>[
        pt(39.7000, -104.7000),
        pt(39.7010, -104.7000),
        pt(39.7020, -104.7000),
      ], selfLat: 39.7020, selfLon: -104.7000);
      expect(path, hasLength(3));
    });
  });
}
