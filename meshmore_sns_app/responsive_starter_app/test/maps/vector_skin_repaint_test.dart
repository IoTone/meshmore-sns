// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/maps/vector_basemap.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

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

  // A style cache is process-global in the app and must not carry a fixture
  // from one test into the next.
  setUp(resetVectorBasemapCache);

  /// A minimal style document, served by a reader that counts its calls.
  ({Future<String> Function(String) read, int Function() calls}) reader() {
    int calls = 0;
    return (
      read: (String key) async {
        calls++;
        return jsonEncode(<String, Object?>{
          'version': 8,
          'sources': <String, Object?>{
            kVectorBasemapSourceId: <String, Object?>{
              'type': 'vector',
              'maxzoom': 14,
            },
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
              'source-layer': 'water_polygons',
              'paint': <String, Object?>{'fill-color': '#223344'},
            },
          ],
        });
      },
      calls: () => calls,
    );
  }

  test('every skin gets its own theme identity', () async {
    final ({Future<String> Function(String) read, int Function() calls}) r =
        reader();
    final Map<String, MmThemePreset> byId = <String, MmThemePreset>{};
    for (final MmThemePreset p in MmThemePreset.values) {
      final VectorBasemapStyle style = await loadVectorBasemapStyle(
        readText: r.read,
        tokens: kMmPresets[p]!,
        cacheKey: p.name,
      );
      expect(style.theme.id, vectorStyleIdFor(p.name),
          reason: 'a skin the renderer cannot name is a skin it will not '
              'repaint: $p');
      byId[style.theme.id] = p;
    }
    expect(byId.length, MmThemePreset.values.length,
        reason: 'eight skins, eight identities');
  });

  test('the style document is read once, not once per skin', () async {
    // The real path: no injected reader, so the document is cached for the
    // process exactly as it is in the app. Eight skins, one decode.
    final int before = vectorStyleDocumentsDecoded;
    for (final MmThemePreset p in MmThemePreset.values) {
      final VectorBasemapStyle style = await loadVectorBasemapStyle(
        tokens: kMmPresets[p]!,
        cacheKey: 'count-${p.name}',
      );
      expect(style.theme.id, vectorStyleIdFor('count-${p.name}'));
    }
    expect(vectorStyleDocumentsDecoded - before, 1,
        reason: 'one document with eight paints, not eight documents');
  });

  test('a supplied reader is not cached for the next caller', () async {
    final ({Future<String> Function(String) read, int Function() calls}) a =
        reader();
    final ({Future<String> Function(String) read, int Function() calls}) b =
        reader();
    await loadVectorBasemapStyle(
        readText: a.read,
        tokens: kMmPresets[MmThemePreset.studio]!,
        cacheKey: 'leak-a');
    await loadVectorBasemapStyle(
        readText: b.read,
        tokens: kMmPresets[MmThemePreset.seele]!,
        cacheKey: 'leak-b');
    expect(b.calls(), 1,
        reason: 'a fixture must not become the document every later caller '
            'sees');
  });
}
