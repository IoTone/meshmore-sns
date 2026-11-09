// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' show TileIdentity;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/map_source.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/maps/tile_store.dart';
import 'package:meshmore_sns_app/maps/vector_basemap.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

/// R115 — one vector map, painted from the active skin's tokens.
///
/// The style asset stays the same file: what changes per skin is paint. These
/// tests (a) prove the palettes really differ rather than being a tint, and
/// (b) prove the themed JSON lands the skin's colours on the style's own
/// layers, including the label halo.
class _NeverFetch {
  Future<FetchResult> call(Uri url,
          {String? etag, int? ifModifiedSinceMs}) async =>
      const FetchResult(FetchStatus.failed);
}

const MapSource kTestVector = MapSource(
  id: 'test-vector',
  name: 'Test vector',
  urlTemplate: 'https://tiles.test/{z}/{x}/{y}.mvt',
  attribution: 'test',
);

Map<String, Object?> _baseStyle() => <String, Object?>{
      'version': 8,
      'name': 'test',
      'sources': <String, Object?>{
        'openstreetmap': <String, Object?>{'type': 'vector'},
      },
      'layers': <Object?>[
        <String, Object?>{
          'id': 'background',
          'type': 'background',
          'paint': <String, Object?>{'background-color': '#141414'},
        },
        <String, Object?>{
          'id': 'water',
          'type': 'fill',
          'paint': <String, Object?>{'fill-color': '#1b2a36'},
        },
        <String, Object?>{
          'id': 'street_motorway',
          'type': 'line',
          'paint': <String, Object?>{'line-color': '#6a6a6a', 'line-width': 2.8},
          'layout': <String, Object?>{'line-cap': 'round'},
        },
        <String, Object?>{
          'id': 'place_major',
          'type': 'symbol',
          'paint': <String, Object?>{
            'text-color': '#e2e2e2',
            'text-halo-color': '#141414',
            'text-halo-width': 1.2,
          },
          'layout': <String, Object?>{'text-field': '{name}', 'text-size': 13},
        },
        <String, Object?>{
          'id': 'not_themed',
          'type': 'line',
          'paint': <String, Object?>{'line-color': '#123456'},
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('palette', () {
    test('no two presets paint the map the same', () {
      final Map<MmThemePreset, VectorSkinPalette> all =
          <MmThemePreset, VectorSkinPalette>{
        for (final MmThemePreset p in MmThemePreset.values)
          p: VectorSkinPalette.of(kMmPresets[p]!),
      };
      String signature(VectorSkinPalette p) => p.layerColours.values
          .map((Color c) => c.toARGB32().toRadixString(16))
          .join(',');
      final Map<String, MmThemePreset> bySignature = <String, MmThemePreset>{
        for (final MapEntry<MmThemePreset, VectorSkinPalette> e in all.entries)
          signature(e.value): e.key,
      };
      expect(bySignature.length, MmThemePreset.values.length,
          reason: 'two skins painting an identical map is a tint, not a theme');
    });

    test('the ground differs per skin except where two skins share black', () {
      final List<MmThemePreset> presets = MmThemePreset.values;
      final Set<int> grounds = <int>{
        for (final MmThemePreset p in presets)
          VectorSkinPalette.of(kMmPresets[p]!).ground.toARGB32(),
      };
      // Two pairs share a ground by design: SEELE and RECON are both pure
      // black, and AIR and DAYBREAK are both pure white (mm_tokens.dart). A
      // map that tinted only the ground would be identical inside each pair,
      // and their water, road and label roles still part the palettes, which
      // the test above proves.
      expect(grounds.length, presets.length - 2);
    });

    test('the halo is the ground, so a label never floats on a foreign fill',
        () {
      for (final MmThemePreset p in MmThemePreset.values) {
        final VectorSkinPalette pal = VectorSkinPalette.of(kMmPresets[p]!);
        expect(pal.halo, pal.ground, reason: 'halo must be the ground colour');
        expect(pal.layerColours['background'], pal.ground);
      }
    });

    test('a road class ramp keeps every class distinguishable', () {
      final VectorSkinPalette pal =
          VectorSkinPalette.of(kMmPresets[MmThemePreset.seele]!);
      final List<Color> ramp = <Color>[
        pal.motorway,
        pal.trunk,
        pal.primary,
        pal.secondary,
        pal.tertiary,
        pal.minor,
        pal.service,
        pal.path,
      ];
      expect(ramp.toSet().length, ramp.length);
    });
  });

  group('themed style', () {
    test('the paint lands on the style layers and nothing else moves', () {
      final VectorSkinPalette pal =
          VectorSkinPalette.of(kMmPresets[MmThemePreset.studio]!);
      final Map<String, Object?> themed =
          themedVectorStyleJson(_baseStyle(), pal);
      final List<Object?> layers = themed['layers']! as List<Object?>;

      final Map<String, Object?> bg = layers[0]! as Map<String, Object?>;
      expect((bg['paint']! as Map<String, Object?>)['background-color'],
          colourHex(pal.ground));

      final Map<String, Object?> water = layers[1]! as Map<String, Object?>;
      expect((water['paint']! as Map<String, Object?>)['fill-color'],
          colourHex(pal.water));

      final Map<String, Object?> road = layers[2]! as Map<String, Object?>;
      final Map<String, Object?> roadPaint = road['paint']! as Map<String, Object?>;
      expect(roadPaint['line-color'], colourHex(pal.motorway));
      expect(roadPaint['line-width'], 2.8,
          reason: 'a themed map keeps the style widths');
      expect((road['layout']! as Map<String, Object?>)['line-cap'], 'round');

      final Map<String, Object?> label = layers[3]! as Map<String, Object?>;
      final Map<String, Object?> labelPaint =
          label['paint']! as Map<String, Object?>;
      expect(labelPaint['text-color'], colourHex(pal.placeMajor));
      expect(labelPaint['text-halo-color'], colourHex(pal.ground));
      expect((label['layout']! as Map<String, Object?>)['text-size'], 13);

      // A layer the palette does not name keeps the style's own colour.
      final Map<String, Object?> other = layers[4]! as Map<String, Object?>;
      expect((other['paint']! as Map<String, Object?>)['line-color'],
          '#123456');
    });

    test('the base style is not mutated', () {
      final Map<String, Object?> base = _baseStyle();
      themedVectorStyleJson(base, VectorSkinPalette.of(kMmPresets[MmThemePreset.nerv]!));
      final Map<String, Object?> bg =
          (base['layers']! as List<Object?>)[0]! as Map<String, Object?>;
      expect((bg['paint']! as Map<String, Object?>)['background-color'],
          '#141414');
    });

    test('two skins produce two different style documents', () {
      final Map<String, Object?> studio = themedVectorStyleJson(_baseStyle(),
          VectorSkinPalette.of(kMmPresets[MmThemePreset.studio]!));
      final Map<String, Object?> seele = themedVectorStyleJson(_baseStyle(),
          VectorSkinPalette.of(kMmPresets[MmThemePreset.seele]!));
      expect(jsonEncode(studio), isNot(jsonEncode(seele)));
    });
  });

  group('vector ancestor fallback', () {
    late Directory dir;
    late DateTime now;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      dir = await Directory.systemTemp.createTemp('vector_lod_test');
      now = DateTime(2026, 10, 15, 12);
    });

    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('a missing fine tile is served from its coarse ancestor', () async {
      final TileStore seed = TileStore(dir, clock: () => now);
      await seed.load();
      await seed.write(TileStore.keyOf(kTestVector.id, 11, 1000, 1503),
          Uint8List.fromList(<int>[7, 7, 7]),
          maxAge: const Duration(days: 1));
      await seed.flush();

      final MapsController maps = MapsController(
        rootDir: () async => dir,
        fetcher: _NeverFetch().call,
        clock: () => now,
        pace: Duration.zero,
      );
      await maps.load();
      addTearDown(maps.dispose);

      final MmVectorTileProvider provider =
          MmVectorTileProvider(maps, kTestVector);
      final Uint8List bytes = await provider.provide(
          TileIdentity(12, 2001, 3007));
      expect(bytes, <int>[7, 7, 7],
          reason: 'geometry scales, so a coarse tile is a sharp stand-in');
    });

    test('nothing at any zoom is a provider failure, not a wrong tile',
        () async {
      final MapsController maps = MapsController(
        rootDir: () async => dir,
        fetcher: _NeverFetch().call,
        clock: () => now,
        pace: Duration.zero,
      );
      await maps.load();
      addTearDown(maps.dispose);

      final MmVectorTileProvider provider =
          MmVectorTileProvider(maps, kTestVector);
      await expectLater(
          provider.provide(TileIdentity(12, 2001, 3007)), throwsA(anything));
    });
  });
}
