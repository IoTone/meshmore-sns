// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max, min, pow;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;

import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/map_source.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/maps/vector_basemap.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

class _FakeFetch {
  _FakeFetch(this.bytes);
  final Uint8List bytes;
  bool offline = false;
  int calls = 0;

  Future<FetchResult> call(Uri url, {String? etag, int? ifModifiedSinceMs}) async {
    calls++;
    if (offline) return const FetchResult(FetchStatus.failed);
    return FetchResult(FetchStatus.ok, bytes: bytes);
  }
}

/// The raster picker; the vector source is implicit on Studio.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R80 vector basemap style', () {
    test('the bundled asset is a vector style for Shortbread', () async {
      final String json = await rootBundle.loadString(kVectorBasemapAsset);
      final Map<String, dynamic> style = jsonDecode(json) as Map<String, dynamic>;
      final Map<String, dynamic> sources =
          style['sources'] as Map<String, dynamic>;
      expect(sources.keys, <String>[kVectorBasemapSourceId],
          reason: 'one vector source, the OSM vector service');
      expect((sources[kVectorBasemapSourceId] as Map)['type'], 'vector');
      expect((sources[kVectorBasemapSourceId] as Map)['maxzoom'], 14,
          reason: 'Shortbread tops out at z14; deeper zooms overzoom it');
      expect(style.containsKey('glyphs'), isFalse,
          reason: 'labels render through Flutter text, not a glyph server');
      expect(style.containsKey('sprite'), isFalse,
          reason: 'no remote sprite atlas is fetched');
      final List<dynamic> layers = style['layers'] as List<dynamic>;
      expect(layers.length, greaterThan(20),
          reason: 'a lean Shortbread style, not a 47-layer port');
      expect((layers.first as Map)['type'], 'background');
      // Every source-layer must be one the schema actually publishes.
      const Set<String> shortbread = <String>{
        'ocean', 'water_polygons', 'water_polygons_labels', 'water_lines',
        'water_lines_labels', 'boundaries', 'place_labels', 'land', 'sites',
        'buildings', 'streets', 'street_polygons', 'street_labels',
      };
      for (final dynamic l in layers) {
        final String? sl = (l as Map<String, dynamic>)['source-layer'] as String?;
        if (sl != null) {
          expect(shortbread, contains(sl), reason: '${l['id']} uses $sl');
        }
      }
    });

    test('it parses into a renderable theme', () async {
      final VectorBasemapStyle s = await loadVectorBasemapStyle();
      expect(s.theme.tileSources, contains(kVectorBasemapSourceId));
      expect(s.sprites, isNull);
    });
  });

  group('R80 vector tile provider', () {
    late Directory dir;
    late _FakeFetch net;
    late MapsController maps;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final Directory root = await Directory.systemTemp.createTemp('vec_tiles');
      dir = root;
      net = _FakeFetch(Uint8List.fromList(<int>[0x1a, 0x02, 0x03, 0x04]));
      maps = MapsController(
        rootDir: () async => root,
        fetcher: net.call,
        pace: Duration.zero,
      );
      await maps.load();
    });

    tearDown(() async {
      maps.dispose();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('serves bytes from the same store the raster layer used', () async {
      final MmVectorTileProvider provider =
          MmVectorTileProvider(maps, kOsmVector);
      final Uint8List first =
          await provider.provide(vmt.TileIdentity(3, 2, 1));
      expect(first, <int>[0x1a, 0x02, 0x03, 0x04]);
      expect(provider.type, vmt.TileProviderType.vector);

      // Second read comes off disk: the vector path must not refetch.
      await provider.provide(vmt.TileIdentity(3, 2, 1));
      expect(net.calls, 1, reason: 'disk-first, exactly like raster tiles');
    });

    test('an unavailable tile fails as a provider error, not a crash',
        () async {
      net.offline = true;
      final MmVectorTileProvider provider =
          MmVectorTileProvider(maps, kOsmVector);
      await expectLater(
        provider.provide(vmt.TileIdentity(4, 1, 1)),
        throwsA(isA<vmt.ProviderException>()
            .having((vmt.ProviderException e) => e.retryable,
                'retryable', vmt.Retryable.none)),
      );
    });

    test('R81 a server "no such tile" becomes a 404 the renderer draws empty',
        () async {
      final MapsController m = MapsController(
        rootDir: () async => dir,
        fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs}) async =>
            const FetchResult(FetchStatus.missing),
        pace: Duration.zero,
      );
      await m.load();
      await expectLater(
        MmVectorTileProvider(m, kOsmVector)
            .provide(vmt.TileIdentity(2, 0, 0)),
        throwsA(isA<vmt.ProviderException>()
            .having((vmt.ProviderException e) => e.statusCode, 'status', 404)),
      );
      m.dispose();
    });

    test('R81 even an unexpected error stays a ProviderException', () async {
      final MapsController m = MapsController(
        rootDir: () async => dir,
        fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs}) async =>
            throw StateError('boom'),
        pace: Duration.zero,
      );
      await m.load();
      await expectLater(
        MmVectorTileProvider(m, kOsmVector)
            .provide(vmt.TileIdentity(2, 0, 0)),
        throwsA(isA<vmt.ProviderException>()),
        reason: 'the renderer pool must never see a raw exception',
      );
      m.dispose();
    });

    test('zoom bounds follow the source', () {
      final MmVectorTileProvider provider =
          MmVectorTileProvider(maps, kOsmVector);
      expect(provider.minimumZoom, 0);
      expect(provider.maximumZoom, kOsmVector.maxNativeZoom);
    });
  });

  group('R81 the Studio style is legible, with colour in the content', () {
    late Map<String, Map<String, dynamic>> byId;
    setUpAll(() async {
      final Map<String, dynamic> style = jsonDecode(
              await rootBundle.loadString(kVectorBasemapAsset))
          as Map<String, dynamic>;
      byId = <String, Map<String, dynamic>>{
        for (final Map<String, dynamic> l
            in (style['layers'] as List<dynamic>).cast<Map<String, dynamic>>())
          l['id'] as String: l
      };
    });

    List<int> rgb(String hex) => <int>[
          int.parse(hex.substring(1, 3), radix: 16),
          int.parse(hex.substring(3, 5), radix: 16),
          int.parse(hex.substring(5, 7), radix: 16),
        ];
    double lum(String hex) {
      double c(int v) {
        final double x = v / 255;
        return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4).toDouble();
      }

      final List<int> v = rgb(hex);
      return 0.2126 * c(v[0]) + 0.7152 * c(v[1]) + 0.0722 * c(v[2]);
    }

    double contrast(String a, String b) {
      final double la = lum(a), lb = lum(b);
      return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
    }

    String paint(String id, String key) =>
        (byId[id]!['paint'] as Map<String, dynamic>)[key] as String;

    const String land = '#141414';

    test('every label is WCAG AA (4.5:1) against the land it sits on', () {
      int labels = 0;
      for (final Map<String, dynamic> l in byId.values) {
        final Map<String, dynamic>? p = l['paint'] as Map<String, dynamic>?;
        final Object? c = p?['text-color'];
        if (l['type'] == 'symbol' && c is String) {
          labels++;
          expect(contrast(c, land), greaterThanOrEqualTo(4.5),
              reason: '${l['id']} $c');
          expect((p!['text-halo-width'] as num), greaterThanOrEqualTo(1.2),
              reason: '${l['id']} needs a real halo');
        }
      }
      expect(labels, 6, reason: '3 place ranks, 1 road name, 2 water names');
    });

    test('roads separate from the land, and rank by importance', () {
      final double minor = contrast(paint('street_minor', 'line-color'), land);
      final double secondary =
          contrast(paint('street_secondary', 'line-color'), land);
      final double motorway =
          contrast(paint('street_motorway', 'line-color'), land);
      expect(minor, greaterThanOrEqualTo(1.8));
      expect(secondary, greaterThan(minor));
      expect(motorway, greaterThanOrEqualTo(3.0));
      expect(motorway, greaterThan(secondary));
    });

    test('water is blue, parks are green, both visible against land', () {
      final List<int> w = rgb(paint('water', 'fill-color'));
      final List<int> g = rgb(paint('land_grass', 'fill-color'));
      expect(w[2], greaterThan(w[0] + 12), reason: 'blue');
      expect(g[1], greaterThan(g[0] + 8), reason: 'green');
      expect(contrast(paint('water', 'fill-color'), land), greaterThan(1.1));
      expect(contrast(paint('land_grass', 'fill-color'), land),
          greaterThan(1.1));
      // Water is distinguishable from a park, not just from land.
      expect(paint('water', 'fill-color'),
          isNot(paint('land_grass', 'fill-color')));
    });

    test('the style stays lean: 28 layers, one source, under 20 KB', () async {
      expect(byId, hasLength(28));
      expect((await rootBundle.loadString(kVectorBasemapAsset)).length,
          lessThan(20 * 1000));
    });
  });

  test('R81 the underlay colour is the style\'s own background', () async {
    final Map<String, dynamic> style = jsonDecode(
        await rootBundle.loadString(kVectorBasemapAsset)) as Map<String, dynamic>;
    final Map<String, dynamic> bg = (style['layers'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((Map<String, dynamic> l) => l['type'] == 'background');
    final String hex =
        (bg['paint'] as Map<String, dynamic>)['background-color'] as String;
    expect(
        Color(0xFF000000 | int.parse(hex.substring(1), radix: 16)),
        kVectorBasemapBackground,
        reason: 'unloaded tiles must look like the map, not like a fault');
  });

  test('R90 the vector basemap is no longer Studio-only', () {
    // R80 gated the vector renderer on the skin's shape. R90 lets every
    // preset draw it (the style asset is a neutral dark palette), so the
    // flag no longer decides anything; the map view ignores it.
    for (final MmThemePreset p in MmThemePreset.values) {
      expect(mmSkinFor(p).shape.vectorBasemap, p == MmThemePreset.studio,
          reason: 'the flag still records which skin first adopted it: $p');
    }
  });

  test('R82 the vector source is OSM itself, credited, and view-only', () {
    expect(kOsmVector.urlTemplate, contains('vector.openstreetmap.org'));
    expect(kOsmVector.attribution, contains('OpenStreetMap'));
    expect(kOsmVector.allowsPacks, isFalse,
        reason: 'the OSM vector policy forbids bulk download; regions are '
            'PMTiles archives (R81), never a crawl of this service');
    // R90 — it is now the first entry in the picker, but still never a
    // pack source: packability is `allowsPacks`, checked above.
    expect(kBuiltInSources.first, kOsmVector);
  });

  test('R82 the tile life honours the policy floor, not the header', () {
    expect(kOsmVector.minCacheAge, const Duration(days: 7),
        reason: 'the policy says seven days; the service says 300 s');
    expect(kOsmStandard.minCacheAge, Duration.zero,
        reason: 'raster sources keep the server\'s own expiry');
  });

  testWidgets('R80 the layer draws nothing without a MapsController',
      (WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
        home: Provider<MapsController?>.value(
            value: null, child: const VectorBasemapLayer())));
    expect(t.takeException(), isNull);
  });
}
