// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;

import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/maps/vector_basemap.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

/// The map is one map in eight skins, and a skin change has to reach it.
///
/// `vector_map_tiles` 8.0.0 repaints a layer only when the theme's *identity*
/// changes (`options.dart:52-61` `hasRenderDifferences`; `grid_layer.dart:312`
/// compares `oldWidget.options.theme.id`). The style asset declares no `id`, so
/// `ThemeReader` gave every skin the same one — `default` — and the renderer
/// saw eight identical themes. The palette was applied to the JSON correctly
/// and then never drawn: the map stayed in the previous skin's colours, and
/// only tiles created after the switch came out in the new one.
///
/// These tests pin the identity, the one-read cost, and the fact that a skin
/// change actually reaches the layer widget.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the drawn layer', () {
    late Directory dir;
    late MapsController maps;
    late ThemeController theme;
    late List<SingleChildWidget> providers;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      dir = await Directory.systemTemp.createTemp('vector_repaint');
      maps = MapsController(
        rootDir: () async => dir,
        fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs}) async =>
            const FetchResult(FetchStatus.failed),
        pace: Duration.zero,
      );
      await maps.load();
      theme = ThemeController();
      providers = <SingleChildWidget>[
        ChangeNotifierProvider<MapsController>.value(value: maps),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
      ];
    });

    tearDown(() async {
      maps.dispose();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    Future<void> pump(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: MultiProvider(
            providers: providers,
            child: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(39.7, -104.7),
                initialZoom: 12,
              ),
              children: const <Widget>[VectorBasemapLayer()],
            ),
          ),
        ),
      ));
      // The style is a future over a real asset read, so settle it by
      // pumping until the layer is on screen rather than by guessing frames.
      for (int i = 0;
          i < 20 && find.byType(vmt.VectorTileLayer).evaluate().isEmpty;
          i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
    }

    /// Pump until the layer is drawing [expected]'s theme. A style swap keeps
    /// the previous map on screen (that is the point of [_shown]), so waiting
    /// for "a layer exists" would return before the new theme arrived.
    Future<String?> drawnTheme(WidgetTester t, String expected) async {
      for (int i = 0; i < 25; i++) {
        await t.pump(const Duration(milliseconds: 20));
        final Finder f = find.byType(vmt.VectorTileLayer);
        if (f.evaluate().isEmpty) continue;
        final String id = t.widget<vmt.VectorTileLayer>(f).theme.id;
        if (id == expected) return id;
      }
      final Finder f = find.byType(vmt.VectorTileLayer);
      return f.evaluate().isEmpty
          ? null
          : t.widget<vmt.VectorTileLayer>(f).theme.id;
    }

    testWidgets('a skin change reaches the renderer as a new theme',
        (WidgetTester t) async {
      await pump(t);

      await theme.setPreset(MmThemePreset.studio);
      final String? studioId =
          await drawnTheme(t, vectorStyleIdFor(MmThemePreset.studio.name));
      expect(studioId, vectorStyleIdFor(MmThemePreset.studio.name));

      await theme.setPreset(MmThemePreset.air);
      final String? lightId =
          await drawnTheme(t, vectorStyleIdFor(MmThemePreset.air.name));
      expect(t.takeException(), isNull,
          reason: 'a light map at 320 dp and 200 % text');
      expect(lightId, vectorStyleIdFor(MmThemePreset.air.name),
          reason: 'the renderer repaints only when the id changes; the same '
              'id would have left the dark palette on a paper skin');
      expect(lightId, isNot(studioId));

      // `vector_map_tiles` schedules a 3 s cache sweep in `initState`
      // (`grid_layer.dart:80`); a test that ends before it fires fails on a
      // pending timer rather than on the thing it was testing.
      await t.pump(const Duration(seconds: 4));
    });
  });
}
