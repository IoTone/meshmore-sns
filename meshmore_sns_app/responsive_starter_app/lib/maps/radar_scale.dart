// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import '../util/mm_format.dart';

/// The distance a radar's rings are drawn at, in metres, from a third to the rim.
///
/// The dial labels its rings at a third, two thirds and the rim, so it is the
/// **step** that has to be a round number rather than the rim: 25 / 50 / 75 km
/// is read at a glance, while 66 / 132 / 198 asks the reader to do arithmetic
/// with a scale nobody chose. The step is the smallest one on a short ladder of
/// round numbers whose third-of-the-rim still covers the furthest peer, so the
/// outermost node is always inside the dial and every label is a number a person
/// would say out loud.
double radarRingStepMeters(double maxMeters) {
  if (!maxMeters.isFinite || maxMeters <= 0) return 10;
  // A third of the rim has to reach the furthest peer.
  final double need = maxMeters / 3;
  // 1, 2, 3, 5 and 7.5 per decade: 10 / 20 / 30 / 50 / 75, then 100 / 150 / 250.
  const List<double> mantissas = <double>[1, 2, 3, 5, 7.5];
  double decade = 1;
  for (int d = 0; d < 9; d++) {
    for (final double m in mantissas) {
      final double candidate = m * decade;
      if (candidate >= need) return candidate;
    }
    decade *= 10;
  }
  return math.max(1, need);
}

/// A distance on the dial, written the way a person reads it: "250 m", "1 km".
///
/// Whole numbers only, because the step is round by construction; a label with a
/// decimal means [radarRingStepMeters] was bypassed.
String radarDistanceLabel(double meters, {FormatPrefs? prefs}) {
  if (prefs != null) return MmFormat.step(meters, prefs: prefs);
  if (meters < 1000) return '${meters.round()} m';
  final double km = meters / 1000;
  return '${km.round()} km';
}
