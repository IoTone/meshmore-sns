// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/map_source.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/maps/vector_basemap.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/map_screen.dart';
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
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<MapsController>.value(value: maps),
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

List<PopupMenuEntry<String>> _items(WidgetTester t) {
  final PopupMenuButton<String> picker =
      t.widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>));
  return picker.itemBuilder(
      t.element(find.byType(PopupMenuButton<String>)));
}

/// Let the map's debounced warm-up timer fire and the tree go away, or the
/// binding reports a pending timer.
Future<void> _settle(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

void _select(WidgetTester t, String id) {
  final PopupMenuButton<String> picker =
      t.widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>));
  picker.onSelected!(id);
}

void main() {
  testWidgets('Studio draws the vector basemap and offers it in the picker',
      (WidgetTester t) async {
    await _pump(t, MmThemePreset.studio);
    expect(find.byType(VectorBasemapLayer), findsOneWidget);
    // vector_map_tiles builds its own TileLayer internally, so the signal
    // for "raster is drawn" is the credit line, not the widget type.
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);

    // The vector basemap must be an offered choice, not an implicit one.
    final List<PopupMenuEntry<String>> items = _items(t);
    expect(items.map((PopupMenuEntry<String> e) => (e as PopupMenuItem<String>).value),
        contains(kOsmVector.id));
    expect(items.length, kBuiltInSources.length + 1,
        reason: 'the vector entry plus every raster source');

    // Drive the picker's own callback: the menu's pop animation and hit
    // testing are Flutter's, the choice is ours.
    _select(t, kUsgsImagery.id);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(VectorBasemapLayer), findsNothing,
        reason: 'a raster pick must actually draw raster');
    expect(find.text(kUsgsImagery.attribution), findsOneWidget,
        reason: 'the credit follows what is drawn');
    await _settle(t);
  });

  testWidgets('picking the vector entry returns to the Studio basemap',
      (WidgetTester t) async {
    await _pump(t, MmThemePreset.studio);
    _select(t, kUsgsTopo.id);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(VectorBasemapLayer), findsNothing);

    _select(t, kOsmVector.id);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(VectorBasemapLayer), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    await _settle(t);
  });

  testWidgets('a raster skin has no vector entry and draws raster',
      (WidgetTester t) async {
    await _pump(t, MmThemePreset.seele);
    expect(find.byType(VectorBasemapLayer), findsNothing);
    expect(find.byType(TileLayer), findsWidgets,
        reason: 'a raster skin draws raster');
    expect(
        _items(t).map((PopupMenuEntry<String> e) => (e as PopupMenuItem<String>).value),
        isNot(contains(kOsmVector.id)),
        reason: 'the vector basemap belongs to the Studio skin');
    await _settle(t);
  });
}
