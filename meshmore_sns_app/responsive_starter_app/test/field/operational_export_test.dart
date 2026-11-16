// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/field/operational_export.dart';
import 'package:meshmore_sns_app/field/position_history.dart';
import 'package:meshmore_sns_app/meshcore/own_location.dart';
import 'package:meshmore_sns_app/telemetry/coverage_model.dart';

final DateTime t0 = DateTime.utc(2026, 11, 5, 12);

PositionSample _p(DateTime at) => PositionSample(
      latitude: 51.5,
      longitude: -0.12,
      at: at,
      source: OwnLocationSource.phoneFix,
    );

Map<String, Object?> _bundle({
  List<PositionSample> trail = const <PositionSample>[],
  List<CoverageSample> coverage = const <CoverageSample>[],
  DateTime? from,
  DateTime? to,
}) =>
    OperationalExport.build(
      trail: trail,
      places: const [],
      coverage: coverage,
      edges: const <CoverageEdge>[],
      from: from ?? t0,
      to: to ?? t0.add(const Duration(hours: 1)),
      now: t0,
    );

void main() {
  test('only the window is exported, and the manifest counts what it cut',
      () {
    final Map<String, Object?> b = _bundle(
      trail: <PositionSample>[
        _p(t0.subtract(const Duration(hours: 2))), // outside
        _p(t0.add(const Duration(minutes: 10))), // inside
        _p(t0.add(const Duration(minutes: 20))), // inside
      ],
    );
    final Map<String, Object?> manifest =
        b['manifest']! as Map<String, Object?>;
    expect(manifest['trailPoints'], 2);
    expect((b['trail']! as List<Object?>).length, 2);
  });

  test('answered and unanswered pings are counted apart, because the '
      'denominator is what was tried', () {
    final Map<String, Object?> b = _bundle(
      coverage: <CoverageSample>[
        CoverageSample(lat: 51.5, lon: -0.12, at: t0, answered: true),
        CoverageSample(lat: 51.5, lon: -0.12, at: t0, answered: false),
        CoverageSample(lat: 51.5, lon: -0.12, at: t0, answered: false),
      ],
    );
    final Map<String, Object?> manifest =
        b['manifest']! as Map<String, Object?>;
    expect(manifest['coverageAnsweredPings'], 1);
    expect(manifest['coverageUnansweredPings'], 2);
    expect(manifest['coverageSamples'], 3);
  });

  test('an empty window says why it is empty rather than implying a quiet '
      'mesh', () {
    final Map<String, Object?> b = _bundle();
    final Map<String, Object?> manifest =
        b['manifest']! as Map<String, Object?>;
    expect(manifest['trailPoints'], 0);
    expect(manifest['caveat'], contains('nothing was recorded'));
  });

  test('the file is JSON with a format and a version', () async {
    final String encoded =
        const JsonEncoder.withIndent('  ').convert(_bundle());
    final Map<String, dynamic> decoded =
        jsonDecode(encoded) as Map<String, dynamic>;
    expect(decoded['format'], 'meshmore.field');
    expect(decoded['version'], OperationalExport.formatVersion);
    expect(decoded['window'], isA<Map<String, dynamic>>());
  });
}
