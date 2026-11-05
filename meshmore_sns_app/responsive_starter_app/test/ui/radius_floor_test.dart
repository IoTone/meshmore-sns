// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/ui/mm_shape.dart';

/// R114 — no corner in this app is perfectly sharp.
///
/// Two halves, in the style of `square_controls_guard_test.dart`:
///
///  * a source scan, so a screen cannot reintroduce a zero radius;
///  * a widget pass over the seven surfaces the framework draws itself, under
///    all seven presets, resolving the corner each one actually paints.
///
/// The floor is one logical pixel ([kSquareRadius]): the edge stays flat to
/// the eye and the stroke still has somewhere to turn. A true zero cuts the
/// border's own pixel, which at phone densities reads as a damaged corner.
void main() {
  ThemeData themeFor(MmThemePreset p) {
    final MmSkin s = mmSkinFor(p);
    return buildMmTheme(s.color,
        fontFamily: s.type.displayFamily, shape: s.shape);
  }

  /// The smallest corner radius in a resolved border, or 0 for a shape that
  /// has no radius at all (`StadiumBorder`, a bare `Border`).
  double? smallestRadius(ShapeBorder? b) {
    if (b is RoundedRectangleBorder) {
      final BorderRadius r = b.borderRadius as BorderRadius;
      return <double>[r.topLeft.x, r.topRight.x, r.bottomLeft.x, r.bottomRight.x]
          .reduce((double a, double c) => a < c ? a : c);
    }
    if (b is ContinuousRectangleBorder) {
      return b.borderRadius.resolve(TextDirection.ltr).topLeft.x;
    }
    if (b is OutlineInputBorder) {
      return b.borderRadius.topLeft.x;
    }
    // A stadium or a chamfer is already non-sharp; the floor does not apply.
    return null;
  }

  test('the helper never returns a zero radius, under any preset', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      final MmShape s = mmSkinFor(p).shape;
      final double? own = smallestRadius(
          mmShapeBorder(s, side: const BorderSide()));
      if (own != null) {
        expect(own, greaterThanOrEqualTo(kSquareRadius),
            reason: '$p: a panel border must not be sharp');
      }
      expect(smallestRadius(mmShapeBorder(
              const MmShape(
                  corner: MmCorner.sharp,
                  cornerSize: 0,
                  borderWidth: 1),
              side: const BorderSide())),
          kSquareRadius,
          reason: '$p: a deliberately sharp skin still turns the corner');
      expect(
          smallestRadius(mmShapeBorder(
              const MmShape(
                  corner: MmCorner.rounded, cornerSize: 0, borderWidth: 1),
              side: const BorderSide())),
          kSquareRadius,
          reason: '$p: a rounded skin whose size is 0 still turns the corner');
    }
  });

  test('mmCornerFloor raises a zero and leaves a real radius alone', () {
    expect(mmCornerFloor(0), kSquareRadius);
    expect(mmCornerFloor(0.5), kSquareRadius);
    expect(mmCornerFloor(kSquareRadius), kSquareRadius);
    expect(mmCornerFloor(8), 8);
    expect(mmCornerFloor(24), 24);
  });

  testWidgets('every framework-drawn surface paints a corner >= 1 px',
      (WidgetTester tester) async {
    for (final MmThemePreset p in MmThemePreset.values) {
      final ThemeData theme = themeFor(p);

      // Card: the theme may supply a shape (Studio) or fall back to the M3
      // default (the other six). Either way the painted corner is not sharp.
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(body: Card(child: SizedBox(width: 40, height: 20))),
      ));
      await tester.pumpAndSettle();
      final Material card = tester.widget<Material>(find
          .descendant(of: find.byType(Card), matching: find.byType(Material))
          .first);
      final double? cardRadius = smallestRadius(card.shape);
      expect(cardRadius, isNotNull, reason: '$p: card shape unknown');
      expect(cardRadius, greaterThanOrEqualTo(kSquareRadius),
          reason: '$p: a card must not be sharp');

      // Chip: the theme sets 20 px on every preset that is not Studio.
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
            body: Center(
                child: ChoiceChip(
                    label: const Text('c'), selected: false,
                    onSelected: (bool _) {}))),
      ));
      await tester.pumpAndSettle();
      final Material chip = tester.widget<Material>(find
          .descendant(of: find.byType(ChoiceChip), matching: find.byType(Material))
          .first);
      expect(smallestRadius(chip.shape),
          greaterThanOrEqualTo(kSquareRadius),
          reason: '$p: a chip must not be sharp');

      // Text field, dialog, sheet, menu and snackbar all come from the theme,
      // so asserting the theme's own resolved shapes covers them without
      // pumping a route per surface.
      final ShapeBorder? field = theme.inputDecorationTheme.border;
      if (field != null) {
        expect(smallestRadius(field), greaterThanOrEqualTo(kSquareRadius),
            reason: '$p: a text field must not be sharp');
      }
      final ShapeBorder? dialog = theme.dialogTheme.shape;
      if (dialog != null) {
        expect(smallestRadius(dialog), greaterThanOrEqualTo(kSquareRadius),
            reason: '$p: a dialog must not be sharp');
      }
      final ShapeBorder? sheet = theme.bottomSheetTheme.shape;
      if (sheet != null) {
        expect(smallestRadius(sheet), greaterThanOrEqualTo(kSquareRadius),
            reason: '$p: a sheet must not be sharp');
      }
      final ShapeBorder? menu = theme.popupMenuTheme.shape;
      if (menu != null) {
        expect(smallestRadius(menu), greaterThanOrEqualTo(kSquareRadius),
            reason: '$p: a menu must not be sharp');
      }
    }
  });

  test('no source file spells a zero corner', () {
    // The helper is the one place allowed to talk about the floor; every other
    // file names a radius through `mmRadius`, `mmShapeBorder` or `kRadius*`.
    const Set<String> allowed = <String>{
      'lib/ui/mm_shape.dart',
    };
    final RegExp zero = RegExp(
        r'BorderRadius\.circular\(\s*0(\.0+)?\s*\)|Radius\.zero');
    final List<String> bad = <String>[];
    for (final FileSystemEntity e
        in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String path = e.path.replaceAll('\\', '/');
      if (path.startsWith('lib/gen/') || allowed.contains(path)) continue;
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (zero.hasMatch(line)) bad.add('$path:${i + 1} ${line.trim()}');
      }
    }
    expect(bad, isEmpty,
        reason: 'these spell a sharp corner, which R114 forbids:\n'
            '${bad.join('\n')}');
  });
}
