// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/maps/disk_space.dart';
import 'package:meshmore_sns_app/maps/map_archive.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/maps/network_gate.dart';
import 'package:meshmore_sns_app/maps/tile_math.dart';

import 'pmtiles_fixture.dart';

/// A host serving one file with enough range support to finish in one pass.
class _Host {
  _Host(this.file);

  final Uint8List file;
  int requests = 0;

  Future<ArchiveResponse> call(Uri url,
      {int? rangeStart, String? ifRange}) async {
    requests++;
    final int start = (rangeStart ?? 0).clamp(0, file.length);
    return ArchiveResponse(
      status: start > 0 ? 206 : 200,
      body: Stream<List<int>>.value(file.sublist(start)),
      contentLength: file.length - start,
      rangeStart: start > 0 ? start : null,
      rangeTotal: start > 0 ? file.length : null,
      etag: '"v1"',
    );
  }
}

class _Gate extends NetworkGate {
  _Gate({required this.metered});

  bool metered;

  @override
  Future<bool?> unmetered() async => !metered;
}

class _Disk extends DiskSpace {
  _Disk(this.free);

  int? free;

  @override
  Future<int?> allocatableBytes() async => free;
}

void main() {
  late Directory dir;
  late Uint8List archive;
  late _Host host;

  const GeoBox box = GeoBox(south: 38.0, west: -105.0, north: 39.0, east: -104.0);

  MapsController make({required NetworkGate gate, required DiskSpace disk}) =>
      MapsController(
        rootDir: () async => dir,
        fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs, int? maxBytes}) async =>
            FetchResult(FetchStatus.ok, bytes: Uint8List(10)),
        archiveFetcher: host.call,
        diskSpace: disk,
        networkGate: gate,
        pace: Duration.zero,
        retryFloor: const Duration(milliseconds: 20),
        catalogUrl: '',
      );

  /// Pumps until [done] is true, or up to ~5 s of event queue.
  Future<void> until(MapsController m, bool Function() done) async {
    for (int i = 0; i < 400; i++) {
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await m.idle();
      if (done()) return;
    }
  }

  /// Waits until no archive is actively downloading or waiting for the
  /// network, or gives up after ~5 s of pumped event queue.
  Future<void> settle(MapsController m) async {
    for (int i = 0; i < 500; i++) {
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await m.idle();
      final bool busy = m.archives.any((MapArchive a) =>
          a.state == ArchiveState.downloading ||
          a.state == ArchiveState.waitingForNetwork);
      if (!busy) return;
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = await Directory.systemTemp.createTemp('archive_gates');
    final Map<(int, int, int), List<int>> tiles = <(int, int, int), List<int>>{
      // One z6 cell and one z7 child: enough for a real PMTiles file.
      (6, 11, 24): <int>[0x1a, ...List<int>.generate(64, (int i) => i)],
      (7, 22, 49): <int>[0x1a, ...List<int>.generate(64, (int i) => 63 - i)],
    };
    archive = PmBuild(tiles,
            layers: <String>['water', 'transportation', 'place'],
            minLon: box.west,
            minLat: box.south,
            maxLon: box.east,
            maxLat: box.north,
            leafSize: 2)
        .build();
    host = _Host(archive);
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  group('Wi-Fi rule', () {
    test('a metered link parks the download instead of spending data',
        () async {
      final _Gate gate = _Gate(metered: true);
      final MapsController m =
          make(gate: gate, disk: const UnknownDiskSpace());
      await m.load();
      expect(m.wifiOnlyArchives, isTrue);
      await m.addArchive(name: 'Metered', url: 'https://h.example/a.pmtiles');
      await settle(m);
      expect(m.archives.single.state, ArchiveState.waitingForWifi);
      expect(host.requests, 0);
    });

    test('it resumes by itself once the link is unmetered', () async {
      final _Gate gate = _Gate(metered: true);
      final MapsController m =
          make(gate: gate, disk: const UnknownDiskSpace());
      await m.load();
      await m.addArchive(name: 'Later', url: 'https://h.example/a.pmtiles');
      await settle(m);
      expect(m.archives.single.state, ArchiveState.waitingForWifi);
      gate.metered = false;
      await until(
          m, () => m.archives.single.state == ArchiveState.complete);
      expect(m.archives.single.state, ArchiveState.complete);
      expect(host.requests, greaterThan(0));
    });

    test('turning the rule off lets a metered download start now', () async {
      final _Gate gate = _Gate(metered: true);
      final MapsController m =
          make(gate: gate, disk: const UnknownDiskSpace());
      await m.load();
      await m.addArchive(name: 'Now', url: 'https://h.example/a.pmtiles');
      await settle(m);
      expect(m.archives.single.state, ArchiveState.waitingForWifi);
      m.setWifiOnlyArchives(false);
      await until(
          m, () => m.archives.single.state == ArchiveState.complete);
      expect(m.archives.single.state, ArchiveState.complete);
    });

    test('the preference survives a restart', () async {
      final _Gate gate = _Gate(metered: false);
      final MapsController m = make(gate: gate, disk: const UnknownDiskSpace());
      await m.load();
      m.setWifiOnlyArchives(false);
      await m.idle();
      final MapsController again =
          make(gate: gate, disk: const UnknownDiskSpace());
      await again.load();
      expect(again.wifiOnlyArchives, isFalse);
      m.dispose();
      again.dispose();
    });
  });

  group('space preflight', () {
    test('a pack that does not fit is refused before it is downloaded',
        () async {
      final MapsController m = make(
          gate: const AlwaysUnmetered(),
          disk: _Disk(1 * 1000 * 1000));
      await m.load();
      final ArchiveRefusal? why = await m.addArchive(
        name: 'Too big',
        url: 'https://h.example/a.pmtiles',
        expectedBytes: archive.length,
      );
      expect(why, ArchiveRefusal.notEnoughSpace);
      expect(m.archives, isEmpty);
      expect(host.requests, 0);
    });

    test('a pack that fits, with the reserve kept back, installs', () async {
      final MapsController m = make(
          gate: const AlwaysUnmetered(),
          disk: _Disk(archive.length + kDownloadReserveBytes + 1));
      await m.load();
      final ArchiveRefusal? why = await m.addArchive(
        name: 'Fits',
        url: 'https://h.example/a.pmtiles',
        expectedBytes: archive.length,
      );
      expect(why, isNull);
      await until(m, () => m.archives.single.state == ArchiveState.complete);
      expect(m.archives.single.state, ArchiveState.complete);
    });

    test('a host that cannot answer is never a refusal', () async {
      final MapsController m = make(
          gate: const AlwaysUnmetered(), disk: const UnknownDiskSpace());
      await m.load();
      final ArchiveRefusal? why = await m.addArchive(
        name: 'Unknown room',
        url: 'https://h.example/a.pmtiles',
        expectedBytes: archive.length,
      );
      expect(why, isNull);
      await until(m, () => m.archives.single.state == ArchiveState.complete);
      expect(m.archives.single.state, ArchiveState.complete);
    });

    test('the reserve is part of the answer, not a separate check', () {
      expect(hasRoomFor(null, 1), isTrue);
      expect(hasRoomFor(kDownloadReserveBytes + 10, 10), isTrue);
      expect(hasRoomFor(kDownloadReserveBytes + 9, 10), isFalse);
    });
  });

  group('pack catalogue state', () {
    test('an empty bundle is a state the screen can state, not an error',
        () async {
      final MapsController m = make(
          gate: const AlwaysUnmetered(), disk: const UnknownDiskSpace());
      await m.load();
      await m.refreshCatalog();
      expect(m.catalog, isNotNull);
      expect(m.catalog!.fromBundle, isTrue);
      expect(m.catalogUrl, isEmpty);
      m.dispose();
    });
  });
}
