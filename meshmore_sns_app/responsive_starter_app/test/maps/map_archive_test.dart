// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/maps/map_archive.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/map_source.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/maps/tile_math.dart';

import 'pmtiles_fixture.dart';

/// A host serving one file with real HTTP range semantics.
class FakeHost {
  FakeHost(this.file, {this.etag = '"v1"'});

  Uint8List file;
  String etag;
  bool ignoreRange = false;
  int status = 200;

  /// Cut the stream with an error after this many bytes of the next
  /// response (once).
  int? dropAfter;

  /// If set, the body waits on this before each chunk after [holdAfter].
  Completer<void>? hold;
  int holdAfter = 1 << 30;

  final List<(int?, String?)> requests = <(int?, String?)>[];
  int bytesSent = 0;

  Future<ArchiveResponse> call(Uri url, {int? rangeStart, String? ifRange}) async {
    requests.add((rangeStart, ifRange));
    if (status != 200) {
      return ArchiveResponse(status: status, body: const Stream<List<int>>.empty());
    }
    final bool changed = ifRange != null && ifRange != etag;
    final int start = (!ignoreRange && !changed && (rangeStart ?? 0) > 0)
        ? rangeStart!
        : 0;
    if (start >= file.length && start > 0) {
      return ArchiveResponse(
          status: 416,
          body: const Stream<List<int>>.empty(),
          rangeTotal: file.length);
    }
    final int? cut = dropAfter;
    dropAfter = null;
    Stream<List<int>> body() async* {
      int sent = 0;
      for (int o = start; o < file.length; o += 4096) {
        if (cut != null && sent >= cut) throw const SocketException('lost');
        if (hold != null && sent >= holdAfter) await hold!.future;
        final int end = min(o + 4096, file.length);
        final int cap = cut == null ? end : min(end, o + (cut - sent));
        yield file.sublist(o, cap);
        sent += cap - o;
        bytesSent += cap - o;
        if (cut != null && sent >= cut) throw const SocketException('lost');
      }
    }

    return ArchiveResponse(
      status: start > 0 ? 206 : 200,
      body: body(),
      contentLength: file.length - start,
      rangeStart: start > 0 ? start : null,
      rangeTotal: start > 0 ? file.length : null,
      etag: etag,
    );
  }
}

String _sha(Uint8List b) => crypto.sha256.convert(b).toString();

void main() {
  late Directory dir;
  late FakeHost host;
  late DateTime now;
  late List<Uri> tileCalls;

  // Colorado-ish extent at z9 (a handful of cells), one left out on purpose.
  const int kZ = 9;
  List<int> cellBytes((int, int, int) c) {
    final Random r = Random(c.$2 * 1000 + c.$3);
    return <int>[0x1a, ...List<int>.generate(3000, (_) => r.nextInt(256))];
  }

  const GeoBox box = GeoBox(south: 38.0, west: -105.0, north: 39.0, east: -104.0);
  late (int, int, int) emptyCell;
  late (int, int, int) inside;
  Uint8List archiveBytes({List<String>? layers, int pad = 0}) {
    final Map<(int, int, int), List<int>> t = <(int, int, int), List<int>>{};
    final List<(int, int, int)> cells = tileRange(box, kZ).tiles.toList();
    inside = cells.first;
    emptyCell = cells.last;
    for (final (int, int, int) c in cells.take(cells.length - 1)) {
      t[c] = cellBytes(c);
    }
    if (pad > 0) {
      final Random r = Random(7);
      t[(kZ, 0, 0)] = List<int>.generate(pad, (_) => r.nextInt(256));
    }
    return PmBuild(t,
            layers: layers ?? <String>['water', 'transportation', 'place'],
            minLon: box.west,
            minLat: box.south,
            maxLon: box.east,
            maxLat: box.north,
            leafSize: 3)
        .build();
  }

  MapsController make({Duration pace = Duration.zero}) => MapsController(
        rootDir: () async => dir,
        fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs}) async {
          tileCalls.add(u);
          return FetchResult(FetchStatus.ok, bytes: Uint8List(10));
        },
        archiveFetcher: host.call,
        clock: () => now,
        pace: pace,
        retryFloor: const Duration(milliseconds: 20),
      );

  Future<void> settle(MapsController m) async {
    for (int i = 0; i < 1000; i++) {
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await m.idle();
      if (m.archives.every((MapArchive a) =>
          a.state != ArchiveState.downloading &&
          a.state != ArchiveState.waitingForNetwork)) {
        return;
      }
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = await Directory.systemTemp.createTemp('archive_test');
    host = FakeHost(archiveBytes());
    now = DateTime(2026, 10, 20, 12);
    tileCalls = <Uri>[];
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<MapsController> loaded() async {
    final MapsController m = make();
    await m.load();
    return m;
  }

  group('download', () {
    test('one file, verified, then read in place with no network', () async {
      final MapsController m = await loaded();
      expect(
          await m.addArchive(
              name: 'Front Range',
              url: 'https://host.example/front-range.pmtiles',
              expectedBytes: host.file.length,
              sha256: _sha(host.file)),
          isNull);
      await settle(m);
      final MapArchive a = m.archives.single;
      expect(a.state, ArchiveState.complete);
      expect((a.minZoom, a.maxZoom), (kZ, kZ));
      expect(a.west, closeTo(-105.0, 1e-6));
      expect(m.archiveBytes, host.file.length);
      expect(m.usedBytes, host.file.length, reason: 'counted in the budget');
      expect(host.requests, hasLength(1));
      expect(host.bytesSent, host.file.length);

      final TileLoad hit = await m.loadTileDetailed(
          kOpenFreeMapVector, kZ, inside.$2, inside.$3);
      expect(hit.bytes, cellBytes(inside));
      final TileLoad empty = await m.loadTileDetailed(
          kOpenFreeMapVector, kZ, emptyCell.$2, emptyCell.$3);
      expect(empty.missing, isTrue, reason: 'in the extent but empty: final');
      expect(tileCalls, isEmpty, reason: 'both answered from the file');

      // Outside the extent (Tokyo-ish cell) is still the network's job.
      await m.loadTileDetailed(kOpenFreeMapVector, kZ, 3, 3);
      expect(tileCalls, hasLength(1));
      m.dispose();
    });

    test('a lost connection resumes by byte range and never re-sends',
        () async {
      host.dropAfter = 5000;
      final MapsController m = await loaded();
      await m.addArchive(
          name: 'r',
          url: 'https://host.example/r.pmtiles',
          sha256: _sha(host.file));
      await settle(m);
      expect(m.archives.single.state, ArchiveState.complete,
          reason: 'woke itself after the retry timer');
      expect(host.requests.length, greaterThanOrEqualTo(2));
      expect(host.requests[0].$1, 0, reason: 'first ask is the whole file');
      expect(host.requests[1].$1, 5000, reason: 'resume at the byte we had');
      expect(host.requests[1].$2, '"v1"', reason: 'If-Range carries the etag');
      expect(host.bytesSent, host.file.length,
          reason: 'each byte sent exactly once');
      m.dispose();
    });

    test('a server that ignores Range restarts cleanly, not corrupt', () async {
      host.dropAfter = 5000;
      host.ignoreRange = true;
      final MapsController m = await loaded();
      await m.addArchive(
          name: 'r',
          url: 'https://host.example/r.pmtiles',
          sha256: _sha(host.file));
      await settle(m);
      expect(m.archives.single.state, ArchiveState.complete);
      expect(host.bytesSent, 5000 + host.file.length);
      m.dispose();
    });

    test('a file replaced on the server restarts (If-Range mismatch)',
        () async {
      host.dropAfter = 5000;
      final MapsController m = await loaded();
      final Uint8List v2 = archiveBytes(layers: <String>['water', 'transportation']);
      await m.addArchive(name: 'r', url: 'https://host.example/r.pmtiles');
      // Let the first attempt be cut, then swap the file before the retry.
      for (int i = 0; i < 100 && host.requests.isEmpty; i++) {
        await pumpEventQueue();
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
      host
        ..file = v2
        ..etag = '"v2"';
      await settle(m);
      final MapArchive a = m.archives.single;
      expect(a.state, ArchiveState.complete);
      final File f = File('${dir.path}/archives/${a.id}.pmtiles');
      expect(await sha256OfFile(f), _sha(v2),
          reason: 'never stitched from two versions');
      m.dispose();
    });

    test('pause keeps the partial file; resume finishes it', () async {
      host.hold = Completer<void>();
      host.holdAfter = 8192;
      final MapsController m = await loaded();
      await m.addArchive(name: 'r', url: 'https://host.example/r.pmtiles');
      for (int i = 0; i < 100 && host.bytesSent < 8192; i++) {
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final MapArchive a = m.archives.single;
      m.pauseArchive(a);
      host.hold!.complete();
      await settle(m);
      expect(a.state, ArchiveState.paused);
      expect(m.archiveBytes, inInclusiveRange(8192, host.file.length));
      expect(m.archiveBytes, lessThan(host.file.length));
      m.resumeArchive(a);
      await settle(m);
      expect(a.state, ArchiveState.complete);
      expect(host.requests.last.$1, greaterThan(0), reason: 'resumed by range');
      m.dispose();
    });
  });

  test('a part file that already holds the whole file is accepted (416)',
      () async {
    // A crash after the last byte, before verification: the server answers
    // the resume request with 416 and the total length.
    final File part = File('${dir.path}/whole.part')..writeAsBytesSync(host.file);
    final DownloadResult r = await downloadResumable(
      fetch: host.call,
      url: Uri.parse('https://host.example/x.pmtiles'),
      part: part,
      shouldStop: () => false,
      allowedBytes: () => 1 << 40,
    );
    expect(r.end, DownloadEnd.complete);
    expect(r.bytes, host.file.length);
    expect(host.bytesSent, 0, reason: 'nothing re-downloaded');
  });

  group('refusals on arrival delete the file and say why', () {
    Future<MapArchive> add(MapsController m,
        {int? bytes, String? sha}) async {
      await m.addArchive(
          name: 'x',
          url: 'https://host.example/x.pmtiles',
          expectedBytes: bytes,
          sha256: sha);
      await settle(m);
      return m.archives.single;
    }

    test('wrong hash', () async {
      final MapsController m = await loaded();
      final MapArchive a = await add(m, sha: 'ab' * 32);
      expect(a.state, ArchiveState.failed);
      expect(a.failure, ArchiveFailure.badHash);
      expect(m.archiveBytes, 0);
      expect(Directory('${dir.path}/archives').listSync(), isEmpty);
      m.dispose();
    });

    test('wrong size', () async {
      final MapsController m = await loaded();
      final MapArchive a = await add(m, bytes: host.file.length - 1);
      expect(a.failure, ArchiveFailure.badSize);
      m.dispose();
    });

    test('a Protomaps-schema archive is refused, not installed blank',
        () async {
      host.file = archiveBytes(layers: <String>['earth', 'roads', 'water']);
      final MapsController m = await loaded();
      final MapArchive a = await add(m);
      expect(a.failure, ArchiveFailure.wrongSchema);
      m.dispose();
    });

    test('not a PMTiles file', () async {
      host.file = Uint8List.fromList(utf8.encode('<html>nope</html>' * 20));
      final MapsController m = await loaded();
      final MapArchive a = await add(m);
      expect(a.failure, ArchiveFailure.notPmTiles);
      m.dispose();
    });

    test('a dead URL', () async {
      host.status = 404;
      final MapsController m = await loaded();
      final MapArchive a = await add(m);
      expect(a.failure, ArchiveFailure.notFound);
      m.dispose();
    });

    test('setup refusals: name, https, duplicate, size over budget', () async {
      final MapsController m = await loaded();
      expect(await m.addArchive(name: ' ', url: 'https://h/x'),
          ArchiveRefusal.noName);
      expect(await m.addArchive(name: 'x', url: 'http://h/x'),
          ArchiveRefusal.badUrl);
      expect(await m.addArchive(name: 'x', url: 'nonsense'),
          ArchiveRefusal.badUrl);
      expect(
          await m.addArchive(
              name: 'x', url: 'https://h/x', expectedBytes: 6000 * 1000 * 1000),
          ArchiveRefusal.overBudget);
      expect(await m.addArchive(name: 'x', url: 'https://h/x'), isNull);
      expect(await m.addArchive(name: 'y', url: 'https://h/x'),
          ArchiveRefusal.duplicate);
      m.dispose();
    });
  });

  group('budget, lifecycle', () {
    test('an archive that outgrows the budget stops; raising it resumes',
        () async {
      host.file = archiveBytes(pad: 1500 * 1000);
      final MapsController m = await loaded();
      m.budgetMb = 1;
      await m.addArchive(name: 'big', url: 'https://host.example/big.pmtiles');
      await settle(m);
      final MapArchive a = m.archives.single;
      expect(a.state, ArchiveState.overBudget);
      expect(m.archiveBytes, lessThanOrEqualTo(1000 * 1000));
      expect(m.archiveBytes, greaterThan(0), reason: 'partial kept');
      await m.setBudgetMb(100);
      m.resumeArchive(a);
      await settle(m);
      expect(a.state, ArchiveState.complete);
      m.dispose();
    });

    test('state survives a restart; an interrupted download resumes',
        () async {
      final MapsController m = await loaded();
      await m.addArchive(name: 'r', url: 'https://host.example/r.pmtiles');
      await settle(m);
      m.dispose();
      final MapsController m2 = await loaded();
      expect(m2.archives.single.state, ArchiveState.complete);
      expect(m2.archiveBytes, host.file.length);
      final TileLoad t =
          await m2.loadTileDetailed(kOpenFreeMapVector, kZ, inside.$2, inside.$3);
      expect(t.bytes, isNotNull);
      m2.dispose();
    });

    test('expiry deletes an archive after its keep-for; delete frees bytes',
        () async {
      final MapsController m = await loaded();
      await m.addArchive(
          name: 'r', url: 'https://host.example/r.pmtiles', keepDays: 7);
      await settle(m);
      expect(m.archives, hasLength(1));
      now = now.add(const Duration(days: 8));
      await m.sweepExpired();
      expect(m.archives, isEmpty);
      expect(m.archiveBytes, 0);
      expect(Directory('${dir.path}/archives').listSync(), isEmpty);
      m.dispose();
    });

    test('an unreadable archive falls through to the network, not a blank',
        () async {
      final MapsController m = await loaded();
      await m.addArchive(name: 'r', url: 'https://host.example/r.pmtiles');
      await settle(m);
      final MapArchive a = m.archives.single;
      File('${dir.path}/archives/${a.id}.pmtiles').writeAsBytesSync(<int>[1, 2]);
      final TileLoad t =
          await m.loadTileDetailed(kOpenFreeMapVector, kZ, inside.$2, inside.$3);
      expect(t.bytes, isNotNull, reason: 'network answered');
      expect(tileCalls, hasLength(1));
      m.dispose();
    });
  });
}
