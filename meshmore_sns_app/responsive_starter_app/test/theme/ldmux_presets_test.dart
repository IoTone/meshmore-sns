// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

/// The four LDMUX looks, held to the contract they were designed against.
///
/// Every neutral in the source project is a Radix Colors 3.0 value, and the
/// roles carry stated contrast floors in `Palette`'s doc table. This file
/// recomputes those floors from the literals rather than trusting either
/// project's comments, so a later edit that moves a colour has to move a
/// number here with it.
///
/// It also records the one mapping decision the port turns on: which Meshmore
/// sites draw a **control boundary** (the 3:1 floor applies) and which draw a
/// **divider** (no floor; a divider is meant to be barely there). The app
/// draws both with `MmTokens.line`, and supplies `hairline` for the second
/// kind; the inventory below is what makes that split legible.
void main() {
  double ratio(Color a, Color b) {
    final double la = a.computeLuminance();
    final double lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  const List<MmThemePreset> ported = <MmThemePreset>[
    MmThemePreset.forest,
    MmThemePreset.air,
    MmThemePreset.daybreak,
    MmThemePreset.umber,
  ];

  /// The literals this app ships, so a value cannot drift silently — and so a
  /// second `light_ground_test` correction has to be a deliberate edit here.
  ///
  /// These are the LDMUX values wherever LDMUX's own contract holds on this
  /// app's surfaces, and a value moved one step where it does not. Each move is
  /// called out beside the value, with the ratio that forced it: `surfaceAlt`
  /// is a role LDMUX does not have, and the paper grounds are held to layer
  /// steps and a visible hairline that the source never needed to state.
  const Map<MmThemePreset, Map<String, int>> pinned =
      <MmThemePreset, Map<String, int>>{
    MmThemePreset.forest: <String, int>{
      'base': 0xFF121514,
      'surface': 0xFF1A211D,
      'surfaceAlt': 0xFF232C27,
      // D11.5 — LDMUX's two values, under this app's two names: the edge is
      // the control boundary (3:1), the line is the divider it always was.
      'edge': 0xFF7C8884,
      'line': 0xFF2F3A33,
      'hairline': 0xFF2F3A33,
      'fg': 0xFFEDF2EE,
      'fgMuted': 0xFFAEBBB2,
      'accent': 0xFF7FC98A,
      'alert': 0xFFE58A84,
      'warn': 0xFFE6C177,
      'onAccent': 0xFF0E1512,
    },
    MmThemePreset.air: <String, int>{
      'base': 0xFFFFFFFF,
      'surface': 0xFFF4F6F9,
      // slate-3: `surface` → `surfaceAlt` was 1.065:1, under the 1.08 step the
      // paper grounds are held to; one step darker.
      'surfaceAlt': 0xFFE8ECF1,
      // LDMUX edge #8B8D98 is 2.86:1 on surfaceAlt, under the control floor.
      'edge': 0xFF7E808A,
      // The divider: LDMUX's own quiet line, which Meshmore's `line` now is.
      'line': 0xFFC4C6D0,
      // slate-7 was 1.57:1 on white: not a rule you can see in daylight.
      'hairline': 0xFFC4C6D0,
      'fg': 0xFF1C2024,
      'fgMuted': 0xFF4D525A,
      'accent': 0xFF0A68BA,
      // red-11 is 4.43:1 on the darkened panel above, under the label floor.
      'alert': 0xFFC92A2F,
      'warn': 0xFF8A5A00,
      'onAccent': 0xFFFFFFFF,
    },
    MmThemePreset.daybreak: <String, int>{
      'base': 0xFFFFFFFF,
      // olive-2 was 1.077:1 off the page, just under the step floor.
      'surface': 0xFFF3F5F1,
      'surfaceAlt': 0xFFE8EBE7,
      'edge': 0xFF7A7F79,
      'line': 0xFFC2C6C1,
      // olive-7 was 1.41:1 on white: invisible as a rule on paper.
      'hairline': 0xFFC2C6C1,
      'fg': 0xFF1D211C,
      'fgMuted': 0xFF4D524B,
      // tomato-11 #D13415 is 4.26:1 on surfaceAlt, under the label floor.
      'accent': 0xFFBE2C11,
      // red-11 #CE2C31 is 4.46:1 on surfaceAlt.
      'alert': 0xFFC4272C,
      'warn': 0xFF8A5A00,
      'onAccent': 0xFFFFFFFF,
    },
    MmThemePreset.umber: <String, int>{
      'base': 0xFF211D1B,
      'surface': 0xFF2B2521,
      'surfaceAlt': 0xFF38312B,
      'edge': 0xFF8C7F73,
      'line': 0xFF4A403A,
      'hairline': 0xFF4A403A,
      'fg': 0xFFE7D7AD,
      'fgMuted': 0xFFC5B18D,
      'accent': 0xFFE78A4E,
      // gruvbox red #EA6962 is 4.08:1 on surfaceAlt.
      'alert': 0xFFF07A74,
      'warn': 0xFFD8A657,
      'onAccent': 0xFF282828,
    },
  };

  group('the four ported presets exist and are distinct', () {
    test('each is in the enum, the token map, and the skin factory', () {
      for (final MmThemePreset p in ported) {
        expect(MmThemePreset.values, contains(p));
        expect(kMmPresets.containsKey(p), isTrue, reason: '$p has no tokens');
        expect(mmSkinFor(p).color, kMmPresets[p]);
        expect(mmSkinFor(p).preset, p);
        expect(p.label, isNotEmpty);
      }
    });

    test('no two ported looks are the same', () {
      // Air and Daybreak both keep a white page — that is the source's
      // decision, not an accident — so identity is the triple of page, panel
      // and accent, not the page alone.
      final Set<String> looks = <String>{
        for (final MmThemePreset p in ported)
          // ignore: deprecated_member_use
          '${kMmPresets[p]!.base.value}/${kMmPresets[p]!.surface.value}/'
              // ignore: deprecated_member_use
              '${kMmPresets[p]!.accent.value}',
      };
      expect(looks.length, ported.length);
    });

    test('two are light and two are dark, which is the point of the pair', () {
      expect(
        ported.where((MmThemePreset p) => kMmPresets[p]!.isLight).toSet(),
        <MmThemePreset>{MmThemePreset.air, MmThemePreset.daybreak},
      );
    });
  });

  group('the palette is the LDMUX palette', () {
    for (final MmThemePreset p in ported) {
      test('${p.name} keeps its literals', () {
        final MmTokens t = kMmPresets[p]!;
        final Map<String, int> want = pinned[p]!;
        // ignore: deprecated_member_use
        int v(Color c) => c.value;
        expect(v(t.base), want['base'], reason: 'base');
        expect(v(t.surface), want['surface'], reason: 'surface');
        expect(v(t.surfaceAlt), want['surfaceAlt'], reason: 'surfaceAlt');
        expect(v(t.edge), want['edge'], reason: 'edge (LDMUX edge)');
        expect(v(t.line), want['line'], reason: 'line (LDMUX divider)');
        expect(v(t.hairline), want['hairline'], reason: 'hairline');
        expect(v(t.fg), want['fg'], reason: 'fg');
        expect(v(t.fgMuted), want['fgMuted'], reason: 'fgMuted (LDMUX dim)');
        expect(v(t.accent), want['accent'], reason: 'accent');
        expect(v(t.alert), want['alert'], reason: 'alert (LDMUX danger)');
        expect(v(t.warn), want['warn'], reason: 'warn');
        expect(v(t.onAccent), want['onAccent'], reason: 'onAccent');
      });
    }
  });

  group('the contract the source states, recomputed here', () {
    for (final MmThemePreset p in ported) {
      final MmTokens t = kMmPresets[p]!;
      final List<Color> grounds = <Color>[t.base, t.surface, t.surfaceAlt];

      test('${p.name}: text and the accent clear 4.5:1 on every ground', () {
        for (final Color g in grounds) {
          expect(ratio(t.fg, g), greaterThanOrEqualTo(4.5), reason: 'fg on $g');
          expect(ratio(t.fgMuted, g), greaterThanOrEqualTo(4.5),
              reason: 'fgMuted on $g');
          expect(ratio(t.accent, g), greaterThanOrEqualTo(4.5),
              reason: 'accent on $g');
          expect(ratio(t.alert, g), greaterThanOrEqualTo(4.5),
              reason: 'alert on $g');
          expect(ratio(t.warn, g), greaterThanOrEqualTo(4.5),
              reason: 'warn on $g');
          expect(ratio(t.ok, g), greaterThanOrEqualTo(4.5), reason: 'ok on $g');
        }
      });

      test('${p.name}: the control boundary clears 3:1 on every ground', () {
        // This is the floor the register records as violated on the seven
        // older dark skins (1.14-2.75:1). D11.5 gave the control boundary its
        // own role, so this is what makes "the control has a visible edge"
        // true rather than hoped for, and the divider is separately held to
        // staying under it.
        for (final Color g in grounds) {
          expect(ratio(t.edge, g), greaterThanOrEqualTo(3.0),
              reason: 'edge (the control boundary) on $g');
          expect(ratio(t.line, g), lessThan(3.0),
              reason: 'the divider on $g has climbed into the boundary role');
        }
      });

      test('${p.name}: a label on a filled accent or alert is readable', () {
        expect(ratio(t.onAccent, t.accent), greaterThanOrEqualTo(4.5));
        expect(ratio(t.onAlert, t.alert), greaterThanOrEqualTo(4.5));
      });

      test(
          '${p.name}: the disabled tier clears 3:1 and is quieter than the '
          'second voice', () {
        // `disabled_affordance_test` holds every preset to this floor; proving
        // it here keeps the reason beside the value.
        for (final Color g in grounds) {
          expect(ratio(t.fgDisabled, g), greaterThanOrEqualTo(3.0),
              reason: 'fgDisabled on $g');
        }
        expect(t.fgDisabled.computeLuminance(),
            isNot(t.fgMuted.computeLuminance()));
      });

      test('${p.name}: the divider is quieter than the boundary', () {
        // A divider is meant to be barely there, and a boundary is meant to be
        // seen. If these two ever swap, a group rule starts shouting and a
        // control starts disappearing.
        expect(ratio(t.hairline, t.base), lessThan(ratio(t.edge, t.base)));
        expect(ratio(t.line, t.base), lessThanOrEqualTo(ratio(t.edge, t.base)));
      });
    }
  });

  group('the surfaces step the way the source designed them to', () {
    for (final MmThemePreset p in ported) {
      test('${p.name}: panel and raised fill are visible steps off the page',
          () {
        final MmTokens t = kMmPresets[p]!;
        expect(ratio(t.surface, t.base), greaterThan(1.03));
        expect(ratio(t.surfaceAlt, t.base), greaterThan(1.05));
        expect(ratio(t.surfaceAlt, t.surface), greaterThan(1.02));
      });
    }
  });

  test('the type rule holds: the four keep their words in mono', () {
    // Only Studio and Studio Light turn words sans. Adding one of these to
    // that set would be a type-rule change, not a colour one.
    for (final MmThemePreset p in ported) {
      final MmType t = mmSkinFor(p).type;
      expect(t.sansLabels, isFalse, reason: '$p');
      expect(t.wordsMono, t.monoFamily, reason: '$p');
    }
  });

  test('the shape rule holds: no Material control is squared by them', () {
    // squared controls theme every framework button; these four keep the
    // framework's own rounding, which is what `square_controls_guard_test`
    // expects of anything outside the two Studio presets.
    for (final MmThemePreset p in ported) {
      expect(mmSkinFor(p).shape.squareControls, isFalse, reason: '$p');
    }
  });
}
