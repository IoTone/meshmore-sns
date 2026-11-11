// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/gen/app_localizations_en.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/maps/density_overlay.dart';
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
    expect(find.byType(PolygonLayer<DensityCell>), findsNothing);
    expect(find.byKey(const ValueKey<String>('map-density-toggle')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('map-coverage-toggle')),
        findsOneWidget);

    await t.tap(find.byKey(const ValueKey<String>('map-density-toggle')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    final PolygonLayer<DensityCell> layer =
        t.widget<PolygonLayer<DensityCell>>(
            find.byType(PolygonLayer<DensityCell>));
    expect(layer.polygons.length, greaterThanOrEqualTo(2),
        reason: 'a cluster and an outlier are two squares');
    // Every located node is in exactly one square, and the square carries the
    // keys a tap needs to name them.
    final Set<String> keys = <String>{
      for (final Polygon<DensityCell> p in layer.polygons)
        ...p.hitValue!.pubKeys,
    };
    expect(keys, hasLength(3));
    expect(layer.polygons.first.hitValue!.count,
        layer.polygons.first.hitValue!.pubKeys.length);

    // The count is drawn when the square is big enough to hold it: at the
    // test's zoom a 250 m square is tens of pixels.
    expect(find.byType(MarkerLayer), findsWidgets,
        reason: 'the count markers are in the tree');
    final Iterable<String> counts = t
        .widgetList<Text>(find.byType(Text))
        .map((Text x) => x.data ?? '')
        .where((String d) => d == '1' || d == '2');
    expect(counts, isNotEmpty, reason: 'a square shows its count');

    // And a tap on a square names the nodes in it. The screen point comes from
    // the camera rather than from a guess, so the tap lands inside the square
    // wherever the map happens to be centred.
    final MapCamera camera = MapCamera.of(
        t.element(find.byType(PolygonLayer<DensityCell>)));
    final DensityCell target = layer.polygons.first.hitValue!;
    // A corner of the square, not its centre: the centre is where the node is,
    // and its pin would take the tap. That is exactly why the tap is resolved
    // by point-in-square rather than by a polygon hit test.
    final Point<double> p = camera.latLngToScreenPoint(LatLng(
      target.bounds[0].latitude + (target.bounds[2].latitude - target.bounds[0].latitude) * 0.1,
      target.bounds[0].longitude + (target.bounds[2].longitude - target.bounds[0].longitude) * 0.1,
    ));
    await t.tapAt(Offset(p.x, p.y));
    await t.pumpAndSettle();
    expect(find.text(_en.mapDensityCellTitle(target.count)), findsOneWidget,
        reason: 'the sheet names the count the square carries');
    expect(find.text(_en.mapDensityCellArea), findsOneWidget);
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
    await t.tap(find.byKey(const ValueKey<String>('map-density-toggle')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    // A column of seven 48 dp controls is 336 dp; this proves it does not
    // overflow the shortest phone the product promises.
    Object? e;
    while ((e = t.takeException()) != null) {
      expect('$e', isNot(contains('overflowed')), reason: '$e');
    }
    expect(find.byTooltip(_en.mapDensityHide), findsOneWidget,
        reason: 'the label follows the state');
    await _drain(t, mc);
  });
}
