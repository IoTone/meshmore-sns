// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'event_layer.dart';
import 'fetch_gate.dart';
import 'map_archive.dart';
import 'map_fetch.dart';
import 'map_pack.dart';
import 'map_source.dart';
import 'network_gate.dart';
import '../util/safe_notifier.dart';
import 'disk_space.dart';
import 'pack_catalog.dart';
import 'pmtiles.dart';
import 'tile_ancestor.dart';
import 'tile_math.dart';
import 'tile_store.dart';
import '../app/app_errors.dart';
import '../util/prefs.dart';

/// A coarser tile that can stand in for one that is not on disk (R114).
class TileAncestor {
  const TileAncestor({required this.bytes, required this.coord});

  final Uint8List bytes;
  final TileAncestorCoord coord;
}

/// What [MapsController.loadTileDetailed] found.
class TileLoad {
  const TileLoad(this.bytes, {this.missing = false});

  /// null when the tile could not be had right now.
  final Uint8List? bytes;

  /// True when the server answered "no such tile" (404/410/204): a real,
  /// final answer (ocean, empty area), not an outage.
  final bool missing;
}

/// Why a pack was not created — one sentence each in the UI.
enum PackRefusal {
  noName,
  offline,
  sourceViewOnly,
  outsideCoverage,
  tooManyTiles,
  overBudget,
}

/// Why an event layer was not added.
enum LayerRefusal {
  badUrl,
  offline,

  /// The document is not GeoJSON this build can read.
  notGeoJson,

  /// It parsed, and it holds nothing to draw.
  ///
  /// A publisher's empty FeatureCollection is a legitimate document and was
  /// reported as `notGeoJson`, which told the reader their file was malformed
  /// when it was simply empty. This is the honest refusal.
  empty,
  tooLarge,
  overBudget,
}

/// R61 — offline maps (issue #5): the tile cache, region packs, event
/// layers, the storage budget and expiry. See
/// `meshmore-sns-maps-spec.md`.
///
/// One download runs at a time, politely paced. Downloads are
/// opportunistic: a network failure parks the pack as "waiting for
/// network" and a backoff timer (or any successful map fetch, e.g. the
/// user panning a map) wakes it. A half-done pack still shows what it
/// has; packs fill lowest zoom first.
class MapsController extends ChangeNotifier with SafeNotifier {
  MapsController({
    Future<Directory> Function()? rootDir,
    MapFetcher? fetcher,
    DateTime Function()? clock,
    this.pace = const Duration(milliseconds: 40),
    this.concurrency = 3,
    String Function()? appVersion,
    this.prefsKey = 'maps.state.v1',
    this.retryFloor = const Duration(seconds: 30),
    math.Random? random,
    ArchiveFetcher? archiveFetcher,
    DiskSpace? diskSpace,
    NetworkGate? networkGate,
    this.catalogUrl = kPackCatalogUrl,
    Future<String> Function()? bundledCatalog,
    Future<String> Function(Uri)? catalogFetcher,
  })  : _random = random ?? math.Random(),
        _diskSpace = diskSpace ?? const PlatformDiskSpace(),
        _networkGate = networkGate ?? const PlatformNetworkGate(),
        _bundledCatalog = bundledCatalog ?? _bundleCatalogText,
        _catalogFetcher = catalogFetcher ?? _httpCatalogText,
        _rootDir = rootDir ?? _defaultRoot,
        _clock = clock ?? DateTime.now {
    _fetch = fetcher ??
        httpMapFetcher(() => mapUserAgent(appVersion?.call() ?? ''));
    _archiveFetch = archiveFetcher ??
        httpArchiveFetcher(() => mapUserAgent(appVersion?.call() ?? ''));
  }

  static Future<Directory> _defaultRoot() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/maps');

  /// Where state persists; the self-test uses its own so it never
  /// touches the user's packs.
  final String prefsKey;

  /// Shortest wait before a parked download tries again.
  final Duration retryFloor;

  /// How many tile requests may be in flight at once.
  ///
  /// One at a time made the download latency-bound: a 200 ms round trip plus the
  /// old 150 ms sleep is four tiles a second, so a 2000-tile pack was five
  /// minutes of mostly waiting. Three in flight overlaps the round trips without
  /// turning a tile host into a target.
  final int concurrency;

  final math.Random _random;

  /// R81 — viewing fetches go through this: 4 at a time, newest first,
  /// stale requests dropped. See [TileFetchGate].
  final TileFetchGate viewGate = TileFetchGate();

  /// Keys the server said do not exist, remembered for this run so a pan
  /// back over open ocean does not ask again. Bounded; cleared when full.
  final Set<String> _absent = <String>{};
  static const int _absentCap = 2048;

  /// R81 — consecutive failed *viewing* fetches on one source before that
  /// source (only) stops being asked. One lost tile on a cell link is
  /// normal; three in a row is an outage.
  static const int viewFailuresBeforeBackoff = 3;

  static const List<int> budgetChoicesMb = <int>[100, 250, 500, 1000, 2000, 5000];
  static const List<int> keepChoicesDays = <int>[0, 7, 30, 90, 365];
  static const List<int> viewKeepChoicesDays = <int>[7, 30, 90, 365];

  /// A pack is a neighbourhood: past this many tiles, zoom out or
  /// shrink the area.
  static const int maxPackTiles = 50000;
  static const int maxLayerBytes = 10 * 1024 * 1024;

  /// Server said nothing: OSM's policy floor for a viewed tile, and a
  /// month for a pack tile (packs refresh on Update).
  static const Duration viewMaxAgeDefault = Duration(days: 7);
  static const Duration packMaxAgeDefault = Duration(days: 30);

  final Future<Directory> Function() _rootDir;
  final DateTime Function() _clock;
  late final MapFetcher _fetch;
  late final ArchiveFetcher _archiveFetch;
  final Duration pace;

  TileStore? _store;
  Directory? _root;
  final Completer<void> _ready = Completer<void>();

  final List<MapSource> _custom = <MapSource>[];
  final List<MapPack> packs = <MapPack>[];

  /// R81 — region archives (one PMTiles file each). See [addArchive].
  final List<MapArchive> archives = <MapArchive>[];
  final Map<String, int> _archiveSize = <String, int>{};
  // Futures, so a burst of first reads opens the file once, not once each.
  final Map<String, Future<PmTilesArchive>> _openArchives =
      <String, Future<PmTilesArchive>>{};
  final List<EventLayer> layers = <EventLayer>[];
  final Map<String, GeoShapes> _shapes = <String, GeoShapes>{};

  int budgetMb = 500;
  int viewKeepDays = 30;

  /// R84 — a region archive is tens to hundreds of megabytes, so the download
  /// waits for an unmetered link unless the user says otherwise.
  bool wifiOnlyArchives = true;

  final DiskSpace _diskSpace;
  final NetworkGate _networkGate;
  final Future<String> Function() _bundledCatalog;
  final Future<String> Function(Uri) _catalogFetcher;

  /// Where a published pack list is fetched from; empty = bundle only.
  final String catalogUrl;

  /// The pack list a user may install from, once [refreshCatalog] has run.
  PackCatalog? catalog;
  bool catalogLoading = false;

  bool _pumping = false;
  Timer? _retry;
  Timer? _sweep;
  Timer? _trim;
  int _backoffS = 0;
  int _offlineUntilMs = 0;

  /// R81 — view-path health, per tile source. Before this, one failed
  /// fetch set the single global [_offlineUntilMs] and every tile of every
  /// source returned null for 30 s (doubling to 900 s): a hiccup on one
  /// tile blanked the whole map.
  final Map<String, _SourceHealth> _health = <String, _SourceHealth>{};

  /// null = no fetch yet this run.
  bool? lastFetchOk;

  int get _now => _clock().millisecondsSinceEpoch;
  bool get loaded => _ready.isCompleted;
  Future<void> get ready => _ready.future;
  bool get _inBackoff => _now < _offlineUntilMs;

  /// Best guess at reachability, from the last map fetch.
  bool get online => lastFetchOk != false && !_inBackoff;

  List<MapSource> get sources => <MapSource>[...kBuiltInSources, ..._custom];
  List<MapSource> get customSources => List<MapSource>.unmodifiable(_custom);

  MapSource? sourceById(String id) {
    for (final MapSource s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  // ---- accounting --------------------------------------------------

  int get budgetBytes => budgetMb * 1000 * 1000;
  int get layerBytes => layers.fold(0, (int a, EventLayer l) => a + l.bytes);
  int get tileBytes => _store?.totalBytes ?? 0;
  int get viewBytes => _store?.viewBytes ?? 0;
  int archiveBytesOf(MapArchive a) => _archiveSize[a.id] ?? 0;
  int get archiveBytes => _archiveSize.values.fold(0, (int a, int b) => a + b);
  int get usedBytes => tileBytes + layerBytes + archiveBytes;

  /// Bytes nothing will evict on its own: pack tiles and layers.
  int get pinnedBytes => usedBytes - viewBytes;

  int packBytes(MapPack p) => _store?.packBytes(p.id) ?? 0;
  int packTilesHeld(MapPack p) => _store?.packTiles(p.id) ?? 0;

  /// The folder tiles and layers live in (null until [load]).
  Directory? get storageDir => _root;

  int estimateBytes(MapSource s, GeoBox box, int minZ, int maxZ) =>
      tileCount(box, minZ, maxZ) * s.bytesPerTile;

  // ---- lifecycle ---------------------------------------------------

  Future<void> load() async {
    if (_ready.isCompleted) return;
    try {
      _root = await _rootDir();
      _store = TileStore(_root!, clock: _clock);
      await _store!.load();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(prefsKey);
      if (raw != null) _decode(raw);
      await _measureArchives();
    } catch (_) {
      _store ??= TileStore(Directory.systemTemp, clock: _clock);
    }
    _ready.complete();
    // The map is usable as soon as the store and the prefs are in. Expiry
    // sweeping and the view trim walk the tile directories, which is real file
    // I/O and grows with the cache, and holding the first frame behind it is
    // part of why the map took a moment to appear. Housekeeping runs after the
    // map has drawn.
    notifyListeners();
    unawaited(_housekeep());
    unawaited(_pump());
  }

  void _decode(String raw) {
    try {
      final Map<String, Object?> j = jsonDecode(raw) as Map<String, Object?>;
      budgetMb = (j['budgetMb'] as num?)?.toInt() ?? budgetMb;
      viewKeepDays = (j['viewKeep'] as num?)?.toInt() ?? viewKeepDays;
      wifiOnlyArchives = (j['wifiOnly'] as bool?) ?? wifiOnlyArchives;
      for (final Object? s in (j['sources'] as List<Object?>?) ?? <Object?>[]) {
        _custom.add(MapSource.fromJson(s! as Map<String, Object?>));
      }
      for (final Object? p in (j['packs'] as List<Object?>?) ?? <Object?>[]) {
        packs.add(MapPack.fromJson(p! as Map<String, Object?>));
      }
      for (final Object? l in (j['layers'] as List<Object?>?) ?? <Object?>[]) {
        layers.add(EventLayer.fromJson(l! as Map<String, Object?>));
      }
      for (final Object? a in (j['archives'] as List<Object?>?) ?? <Object?>[]) {
        archives.add(MapArchive.fromJson(a! as Map<String, Object?>));
      }
    } catch (error, stack) {
      // A corrupt state document used to be dropped in silence, which lost every
      // saved pack, archive and custom source with nothing said. It is recorded
      // now, so the loss is visible in Diagnostics instead of being a mystery.
      AppErrors.record(error, stack, where: 'maps.state');
    }
  }

  /// Writes the map state.
  ///
  /// Every caller is `unawaited`, so a throw here used to become an unhandled
  /// async error: a full disk or a read-only preferences store would surface as
  /// a crash-report entry with no sentence, and the state would silently stop
  /// being saved. It is recorded instead, which is what Diagnostics shows.
  Future<void> _save() async {
    try {
      await _saveUnsafe();
    } catch (error, stack) {
      AppErrors.record(error, stack, where: 'maps.save');
    }
  }

  Future<void> _saveUnsafe() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await Prefs.setString(prefs,
        prefsKey,
        jsonEncode(<String, Object?>{
          'budgetMb': budgetMb,
          'viewKeep': viewKeepDays,
          'sources': <Object>[for (final MapSource s in _custom) s.toJson()],
          'packs': <Object>[for (final MapPack p in packs) p.toJson()],
          'layers': <Object>[for (final EventLayer l in layers) l.toJson()],
          'archives': <Object>[for (final MapArchive a in archives) a.toJson()],
          'wifiOnly': wifiOnlyArchives,
        }));
  }

  void _changed() {
    if (isDisposed) return;
    unawaited(_save());
    notifyListeners();
  }

  @override
  void dispose() {
    _retry?.cancel();
    _sweep?.cancel();
    _trim?.cancel();
    for (final Future<PmTilesArchive> a in _openArchives.values) {
      unawaited(a.then((PmTilesArchive x) => x.close(), onError: (Object _) {}));
    }
    _openArchives.clear();
    unawaited(_store?.flush());
    _store?.dispose();
    super.dispose();
  }

  // ---- network state -----------------------------------------------

  void _noteFetch(FetchStatus s) {
    if (s == FetchStatus.failed) {
      lastFetchOk = false;
      _backoffS = _backoffS == 0
          ? math.max(1, retryFloor.inSeconds)
          : math.min(_backoffS * 2, 900);
      _offlineUntilMs = _now + _backoffS * 1000;
      return;
    }
    final bool wasOff = lastFetchOk == false;
    lastFetchOk = true;
    _backoffS = 0;
    _offlineUntilMs = 0;
    if (wasOff) _wakeWaiting();
  }

  bool _gated(String sourceId) {
    final _SourceHealth? h = _health[sourceId];
    return h != null && _now < h.untilMs;
  }

  /// Outcome of a viewing fetch for [src]. Failures only gate that source,
  /// and only after [viewFailuresBeforeBackoff] in a row; the wait doubles
  /// to 900 s and is jittered +-20% so many phones (or many sources) do
  /// not retry in lockstep. Any success clears the source and, through
  /// [_noteFetch], wakes parked packs exactly as before.
  void _noteView(MapSource src, FetchStatus s) {
    final _SourceHealth h = _health.putIfAbsent(src.id, _SourceHealth.new);
    if (s == FetchStatus.failed) {
      h.fails++;
      if (h.fails >= viewFailuresBeforeBackoff) {
        h.step = h.step == 0
            ? math.max(1, retryFloor.inSeconds)
            : math.min(h.step * 2, 900);
        final double jitter = 0.8 + 0.4 * _random.nextDouble();
        h.untilMs = _now + (h.step * 1000 * jitter).round();
        lastFetchOk = false;
      }
      return;
    }
    h.fails = 0;
    h.step = 0;
    h.untilMs = 0;
    _noteFetch(s);
  }

  /// Back online: every pack that was waiting picks up where it was.
  void _wakeWaiting() {
    bool any = false;
    for (final MapPack p in packs) {
      if (p.state == PackState.waitingForNetwork) {
        p.state = p.updateStartedMs != null
            ? PackState.updating
            : PackState.downloading;
        any = true;
      }
    }
    for (final MapArchive a in archives) {
      if (a.state == ArchiveState.waitingForNetwork) {
        a.state = ArchiveState.downloading;
        any = true;
      }
    }
    if (any) {
      _changed();
      unawaited(_pump());
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    final Duration wait = Duration(seconds: _backoffS) > retryFloor
        ? Duration(seconds: _backoffS)
        : retryFloor;
    _retry = Timer(wait, () {
      if (isDisposed) return;
      _offlineUntilMs = 0;
      for (final MapPack p in packs) {
        if (p.state == PackState.waitingForNetwork) {
          p.state = p.updateStartedMs != null
              ? PackState.updating
              : PackState.downloading;
        }
      }
      for (final MapArchive a in archives) {
        if (a.state == ArchiveState.waitingForNetwork) {
          a.state = ArchiveState.downloading;
        }
      }
      unawaited(_pump());
    });
  }

  // ---- tiles for the map views -------------------------------------

  /// Bytes for one tile: the store first, the network if we must.
  /// Stale view tiles are revalidated (If-None-Match) when online and
  /// shown as-is when not; pack tiles are never refetched by viewing.
  Future<Uint8List?> loadTile(MapSource src, int z, int x, int y) async =>
      (await loadTileDetailed(src, z, x, y)).bytes;

  /// [loadTile] plus the one distinction the vector layer needs: "the
  /// server has nothing here" (draw an empty tile) versus "could not reach
  /// it" (leave the tile to be asked for again).
  /// Network fetches in flight, keyed by tile. A pan that returns to a tile
  /// before its first request lands must not open a second one: the library
  /// asks for the same coordinate again as soon as it is visible, and the
  /// gate would happily run both.
  final Map<String, Future<FetchResult?>> _inflight =
      <String, Future<FetchResult?>>{};

  /// [_viewFetch], but one request per tile at a time.
  Future<FetchResult?> _viewFetchOnce(MapSource src, int z, int x, int y,
      {String? etag, int? ifModifiedSinceMs}) {
    final String key = TileStore.keyOf(src.id, z, x, y);
    final Future<FetchResult?>? running = _inflight[key];
    if (running != null) return running;
    final Future<FetchResult?> f = _viewFetch(src, z, x, y,
        etag: etag, ifModifiedSinceMs: ifModifiedSinceMs);
    _inflight[key] = f;
    return f.whenComplete(() {
      if (identical(_inflight[key], f)) _inflight.remove(key);
    });
  }

  /// True when nothing is fetching: no request running and none queued.
  /// Warm-up work only runs here, so it can never delay a visible tile.
  bool get viewIdle => viewGate.running == 0 && viewGate.queued == 0;

  /// Whether the store already holds this tile (from any pack or view).
  bool hasTile(MapSource src, int z, int x, int y) =>
      _store?.has(TileStore.keyOf(src.id, z, x, y)) ?? false;

  /// Fetch tiles the user is about to need, one at a time, and only while
  /// the map is idle. A pan that settles leaves its surrounding ring on
  /// disk, so the next pan paints from storage instead of the network.
  ///
  /// Deliberately not a priority queue: it runs sequentially through
  /// [loadTileDetailed], which means it obeys the same gate, backoff,
  /// budget and expiry rules as a visible tile, and it stops the moment a
  /// real request arrives.
  /// Bumped whenever the view moves. A prefetch loop that started for an older
  /// view stops at its next tile instead of walking a queue for a place the
  /// user has already left.
  int _warmGeneration = 0;

  /// Abandon any warm-up in flight. Called when the camera moves and before a
  /// new warm-up starts, so exactly one generation of warm work is ever alive.
  void cancelPrefetch() => _warmGeneration++;

  /// The generation a warm-up should carry so it can tell it has been cancelled.
  int get warmGeneration => _warmGeneration;

  Future<int> prefetch(MapSource src, Iterable<(int, int, int)> coords,
      {int limit = 24, int? generation}) async {
    if (!online || _gated(src.id) || usedBytes >= budgetBytes) return 0;
    int got = 0;
    for (final (int z, int x, int y) in coords) {
      // A moved camera, a new generation, or a visible tile waiting: the queue
      // dies here rather than finishing a list nobody is looking at.
      if (generation != null && generation != _warmGeneration) break;
      if (got >= limit || isDisposed || !viewIdle || !online) break;
      if (hasTile(src, z, x, y) || _absent.contains(TileStore.keyOf(src.id, z, x, y))) {
        continue;
      }
      final TileLoad t = await loadTileDetailed(src, z, x, y);
      if (t.bytes != null) got++;
    }
    return got;
  }

  /// Which tiles the map has actually drawn, so an overlay can refuse to be
  /// the only thing on a black screen.
  ///
  /// The density hexagons are vector shapes over the basemap: with no basemap
  /// under them they floated over the background colour, which reads as a
  /// rendering fault rather than as "the tiles have not arrived". `loadTile`
  /// records every tile it served (from the store, a pack, or the network), and
  /// the map asks what share of the tiles it is looking at are ready.
  ///
  /// Bounded and cleared with the view cache: this is a hint about right now,
  /// not a record of everything ever fetched.
  final Set<String> _tilesDrawn = <String>{};
  static const int _tilesDrawnCap = 4096;

  /// Bumped when a tile is added to [_tilesDrawn]. An overlay memoises on it, so
  /// a cell appears when the tile under it does and the field is not re-filtered
  /// for nothing.
  int _tilesReadyRevision = 0;
  int get tilesReadyRevision => _tilesReadyRevision;

  void _noteReady(MapSource src, int z, int x, int y) {
    if (_tilesDrawn.length >= _tilesDrawnCap) _tilesDrawn.clear();
    if (_tilesDrawn.add(TileStore.keyOf(src.id, z, x, y))) {
      _tilesReadyRevision++;
    }
  }

  /// Test seam: treat every tile as served.
  ///
  /// The density field is drawn only over ground the map has drawn, so a widget
  /// test with no tiles has no field at all. A test that is about the field
  /// rather than about tiles sets this instead of standing up a tile server.
  @visibleForTesting
  bool assumeTilesReady = false;

  /// Whether this tile has been served to the map since the app started.
  bool tileReady(MapSource src, int z, int x, int y) =>
      assumeTilesReady ||
      _tilesDrawn.contains(TileStore.keyOf(src.id, z, x, y));

  /// How much of [box] at [z] the map has already drawn, 0..1.
  ///
  /// One tile range, no per-cell bookkeeping: an overlay asks once per rebuild
  /// whether the ground under it exists, and the answer costs one set lookup per
  /// visible tile (a dozen at street zoom).
  double tileCoverage(MapSource src, GeoBox box, int z) {
    final TileRange r = tileRange(box, z);
    final int total = r.count;
    if (total <= 0) return 1;
    int ready = 0;
    for (int x = r.minX; x <= r.maxX; x++) {
      for (int y = r.minY; y <= r.maxY; y++) {
        if (tileReady(src, z, x, y)) ready++;
      }
    }
    return ready / total;
  }

  /// A source may require a longer life than the server advertises.
  @visibleForTesting
  Duration tileTtl(Duration? server, MapSource src) {
    final Duration d = server ?? viewMaxAgeDefault;
    return d < src.minCacheAge ? src.minCacheAge : d;
  }

  /// [loadTileDetailed] with the readiness note, so every consumer counts.
  ///
  /// The raster layer calls [loadTile] and the vector layer calls this one
  /// directly, and only the first of those used to record the tile. The map
  /// draws vector tiles by default, so the density field's "is this ground
  /// drawn?" test answered no for every cell on every skin and the hexagons
  /// vanished. One wrapper, so a new tile consumer cannot miss it again.
  Future<TileLoad> loadTileDetailed(MapSource src, int z, int x, int y) async {
    final TileLoad t = await _loadTileDetailed(src, z, x, y);
    if (t.bytes != null) _noteReady(src, z, x, y);
    return t;
  }

  Future<TileLoad> _loadTileDetailed(MapSource src, int z, int x, int y) async {
    await ready;
    if (src.id == kOsmVector.id && archives.isNotEmpty) {
      final TileLoad? a = await _fromArchives(z, x, y);
      if (a != null) return a;
    }
    final TileStore store = _store!;
    final String key = TileStore.keyOf(src.id, z, x, y);
    final TileMeta? meta = store.meta(key);
    if (meta != null) {
      final Uint8List? held = await store.read(key);
      if (held != null) {
        if (meta.expiresMs > _now || !meta.viewOnly || _gated(src.id)) {
          return TileLoad(held);
        }
        final FetchResult? r = await _viewFetchOnce(src, z, x, y,
            etag: meta.etag, ifModifiedSinceMs: meta.fetchedMs);
        if (r == null) return TileLoad(held);
        if (r.status == FetchStatus.notModified) {
          store.revalidated(key, tileTtl(r.maxAge, src));
        } else if (r.status == FetchStatus.ok && r.bytes != null) {
          await store.write(key, r.bytes!,
              maxAge: tileTtl(r.maxAge, src), etag: r.etag);
          _scheduleTrim();
          return TileLoad(r.bytes);
        }
        return TileLoad(held);
      }
    }
    if (_absent.contains(key)) return const TileLoad(null, missing: true);
    if (_gated(src.id)) return const TileLoad(null);
    final FetchResult? r = await _viewFetchOnce(src, z, x, y);
    if (r == null) return const TileLoad(null);
    if (r.status == FetchStatus.missing) {
      if (_absent.length >= _absentCap) _absent.clear();
      _absent.add(key);
      return const TileLoad(null, missing: true);
    }
    if (r.status != FetchStatus.ok || r.bytes == null) {
      return const TileLoad(null);
    }
    await store.write(key, r.bytes!,
        maxAge: tileTtl(r.maxAge, src), etag: r.etag);
    _scheduleTrim();
    return TileLoad(r.bytes);
  }

  /// One viewing fetch through [viewGate]. null = superseded in the queue
  /// before it started (never asked, never counted as a failure).
  Future<FetchResult?> _viewFetch(MapSource src, int z, int x, int y,
      {String? etag, int? ifModifiedSinceMs}) async {
    try {
      final FetchResult r = await viewGate.run(() => _fetch(
          src.tileUri(z, x, y),
          etag: etag,
          ifModifiedSinceMs: ifModifiedSinceMs));
      _noteView(src, r.status);
      return r;
    } on TileDropped {
      return null;
    }
  }

  /// R114 — the coarsest useful stand-in for a tile that is not on disk.
  ///
  /// Looks in the store only, never at the network: a miss here is a
  /// *drawing* problem, and asking the server for six ancestors per visible
  /// tile would turn one slow pan into a flood. The nearest ancestor wins, so
  /// a z12 miss with z10 held draws at 1/4 scale rather than jumping to the
  /// world tile.
  Future<TileAncestor?> ancestorTile(MapSource src, int z, int x, int y,
      {int maxUp = 6}) async {
    final TileStore? store = _store;
    if (store == null) return null;
    await ready;
    final int depth = math.min(maxUp, z);
    for (int up = 1; up <= depth; up++) {
      final TileAncestorCoord? a = ancestorOf(z, x, y, up);
      if (a == null) continue;
      final String key = TileStore.keyOf(src.id, a.z, a.x, a.y);
      if (!store.has(key)) continue;
      final Uint8List? held = await store.read(key);
      if (held == null) continue;
      return TileAncestor(bytes: held, coord: a);
    }
    return null;
  }

  /// The zoom range the packs of [src] cover, if any pack holds this source.
  /// Null means "no pack", which is not the same as "this zoom is missing":
  /// the map only explains a gap when a pack exists and the zoom is outside
  /// it.
  ({int minZoom, int maxZoom})? packZoomSpan(MapSource src) {
    int? lo;
    int? hi;
    for (final MapPack p in packs) {
      if (p.sourceId != src.id) continue;
      lo = lo == null ? p.minZoom : math.min(lo, p.minZoom);
      hi = hi == null ? p.maxZoom : math.max(hi, p.maxZoom);
    }
    return lo == null || hi == null ? null : (minZoom: lo, maxZoom: hi);
  }

  void _scheduleTrim() {
    _trim ??= Timer(const Duration(seconds: 5), () {
      _trim = null;
      unawaited(_trimView());
    });
  }

  Future<void> _trimView() async {
    final TileStore? store = _store;
    if (store == null) return;
    await store.trimView(
      maxViewBytes: math.max(0, budgetBytes - pinnedBytes),
      maxIdle: Duration(days: viewKeepDays),
    );
    notifyListeners();
  }

  // ---- packs -------------------------------------------------------

  /// Plan check without side effects; null = would be accepted
  /// (online-ness is only known by trying).
  PackRefusal? checkPack({
    required String name,
    required MapSource source,
    required GeoBox box,
    required int minZoom,
    required int maxZoom,
  }) {
    if (name.trim().isEmpty) return PackRefusal.noName;
    if (!source.allowsPacks) return PackRefusal.sourceViewOnly;
    if (!source.covers(box)) return PackRefusal.outsideCoverage;
    if (tileCount(box, minZoom, maxZoom) > maxPackTiles) {
      return PackRefusal.tooManyTiles;
    }
    if (pinnedBytes + estimateBytes(source, box, minZoom, maxZoom) >
        budgetBytes) {
      return PackRefusal.overBudget;
    }
    return null;
  }

  /// Create and start a pack. Setup is online-only: the first tile is
  /// fetched here and, if that fails, nothing is created.
  Future<PackRefusal?> createPack({
    required String name,
    required MapSource source,
    required GeoBox box,
    required int minZoom,
    required int maxZoom,
    int keepDays = 0,
  }) async {
    await ready;
    final PackRefusal? why = checkPack(
        name: name,
        source: source,
        box: box,
        minZoom: minZoom,
        maxZoom: maxZoom);
    if (why != null) return why;
    // The probe is the first tile not already held, so setting up a
    // pack over an area you have browsed costs no duplicate fetch.
    final TileStore store = _store!;
    (int, int, int) first = tilesIn(box, minZoom, maxZoom).first;
    for (final (int, int, int) t in tilesIn(box, minZoom, maxZoom).take(1000)) {
      if (!store.has(TileStore.keyOf(source.id, t.$1, t.$2, t.$3))) {
        first = t;
        break;
      }
    }
    final String firstKey =
        TileStore.keyOf(source.id, first.$1, first.$2, first.$3);
    final TileMeta? held = store.meta(firstKey);
    final FetchResult probe = await _fetch(
        source.tileUri(first.$1, first.$2, first.$3),
        etag: held?.etag,
        ifModifiedSinceMs: held?.fetchedMs);
    _noteFetch(probe.status);
    if (probe.status == FetchStatus.failed) return PackRefusal.offline;
    final MapPack p = MapPack(
      id: 'p${_now.toRadixString(36)}',
      name: name.trim(),
      sourceId: source.id,
      box: box,
      minZoom: minZoom,
      maxZoom: maxZoom,
      createdMs: _now,
      total: tileCount(box, minZoom, maxZoom),
      keepDays: keepDays,
    );
    if (probe.status == FetchStatus.ok && probe.bytes != null) {
      await store.write(firstKey, probe.bytes!,
          maxAge: probe.maxAge ?? packMaxAgeDefault,
          etag: probe.etag,
          packId: p.id);
    } else if (probe.status == FetchStatus.notModified) {
      store.revalidated(firstKey, probe.maxAge ?? packMaxAgeDefault,
          packId: p.id);
    }
    packs.add(p);
    _changed();
    unawaited(_pump());
    return null;
  }

  void pausePack(MapPack p) {
    if (p.state == PackState.complete) return;
    p.state = PackState.paused;
    _changed();
  }

  void resumePack(MapPack p) {
    if (p.state == PackState.complete) return;
    p.state =
        p.updateStartedMs != null ? PackState.updating : PackState.downloading;
    _offlineUntilMs = 0;
    _changed();
    unawaited(_pump());
  }

  /// Ask the server about every tile again (304s are cheap) and fill
  /// any gaps. Expiry restarts when the update finishes.
  void updatePack(MapPack p) {
    p
      ..state = PackState.updating
      ..updateStartedMs = _now
      ..done = 0
      ..missing = 0;
    _offlineUntilMs = 0;
    _changed();
    unawaited(_pump());
  }

  Future<void> deletePack(MapPack p) async {
    packs.remove(p);
    p.state = PackState.paused; // stops a running pass at its next tile
    await _store?.releasePack(p.id);
    _changed();
  }

  void setPackKeep(MapPack p, int days) {
    p.keepDays = days;
    _changed();
  }

  Future<void>? _pumpRun;

  /// Completes when no download pass is running (tests).
  @visibleForTesting
  Future<void> idle() async {
    while (_pumpRun != null) {
      await _pumpRun;
    }
  }

  Future<void> _pump() {
    if (_pumping || isDisposed || !loaded) return Future<void>.value();
    final Future<void> run = _pumpBody();
    _pumpRun = run;
    return run.whenComplete(() {
      if (identical(_pumpRun, run)) _pumpRun = null;
    });
  }

  Future<void> _pumpBody() async {
    _pumping = true;
    try {
      await _promoteWifiParked();
      while (!isDisposed) {
        MapPack? next;
        for (final MapPack p in packs) {
          if (p.state == PackState.downloading ||
              p.state == PackState.updating) {
            next = p;
            break;
          }
        }
        if (next != null) {
          if (!await _runPack(next)) break;
          continue;
        }
        MapArchive? arch;
        for (final MapArchive a in archives) {
          if (a.state == ArchiveState.downloading) {
            arch = a;
            break;
          }
        }
        if (arch == null) break;
        if (await _parkedForWifi(arch)) break;
        if (!await _runArchive(arch)) break;
      }
    } finally {
      _pumping = false;
    }
  }

  /// One pass over a pack. False when the network went away.
  ///
  /// [concurrency] workers pull from one iterator, so the pass is limited by the
  /// host's latency rather than by a sleep between requests. The budget check is
  /// serialised: two workers that both saw room would both spend it.
  Future<bool> _runPack(MapPack p) async {
    final TileStore store = _store!;
    final MapSource? src = sourceById(p.sourceId);
    if (src == null) {
      p.state = PackState.paused;
      _changed();
      return true;
    }
    int done = 0;
    int missing = 0;
    // Budget checks use the larger of the plan and what this server
    // actually sends, so a heavy server can't overshoot by much.
    int perTile = src.bytesPerTile;
    final Iterator<(int, int, int)> tiles =
        tilesIn(p.box, p.minZoom, p.maxZoom).iterator;
    // The rate is measured from here, so the row can say how long is left.
    p
      ..passStartedMs = _now
      ..passStartDone = p.done;
    bool stop = false;
    bool networkGone = false;
    // Bytes this pass has promised to the disk but not yet written. With more
    // than one worker in flight, checking the budget per tile is not enough: two
    // workers that both saw room would both spend it, and the pack would land
    // over budget by up to `concurrency` tiles.
    int reserved = 0;

    Future<void> worker() async {
      while (!stop) {
        if (isDisposed || !packs.contains(p)) {
          stop = true;
          return;
        }
        if (p.state != PackState.downloading && p.state != PackState.updating) {
          stop = true;
          return;
        }
        // `moveNext` is synchronous, so two workers cannot take the same tile.
        if (!tiles.moveNext()) return;
        final (int z, int x, int y) = tiles.current;
        final String key = TileStore.keyOf(src.id, z, x, y);
        final TileMeta? meta = store.meta(key);
        final bool refresh = p.state == PackState.updating &&
            meta != null &&
            meta.fetchedMs < (p.updateStartedMs ?? 0);
        if (meta != null && !refresh) {
          store.addToPack(key, p.id);
          done++;
          _progress(p, done, missing);
          continue;
        }
        final int claim = perTile;
        if (meta == null) {
          if (!await _fitsSerial(claim + reserved)) {
            p
              ..state = PackState.overBudget
              ..done = done
              ..missing = missing;
            _changed();
            stop = true;
            return;
          }
          reserved += claim;
        }
        await _pacer.wait(pace);
        if (stop) return;
        final FetchResult r = await _fetch(src.tileUri(z, x, y),
            etag: refresh ? meta.etag : null,
            ifModifiedSinceMs: refresh ? meta.fetchedMs : null);
        _noteFetch(r.status);
        switch (r.status) {
          case FetchStatus.ok:
            if (!packs.contains(p)) {
              stop = true;
              return;
            }
            perTile = math.max(perTile, r.bytes!.length);
            await store.write(key, r.bytes!,
                maxAge: r.maxAge ?? packMaxAgeDefault,
                etag: r.etag,
                packId: p.id);
            reserved -= claim;
          case FetchStatus.notModified:
            store.revalidated(key, r.maxAge ?? packMaxAgeDefault, packId: p.id);
          case FetchStatus.missing:
            missing++;
            reserved -= claim;
          case FetchStatus.failed:
            reserved -= claim;
            p
              ..state = PackState.waitingForNetwork
              ..done = done
              ..missing = missing;
            _changed();
            _scheduleRetry();
            stop = true;
            networkGone = true;
            return;
        }
        done++;
        _progress(p, done, missing);
      }
    }

    await Future.wait(<Future<void>>[
      for (int i = 0; i < math.max(1, concurrency); i++) worker(),
    ]);
    if (networkGone) return false;
    if (stop) return true;
    p
      ..done = p.total
      ..missing = missing
      ..state = PackState.complete
      ..updatedMs = _now
      ..updateStartedMs = null
      ..passStartedMs = null;
    _changed();
    return true;
  }

  /// The shared request budget, so [concurrency] workers do not multiply the
  /// rate the pace was chosen to allow.
  final _Pacer _pacer = _Pacer();

  /// Serialises the budget check: it trims the view cache and then re-reads the
  /// total, and two workers interleaving that would both spend the same room.
  Future<void> _budgetTail = Future<void>.value();

  Future<bool> _fitsSerial(int bytes) {
    final Future<bool> next = _budgetTail.then((_) => _fits(bytes));
    _budgetTail = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  void _progress(MapPack p, int done, int missing) {
    p
      ..done = done
      ..missing = missing;
    // Every tile, not every twenty-fifth: the bar is the only thing a reader
    // watches during a download, and a bar that jumps in twenty-five-tile steps
    // reads as a stall. A notification is a rebuild of one row, and the pass is
    // rate-limited anyway.
    if (done % 500 == 0) unawaited(_save());
    notifyListeners();
  }

  /// Tiles per second over the current pass, or null before it can be measured.
  double? packRate(MapPack p) {
    final int? started = p.passStartedMs;
    if (started == null) return null;
    final int elapsed = _now - started;
    if (elapsed < 1000) return null;
    final int moved = p.done - p.passStartDone;
    if (moved <= 0) return null;
    return moved * 1000 / elapsed;
  }

  /// How long the rest of the pass should take at the rate so far.
  Duration? packEta(MapPack p) {
    final double? rate = packRate(p);
    if (rate == null || rate <= 0) return null;
    final int left = p.total - p.done;
    if (left <= 0) return null;
    return Duration(milliseconds: (left * 1000 / rate).round());
  }

  /// Room for [bytes] more pinned data? Evicts view tiles to make it.
  Future<bool> _fits(int bytes) async {
    if (usedBytes + bytes <= budgetBytes) return true;
    final int over = usedBytes + bytes - budgetBytes;
    await _store!.trimView(maxViewBytes: math.max(0, viewBytes - over));
    return usedBytes + bytes <= budgetBytes;
  }

  // ---- budget + expiry ---------------------------------------------

  Future<void> setBudgetMb(int mb) async {
    budgetMb = mb;
    await _trimView();
    // A larger budget lets an over-budget pack carry on.
    if (pinnedBytes < budgetBytes) {
      for (final MapPack p in packs) {
        if (p.state == PackState.overBudget) {
          p.state = p.updateStartedMs != null
              ? PackState.updating
              : PackState.downloading;
        }
      }
      unawaited(_pump());
    }
    _changed();
  }

  Future<void> setViewKeepDays(int days) async {
    viewKeepDays = days;
    await _trimView();
    _changed();
  }

  Future<void> clearViewCache() async {
    await _store?.clearView();
    _changed();
  }

  /// Delete every pack and layer past its keep-for, and view tiles
  /// idle past theirs. Runs at load and hourly.
  /// The post-load chores: expiry sweep, the view trim, and the hourly timer.
  Future<void> _housekeep() async {
    try {
      await sweepExpired();
      _sweep = Timer.periodic(const Duration(hours: 1), (_) => sweepExpired());
    } catch (_) {
      // A failed sweep must not take the map with it.
    }
  }

  Future<void> sweepExpired() async {
    if (!loaded) return;
    final int now = _now;
    for (final MapPack p in List<MapPack>.of(packs)) {
      final int? at = p.expiresAtMs;
      if (at != null && at <= now) {
        await deletePack(p);
      }
    }
    for (final EventLayer l in List<EventLayer>.of(layers)) {
      final int? at = l.expiresAtMs;
      if (at != null && at <= now) await deleteLayer(l);
    }
    for (final MapArchive a in List<MapArchive>.of(archives)) {
      final int? at = a.expiresAtMs;
      if (a.complete && at != null && at <= now) await deleteArchive(a);
    }
    await _trimView();
  }

  // ---- region archives (R81) ---------------------------------------

  /// The root of archives on disk (null until [load]).
  Directory? get _archiveDir =>
      _root == null ? null : Directory('${_root!.path}/archives');

  File _partFile(MapArchive a) => File('${_archiveDir!.path}/${a.id}.part');
  File _archiveFile(MapArchive a) => File('${_archiveDir!.path}/${a.id}.pmtiles');

  /// Sizes on disk, so the budget counts a half-downloaded archive.
  Future<void> _measureArchives() async {
    _archiveSize.clear();
    for (final MapArchive a in archives) {
      final File f = a.complete ? _archiveFile(a) : _partFile(a);
      if (await f.exists()) {
        _archiveSize[a.id] = await f.length();
      } else if (a.complete) {
        // The file went away behind our back: do not claim a region.
        a.state = ArchiveState.failed;
        a.failure = ArchiveFailure.notPmTiles;
      }
    }
  }

  /// Download one region as a single resumable PMTiles file.
  ///
  /// Setup is offline-safe (nothing is fetched here): the pump downloads,
  /// resuming by byte range after a lost connection or a restart.
  /// [expectedBytes] and [sha256] are the host's published size and
  /// SHA-256; with them the file is verified before it is used. Without
  /// them the server's length is trusted and only the PMTiles structure is
  /// checked. The budget check uses [expectedBytes] and, whatever it says,
  /// the download stops if the real bytes would break the budget.
  Future<ArchiveRefusal?> addArchive({
    required String name,
    required String url,
    int? expectedBytes,
    String? sha256,
    int keepDays = 0,
  }) async {
    await ready;
    if (name.trim().isEmpty) return ArchiveRefusal.noName;
    final Uri? u = Uri.tryParse(url.trim());
    if (u == null || u.scheme != 'https' || u.host.isEmpty) {
      return ArchiveRefusal.badUrl;
    }
    if (archives.any((MapArchive a) => a.url == u.toString())) {
      return ArchiveRefusal.duplicate;
    }
    if (expectedBytes != null && pinnedBytes + expectedBytes > budgetBytes) {
      return ArchiveRefusal.overBudget;
    }
    if (expectedBytes != null) {
      final int? free = await _diskSpace.allocatableBytes();
      if (!hasRoomFor(free, expectedBytes)) return ArchiveRefusal.notEnoughSpace;
    }
    final MapArchive a = MapArchive(
      id: 'a${_now.toRadixString(36)}',
      name: name.trim(),
      url: u.toString(),
      createdMs: _now,
      expectedBytes: expectedBytes,
      sha256: sha256?.trim().toLowerCase(),
      keepDays: keepDays,
    );
    archives.add(a);
    _changed();
    unawaited(_pump());
    return null;
  }

  void pauseArchive(MapArchive a) {
    if (a.state == ArchiveState.downloading ||
        a.state == ArchiveState.waitingForNetwork) {
      a.state = ArchiveState.paused;
      _changed();
    }
  }

  void resumeArchive(MapArchive a) {
    if (a.state == ArchiveState.paused ||
        a.state == ArchiveState.overBudget ||
        a.state == ArchiveState.waitingForWifi) {
      a.state = ArchiveState.downloading;
      _changed();
      unawaited(_pump());
    }
  }

  void setArchiveKeep(MapArchive a, int days) {
    a.keepDays = days;
    _changed();
  }

  /// Wi-Fi-only for region downloads. Turning it off lets a metered link
  /// through, and the next pump picks up anything parked in
  /// [ArchiveState.waitingForWifi].
  void setWifiOnlyArchives(bool value) {
    if (wifiOnlyArchives == value) return;
    wifiOnlyArchives = value;
    _changed();
    unawaited(_pump());
  }

  /// Reads the bundled pack list, then the published one when this build was
  /// pointed at it. Safe to call more than once; a failed remote fetch keeps
  /// the bundled list and records why.
  Future<void> refreshCatalog() async {
    if (catalogLoading) return;
    catalogLoading = true;
    // No notify here: the screen calls this from initState, which runs inside
    // a build pass, so notifying now is "setState during build". The loading
    // flag matters to the screen only as "the list is not ready yet", which
    // is the state it already rendered.
    try {
      final PackCatalogLoader loader = PackCatalogLoader(
        bundled: _bundledCatalog,
        url: catalogUrl,
        remote: catalogUrl.isEmpty ? null : _catalogFetcher,
      );
      catalog = await loader.load();
    } finally {
      catalogLoading = false;
      notifyListeners();
    }
  }

  static Future<String> _bundleCatalogText() =>
      rootBundle.loadString('assets/maps/packs.json');

  static Future<String> _httpCatalogText(Uri url) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final HttpClientRequest req = await client.getUrl(url);
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        throw HttpException('catalogue ${resp.statusCode}', uri: url);
      }
      return await resp.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> deleteArchive(MapArchive a) async {
    archives.remove(a);
    if (a.state == ArchiveState.downloading) a.state = ArchiveState.paused;
    await _closeArchive(a.id);
    for (final File f in <File>[_partFile(a), _archiveFile(a)]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    _archiveSize.remove(a.id);
    _changed();
  }

  /// Moves anything parked on the Wi-Fi-only rule back into the queue.
  ///
  /// Two things un-park a download: the preference turned off, or an
  /// unmetered link arriving. Checking the link here rather than only in
  /// [setWifiOnlyArchives] is what lets a pack sitting in
  /// [ArchiveState.waitingForWifi] resume on its own when the phone joins
  /// Wi-Fi, without the user finding it again.
  Future<void> _promoteWifiParked() async {
    for (final MapArchive a in archives) {
      if (a.state != ArchiveState.waitingForWifi) continue;
      if (wifiOnlyArchives && await _networkGate.unmetered() == false) {
        continue;
      }
      a.state = ArchiveState.downloading;
      _changed();
    }
  }

  /// True when [a] must wait for an unmetered link, having parked it.
  Future<bool> _parkedForWifi(MapArchive a) async {
    if (!wifiOnlyArchives) return false;
    if (await _networkGate.unmetered() != false) return false;
    a.state = ArchiveState.waitingForWifi;
    _changed();
    _scheduleRetry();
    return true;
  }

  /// One download attempt. False when the network went away.
  Future<bool> _runArchive(MapArchive a) async {
    try {
      await _archiveDir!.create(recursive: true);
    } on FileSystemException {
      // The directory can vanish under a queued download (storage cleared or
      // evicted). That is a local failure with its own sentence, not an
      // unhandled async error that leaves the archive "downloading" for ever.
      await _rejectArchive(a, ArchiveFailure.storage);
      return true;
    }
    final File part = _partFile(a);
    final int own = _archiveSize[a.id] ?? 0;
    int lastNotify = 0;
    final DownloadResult r = await downloadResumable(
      fetch: _archiveFetch,
      url: Uri.parse(a.url),
      part: part,
      etag: a.etag,
      shouldStop: () =>
          isDisposed ||
              !archives.contains(a) ||
              a.state != ArchiveState.downloading,
      // Room for THIS file: the budget less everything else pinned.
      allowedBytes: () => budgetBytes - (pinnedBytes - (_archiveSize[a.id] ?? own)),
      onProgress: (int bytes, int? total) {
        _archiveSize[a.id] = bytes;
        if (_now - lastNotify > 500 && !isDisposed) {
          lastNotify = _now;
          notifyListeners();
        }
      },
    );
    _archiveSize[a.id] = r.bytes;
    a.etag = r.etag ?? a.etag;
    if (isDisposed || !archives.contains(a)) return true;
    switch (r.end) {
      case DownloadEnd.stopped:
        _changed();
        return true;
      case DownloadEnd.overBudget:
        a.state = ArchiveState.overBudget;
        _changed();
        return true;
      case DownloadEnd.notFound:
        await _rejectArchive(a, ArchiveFailure.notFound);
        return true;
      case DownloadEnd.networkLost:
        a.state = ArchiveState.waitingForNetwork;
        _noteFetch(FetchStatus.failed);
        _changed();
        _scheduleRetry();
        return false;
      case DownloadEnd.complete:
        _noteFetch(FetchStatus.ok);
        await _acceptArchive(a, r);
        return true;
    }
  }

  /// A finished file is only trusted after size, hash and structure pass.
  Future<void> _acceptArchive(MapArchive a, DownloadResult r) async {
    final File part = _partFile(a);
    final int? want = a.expectedBytes ?? r.total;
    if (want != null && r.bytes != want) {
      // Awaited rather than returned inside the try: an unawaited return there
      // is what the analyzer's `unawaited_return_in_try_block` flags, and this
      // file was the reason the project carried two standing warnings.
      await _rejectArchive(a, ArchiveFailure.badSize);
      return;
    }
    if (a.sha256 != null && await sha256OfFile(part) != a.sha256) {
      return _rejectArchive(a, ArchiveFailure.badHash);
    }
    PmTilesArchive? opened;
    try {
      opened = await PmTilesArchive.open(await PmFileSource.open(part.path));
      if (opened.header.tileType != PmTileType.mvt) {
        await opened.close();
        await _rejectArchive(a, ArchiveFailure.notPmTiles);
        return;
      }
      final Set<String> layers = await opened.vectorLayerIds();
      if (!layers.containsAll(kArchiveRequiredLayers)) {
        await opened.close();
        await _rejectArchive(a, ArchiveFailure.wrongSchema);
        return;
      }
      final PmHeader h = opened.header;
      a
        ..minZoom = h.minZoom
        ..maxZoom = h.maxZoom
        ..west = h.minLon
        ..south = h.minLat
        ..east = h.maxLon
        ..north = h.maxLat;
      await opened.close();
    } catch (_) {
      await opened?.close();
      await _rejectArchive(a, ArchiveFailure.notPmTiles);
      return;
    }
    final File dest = _archiveFile(a);
    await _closeArchive(a.id);
    if (await dest.exists()) await dest.delete();
    await part.rename(dest.path);
    a
      ..state = ArchiveState.complete
      ..failure = null
      ..updatedMs = _now;
    _archiveSize[a.id] = r.bytes;
    _changed();
  }

  Future<void> _closeArchive(String id) async {
    final Future<PmTilesArchive>? f = _openArchives.remove(id);
    if (f == null) return;
    try {
      await (await f).close();
    } catch (_) {}
  }

  Future<void> _rejectArchive(MapArchive a, ArchiveFailure why) async {
    try {
      final File f = _partFile(a);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    _archiveSize[a.id] = 0;
    a
      ..state = ArchiveState.failed
      ..failure = why
      ..etag = null;
    _changed();
  }

  /// True when a finished region archive covers [box] at zoom [z].
  ///
  /// This is the question the map asks before it tells a user that the area
  /// on screen is outside every offline pack: a pack answers a whole bbox and
  /// a zoom range, so "do I have this view offline" is a box test, not a
  /// per-tile guess.
  bool archiveCovers(GeoBox box, int z) {
    for (final MapArchive a in archives) {
      if (!a.complete || a.minZoom == null || a.maxZoom == null) continue;
      if (z < a.minZoom! || z > a.maxZoom!) continue;
      final GeoBox pack = GeoBox(
          south: a.south!, west: a.west!, north: a.north!, east: a.east!);
      if (pack.intersects(box)) return true;
    }
    return false;
  }

  /// Archive-first read for the vector basemap: a tile inside a complete
  /// archive's extent and zoom range is answered from the file (a seek,
  /// no network) and an empty cell there is final ("missing"). Anything
  /// outside every archive returns null and falls through to the view
  /// cache and network.
  Future<TileLoad?> _fromArchives(int z, int x, int y) async {
    for (final MapArchive a in archives) {
      if (!a.complete || a.minZoom == null || z < a.minZoom! || z > a.maxZoom!) {
        continue;
      }
      final TileRange r = tileRange(
          GeoBox(south: a.south!, west: a.west!, north: a.north!, east: a.east!),
          z);
      if (x < r.minX || x > r.maxX || y < r.minY || y > r.maxY) continue;
      try {
        final PmTilesArchive open = await (_openArchives[a.id] ??=
            PmFileSource.open(_archiveFile(a).path).then(PmTilesArchive.open));
        final Uint8List? bytes = await open.tile(z, x, y);
        return bytes == null
            ? const TileLoad(null, missing: true)
            : TileLoad(bytes);
      } catch (e) {
        // A damaged or vanished file must not blank the map: forget the
        // handle and let the network path answer.
        _openArchives.remove(a.id);
        if (kDebugMode) debugPrint('archive ${a.id} unreadable: $e');
      }
    }
    return null;
  }

  // ---- custom sources ----------------------------------------------

  /// Add a tile server. [allowsPacks] is the user's word that the
  /// server permits offline download (their own server, or one whose
  /// terms say so).
  MapSource? addCustomSource({
    required String name,
    required String urlTemplate,
    String attribution = '',
    bool allowsPacks = false,
    int maxZoom = 18,
  }) {
    if (name.trim().isEmpty || !MapSource.validTemplate(urlTemplate.trim())) {
      return null;
    }
    final MapSource s = MapSource(
      id: 'c${_now.toRadixString(36)}',
      name: name.trim(),
      urlTemplate: urlTemplate.trim(),
      attribution: attribution.trim(),
      allowsPacks: allowsPacks,
      maxNativeZoom: maxZoom,
      custom: true,
    );
    _custom.add(s);
    _changed();
    return s;
  }

  Future<void> removeCustomSource(MapSource s) async {
    for (final MapPack p
        in packs.where((MapPack p) => p.sourceId == s.id).toList()) {
      await deletePack(p);
    }
    _custom.removeWhere((MapSource c) => c.id == s.id);
    _changed();
  }

  // ---- event layers ------------------------------------------------

  File _layerFile(String id) => File('${_root!.path}/layers/$id.geojson');

  Future<LayerRefusal?> addLayer({
    required String name,
    required String url,
    int keepDays = 0,
  }) async {
    await ready;
    final Uri? u = Uri.tryParse(url.trim());
    if (u == null || u.scheme != 'https' || u.host.isEmpty) {
      return LayerRefusal.badUrl;
    }
    final EventLayer l = EventLayer(
      id: 'l${_now.toRadixString(36)}',
      name: name.trim().isEmpty ? u.pathSegments.last : name.trim(),
      url: u.toString(),
      addedMs: _now,
      updatedMs: _now,
      bytes: 0,
      features: 0,
      keepDays: keepDays,
    );
    final LayerRefusal? why = await _downloadLayer(l);
    if (why != null) return why;
    layers.add(l);
    _changed();
    return null;
  }

  Future<LayerRefusal?> refreshLayer(EventLayer l) async {
    final LayerRefusal? why = await _downloadLayer(l);
    if (why == null) _changed();
    return why;
  }

  Future<LayerRefusal?> _downloadLayer(EventLayer l) async {
    final FetchResult r =
        await _fetch(Uri.parse(l.url), maxBytes: maxLayerBytes);
    _noteFetch(r.status);
    if (r.tooLarge) return LayerRefusal.tooLarge;
    if (r.status == FetchStatus.failed) return LayerRefusal.offline;
    if (r.status != FetchStatus.ok || r.bytes == null) {
      return LayerRefusal.notGeoJson;
    }
    final Uint8List b = r.bytes!;
    // Still checked, because a fake fetcher in a test has no cap and a caller
    // may pass one larger than the budget check below.
    if (b.length > maxLayerBytes) return LayerRefusal.tooLarge;
    // **Off the UI isolate.** A layer may be ten megabytes, and decoding ten
    // megabytes of JSON plus walking every feature is seconds of work. Run on the
    // main isolate it is a frozen map and, measured on the handset on 2026-11-13,
    // three "not responding" dialogs whose trace showed the main thread executing
    // Dart for five seconds straight. `Isolate.run` copies the text in and the
    // shapes out, both plain values, so nothing crosses that cannot.
    final GeoShapes? shapes = await Isolate.run(
        () => parseGeoJson(utf8.decode(b, allowMalformed: true)));
    if (shapes == null) return LayerRefusal.notGeoJson;
    if (shapes.count == 0) return LayerRefusal.empty;
    if (pinnedBytes - l.bytes + b.length > budgetBytes) {
      return LayerRefusal.overBudget;
    }
    final File f = _layerFile(l.id);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(b);
    l
      ..bytes = b.length
      ..features = shapes.count
      ..updatedMs = _now;
    _shapes[l.id] = shapes;
    await _trimView();
    return null;
  }

  Future<void> deleteLayer(EventLayer l) async {
    layers.remove(l);
    _shapes.remove(l.id);
    try {
      await _layerFile(l.id).delete();
    } catch (_) {}
    _changed();
  }

  void setLayerVisible(EventLayer l, bool v) {
    l.visible = v;
    _changed();
  }

  void setLayerKeep(EventLayer l, int days) {
    l.keepDays = days;
    _changed();
  }

  /// Whether this layer's GeoJSON has already been parsed. A visible layer
  /// that is not loaded yet draws nothing (missing file, expired, or still
  /// reading), which the map's layer menu now shows instead of leaving the
  /// user with an empty map and a switch that claims to be on.
  bool isLayerLoaded(EventLayer l) => _shapes.containsKey(l.id);

  /// Parsed shapes for a layer, read from disk once.
  Future<GeoShapes?> shapesFor(EventLayer l) async {
    final GeoShapes? hit = _shapes[l.id];
    if (hit != null) return hit;
    await ready;
    try {
      // Same reason as `_downloadLayer`: a saved layer is the same size on the
      // way in as it was on the way down, so reopening a map after a restart hit
      // the same stall.
      final String text = await _layerFile(l.id).readAsString();
      final GeoShapes? s = await Isolate.run(() => parseGeoJson(text));
      if (s != null) _shapes[l.id] = s;
      return s;
    } catch (_) {
      return null;
    }
  }
}

/// Consecutive-failure state for one tile source's viewing fetches.
class _SourceHealth {
  int fails = 0;
  int step = 0; // seconds, doubles per gate opening
  int untilMs = 0;
}

/// A shared request budget for one download pass.
///
/// The pace used to be a sleep after every tile, which made the pass
/// latency-bound and left the rate at whatever one request plus one sleep
/// allowed. A token bucket keeps the same promise — no more than one request per
/// [pace] on average — while letting [MapsController.concurrency] workers overlap
/// their round trips, so the pass is limited by the host rather than by the
/// sleep.
class _Pacer {
  /// When the next request may go out.
  int _nextMs = 0;

  Future<void> wait(Duration pace) async {
    if (pace <= Duration.zero) return;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int at = _nextMs > now ? _nextMs : now;
    _nextMs = at + pace.inMilliseconds;
    final int delay = at - now;
    if (delay > 0) await Future<void>.delayed(Duration(milliseconds: delay));
  }
}
