// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/perms/location_service.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/screens/map_screen.dart';
import 'package:meshmore_sns_app/maps/map_centre.dart';
import 'package:meshmore_sns_app/screens/street_map_view.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

/// R69 — the Map tab is browsable with no position fix; the grid's
/// street-map mode keeps its empty state.
/// Records whether the app asked the OS settings page to open.
class _RecordingPermissions implements PermissionsService {
  int settingsOpened = 0;
  @override
  Future<void> openAppSettingsPage() async => settingsOpened++;
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<MeshcoreController> _pump(WidgetTester t, Widget body,
    {Locale locale = const Locale('en'),
    NoopLocationService? location,
    _RecordingPermissions? permissions}) async {
  await t.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final MeshcoreController ctrl = MeshcoreController(
    transportFactory: () async => FakeMeshcoreTransport(connected: true),
    locationService: location ?? NoopLocationService(),
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
      home: MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<MeshcoreController>.value(value: ctrl),
          ChangeNotifierProvider<PlaceStore>.value(value: PlaceStore()),
          Provider<PlaceReportBudget>(create: (_) => PlaceReportBudget(clock: DateTime.now)),
          Provider<PermissionsService>.value(
              value: permissions ?? _RecordingPermissions()),
        ],
        child: Scaffold(body: body),
      ),
    ),
  );
  await t.pump();
  return ctrl;
}

void main() {
  const String en = 'Your position is not known yet.';
  const String ja = '現在地がまだ分かりません。';

  testWidgets('Map tab with no fix renders a map and the banner',
      (WidgetTester t) async {
    final MeshcoreController c = await _pump(t, const MapScreen());
    expect(find.byType(FlutterMap), findsOneWidget,
        reason: 'a map, not just text');
    expect(find.text(en), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('map-no-position-banner')),
        findsOneWidget);
    final FlutterMap fm = t.widget(find.byType(FlutterMap));
    expect(fm.options.initialZoom, MapCentre.worldZoom);
    expect(fm.options.initialCenter, MapCentre.worldCentre);
    expect(find.text('Find me'), findsOneWidget,
        reason: 'the banner carries the action that helps');
    // Offline maps is reachable with no fix, because a map with no position is
    // exactly when a reader goes looking for a region to download. It is a row
    // in the overlays sheet now, one tap from the same column.
    await t.tap(find.byKey(const ValueKey<String>('map-overlays-button')));
    await t.pumpAndSettle();
    expect(find.text('Offline maps'), findsOneWidget);
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('the banner is Japanese in the ja locale',
      (WidgetTester t) async {
    final MeshcoreController c =
        await _pump(t, const MapScreen(), locale: const Locale('ja'));
    expect(find.text(ja), findsOneWidget);
    expect(find.text(en), findsNothing);
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('a bare StreetMapView draws the world view, like the Map tab',
      (WidgetTester t) async {
    // There is no "needs your position" screen any more: the world view is a
    // real answer to "where am I", and the only caller that wanted a refusal
    // (the grid's street-map mode) has left the picker.
    final MeshcoreController c = await _pump(t, const StreetMapView());
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.textContaining('This view needs your position'), findsNothing);
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
        find.byKey(const ValueKey<String>('map-no-position-banner')));
    expect(t.getRect(credit).bottom, lessThanOrEqualTo(banner.top),
        reason: 'attribution sits above the banner, not under it');
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('R70: the controls are 48dp and there is no edge band any more',
      (WidgetTester t) async {
    final MeshcoreController c = await _pump(t, const MapScreen());
    final Rect col =
        t.getRect(find.byKey(const ValueKey<String>('map-controls')));
    expect(col.width, greaterThanOrEqualTo(48));
    expect(col.height, greaterThanOrEqualTo(5 * 48),
        reason: 'five controls, 48dp each');
    // The edge-swipe bands are gone by the owner's ruling: a drag near an edge
    // is the map's, and paging happens on the strip at the top.
    expect(find.byKey(const ValueKey<String>('mm-edge-right')), findsNothing);
    expect(find.byKey(const ValueKey<String>('mm-edge-left')), findsNothing);
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('a late position does not move a map the user has panned',
      (WidgetTester t) async {
    final NoopLocationService location = NoopLocationService();
    final MeshcoreController c =
        await _pump(t, const MapScreen(), location: location);
    // Drag the map, which is the user's own move.
    await t.drag(find.byType(FlutterMap), const Offset(-120, 0));
    await t.pump(const Duration(milliseconds: 50));

    // Now a phone position arrives and the widget rebuilds.
    location.next =
        PhoneFix(latitude: 38.9, longitude: -104.7, altitudeMeters: null);
    await c.requestPhoneLocationFix();
    await t.pump(const Duration(milliseconds: 50));

    final FlutterMap after = t.widget(find.byType(FlutterMap));
    expect(after.options.initialCenter.latitude, isNot(closeTo(38.9, 1e-6)),
        reason: 'the camera must not jump under the finger');
    expect(after.options.initialCenter.longitude, isNot(closeTo(-104.7, 1e-6)),
        reason: 'the camera must not jump under the finger');
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('the locate control asks for a position and names the failure',
      (WidgetTester t) async {
    final NoopLocationService location =
        NoopLocationService(failure: LocationFailure.permissionDenied);
    final _RecordingPermissions perms = _RecordingPermissions();
    final MeshcoreController c = await _pump(t, const MapScreen(),
        location: location, permissions: perms);
    await t.tap(find.byTooltip('Re-centre on me'));
    await t.pump(const Duration(milliseconds: 50));
    expect(location.callCount, greaterThan(0),
        reason: 'the control asks instead of being dead');
    expect(find.text('Location is off for this app.'), findsOneWidget,
        reason: 'the permission failure is named, not blamed on the sky');
    expect(find.text('Allow location'), findsOneWidget);
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('a blocked permission offers the OS settings page',
      (WidgetTester t) async {
    final NoopLocationService location =
        NoopLocationService(failure: LocationFailure.permissionDeniedForever);
    final _RecordingPermissions perms = _RecordingPermissions();
    final MeshcoreController c = await _pump(t, const MapScreen(),
        location: location, permissions: perms);
    await t.tap(find.byTooltip('Re-centre on me'));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Location is blocked for this app.'), findsOneWidget);
    await t.tap(find.text('Open settings'));
    await t.pump(const Duration(milliseconds: 50));
    expect(perms.settingsOpened, 1);
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('the app opens on the view the user left',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flutter.mm.mapview.v1': '{"lat":35.6,"lon":139.7,"z":11.0}',
    });
    final MeshcoreController c = await _pump(t, const MapScreen());
    await t.pump(const Duration(milliseconds: 50));
    final FlutterMap fm = t.widget(find.byType(FlutterMap));
    expect(fm.options.initialCenter.latitude, closeTo(35.6, 1e-6));
    expect(fm.options.initialCenter.longitude, closeTo(139.7, 1e-6));
    expect(fm.options.initialZoom, 11.0);
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
