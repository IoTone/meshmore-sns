// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

/// R63 — the layer-stack extension must be invisible to the six older
/// presets, and Studio must actually be a stack.
void main() {
  final List<MmThemePreset> legacy = <MmThemePreset>[
    for (final MmThemePreset p in MmThemePreset.values)
      if (p != MmThemePreset.studio) p,
  ];

  group('the six older presets are appearance-neutral', () {
    test('derived layer tokens equal the colours the app already drew', () {
      expect(legacy, hasLength(6));
      for (final MmThemePreset p in legacy) {
        final MmTokens t = kMmPresets[p]!;
        expect(t.hasLayerStack, isFalse, reason: '$p');
        expect(t.raised, t.surfaceAlt, reason: '$p');
        expect(t.selected, t.surfaceAlt, reason: '$p');
        expect(t.hairline, t.line, reason: '$p');
        expect(t.onAccent, t.base, reason: '$p');
      }
    });

    test('ThemeData colour roles are the pre-R63 mapping', () {
      for (final MmThemePreset p in legacy) {
        final MmTokens t = kMmPresets[p]!;
        final ColorScheme c = buildMmTheme(t).colorScheme;
        expect(c.surfaceContainerHigh, t.surfaceAlt, reason: '$p');
        expect(c.surfaceContainerHighest, t.surfaceAlt, reason: '$p');
        expect(c.onPrimary, t.base, reason: '$p');
        expect(c.onSecondary, t.base, reason: '$p');
        expect(c.outline, t.line, reason: '$p');
      }
    });

    test('shape, and Material rounding, are untouched', () {
      for (final MmThemePreset p in legacy) {
        final MmSkin s = mmSkinFor(p);
        expect(s.shape.squareControls, isFalse, reason: '$p');
        expect(s.shape.hairlineWidth, 1.0, reason: '$p');
        final ThemeData td =
            buildMmTheme(s.color, fontFamily: s.type.displayFamily,
                shape: s.shape);
        final RoundedRectangleBorder chip =
            td.chipTheme.shape! as RoundedRectangleBorder;
        expect(chip.borderRadius, BorderRadius.circular(20), reason: '$p');
        expect(td.dialogTheme.shape, isNull, reason: '$p');
        expect(td.cardTheme.shape, isNull, reason: '$p');
      }
    });
  });

  group('Studio is a real layer stack', () {
    final MmTokens t = kMmPresets[MmThemePreset.studio]!;
    double lum(Color c) => c.computeLuminance();
    double ratio(Color hi, Color lo) =>
        (lum(hi) + 0.05) / (lum(lo) + 0.05);

    test('supplies its own stack', () => expect(t.hasLayerStack, isTrue));

    test('monotonic, and each step distinguishable', () {
      final List<Color> l = t.layers;
      expect(l, hasLength(4));
      for (int i = 1; i < l.length; i++) {
        expect(lum(l[i]), greaterThan(lum(l[i - 1])), reason: 'step $i');
        expect(ratio(l[i], l[i - 1]), greaterThanOrEqualTo(1.08),
            reason: 'step $i must be visible');
      }
      expect(ratio(t.hairline, t.surface), greaterThanOrEqualTo(1.1));
    });

    test('text tiers are ordered and legible on every layer', () {
      for (final Color layer in t.layers) {
        expect(ratio(t.fg, layer), greaterThanOrEqualTo(7));
        expect(ratio(t.fgMuted, layer), greaterThanOrEqualTo(4.5));
      }
      expect(lum(t.fgDisabled), lessThan(lum(t.fgMuted)));
    });

    test('one accent: greyscale chrome, only the accent has a hue', () {
      double sat(Color c) {
        final HSVColor h = HSVColor.fromColor(c);
        return h.saturation;
      }
      for (final Color c in <Color>[
        ...t.layers, t.line, t.hairline, t.fg, t.fgMuted, t.fgDisabled
      ]) {
        expect(sat(c), lessThan(0.02), reason: '$c should be grey');
      }
      expect(sat(t.accent), greaterThan(0.3));
      expect(ratio(t.accent, t.surface), greaterThanOrEqualTo(4.5));
      expect(ratio(t.onAccent, t.accent) > 4.5 ||
          ratio(t.accent, t.onAccent) > 4.5, isTrue);
    });

    test('square controls, 1px hairline, no ornament', () {
      final MmSkin s = mmSkinFor(MmThemePreset.studio);
      expect(s.shape.corner, MmCorner.sharp);
      expect(s.shape.squareControls, isTrue);
      expect(s.shape.hairlineWidth, 1.0);
      expect(s.ornament.any, isFalse);
      final ThemeData td =
          buildMmTheme(s.color, fontFamily: s.type.displayFamily,
              shape: s.shape);
      expect(td.chipTheme.shape, const RoundedRectangleBorder());
      expect(td.cardTheme.shape, const RoundedRectangleBorder());
      expect(td.dialogTheme.shape, const RoundedRectangleBorder());
      expect(td.colorScheme.surfaceContainerHighest, t.selected);
      expect(td.colorScheme.onPrimary, t.onAccent);
    });

    test('persists by name and is selectable', () {
      expect(presetFromId('studio'), MmThemePreset.studio);
      expect(MmThemePreset.studio.label, contains('Studio'));
      // R64: the label used to promise "compact", but no density token
      // exists, so nothing about Studio is denser than the other skins.
      expect(MmThemePreset.studio.label.toLowerCase(),
          isNot(contains('compact')));
    });
  });
}
