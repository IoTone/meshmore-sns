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

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/maps/hex_field.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/map_overlay_prefs.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/perms/location_service.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/map_screen.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// What the map draws is a preference, not a session.
///
/// The basemap survived a relaunch and so did the camera, but everything the
/// overlays sheet owned did not: a reader who turned the hexagon field on to
/// read the mesh's density found it off again next launch, every launch. The
/// store is proved on its own in `test/maps/map_overlay_prefs_test.dart`; this
/// file proves the screen actually reads it and actually writes it.
class _Net {
  Future<FetchResult> call(Uri url,
          {String? etag, int? ifModifiedSinceMs, int? maxBytes}) async =>
      FetchResult(FetchStatus.ok,
          bytes: Uint8List(1000), maxAge: const Duration(hours: 1));
}

class _NoPermissions implements PermissionsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<bool>.value(false);
}

/// One map, built the way the app builds it, on a transport that is connected
/// with three located nodes so the density field has something to count.
Future<MeshcoreController> _pump(WidgetTester t, FakeMeshcoreTransport fake,
    {Size size = const Size(420, 900)}) async {
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  late final Directory dir;
  late final MapsController maps;
  await t.runAsync(() async {
    dir = await Directory.systemTemp.createTemp('mapoverlays');
    maps = MapsController(
      rootDir: () async => dir,
      fetcher: _Net().call,
      prefsKey: 'maps.overlays.test.v1',
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
    transportFactory: () async => fake,
    locationService: NoopLocationService(),
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
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
        ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
        ChangeNotifierProvider<PlaceStore>.value(value: PlaceStore()),
        Provider<PlaceReportBudget>(
            create: (_) => PlaceReportBudget(clock: DateTime.now)),
        Provider<PermissionsService>.value(value: _NoPermissions()),
      ],
      child: const Scaffold(body: MapScreen()),
    ),
  ));
  await mc.connect();
  fake.emit(selfInfoFrameAt(lat: 39.0, lon: -105.0));
  fake.emit(advertFrameAt(lat: 39.0001, lon: -104.9999, name: 'N1'));
  fake.emit(advertFrameAt(
      lat: 39.0002, lon: -104.9998, name: 'N2', firstPubByte: 40));
  fake.emit(advertFrameAt(
      lat: 39.0040, lon: -104.9999, name: 'N3', firstPubByte: 70));
  // Bounded pumps rather than a settle: the map runs its own timers (a
  // reconnect ladder, the view-debounce), and a settle that keeps finding one
  // more frame never returns. Six frames is enough for the stored preference to
  // arrive and for the layer to be built from it.
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
  return mc;
}

Future<void> _openSheet(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey<String>('map-overlays-button')));
  await t.pumpAndSettle();
}

Future<void> _drain(WidgetTester t, MeshcoreController mc) async {
  mc.dispose();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('hemanthmeshmore/compass'),
            (MethodCall call) async => null);
  });

  testWidgets('a stored choice is drawn on the first frame', (WidgetTester t) async {
    // Written by the previous launch, read before the map has anything to say.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mm.mapOverlays.v1': jsonEncode(<String, Object?>{'density': true}),
    });
    final MeshcoreController mc =
        await _pump(t, FakeMeshcoreTransport(connected: true));
    // No tap, no sheet: the reader asked once, last week.
    expect(find.byType(PolygonLayer<HexCell>), findsOneWidget,
        reason: 'the field the reader turned on was off again');
    await _drain(t, mc);
  });

  testWidgets('turning it on stores it, and off stores that too',
      (WidgetTester t) async {
    final MeshcoreController mc =
        await _pump(t, FakeMeshcoreTransport(connected: true));
    expect(await MapOverlayPrefsStore.load(), MapOverlayPrefs.defaults);

    await _openSheet(t);
    await t.tap(find.byKey(const ValueKey<String>('map-density-toggle')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect((await MapOverlayPrefsStore.load()).density, isTrue,
        reason: 'the switch moved but nothing was written');

    await t.tap(find.byKey(const ValueKey<String>('map-density-toggle')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect((await MapOverlayPrefsStore.load()).density, isFalse,
        reason: 'turning it off is a decision as well');
    await _drain(t, mc);
  });

  testWidgets('a corrupt record is defaults, not a broken map',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mm.mapOverlays.v1': '{not json',
    });
    final MeshcoreController mc =
        await _pump(t, FakeMeshcoreTransport(connected: true));
    expect(find.byType(PolygonLayer<HexCell>), findsNothing);
    expect(t.takeException(), isNull);
    await _drain(t, mc);
  });
}
