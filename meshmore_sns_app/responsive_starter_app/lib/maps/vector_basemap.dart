// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
/// R80 — the Studio basemap is **rendered**, not a recoloured picture.
///
/// `vector_map_tiles` draws Mapbox-GL-style vector tiles onto Flutter's own
/// canvas (no platform view), from a style JSON that says what land, water,
/// roads and labels look like. That replaces the raster-tile-plus-filter
/// arrangement (R70-R79): there is nothing to invert or desaturate, colour
/// is part of the style, and the result is sharp at every zoom instead of
/// being upscaled PNG.
///
/// Offline is unchanged. [MmVectorTileProvider] hands the layer the *same*
/// `MapsController.loadTile` bytes path the raster layer used, so the R61
/// view cache, packs, ETag revalidation, budget and expiry all still
/// apply, keyed by source id. A vector tile is simply a smaller payload
/// for the same (z, x, y), so an existing pack costs less space for the
/// same area.
library;
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'map_source.dart';
import 'maps_controller.dart';



/// The style asset. Apache-2.0, derived from OpenFreeMap's `dark` style
/// (OpenMapTiles schema, OSM data); trimmed to the one vector source and
/// with the unused raster relief source, `glyphs` and `sprite` removed.
///
/// Labels need no glyph server: `vector_tile_renderer` renders `text-font`
/// with Flutter's own text engine, so a missing font family falls back to
/// the app's typeface rather than to a network fetch.
const String kVectorBasemapAsset = 'assets/maps/studio_dark.json';

/// The source id inside the style that [MmVectorTileProvider] serves.
const String kVectorBasemapSourceId = 'openmaptiles';

/// Parsed once per process: the JSON is ~35 KB and parsing it per rebuild
/// would be wasteful. A failed load is not cached, so a fix is retried.
Future<VectorBasemapStyle>? _styleFuture;

@immutable
class VectorBasemapStyle {
  const VectorBasemapStyle(this.theme, this.sprites);
  final vtr.Theme theme;
  final SpriteStyle? sprites;
}

/// Load (and cache) the bundled style.
Future<VectorBasemapStyle> loadVectorBasemapStyle({
  AssetBundle? bundle,
  Future<String> Function(String key)? readText,
}) {
  final Future<String> Function(String key) read =
      readText ?? (bundle ?? rootBundle).loadString;
  return _styleFuture ??= read(kVectorBasemapAsset).then((String json) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('$kVectorBasemapAsset is not a style object');
    }
    return VectorBasemapStyle(
      vtr.ThemeReader().read(decoded),
      null, // no sprite atlas is bundled; icon layers draw nothing
    );
  }, onError: (Object e) {
    _styleFuture = null; // do not cache a failure
    throw e;
  });
}

/// Serves vector tiles from the app's own tile store, so offline works the
/// same way it did for raster: disk first, network second, packs honoured.
class MmVectorTileProvider implements VectorTileProvider {
  MmVectorTileProvider(this.maps, this.source);

  final MapsController maps;
  final MapSource source;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    final Uint8List? bytes =
        await maps.loadTile(source, tile.z, tile.x, tile.y);
    if (bytes == null) {
      // Offline and never seen. Not retryable inside this frame; the view
      // cache is tried again when the map moves.
      throw ProviderException(
        message: 'vector tile ${source.id}/${tile.z}/${tile.x}/${tile.y} '
            'unavailable',
        retryable: Retryable.none,
      );
    }
    return bytes;
  }

  @override
  int get minimumZoom => 0;

  @override
  int get maximumZoom => source.maxNativeZoom;

  @override
  TileProviderType get type => TileProviderType.vector;
}

/// The Studio basemap layer. Must be a child of `FlutterMap`.
///
/// While the style loads (one asset read, once) nothing is drawn; the map
/// still shows its markers and event layers, so this never blocks the view.
class VectorBasemapLayer extends StatelessWidget {
  const VectorBasemapLayer({super.key, this.source = kOpenFreeMapVector});

  final MapSource source;

  @override
  Widget build(BuildContext context) {
    final MapsController? maps =
        Provider.of<MapsController?>(context, listen: false);
    if (maps == null) return const SizedBox.shrink();
    return FutureBuilder<VectorBasemapStyle>(
      future: loadVectorBasemapStyle(),
      builder: (BuildContext context, AsyncSnapshot<VectorBasemapStyle> s) {
        final VectorBasemapStyle? style = s.data;
        if (style == null) return const SizedBox.shrink();
        return VectorTileLayer(
          theme: style.theme,
          sprites: style.sprites,
          tileProviders: TileProviders(<String, VectorTileProvider>{
            kVectorBasemapSourceId: MmVectorTileProvider(maps, source),
          }),
          // Parsing happens off the UI thread when the platform allows it.
          concurrency: 2,
        );
      },
    );
  }
}
