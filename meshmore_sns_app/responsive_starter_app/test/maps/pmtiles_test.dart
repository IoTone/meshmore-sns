// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/maps/pmtiles.dart';

import 'pmtiles_fixture.dart';

/// R81 — the PMTiles reader against real archive bytes.
void main() {
  group('tile ids', () {
    test('match the published PMTiles examples', () {
      // docs/spec table: Z X Y -> TileID
      const List<(int, int, int, int)> table = <(int, int, int, int)>[
        (0, 0, 0, 0),
        (1, 0, 0, 1),
        (1, 0, 1, 2),
        (1, 1, 1, 3),
        (1, 1, 0, 4),
        (2, 0, 0, 5),
        (12, 3423, 1763, 19078479),
      ];
      for (final (int z, int x, int y, int id) in table) {
        expect(pmTileId(z, x, y), id, reason: '$z/$x/$y');
        expect(pmZxy(id), (z, x, y), reason: 'id $id');
      }
    });

    test('are a bijection over zooms 0-6, in zoom-major order', () {
      int prev = -1;
      for (int z = 0; z <= 6; z++) {
        for (int x = 0; x < 1 << z; x++) {
          for (int y = 0; y < 1 << z; y++) {
            final int id = pmTileId(z, x, y);
            expect(pmZxy(id), (z, x, y));
            expect(id, greaterThan(-1));
            if (x == 0 && y == 0) {
              expect(id, greaterThan(prev),
                  reason: 'each zoom starts after the previous one');
            }
          }
        }
        prev = pmTileId(z, 1 % (1 << z), 0);
      }
    });

    test('reject coordinates outside the pyramid', () {
      expect(() => pmTileId(2, 4, 0), throwsRangeError);
      expect(() => pmTileId(2, 0, -1), throwsRangeError);
      expect(() => pmTileId(27, 0, 0), throwsRangeError);
    });
  });

  Map<(int, int, int), List<int>> pyramid() {
    final Map<(int, int, int), List<int>> t = <(int, int, int), List<int>>{};
    for (int z = 0; z <= 4; z++) {
      for (int x = 0; x < 1 << z; x++) {
        for (int y = 0; y < 1 << z; y++) {
          t[(z, x, y)] = <int>[z, x, y, 0x1a, 0x02];
        }
      }
    }
    return t;
  }

  group('PmTilesArchive', () {
    test('reads every tile, and null for what is not there', () async {
      final MemSource src = MemSource(PmBuild(pyramid()).build());
      final PmTilesArchive a = await PmTilesArchive.open(src);
      expect(a.header.minZoom, 0);
      expect(a.header.maxZoom, 4);
      for (final MapEntry<(int, int, int), List<int>> e in pyramid().entries) {
        expect(await a.tile(e.key.$1, e.key.$2, e.key.$3), e.value,
            reason: '${e.key}');
      }
      expect(await a.tile(5, 0, 0), isNull, reason: 'above maxzoom');
      final Uint8List? none = await PmTilesArchive.open(MemSource(PmBuild(
              <(int, int, int), List<int>>{(3, 0, 0): <int>[1]}).build()))
          .then((PmTilesArchive s) => s.tile(3, 7, 7));
      expect(none, isNull, reason: 'a gap between entries');
    });

    test('follows leaf directories', () async {
      final MemSource src = MemSource(PmBuild(pyramid(), leafSize: 7).build());
      final PmTilesArchive a = await PmTilesArchive.open(src);
      for (final MapEntry<(int, int, int), List<int>> e in pyramid().entries) {
        expect(await a.tile(e.key.$1, e.key.$2, e.key.$3), e.value,
            reason: '${e.key}');
      }
      expect(a.header.leafLength, greaterThan(0), reason: 'fixture uses leaves');
    });

    test('a run of identical tiles is stored once and read for each id',
        () async {
      // Four neighbouring "open ocean" tiles with identical content.
      final Map<(int, int, int), List<int>> t = <(int, int, int), List<int>>{};
      for (final (int, int, int) k in <(int, int, int)>[
        (2, 0, 0),
        (2, 0, 1),
        (2, 1, 1),
        (2, 1, 0)
      ]) {
        t[k] = <int>[9, 9, 9];
      }
      t[(2, 2, 2)] = <int>[1, 2];
      final PmTilesArchive a =
          await PmTilesArchive.open(MemSource(PmBuild(t).build()));
      for (final (int, int, int) k in t.keys) {
        expect(await a.tile(k.$1, k.$2, k.$3), t[k], reason: '$k');
      }
    });

    test('reads by range: header, directory, tile, never the whole file',
        () async {
      final Map<(int, int, int), List<int>> big = pyramid();
      final MemSource src = MemSource(PmBuild(big).build());
      final PmTilesArchive a = await PmTilesArchive.open(src);
      src.reads.clear();
      await a.tile(4, 5, 6);
      final int touched = src.reads.fold(0, (int s, (int, int) r) => s + r.$2);
      expect(touched, lessThan(src.length ~/ 2));
      expect(src.reads.length, lessThanOrEqualTo(2), reason: 'dir + tile');
      src.reads.clear();
      await a.tile(4, 5, 7);
      expect(src.reads.length, 1, reason: 'the root directory is cached');
    });

    test('exposes metadata, layers and the extent', () async {
      final PmTilesArchive a = await PmTilesArchive.open(MemSource(
          PmBuild(pyramid(), layers: <String>['water', 'poi']).build()));
      expect(await a.vectorLayerIds(), <String>{'water', 'poi'});
      expect(a.header.minLon, closeTo(-105.0, 1e-6));
      expect(a.header.maxLat, closeTo(39.0, 1e-6));
      expect(a.header.tileType, PmTileType.mvt);
    });

    test('works over a real file', () async {
      final Directory d = await Directory.systemTemp.createTemp('pmt');
      final File f = File('${d.path}/x.pmtiles')
        ..writeAsBytesSync(PmBuild(pyramid(), leafSize: 5).build());
      final PmTilesArchive a =
          await PmTilesArchive.open(await PmFileSource.open(f.path));
      expect(await a.tile(3, 2, 5), <int>[3, 2, 5, 0x1a, 0x02]);
      await a.close();
      await d.delete(recursive: true);
    });

    test('concurrent reads of one file never swap bytes', () async {
      // Many different tiles asked for at once, as a panning map does.
      final Map<(int, int, int), List<int>> t = <(int, int, int), List<int>>{};
      for (int x = 0; x < 16; x++) {
        for (int y = 0; y < 16; y++) {
          t[(4, x, y)] = List<int>.generate(900, (int i) => (x * 16 + y + i) & 255);
        }
      }
      final Directory d = await Directory.systemTemp.createTemp('pmt');
      final File f = File('${d.path}/c.pmtiles')
        ..writeAsBytesSync(PmBuild(t, leafSize: 20, tileComp: 1).build());
      final PmTilesArchive a =
          await PmTilesArchive.open(await PmFileSource.open(f.path));
      final List<(int, int, int)> keys = t.keys.toList()..shuffle(Random(3));
      final List<Uint8List?> got = await Future.wait(<Future<Uint8List?>>[
        for (final (int, int, int) k in keys) a.tile(k.$1, k.$2, k.$3)
      ]);
      for (int i = 0; i < keys.length; i++) {
        expect(got[i], t[keys[i]], reason: '${keys[i]}');
      }
      await a.close();
      await d.delete(recursive: true);
    });

    test('uncompressed archives (internal and tile) read too', () async {
      final PmTilesArchive a = await PmTilesArchive.open(MemSource(
          PmBuild(pyramid(), internal: 1, tileComp: 1).build()));
      expect(await a.tile(2, 1, 3), <int>[2, 1, 3, 0x1a, 0x02]);
    });
  });

  group('refusals', () {
    Future<Object?> openErr(Uint8List b) async {
      try {
        await PmTilesArchive.open(MemSource(b));
      } catch (e) {
        return e;
      }
      return null;
    }

    test('not a PMTiles file / wrong version / truncated', () async {
      final Uint8List good = PmBuild(pyramid()).build();
      final Uint8List bad = Uint8List.fromList(good)..[0] = 0x58;
      expect(await openErr(bad), isA<PmFormatException>());
      expect(await openErr(PmBuild(pyramid(), version: 2).build()),
          isA<PmFormatException>());
      expect(await openErr(Uint8List.sublistView(good, 0, 100)),
          isA<PmFormatException>());
      expect(await openErr(Uint8List.sublistView(good, 0, good.length - 5)),
          isA<PmFormatException>(),
          reason: 'data section runs past the end');
    });

    test('brotli and zstd are refused, not misread', () async {
      expect(await openErr(PmBuild(pyramid(), internal: 3).build()),
          isA<PmFormatException>());
      expect(await openErr(PmBuild(pyramid(), tileComp: 4).build()),
          isA<PmFormatException>());
    });

    test('a corrupt directory is a format error, not a hang or a range crash',
        () async {
      final Uint8List b = PmBuild(pyramid(), internal: 1).build();
      // Root directory starts at byte 127: claim 2^28 entries.
      b[127] = 0x80;
      b[128] = 0x80;
      b[129] = 0x80;
      b[130] = 0x80;
      b[131] = 0x01;
      final PmTilesArchive a = await PmTilesArchive.open(MemSource(b));
      await expectLater(a.tile(1, 0, 0), throwsA(isA<PmFormatException>()));
    });
  });
}
