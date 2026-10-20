// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
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

  test('OSM palette goes dark, keeps contrast, loses hue', () {
    final List<double> land = _apply(m(.15), <double>[242, 239, 233]);
    final List<double> sea = _apply(m(.15), <double>[170, 211, 223]);
    final List<double> road = _apply(m(.15), <double>[255, 255, 255]);
    final List<double> label = _apply(m(.15), <double>[40, 40, 40]);
    expect(_lum(land), lessThan(40), reason: 'pale land becomes dark');
    expect(_lum(sea), lessThan(90));
    expect(_lum(road) / 255, lessThan(.1), reason: 'white road fill: dark');
    expect(_lum(label), greaterThan(190), reason: 'dark text turns light');
    // contrast between a label and the land under it survives
    expect(_lum(label) - _lum(land), greaterThan(150));
    // desaturated: channel spread stays small
    final double spread = (sea.reduce((a, b) => a > b ? a : b) -
        sea.reduce((a, b) => a < b ? a : b));
    expect(spread, lessThan(60));
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
