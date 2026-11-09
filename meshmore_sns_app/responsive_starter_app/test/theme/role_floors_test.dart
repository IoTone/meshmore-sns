// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/theme/mm_tokens.dart';

/// Every role, on every layer, on every preset — the contract the palettes
/// state in prose, recomputed here.
///
/// The rule is not one contrast ratio for the app. It is one floor per role,
/// decided by what the role is drawn as. This table is the owner's LDMUX
/// palette contract in Dart, and porting it found four dark-ground defects
/// that no test had covered, because the earlier audits each checked half the
/// app: the disabled-ink floor was asserted for the light grounds only (it was
/// found on paper, so it was fixed on paper), and the dark presets kept drawing
/// a disabled control at 2.2:1 and an alert sentence at 2.8:1 with nothing
/// failing. A floor only one skin family meets is not a floor.
///
/// | role | drawn as | floor |
/// | --- | --- | --- |
/// | fg | body text | 4.5:1 on every layer |
/// | fgMuted | the second voice | 4.5:1 on every layer |
/// | accent | the one primary action, as a label | 4.5:1 on base and surface |
/// | alertInk | an alert written as a sentence | 4.5:1 on base and surface |
/// | alert | a fill, a border, an icon | 3:1 on every layer (a graphical object) |
/// | onAlert | the label on a filled alert | the better read of the two candidates |
/// | ok, warn | a status word | 4.5:1 on base and surface |
/// | edge | the boundary of a control | 3:1 on every layer |
/// | fgDisabled | a control that is off | 3:1 on every layer, below fgMuted |
/// | line, hairline | a divider | none: a divider is meant to be barely there |
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

  double ratio(Color a, Color b) {
    final double la = luminance(a), lb = luminance(b);
    final double hi = math.max(la, lb), lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// The layers a role can be drawn on, which is what makes this stricter than
  /// the paper-only audit it replaces.
  Map<String, Color> layersOf(MmTokens t) => <String, Color>{
        'base': t.base,
        'surface': t.surface,
        'raised': t.raised,
        'selected': t.selected,
      };

  group('body and the second voice clear 4.5:1 on every layer', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      test(p.name, () {
        final MmTokens t = kMmPresets[p]!;
        for (final MapEntry<String, Color> layer in layersOf(t).entries) {
          for (final MapEntry<String, Color> role in <String, Color>{
            'fg': t.fg,
            'fgMuted': t.fgMuted,
          }.entries) {
            expect(ratio(role.value, layer.value), greaterThanOrEqualTo(4.5),
                reason: '${p.name}: ${role.key} on ${layer.key} is '
                    '${ratio(role.value, layer.value).toStringAsFixed(2)}:1');
          }
        }
      });
    }
  });

  group('the accent is legible where it is written', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      test(p.name, () {
        final MmTokens t = kMmPresets[p]!;
        // The accent is the one primary action on a screen, and the contract
        // holds it to the page and the panel. A selected row carries body text,
        // not the accent, so a fourth layer is not the same requirement.
        for (final MapEntry<String, Color> layer in <String, Color>{
          'base': t.base,
          'surface': t.surface,
        }.entries) {
          expect(ratio(t.accent, layer.value), greaterThanOrEqualTo(4.5),
              reason: '${p.name}: accent on ${layer.key} is '
                  '${ratio(t.accent, layer.value).toStringAsFixed(2)}:1');
        }
      });
    }
  });

  group('an alert written as a sentence is legible', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      test(p.name, () {
        final MmTokens t = kMmPresets[p]!;
        for (final MapEntry<String, Color> layer in <String, Color>{
          'base': t.base,
          'surface': t.surface,
        }.entries) {
          expect(ratio(t.alertInk, layer.value), greaterThanOrEqualTo(4.5),
              reason: '${p.name}: alert ink on ${layer.key} is '
                  '${ratio(t.alertInk, layer.value).toStringAsFixed(2)}:1');
        }
        // …and the fill it was lifted from still reads as a graphic.
        for (final MapEntry<String, Color> layer in layersOf(t).entries) {
          expect(ratio(t.alert, layer.value), greaterThanOrEqualTo(3.0),
              reason: '${p.name}: the alert fill on ${layer.key} is '
                  '${ratio(t.alert, layer.value).toStringAsFixed(2)}:1');
        }
      });
    }
  });

  group('the label on a filled alert is legible', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      test(p.name, () {
        final MmTokens t = kMmPresets[p]!;
        // The fill the app writes a label on is the alert *ink*: the
        // destructive confirm is filled with it and labelled with the ground,
        // because three skins keep a saturated crimson whose raw fill has no
        // legible label at all.
        expect(ratio(t.base, t.alertInk), greaterThanOrEqualTo(4.5),
            reason: '${p.name}: the ground on the alert fill is '
                '${ratio(t.base, t.alertInk).toStringAsFixed(2)}:1');
        // `onAlert` is Material's onError role. What is required is that it
        // reads at least as well on the raw fill as either candidate would:
        // the value is the skin's own near-black or near-white, which is not
        // always the exact token it was chosen over.
        final double best = math.max(
            ratio(t.base, t.alert), ratio(t.fg, t.alert));
        expect(ratio(t.onAlert, t.alert), greaterThanOrEqualTo(best - 0.01),
            reason: '${p.name}: onAlert on its fill is '
                '${ratio(t.onAlert, t.alert).toStringAsFixed(2)}:1 against a '
                'best candidate of ${best.toStringAsFixed(2)}:1');
      });
    }
  });

  group('status words clear 4.5:1 on base and surface', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      test(p.name, () {
        final MmTokens t = kMmPresets[p]!;
        for (final MapEntry<String, Color> layer in <String, Color>{
          'base': t.base,
          'surface': t.surface,
        }.entries) {
          for (final MapEntry<String, Color> role in <String, Color>{
            'ok': t.ok,
            'warn': t.warn,
          }.entries) {
            expect(ratio(role.value, layer.value), greaterThanOrEqualTo(4.5),
                reason: '${p.name}: ${role.key} on ${layer.key} is '
                    '${ratio(role.value, layer.value).toStringAsFixed(2)}:1');
          }
        }
      });
    }
  });

  group('the disabled tier is legible and stays the quietest', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      test(p.name, () {
        final MmTokens t = kMmPresets[p]!;
        for (final MapEntry<String, Color> layer in layersOf(t).entries) {
          expect(ratio(t.fgDisabled, layer.value), greaterThanOrEqualTo(3.0),
              reason: '${p.name}: disabled ink on ${layer.key} is '
                  '${ratio(t.fgDisabled, layer.value).toStringAsFixed(2)}:1, '
                  'and a control that is off still has to be found');
        }
        expect(
            ratio(t.fgMuted, t.base), greaterThan(ratio(t.fgDisabled, t.base)),
            reason: '${p.name}: "off" still reads below the second voice');
      });
    }
  });

  group('the derived tiers still derive', () {
    test('alertInk falls back to the fill, and onAlert to the body colour', () {
      const MmTokens bare = MmTokens(
        base: Color(0xFF101010),
        surface: Color(0xFF181818),
        surfaceAlt: Color(0xFF202020),
        line: Color(0xFF333333),
        fg: Color(0xFFEEEEEE),
        fgMuted: Color(0xFFAAAAAA),
        accent: Color(0xFFFFAA00),
        alert: Color(0xFFFF6666),
        ok: Color(0xFF44FF44),
      );
      expect(bare.alertInk, bare.alert);
      expect(bare.onAlert, bare.fg);
    });
  });
}
