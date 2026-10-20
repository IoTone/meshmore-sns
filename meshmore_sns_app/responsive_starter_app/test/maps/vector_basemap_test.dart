// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
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

    test('zoom bounds follow the source', () {
      final MmVectorTileProvider provider =
          MmVectorTileProvider(maps, kOpenFreeMapVector);
      expect(provider.minimumZoom, 0);
      expect(provider.maximumZoom, kOpenFreeMapVector.maxNativeZoom);
    });
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
