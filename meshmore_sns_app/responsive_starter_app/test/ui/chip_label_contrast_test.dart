// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/mm_components.dart';

/// A chip's fill and its label are one decision, and it has to be legible.
///
/// Measured on the phone: the places sheet's ticked chips were pale boxes with
/// a checkmark floating in them. `ChipThemeData.selectedColor` fills the chip
/// with the accent, and Flutter merges a **single** `labelStyle` into every
/// state of a chip, so the label kept `onSurfaceVariant` while the fill went
/// pale — a light label on a light ground. Every chip in the app is therefore
/// built through `MmFilterChip`/`MmChoiceChip`, which state both halves, and the
/// contrast between them is asserted here rather than described.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // WCAG 2.1 relative luminance and contrast ratio: the same arithmetic the
  // theme's own contrast audit uses.
  double linearOf(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * linearOf(c.r) + 0.7152 * linearOf(c.g) + 0.0722 * linearOf(c.b);

  double contrast(Color a, Color b) {
    final double la = luminance(a);
    final double lb = luminance(b);
    final double hi = la > lb ? la : lb;
    final double lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// The colour a chip's label is actually painted in. The label widget carries
  /// no style of its own: the chip resolves one and wraps the label in a
  /// `DefaultTextStyle`, so reading `Text.style` reads nothing.
  Color paintedColour(WidgetTester t, Finder f) {
    final RenderParagraph p = t.renderObject<RenderParagraph>(f);
    return p.text.style!.color!;
  }

  Future<ColorScheme> schemeFor(
      WidgetTester t, MmThemePreset preset, Widget child) async {
    final ThemeController tc = ThemeController();
    await tc.setPreset(preset);
    addTearDown(tc.dispose);
    await t.pumpWidget(ChangeNotifierProvider<ThemeController>.value(
      value: tc,
      child: MaterialApp(
        theme: tc.theme,
        home: Scaffold(body: child),
      ),
    ));
    await t.pumpAndSettle();
    return tc.theme.colorScheme;
  }

  for (final MmThemePreset preset in MmThemePreset.values) {
    testWidgets('${preset.name}: a selected chip is readable on its fill',
        (WidgetTester t) async {
      final ColorScheme cs = await schemeFor(
        t,
        preset,
        MmFilterChip(
          label: const Text('live'),
          selected: true,
          onSelected: (_) {},
        ),
      );
      final Color ink = paintedColour(t, find.text('live'));
      expect(ink, cs.onPrimary,
          reason: 'the selected label takes the ink the accent was defined '
              'against, not the ordinary foreground');
      final double ratio = contrast(ink, cs.primary);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: '${preset.name}: ${ratio.toStringAsFixed(1)}:1 on the '
              'accent fill is not a readable chip');
    });

    testWidgets('${preset.name}: an unselected chip keeps body contrast',
        (WidgetTester t) async {
      final ColorScheme cs = await schemeFor(
        t,
        preset,
        MmChoiceChip(
          label: const Text('Public'),
          selected: false,
          onSelected: (_) {},
        ),
      );
      final Color ink = paintedColour(t, find.text('Public'));
      expect(ink, cs.onSurface);
      expect(contrast(ink, cs.surface), greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('a disabled chip names its state in the muted tier',
      (WidgetTester t) async {
    final ColorScheme cs = await schemeFor(
      t,
      MmThemePreset.studio,
      const MmChoiceChip(
        label: Text('locked'),
        selected: false,
        onSelected: null,
      ),
    );
    expect(paintedColour(t, find.text('locked')), cs.onSurfaceVariant);
  });

  test('the theme fills a selected chip with the accent and ticks it in ink',
      () {
    for (final MmThemePreset p in MmThemePreset.values) {
      final ThemeData theme = buildMmTheme(mmSkinFor(p).color);
      final MmTokens t = mmSkinFor(p).color;
      expect(theme.chipTheme.selectedColor, t.accent, reason: p.name);
      expect(theme.chipTheme.checkmarkColor, t.onAccent, reason: p.name);
    }
  });

  // The source ratchet: a bare chip is a chip that can split its own pair.
  // This is the same shape as the type-rule and square-corner guards: the
  // rule is only real while nothing routes around it.
  test('no surface builds a bare FilterChip or ChoiceChip', () {
    final List<String> offenders = <String>[];
    for (final FileSystemEntity e
        in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.endsWith('lib/ui/mm_components.dart')) continue;
      final String src = e.readAsStringSync();
      // `MmFilterChip(`/`MmChoiceChip(` are the wrappers and contain the bare
      // names as substrings, so the match is anchored on the call.
      for (final RegExp re
          in <RegExp>[RegExp(r'(?<!Mm)FilterChip\('), RegExp(r'(?<!Mm)ChoiceChip\(')]) {
        final RegExpMatch? m = re.firstMatch(src);
        if (m != null) {
          final int line = src.substring(0, m.start).split('\n').length;
          offenders.add('${e.path}:$line ${m.group(0)}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'build chips through MmFilterChip/MmChoiceChip: '
            '${offenders.join(', ')}');
  });

  // An unread count is drawn twice: as a chip avatar in the chat strip and as a
  // badge on the tab strip. Both used the accent pair, and on a *selected* chip
  // the accent is already the chip's own fill, so the count vanished into the
  // thing it was counting for. The attention pair fixes both, and the pair has
  // to hold on every skin.
  test('an unread count reads against its own fill on every skin', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      final MmTokens t = mmSkinFor(p).color;
      expect(contrast(t.onAlert, t.alert), greaterThanOrEqualTo(4.5),
          reason: '${p.name}: the count must be legible on its own badge');
      // And it must not be the accent, or it disappears on a selected chip.
      expect(t.alert, isNot(t.accent), reason: p.name);
    }
  });
}
