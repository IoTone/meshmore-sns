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
        expect(t.onAlert, t.fg, reason: '$p');
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
        expect(c.onError, t.fg, reason: '$p');
        expect(c.onErrorContainer, t.fg, reason: '$p');
      }
    });

    test('shape, and Material rounding, are untouched', () {
      for (final MmThemePreset p in legacy) {
        final MmSkin s = mmSkinFor(p);
        expect(s.shape.squareControls, isFalse, reason: '$p');
        expect(s.shape.hairlineWidth, 1.0, reason: '$p');
        final ThemeData td = buildMmTheme(s.color,
            fontFamily: s.type.displayFamily, shape: s.shape);
        final RoundedRectangleBorder chip =
            td.chipTheme.shape! as RoundedRectangleBorder;
        expect(chip.borderRadius, BorderRadius.circular(20), reason: '$p');
        expect(td.dialogTheme.shape, isNull, reason: '$p');
        expect(td.cardTheme.shape, isNull, reason: '$p');
        expect(td.appBarTheme.shape, isNull, reason: '$p');
      }
    });
  });

  group('R66 Studio edges', () {
    ThemeData studio() {
      final MmSkin s = mmSkinFor(MmThemePreset.studio);
      return buildMmTheme(s.color,
          fontFamily: s.type.displayFamily, shape: s.shape);
    }

    test('card has a 1px hairline side, square corners, no elevation', () {
      final MmTokens t = kMmPresets[MmThemePreset.studio]!;
      final RoundedRectangleBorder c =
          studio().cardTheme.shape! as RoundedRectangleBorder;
      expect(c.side.color, t.hairline);
      expect(c.side.width, 1.0);
      expect(c.borderRadius, BorderRadius.zero);
      expect(studio().cardTheme.elevation, isNull);
    });

    test('app bar ends in a 1px hairline (and only on the bottom)', () {
      final MmTokens t = kMmPresets[MmThemePreset.studio]!;
      final Border b = studio().appBarTheme.shape! as Border;
      expect(b.bottom.color, t.hairline);
      expect(b.bottom.width, 1.0);
      expect(b.top, BorderSide.none);
      expect(b.left, BorderSide.none);
      expect(b.right, BorderSide.none);
    });

    test('older presets: card and app-bar shape stay null', () {
      for (final MmThemePreset p in MmThemePreset.values) {
        if (p == MmThemePreset.studio) continue;
        final MmSkin s = mmSkinFor(p);
        final ThemeData td = buildMmTheme(s.color,
            fontFamily: s.type.displayFamily, shape: s.shape);
        expect(td.cardTheme.shape, isNull, reason: '$p');
        expect(td.appBarTheme.shape, isNull, reason: '$p');
      }
    });
  });

  group('Studio is a real layer stack', () {
    final MmTokens t = kMmPresets[MmThemePreset.studio]!;
    double lum(Color c) => c.computeLuminance();
    double ratio(Color hi, Color lo) => (lum(hi) + 0.05) / (lum(lo) + 0.05);

    test('supplies its own stack', () => expect(t.hasLayerStack, isTrue));

    test('monotonic, and each step distinguishable', () {
      final List<Color> l = t.layers;
      expect(l, hasLength(4));
      for (int i = 1; i < l.length; i++) {
        expect(lum(l[i]), greaterThan(lum(l[i - 1])), reason: 'step $i');
        expect(ratio(l[i], l[i - 1]), greaterThanOrEqualTo(1.08),
            reason: 'step $i must be visible');
      }
    });

    test('R65: the rule is visible on EVERY layer it separates', () {
      // R63 only checked the hairline over the panel; on `selected` the
      // old #3A3A3A was 1.06:1, i.e. invisible.
      for (final Color layer in t.layers) {
        expect(ratio(t.hairline, layer), greaterThanOrEqualTo(1.3),
            reason: 'hairline on $layer');
        expect(ratio(t.line, layer), greaterThanOrEqualTo(1.3),
            reason: 'line (dividers, outlines) on $layer');
        // ...but it stays a rule, well below text.
        expect(ratio(t.hairline, layer), lessThan(2.5),
            reason: 'hairline on $layer must stay subordinate');
      }
      expect(t.hairline, t.line, reason: 'one rule colour for Studio');
    });

    test('R65: accent, alert and ok are legible text on every layer', () {
      for (final Color layer in t.layers) {
        for (final Color c in <Color>[t.accent, t.alert, t.ok]) {
          expect(ratio(c, layer), greaterThanOrEqualTo(4.5),
              reason: '$c on $layer');
        }
      }
    });

    test('text tiers are ordered and legible on every layer', () {
      for (final Color layer in t.layers) {
        expect(ratio(t.fg, layer), greaterThanOrEqualTo(7));
        expect(ratio(t.fgMuted, layer), greaterThanOrEqualTo(4.5));
      }
      expect(lum(t.fgDisabled), lessThan(lum(t.fgMuted)));
    });

    double sat(Color c) => HSVColor.fromColor(c).saturation;

    test('R68: NO hue in chrome or accent — the accent is a light grey', () {
      for (final Color c in <Color>[
        ...t.layers,
        t.line,
        t.hairline,
        t.fg,
        t.fgMuted,
        t.fgDisabled,
        t.accent,
        t.onAccent,
        t.onAlert,
      ]) {
        expect(sat(c), lessThan(0.02), reason: '$c should be grey');
      }
      expect(sat(t.accent), 0.0, reason: 'zero saturation, so zero hue');
      // Light, not mid: selection is carried by lightness.
      expect(lum(t.accent), greaterThan(0.55));
      expect(lum(t.accent), lessThan(lum(t.fg)));
      expect(ratio(t.accent, t.base), greaterThanOrEqualTo(7));
      expect(ratio(t.accent, t.onAccent), greaterThanOrEqualTo(7));
    });

    test('R68: alert and ok are tints, never the loudest thing', () {
      for (final Color c in <Color>[t.alert, t.ok]) {
        expect(sat(c), lessThanOrEqualTo(0.30), reason: '$c');
      }
      // Still distinguishable from neutral text: a visible tint.
      expect(sat(t.alert), greaterThan(0.10));
      expect(sat(t.ok), greaterThan(0.10));
      // A filled alert carries dark text (light text was 1.5:1).
      expect(ratio(t.alert, t.onAlert), greaterThanOrEqualTo(7));
      final ColorScheme c = buildMmTheme(t).colorScheme;
      expect(c.onError, t.onAlert);
    });

    test('R68: accent text is legible on every layer', () {
      for (final Color layer in t.layers) {
        expect(ratio(t.accent, layer), greaterThanOrEqualTo(7),
            reason: 'accent on $layer');
      }
    });

    test('square controls, 1px hairline, no ornament', () {
      final MmSkin s = mmSkinFor(MmThemePreset.studio);
      expect(s.shape.corner, MmCorner.sharp);
      expect(s.shape.squareControls, isTrue);
      expect(s.shape.hairlineWidth, 1.0);
      expect(s.ornament.any, isFalse);
      final ThemeData td = buildMmTheme(s.color,
          fontFamily: s.type.displayFamily, shape: s.shape);
      expect(td.chipTheme.shape, const RoundedRectangleBorder());
      expect(td.cardTheme.shape,
          RoundedRectangleBorder(side: BorderSide(color: t.hairline)));
      expect(td.dialogTheme.shape, const RoundedRectangleBorder());
      expect(td.colorScheme.surfaceContainerHighest, t.selected);
      expect(td.colorScheme.onPrimary, t.onAccent);
    });

    test('persists by name and is selectable', () {
      expect(presetFromId('studio'), MmThemePreset.studio);
      expect(MmThemePreset.studio.label, contains('Studio'));
      // R64: the label used to promise "compact", but no density token
      // exists, so nothing about Studio is denser than the other skins.
      expect(
          MmThemePreset.studio.label.toLowerCase(), isNot(contains('compact')));
    });
  });
}
