// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/maps/event_layer.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/map_pack.dart';
import 'package:meshmore_sns_app/maps/map_source.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/maps/tile_math.dart';
import 'package:meshmore_sns_app/maps/tile_store.dart';

/// Scripted network. Every URL answers 200 with 1000 bytes unless
/// [offline], a [missing] path fragment, or a [bodies] override.
class FakeFetch {
  bool offline = false;
  final List<String> missing = <String>[];

  /// URL fragments that fail (connection error) while the rest succeed.
  final List<String> failing = <String>[];
  final Map<String, String> bodies = <String, String>{};
  final List<(Uri, String?)> calls = <(Uri, String?)>[];
  Duration? maxAge;
  bool answer304 = false;

  Future<FetchResult> call(Uri url, {String? etag, int? ifModifiedSinceMs}) async {
    calls.add((url, etag));
    if (offline || failing.any(url.toString().contains)) {
      return const FetchResult(FetchStatus.failed);
    }
    if (missing.any(url.toString().contains)) {
      return const FetchResult(FetchStatus.missing);
    }
    if (answer304 && etag != null) {
      return FetchResult(FetchStatus.notModified, maxAge: maxAge, etag: etag);
    }
    final String? body = bodies[url.toString()];
    return FetchResult(FetchStatus.ok,
        bytes: body != null
            ? Uint8List.fromList(utf8.encode(body))
            : Uint8List(1000),
        maxAge: maxAge,
        etag: '"e1"');
  }
}

const String _geo = '''
{"type":"FeatureCollection","features":[
 {"type":"Feature","properties":{"name":"Center Camp"},
  "geometry":{"type":"Point","coordinates":[-119.2065,40.7861]}},
 {"type":"Feature","properties":{},
  "geometry":{"type":"LineString","coordinates":[[-119.2,40.78],[-119.21,40.79]]}},
 {"type":"Feature","properties":{},
  "geometry":{"type":"MultiPolygon","coordinates":[[[[-119.2,40.78],[-119.21,40.78],[-119.21,40.79],[-119.2,40.78]]]]}}
]}''';

void main() {
  late Directory dir;
  late FakeFetch net;
  late DateTime now;

  MapsController make() => MapsController(
        rootDir: () async => dir,
        fetcher: net.call,
        clock: () => now,
        pace: Duration.zero,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = await Directory.systemTemp.createTemp('maps_test');
    net = FakeFetch();
    now = DateTime(2026, 10, 15, 12);
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  // A ~1 km neighbourhood of San Francisco, zoom 12-13: a handful of
  // tiles, inside USGS coverage.
  final GeoBox sf = GeoBox.around(37.77, -122.42, 1);

  group('tile math', () {
    test('known tile coordinates', () {
      expect(lonToTileX(0, 1), 1);
      expect(latToTileY(0, 1), 1);
      expect(lonToTileX(-180, 3), 0);
      expect(lonToTileX(180, 3), 7);
      // Null Island's north-west neighbour at z2.
      expect(latToTileY(10, 2), 1);
    });

    test('counts grow ~4x per zoom and run low zoom first', () {
      final int a = tileCount(sf, 14, 14);
      final int b = tileCount(sf, 15, 15);
      expect(b, greaterThanOrEqualTo(a * 2));
      final List<(int, int, int)> t = tilesIn(sf, 12, 14).toList();
      expect(t.length, tileCount(sf, 12, 14));
      expect(t.first.$1, 12);
      expect(t.last.$1, 14);
    });
  });

  group('sources', () {
    test('USGS covers SF, not Tokyo; OSM covers both but is view-only', () {
      expect(kUsgsTopo.covers(sf), isTrue);
      expect(kUsgsTopo.covers(GeoBox.around(35.68, 139.69, 5)), isFalse);
      expect(kOsmStandard.allowsPacks, isFalse);
      expect(kOpenTopo.allowsPacks, isFalse);
    });

    test('USGS template is z/y/x', () {
      expect(kUsgsTopo.tileUri(3, 1, 2).path, endsWith('/tile/3/2/1'));
    });

    test('custom templates need https and z/x/y', () {
      expect(MapSource.validTemplate('https://t.example/{z}/{x}/{y}.png'),
          isTrue);
      expect(MapSource.validTemplate('http://t.example/{z}/{x}/{y}.png'),
          isFalse);
      expect(MapSource.validTemplate('https://t.example/{z}/{x}.png'),
          isFalse);
    });
  });

  test('cache headers: max-age wins, Expires falls back', () {
    final DateTime t = DateTime.utc(2026, 1, 1);
    expect(parseMaxAge('public, max-age=600', null, t),
        const Duration(minutes: 10));
    expect(parseMaxAge(null, 'Thu, 01 Jan 2026 01:00:00 GMT', t),
        const Duration(hours: 1));
    expect(parseMaxAge(null, null, t), isNull);
  });

  group('GeoJSON', () {
    test('points, lines and polygons; labels from properties', () {
      final GeoShapes s = parseGeoJson(_geo)!;
      expect(s.points.single.label, 'Center Camp');
      expect(s.lines, hasLength(1));
      expect(s.polygons, hasLength(1));
      expect(s.points.single.at.latitude, closeTo(40.7861, 1e-9));
    });

    test('not GeoJSON is null', () {
      expect(parseGeoJson('<html>'), isNull);
      expect(parseGeoJson('{"hello":1}'), isNull);
    });
  });

  group('view cache', () {
    test('a viewed tile is fetched once, then served from disk', () async {
      final MapsController m = make();
      await m.load();
      expect(await m.loadTile(kOsmStandard, 10, 1, 2), isNotNull);
      expect(await m.loadTile(kOsmStandard, 10, 1, 2), isNotNull);
      expect(net.calls, hasLength(1));
      expect(net.calls.single.$1.toString(),
          'https://tile.openstreetmap.org/10/1/2.png');
      expect(m.viewBytes, 1000);
      m.dispose();
    });

    test('stale tiles revalidate with their ETag; offline shows stale',
        () async {
      final MapsController m = make();
      await m.load();
      await m.loadTile(kOsmStandard, 10, 1, 2);
      // OSM floor: 7 days when the server says nothing.
      now = now.add(const Duration(days: 8));
      net.answer304 = true;
      expect(await m.loadTile(kOsmStandard, 10, 1, 2), isNotNull);
      expect(net.calls.last.$2, '"e1"');
      now = now.add(const Duration(days: 8));
      net.offline = true;
      expect(await m.loadTile(kOsmStandard, 10, 1, 2), isNotNull);
      // R81: one failed revalidation is a lost packet, not "offline". The
      // banner flips once the source has failed three times in a row.
      expect(m.online, isTrue);
      expect(await m.loadTile(kOsmStandard, 10, 1, 2), isNotNull);
      expect(await m.loadTile(kOsmStandard, 10, 1, 2), isNotNull);
      expect(m.online, isFalse);
      m.dispose();
    });

    test('offline and never seen: no tile, and backoff stops hammering',
        () async {
      final MapsController m = make();
      await m.load();
      net.offline = true;
      // R81: three failures in a row open the gate (was: one). Tiles 1-3
      // are asked about; the fourth and fifth are not.
      for (int i = 0; i < 3; i++) {
        expect(await m.loadTile(kOsmStandard, 10, 5, 5 + i), isNull);
      }
      expect(net.calls, hasLength(3));
      expect(await m.loadTile(kOsmStandard, 10, 5, 9), isNull);
      expect(await m.loadTile(kOsmStandard, 10, 5, 10), isNull);
      expect(net.calls, hasLength(3), reason: 'gated: no more requests');
      m.dispose();
    });

    test('R81 one failed tile does not blank the map', () async {
      final MapsController m = make();
      await m.load();
      net.failing.add('/10/5/5');
      expect(await m.loadTile(kOsmStandard, 10, 5, 5), isNull);
      // Used to return null for the next 30 s without asking.
      expect(await m.loadTile(kOsmStandard, 10, 5, 6), isNotNull);
      expect(await m.loadTile(kOsmStandard, 10, 5, 7), isNotNull);
      expect(m.online, isTrue);
      m.dispose();
    });

    test('R81 a success resets the failure count', () async {
      final MapsController m = make();
      await m.load();
      net.failing.add('/10/5/');
      await m.loadTile(kOsmStandard, 10, 5, 1);
      await m.loadTile(kOsmStandard, 10, 5, 2);
      net.failing.clear();
      expect(await m.loadTile(kOsmStandard, 10, 5, 3), isNotNull);
      net.failing.add('/10/5/');
      await m.loadTile(kOsmStandard, 10, 5, 4);
      await m.loadTile(kOsmStandard, 10, 5, 5);
      final int before = net.calls.length;
      await m.loadTile(kOsmStandard, 10, 5, 6); // third since the success
      expect(net.calls.length, before + 1, reason: 'still asked: 2 < 3');
      m.dispose();
    });

    test('R81 a dead source is gated alone, with jitter, and retried', () async {
      final MapsController m = MapsController(
        rootDir: () async => dir,
        fetcher: net.call,
        clock: () => now,
        pace: Duration.zero,
        random: _FixedRandom(0.0), // jitter factor 0.8 -> 24 s of 30 s
      );
      await m.load();
      net.failing.add('tile.openstreetmap.org');
      for (int i = 0; i < 3; i++) {
        await m.loadTile(kOsmStandard, 10, 5, i);
      }
      // Another source is unaffected by OSM's outage.
      expect(await m.loadTile(kUsgsTopo, 10, 5, 5), isNotNull);
      final int gated = net.calls.length;
      expect(await m.loadTile(kOsmStandard, 10, 5, 20), isNull);
      expect(net.calls.length, gated);
      now = now.add(const Duration(seconds: 23));
      await m.loadTile(kOsmStandard, 10, 5, 21);
      expect(net.calls.length, gated, reason: 'jittered wait is 24 s');
      now = now.add(const Duration(seconds: 2));
      await m.loadTile(kOsmStandard, 10, 5, 22);
      expect(net.calls.length, gated + 1, reason: 'retried after the wait');
      // Retry failed again: the next wait doubles (60 s * 0.8).
      now = now.add(const Duration(seconds: 47));
      await m.loadTile(kOsmStandard, 10, 5, 23);
      expect(net.calls.length, gated + 1);
      now = now.add(const Duration(seconds: 2));
      await m.loadTile(kOsmStandard, 10, 5, 24);
      expect(net.calls.length, gated + 2);
      m.dispose();
    });
  });

  group('packs', () {
    test('R81 only sources that permit bulk download can start a pack',
        () async {
      // OSM's tile policy forbids scraping; OpenTopoMap is a shared
      // volunteer server; OpenFreeMap caps offline use at 3,000 tiles /
      // 50 MB per download. Only the USGS public-domain sources stay legal.
      expect(<String>[
        for (final MapSource s in <MapSource>[
          ...kBuiltInSources,
          kOsmVector,
        ])
          if (s.allowsPacks) s.id
      ], <String>['usgs-topo', 'usgs-imagery']);
      final MapsController m = make();
      await m.load();
      expect(await m.createPack(
              name: 'x', source: kOsmVector, box: sf,
              minZoom: 10, maxZoom: 12),
          PackRefusal.sourceViewOnly);
      expect(net.calls, isEmpty, reason: 'refused before any request');
      m.dispose();
    });

    test('refusals: view-only source, coverage, size, budget, offline',
        () async {
      final MapsController m = make();
      await m.load();
      Future<PackRefusal?> make0(MapSource s, GeoBox b, int lo, int hi) =>
          m.createPack(name: 'x', source: s, box: b, minZoom: lo, maxZoom: hi);
      expect(await make0(kOsmStandard, sf, 12, 13), PackRefusal.sourceViewOnly);
      expect(await make0(kUsgsTopo, GeoBox.around(35.68, 139.69, 2), 12, 13),
          PackRefusal.outsideCoverage);
      expect(await make0(kUsgsTopo, GeoBox.around(37.77, -122.42, 50), 6, 16),
          PackRefusal.tooManyTiles);
      await m.setBudgetMb(100);
      expect(await make0(kUsgsTopo, GeoBox.around(37.77, -122.42, 15), 10, 16),
          PackRefusal.overBudget);
      expect(
          await m.createPack(
              name: ' ', source: kUsgsTopo, box: sf, minZoom: 12, maxZoom: 13),
          PackRefusal.noName);
      net.offline = true;
      expect(await make0(kUsgsTopo, sf, 12, 13), PackRefusal.offline);
      expect(m.packs, isEmpty);
      m.dispose();
    });

    test('a pack downloads every tile, counts gaps, and completes',
        () async {
      final MapsController m = make();
      await m.load();
      net.missing.add('/tile/13/');
      expect(
          await m.createPack(
              name: 'SF', source: kUsgsTopo, box: sf, minZoom: 12, maxZoom: 13),
          isNull);
      await m.idle();
      final MapPack p = m.packs.single;
      expect(p.state, PackState.complete);
      expect(p.done, p.total);
      expect(p.missing, tileCount(sf, 13, 13));
      expect(m.packBytes(p), tileCount(sf, 12, 12) * 1000);
      // Pack tiles are not view-cache tiles.
      expect(m.viewBytes, 0);
      m.dispose();
    });

    test('network loss parks the pack; resume finishes it', () async {
      final MapsController m = make();
      await m.load();
      await m.createPack(
          name: 'SF', source: kUsgsTopo, box: sf, minZoom: 12, maxZoom: 14);
      // Fail after the probe tile.
      net.offline = true;
      await m.idle();
      final MapPack p = m.packs.single;
      expect(p.state, PackState.waitingForNetwork);
      net.offline = false;
      m.resumePack(p);
      await m.idle();
      expect(p.state, PackState.complete);
      expect(m.packBytes(p), tileCount(sf, 12, 14) * 1000);
      m.dispose();
    });

    test('a viewed tile that falls inside a pack joins it, unfetched',
        () async {
      final MapsController m = make();
      await m.load();
      final (int z, int x, int y) t = tilesIn(sf, 12, 13).first;
      await m.loadTile(kUsgsTopo, t.$1, t.$2, t.$3);
      await m.createPack(
          name: 'SF', source: kUsgsTopo, box: sf, minZoom: 12, maxZoom: 13);
      await m.idle();
      final int fetchedForT = net.calls
          .where((c) => c.$1.path.endsWith('/${t.$1}/${t.$3}/${t.$2}'))
          .length;
      expect(fetchedForT, 1);
      expect(m.viewBytes, 0);
      m.dispose();
    });

    test('update asks with ETags; delete keeps tiles another pack holds',
        () async {
      final MapsController m = make();
      await m.load();
      await m.createPack(
          name: 'A', source: kUsgsTopo, box: sf, minZoom: 12, maxZoom: 13);
      await m.idle();
      now = now.add(const Duration(seconds: 1));
      await m.createPack(
          name: 'B', source: kUsgsTopo, box: sf, minZoom: 12, maxZoom: 12);
      await m.idle();
      final MapPack a = m.packs[0];
      final MapPack b = m.packs[1];
      expect(m.packBytes(b), tileCount(sf, 12, 12) * 1000);

      net.calls.clear();
      net.answer304 = true;
      now = now.add(const Duration(days: 40));
      m.updatePack(a);
      await m.idle();
      expect(a.state, PackState.complete);
      expect(net.calls, hasLength(a.total));
      expect(net.calls.every(((Uri, String?) c) => c.$2 == '"e1"'), isTrue);

      await m.deletePack(a);
      expect(m.packBytes(b), tileCount(sf, 12, 12) * 1000);
      expect(m.tileBytes, tileCount(sf, 12, 12) * 1000);
      m.dispose();
    });

    test('expiry deletes a pack after its keep-for', () async {
      final MapsController m = make();
      await m.load();
      await m.createPack(
          name: 'SF',
          source: kUsgsTopo,
          box: sf,
          minZoom: 12,
          maxZoom: 12,
          keepDays: 7);
      await m.idle();
      now = now.add(const Duration(days: 6));
      await m.sweepExpired();
      expect(m.packs, hasLength(1));
      now = now.add(const Duration(days: 2));
      await m.sweepExpired();
      expect(m.packs, isEmpty);
      expect(m.tileBytes, 0);
      m.dispose();
    });

    test('state survives a restart', () async {
      final MapsController m = make();
      await m.load();
      await m.createPack(
          name: 'SF', source: kUsgsTopo, box: sf, minZoom: 12, maxZoom: 12);
      await m.idle();
      await m.setBudgetMb(250);
      m.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final MapsController again = make();
      await again.load();
      expect(again.budgetMb, 250);
      expect(again.packs.single.state, PackState.complete);
      expect(again.packBytes(again.packs.single),
          tileCount(sf, 12, 12) * 1000);
      again.dispose();
    });
  });

  group('budget', () {
    test('view tiles are evicted least-recently-used first', () async {
      final TileStore store = TileStore(dir, clock: () => now);
      await store.load();
      for (int i = 0; i < 5; i++) {
        now = now.add(const Duration(seconds: 1));
        await store.write(TileStore.keyOf('osm', 10, i, 0), Uint8List(1000),
            maxAge: const Duration(days: 7));
      }
      await store.write(TileStore.keyOf('osm', 10, 9, 9), Uint8List(1000),
          maxAge: const Duration(days: 7), packId: 'p');
      // Touch tile 0 so tiles 1 and 2 are the oldest.
      now = now.add(const Duration(seconds: 1));
      await store.read(TileStore.keyOf('osm', 10, 0, 0));
      await store.trimView(maxViewBytes: 3000);
      expect(store.has(TileStore.keyOf('osm', 10, 0, 0)), isTrue);
      expect(store.has(TileStore.keyOf('osm', 10, 1, 0)), isFalse);
      expect(store.has(TileStore.keyOf('osm', 10, 2, 0)), isFalse);
      expect(store.has(TileStore.keyOf('osm', 10, 4, 0)), isTrue);
      // Pack tiles are never evicted to make room.
      await store.trimView(maxViewBytes: 0);
      expect(store.viewBytes, 0);
      expect(store.has(TileStore.keyOf('osm', 10, 9, 9)), isTrue);
      // Idle view tiles age out.
      await store.write(TileStore.keyOf('osm', 10, 7, 7), Uint8List(1000),
          maxAge: const Duration(days: 7));
      now = now.add(const Duration(days: 31));
      await store.trimView(
          maxViewBytes: 1 << 30, maxIdle: const Duration(days: 30));
      expect(store.has(TileStore.keyOf('osm', 10, 7, 7)), isFalse);
      store.dispose();
    });

    test('prefetch warms the ring once, then spends nothing (R83)', () async {
      int calls = 0;
      final MapsController m = MapsController(
        rootDir: () async => dir,
        fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs}) async {
          calls++;
          return FetchResult(FetchStatus.ok, bytes: Uint8List(1000),
              maxAge: const Duration(days: 1));
        },
        clock: () => now,
        pace: Duration.zero,
      );
      await m.load();
      const List<(int, int, int)> ring = <(int, int, int)>[
        (10, 1, 1), (10, 1, 2), (10, 2, 1),
      ];
      expect(await m.prefetch(kOsmVector, ring), 3);
      expect(calls, 3);
      expect(m.hasTile(kOsmVector, 10, 1, 1), isTrue);
      // Already held: a warm-up must not spend a request on it.
      expect(await m.prefetch(kOsmVector, ring), 0);
      expect(calls, 3);
      // Warmed tiles are ordinary tiles: the map reads them from the store.
      expect((await m.loadTile(kOsmVector, 10, 1, 2))?.length, 1000);
      expect(calls, 3);
      m.dispose();
    });

    test('a tile already in flight is asked for once (R83)', () async {
      int calls = 0;
      final MapsController m = MapsController(
        rootDir: () async => dir,
        fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs}) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return FetchResult(FetchStatus.ok, bytes: Uint8List(1000),
              maxAge: const Duration(days: 1));
        },
        clock: () => now,
        pace: Duration.zero,
      );
      await m.load();
      // The library asks for a tile as soon as it is visible; a pan that
      // returns before the first response lands must not double the fetch.
      final List<TileLoad> both = await Future.wait<TileLoad>(<Future<TileLoad>>[
        m.loadTileDetailed(kOsmVector, 12, 853, 1560),
        m.loadTileDetailed(kOsmVector, 12, 853, 1560),
      ]);
      expect(calls, 1);
      expect(both.first.bytes, isNotNull);
      expect(both.last.bytes, both.first.bytes);
      m.dispose();
    });

    test('a source floor outlives a shorter server max-age (R82)', () async {
      // The OSM vector service advertises max-age=300; its policy wants tiles
      // kept at least seven days, so the store must floor it, not follow it.
      final MapsController m = MapsController(
        rootDir: () async => dir,
        fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs}) async =>
            const FetchResult(FetchStatus.failed),
        clock: () => now,
      );
      const Duration fiveMin = Duration(minutes: 5);
      expect(m.tileTtl(fiveMin, kOsmVector), const Duration(days: 7));
      expect(m.tileTtl(fiveMin, kOsmStandard), fiveMin,
          reason: 'a raster source keeps the server\'s own expiry');
      expect(m.tileTtl(const Duration(days: 30), kOsmVector),
          const Duration(days: 30),
          reason: 'a longer server life is never shortened');
      expect(m.tileTtl(null, kOsmVector), const Duration(days: 7));
      m.dispose();
    });

    test('a pack that outgrows the budget stops and says so', () async {
      // Estimate fits (25 kB/tile planned) but the server sends 20 MB
      // tiles; the pack stops at the budget, not past it.
      final MapsController big = MapsController(
        rootDir: () async => dir,
        fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs}) async =>
            FetchResult(FetchStatus.ok, bytes: Uint8List(20 * 1000 * 1000)),
        clock: () => now,
        pace: Duration.zero,
      );
      await big.load();
      await big.setBudgetMb(100);
      await big.createPack(
          name: 'SF', source: kUsgsTopo, box: sf, minZoom: 12, maxZoom: 15);
      await big.idle();
      final MapPack p = big.packs.single;
      expect(p.state, PackState.overBudget);
      expect(big.usedBytes, lessThanOrEqualTo(big.budgetBytes));
      big.dispose();
    });
  });

  group('event layers', () {
    const String url = 'https://example.org/brc/streets.geojson';

    test('refusals: http, not GeoJSON, offline', () async {
      final MapsController m = make();
      await m.load();
      expect(await m.addLayer(name: 'x', url: 'http://example.org/a.json'),
          LayerRefusal.badUrl);
      net.bodies[url] = '<html>not here</html>';
      expect(await m.addLayer(name: 'x', url: url), LayerRefusal.notGeoJson);
      net.offline = true;
      expect(await m.addLayer(name: 'x', url: url), LayerRefusal.offline);
      expect(m.layers, isEmpty);
      m.dispose();
    });

    test('added, counted, drawn from disk after restart, expires', () async {
      net.bodies[url] = _geo;
      final MapsController m = make();
      await m.load();
      expect(await m.addLayer(name: 'BRC', url: url, keepDays: 30), isNull);
      final EventLayer l = m.layers.single;
      expect(l.features, 3);
      expect(m.layerBytes, utf8.encode(_geo).length);
      m.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final MapsController again = make();
      await again.load();
      final EventLayer l2 = again.layers.single;
      expect((await again.shapesFor(l2))!.count, 3);
      now = now.add(const Duration(days: 31));
      await again.sweepExpired();
      expect(again.layers, isEmpty);
      again.dispose();
    });
  });
}

class _FixedRandom implements Random {
  _FixedRandom(this.v);
  final double v;
  @override
  double nextDouble() => v;
  @override
  bool nextBool() => v >= 0.5;
  @override
  int nextInt(int max) => (v * max).floor();
}
