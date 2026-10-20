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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R80 vector basemap style', () {
    test('the bundled asset is a vector style for openmaptiles', () async {
      final String json = await rootBundle.loadString(kVectorBasemapAsset);
      final Map<String, dynamic> style = jsonDecode(json) as Map<String, dynamic>;
      final Map<String, dynamic> sources =
          style['sources'] as Map<String, dynamic>;
      expect(sources.keys, <String>[kVectorBasemapSourceId],
          reason: 'one vector source; the unused raster relief source is gone');
      expect((sources[kVectorBasemapSourceId] as Map)['type'], 'vector');
      expect(style.containsKey('glyphs'), isFalse,
          reason: 'labels render through Flutter text, not a glyph server');
      expect(style.containsKey('sprite'), isFalse,
          reason: 'no remote sprite atlas is fetched');
      final List<dynamic> layers = style['layers'] as List<dynamic>;
      expect(layers.length, greaterThan(40));
      expect((layers.first as Map)['type'], 'background');
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
          MmVectorTileProvider(maps, kOpenFreeMapVector);
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
          MmVectorTileProvider(maps, kOpenFreeMapVector);
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
        MmVectorTileProvider(m, kOpenFreeMapVector)
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
        MmVectorTileProvider(m, kOpenFreeMapVector)
            .provide(vmt.TileIdentity(2, 0, 0)),
        throwsA(isA<vmt.ProviderException>()),
        reason: 'the renderer pool must never see a raw exception',
      );
      m.dispose();
    });

    test('zoom bounds follow the source', () {
      final MmVectorTileProvider provider =
          MmVectorTileProvider(maps, kOpenFreeMapVector);
      expect(provider.minimumZoom, 0);
      expect(provider.maximumZoom, kOpenFreeMapVector.maxNativeZoom);
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
      expect(labels, 13, reason: '10 places, 2 road names, 1 water name');
    });

    test('roads separate from the land, and rank by importance', () {
      final double minor = contrast(paint('highway_minor', 'line-color'), land);
      final double major =
          contrast(paint('highway_major_inner', 'line-color'), land);
      final double motorway =
          contrast(paint('highway_motorway_subtle', 'line-color'), land);
      expect(minor, greaterThanOrEqualTo(1.8));
      expect(major, greaterThan(minor));
      expect(major, greaterThanOrEqualTo(3.0));
      expect(motorway, greaterThanOrEqualTo(1.8));
    });

    test('water is blue, parks are green, both visible against land', () {
      final List<int> w = rgb(paint('water', 'fill-color'));
      final List<int> g = rgb(paint('landuse_park', 'fill-color'));
      expect(w[2], greaterThan(w[0] + 12), reason: 'blue');
      expect(g[1], greaterThan(g[0] + 8), reason: 'green');
      expect(contrast(paint('water', 'fill-color'), land), greaterThan(1.1));
      expect(contrast(paint('landuse_park', 'fill-color'), land),
          greaterThan(1.1));
      // Water is distinguishable from a park, not just from land.
      expect(paint('water', 'fill-color'),
          isNot(paint('landuse_park', 'fill-color')));
    });

    test('the style stays small: 47 layers, one source, under 40 KB', () async {
      expect(byId, hasLength(47));
      expect((await rootBundle.loadString(kVectorBasemapAsset)).length,
          lessThan(40 * 1000));
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

  test('R80 only Studio renders the vector basemap', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      expect(mmSkinFor(p).shape.vectorBasemap, p == MmThemePreset.studio,
          reason: '$p');
    }
  });

  test('R80 the vector source carries the credit its licence requires', () {
    expect(kOpenFreeMapVector.attribution, contains('OpenFreeMap'));
    expect(kOpenFreeMapVector.attribution, contains('OpenMapTiles'));
    expect(kOpenFreeMapVector.attribution, contains('OpenStreetMap'));
    expect(kOpenFreeMapVector.allowsPacks, isFalse,
        reason: 'OpenFreeMap caps offline use at 3,000 tiles / 50 MB per '
            'download; a region pack must not come from it (R81)');
  });

  testWidgets('R80 the layer draws nothing without a MapsController',
      (WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
        home: Provider<MapsController?>.value(
            value: null, child: const VectorBasemapLayer())));
    expect(t.takeException(), isNull);
  });
}
