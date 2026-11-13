// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/cue/asset_audio_pack.dart';
import 'package:meshmore_sns_app/cue/cue_service.dart';
import 'package:meshmore_sns_app/maps/vector_basemap.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

/// A theme is not a palette. It is a layout, a sound, a map and a set of tokens,
/// and a preset that is wired on three of those four is the bug this file exists
/// to catch.
///
/// Four of the eleven presets were added in one wave (2026-11-09) and only the
/// tokens came with them: no layout of their own, one borrowed sound pack, and
/// nothing anywhere that would have failed if a fifth were added the same way.
/// So this is the census, written as assertions, and the two allow-lists below
/// are the honest record of what is still borrowed.
///
/// The rule: adding a preset to [MmThemePreset] must break this test until every
/// axis is either wired or added to an allow-list with a reason.
void main() {
  const String dashboardDir = 'lib/screens/dashboards';

  /// Presets with a dashboard widget of their own.
  ///
  /// `seele` is not here: its layout is `DashboardScreen`, the original
  /// monolith, which is the default the host falls back to.
  const Set<MmThemePreset> withOwnLayout = <MmThemePreset>{
    MmThemePreset.nerv,
    MmThemePreset.agHud,
    MmThemePreset.hyperlocal,
    MmThemePreset.drPop,
    MmThemePreset.recon,
    MmThemePreset.studio,
    MmThemePreset.air,
    MmThemePreset.forest,
    MmThemePreset.umber,
  };

  /// Presets that still inherit the monolith. Each name here is a theme that has
  /// had its palette done and its layout not done yet.
  const Set<MmThemePreset> inheritingLayout = <MmThemePreset>{
    MmThemePreset.daybreak,
  };

  /// Presets whose sound is knowingly another preset's pack. Every entry is a
  /// debt: the theme changes colour and not the cue set, so two themes sound
  /// identical and the reader cannot tell them apart with the phone in a pocket.
  const Map<MmThemePreset, MmThemePreset> borrowingSound =
      <MmThemePreset, MmThemePreset>{
    MmThemePreset.forest: MmThemePreset.hyperlocal,
    MmThemePreset.air: MmThemePreset.hyperlocal,
    MmThemePreset.daybreak: MmThemePreset.hyperlocal,
    MmThemePreset.umber: MmThemePreset.hyperlocal,
    MmThemePreset.studio: MmThemePreset.hyperlocal,
  };

  test('every preset is accounted for on the layout axis', () {
    final Set<MmThemePreset> covered = <MmThemePreset>{
      ...withOwnLayout,
      ...inheritingLayout,
      // SEELE is the fallback itself, so it is never a missing case.
      MmThemePreset.seele,
    };
    expect(covered, MmThemePreset.values.toSet(),
        reason: 'a preset is neither in withOwnLayout nor in '
            'inheritingLayout, so nobody decided what it should look like');
  });

  test('every declared layout has a file named after it', () {
    final List<String> files = <String>[
      for (final FileSystemEntity f in Directory(dashboardDir).listSync())
        if (f is File && f.path.endsWith('.dart'))
          f.uri.pathSegments.last,
    ];
    for (final MmThemePreset p in withOwnLayout) {
      // agHud -> aghud_dashboard.dart, drPop -> drpop_dashboard.dart.
      final String slug =
          p.audioPackKey; // the same lowercase slug the packs use
      expect(
        files.any((String f) => f.toLowerCase() == '${slug}_dashboard.dart'),
        isTrue,
        reason: '$p claims a layout and $dashboardDir/${slug}_dashboard.dart '
            'does not exist',
      );
    }
  });

  test('every preset resolves to a sound pack that exists on disk', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      final String dir = 'assets/audio/${p.audioPackKey}';
      expect(Directory(dir).existsSync(), isTrue,
          reason: '$p resolves to $dir, which is not in the bundle');
      // Every cue the enum defines, because a pack missing one plays the system
      // fallback and the theme goes unthemed for that event only.
      for (final CueKind k in CueKind.values) {
        final String path = AssetAudioPack.assetPathFor(p, k);
        expect(File('assets/$path').existsSync(), isTrue,
            reason: '$p is missing $path');
      }
    }
  });

  test('the borrowing is exactly the declared borrowing', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      final MmThemePreset? owes = borrowingSound[p];
      if (owes == null) {
        // Own pack: it must be its own slug, so a preset cannot quietly point
        // at another theme's folder and pass the earlier on-disk check.
        expect(p.audioPackKey, p.name.toLowerCase(),
            reason: '${p.name} claims its own sound but resolves to '
                '"${p.audioPackKey}"');
      } else {
        expect(p.audioPackKey, owes.audioPackKey,
            reason: '$p is declared to borrow ${owes.name} and does not');
      }
    }
  });

  test('every preset has a palette with readable body text on its ground', () {
    // The one contrast relationship every skin must hold, and the map palette is
    // derived from these same tokens, so a preset that fails this is as broken on
    // the map as it is in a list.
    for (final MmThemePreset p in MmThemePreset.values) {
      final MmTokens t = kMmPresets[p]!;
      final double ratio = contrastRatio(t.fg, t.base);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: '${p.name}: body text on the ground is '
              '${ratio.toStringAsFixed(2)}:1');
    }
  });

  test('every preset derives a map palette whose labels clear their ground', () {
    // The vector basemap is drawn from VectorSkinPalette.of(tokens), and the
    // light skins derive a map from a document authored dark, so the label
    // relationships were never checked on a paper ground.
    for (final MmThemePreset p in MmThemePreset.values) {
      final VectorSkinPalette m = VectorSkinPalette.of(kMmPresets[p]!);
      for (final (String role, Color fg) in <(String, Color)>[
        ('street label', m.streetLabel),
        ('water label', m.waterLabel),
      ]) {
        final double ratio = contrastRatio(fg, m.ground);
        expect(ratio, greaterThanOrEqualTo(3.0),
            reason: '${p.name}: $role on the map ground is '
                '${ratio.toStringAsFixed(2)}:1');
      }
    }
  });
}

/// WCAG relative luminance contrast, 1.0 to 21.0.
double contrastRatio(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  final double hi = math.max(la, lb);
  final double lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}
