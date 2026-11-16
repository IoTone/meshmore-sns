// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/theme/mm_tokens.dart';

/// D11.5 — a control's edge is its own role, and it has a floor.
///
/// WCAG 2.2 SC 1.4.11 asks 3:1 for the boundary of something you press. This
/// app drew every border with one token, `line`, which is also what it draws a
/// divider with — and a divider wants to be barely there. The result, measured
/// on 2026-11-05 and left open until the owner's LDMUX palettes arrived with
/// the separation already in them:
///
/// | preset | line on the page | what an outlined control was |
/// | --- | --- | --- |
/// | studio | 2.08:1 | outlined at 1.84:1 on its panel |
/// | seele | 1.46:1 | 1.34:1 |
/// | nerv | 1.46:1 | 1.35:1 |
/// | agHud | 1.38:1 | 1.26:1 |
/// | hyperlocal | 1.44:1 | 1.30:1 |
/// | drPop | 1.52:1 | 1.36:1 |
/// | recon | 2.75:1 | 2.60:1 |
///
/// On the light grounds the same value happened to pass, which is why the
/// defect read as a matter of taste between skins rather than as a floor
/// nobody met. `edge` is now that role: every preset states the smallest blend
/// of its own `line` toward its own `fg` that clears 3:1 on the page and on the
/// raised layer, so each skin keeps its hue. The LDMUX presets carry that
/// palette's own two values.
void main() {
  double chanLinear(double channel) {
    final double c = channel / 255;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4) as double;
  }

  double luminanceOf(Color c) =>
      0.2126 * chanLinear(c.r * 255) +
      0.7152 * chanLinear(c.g * 255) +
      0.0722 * chanLinear(c.b * 255);

  double ratio(Color a, Color b) {
    final double la = luminanceOf(a), lb = luminanceOf(b);
    final double hi = math.max(la, lb), lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  test(
      'every preset states an edge that clears 3:1 on every layer it is drawn '
      'on', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      final MmTokens t = kMmPresets[p]!;
      for (final MapEntry<String, Color> layer in <String, Color>{
        'base': t.base,
        'surface': t.surface,
        'raised': t.raised,
      }.entries) {
        expect(ratio(t.edge, layer.value), greaterThanOrEqualTo(2.99),
            reason: '${p.name}: edge on ${layer.key} is '
                '${ratio(t.edge, layer.value).toStringAsFixed(2)}:1, under the '
                '3:1 a control boundary is held to');
      }
    }
  });

  test('the edge is visibly stronger than the divider it used to be', () {
    // Two roles, two strengths. A preset may state an edge brighter than its
    // line; what it may not do is leave the divider as the loud value, because
    // a rule between two rows is meant to be barely there.
    for (final MmThemePreset p in MmThemePreset.values) {
      final MmTokens t = kMmPresets[p]!;
      final double edge = ratio(t.edge, t.base);
      final double line = ratio(t.line, t.base);
      expect(edge, greaterThan(line),
          reason: '${p.name}: the control boundary must read stronger than the '
              'divider, or the two roles have collapsed again');
      expect(line, lessThan(3.0),
          reason: '${p.name}: a divider at 3:1 is a control boundary wearing '
              'the wrong role');
    }
  });

  test('the Material outline role is the edge, not the divider', () {
    // Material draws a focused input's ring and an outlined button's border
    // from `outline`; `outlineVariant` is the quieter companion. They were the
    // same value, which is the same defect one layer down.
    for (final MmThemePreset p in MmThemePreset.values) {
      final MmTokens t = kMmPresets[p]!;
      final ColorScheme c = buildMmTheme(t).colorScheme;
      expect(c.outline, t.edge, reason: p.name);
      expect(c.outlineVariant, t.line, reason: p.name);
    }
  });

  test('a preset that states no edge draws exactly its divider, as before', () {
    // The derived default is what keeps a preset that has not been measured
    // unchanged. This is the property that let the port land preset by preset.
    const MmTokens bare = MmTokens(
      base: Color(0xFF101010),
      surface: Color(0xFF181818),
      surfaceAlt: Color(0xFF202020),
      line: Color(0xFF333333),
      fg: Color(0xFFEEEEEE),
      fgMuted: Color(0xFFAAAAAA),
      accent: Color(0xFFFFAA00),
      alert: Color(0xFFFF4444),
      ok: Color(0xFF44FF44),
    );
    expect(bare.edge, bare.line);
  });
}
