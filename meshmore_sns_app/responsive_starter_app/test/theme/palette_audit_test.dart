// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

/// A palette has to *say* something, and two roles that look the same say
/// nothing.
///
/// The role floors (`role_floors_test`) hold every ink to a contrast floor, which
/// is legibility. This is the other half: the five semantic colours a screen can
/// draw — action, good, warning, alert, link — have to be tellable apart at a
/// glance, because they are the only cue distinguishing "press me" from "this is
/// fine" from "this is wrong" on a HUD with no room for words.
///
/// Two roles may share a hue if one is much brighter or darker than the other
/// (a dim and a bright amber still read as different things), which is why the
/// rule is a distance in HSL rather than a bare hue difference.
void main() {
  /// Hue in degrees, saturation and lightness in 0..1.
  ({double h, double s, double l}) hsl(Color c) {
    final double r = c.r, g = c.g, b = c.b;
    final double mx = math.max(r, math.max(g, b));
    final double mn = math.min(r, math.min(g, b));
    final double d = mx - mn;
    double h = 0;
    if (d > 0) {
      if (mx == r) {
        h = 60 * (((g - b) / d) % 6);
      } else if (mx == g) {
        h = 60 * ((b - r) / d + 2);
      } else {
        h = 60 * ((r - g) / d + 4);
      }
    }
    if (h < 0) h += 360;
    final double l = (mx + mn) / 2;
    final double s = d == 0 ? 0 : d / (1 - (2 * l - 1).abs());
    return (h: h, s: s, l: l);
  }

  /// How far apart two colours read, on a scale where 1.0 is "unmistakable".
  double separation(Color a, Color b) {
    final ({double h, double s, double l}) x = hsl(a);
    final ({double h, double s, double l}) y = hsl(b);
    double dh = (x.h - y.h).abs();
    if (dh > 180) dh = 360 - dh;
    // A grey has no hue worth comparing, so it is compared by lightness only.
    final double hue = (x.s < 0.15 || y.s < 0.15) ? 0 : dh / 60;
    return hue + (x.l - y.l).abs() * 2.5 + (x.s - y.s).abs();
  }

  for (final MmThemePreset preset in MmThemePreset.values) {
    final MmTokens t = mmSkinFor(preset).color;

    test('${preset.name}: the semantic colours are tellable apart', () {
      final List<(String, Color)> roles = <(String, Color)>[
        ('accent', t.accent),
        ('ok', t.ok),
        ('warn', t.warn),
        ('alert', t.alert),
        ('link', t.link),
      ];
      for (int i = 0; i < roles.length; i++) {
        for (int j = i + 1; j < roles.length; j++) {
          final double d = separation(roles[i].$2, roles[j].$2);
          expect(d, greaterThan(0.35),
              reason: '${preset.name}: ${roles[i].$1} and ${roles[j].$1} read '
                  'as the same colour (separation ${d.toStringAsFixed(2)})');
        }
      }
    });

    // Studio says state with ink weight on purpose: its whole language is
    // monochrome, and forcing a hue into it would be a different skin.
    final bool monochrome = preset == MmThemePreset.studio;

    test('${preset.name}: a semantic colour is not a wash', () {
      // A role drawn at 20 % saturation is a grey with a rumour of colour, and
      // on a HUD it reads as disabled rather than as a state.
      for (final (String name, Color colour) in <(String, Color)>[
        ('accent', t.accent),
        ('ok', t.ok),
        ('warn', t.warn),
        ('alert', t.alert),
        ('link', t.link),
      ]) {
        if (monochrome) continue;
        expect(hsl(colour).s, greaterThan(0.18),
            reason: '${preset.name}: $name is '
                '${(hsl(colour).s * 100).round()} % saturated');
      }
    });
  }
}
