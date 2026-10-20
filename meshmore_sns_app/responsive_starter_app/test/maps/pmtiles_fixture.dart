// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshmore_sns_app/maps/pmtiles.dart';

/// Builds a real PMTiles v3 archive in memory, so tests read genuine bytes
/// through the real reader. Generated at test time rather than committed:
/// `test/no_binary_sources_test.dart` keeps binaries out of the tree, and a
/// builder shows exactly what is in the file.
///
/// Mirrors the format's writer: tiles sorted by Hilbert tile id, identical
/// consecutive tiles collapsed into one run, directories varint-encoded and
/// delta-coded, gzip inside, optional leaf directories.
class PmBuild {
  PmBuild(this.tiles,
      {this.leafSize = 0,
      this.layers = const <String>['water', 'transportation'],
      this.minLon = -105.0,
      this.minLat = 38.0,
      this.maxLon = -104.0,
      this.maxLat = 39.0,
      this.internal = 2,
      this.tileComp = 2,
      this.version = 3});

  /// (z, x, y) -> raw (uncompressed) tile bytes.
  final Map<(int, int, int), List<int>> tiles;

  /// 0 = root directory only; otherwise entries per leaf directory.
  final int leafSize;
  final List<String> layers;
  final double minLon, minLat, maxLon, maxLat;
  final int internal; // 1 none, 2 gzip, 3 brotli
  final int tileComp;
  final int version;

  Uint8List build() {
    final List<(int, int, int)> keys = tiles.keys.toList()
      ..sort((a, b) => pmTileId(a.$1, a.$2, a.$3)
          .compareTo(pmTileId(b.$1, b.$2, b.$3)));
    final BytesBuilder data = BytesBuilder();
    final List<PmEntry> entries = <PmEntry>[];
    List<int>? lastBytes;
    int lastId = -2;
    for (final (int, int, int) k in keys) {
      final int id = pmTileId(k.$1, k.$2, k.$3);
      final List<int> raw = tiles[k]!;
      final List<int> stored = tileComp == 2 ? gzip.encode(raw) : raw;
      if (lastBytes != null &&
          id == lastId + 1 &&
          _same(lastBytes, stored) &&
          entries.isNotEmpty) {
        final PmEntry e = entries.removeLast();
        entries.add(PmEntry(e.tileId, e.offset, e.length, e.runLength + 1));
      } else {
        entries.add(PmEntry(id, data.length, stored.length, 1));
        data.add(stored);
      }
      lastBytes = stored;
      lastId = id;
    }

    List<int> pack(List<int> b) => internal == 2 ? gzip.encode(b) : b;

    final BytesBuilder leaves = BytesBuilder();
    List<PmEntry> rootEntries = entries;
    if (leafSize > 0 && entries.length > leafSize) {
      rootEntries = <PmEntry>[];
      for (int i = 0; i < entries.length; i += leafSize) {
        final List<PmEntry> chunk = entries.sublist(
            i, i + leafSize > entries.length ? entries.length : i + leafSize);
        final Uint8List enc = Uint8List.fromList(pack(_encodeDir(chunk)));
        rootEntries.add(PmEntry(chunk.first.tileId, leaves.length, enc.length, 0));
        leaves.add(enc);
      }
    }
    final Uint8List root = Uint8List.fromList(pack(_encodeDir(rootEntries)));
    final Uint8List meta = Uint8List.fromList(pack(utf8.encode(jsonEncode(
        <String, Object?>{
          'name': 'fixture',
          'vector_layers': <Object>[
            for (final String l in layers) <String, Object?>{'id': l}
          ],
        }))));

    int z0 = 99, z1 = 0;
    for (final (int, int, int) k in keys) {
      if (k.$1 < z0) z0 = k.$1;
      if (k.$1 > z1) z1 = k.$1;
    }
    const int hdr = 127;
    final int rootOff = hdr;
    final int metaOff = rootOff + root.length;
    final int leafOff = metaOff + meta.length;
    final int dataOff = leafOff + leaves.length;
    final ByteData h = ByteData(hdr);
    final List<int> magic = utf8.encode('PMTiles');
    for (int i = 0; i < 7; i++) {
      h.setUint8(i, magic[i]);
    }
    h.setUint8(7, version);
    void u64(int o, int v) => h.setUint64(o, v, Endian.little);
    u64(0x08, rootOff);
    u64(0x10, root.length);
    u64(0x18, metaOff);
    u64(0x20, meta.length);
    u64(0x28, leafOff);
    u64(0x30, leaves.length);
    u64(0x38, dataOff);
    u64(0x40, data.length);
    u64(0x48, tiles.length);
    u64(0x50, entries.length);
    u64(0x58, entries.length);
    h.setUint8(0x60, 1);
    h.setUint8(0x61, internal);
    h.setUint8(0x62, tileComp);
    h.setUint8(0x63, 1); // mvt
    h.setUint8(0x64, z0);
    h.setUint8(0x65, z1);
    h.setInt32(0x66, (minLon * 1e7).round(), Endian.little);
    h.setInt32(0x6A, (minLat * 1e7).round(), Endian.little);
    h.setInt32(0x6E, (maxLon * 1e7).round(), Endian.little);
    h.setInt32(0x72, (maxLat * 1e7).round(), Endian.little);
    return (BytesBuilder()
          ..add(h.buffer.asUint8List())
          ..add(root)
          ..add(meta)
          ..add(leaves.toBytes())
          ..add(data.toBytes()))
        .toBytes();
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<int> _encodeDir(List<PmEntry> es) {
    final List<int> o = <int>[];
    void v(int n) {
      while (n >= 0x80) {
        o.add((n & 0x7f) | 0x80);
        n >>= 7;
      }
      o.add(n);
    }

    v(es.length);
    int last = 0;
    for (final PmEntry e in es) {
      v(e.tileId - last);
      last = e.tileId;
    }
    for (final PmEntry e in es) {
      v(e.runLength);
    }
    for (final PmEntry e in es) {
      v(e.length);
    }
    for (int i = 0; i < es.length; i++) {
      final PmEntry e = es[i];
      if (i > 0 && e.offset == es[i - 1].offset + es[i - 1].length) {
        v(0);
      } else {
        v(e.offset + 1);
      }
    }
    return o;
  }
}

/// In-memory [PmSource] that counts reads, to prove access is by range.
class MemSource implements PmSource {
  MemSource(this.bytes);
  final Uint8List bytes;
  final List<(int, int)> reads = <(int, int)>[];

  @override
  int get length => bytes.length;

  @override
  Future<Uint8List> read(int offset, int len) async {
    reads.add((offset, len));
    if (offset + len > bytes.length) {
      throw const PmFormatException('short read: archive is truncated');
    }
    return Uint8List.sublistView(bytes, offset, offset + len);
  }

  @override
  Future<void> close() async {}
}
