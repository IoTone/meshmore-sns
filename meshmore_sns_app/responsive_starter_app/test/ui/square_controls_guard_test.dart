// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/ui/mm_shape.dart';

/// R71 — Studio is square everywhere. Two halves: the theme (Material's
/// own buttons/FAB/menus/fields) and a source scan (screens that draw
/// their own corner). What is NOT enforceable: a radius below 6px
/// (progress bars, swatches), `BoxShape.circle` dots, and painter code.
///
/// R98 — "square" is `kSquareRadius` (1 px), not zero.
void main() {
  ThemeData themeFor(MmThemePreset p) {
    final MmSkin s = mmSkinFor(p);
    return buildMmTheme(s.color,
        fontFamily: s.type.displayFamily, shape: s.shape);
  }

  OutlinedBorder? shapeOf(ButtonStyle? s) => s?.shape?.resolve(<WidgetState>{});

  // R98: the corner a square skin draws.
  final BorderRadius squareRadius = BorderRadius.circular(kSquareRadius);

  test('Studio: every Material button family resolves square', () {
    final ThemeData t = themeFor(MmThemePreset.studio);
    for (final ButtonStyle? s in <ButtonStyle?>[
      t.filledButtonTheme.style,
      t.outlinedButtonTheme.style,
      t.textButtonTheme.style,
      t.elevatedButtonTheme.style,
    ]) {
      final OutlinedBorder? b = shapeOf(s);
      expect(b, isA<RoundedRectangleBorder>());
      expect((b! as RoundedRectangleBorder).borderRadius, squareRadius);
    }
    expect((t.floatingActionButtonTheme.shape! as RoundedRectangleBorder)
        .borderRadius, squareRadius);
    expect((t.popupMenuTheme.shape! as RoundedRectangleBorder).borderRadius,
        squareRadius);
    final OutlineInputBorder f =
        t.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
    expect(f.borderRadius, squareRadius);
    expect(f.borderSide.color, kMmPresets[MmThemePreset.studio]!.accent);
  });

  // R114 — the one family that is themed in EVERY preset is the text button,
  // because a bare one is a control that looks like a label. The others keep
  // their skin defaults.
  test('older presets: only the text button is themed, and it is bounded', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      if (p == MmThemePreset.studio) {
        continue;
      }
      final ThemeData t = themeFor(p);
      expect(t.filledButtonTheme.style, isNull, reason: '$p');
      expect(t.outlinedButtonTheme.style, isNull, reason: '$p');
      expect(t.elevatedButtonTheme.style, isNull, reason: '$p');
      expect(t.floatingActionButtonTheme.shape, isNull, reason: '$p');
      expect(t.popupMenuTheme.shape, isNull, reason: '$p');
      expect(t.inputDecorationTheme.border, isNull, reason: '$p');

      final ButtonStyle? text = t.textButtonTheme.style;
      expect(text, isNotNull, reason: '$p has no text-button affordance');
      expect(shapeOf(text), isA<RoundedRectangleBorder>(), reason: '$p');
      expect(text!.side!.resolve(<WidgetState>{}), isNotNull, reason: '$p');
      expect(text.backgroundColor!.resolve(<WidgetState>{}),
          kMmPresets[p]!.surfaceAlt,
          reason: '$p label sits on the raised tone');
      expect(text.minimumSize!.resolve(<WidgetState>{})!.height, 48,
          reason: '$p meets the app minimum');
    }
  });

  testWidgets('a FilledButton under Studio is square, under SEELE a stadium',
      (WidgetTester tester) async {
    Future<OutlinedBorder> shape(MmThemePreset p) async {
      await tester.pumpWidget(MaterialApp(
        theme: themeFor(p),
        home: Scaffold(
            body: FilledButton(onPressed: () {}, child: const Text('Go'))),
      ));
      await tester.pumpAndSettle(); // let the theme lerp finish
      final Material m = tester.widget<Material>(find.descendant(
          of: find.byType(FilledButton), matching: find.byType(Material)));
      return m.shape! as OutlinedBorder;
    }

    expect(await shape(MmThemePreset.studio), isA<RoundedRectangleBorder>());
    expect(await shape(MmThemePreset.seele), isA<StadiumBorder>());
  });

  test('no screen hardcodes a control/card radius of 6px+ or a pill', () {
    // Allowed: the theme builder, the helper itself, and the two
    // dashboards only the older presets can show (Studio has its own).
    const Set<String> allowed = <String>{
      'lib/theme/mm_tokens.dart',
      'lib/ui/mm_shape.dart',
      'lib/screens/dashboards/aghud_dashboard.dart',
      'lib/screens/dashboards/hyperlocal_dashboard.dart',
    };
    final RegExp radius = RegExp(r'BorderRadius\.circular\(\s*([0-9.]+)\s*\)');
    final List<String> bad = <String>[];
    for (final FileSystemEntity e
        in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String path = e.path.replaceAll('\\', '/');
      if (path.startsWith('lib/gen/') || allowed.contains(path)) continue;
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String l = lines[i];
        if (l.trimLeft().startsWith('//')) continue;
        for (final RegExpMatch m in radius.allMatches(l)) {
          if (double.parse(m.group(1)!) >= 6) bad.add('$path:${i + 1} $l');
        }
        // The one guarded pill (chat "jump to latest") branches on the skin.
        if (l.contains('StadiumBorder') &&
            !(i > 3 &&
                lines
                    .sublist(i - 4, i)
                    .any((String x) => x.contains('squareControls')))) {
          bad.add('$path:${i + 1} $l');
        }
      }
    }
    expect(bad, isEmpty,
        reason: 'use mmRadius(context, r) so Studio stays square');
  });
}
