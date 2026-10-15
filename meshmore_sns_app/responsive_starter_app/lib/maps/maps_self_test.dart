// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'event_layer.dart';
import 'map_fetch.dart';
import 'map_pack.dart';
import 'map_source.dart';
import 'maps_controller.dart';
import 'tile_math.dart';

/// R61 — what the self-test checks, in run order.
enum SelfCheckId {
  reach,
  viewCache,
  revalidate,
  pack,
  update,
  eventLayer,
  offline,
  resume,
  guards,
  expiry,
  disk,
}

enum CheckState { pending, running, pass, fail, skipped }

class SelfCheck {
  SelfCheck(this.id);
  final SelfCheckId id;
  CheckState state = CheckState.pending;

  /// Technical one-liner: numbers, statuses, timings.
  String detail = '';
  Duration? took;
}

/// The real network, with a switch to play dead and counters.
class _ProbeFetch {
  _ProbeFetch(this._real);
  final MapFetcher _real;
  bool offline = false;

  /// Go offline by itself after this many more successful fetches.
  int? failAfter;
  int requests = 0;
  int conditional = 0;
  int notModified = 0;
  int bytes = 0;

  Future<FetchResult> call(Uri url, {String? etag, int? ifModifiedSinceMs}) async {
    if (failAfter != null && failAfter! <= 0) offline = true;
    if (offline) return const FetchResult(FetchStatus.failed);
    requests++;
    if (etag != null || ifModifiedSinceMs != null) conditional++;
    final FetchResult r =
        await _real(url, etag: etag, ifModifiedSinceMs: ifModifiedSinceMs);
    if (r.status == FetchStatus.notModified) notModified++;
    bytes += r.bytes?.length ?? 0;
    if (failAfter != null && r.status == FetchStatus.ok) failAfter = failAfter! - 1;
    return r;
  }
}

/// R61 — validates offline maps end to end on the device: the real tile
/// servers, the real disk, the real download loop. Runs in a sandbox
/// (its own folder and settings key) and deletes it afterwards, so the
/// user's packs and budget are never touched.
///
/// About a minute and a few hundred kB of data, mostly the pause/resume
/// check waiting out the 30 s network backoff.
class MapsSelfTest extends ChangeNotifier {
  MapsSelfTest({
    required this.sandbox,
    MapFetcher? fetcher,
    this.appVersion = '',
    this.lat,
    this.lon,
    this.layerUrl = defaultLayerUrl,
    this.retryFloor = const Duration(seconds: 30),
  }) : _net = _ProbeFetch(fetcher ?? httpMapFetcher(() => mapUserAgent(appVersion)));

  /// A small public GeoJSON (Black Rock City street centrelines,
  /// ~240 kB) used only to prove the event-layer path.
  static const String defaultLayerUrl =
      'https://raw.githubusercontent.com/burningmantech/innovate-GIS-data/'
      'master/2026/GeoJSON/street_lines.geojson';

  /// Fallback test point inside USGS coverage: Black Rock City.
  static const double fallbackLat = 40.7864;
  static const double fallbackLon = -119.2065;

  final Directory sandbox;
  final String appVersion;
  final double? lat;
  final double? lon;
  final String layerUrl;
  final Duration retryFloor;
  final _ProbeFetch _net;

  final List<SelfCheck> checks = <SelfCheck>[
    for (final SelfCheckId id in SelfCheckId.values) SelfCheck(id),
  ];
  bool running = false;
  DateTime? startedAt;
  Duration? total;
  String pointLabel = '';

  Duration _skew = Duration.zero;
  bool get passed =>
      checks.every((SelfCheck c) =>
          c.state == CheckState.pass || c.state == CheckState.skipped);
  int get failures =>
      checks.where((SelfCheck c) => c.state == CheckState.fail).length;

  SelfCheck _c(SelfCheckId id) => checks[id.index];

  Future<void> run() async {
    if (running) return;
    running = true;
    startedAt = DateTime.now();
    for (final SelfCheck c in checks) {
      c
        ..state = CheckState.pending
        ..detail = ''
        ..took = null;
    }
    notifyListeners();
    final Stopwatch all = Stopwatch()..start();

    // Where to test: the user's own spot if USGS covers it, else BRC.
    double tLat = fallbackLat;
    double tLon = fallbackLon;
    if (lat != null &&
        lon != null &&
        kUsgsTopo.covers(GeoBox.around(lat!, lon!, 1))) {
      tLat = lat!;
      tLon = lon!;
      pointLabel = 'own location';
    } else {
      pointLabel = 'Black Rock City (own location outside USGS coverage '
          'or unknown)';
    }

    try {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    } catch (_) {}
    final MapsController m = MapsController(
      rootDir: () async => sandbox,
      fetcher: _net.call,
      clock: () => DateTime.now().add(_skew),
      pace: const Duration(milliseconds: 50),
      prefsKey: 'maps.selftest.v1',
      retryFloor: retryFloor,
    );
    MapPack? pack;
    EventLayer? layer;
    // A view-cache tile at z14 over the test point.
    final int vz = 14;
    final int vx = lonToTileX(tLon, vz);
    final int vy = latToTileY(tLat, vz);
    final GeoBox box = GeoBox.around(tLat, tLon, 1);

    try {
      await m.load();

      await _step(SelfCheckId.reach, () async {
        final List<String> parts = <String>[];
        bool osmOk = false;
        bool usgsOk = false;
        for (final MapSource s in kBuiltInSources) {
          final Stopwatch w = Stopwatch()..start();
          final FetchResult r = await _net.call(s.tileUri(12,
              lonToTileX(tLon, 12), latToTileY(tLat, 12)));
          final bool img = r.status == FetchStatus.ok && _isImage(r.bytes);
          if (s == kOsmStandard) osmOk = img;
          if (s == kUsgsTopo) usgsOk = img;
          parts.add('${s.id} ${img ? 'ok' : r.status.name} '
              '${_kb(r.bytes?.length ?? 0)} ${w.elapsedMilliseconds} ms'
              '${r.maxAge == null ? '' : ' max-age ${_dur(r.maxAge!)}'}');
        }
        return (osmOk && usgsOk, parts.join(' · '));
      });

      await _step(SelfCheckId.viewCache, () async {
        final int before = _net.requests;
        final Uint8List? a = await m.loadTile(kOsmStandard, vz, vx, vy);
        final Uint8List? b = await m.loadTile(kOsmStandard, vz, vx, vy);
        final int fetched = _net.requests - before;
        return (
          a != null && b != null && fetched == 1 && m.viewBytes > 0,
          '2 loads → $fetched fetch; view cache ${_kb(m.viewBytes)}'
        );
      });

      await _step(SelfCheckId.revalidate, () async {
        // Jump past OSM's freshness and look again: the app must ask
        // with its ETag rather than download blind.
        _skew = const Duration(days: 8);
        final int cond = _net.conditional;
        final int nm = _net.notModified;
        final Uint8List? t = await m.loadTile(kOsmStandard, vz, vx, vy);
        _skew = Duration.zero;
        final bool asked = _net.conditional > cond;
        return (
          t != null && asked,
          asked
              ? (_net.notModified > nm
                  ? 'conditional request → 304 not modified'
                  : 'conditional request → re-sent (server ignored ETag)')
              : 'no conditional request sent'
        );
      });

      await _step(SelfCheckId.pack, () async {
        final Stopwatch w = Stopwatch()..start();
        final PackRefusal? why = await m.createPack(
            name: 'self-test', source: kUsgsTopo, box: box,
            minZoom: 12, maxZoom: 14);
        if (why != null) return (false, 'refused: ${why.name}');
        pack = m.packs.single;
        final bool done = await _until(
            () => pack!.state == PackState.complete,
            const Duration(seconds: 120));
        final MapPack p = pack!;
        final int held = m.packTilesHeld(p);
        final double rate = held / (w.elapsedMilliseconds / 1000);
        return (
          done && held == p.total - p.missing && held > 0,
          '${p.state.name}: $held/${p.total} tiles, ${p.missing} missing, '
              '${_kb(m.packBytes(p))}, ${rate.toStringAsFixed(1)} tiles/s'
        );
      });

      await _step(SelfCheckId.update, () async {
        final MapPack? p = pack;
        if (p == null) return (null, 'no pack');
        final int nm = _net.notModified;
        final int req = _net.requests;
        _skew = const Duration(seconds: 2);
        m.updatePack(p);
        final bool done = await _until(
            () => p.state == PackState.complete, const Duration(seconds: 120));
        _skew = Duration.zero;
        final int asked = _net.requests - req;
        final int same = _net.notModified - nm;
        return (
          done && asked > 0,
          'asked $asked: $same not modified, ${asked - same} re-sent'
        );
      });

      await _step(SelfCheckId.eventLayer, () async {
        final LayerRefusal? why =
            await m.addLayer(name: 'self-test', url: layerUrl);
        if (why != null) return (false, 'refused: ${why.name}');
        layer = m.layers.single;
        final GeoShapes? s = await m.shapesFor(layer!);
        return (
          (s?.count ?? 0) > 0,
          '${layer!.features} features (${s?.lines.length ?? 0} lines, '
              '${s?.polygons.length ?? 0} polygons, '
              '${s?.points.length ?? 0} points), ${_kb(layer!.bytes)}'
        );
      });

      await _step(SelfCheckId.offline, () async {
        _net.offline = true;
        final Uint8List? cached = await m.loadTile(kOsmStandard, vz, vx, vy);
        final Uint8List? fresh =
            await m.loadTile(kOsmStandard, vz, vx + 3, vy + 3);
        final PackRefusal? pr = await m.createPack(
            name: 'x', source: kUsgsTopo, box: box, minZoom: 15, maxZoom: 15);
        final LayerRefusal? lr = await m.addLayer(name: 'x', url: layerUrl);
        _net.offline = false;
        final bool ok = cached != null &&
            fresh == null &&
            pr == PackRefusal.offline &&
            lr == LayerRefusal.offline &&
            !m.online;
        return (
          ok,
          'cached tile ${cached != null ? 'shown' : 'MISSING'}; '
              'unseen tile ${fresh == null ? 'blank' : 'UNEXPECTED'}; '
              'new pack ${pr?.name ?? 'ALLOWED'}; '
              'new layer ${lr?.name ?? 'ALLOWED'}'
        );
      });

      await _step(SelfCheckId.resume, () async {
        // The probe fetch in createPack also clears the offline
        // check's backoff, as any successful fetch does.
        final Stopwatch w = Stopwatch()..start();
        final PackRefusal? why = await m.createPack(
            name: 'resume', source: kUsgsTopo, box: box,
            minZoom: 15, maxZoom: 15);
        if (why != null) return (false, 'refused: ${why.name}');
        final MapPack p = m.packs.last;
        _net.failAfter = 3;
        final bool parked = await _until(
            () => p.state == PackState.waitingForNetwork,
            const Duration(seconds: 60));
        final int at = p.done;
        final Duration parkedAt = w.elapsed;
        _net
          ..failAfter = null
          ..offline = false;
        final bool done = await _until(
            () => p.state == PackState.complete, const Duration(seconds: 120));
        return (
          parked && done,
          '${parked ? 'parked at $at/${p.total}' : 'never parked'}; '
              '${done ? 'resumed by itself, done ${(w.elapsed - parkedAt).inSeconds} s later' : 'did not finish (${p.state.name})'}'
        );
      });

      await _step(SelfCheckId.guards, () async {
        final GeoBox big = GeoBox.around(tLat, tLon, 60);
        final PackRefusal? size = m.checkPack(
            name: 'x', source: kUsgsTopo, box: big, minZoom: 6, maxZoom: 16);
        await m.setBudgetMb(100);
        final PackRefusal? budget = m.checkPack(
            name: 'x', source: kUsgsTopo, box: GeoBox.around(tLat, tLon, 15),
            minZoom: 10, maxZoom: 16);
        final PackRefusal? osm = m.checkPack(
            name: 'x', source: kOsmStandard, box: box, minZoom: 12, maxZoom: 13);
        final PackRefusal? tokyo = m.checkPack(
            name: 'x', source: kUsgsTopo,
            box: GeoBox.around(35.68, 139.69, 1), minZoom: 12, maxZoom: 13);
        final bool ok = size == PackRefusal.tooManyTiles &&
            budget == PackRefusal.overBudget &&
            osm == PackRefusal.sourceViewOnly &&
            tokyo == PackRefusal.outsideCoverage;
        return (
          ok,
          'huge ${size?.name}; 100 MB ${budget?.name}; '
              'OSM ${osm?.name}; Tokyo ${tokyo?.name}'
        );
      });

      await _step(SelfCheckId.expiry, () async {
        final List<MapPack> ps = List<MapPack>.of(m.packs);
        for (final MapPack p in ps) {
          m.setPackKeep(p, 7);
        }
        if (layer != null) m.setLayerKeep(layer!, 7);
        final int before = m.usedBytes;
        _skew = const Duration(days: 8);
        await m.sweepExpired();
        _skew = Duration.zero;
        return (
          m.packs.isEmpty && m.layers.isEmpty && m.pinnedBytes == 0,
          '${ps.length} packs + ${layer == null ? 0 : 1} layer deleted; '
              '${_kb(before)} → ${_kb(m.usedBytes)}'
        );
      });

      await _step(SelfCheckId.disk, () async {
        await m.ready;
        int onDisk = 0;
        int files = 0;
        if (await sandbox.exists()) {
          await for (final FileSystemEntity e
              in sandbox.list(recursive: true)) {
            if (e is File && e.path.contains('/tiles/')) {
              files++;
              onDisk += await e.length();
            }
          }
        }
        // Accounting and disk must agree (index flushed or not, the
        // files are written synchronously with the index update).
        return (
          onDisk == m.tileBytes,
          'index ${_kb(m.tileBytes)}, disk ${_kb(onDisk)} in $files files; '
              '${sandbox.path}'
        );
      });
    } catch (e) {
      for (final SelfCheck c in checks) {
        if (c.state == CheckState.running) {
          c
            ..state = CheckState.fail
            ..detail = 'threw: $e';
        }
      }
    } finally {
      m.dispose();
      try {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (await sandbox.exists()) await sandbox.delete(recursive: true);
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.remove('maps.selftest.v1');
      } catch (_) {}
      for (final SelfCheck c in checks) {
        if (c.state == CheckState.pending) c.state = CheckState.skipped;
      }
      total = all.elapsed;
      running = false;
      notifyListeners();
    }
  }

  /// Run one check. The body returns (passed?, detail); null = skipped.
  Future<void> _step(
      SelfCheckId id, Future<(bool?, String)> Function() body) async {
    final SelfCheck c = _c(id);
    c.state = CheckState.running;
    notifyListeners();
    final Stopwatch w = Stopwatch()..start();
    try {
      final (bool? ok, String detail) =
          await body().timeout(const Duration(minutes: 3));
      c
        ..state = ok == null
            ? CheckState.skipped
            : ok
                ? CheckState.pass
                : CheckState.fail
        ..detail = detail;
    } catch (e) {
      c
        ..state = CheckState.fail
        ..detail = 'threw: $e';
    }
    c.took = w.elapsed;
    notifyListeners();
  }

  static Future<bool> _until(bool Function() cond, Duration timeout) async {
    final DateTime end = DateTime.now().add(timeout);
    while (!cond()) {
      if (DateTime.now().isAfter(end)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return true;
  }

  static bool _isImage(Uint8List? b) {
    if (b == null || b.length < 4) return false;
    final bool png = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
    final bool jpg = b[0] == 0xFF && b[1] == 0xD8;
    return png || jpg;
  }

  static String _kb(int b) => b < 10000
      ? '$b B'
      : b < 10 * 1000 * 1000
          ? '${(b / 1000).toStringAsFixed(0)} kB'
          : '${(b / 1e6).toStringAsFixed(1)} MB';

  static String _dur(Duration d) => d.inDays >= 1
      ? '${d.inDays}d'
      : d.inHours >= 1
          ? '${d.inHours}h'
          : '${d.inMinutes}m';

  /// Plain-text report for an issue comment.
  String report() {
    final StringBuffer b = StringBuffer()
      ..writeln('Meshmore SNS offline-maps self-test')
      ..writeln('app $appVersion · ${startedAt?.toIso8601String() ?? '-'}'
          ' · ${total?.inSeconds ?? '-'} s')
      ..writeln('test point: $pointLabel')
      ..writeln('network: ${_net.requests} requests, '
          '${_net.conditional} conditional, ${_net.notModified} × 304, '
          '${_kb(_net.bytes)}')
      ..writeln(passed ? 'RESULT: PASS' : 'RESULT: FAIL ($failures)');
    for (final SelfCheck c in checks) {
      b.writeln('[${c.state.name.toUpperCase()}] ${c.id.name}'
          '${c.took == null ? '' : ' (${c.took!.inMilliseconds} ms)'}: '
          '${c.detail}');
    }
    return b.toString();
  }
}
