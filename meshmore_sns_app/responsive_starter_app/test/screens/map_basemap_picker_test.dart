// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/map_source.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/maps/vector_basemap.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/map_screen.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// R84 - the basemap picker on a vector skin.
///
/// Before this the picker was a dead control in Studio: it changed the
/// selected raster source and the vector layer ignored it, so choosing
/// USGS Imagery changed nothing at all. Now the picker offers the vector
/// basemap plus the raster sources, and picking a raster one draws it.
///
/// A MapsController with a fetcher that never touches the network: the
/// raster layer must go through the store, and flutter_test's stub client
/// would otherwise throw 400s into the test.
Future<void> _pump(WidgetTester t, MmThemePreset preset) async {
  await t.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));

  final MeshcoreController mc = MeshcoreController(
    transportFactory: () async => FakeMeshcoreTransport(connected: true),
  );
  final ThemeController theme = ThemeController();
  theme.setPreset(preset);
  // Real file I/O must run outside the fake-async zone, or it never
  // completes and the test hangs.
  late final MapsController maps;
  await t.runAsync(() async {
    final Directory dir = await Directory.systemTemp.createTemp('picker');
    maps = MapsController(
      rootDir: () async => dir,
      fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs}) async =>
          const FetchResult(FetchStatus.failed),
      pace: Duration.zero,
    );
    await maps.load();
  });
  addTearDown(() {
    mc.dispose();
    theme.dispose();
    maps.dispose();
  });

  await t.pumpWidget(
    MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<MapsController>.value(value: maps),
        ChangeNotifierProvider<PlaceStore>.value(value: PlaceStore()),
        Provider<PlaceReportBudget>(create: (_) => PlaceReportBudget(clock: DateTime.now)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: MapScreen()),
      ),
    ),
  );
  await t.pump();
}

/// Open the picker sheet through the control the map actually offers.
///
/// The control was a `PopupMenuButton` and this file used to read its
/// `itemBuilder`. It is the app's one pick-one-of-N sheet now, so a test drives
/// the sheet: the same path a thumb takes, and the same rows a reader sees.
Future<void> _open(WidgetTester t) async {
  final IconButton button = t.widget<IconButton>(
      find.byKey(const ValueKey<String>('map-basemap-picker')));
  button.onPressed!();
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

/// The names the picker offers, in order, read off the open sheet.
Future<List<String>> _names(WidgetTester t) async {
  await _open(t);
  final List<String> out = <String>[];
  for (final Text w in t.widgetList<Text>(find.byType(Text))) {
    final String? data = w.data;
    if (data == null) continue;
    final String first = data.split('\n').first;
    if (kBuiltInSources.any((MapSource s) => s.name == first)) out.add(first);
  }
  return out;
}

/// Let the map's debounced warm-up timer fire and the tree go away, or the
/// binding reports a pending timer.
Future<void> _settle(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

/// Choose a source by its name, through the sheet's own row.
Future<void> _select(WidgetTester t, MapSource source) async {
  await _open(t);
  await t.tap(find.textContaining(source.name).last);
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('the vector basemap is drawn and offered on every skin',
      (WidgetTester t) async {
    await _pump(t, MmThemePreset.studio);
    expect(find.byType(VectorBasemapLayer), findsOneWidget);
    // vector_map_tiles builds its own TileLayer internally, so the signal
    // for "raster is drawn" is the credit line, not the widget type.
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);

    // The vector basemap must be an offered choice, not an implicit one.
    final List<String> names = await _names(t);
    expect(names, contains(kOsmVector.name));
    expect(names.length, kBuiltInSources.length,
        reason: 'every built-in source, vector included');

    await _select(t, kUsgsImagery);
    expect(find.byType(VectorBasemapLayer), findsNothing,
        reason: 'a raster pick must actually draw raster');
    expect(find.text(kUsgsImagery.attribution), findsOneWidget,
        reason: 'the credit follows what is drawn');
    await _settle(t);
  });

  testWidgets('picking the vector entry returns to the vector basemap',
      (WidgetTester t) async {
    await _pump(t, MmThemePreset.studio);
    await _select(t, kUsgsTopo);
    expect(find.byType(VectorBasemapLayer), findsNothing);

    await _select(t, kOsmVector);
    expect(find.byType(VectorBasemapLayer), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    await _settle(t);
  });

  testWidgets('a non-Studio skin also draws vector and offers it',
      (WidgetTester t) async {
    // R90 — the style asset is a neutral dark palette, so the vector
    // basemap is not a Studio-only feature any more. Gating it made the
    // picker's first entry a dead control on six presets.
    await _pump(t, MmThemePreset.seele);
    expect(find.byType(VectorBasemapLayer), findsOneWidget);
    expect(await _names(t), contains(kOsmVector.name));
    await _settle(t);
  });

  test('the raster OSM source is not offered any more', () {
    // R90 — same data as the vector source, 4-10x the bytes, and no
    // seven-day cache floor. It stays in the code as the raster fallback.
    expect(kBuiltInSources, isNot(contains(kOsmStandard)));
    expect(kBuiltInSources.first, kOsmVector);
  });
}
