// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/telemetry/coverage_model.dart';
import 'package:meshmore_sns_app/telemetry/coverage_pacing.dart';
import 'package:meshmore_sns_app/telemetry/geohash.dart';

void main() {
  group('the cell key', () {
    test('is the published geohash at precision 6', () {
      expect(geohash6(39.7392, -104.9903), '9xj64f');
      expect(geohash6(0, 0), 's00000');
      expect(geohash6(-33.8688, 151.2093), 'r3gx2f');
      expect(geohash6(51.5074, -0.1278), 'gcpvj0');
    });

    test('neighbours inside one cell share a key, and a step out does not', () {
      expect(geohash6(39.73921, -104.99031), geohash6(39.7392, -104.9903));
      expect(geohash6(39.74, -104.99), geohash6(39.7392, -104.9903));
      expect(geohash6(39.75, -104.99), isNot(geohash6(39.7392, -104.9903)));
    });

    test('refuses a coordinate outside the world, and a bad precision', () {
      expect(() => geohashOf(91, 0, 6), throwsArgumentError);
      expect(() => geohashOf(0, 181, 6), throwsArgumentError);
      expect(() => geohashOf(0, 0, 0), throwsArgumentError);
      expect(() => geohashOf(0, 0, 13), throwsArgumentError);
    });
  });

  group('pacing', () {
    final DateTime t0 = DateTime.utc(2026, 11, 5, 12);
    late DateTime now;
    CoveragePacing pacing() => CoveragePacing(clock: () => now);

    setUp(() {
      now = t0;
    });

    test('the 30 s floor holds; the 31st second is allowed', () {
      final CoveragePacing p = pacing();
      expect(p.check(cell: 'a'), isNull);
      p.markPinged(cell: 'a');
      now = t0.add(const Duration(seconds: 29));
      expect(p.check(cell: 'a'), CoveragePacingRefusal.tooSoon);
      expect(p.check(cell: 'b'), CoveragePacingRefusal.tooSoon);
      now = t0.add(const Duration(seconds: 31));
      expect(p.check(cell: 'b'), isNull);
    });

    test('a second ping in one cell inside the hour is refused', () {
      final CoveragePacing p = pacing();
      p.markPinged(cell: '9xj64f');
      now = t0.add(const Duration(minutes: 20));
      expect(p.check(cell: '9xj64f'), CoveragePacingRefusal.cellFresh);
      expect(p.check(cell: '9xj64g'), isNull);
      expect(p.nextAllowedAt('9xj64f'), t0.add(const Duration(hours: 1)));
      now = t0.add(const Duration(hours: 1));
      expect(p.check(cell: '9xj64f'), isNull);
    });

    test('the manual override buys one early ping in the hour, never the floor', () {
      final CoveragePacing p = pacing();
      p.markPinged(cell: '9xj64f');
      now = t0.add(const Duration(minutes: 10));
      expect(p.check(cell: '9xj64f', manual: true), isNull);
      expect(p.markPinged(cell: '9xj64f', manual: true), isTrue);
      now = t0.add(const Duration(minutes: 20));
      expect(p.check(cell: '9xj64f', manual: true),
          CoveragePacingRefusal.manualAlreadyUsed);
      // The floor still binds a manual ping.
      // A later hour frees the manual override, but the floor still binds it.
      now = t0.add(const Duration(hours: 1, minutes: 10));
      expect(p.markPinged(cell: 'other', manual: true), isTrue);
      now = t0.add(const Duration(hours: 1, minutes: 10, seconds: 5));
      expect(p.check(cell: 'third', manual: true),
          CoveragePacingRefusal.tooSoon);
    });

    test('the jittered interval stays inside 20 %', () {
      final CoveragePacing p =
          CoveragePacing(clock: () => now, random: Random(7));
      const Duration base = Duration(seconds: 30);
      for (int i = 0; i < 200; i++) {
        final Duration d = p.jittered(base);
        expect(d.inMilliseconds, inInclusiveRange(24000, 36000));
      }
      // With no random source the interval is exact, which is what a test that
      // pins a time wants.
      expect(pacing().jittered(base), base);
    });
  });

  group('the cell model', () {
    final DateTime now = DateTime.utc(2026, 11, 5, 12);
    final List<int> keyA = List<int>.generate(32, (int i) => i);
    final List<int> keyB = List<int>.generate(32, (int i) => 200 + i);

    CoverageSample sample(Duration age,
            {required bool answered, List<int>? key}) =>
        CoverageSample(
          lat: 39.7392,
          lon: -104.9903,
          at: now.subtract(age),
          answered: answered,
          responderKey: key,
        );

    test('time weight is 1.0 under a day, 0.8 under a week, 0.5 under a month, 0.2 older', () {
      expect(timeWeight(const Duration(hours: 2)), 1.0);
      expect(timeWeight(const Duration(days: 3)), 0.8);
      expect(timeWeight(const Duration(days: 20)), 0.5);
      expect(timeWeight(const Duration(days: 40)), 0.2);
    });

    test('an old success against a fresh failure is weak evidence, not no evidence', () {
      final List<CoverageSample> samples = <CoverageSample>[
        sample(const Duration(days: 40), answered: true, key: keyA),
        sample(const Duration(hours: 1), answered: false),
      ];
      final CoverageCellSummary s = summariseCell(samples, now: now);
      expect(s.samples, 2);
      // The old sample is 40 days old (0.2) and contradicted by the newer
      // failure, so it carries a tenth of that: 0.02 / (0.02 + 1.0).
      expect(s.score, closeTo(0.02 / 1.02, 1e-9));
      expect(s.score, greaterThan(0));
    });

    test('a newer opposite demotes the older sample to a tenth, not to nothing', () {
      final List<CoverageSample> samples = <CoverageSample>[
        sample(const Duration(hours: 3), answered: true, key: keyA),
        sample(const Duration(hours: 1), answered: false),
      ];
      final CoverageCellSummary s = summariseCell(samples, now: now);
      // 0.1 / (0.1 + 1.0)
      expect(s.score, closeTo(0.1 / 1.1, 1e-9));
      expect(s.score, greaterThan(0));
    });

    test('weights cancel when the outcomes agree, so age alone does not bias', () {
      final CoverageCellSummary s = summariseCell(<CoverageSample>[
        sample(const Duration(days: 40), answered: true, key: keyA),
        sample(const Duration(hours: 1), answered: true, key: keyB),
      ], now: now);
      expect(s.score, 1.0);
      expect(s.samples, 2);
    });

    test('agreement is not demoted', () {
      final CoverageCellSummary s = summariseCell(<CoverageSample>[
        sample(const Duration(hours: 3), answered: true, key: keyA),
        sample(const Duration(hours: 1), answered: true, key: keyB),
      ], now: now);
      expect(s.score, 1.0);
    });

    test('edges come only from responses, never from a sample that failed', () {
      final List<CoverageSample> samples = <CoverageSample>[
        sample(const Duration(hours: 1), answered: true, key: keyA),
        sample(const Duration(hours: 2), answered: true, key: keyA),
        sample(const Duration(hours: 3), answered: false),
      ];
      final List<CoverageEdge> edges = observedEdges(samples);
      expect(edges, hasLength(1));
      expect(edges.single.responses, 2);
      expect(edges.single.responderKey, keyA);
    });

    test('a blocked key is counted, excluded from the score and not drawn', () {
      final List<CoverageSample> samples = <CoverageSample>[
        sample(const Duration(hours: 1), answered: true, key: keyA),
        sample(const Duration(hours: 2), answered: true, key: keyB),
      ];
      final String blocked = keyB
          .map((int b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final CoverageCellSummary s =
          summariseCell(samples, now: now, blockedKeys: <String>{blocked});
      expect(s.hidden, 1);
      expect(s.score, 1.0, reason: 'the visible sample still answered');
      final List<CoverageEdge> edges =
          observedEdges(samples, blockedKeys: <String>{blocked});
      expect(edges, hasLength(1));
      expect(edges.single.responderKey, keyA);
    });

    test('an empty cell is zero, not a division by zero', () {
      final CoverageCellSummary s =
          summariseCell(const <CoverageSample>[], now: now);
      expect(s.score, 0);
      expect(s.samples, 0);
    });
  });
}
