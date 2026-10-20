// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'tile_math.dart';

/// R61 — a raster basemap the app can show and (sometimes) download.
///
/// [allowsPacks] is the server's own rule, not a preference. OSM's tile
/// policy forbids prefetch and offline use on tile.openstreetmap.org,
/// and OpenTopoMap asks not to be mass-downloaded, so both are
/// view-cache only: tiles you have looked at are kept and honoured by
/// their cache headers, nothing more. USGS National Map basemaps are
/// US-government public domain, so packs are allowed inside the US. A
/// custom server is whatever its owner says it is.
class MapSource {
  const MapSource({
    required this.id,
    required this.name,
    required this.urlTemplate,
    required this.attribution,
    this.subdomains = const <String>[],
    this.maxNativeZoom = 19,
    this.allowsPacks = false,
    this.coverage = const <GeoBox>[],
    this.bytesPerTile = 20000,
    this.custom = false,
  });

  final String id;
  final String name;

  /// `{z}/{x}/{y}` (and optional `{s}`) template.
  final String urlTemplate;
  final String attribution;
  final List<String> subdomains;
  final int maxNativeZoom;
  final bool allowsPacks;

  /// Where the server has data; empty = the whole world.
  final List<GeoBox> coverage;

  /// Planning estimate before a pack has real numbers.
  final int bytesPerTile;
  final bool custom;

  bool covers(GeoBox box) =>
      coverage.isEmpty || coverage.any((GeoBox c) => c.intersects(box));

  Uri tileUri(int z, int x, int y) {
    final String s =
        subdomains.isEmpty ? '' : subdomains[(x + y) % subdomains.length];
    return Uri.parse(urlTemplate
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y')
        .replaceAll('{s}', s));
  }

  Map<String, Object> toJson() => <String, Object>{
        'id': id,
        'name': name,
        'url': urlTemplate,
        'attr': attribution,
        'maxZoom': maxNativeZoom,
        'packs': allowsPacks,
      };

  static MapSource fromJson(Map<String, Object?> j) => MapSource(
        id: j['id']! as String,
        name: j['name']! as String,
        urlTemplate: j['url']! as String,
        attribution: (j['attr'] as String?) ?? '',
        maxNativeZoom: (j['maxZoom'] as num?)?.toInt() ?? 19,
        allowsPacks: j['packs'] == true,
        custom: true,
      );

  /// A custom template must be https and carry all three placeholders.
  static bool validTemplate(String t) {
    final Uri? u = Uri.tryParse(t
        .replaceAll('{z}', '0')
        .replaceAll('{x}', '0')
        .replaceAll('{y}', '0')
        .replaceAll('{s}', 'a'));
    return u != null &&
        u.scheme == 'https' &&
        u.host.isNotEmpty &&
        t.contains('{z}') &&
        t.contains('{x}') &&
        t.contains('{y}');
  }
}

/// US states and territories, coarsely.
const List<GeoBox> _usCoverage = <GeoBox>[
  GeoBox(south: 24.3, west: -125.0, north: 49.5, east: -66.8), // CONUS
  GeoBox(south: 51.0, west: -180.0, north: 71.6, east: -129.0), // Alaska
  GeoBox(south: 18.8, west: -160.4, north: 22.4, east: -154.7), // Hawaii
  GeoBox(south: 17.5, west: -67.4, north: 18.7, east: -64.4), // PR / USVI
];

const MapSource kOsmStandard = MapSource(
  id: 'osm',
  name: 'OpenStreetMap',
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  attribution: '© OpenStreetMap contributors',
  maxNativeZoom: 19,
);

const MapSource kOpenTopo = MapSource(
  id: 'otm',
  name: 'OpenTopoMap',
  urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
  attribution: '© OpenStreetMap contributors, SRTM | © OpenTopoMap (CC-BY-SA)',
  subdomains: <String>['a', 'b', 'c'],
  maxNativeZoom: 17,
);

const MapSource kUsgsTopo = MapSource(
  id: 'usgs-topo',
  name: 'USGS Topo',
  urlTemplate: 'https://basemap.nationalmap.gov/arcgis/rest/services/'
      'USGSTopo/MapServer/tile/{z}/{y}/{x}',
  attribution: 'USGS The National Map',
  maxNativeZoom: 16,
  allowsPacks: true,
  coverage: _usCoverage,
  bytesPerTile: 25000,
);

const MapSource kUsgsImagery = MapSource(
  id: 'usgs-imagery',
  name: 'USGS Imagery',
  urlTemplate: 'https://basemap.nationalmap.gov/arcgis/rest/services/'
      'USGSImageryTopo/MapServer/tile/{z}/{y}/{x}',
  attribution: 'USGS The National Map',
  maxNativeZoom: 16,
  allowsPacks: true,
  coverage: _usCoverage,
  bytesPerTile: 40000,
);

/// The Studio basemap since R82, rendered by `vector_map_tiles` rather than
/// shown as pictures. Deliberately NOT in [kBuiltInSources]: that list is
/// the raster basemap picker, and this source is the Studio skin's implicit
/// basemap. It shares the tile store with the raster sources, so the view
/// cache, ETag revalidation, budget and expiry apply to it too.
///
/// The OpenStreetMap Foundation's own vector tile service, live since July
/// 2025. This is the whole point of R82: OSM publishes vector tiles itself,
/// so the basemap needs no third-party tile company in the middle.
///
/// Policy (`operations.osmfoundation.org/policies/vector`): interactive use
/// by applications is permitted, a unique User-Agent is required, tiles must
/// be cached at least 7 days, attribution goes in the corner, and bulk
/// downloading is forbidden. `httpMapFetcher` sends `MeshmoreSNS/<version>`,
/// the store honours the server's max-age, `kBuiltInSources` keeps it out of
/// the pack picker, and `allowsPacks` is false, so all four hold.
///
/// Schema is Shortbread v1, not OpenMapTiles: different layer names and a
/// flatter model. The bundled style (`assets/maps/studio_dark.json`) is
/// written against that schema, and an archive must carry it too.
const MapSource kOsmVector = MapSource(
  id: 'osm-vec',
  name: 'OpenStreetMap vector',
  urlTemplate: 'https://vector.openstreetmap.org/shortbread_v1/'
      '{z}/{x}/{y}.mvt',
  attribution: '\u00a9 OpenStreetMap contributors',
  maxNativeZoom: 14,
  allowsPacks: false,
  // 84 KB measured for a dense z13 Denver tile; 40 KB is the planning figure.
  bytesPerTile: 40000,
);

const Set<String> kArchiveRequiredLayers = <String>{'water', 'transportation'};

const List<MapSource> kBuiltInSources = <MapSource>[
  kOsmStandard,
  kOpenTopo,
  kUsgsTopo,
  kUsgsImagery,
];
