// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'geohash.dart';

/// One coverage observation: a ping that was sent from a position and whether a
/// responder answered it (`meshmore-telemetry-coverage-spec.md` §6, §8).
final class CoverageSample {
  const CoverageSample({
    required this.lat,
    required this.lon,
    required this.at,
    required this.answered,
    this.responderKey,
    this.rssi,
    this.snr,
    this.hops,
  });

  final double lat;
  final double lon;
  final DateTime at;
  final bool answered;

  /// Set only when this sample is a response: an unanswered ping has no
  /// responder, which is exactly why no edge can be inferred from it.
  final List<int>? responderKey;
  final int? rssi;
  final int? snr;
  final int? hops;

  String get cell => geohash6(lat, lon);
}

/// A link that was observed: this responder answered this device.
///
/// Thickness is the count of successful responses, never a modelled signal
/// strength, and an edge exists only where a response came back. The app never
/// infers one from proximity or from an advert heard
/// (`meshmore-telemetry-coverage-spec.md` §9).
final class CoverageEdge {
  const CoverageEdge({required this.responderKey, required this.responses});

  final List<int> responderKey;
  final int responses;
}

/// A cell's summary: the weighted score and the sample count beside it, because
/// "80 %" from two samples is not the same claim as "80 %" from forty.
final class CoverageCellSummary {
  const CoverageCellSummary({
    required this.cell,
    required this.score,
    required this.samples,
    required this.hidden,
  });

  final String cell;

  /// Time-weighted mean of the answered flag, 0..1.
  final double score;

  /// How many samples the score came from, including hidden ones.
  final int samples;

  /// Responses from a blocked key: counted as evidence, excluded from results,
  /// never drawn (§10).
  final int hidden;
}

/// The time weight of one sample: under a day, a week, a month, older.
double timeWeight(Duration age) {
  if (age < const Duration(days: 1)) return 1.0;
  if (age < const Duration(days: 7)) return 0.8;
  if (age < const Duration(days: 30)) return 0.5;
  return 0.2;
}

/// A cell's time-weighted score at [now].
///
/// Contradiction demotion: when a newer sample shows the opposite of an older
/// one, the older sample's weight drops to a tenth. It is not deleted, because
/// an old observation is weak evidence rather than no evidence.
CoverageCellSummary summariseCell(
  List<CoverageSample> samples, {
  required DateTime now,
  Set<String> blockedKeys = const <String>{},
}) {
  if (samples.isEmpty) {
    return const CoverageCellSummary(
        cell: '', score: 0, samples: 0, hidden: 0);
  }
  final List<CoverageSample> ordered = List<CoverageSample>.of(samples)
    ..sort((CoverageSample a, CoverageSample b) => a.at.compareTo(b.at));

  double weighted = 0;
  double total = 0;
  int hidden = 0;
  for (int i = 0; i < ordered.length; i++) {
    final CoverageSample s = ordered[i];
    final Duration age = now.difference(s.at);
    double w = timeWeight(age.isNegative ? Duration.zero : age);
    // Contradiction: any strictly newer sample with the opposite outcome.
    final bool contradicted = ordered
        .skip(i + 1)
        .any((CoverageSample later) => later.answered != s.answered);
    if (contradicted) w *= 0.1;

    final bool blocked = s.responderKey != null &&
        blockedKeys.contains(_keyId(s.responderKey!));
    if (blocked) {
      // Excluded from the result, counted here so the map does not silently
      // understate the mesh: a blocked key that answered still proves the link
      // existed.
      hidden++;
      continue;
    }
    total += w;
    if (s.answered) weighted += w;
  }
  return CoverageCellSummary(
    cell: ordered.first.cell,
    score: total == 0 ? 0 : weighted / total,
    samples: ordered.length,
    hidden: hidden,
  );
}

/// Every responder that actually answered, with its count.
///
/// Observed only: a sample that was not answered contributes nothing, and a
/// blocked key is excluded from the drawn set while still counting as evidence
/// in the summary above.
List<CoverageEdge> observedEdges(
  List<CoverageSample> samples, {
  Set<String> blockedKeys = const <String>{},
}) {
  final Map<String, int> counts = <String, int>{};
  final Map<String, List<int>> keys = <String, List<int>>{};
  for (final CoverageSample s in samples) {
    if (!s.answered) continue;
    final List<int>? key = s.responderKey;
    if (key == null) continue;
    final String id = _keyId(key);
    if (blockedKeys.contains(id)) continue;
    keys[id] = key;
    counts[id] = (counts[id] ?? 0) + 1;
  }
  return <CoverageEdge>[
    for (final MapEntry<String, int> e in counts.entries)
      CoverageEdge(responderKey: keys[e.key]!, responses: e.value),
  ];
}

String _keyId(List<int> key) =>
    key.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
