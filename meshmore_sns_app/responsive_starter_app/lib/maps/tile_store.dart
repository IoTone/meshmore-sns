// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// R61 — what the store knows about one cached tile.
class TileMeta {
  TileMeta({
    required this.bytes,
    required this.fetchedMs,
    required this.expiresMs,
    required this.lastUsedMs,
    this.etag,
    Set<String>? packs,
  }) : packs = packs ?? <String>{};

  int bytes;
  int fetchedMs;

  /// When the server says the tile goes stale. A stale tile is still
  /// shown; it is just asked about again (conditionally) when online.
  int expiresMs;
  int lastUsedMs;
  String? etag;

  /// Packs that hold this tile. Empty = a view-cache tile, the only
  /// kind the store evicts on its own.
  final Set<String> packs;

  bool get viewOnly => packs.isEmpty;

  List<Object?> toJson() => <Object?>[
        bytes,
        fetchedMs,
        expiresMs,
        lastUsedMs,
        etag,
        packs.toList(),
      ];

  static TileMeta fromJson(List<Object?> j) => TileMeta(
        bytes: (j[0]! as num).toInt(),
        fetchedMs: (j[1]! as num).toInt(),
        expiresMs: (j[2]! as num).toInt(),
        lastUsedMs: (j[3]! as num).toInt(),
        etag: j[4] as String?,
        packs: (j[5]! as List<Object?>).cast<String>().toSet(),
      );
}

/// R61 — tiles on disk, one file per tile under
/// `<root>/tiles/<source>/<z>/<x>/<y>`, plus one JSON index. The index
/// is the truth for accounting; a file without an index entry is
/// garbage and a missing file drops its entry on first read.
class TileStore {
  TileStore(this.root, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Directory root;
  final DateTime Function() _clock;
  final Map<String, TileMeta> _index = <String, TileMeta>{};
  Timer? _saveTimer;
  bool _loaded = false;

  int get _now => _clock().millisecondsSinceEpoch;

  static String keyOf(String source, int z, int x, int y) =>
      '$source/$z/$x/$y';

  File _fileFor(String key) => File('${root.path}/tiles/$key');
  File get _indexFile => File('${root.path}/tile_index.json');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final String raw = await _indexFile.readAsString();
      final Map<String, Object?> j =
          jsonDecode(raw) as Map<String, Object?>;
      j.forEach((String k, Object? v) =>
          _index[k] = TileMeta.fromJson(v! as List<Object?>));
    } catch (_) {
      // No index yet, or a torn write: start empty. Orphan files are
      // swept by [clearAll] / pack deletes, never trusted.
    }
  }

  TileMeta? meta(String key) => _index[key];

  bool has(String key) => _index.containsKey(key);

  int get tileCount => _index.length;

  int get totalBytes =>
      _index.values.fold(0, (int a, TileMeta m) => a + m.bytes);

  int get viewBytes => _index.values
      .where((TileMeta m) => m.viewOnly)
      .fold(0, (int a, TileMeta m) => a + m.bytes);

  int packBytes(String packId) => _index.values
      .where((TileMeta m) => m.packs.contains(packId))
      .fold(0, (int a, TileMeta m) => a + m.bytes);

  int packTiles(String packId) =>
      _index.values.where((TileMeta m) => m.packs.contains(packId)).length;

  /// Bytes for a tile, or null. Marks it used (LRU) when found.
  Future<Uint8List?> read(String key) async {
    final TileMeta? m = _index[key];
    if (m == null) return null;
    try {
      final Uint8List b = await _fileFor(key).readAsBytes();
      m.lastUsedMs = _now;
      _scheduleSave();
      return b;
    } catch (_) {
      _index.remove(key);
      _scheduleSave();
      return null;
    }
  }

  Future<void> write(
    String key,
    Uint8List bytes, {
    required Duration maxAge,
    String? etag,
    String? packId,
  }) async {
    final File f = _fileFor(key);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: false);
    final int now = _now;
    final TileMeta m = _index.putIfAbsent(
        key,
        () => TileMeta(
            bytes: 0, fetchedMs: now, expiresMs: now, lastUsedMs: now));
    m
      ..bytes = bytes.length
      ..fetchedMs = now
      ..expiresMs = now + maxAge.inMilliseconds
      ..lastUsedMs = now
      ..etag = etag;
    if (packId != null) m.packs.add(packId);
    _scheduleSave();
  }

  /// A 304: the tile we hold is good for another [maxAge].
  void revalidated(String key, Duration maxAge, {String? packId}) {
    final TileMeta? m = _index[key];
    if (m == null) return;
    final int now = _now;
    m
      ..fetchedMs = now
      ..expiresMs = now + maxAge.inMilliseconds;
    if (packId != null) m.packs.add(packId);
    _scheduleSave();
  }

  void addToPack(String key, String packId) {
    _index[key]?.packs.add(packId);
    _scheduleSave();
  }

  /// Drop [packId]'s claim on every tile. Tiles no other pack holds go
  /// back to the view cache when [keepAsView], else they are deleted.
  Future<void> releasePack(String packId, {bool keepAsView = false}) async {
    final List<String> orphans = <String>[];
    _index.forEach((String k, TileMeta m) {
      if (m.packs.remove(packId) && m.packs.isEmpty && !keepAsView) {
        orphans.add(k);
      }
    });
    for (final String k in orphans) {
      await _delete(k);
    }
    _scheduleSave();
  }

  /// Evict view-cache tiles, least recently used first, until view
  /// bytes are at most [maxViewBytes]; also drop any view tile unused
  /// for longer than [maxIdle]. Pack tiles are never touched.
  Future<int> trimView({required int maxViewBytes, Duration? maxIdle}) async {
    final List<MapEntry<String, TileMeta>> view = _index.entries
        .where((MapEntry<String, TileMeta> e) => e.value.viewOnly)
        .toList()
      ..sort((MapEntry<String, TileMeta> a, MapEntry<String, TileMeta> b) =>
          a.value.lastUsedMs.compareTo(b.value.lastUsedMs));
    int bytes = view.fold(0, (int a, MapEntry<String, TileMeta> e) =>
        a + e.value.bytes);
    final int idleBefore =
        maxIdle == null ? -1 : _now - maxIdle.inMilliseconds;
    int freed = 0;
    for (final MapEntry<String, TileMeta> e in view) {
      final bool idle = e.value.lastUsedMs < idleBefore;
      if (bytes <= maxViewBytes && !idle) continue;
      bytes -= e.value.bytes;
      freed += e.value.bytes;
      await _delete(e.key);
    }
    if (freed > 0) _scheduleSave();
    return freed;
  }

  Future<void> clearView() => trimView(maxViewBytes: 0);

  Future<void> _delete(String key) async {
    _index.remove(key);
    try {
      await _fileFor(key).delete();
    } catch (_) {}
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      await root.create(recursive: true);
      final File tmp = File('${_indexFile.path}.tmp');
      await tmp.writeAsString(jsonEncode(<String, Object?>{
        for (final MapEntry<String, TileMeta> e in _index.entries)
          e.key: e.value.toJson(),
      }));
      await tmp.rename(_indexFile.path);
    } catch (_) {}
  }

  void dispose() {
    _saveTimer?.cancel();
  }
}
