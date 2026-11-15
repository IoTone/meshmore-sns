// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
/// R81 — a small, read-only PMTiles v3 reader.
///
/// Written from the public format description (docs.protomaps.com,
/// github.com/protomaps/PMTiles `spec/v3/spec.md`) rather than adding the
/// `pmtiles` pub package, which is BSD-2-Clause. The app takes only
/// MIT/Apache code for new dependencies; the format needs ~250 lines.
///
/// A PMTiles file is one archive of tiles addressed by a Hilbert-curve
/// *tile id*, with a root directory and optional leaf directories (a sorted
/// run of `(tileId, runLength, offset, length)` entries). Reading a tile is
/// a handful of range reads: header, directory, tile. On disk that is a
/// seek, which is the whole point for an off-grid map.
///
/// Not supported, and refused loudly rather than misread: version != 3,
/// brotli/zstd internal or tile compression (gzip and none only), tile
/// types other than MVT for the vector path.
library;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Bytes at an offset: a file here, anything with random access in tests.
abstract class PmSource {
  int get length;
  Future<Uint8List> read(int offset, int length);
  Future<void> close();
}

class PmFileSource implements PmSource {
  PmFileSource._(this._file, this.length);

  final RandomAccessFile _file;
  @override
  final int length;

  static Future<PmFileSource> open(String path) async {
    final RandomAccessFile f = await File(path).open();
    return PmFileSource._(f, await f.length());
  }

  // `setPosition` then `read` are two awaits on ONE shared file position.
  // Without this chain, two tile reads in flight (the map asks for several
  // at once) interleave and each can return the other's bytes, silently.
  Future<void> _last = Future<void>.value();

  @override
  Future<Uint8List> read(int offset, int len) {
    final Future<Uint8List> r = _last.then((_) async {
      await _file.setPosition(offset);
      final Uint8List b = await _file.read(len);
      if (b.length != len) {
        throw const PmFormatException('short read: archive is truncated');
      }
      return b;
    });
    _last = r.then<void>((_) {}, onError: (Object _) {});
    return r;
  }

  @override
  Future<void> close() => _file.close();
}

/// The archive is not a PMTiles v3 file this reader understands.
class PmFormatException implements Exception {
  const PmFormatException(this.message);
  final String message;
  @override
  String toString() => 'PmFormatException: $message';
}

enum PmCompression { unknown, none, gzip, brotli, zstd }

enum PmTileType { unknown, mvt, png, jpeg, webp, avif }

class PmHeader {
  PmHeader._(this._d);

  static const int length = 127;

  final ByteData _d;

  static PmHeader parse(Uint8List b) {
    if (b.length < length) {
      throw const PmFormatException('shorter than the 127-byte header');
    }
    if (utf8.decode(b.sublist(0, 7), allowMalformed: true) != 'PMTiles') {
      throw const PmFormatException('bad magic: not a PMTiles file');
    }
    if (b[7] != 3) {
      throw PmFormatException('PMTiles version ${b[7]} is not supported');
    }
    return PmHeader._(ByteData.sublistView(b, 0, length));
  }

  int _u64(int o) {
    final int v = _d.getUint64(o, Endian.little);
    if (v < 0) throw const PmFormatException('offset beyond 2^63');
    return v;
  }

  int get rootOffset => _u64(0x08);
  int get rootLength => _u64(0x10);
  int get metadataOffset => _u64(0x18);
  int get metadataLength => _u64(0x20);
  int get leafOffset => _u64(0x28);
  int get leafLength => _u64(0x30);
  int get dataOffset => _u64(0x38);
  int get dataLength => _u64(0x40);

  PmCompression _comp(int o) {
    final int v = _d.getUint8(o);
    return v < PmCompression.values.length
        ? PmCompression.values[v]
        : PmCompression.unknown;
  }

  PmCompression get internalCompression => _comp(0x61);
  PmCompression get tileCompression => _comp(0x62);

  PmTileType get tileType {
    final int v = _d.getUint8(0x63);
    return v < PmTileType.values.length ? PmTileType.values[v] : PmTileType.unknown;
  }

  int get minZoom => _d.getUint8(0x64);
  int get maxZoom => _d.getUint8(0x65);

  double _deg(int o) => _d.getInt32(o, Endian.little) / 1e7;
  double get minLon => _deg(0x66);
  double get minLat => _deg(0x6A);
  double get maxLon => _deg(0x6E);
  double get maxLat => _deg(0x72);
}

class PmEntry {
  const PmEntry(this.tileId, this.offset, this.length, this.runLength);
  final int tileId;
  final int offset;
  final int length;

  /// 0 marks a pointer to a leaf directory.
  final int runLength;
}

/// Hilbert-curve tile ids, as the format defines them.
int pmTileId(int z, int x, int y) {
  if (z < 0 || z > 26 || x < 0 || y < 0 || x >= 1 << z || y >= 1 << z) {
    throw RangeError('tile $z/$x/$y is outside the pyramid');
  }
  final int before = ((1 << (2 * z)) - 1) ~/ 3; // 4^0 + ... + 4^(z-1)
  final int n = 1 << z;
  int xx = x, yy = y, d = 0;
  for (int s = n >> 1; s > 0; s >>= 1) {
    final int rx = (xx & s) > 0 ? 1 : 0;
    final int ry = (yy & s) > 0 ? 1 : 0;
    d += s * s * ((3 * rx) ^ ry);
    if (ry == 0) {
      if (rx == 1) {
        xx = n - 1 - xx;
        yy = n - 1 - yy;
      }
      final int t = xx;
      xx = yy;
      yy = t;
    }
  }
  return before + d;
}

(int, int, int) pmZxy(int tileId) {
  int id = tileId;
  for (int z = 0; z <= 26; z++) {
    final int count = 1 << (2 * z);
    if (id < count) {
      final int n = 1 << z;
      int x = 0, y = 0, t = id;
      for (int s = 1; s < n; s <<= 1) {
        final int rx = 1 & (t >> 1);
        final int ry = 1 & (t ^ rx);
        if (ry == 0) {
          if (rx == 1) {
            x = s - 1 - x;
            y = s - 1 - y;
          }
          final int tmp = x;
          x = y;
          y = tmp;
        }
        x += s * rx;
        y += s * ry;
        t >>= 2;
      }
      return (z, x, y);
    }
    id -= count;
  }
  throw const PmFormatException('tile id beyond zoom 26');
}

class PmTilesArchive {
  PmTilesArchive._(this._src, this.header);

  /// Hard caps so a damaged or hostile file cannot make a read enormous.
  static const int maxDirBytes = 64 * 1024 * 1024;
  static const int maxTileBytes = 16 * 1024 * 1024;
  static const int maxEntriesPerDir = 4 * 1000 * 1000;
  static const int _maxDepth = 4;
  static const int _dirCacheSize = 64;

  final PmSource _src;
  final PmHeader header;

  // Leaf directories keyed by absolute offset, oldest evicted first.
  final Map<int, List<PmEntry>> _dirs = <int, List<PmEntry>>{};

  static Future<PmTilesArchive> open(PmSource src) async {
    if (src.length < PmHeader.length) {
      throw const PmFormatException('shorter than the 127-byte header');
    }
    final PmHeader h = PmHeader.parse(await src.read(0, PmHeader.length));
    for (final PmCompression c in <PmCompression>[
      h.internalCompression,
      h.tileCompression
    ]) {
      if (c != PmCompression.gzip && c != PmCompression.none) {
        throw PmFormatException('${c.name} compression is not supported');
      }
    }
    final int end = src.length;
    bool inFile(int o, int l) => o >= 0 && l >= 0 && o + l <= end;
    if (!inFile(h.rootOffset, h.rootLength) ||
        !inFile(h.metadataOffset, h.metadataLength) ||
        !inFile(h.leafOffset, h.leafLength) ||
        !inFile(h.dataOffset, h.dataLength)) {
      throw const PmFormatException('a section lies outside the file');
    }
    return PmTilesArchive._(src, h);
  }

  Future<void> close() => _src.close();

  Uint8List _inflate(Uint8List b, PmCompression c) =>
      c == PmCompression.gzip ? Uint8List.fromList(gzip.decode(b)) : b;

  /// The archive's JSON metadata (`vector_layers`, attribution, ...).
  Future<Map<String, Object?>> metadata() async {
    if (header.metadataLength == 0) return <String, Object?>{};
    if (header.metadataLength > maxDirBytes) {
      throw const PmFormatException('metadata is implausibly large');
    }
    final Uint8List raw =
        await _src.read(header.metadataOffset, header.metadataLength);
    final Object? j = jsonDecode(
        utf8.decode(_inflate(raw, header.internalCompression)));
    return j is Map<String, Object?> ? j : <String, Object?>{};
  }

  /// The ids of the vector layers the tiles carry (empty for non-vector
  /// archives or ones that omit the field).
  Future<Set<String>> vectorLayerIds() async {
    final Object? vl = (await metadata())['vector_layers'];
    if (vl is! List<Object?>) return <String>{};
    return <String>{
      for (final Object? l in vl)
        if (l is Map<String, Object?> && l['id'] is String) l['id']! as String
    };
  }

  Future<List<PmEntry>> _dir(int offset, int length) async {
    final List<PmEntry>? hit = _dirs.remove(offset);
    if (hit != null) {
      _dirs[offset] = hit; // most recent last
      return hit;
    }
    if (length > maxDirBytes) {
      throw const PmFormatException('directory is implausibly large');
    }
    final Uint8List raw = await _src.read(offset, length);
    final List<PmEntry> entries =
        _parseDir(_inflate(raw, header.internalCompression));
    _dirs[offset] = entries;
    while (_dirs.length > _dirCacheSize) {
      _dirs.remove(_dirs.keys.first);
    }
    return entries;
  }

  /// The bytes of tile z/x/y, decompressed; null when the archive has no
  /// such tile (outside its extent or an empty cell).
  Future<Uint8List?> tile(int z, int x, int y) async {
    if (z < header.minZoom || z > header.maxZoom) return null;
    final int id = pmTileId(z, x, y);
    int offset = header.rootOffset;
    int length = header.rootLength;
    for (int depth = 0; depth < _maxDepth; depth++) {
      final List<PmEntry> dir = await _dir(
          depth == 0 ? offset : header.leafOffset + offset, length);
      final PmEntry? e = _find(dir, id);
      if (e == null) return null;
      if (e.runLength > 0) {
        if (e.length > maxTileBytes) {
          throw const PmFormatException('tile is implausibly large');
        }
        if (e.offset + e.length > header.dataLength) {
          throw const PmFormatException('tile lies outside the data section');
        }
        final Uint8List raw =
            await _src.read(header.dataOffset + e.offset, e.length);
        return _inflate(raw, header.tileCompression);
      }
      offset = e.offset; // leaf pointer: relative to the leaf section
      length = e.length;
      if (offset + length > header.leafLength) {
        throw const PmFormatException('leaf directory lies outside its section');
      }
    }
    throw const PmFormatException('directory nesting is too deep');
  }

  /// Largest entry whose tileId <= id, if it covers [id].
  static PmEntry? _find(List<PmEntry> dir, int id) {
    int lo = 0, hi = dir.length - 1;
    while (lo <= hi) {
      final int mid = (lo + hi) >> 1;
      final int t = dir[mid].tileId;
      if (t == id) return dir[mid];
      if (t < id) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (hi < 0) return null;
    final PmEntry e = dir[hi];
    if (e.runLength == 0) return e; // a leaf pointer covers a range
    return id - e.tileId < e.runLength ? e : null;
  }

  static List<PmEntry> _parseDir(Uint8List b) {
    int p = 0;
    int varint() {
      int result = 0;
      int shift = 0;
      while (true) {
        if (p >= b.length || shift > 63) {
          throw const PmFormatException('bad varint in directory');
        }
        final int byte = b[p++];
        result |= (byte & 0x7f) << shift;
        if (byte < 0x80) return result;
        shift += 7;
      }
    }

    final int n = varint();
    if (n < 0 || n > maxEntriesPerDir) {
      throw const PmFormatException('implausible directory size');
    }
    final List<int> ids = List<int>.filled(n, 0);
    final List<int> runs = List<int>.filled(n, 0);
    final List<int> lens = List<int>.filled(n, 0);
    final List<int> offs = List<int>.filled(n, 0);
    int last = 0;
    for (int i = 0; i < n; i++) {
      last += varint();
      ids[i] = last;
    }
    for (int i = 0; i < n; i++) {
      runs[i] = varint();
    }
    for (int i = 0; i < n; i++) {
      lens[i] = varint();
    }
    for (int i = 0; i < n; i++) {
      final int v = varint();
      offs[i] = v == 0 && i > 0 ? offs[i - 1] + lens[i - 1] : v - 1;
    }
    return <PmEntry>[
      for (int i = 0; i < n; i++) PmEntry(ids[i], offs[i], lens[i], runs[i])
    ];
  }
}
