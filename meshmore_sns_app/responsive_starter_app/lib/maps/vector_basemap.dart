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

/// The bundled style document, decoded once for the whole process.
///
/// Themes are eight paints over one document, so the asset is read and
/// `jsonDecode`d once and every skin then only maps colours. Before this each
/// preset read the asset and parsed 35 KB again, which is the work the owner
/// could see as the map rebuilding itself when the skin changed.
final Map<String, Future<Map<String, Object?>>> _baseStyles =
    <String, Future<Map<String, Object?>>>{};

/// Test seam: forget every parsed style and decoded document.
///
/// The caches are process-global because the app has one style and one asset,
/// which is right in a build and wrong in a test file: a test that loads a
/// fixture under a preset's own key would otherwise hand that fixture to the
/// next test. Only tests call this.
@visibleForTesting
void resetVectorBasemapCache() {
  _stylesByPreset.clear();
  _baseStyles.clear();
  _documentsDecoded = 0;
}

/// Test seam: how many times a style document has actually been read and
/// decoded. The whole point of the cache above is that this stays at one
/// across eight skins, and a number is easier to check than a timing.
@visibleForTesting
int get vectorStyleDocumentsDecoded => _documentsDecoded;
int _documentsDecoded = 0;

/// [cache] is false when a caller supplied its own reader. A supplied reader
/// is a seam (a fixture, a counter), and caching its document for the process
/// would leak one caller's style into the next — the real bundle is the only
/// document that is the same for everyone.
Future<Map<String, Object?>> _baseStyle(
    String asset, Future<String> Function(String) read, {bool cache = true}) {
  final Future<Map<String, Object?>>? cached = cache ? _baseStyles[asset] : null;
  if (cached != null) return cached;
  _documentsDecoded++;
  final Future<Map<String, Object?>> base =
      read(asset).then((String json) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('$asset is not a style object');
    }
    return Map<String, Object?>.from(decoded);
  }, onError: (Object e) {
    if (cache) _baseStyles.remove(asset); // do not cache a failure
    throw e;
  });
  if (cache) _baseStyles[asset] = base;
  return base;
}

/// R115 — the vector basemap is one map in eight skins.
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
      // Sand leans on the *warn* token rather than the accent, because on the
      // skins where the accent and `ok` are the same colour (AG-HUD, Recon) the
      // two derived fills came out identical and the beach was the park. A
      // beach is warm, `warn` is the palette's warm token, and the two are now
      // independent of the accent by construction.
      sand: mix(t.base, t.warn, .16),
      rock: mix(t.base, t.surfaceAlt, .50),
      site: mix(t.surface, t.base, .50),
      building: mix(t.surfaceAlt, t.base, .40),
      streetArea: mix(t.surface, t.surfaceAlt, .50),
      boundary: t.line,
      // The road network is the *ground* the data is drawn on, not a subject of
      // its own, and it used to be mixed most of the way toward the foreground
      // text colour — a motorway at 85 % of `fg` was the brightest thing on the
      // map in every skin, so a thread of node markers sat under a web of pale
      // lines. The ramp starts from the quiet rule colour instead and reaches
      // only a third of the way to the muted text colour at its loudest, so a
      // ring road reads as structure and a pin reads as data.
      //
      // The mix reaches 70 % of the way to the muted text colour at most, where
      // it used to reach 85 % of the way to the *foreground* colour, so the whole
      // network sits a full step below the labels and a second step below the
      // node pins. The floor matters as much as the ceiling: the map guard holds
      // every road at 2.6:1 against its ground, because a road that cannot be
      // seen is not a quieter road, it is a missing one.
      casing: mix(t.line, t.base, .35),
      motorway: mix(t.line, t.fgMuted, .70),
      trunk: mix(t.line, t.fgMuted, .64),
      primary: mix(t.line, t.fgMuted, .60),
      secondary: mix(t.line, t.fgMuted, .56),
      tertiary: mix(t.line, t.fgMuted, .52),
      minor: mix(t.line, t.fgMuted, .48),
      service: mix(t.line, t.fgMuted, .44),
      path: mix(t.line, t.fgMuted, .40),
      rail: mix(t.line, t.fgMuted, .42),
      waterLabel: mix(t.fgMuted, t.link, .35),
      streetLabel: mix(t.fgMuted, t.fg, .45),
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

/// The identity a themed style carries into `vector_map_tiles`.
///
/// The style asset declares no `id`, so `ThemeReader` fell back to the string
/// `default` for every skin: eight themes all called `default`. The layer only
/// repaints when `theme.id` changes (`vector_map_tiles` 8.0.0,
/// `options.dart:52-61` `hasRenderDifferences`, `grid_layer.dart:312-320`), so
/// a skin change left the old palette on screen and painted only the tiles
/// created afterwards in the new one — a map in two themes at once. One id per
/// skin restores the repaint the library expects.
String vectorStyleIdFor(String skinId) => 'meshmore-$skinId';

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
      _baseStyle(kVectorBasemapAsset, read, cache: readText == null)
          .then((Map<String, Object?> base) {
    final Map<String, Object?> themed = tokens == null
        ? base
        : themedVectorStyleJson(base, VectorSkinPalette.of(tokens));
    // The identity is what tells the renderer that a skin changed; the paint
    // alone is invisible to it. See [vectorStyleIdFor].
    final Map<String, Object?> identified = <String, Object?>{
      ...themed,
      'id': vectorStyleIdFor(cacheKey),
    };
    return VectorBasemapStyle(
      vtr.ThemeReader().read(identified),
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
/// The last style that loaded stays on screen while the next skin's style is
/// built. Rendering nothing in that gap is what the owner described as the
/// vectors "loading as black and then having to get redrawn as white": the
/// layer vanished for a frame or two, the map's own ground colour (near-black
/// in the dark skins, paper in the light one) showed through, and the tiles
/// popped back. One map, kept, is better than a correct one a frame later.
class VectorBasemapLayer extends StatefulWidget {
  const VectorBasemapLayer({super.key, this.source = kOsmVector});

  final MapSource source;

  @override
  State<VectorBasemapLayer> createState() => _VectorBasemapLayerState();
}

class _VectorBasemapLayerState extends State<VectorBasemapLayer> {
  /// The style currently drawn. Kept across a skin change so the map does not
  /// blink through its ground colour.
  VectorBasemapStyle? _shown;

  /// The provider handed to the renderer, kept for the life of this State.
  ///
  /// It used to be constructed inside `build`, so every rebuild of the map —
  /// and the map rebuilt once a second — handed the renderer a *new* provider
  /// object and a new `TileProviders` map. The renderer keys its parsed-tile
  /// cache off those, so each rebuild orphaned up to 24 MB of parsed tiles and
  /// started again. That is a heap that never settles, and it is the second
  /// half of the out-of-memory report.
  MmVectorTileProvider? _provider;
  TileProviders? _providers;
  String? _providerSourceId;

  MapSource get source => widget.source;

  /// The provider for [maps] and the current source, rebuilt only when either
  /// actually changes.
  TileProviders _providersFor(MapsController maps) {
    if (_providers != null && _providerSourceId == source.id) {
      return _providers!;
    }
    _provider = MmVectorTileProvider(maps, source);
    _providerSourceId = source.id;
    _providers = TileProviders(<String, VectorTileProvider>{
      kVectorBasemapSourceId: _provider!,
    });
    return _providers!;
  }

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
        final VectorBasemapStyle? style = s.data ?? _shown;
        if (style == null) return const SizedBox.shrink();
        _shown = style;
        return VectorTileLayer(
          theme: style.theme,
          sprites: style.sprites,
          tileProviders: _providersFor(maps),
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
