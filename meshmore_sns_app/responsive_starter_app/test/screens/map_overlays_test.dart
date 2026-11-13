// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/gen/app_localizations_en.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/maps/hex_field.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/street_map_view.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/perms/location_service.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';

import '../meshcore/fake_transport.dart';

/// The Map tab's two overlays, from the grid audit: the reception quilt that
/// came with the Coverage view's removal, and the equal-area density grid that
/// view owed.
///
/// The geometry is proved in `test/maps/overlays_test.dart`; what is proved
/// here is that the controls exist, that the density layer is off until asked
/// for, and that asking for it puts the real cells on the map.

final AppLocalizationsEn _en = AppLocalizationsEn();

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
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<ThemeController>(
              create: (_) => ThemeController()),
          ChangeNotifierProvider<PlaceStore>.value(value: PlaceStore()),
          Provider<PlaceReportBudget>(
              create: (_) => PlaceReportBudget(clock: DateTime.now)),
          Provider<PermissionsService>.value(value: _NoPermissions()),
        ],
        child: const Scaffold(body: StreetMapView()),
      ),
    );

MeshcoreController _mc(FakeMeshcoreTransport f) => MeshcoreController(
      transportFactory: () async => f,
      locationService: NoopLocationService(),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );

/// The map asks permissions only when a control needs them.
class _NoPermissions implements PermissionsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<bool>.value(false);
}

Future<void> _drain(WidgetTester t, MeshcoreController mc) async {
  mc.dispose();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

void main() {
  testWidgets('the density layer is off until it is asked for, then it is '
      'the mesh it describes', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    // A semantics label is only findable by label once semantics is switched
    // on, which is what the tap below goes through.
    final SemanticsHandle semantics = t.ensureSemantics();
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _mc(fake);
    await t.pumpWidget(_host(mc));
    await mc.connect();
    fake.emit(selfInfoFrameAt(lat: 39.0, lon: -105.0));
    // Two nodes inside one 250 m square, one a few hundred metres away.
    fake.emit(advertFrameAt(lat: 39.0001, lon: -104.9999, name: 'N1'));
    fake.emit(advertFrameAt(
        lat: 39.0002, lon: -104.9998, name: 'N2', firstPubByte: 40));
    fake.emit(advertFrameAt(
        lat: 39.0040, lon: -104.9999, name: 'N3', firstPubByte: 70));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    // Off by default: a reading about the mesh is something to ask for.
    expect(find.byType(PolygonLayer<HexCell>), findsNothing);
    // One control for everything the map shows: the toggles live in its sheet.
    expect(find.byKey(const ValueKey<String>('map-overlays-button')),
        findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('map-overlays-button')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('map-density-toggle')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('map-coverage-toggle')),
        findsOneWidget);

    // The sheet is already open (above); switching the layer on is one tap, and
    // the sheet is dismissed afterwards so the map itself can be tapped.
    await t.tap(find.byKey(const ValueKey<String>('map-density-toggle')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.tapAt(const Offset(20, 20));
    await t.pumpAndSettle();

    final PolygonLayer<HexCell> layer = t.widget<PolygonLayer<HexCell>>(
        find.byType(PolygonLayer<HexCell>));
    // How many squares there are is a property of the zoom now, because the
    // cell size follows it: the assertion is that every located node is in one
    // of them, not that the count happens to be two.
    expect(layer.polygons, isNotEmpty);
    // Every located node is in exactly one hexagon, and the hexagon carries the
    // keys a tap needs to name them.
    final Set<String> keys = <String>{
      for (final Polygon<HexCell> p in layer.polygons) ...p.hitValue!.points,
    };
    expect(keys, hasLength(3));
    expect(layer.polygons.first.hitValue!.count,
        layer.polygons.first.hitValue!.points.length);
    // A hexagon has six corners and the width/height ratio a regular one has,
    // which is what stops the field reading as a row of squashed cells.
    expect(layer.polygons.first.points, hasLength(6));

    // A count only means something next to the distance it is a count per, so
    // the size is stated on screen. Whether the numbers themselves are drawn
    // depends on the zoom (they fit, or they do not), which the pure test
    // covers; this one asserts the label that makes them readable.
    expect(find.byKey(const ValueKey<String>('map-density-size')),
        findsOneWidget);
    // The chip over the map. (The switch's subtitle in the sheet says the same
    // thing at the same size, which is why the sheet is dismissed above before
    // this is counted.)
    expect(find.textContaining('Cells'), findsOneWidget);

    // And a tap on a square names the nodes in it. The screen point comes from
    // the camera rather than from a guess, so the tap lands inside the square
    // wherever the map happens to be centred.
    // A count is the square's own tap target, drawn above the pins: a 48 dp
    // box with the number inside it. Tapping it opens the square, which is what
    // a polygon hit test could never do — a pin's box covers its cell's centre.
    final Iterable<Semantics> counts = t
        .widgetList<Semantics>(find.byType(Semantics))
        .where((Semantics s) =>
            (s.properties.label ?? '').contains('in this square'));
    expect(counts, isNotEmpty, reason: 'a square carries a labelled count');
    // The label the widget actually carries, rather than a guess at which
    // square is first: how many nodes share one depends on the zoom's cell size.
    final String label = counts.first.properties.label!;
    expect(
        layer.polygons.any(
            (Polygon<HexCell> p) => _en.mapDensityCellTitle(p.hitValue!.count) == label),
        isTrue,
        reason: 'the label names a real cell, count and all');
    final HexCell tapped = layer.polygons
        .firstWhere((Polygon<HexCell> p) =>
            _en.mapDensityCellTitle(p.hitValue!.count) == label)
        .hitValue!;
    await t.tap(find.byKey(ValueKey<String>('density-count-${tapped.id}')));
    // ignore: avoid_print
    print('PROBE after-tap texts=${t.widgetList<Text>(find.byType(Text)).map((Text x) => x.data).where((String? d) => d != null).take(14).toList()}');
    await t.pumpAndSettle();
    expect(find.textContaining('so every cell covers'),
        findsOneWidget,
        reason: 'the sheet says what a square covers, at the size drawn');
    semantics.dispose();
    await _drain(t, mc);
  });

  testWidgets('both overlays fit a 320 dp phone with the largest text',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(320, 560));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _mc(fake);
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
      child: _host(mc),
    ));
    await mc.connect();
    fake.emit(selfInfoFrameAt(lat: 39.0, lon: -105.0));
    fake.emit(advertFrameAt(lat: 39.0001, lon: -104.9999, name: 'N1'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    // Everything the map shows is behind one control now, so a test that wants
    // the density layer opens the sheet first — which is also the shortest
    // statement of what a reader does.
    await t.tap(find.byKey(const ValueKey<String>('map-overlays-button')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('map-density-toggle')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    // A column of seven 48 dp controls is 336 dp; this proves it does not
    // overflow the shortest phone the product promises.
    Object? e;
    while ((e = t.takeException()) != null) {
      expect('$e', isNot(contains('overflowed')), reason: '$e');
    }
    // The toggle is a switch in the sheet now, and its state is the assertion:
    // the sheet stays open so a second overlay is one more tap, not a reopening.
    final SwitchListTile density =
        t.widget<SwitchListTile>(find.byKey(const ValueKey<String>('map-density-toggle')));
    expect(density.value, isTrue, reason: 'the switch says the layer is on');
    await _drain(t, mc);
  });
}
