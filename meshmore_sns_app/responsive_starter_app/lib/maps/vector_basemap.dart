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

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'map_source.dart';
import 'maps_controller.dart';



/// The style asset. Written for this app (R82) against the Shortbread v1
/// schema that OSM's own vector service publishes: one vector source, no
/// glyphs, no sprite, no third-party style licence to track.
///
/// Labels need no glyph server: `vector_tile_renderer` renders `text-font`
/// with Flutter's own text engine, so a missing font family falls back to
/// the app's typeface rather than to a network fetch.
const String kVectorBasemapAsset = 'assets/maps/studio_dark.json';

/// The source id inside the style that [MmVectorTileProvider] serves.
/// Must match the source name inside the style asset.
const String kVectorBasemapSourceId = 'openstreetmap';

/// What shows through wherever a tile has not arrived yet (R81). It is the
/// style's own `background` layer colour, so an unloaded tile reads as
/// "land, not yet drawn" and not as a grey fault. A guard test keeps the
/// two equal. Zero network cost, unlike a second basemap underneath.
const Color kVectorBasemapBackground = Color(0xFF141414);

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
    final String name = '${source.id}/${tile.z}/${tile.x}/${tile.y}';
    final TileLoad load;
    try {
      load = await maps.loadTileDetailed(source, tile.z, tile.x, tile.y);
    } catch (e) {
      // Nothing thrown here may reach the renderer's isolate pool: a bad
      // tile is a hole, never a crashed map.
      if (kDebugMode) debugPrint('vector tile $name failed: $e');
      throw ProviderException(
          message: 'vector tile $name failed',
          retryable: Retryable.none);
    }
    if (load.bytes != null) return load.bytes!;
    if (load.missing) {
      // The server's answer is "nothing here" (open ocean, empty area).
      // 404 makes the renderer draw an empty tile, so only the background
      // shows, instead of treating a real answer as a failure.
      throw ProviderException(
          message: 'vector tile $name: no data',
          statusCode: 404,
          retryable: Retryable.none);
    }
    // Offline and never seen, gated, or superseded in the fetch queue. The
    // view cache is tried again when the map moves.
    if (kDebugMode) debugPrint('vector tile $name unavailable');
    throw ProviderException(
        message: 'vector tile $name unavailable', retryable: Retryable.none);
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
  const VectorBasemapLayer({super.key, this.source = kOsmVector});

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
          // Isolates for parsing/rendering (NOT network parallelism: that is
          // MapsController.viewGate). The library default is 4; R80 had
          // set 2. Ignored in debug builds, where the library runs one
          // queue on the UI isolate.
          concurrency: 4,
          // Parsed tiles held for pan-back. The 10 MB default keeps about a
          // screen; a pan actually revisits a ring around it, so hold more.
          // This is RenderingLayers' memory only - bytes on disk are still
          // owned and budgeted by TileStore below.
          memoryTileCacheMaxSize: 24 * 1024 * 1024,
          // Our TileStore is the cache of record (budget, expiry, ETag,
          // packs). The library keeps its own second copy of every tile in
          // the temp directory with a 30-day TTL and no revalidation; keep
          // that to a token size so it cannot hold stale bytes or a
          // hidden gigabyte beside the budgeted store.
          fileCacheMaximumSizeInBytes: 1024 * 1024,
          fileCacheTtl: const Duration(hours: 1),
          // Draw a lower/higher-zoom tile in place of one still loading
          // (library default 2; stated so a library change cannot silently
          // bring holes back).
          maximumTileSubstitutionDifference: 2,
        );
      },
    );
  }
}
