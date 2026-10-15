// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'event_layer.dart';
import 'map_fetch.dart';
import 'map_pack.dart';
import 'map_source.dart';
import 'tile_math.dart';
import 'tile_store.dart';

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
enum LayerRefusal { badUrl, offline, notGeoJson, tooLarge, overBudget }

/// R61 — offline maps (issue #5): the tile cache, region packs, event
/// layers, the storage budget and expiry. See
/// `meshmore-sns-maps-spec.md`.
///
/// One download runs at a time, politely paced. Downloads are
/// opportunistic: a network failure parks the pack as "waiting for
/// network" and a backoff timer (or any successful map fetch, e.g. the
/// user panning a map) wakes it. A half-done pack still shows what it
/// has; packs fill lowest zoom first.
class MapsController extends ChangeNotifier {
  MapsController({
    Future<Directory> Function()? rootDir,
    MapFetcher? fetcher,
    DateTime Function()? clock,
    this.pace = const Duration(milliseconds: 150),
    String Function()? appVersion,
    this.prefsKey = 'maps.state.v1',
    this.retryFloor = const Duration(seconds: 30),
  })  : _rootDir = rootDir ?? _defaultRoot,
        _clock = clock ?? DateTime.now {
    _fetch = fetcher ??
        httpMapFetcher(() => mapUserAgent(appVersion?.call() ?? ''));
  }

  static Future<Directory> _defaultRoot() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/maps');

  /// Where state persists; the self-test uses its own so it never
  /// touches the user's packs.
  final String prefsKey;

  /// Shortest wait before a parked download tries again.
  final Duration retryFloor;

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
  final Duration pace;

  TileStore? _store;
  Directory? _root;
  final Completer<void> _ready = Completer<void>();

  final List<MapSource> _custom = <MapSource>[];
  final List<MapPack> packs = <MapPack>[];
  final List<EventLayer> layers = <EventLayer>[];
  final Map<String, GeoShapes> _shapes = <String, GeoShapes>{};

  int budgetMb = 500;
  int viewKeepDays = 30;

  bool _pumping = false;
  bool _disposed = false;
  Timer? _retry;
  Timer? _sweep;
  Timer? _trim;
  int _backoffS = 0;
  int _offlineUntilMs = 0;

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
  int get usedBytes => tileBytes + layerBytes;

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
    } catch (_) {
      _store ??= TileStore(Directory.systemTemp, clock: _clock);
    }
    _ready.complete();
    await sweepExpired();
    _sweep = Timer.periodic(const Duration(hours: 1), (_) => sweepExpired());
    notifyListeners();
    unawaited(_pump());
  }

  void _decode(String raw) {
    try {
      final Map<String, Object?> j = jsonDecode(raw) as Map<String, Object?>;
      budgetMb = (j['budgetMb'] as num?)?.toInt() ?? budgetMb;
      viewKeepDays = (j['viewKeep'] as num?)?.toInt() ?? viewKeepDays;
      for (final Object? s in (j['sources'] as List<Object?>?) ?? <Object?>[]) {
        _custom.add(MapSource.fromJson(s! as Map<String, Object?>));
      }
      for (final Object? p in (j['packs'] as List<Object?>?) ?? <Object?>[]) {
        packs.add(MapPack.fromJson(p! as Map<String, Object?>));
      }
      for (final Object? l in (j['layers'] as List<Object?>?) ?? <Object?>[]) {
        layers.add(EventLayer.fromJson(l! as Map<String, Object?>));
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        prefsKey,
        jsonEncode(<String, Object?>{
          'budgetMb': budgetMb,
          'viewKeep': viewKeepDays,
          'sources': <Object>[for (final MapSource s in _custom) s.toJson()],
          'packs': <Object>[for (final MapPack p in packs) p.toJson()],
          'layers': <Object>[for (final EventLayer l in layers) l.toJson()],
        }));
  }

  void _changed() {
    if (_disposed) return;
    unawaited(_save());
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _sweep?.cancel();
    _trim?.cancel();
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
      if (_disposed) return;
      _offlineUntilMs = 0;
      for (final MapPack p in packs) {
        if (p.state == PackState.waitingForNetwork) {
          p.state = p.updateStartedMs != null
              ? PackState.updating
              : PackState.downloading;
        }
      }
      unawaited(_pump());
    });
  }

  // ---- tiles for the map views -------------------------------------

  /// Bytes for one tile: the store first, the network if we must.
  /// Stale view tiles are revalidated (If-None-Match) when online and
  /// shown as-is when not; pack tiles are never refetched by viewing.
  Future<Uint8List?> loadTile(MapSource src, int z, int x, int y) async {
    await ready;
    final TileStore store = _store!;
    final String key = TileStore.keyOf(src.id, z, x, y);
    final TileMeta? meta = store.meta(key);
    if (meta != null) {
      final Uint8List? held = await store.read(key);
      if (held != null) {
        if (meta.expiresMs > _now || !meta.viewOnly || _inBackoff) {
          return held;
        }
        final FetchResult r = await _fetch(src.tileUri(z, x, y),
            etag: meta.etag, ifModifiedSinceMs: meta.fetchedMs);
        _noteFetch(r.status);
        if (r.status == FetchStatus.notModified) {
          store.revalidated(key, r.maxAge ?? viewMaxAgeDefault);
        } else if (r.status == FetchStatus.ok && r.bytes != null) {
          await store.write(key, r.bytes!,
              maxAge: r.maxAge ?? viewMaxAgeDefault, etag: r.etag);
          _scheduleTrim();
          return r.bytes;
        }
        return held;
      }
    }
    if (_inBackoff) return null;
    final FetchResult r = await _fetch(src.tileUri(z, x, y));
    _noteFetch(r.status);
    if (r.status != FetchStatus.ok || r.bytes == null) return null;
    await store.write(key, r.bytes!,
        maxAge: r.maxAge ?? viewMaxAgeDefault, etag: r.etag);
    _scheduleTrim();
    return r.bytes;
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
    if (!_disposed) notifyListeners();
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
    if (_pumping || _disposed || !loaded) return Future<void>.value();
    final Future<void> run = _pumpBody();
    _pumpRun = run;
    return run.whenComplete(() {
      if (identical(_pumpRun, run)) _pumpRun = null;
    });
  }

  Future<void> _pumpBody() async {
    _pumping = true;
    try {
      while (!_disposed) {
        MapPack? next;
        for (final MapPack p in packs) {
          if (p.state == PackState.downloading ||
              p.state == PackState.updating) {
            next = p;
            break;
          }
        }
        if (next == null) break;
        if (!await _runPack(next)) break;
      }
    } finally {
      _pumping = false;
    }
  }

  /// One pass over a pack. False when the network went away.
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
    for (final (int z, int x, int y) in tilesIn(p.box, p.minZoom, p.maxZoom)) {
      if (_disposed || !packs.contains(p)) return true;
      if (p.state != PackState.downloading && p.state != PackState.updating) {
        return true;
      }
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
      if (meta == null && !await _fits(perTile)) {
        p
          ..state = PackState.overBudget
          ..done = done
          ..missing = missing;
        _changed();
        return true;
      }
      final FetchResult r = await _fetch(src.tileUri(z, x, y),
          etag: refresh ? meta.etag : null,
          ifModifiedSinceMs: refresh ? meta.fetchedMs : null);
      _noteFetch(r.status);
      switch (r.status) {
        case FetchStatus.ok:
          if (!packs.contains(p)) return true;
          perTile = math.max(perTile, r.bytes!.length);
          await store.write(key, r.bytes!,
              maxAge: r.maxAge ?? packMaxAgeDefault, etag: r.etag, packId: p.id);
        case FetchStatus.notModified:
          store.revalidated(key, r.maxAge ?? packMaxAgeDefault, packId: p.id);
        case FetchStatus.missing:
          missing++;
        case FetchStatus.failed:
          p
            ..state = PackState.waitingForNetwork
            ..done = done
            ..missing = missing;
          _changed();
          _scheduleRetry();
          return false;
      }
      done++;
      _progress(p, done, missing);
      if (pace > Duration.zero) await Future<void>.delayed(pace);
    }
    p
      ..done = p.total
      ..missing = missing
      ..state = PackState.complete
      ..updatedMs = _now
      ..updateStartedMs = null;
    _changed();
    return true;
  }

  void _progress(MapPack p, int done, int missing) {
    p
      ..done = done
      ..missing = missing;
    if (done % 25 == 0) {
      if (done % 500 == 0) unawaited(_save());
      notifyListeners();
    }
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
    await _trimView();
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
    final FetchResult r = await _fetch(Uri.parse(l.url));
    _noteFetch(r.status);
    if (r.status == FetchStatus.failed) return LayerRefusal.offline;
    if (r.status != FetchStatus.ok || r.bytes == null) {
      return LayerRefusal.notGeoJson;
    }
    final Uint8List b = r.bytes!;
    if (b.length > maxLayerBytes) return LayerRefusal.tooLarge;
    final GeoShapes? shapes =
        parseGeoJson(utf8.decode(b, allowMalformed: true));
    if (shapes == null || shapes.count == 0) return LayerRefusal.notGeoJson;
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

  /// Parsed shapes for a layer, read from disk once.
  Future<GeoShapes?> shapesFor(EventLayer l) async {
    final GeoShapes? hit = _shapes[l.id];
    if (hit != null) return hit;
    await ready;
    try {
      final GeoShapes? s = parseGeoJson(await _layerFile(l.id).readAsString());
      if (s != null) _shapes[l.id] = s;
      return s;
    } catch (_) {
      return null;
    }
  }
}
