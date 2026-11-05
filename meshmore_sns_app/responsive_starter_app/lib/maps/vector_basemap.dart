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

import '../theme/mm_skin.dart';
import '../theme/mm_tokens.dart';
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

/// Parsed once per skin: the JSON is ~35 KB and parsing it per rebuild would
/// be wasteful. Keyed by preset because R115 themes the same map seven ways.
/// A failed load is not cached, so a fix is retried.
final Map<String, Future<VectorBasemapStyle>> _stylesByPreset =
    <String, Future<VectorBasemapStyle>>{};

/// R115 — the vector basemap is one map in seven skins.
///
/// Every colour here is a mix of that skin's own tokens, never a literal: the
/// map has to look like the app around it, and a literal would also fail the
/// type/colour ratchet. Roles rather than layers, so the style keeps its
/// structure and only its paint changes.
@immutable
class VectorSkinPalette {
  const VectorSkinPalette({
    required this.ground,
    required this.water,
    required this.waterway,
    required this.forest,
    required this.grass,
    required this.sand,
    required this.rock,
    required this.site,
    required this.building,
    required this.streetArea,
    required this.boundary,
    required this.casing,
    required this.motorway,
    required this.trunk,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.minor,
    required this.service,
    required this.path,
    required this.rail,
    required this.waterLabel,
    required this.streetLabel,
    required this.placeMinor,
    required this.placeMajor,
    required this.halo,
  });

  /// Derive the map's palette from one skin's tokens.
  factory VectorSkinPalette.of(MmTokens t) {
    Color mix(Color a, Color b, double f) => Color.lerp(a, b, f)!;
    return VectorSkinPalette(
      ground: t.base,
      water: mix(t.surfaceAlt, t.link, .22),
      waterway: mix(t.surfaceAlt, t.link, .34),
      forest: mix(t.base, t.ok, .18),
      grass: mix(t.base, t.ok, .10),
      sand: mix(t.base, t.accent, .10),
      rock: mix(t.base, t.surfaceAlt, .50),
      site: mix(t.surface, t.base, .50),
      building: mix(t.surfaceAlt, t.base, .40),
      streetArea: mix(t.surface, t.surfaceAlt, .50),
      boundary: t.line,
      casing: mix(t.line, t.base, .30),
      motorway: mix(t.fgMuted, t.fg, .85),
      trunk: mix(t.fgMuted, t.fg, .75),
      primary: mix(t.fgMuted, t.fg, .65),
      secondary: mix(t.fgMuted, t.fg, .55),
      tertiary: mix(t.fgMuted, t.fg, .45),
      minor: mix(t.fgMuted, t.fg, .35),
      service: mix(t.fgMuted, t.fg, .25),
      path: mix(t.fgMuted, t.fg, .20),
      rail: mix(t.fgMuted, t.line, .40),
      waterLabel: mix(t.fgMuted, t.link, .35),
      streetLabel: mix(t.fgMuted, t.fg, .55),
      placeMinor: t.fgMuted,
      placeMajor: t.fg,
      halo: t.base,
    );
  }

  final Color ground;
  final Color water;
  final Color waterway;
  final Color forest;
  final Color grass;
  final Color sand;
  final Color rock;
  final Color site;
  final Color building;
  final Color streetArea;
  final Color boundary;
  final Color casing;
  final Color motorway;
  final Color trunk;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color minor;
  final Color service;
  final Color path;
  final Color rail;
  final Color waterLabel;
  final Color streetLabel;
  final Color placeMinor;
  final Color placeMajor;
  final Color halo;

  /// The paint each style layer takes from this palette.
  Map<String, Color> get layerColours => <String, Color>{
        'background': ground,
        'ocean': water,
        'water': water,
        'waterway': waterway,
        'land_forest': forest,
        'land_grass': grass,
        'land_sand': sand,
        'land_rock': rock,
        'sites': site,
        'buildings': building,
        'street_area': streetArea,
        'boundary': boundary,
        'street_casing': casing,
        'street_motorway': motorway,
        'street_trunk': trunk,
        'street_primary': primary,
        'street_secondary': secondary,
        'street_tertiary': tertiary,
        'street_minor': minor,
        'street_service': service,
        'street_path': path,
        'street_rail': rail,
        'water_label_line': waterLabel,
        'water_label_point': waterLabel,
        'street_label': streetLabel,
        'place_minor': placeMinor,
        'place_major': placeMajor,
        'place_region': placeMajor,
      };

  /// Text layers that carry a halo, so a label stays readable over any fill.
  static const Set<String> textLayers = <String>{
    'water_label_line',
    'water_label_point',
    'street_label',
    'place_minor',
    'place_major',
    'place_region',
  };
}

/// `#rrggbb`, the only form the style schema accepts.
String colourHex(Color c) {
  final int argb = c.toARGB32();
  final String rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '#$rgb';
}

/// The bundled style with [palette]'s paint applied, layer for layer.
///
/// Only `paint` colours and the text halo change: layer order, filters, widths
/// and label fields are the style's, so a themed map is the same map.
Map<String, Object?> themedVectorStyleJson(
    Map<String, Object?> base, VectorSkinPalette palette) {
  final Map<String, Color> colours = palette.layerColours;
  final List<Object?> layers = <Object?>[];
  for (final Object? raw in (base['layers'] as List<Object?>? ?? <Object?>[])) {
    if (raw is! Map<String, Object?>) {
      layers.add(raw);
      continue;
    }
    final Map<String, Object?> layer = Map<String, Object?>.of(raw);
    final String id = (layer['id'] as String?) ?? '';
    final Color? colour = colours[id];
    if (colour == null) {
      layers.add(layer);
      continue;
    }
    final Map<String, Object?> paint =
        Map<String, Object?>.of((layer['paint'] as Map<String, Object?>?) ??
            <String, Object?>{});
    final String key = switch (layer['type']) {
      'background' => 'background-color',
      'fill' => 'fill-color',
      'line' => 'line-color',
      _ => 'text-color',
    };
    paint[key] = colourHex(colour);
    if (VectorSkinPalette.textLayers.contains(id)) {
      paint['text-halo-color'] = colourHex(palette.halo);
    }
    layer['paint'] = paint;
    layers.add(layer);
  }
  return <String, Object?>{...base, 'layers': layers};
}

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
  MmTokens? tokens,
  String cacheKey = 'default',
}) {
  final Future<VectorBasemapStyle>? cached = _stylesByPreset[cacheKey];
  if (cached != null) return cached;
  final Future<String> Function(String key) read =
      readText ?? (bundle ?? rootBundle).loadString;
  final Future<VectorBasemapStyle> style =
      read(kVectorBasemapAsset).then((String json) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('$kVectorBasemapAsset is not a style object');
    }
    final Map<String, Object?> themed = tokens == null
        ? (decoded as Map<String, Object?>)
        : themedVectorStyleJson(
            Map<String, Object?>.from(decoded), VectorSkinPalette.of(tokens));
    return VectorBasemapStyle(
      vtr.ThemeReader().read(themed),
      null, // no sprite atlas is bundled; icon layers draw nothing
    );
  }, onError: (Object e) {
    _stylesByPreset.remove(cacheKey); // do not cache a failure
    throw e;
  });
  _stylesByPreset[cacheKey] = style;
  return style;
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
    // R114/R115 — the vector half of level of detail: serve the nearest
    // coarse ancestor's *geometry* and let the renderer scale it, which stays
    // sharp because nothing is being upscaled. Two levels, matching the
    // layer's own maximumTileSubstitutionDifference, so the two do not
    // disagree about how far a stand-in may reach.
    final TileAncestor? ancestor =
        await maps.ancestorTile(source, tile.z, tile.x, tile.y, maxUp: 2);
    if (ancestor != null) return ancestor.bytes;
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
    // R115 — the layers use the same vector style and are painted from the
    // active skin's tokens, so all skins share one map that looks like each
    // of them rather than one skin using a raster picture.
    final MmSkin skin = context.skin;
    return FutureBuilder<VectorBasemapStyle>(
      future: loadVectorBasemapStyle(
          tokens: skin.color, cacheKey: skin.preset.name),
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
