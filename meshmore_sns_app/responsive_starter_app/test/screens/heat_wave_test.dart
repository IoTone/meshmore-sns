// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/screens/sns_cells_view.dart';

/// The heat field's wave is the view's only motion, and it is a function of the
/// clock. These are the two properties that were wrong on the handset: the band
/// advanced once a second instead of every frame, and the field it crosses had
/// hexagons drawn in a square box.
void main() {
  test('the wave moves with the clock, not once a second', () {
    const double h = 2000, hex = 24;
    final double a = heatWaveY(1000, h, hex);
    final double b = heatWaveY(1100, h, hex);
    expect(b, greaterThan(a), reason: 'the band travels downward');
    // A hundredth of a second of clock is more than a pixel of travel: the
    // repaint rate is what the eye reads as motion, so a per-second step was one
    // frame every three and a half seconds.
    expect((heatWaveY(1016, h, hex) - a).abs(), greaterThan(1.0),
        reason: 'a 16 ms frame moves the band');
  });

  test('the wave takes one period to cross, and wraps', () {
    const double h = 2000, hex = 24;
    // It starts above the top edge and ends below the bottom one, so it enters
    // and leaves rather than appearing in place.
    expect(heatWaveY(0, h, hex), lessThan(0));
    expect(heatWaveY(kHeatWavePeriodMs - 1, h, hex), greaterThan(h));
    // One period later it is where it was.
    expect(heatWaveY(kHeatWavePeriodMs, h, hex), closeTo(heatWaveY(0, h, hex), 1e-9));
    expect(heatWaveY(kHeatWavePeriodMs * 3 + 500, h, hex),
        closeTo(heatWaveY(500, h, hex), 1e-9));
  });

  test('a taller screen travels further, in the same period', () {
    const double hex = 24;
    const int half = kHeatWavePeriodMs ~/ 2;
    // Half way through the period the band is half way down whichever screen it
    // is on, so the travel distance is the screen's own height.
    expect(heatWaveY(half, 1000, hex), closeTo(500, 12));
    expect(heatWaveY(half, 2000, hex), closeTo(1000, 12));
    expect(heatWaveY(half, 2000, hex) - heatWaveY(0, 2000, hex),
        greaterThan(heatWaveY(half, 1000, hex) - heatWaveY(0, 1000, hex)));
  });
}
