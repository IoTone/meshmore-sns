// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/map_pack.dart';
import 'package:meshmore_sns_app/maps/map_source.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/maps/tile_ancestor.dart';
import 'package:meshmore_sns_app/maps/tile_math.dart';
import 'package:meshmore_sns_app/maps/tile_store.dart';

/// R114 — the coarse stand-in a tile miss falls back to.
///
/// Half the answer is arithmetic, which is here in full. The other half is
/// "does the controller find the parent that is actually on disk", which needs
/// a store and must never need the network: a stand-in is a drawing decision,
/// not a fetch.
class _NeverFetch {
  int calls = 0;

  Future<FetchResult> call(Uri url,
      {String? etag, int? ifModifiedSinceMs}) async {
    calls++;
    return const FetchResult(FetchStatus.failed);
  }
}

/// A raster source with a plain template, so the test does not lean on a
/// built-in catalogue entry keeping one zoom range.
const MapSource kTestRaster = MapSource(
  id: 'test-raster',
  name: 'Test raster',
  urlTemplate: 'https://tiles.test/{z}/{x}/{y}.png',
  attribution: 'test',
  allowsPacks: true,
);

void main() {
  group('ancestor arithmetic', () {
    test('the parent of a tile is its coordinates halved', () {
      final TileAncestorCoord? a = ancestorOf(12, 2001, 3007, 1);
      expect(a, isNotNull);
      expect(a!.z, 11);
      expect(a.x, 1000);
      expect(a.y, 1503);
      expect(a.levelsUp, 1);
      expect(a.span, 2);
    });

    test('four levels up covers a sixteenth of the world', () {
      final TileAncestorCoord? a = ancestorOf(16, 40000, 26000, 4);
      expect(a!.z, 12);
      expect(a.x, 2500);
      expect(a.y, 1625);
      expect(a.span, 16);
    });

    test('a world tile has no parent, and up 0 is not an ancestor', () {
      expect(ancestorOf(0, 0, 0, 1), isNull);
      expect(ancestorOf(5, 3, 3, 0), isNull);
      expect(ancestorOf(5, 3, 3, 6), isNull);
    });

    test('clamping keeps a saturated coordinate inside the coarse grid', () {
      // z1 holds x 0..1; a bogus child coordinate must not escape the parent.
      final TileAncestorCoord? a = ancestorOf(1, 3, 3, 1);
      expect(a!.x, 0);
      expect(a.y, 0);
    });
  });

  group('slice inside an ancestor', () {
    test('a parent has four children, each one quadrant', () {
      expect(sliceInAncestor(2000, 3000, 1), (column: 0, row: 0, span: 2));
      expect(sliceInAncestor(2001, 3000, 1), (column: 1, row: 0, span: 2));
      expect(sliceInAncestor(2000, 3001, 1), (column: 0, row: 1, span: 2));
      expect(sliceInAncestor(2001, 3001, 1), (column: 1, row: 1, span: 2));
    });

    test('the crop rect is that slice of a 256 px ancestor', () {
      final ({double left, double top, double width, double height}) r =
          cropRectInAncestor(2001, 3001, 1, 256);
      expect(r.left, 128);
      expect(r.top, 128);
      expect(r.width, 128);
      expect(r.height, 128);
    });

    test('three levels up is an eighth of the ancestor', () {
      final ({double left, double top, double width, double height}) r =
          cropRectInAncestor(0x2A5, 0x3C7, 3, 256);
      expect(r.width, 32);
      expect(r.left, (0x2A5 & 7) * 32);
      expect(r.top, (0x3C7 & 7) * 32);
    });
  });

  group('controller fallback', () {
    late Directory dir;
    late _NeverFetch net;
    late DateTime now;

    MapsController make() => MapsController(
          rootDir: () async => dir,
          fetcher: net.call,
          clock: () => now,
          pace: Duration.zero,
        );

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      dir = await Directory.systemTemp.createTemp('tile_ancestor_test');
      net = _NeverFetch();
      now = DateTime(2026, 10, 15, 12);
    });

    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    /// Write tiles to the same folder the controller will read, before it
    /// loads: its index is built at load time, so a tile seeded afterwards
    /// would be invisible to it.
    Future<void> seed(List<(int, int, int, List<int>)> tiles) async {
      final TileStore store = TileStore(dir, clock: () => now);
      await store.load();
      for (final (int z, int x, int y, List<int> bytes) in tiles) {
        await store.write(TileStore.keyOf(kTestRaster.id, z, x, y),
            Uint8List.fromList(bytes),
            maxAge: const Duration(days: 1));
      }
      await store.flush();
    }

    test('a z12 miss falls back to the z10 tile that is on disk', () async {
      await seed(<(int, int, int, List<int>)>[
        (10, 500, 751, <int>[1, 2, 3]),
      ]);
      final MapsController maps = make();
      await maps.load();

      final TileAncestor? a =
          await maps.ancestorTile(kTestRaster, 12, 2001, 3007);
      expect(a, isNotNull);
      expect(a!.coord.z, 10);
      expect(a.coord.x, 500);
      expect(a.coord.y, 751);
      expect(a.coord.levelsUp, 2);
      expect(a.bytes, <int>[1, 2, 3]);
      expect(net.calls, 0, reason: 'a stand-in is a store read, not a fetch');
      maps.dispose();
    });

    test('nothing on disk at any zoom is an honest null', () async {
      final MapsController maps = make();
      await maps.load();
      expect(await maps.ancestorTile(kTestRaster, 12, 2001, 3007), isNull);
      expect(net.calls, 0);
      maps.dispose();
    });

    test('the nearest ancestor wins over the coarser one', () async {
      await seed(<(int, int, int, List<int>)>[
        (8, 125, 187, <int>[8]),
        (10, 500, 751, <int>[10]),
      ]);
      final MapsController maps = make();
      await maps.load();

      final TileAncestor? a =
          await maps.ancestorTile(kTestRaster, 12, 2001, 3007);
      expect(a!.coord.z, 10);
      maps.dispose();
    });

    test('a pack reports the zoom span it covers, and none when absent', () {
      final MapsController maps = make();
      expect(maps.packZoomSpan(kTestRaster), isNull);

      final TileRange r = tileRange(
          GeoBox.around(37.77, -122.42, 1), 12);
      maps.packs.add(MapPack(
        id: 'p1',
        name: 'pack',
        sourceId: kTestRaster.id,
        box: GeoBox.around(37.77, -122.42, 1),
        minZoom: 10,
        maxZoom: 14,
        createdMs: now.millisecondsSinceEpoch,
        total: r.count,
      ));
      final ({int minZoom, int maxZoom})? span =
          maps.packZoomSpan(kTestRaster);
      expect(span!.minZoom, 10);
      expect(span.maxZoom, 14);
      maps.dispose();
    });
  });
}
