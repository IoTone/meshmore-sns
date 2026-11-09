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

  /// Per-channel ratio against the source colour. A pure scale keeps every
  /// channel at the same ratio, which is what "hue preserved" means here.
  List<double> channelRatios(List<double> src, List<double> out) => <double>[
        out[0] / src[0],
        out[1] / src[1],
        out[2] / src[2],
      ];

  test('R79 the basemap dim scales RGB and never changes hue', () {
    final List<double> m = mmDimTileMatrix();
    final List<double> sea = _apply(m, <double>[170, 211, 223]);
    final List<double> ratios = channelRatios(<double>[170, 211, 223], sea);
    // Uniform scale = hue kept. R70-R73 inverted (water read orange) and
    // desaturated to 0.15 (no hue at all); both are gone.
    for (final double r in ratios) {
      expect(r, closeTo(kMmDimTileGain, 1e-9));
    }
    expect(sea[2], greaterThan(sea[0]),
        reason: 'sea stays blue-dominant, not inverted orange');
  });

  test('R79 the aerial-imagery basemap survives the treatment', () {
    // A single tile sample of vegetated ground: green dominant, some
    // blue. The old invert turned it magenta and the desaturation made
    // it grey, so the satellite source was unusable under Studio.
    final List<double> inTile = <double>[86, 121, 64];
    final List<double> out = _apply(mmDimTileMatrix(), inTile);
    expect(out[1], greaterThan(out[0]), reason: 'green stays green');
    expect(out[1], greaterThan(out[2]), reason: 'green stays green');
    final double scale = out[1] / inTile[1];
    expect(out[0], closeTo(inTile[0] * scale, 1e-9));
    expect(out[2], closeTo(inTile[2] * scale, 1e-9));
  });

  test('R79 the dimmed OSM palette stays readable', () {
    final List<double> m = mmDimTileMatrix();
    final List<double> land = _apply(m, <double>[242, 239, 233]);
    final List<double> sea = _apply(m, <double>[170, 211, 223]);
    final List<double> label = _apply(m, <double>[40, 40, 40]);
    expect(_lum(land), inInclusiveRange(160, 180), reason: 'land dimmed');
    expect(_lum(land), lessThan(255 * kMmDimTileGain + 0.5),
        reason: 'nothing brighter than the gain allows');
    // A pure scale keeps OSM's own ordering: land is lighter than water.
    expect((_lum(sea) - _lum(land)).abs(), greaterThan(20),
        reason: 'water stays distinguishable from land');
    expect(_lum(land), greaterThan(_lum(sea)));
    expect(wcag(_lum(label), _lum(land)), greaterThan(4.5),
        reason: 'label text keeps AA on land');
  });

  test('R79 the dimmed basemap is opted into per preset, never on a light '
      'ground', () {
    // R79 — the dim pushes a bright raster basemap under dark chrome, which is
    // a decision each skin takes rather than a rule the dark grounds inherit:
    // the radar, HUD, codec and pop skins draw their own map palettes and do
    // not want a second treatment. R115 settled the other half: a light ground
    // wants the basemap to belong to the page, so it is never dimmed.
    const Set<MmThemePreset> dimmed = <MmThemePreset>{
      MmThemePreset.studio,
      MmThemePreset.forest,
      MmThemePreset.umber,
    };
    for (final MmThemePreset p in MmThemePreset.values) {
      expect(mmSkinFor(p).shape.dimmedBasemap, dimmed.contains(p),
          reason: '$p');
      if (kMmPresets[p]!.isLight) {
        expect(mmSkinFor(p).shape.dimmedBasemap, isFalse,
            reason: '$p is a light ground: the basemap is the page, not '
                'something under it');
      }
    }
  });

  test('mmDimTileFilter is a colour-matrix filter', () {
    expect(mmDimTileFilter(), isA<ColorFilter>());
    expect(mmDimTileFilter(gain: 0.5), isNot(equals(mmDimTileFilter())));
  });

  testWidgets('basemapLayer(dim:) wires the tile builder', (t) async {
    late TileLayerProbe probe;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext c) {
      probe = TileLayerProbe(
        dim: basemapLayer(c, kBuiltInSources.first, dim: true).tileBuilder,
        plain: basemapLayer(c, kBuiltInSources.first).tileBuilder,
      );
      return const SizedBox();
    })));
    expect(probe.dim, isNotNull);
    expect(probe.plain, isNull, reason: 'other presets draw tiles unchanged');
  });
}

class TileLayerProbe {
  TileLayerProbe({required this.dim, required this.plain});
  final Object? dim;
  final Object? plain;
}
