// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/maps/vector_basemap.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

/// The vector basemap is drawn in each skin's own colours, so the same rules
/// that hold for text on a surface have to hold for a map: a road you can see, a
/// label you can read, and water that is not the same colour as grass.
///
/// Every value here is *derived* from the skin's tokens rather than written
/// down, which is what makes it worth testing: a palette change moves the map,
/// and the map is the one surface where a wrong colour reads as a broken tile
/// rather than as a styling choice.
void main() {
  double linear(double channel) {
    final double c = channel / 255;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4) as double;
  }

  double luminance(Color c) =>
      0.2126 * linear(c.r * 255) +
      0.7152 * linear(c.g * 255) +
      0.0722 * linear(c.b * 255);

  double contrast(Color a, Color b) {
    final double la = luminance(a);
    final double lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Perceptual distance in a cheap Oklab-ish space: enough to say "these two
  /// fills are the same colour" without pulling in a colour library.
  double distance(Color a, Color b) {
    double ch(double v) {
      final double c = v <= 0.04045
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return math.pow(c, 1 / 3).toDouble();
    }

    final double dr = ch(a.r) - ch(b.r);
    final double dg = ch(a.g) - ch(b.g);
    final double db = ch(a.b) - ch(b.b);
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  for (final MmThemePreset preset in MmThemePreset.values) {
    final VectorSkinPalette p = VectorSkinPalette.of(mmSkinFor(preset).color);

    test('${preset.name}: the map can be read', () {
      // Roads carry the picture. A road under 3:1 against its ground is a road
      // that vanishes on a phone in daylight.
      for (final (String name, Color colour) in <(String, Color)>[
        ('motorway', p.motorway),
        ('primary', p.primary),
        ('secondary', p.secondary),
        ('minor', p.minor),
      ]) {
        expect(contrast(colour, p.ground), greaterThanOrEqualTo(2.6),
            reason: '${preset.name}: $name road is not visible on the ground '
                '(${contrast(colour, p.ground).toStringAsFixed(2)}:1)');
      }
      // Labels are text: 4.5:1 on the ground they sit on.
      expect(contrast(p.placeMajor, p.ground), greaterThanOrEqualTo(4.5),
          reason: '${preset.name}: a place name is not readable');
      expect(contrast(p.streetLabel, p.ground), greaterThanOrEqualTo(3.0),
          reason: '${preset.name}: a street name is not readable');
      expect(contrast(p.waterLabel, p.water), greaterThanOrEqualTo(2.6),
          reason: '${preset.name}: a water label does not read on water');
    });

    test('${preset.name}: the fills tell each other apart', () {
      // Water, vegetation and ground are three different things, and on a small
      // screen they are three large areas: if two of them are the same colour
      // the map reads as a rendering fault.
      final List<(String, Color)> fills = <(String, Color)>[
        ('ground', p.ground),
        ('water', p.water),
        ('forest', p.forest),
        ('grass', p.grass),
        ('sand', p.sand),
        ('building', p.building),
      ];
      for (int i = 0; i < fills.length; i++) {
        for (int j = i + 1; j < fills.length; j++) {
          final double d = distance(fills[i].$2, fills[j].$2);
          expect(d, greaterThan(0.012),
              reason: '${preset.name}: ${fills[i].$1} and ${fills[j].$1} are '
                  'the same colour (${d.toStringAsFixed(3)})');
        }
      }
    });
  }
}
