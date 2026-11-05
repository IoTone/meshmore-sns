// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/field/position_history.dart';
import 'package:meshmore_sns_app/meshcore/own_location.dart';

final DateTime _t0 = DateTime.utc(2026, 11, 5, 12);

OwnLocation _own(double lat, double lon,
        {double? alt, OwnLocationSource source = OwnLocationSource.phoneFix}) =>
    OwnLocation(
      latitude: lat,
      longitude: lon,
      altitudeMeters: alt,
      source: source,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('retention', () {
    test('a point older than the window is dropped on load', () {
      final String raw = PositionHistoryStore.encode(<PositionSample>[
        PositionSample(
          latitude: 1,
          longitude: 1,
          at: _t0.subtract(PositionHistoryStore.retention +
              const Duration(minutes: 1)),
          source: OwnLocationSource.deviceReported,
        ),
        PositionSample(
          latitude: 2,
          longitude: 2,
          at: _t0,
          source: OwnLocationSource.deviceReported,
        ),
      ]);
      final List<PositionSample> rows =
          PositionHistoryStore.decode(raw, clock: () => _t0);
      expect(rows.map((PositionSample s) => s.latitude), <double>[2]);
    });

    test('a point dated in the future is dropped, so a backwards clock cannot '
        'park a row at the front of the trail', () {
      final String raw = PositionHistoryStore.encode(<PositionSample>[
        PositionSample(
          latitude: 3,
          longitude: 3,
          at: _t0.add(const Duration(days: 2)),
          source: OwnLocationSource.deviceReported,
        ),
      ]);
      expect(PositionHistoryStore.decode(raw, clock: () => _t0), isEmpty);
    });

    test('past the cap the oldest points go, not the newest', () {
      final List<PositionSample> rows = <PositionSample>[
        for (int i = 0; i < PositionHistoryStore.capacity + 10; i++)
          PositionSample(
            latitude: i.toDouble() / 1000,
            longitude: 0,
            at: _t0.subtract(Duration(seconds: PositionHistoryStore.capacity + 10 - i)),
            source: OwnLocationSource.deviceReported,
          ),
      ];
      final List<PositionSample> kept =
          PositionHistoryStore.prune(rows, now: _t0);
      expect(kept.length, PositionHistoryStore.capacity);
      expect(kept.last.at, rows.last.at);
    });

    test('a corrupt document is empty, not a crash', () {
      expect(PositionHistoryStore.decode('{"nope":1}', clock: () => _t0),
          isEmpty);
      expect(PositionHistoryStore.decode('[{"lat":"x"}]', clock: () => _t0),
          isEmpty);
      expect(PositionHistoryStore.decode(null, clock: () => _t0), isEmpty);
    });

    test('null island is not a fix', () {
      final String raw = PositionHistoryStore.encode(<PositionSample>[
        PositionSample(
          latitude: 0,
          longitude: 0,
          at: _t0,
          source: OwnLocationSource.phoneFix,
        ),
      ]);
      expect(PositionHistoryStore.decode(raw, clock: () => _t0), isEmpty);
    });
  });

  group('append', () {
    test('a stationary fix is not a point', () {
      final List<PositionSample> rows =
          PositionHistoryStore.append(<PositionSample>[], _own(51.5, -0.12),
              now: _t0);
      final List<PositionSample> again =
          PositionHistoryStore.append(rows, _own(51.5, -0.12),
              now: _t0.add(const Duration(seconds: 5)));
      expect(again, same(rows));
    });

    test('moving past the minimum is a point, with its source and altitude', () {
      final List<PositionSample> rows =
          PositionHistoryStore.append(<PositionSample>[], _own(51.5, -0.12),
              now: _t0);
      final List<PositionSample> moved = PositionHistoryStore.append(
          rows, _own(51.5002, -0.12, alt: 42, source: OwnLocationSource.deviceReported),
          now: _t0.add(const Duration(minutes: 1)));
      expect(moved.length, 2);
      expect(moved.last.altitudeMeters, 42);
      expect(moved.last.source, OwnLocationSource.deviceReported);
    });

    test('a clock that steps backwards adds nothing', () {
      final List<PositionSample> rows =
          PositionHistoryStore.append(<PositionSample>[], _own(51.5, -0.12),
              now: _t0);
      final List<PositionSample> back = PositionHistoryStore.append(
          rows, _own(51.6, -0.12),
          now: _t0.subtract(const Duration(minutes: 5)));
      expect(back, same(rows));
    });
  });

  group('recorder', () {
    test('records a moved fix and ignores a jittered one', () async {
      final PositionRecorder rec = PositionRecorder(
        clock: () => _t0,
        persist: false,
      );
      await rec.load();
      expect(rec.record(_own(51.5, -0.12)), isTrue);
      expect(rec.record(_own(51.5, -0.12)), isFalse);
      expect(rec.rows.length, 1);
    });

    test('loads what a previous run saved', () async {
      final PositionRecorder first = PositionRecorder(clock: () => _t0);
      await first.load();
      first.record(_own(51.5, -0.12));
      // The recorder persists at most every thirty seconds; the first sample
      // is written immediately because there is no previous write yet.
      await PositionHistoryStore.save(first.rows);

      final PositionRecorder second = PositionRecorder(clock: () => _t0);
      await second.load();
      expect(second.rows.length, 1);
      expect(second.rows.single.latitude, closeTo(51.5, 1e-9));
    });

    test('clear empties both the rows and the store', () async {
      final PositionRecorder rec = PositionRecorder(clock: () => _t0);
      await rec.load();
      rec.record(_own(51.5, -0.12));
      await PositionHistoryStore.save(rec.rows);
      await rec.clear();
      expect(rec.rows, isEmpty);
      expect(await PositionHistoryStore.load(clock: () => _t0), isEmpty);
    });
  });
}
