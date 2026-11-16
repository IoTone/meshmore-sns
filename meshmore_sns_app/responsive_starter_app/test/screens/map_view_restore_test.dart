// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/maps/map_view_state.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/perms/location_service.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/map_screen.dart';

import '../meshcore/fake_transport.dart';

/// A tab switch comes back to the map you were looking at.
///
/// The camera was already saved to disk and restored on mount, so the defect was
/// never a missing store: it was the resolve ladder, which put the phone fix
/// above the saved view. On a phone with a fix, every remount re-centred on the
/// reader and threw away where they had panned. These cases mount the real Map
/// tab twice and read the camera the map was built with.
class _NoopPermissions implements PermissionsService {
  @override
  Future<void> openAppSettingsPage() async {}
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DateTime now = DateTime(2026, 11, 13, 12);

  Future<MeshcoreController> pump(
    WidgetTester t,
    MapViewState view,
  ) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      locationService: NoopLocationService(),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(
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
            ChangeNotifierProvider<MeshcoreController>.value(value: ctrl),
            ChangeNotifierProvider<MapViewState>.value(value: view),
            ChangeNotifierProvider<PlaceStore>.value(value: PlaceStore()),
            Provider<PlaceReportBudget>(
                create: (_) => PlaceReportBudget(clock: DateTime.now)),
            Provider<PermissionsService>.value(value: _NoopPermissions()),
          ],
          child: const Scaffold(body: MapScreen()),
        ),
      ),
    );
    await t.pump();
    return ctrl;
  }

  FlutterMap map(WidgetTester t) => t.widget<FlutterMap>(find.byType(FlutterMap));

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    now = DateTime(2026, 11, 13, 12);
  });

  testWidgets('a fresh view is where the map opens', (WidgetTester t) async {
    final MapViewState view =
        MapViewState(clock: () => now, observeLifecycle: false);
    view.remember(centre: const LatLng(40.5, -105.5), zoom: 15);
    final MeshcoreController c = await pump(t, view);

    expect(map(t).options.initialCenter, const LatLng(40.5, -105.5));
    expect(map(t).options.initialZoom, 15);
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('a stale view falls back to the ladder', (WidgetTester t) async {
    final MapViewState view =
        MapViewState(clock: () => now, observeLifecycle: false);
    view.remember(centre: const LatLng(40.5, -105.5), zoom: 15);
    // A minute and a second later the reader has walked away, so the view is no
    // longer authoritative and the ladder decides.
    now = now.add(MapViewState.freshFor + const Duration(seconds: 1));
    final MeshcoreController c = await pump(t, view);

    expect(map(t).options.initialCenter, isNot(const LatLng(40.5, -105.5)));
    expect(map(t).options.initialZoom, isNot(15));
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('a discarded view is not restored', (WidgetTester t) async {
    final MapViewState view =
        MapViewState(clock: () => now, observeLifecycle: false);
    view.remember(centre: const LatLng(40.5, -105.5), zoom: 15);
    view.didChangeAppLifecycleState(AppLifecycleState.paused);
    final MeshcoreController c = await pump(t, view);

    expect(map(t).options.initialCenter, isNot(const LatLng(40.5, -105.5)));
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
