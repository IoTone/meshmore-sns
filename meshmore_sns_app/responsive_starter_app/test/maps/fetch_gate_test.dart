// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/maps/fetch_gate.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/map_source.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';

/// R81 — a panning map must not pile up requests for tiles it has left.
void main() {
  group('TileFetchGate', () {
    test('never runs more than maxConcurrent, and runs the newest first',
        () async {
      final TileFetchGate gate = TileFetchGate(maxConcurrent: 2, maxQueued: 10);
      final List<Completer<void>> held = <Completer<void>>[];
      final List<int> started = <int>[];
      int peak = 0;
      Future<int> job(int i) => gate.run(() async {
            started.add(i);
            peak = peak < gate.running ? gate.running : peak;
            final Completer<void> c = Completer<void>();
            held.add(c);
            await c.future;
            return i;
          });
      final List<Future<int>> all = <Future<int>>[for (int i = 0; i < 6; i++) job(i)];
      await pumpEventQueue();
      expect(started, <int>[0, 1], reason: 'two slots, four waiting');
      expect(gate.queued, 4);
      held[0].complete();
      await pumpEventQueue();
      expect(started.last, 5, reason: 'LIFO: the most recent request next');
      held[1].complete();
      await pumpEventQueue();
      expect(started.last, 4);
      for (final Completer<void> c in held.skip(2)) {
        c.complete();
      }
      while (started.length < 6) {
        await pumpEventQueue();
        for (final Completer<void> c in held) {
          if (!c.isCompleted) c.complete();
        }
      }
      await Future.wait(all);
      expect(peak, 2);
      expect(started.toSet(), <int>{0, 1, 2, 3, 4, 5});
    });

    test('a request pushed out of the queue is dropped, never run', () async {
      final TileFetchGate gate = TileFetchGate(maxConcurrent: 1, maxQueued: 2);
      final Completer<void> block = Completer<void>();
      final List<int> ran = <int>[];
      final Future<void> first = gate.run(() => block.future);
      final List<Future<Object?>> rest = <Future<Object?>>[
        for (int i = 1; i <= 5; i++)
          gate.run<Object?>(() async {
            ran.add(i);
            return i;
          }).then<Object?>((Object? v) => v,
              onError: (Object e) => e is TileDropped ? 'dropped' : e),
      ];
      await pumpEventQueue();
      expect(gate.queued, 2);
      block.complete();
      await first;
      final List<Object?> out = await Future.wait(rest);
      expect(out.sublist(0, 3), everyElement('dropped'),
          reason: 'requests 1-3 were the oldest and left the queue');
      expect(ran.toSet(), <int>{4, 5}, reason: 'dropped work never ran');
    });

    test('an exception in a task frees its slot', () async {
      final TileFetchGate gate = TileFetchGate(maxConcurrent: 1);
      await expectLater(
          gate.run<void>(() async => throw StateError('x')), throwsStateError);
      expect(await gate.run(() async => 7), 7);
      expect(gate.running, 0);
    });
  });

  group('MapsController viewing fetches', () {
    late Directory dir;
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      dir = await Directory.systemTemp.createTemp('gate_test');
    });

    test('abandoned tiles are not requested after a fast pan', () async {
      final List<Completer<FetchResult>> pending = <Completer<FetchResult>>[];
      final List<String> asked = <String>[];
      final MapsController m = MapsController(
        rootDir: () async => dir,
        fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs, int? maxBytes}) {
          asked.add(u.path);
          final Completer<FetchResult> c = Completer<FetchResult>();
          pending.add(c);
          return c.future;
        },
        pace: Duration.zero,
      );
      await m.load();
      // 40 tiles asked for in one burst: 4 run, 32 queue, 4 are pushed out.
      final List<Future<Uint8List?>> loads = <Future<Uint8List?>>[
        for (int i = 0; i < 40; i++) m.loadTile(kOsmVector, 14, 100, i),
      ];
      await pumpEventQueue();
      expect(m.viewGate.running, 4);
      expect(m.viewGate.queued, 32);
      Future<void> drain() async {
        for (int guard = 0; guard < 80; guard++) {
          await pumpEventQueue();
          for (final Completer<FetchResult> c in pending) {
            if (!c.isCompleted) {
              c.complete(FetchResult(FetchStatus.ok, bytes: Uint8List(10)));
            }
          }
        }
      }

      await drain();
      final List<Uint8List?> got = await Future.wait(loads);
      expect(asked, hasLength(36), reason: '4 + 32; 4 were abandoned');
      for (int i = 4; i < 8; i++) {
        expect(asked.any((String p) => p.endsWith('/14/100/$i.pbf')), isFalse,
            reason: 'tile $i left the queue and was never fetched');
        expect(got[i], isNull);
      }
      expect(got.where((Uint8List? b) => b != null), hasLength(36));
      m.dispose();
    });

    test('a 404 is a final answer: reported missing, asked once', () async {
      int calls = 0;
      final MapsController m = MapsController(
        rootDir: () async => dir,
        fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs, int? maxBytes}) async {
          calls++;
          return const FetchResult(FetchStatus.missing);
        },
        pace: Duration.zero,
      );
      await m.load();
      final TileLoad a = await m.loadTileDetailed(kOsmVector, 5, 1, 1);
      final TileLoad b = await m.loadTileDetailed(kOsmVector, 5, 1, 1);
      expect(a.missing, isTrue);
      expect(a.bytes, isNull);
      expect(b.missing, isTrue);
      expect(calls, 1, reason: 'remembered for the run');
      m.dispose();
    });

    test('a network failure is NOT missing', () async {
      final MapsController m = MapsController(
        rootDir: () async => dir,
        fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs, int? maxBytes}) async =>
            const FetchResult(FetchStatus.failed),
        pace: Duration.zero,
      );
      await m.load();
      final TileLoad a = await m.loadTileDetailed(kOsmVector, 5, 1, 1);
      expect(a.missing, isFalse);
      expect(a.bytes, isNull);
      m.dispose();
    });
  });
}
