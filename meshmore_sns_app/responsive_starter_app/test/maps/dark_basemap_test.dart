// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/maps/basemap.dart';
import 'package:meshmore_sns_app/maps/map_source.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

/// Apply a 4x5 colour matrix (as ColorFilter.matrix does) to an RGB.
List<double> _apply(List<double> m, List<double> rgb) => <double>[
      for (int r = 0; r < 3; r++)
        (m[r * 5] * rgb[0] +
                m[r * 5 + 1] * rgb[1] +
                m[r * 5 + 2] * rgb[2] +
                m[r * 5 + 4])
            .clamp(0, 255)
            .toDouble()
    ];

double _lum(List<double> c) => 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];

void main() {
  List<double> m(double s) => mmDarkTileMatrix(saturation: s);

  double wcag(double lumA, double lumB) {
    double lin(double v) {
      final double c = v / 255;
      return c <= .03928
          ? c / 12.92
          : math.pow((c + .055) / 1.055, 2.4) as double;
    }

    final double a = lin(lumA), b = lin(lumB);
    final double hi = math.max(a, b), lo = math.min(a, b);
    return (hi + .05) / (lo + .05);
  }

  test('OSM palette: dark but readable (R73 retune), roads and labels survive',
      () {
    final List<double> land = _apply(m(.15), <double>[242, 239, 233]);
    final List<double> sea = _apply(m(.15), <double>[170, 211, 223]);
    final List<double> casing = _apply(m(.15), <double>[187, 187, 187]);
    final List<double> label = _apply(m(.15), <double>[40, 40, 40]);
    // R70 put land below 40 (roads/labels vanished on the device).
    expect(_lum(land), inInclusiveRange(55, 75), reason: 'land mid-dark');
    expect(_lum(sea) - _lum(land), greaterThan(20),
        reason: 'water stays distinguishable from land');
    expect(_lum(casing) - _lum(land), greaterThan(30),
        reason: 'road casings read against land');
    expect(_lum(label), greaterThan(200), reason: 'dark text turns light');
    expect(wcag(_lum(label), _lum(land)), greaterThan(7),
        reason: 'label text on land is AAA');
    // still unmistakably dark: nothing but labels exceeds mid-grey
    expect(_lum(sea), lessThan(110));
    // desaturated: channel spread stays small
    final double spread = (sea.reduce(math.max) - sea.reduce(math.min));
    expect(spread, lessThan(20));
  });

  test('only Studio opts into the dark basemap', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      expect(mmSkinFor(p).shape.darkBasemap, p == MmThemePreset.studio,
          reason: '$p');
    }
  });

  test('mmDarkTileFilter is a colour-matrix filter', () {
    expect(mmDarkTileFilter(), isA<ColorFilter>());
    expect(mmDarkTileFilter(saturation: 0), isNot(equals(mmDarkTileFilter())));
  });

  testWidgets('basemapLayer(dark:) wires the tile builder', (t) async {
    late TileLayerProbe probe;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext c) {
      probe = TileLayerProbe(
        dark: basemapLayer(c, kBuiltInSources.first, dark: true).tileBuilder,
        light: basemapLayer(c, kBuiltInSources.first).tileBuilder,
      );
      return const SizedBox();
    })));
    expect(probe.dark, isNotNull);
    expect(probe.light, isNull, reason: 'other presets draw tiles unchanged');
  });
}

class TileLayerProbe {
  TileLayerProbe({required this.dark, required this.light});
  final Object? dark;
  final Object? light;
}
