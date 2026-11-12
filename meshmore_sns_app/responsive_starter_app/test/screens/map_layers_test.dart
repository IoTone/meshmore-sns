// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/maps/event_layer.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/map_screen.dart';

import '../meshcore/fake_transport.dart';

/// R90 — event maps on the map.
///
/// Before this, the only way to turn a layer on or off was Settings >
/// Offline maps, a switch in a row's leading slot, on a screen you reach by
/// leaving the map. `EventLayersOverlay` had no widget test at all, so "the
/// layer draws" and "hiding it hides it" were both unverified.
const String _geo = '''
{"type":"FeatureCollection","features":[
 {"type":"Feature","properties":{"name":"Center Camp"},
  "geometry":{"type":"Point","coordinates":[-119.2065,40.7861]}},
 {"type":"Feature","properties":{},
  "geometry":{"type":"LineString","coordinates":[[-119.2,40.78],[-119.21,40.79]]}},
 {"type":"Feature","properties":{},
  "geometry":{"type":"MultiPolygon","coordinates":[[[[-119.2,40.78],[-119.21,40.78],[-119.21,40.79],[-119.2,40.78]]]]}}
]}
''';

class _Net {
  final Map<String, String> bodies = <String, String>{};
  Future<FetchResult> call(Uri url,
      {String? etag, int? ifModifiedSinceMs}) async {
    final String? body = bodies[url.toString()];
    return FetchResult(FetchStatus.ok,
        bytes: body != null
            ? Uint8List.fromList(utf8.encode(body))
            : Uint8List(1000),
        maxAge: const Duration(hours: 1),
        etag: '"e1"');
  }
}

const ValueKey<String> _layersKey = ValueKey<String>('map-layers-menu');

// flutter_map's layer widgets are generic (`PolygonLayer<Polygon>` once the
// points infer the type argument), so byType would need that exact argument.
// The predicates below match whichever argument was inferred.

Future<(MapsController, MeshcoreController)> _pump(
    WidgetTester t, _Net net) async {
  await t.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => t.binding.setSurfaceSize(null));
  // Real file I/O must run outside the fake-async zone, or it never
  // completes and the test hangs.
  late final Directory dir;
  late final MapsController maps;
  await t.runAsync(() async {
    dir = await Directory.systemTemp.createTemp('maplayers');
    maps = MapsController(
      rootDir: () async => dir,
      fetcher: net.call,
      prefsKey: 'maps.layers.test.v1',
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
        Provider<PlaceReportBudget>(create: (_) => PlaceReportBudget(clock: DateTime.now)),
      ],
      child: const Scaffold(body: MapScreen()),
    ),
  ));
  await t.pump();
  return (maps, mc);
}

/// Open the layers sheet through the control the map offers.
///
/// The control was a `PopupMenuButton` and this file used to read its
/// `itemBuilder`. It is a sheet of switches now, so the test reads the sheet:
/// the same rows a thumb sees, and the same control Settings manages a layer
/// with.
Future<void> _openLayers(WidgetTester t) async {
  final IconButton button =
      t.widget<IconButton>(find.byKey(_layersKey));
  button.onPressed!();
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _drain(
    WidgetTester t, MeshcoreController mc, MapsController m) async {
  mc.dispose();
  m.dispose();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // The street map subscribes to the compass; without a handler the
    // missing plugin throws into the test zone and fails the test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('hemanthraj/flutter_compass'),
            (MethodCall call) async => null);
  });

  testWidgets('the map has no basemap off switch any more',
      (WidgetTester t) async {
    final (MapsController m, MeshcoreController mc) = await _pump(t, _Net());
    expect(find.byTooltip('Hide map tiles'), findsNothing);
    expect(find.byTooltip('Show map tiles'), findsNothing);
    // The cell that used to remove the basemap is the event-maps control.
    expect(find.byKey(_layersKey), findsOneWidget);
    await _drain(t, mc, m);
  });

  testWidgets('a layer draws a point, a line and a polygon, and hiding it '
      'removes all three', (WidgetTester t) async {
    final _Net net = _Net();
    const String url = 'https://example.org/brc/streets.geojson';
    net.bodies[url] = _geo;
    final (MapsController m, MeshcoreController mc) = await _pump(t, net);
    late final EventLayer layer;
    await t.runAsync(() async {
      await m.addLayer(name: 'BRC', url: url);
      layer = m.layers.single;
      expect(await m.shapesFor(layer), isNotNull);
    });
    expect(m.layers, hasLength(1));

    await t.pump();
    await t.pump();
    // The street map keeps its own marker layer for peers, and markers
    // outside the viewport are not built, so the event point is identified
    // by the 24 dp hit box the overlay gives it. The label rides inside it
    // as a Tooltip.
    bool hasEventMarker() => t
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .any((MarkerLayer l) => l.markers.any((Marker m) => m.width == 24));
    expect(hasEventMarker(), isTrue);
    expect(find.byWidgetPredicate((Widget w) => w is PolygonLayer), findsWidgets);
    expect(find.byWidgetPredicate((Widget w) => w is PolylineLayer), findsWidgets);

    // The sheet lists it, switched on.
    await _openLayers(t);
    final SwitchListTile row =
        t.widget<SwitchListTile>(find.byKey(ValueKey<String>('map-layer-${layer.id}')));
    expect(row.value, isTrue);

    // Toggle it off through the control the map actually offers.
    row.onChanged!(false);
    await t.pump();
    expect(layer.visible, isFalse);
    expect(hasEventMarker(), isFalse);
    expect(find.byWidgetPredicate((Widget w) => w is PolygonLayer), findsNothing);
    expect(find.byWidgetPredicate((Widget w) => w is PolylineLayer), findsNothing);
    expect(find.byType(FlutterMap), findsOneWidget,
        reason: 'the basemap stays');
    await _drain(t, mc, m);
  });

  testWidgets('each layer gets its own colour', (WidgetTester t) async {
    final _Net net = _Net()
      ..bodies['https://example.org/a.geojson'] = _geo
      ..bodies['https://example.org/b.geojson'] = _geo;
    final (MapsController m, MeshcoreController mc) = await _pump(t, net);
    await t.runAsync(() async {
      await m.addLayer(name: 'A', url: 'https://example.org/a.geojson');
      await m.addLayer(name: 'B', url: 'https://example.org/b.geojson');
      for (final EventLayer l in m.layers) {
        await m.shapesFor(l);
      }
    });
    expect(m.layers, hasLength(2));
    await t.pump();
    await t.pump();

    final List<PolygonLayer> polys = t
        .widgetList<PolygonLayer>(
            find.byWidgetPredicate((Widget w) => w is PolygonLayer))
        .toList();
    expect(polys, hasLength(2), reason: 'one polygon layer per event layer');
    expect(polys[0].polygons.single.color, isNot(polys[1].polygons.single.color),
        reason: 'two layers must be distinguishable; every layer used to '
            'be the same tertiary colour');
    await _drain(t, mc, m);
  });

  testWidgets('with no layers the sheet says so and points at Settings',
      (WidgetTester t) async {
    final (MapsController m, MeshcoreController mc) = await _pump(t, _Net());
    await _openLayers(t);
    expect(find.text('No event maps added'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('map-layers-manage')),
        findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    await _drain(t, mc, m);
  });

  testWidgets('the map offers a labelled way to report a place',
      (WidgetTester t) async {
    final (MapsController m, MeshcoreController mc) = await _pump(t, _Net());
    // A long-press was the only way in, and the empty state had to teach it in
    // a sentence (UX audit C7). The control is labelled, so the gesture is one
    // option rather than the secret.
    expect(find.text('Tag a place'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey<String>('map-report-place')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('place-label')), findsOneWidget);
    await _drain(t, mc, m);
  });
}
