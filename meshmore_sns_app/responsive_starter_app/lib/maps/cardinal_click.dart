// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// A click each time the phone is turned across a quarter turn.
///
/// A dial answers "which way am I facing" in a way a screen cannot while the
/// phone is in a hand at an angle, so the owner asked for the same fact in the
/// one channel that needs no eyes. The rule matters more than the buzz: it must
/// fire at the **marks** — north, east, south, west — and not while a hand
/// wobbles two degrees either side of one.
///
/// So a crossing is not a band change. When the heading enters a new quarter the
/// edge it crossed is remembered, and the click waits until the heading is
/// [hysteresisDegrees] past that edge. A phone sitting at 89°, 90°, 91°, 90°
/// fires nothing; a phone carried round to 95° fires once, at the moment the
/// bearing is unambiguously a new quarter.
class CardinalClick {
  CardinalClick({this.hysteresisDegrees = 3.0});

  /// How far past a mark the heading has to get before the click fires.
  final double hysteresisDegrees;

  int? _quarter;
  double? _edge;
  bool _armed = false;

  /// Feed every heading. Returns true exactly once per crossing, at the moment
  /// the crossing becomes unambiguous.
  bool update(double headingDegrees) {
    if (!headingDegrees.isFinite) return false;
    final double h = headingDegrees % 360;
    final double normalised = h < 0 ? h + 360 : h;
    final int quarter = (normalised / 90).floor() % 4;
    final int? previous = _quarter;
    if (previous == null) {
      // The first reading is where the phone started, not a crossing.
      _quarter = quarter;
      _edge = null;
      _armed = false;
      return false;
    }
    if (quarter != previous) {
      // The edge between the two quarters, in the direction of travel.
      _edge = (quarter == (previous + 1) % 4)
          ? quarter * 90.0
          : previous * 90.0;
      _quarter = quarter;
      _armed = true;
    }
    final double? edge = _edge;
    if (!_armed || edge == null) return false;
    final double travelled = (normalised - edge).abs();
    // 180 of travel is the long way round the back of the dial; past that the
    // reader has plainly left the mark.
    final double away = travelled > 180 ? 360 - travelled : travelled;
    if (away < hysteresisDegrees) return false;
    _armed = false;
    _edge = null;
    return true;
  }

  /// Forget where the phone was: the next reading starts a new calibration.
  void reset() {
    _quarter = null;
    _edge = null;
    _armed = false;
  }
}
