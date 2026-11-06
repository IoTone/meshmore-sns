// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/theme/viz_palette.dart';
import 'package:meshmore_sns_app/ui/mm_components.dart';
import 'package:meshmore_sns_app/ui/mm_scaffold.dart';
import 'package:meshmore_sns_app/ui/mm_shape.dart';

/// R115 — Studio Light is the app's only light ground, and a light theme is
/// not a dark theme with pale paint: every contrast pair is recomputed, the
/// Material brightness has to follow the ground, and the surfaces the dark
/// presets assume (a white outline on a marker, a near-black grid rule) have
/// to invert. These are the numbers that decide whether it is usable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final MmTokens t = kMmPresets[MmThemePreset.studioLight]!;
  final MmSkin skin = mmSkinFor(MmThemePreset.studioLight);

  double ratio(Color a, Color b) {
    final double la = a.computeLuminance();
    final double lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  group('the light ground is declared, not implied', () {
    test('exactly one preset is light, and it is this one', () {
      final List<MmThemePreset> light = MmThemePreset.values
          .where((MmThemePreset p) => kMmPresets[p]!.isLight)
          .toList();
      expect(light, <MmThemePreset>[MmThemePreset.studioLight]);
      expect(t.isLight, isTrue);
    });

    test('Material brightness follows the ground', () {
      final ThemeData td = buildMmTheme(t,
          fontFamily: skin.type.displayFamily, shape: skin.shape);
      expect(td.brightness, Brightness.light);
      expect(td.colorScheme.brightness, Brightness.light);
      expect(td.scaffoldBackgroundColor, t.base);
      expect(td.colorScheme.onSurface, t.fg);
      // Every dark preset still asks for a dark scheme.
      for (final MmThemePreset p in MmThemePreset.values) {
        if (p == MmThemePreset.studioLight) continue;
        expect(buildMmTheme(kMmPresets[p]!).brightness, Brightness.dark,
            reason: p.name);
      }
    });

    test('the stack runs from the page down, and each step is visible', () {
      expect(t.hasLayerStack, isTrue);
      final List<Color> layers = t.layers;
      expect(layers, hasLength(4));
      for (int i = 1; i < layers.length; i++) {
        expect(layers[i].computeLuminance(),
            lessThan(layers[i - 1].computeLuminance()),
            reason: 'a light container is cut into the page, step $i');
        expect(ratio(layers[i], layers[i - 1]), greaterThanOrEqualTo(1.08),
            reason: 'step $i must be visible');
      }
    });
  });

  group('every pair the UI draws meets WCAG AA', () {
    test('text on every layer', () {
      for (final Color layer in t.layers) {
        expect(ratio(t.fg, layer), greaterThanOrEqualTo(7),
            reason: 'ink on $layer');
        expect(ratio(t.fgMuted, layer), greaterThanOrEqualTo(4.5),
            reason: 'muted ink on $layer');
      }
    });

    test('accent, alert and ok read as text on every layer', () {
      for (final Color layer in t.layers) {
        for (final Color c in <Color>[t.accent, t.alert, t.ok]) {
          expect(ratio(c, layer), greaterThanOrEqualTo(4.5),
              reason: '$c on $layer');
        }
      }
    });

    test('a filled control carries its own label', () {
      expect(ratio(t.onAccent, t.accent), greaterThanOrEqualTo(4.5));
      expect(ratio(t.onAlert, t.alert), greaterThanOrEqualTo(4.5));
    });

    test('the live-link green is rebuilt for paper, and stays green', () {
      // The shared #3DDC84 is 1.7:1 here; a link state has to be readable in
      // the theme it is read in.
      expect(t.link, isNot(kMmPresets[MmThemePreset.seele]!.link));
      expect(ratio(t.link, t.base), greaterThanOrEqualTo(4.5));
      final HSVColor hsv = HSVColor.fromColor(t.link);
      expect(hsv.hue, inInclusiveRange(90, 165));
      expect(hsv.saturation, greaterThan(0.30));
    });

    test('rules are visible on paper, and stay subordinate', () {
      // On a light ground a rule is the only thing separating two blocks.
      for (final Color layer in t.layers) {
        expect(ratio(t.line, layer), greaterThanOrEqualTo(2.4),
            reason: 'line on $layer');
        expect(ratio(t.hairline, layer), greaterThanOrEqualTo(1.6),
            reason: 'hairline on $layer');
      }
      expect(ratio(t.hairline, t.base), lessThan(2.6),
          reason: 'a hairline is not a border');
    });

    test('disabled ink is still legible on the deepest layer it is drawn on',
        () {
      // Disabled text is exempt from AA, but a control that is off must still
      // be readable as a control: on paper the old #8E9196 was 2.1:1 on
      // `selected` and read as a smudge.
      for (final Color layer in t.layers) {
        expect(ratio(t.fgDisabled, layer), greaterThanOrEqualTo(3.0),
            reason: 'disabled ink on $layer');
      }
      // …and it stays visibly below the muted tier, so "off" still reads as
      // off rather than as secondary text.
      expect(ratio(t.fgMuted, t.base),
          greaterThan(ratio(t.fgDisabled, t.base)));
    });

    test('caution is a role of its own, and readable on paper', () {
      // The gauge carried an amber literal that was tuned on a dark ground.
      expect(t.warn, isNot(t.accent));
      expect(t.warn, isNot(t.alert));
      for (final Color layer in t.layers) {
        expect(ratio(t.warn, layer), greaterThanOrEqualTo(3.0),
            reason: 'a caution stroke on $layer');
      }
      // The dark presets keep the amber they were drawn with.
      expect(kMmPresets[MmThemePreset.studio]!.warn,
          const Color(0xFFFFB020));
    });

    test('the secondary text tier clears AA on every layer', () {
      // Twenty subtitles across settings and device screens were drawn as
      // `onSurface` at 60 %, which is 3.9:1 on paper — under AA, on screens
      // that are mostly subtitles. The scheme's own secondary role is the
      // right tier and it has to stay legible on every layer.
      final ColorScheme cs = buildMmTheme(t,
              fontFamily: skin.type.displayFamily, shape: skin.shape)
          .colorScheme;
      for (final Color layer in <Color>[
        t.base,
        t.surface,
        t.surfaceAlt,
        t.selected,
        cs.surfaceContainerHigh,
      ]) {
        expect(ratio(cs.onSurfaceVariant, layer), greaterThanOrEqualTo(4.5),
            reason: 'secondary text on $layer');
      }
    });

    test('alert and accent are not the same colour', () {
      expect(t.accent, isNot(t.alert));
      expect(ratio(t.alert, t.accent), greaterThan(1.2),
          reason: 'a warning must not look like a selection');
    });
  });

  group('the map and the grid keep their meaning on paper', () {
    test('the marker outline inverts with the ground', () {
      // R115 — the peer and self glyphs used to outline in white, which is
      // invisible on a light basemap. The ring is now the skin's foreground,
      // which is dark here and light on the seven dark skins.
      expect(ratio(t.fg, t.base), greaterThanOrEqualTo(7));
      expect(t.fg, isNot(const Color(0xFFFFFFFF)));
    });

    test('grid lines and glyphs are dark on a light ground', () {
      final VizPalette viz = VizPalette.of(skin);
      expect(viz.grid, t.line);
      expect(viz.cool, t.fg);
      expect(ratio(viz.grid, t.base), greaterThanOrEqualTo(2.4));
      expect(ratio(viz.cool, t.base), greaterThanOrEqualTo(7));
      // A light basemap's two dominant tones (land, water) both carry the
      // chrome that sits over them.
      expect(ratio(t.fg, const Color(0xFFF2EFE6)), greaterThanOrEqualTo(7));
      expect(ratio(t.fg, const Color(0xFFAAD3DF)), greaterThanOrEqualTo(4.5));
    });
  });

  group('the tool shape rules hold on the light ground', () {
    ThemeData theme() =>
        buildMmTheme(t, fontFamily: skin.type.displayFamily, shape: skin.shape);

    test('controls are the 1 px square family, not Material pills', () {
      final ThemeData td = theme();
      final BorderRadius r = BorderRadius.circular(kSquareRadius);
      expect((td.chipTheme.shape! as RoundedRectangleBorder).borderRadius, r);
      expect((td.cardTheme.shape! as RoundedRectangleBorder).borderRadius, r);
      expect((td.dialogTheme.shape! as RoundedRectangleBorder).borderRadius, r);
      expect(
          (td.bottomSheetTheme.shape! as RoundedRectangleBorder).borderRadius,
          r);
      final OutlineInputBorder f =
          td.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
      expect(f.borderRadius, r);
      expect(f.borderSide.color, t.accent);
      expect(td.filledButtonTheme.style, isNotNull);
    });

    test('the word/machine type rule matches the dark tool skin', () {
      final MmType type = skin.type;
      expect(type.wordsMono, isNull, reason: 'words use the UI face');
      expect(type.monoFamily, 'JetBrains Mono', reason: 'data stays mono');
      expect(type.sansLabels, isTrue);
    });
  });

  testWidgets('the chrome holds 320 dp at 200 % text on the light ground',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ThemeController tc = ThemeController();
    await tc.setPreset(MmThemePreset.studioLight);
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<ThemeController>.value(
      value: tc,
      child: MaterialApp(
        theme: tc.theme,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: MmScaffold(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  MmPanel(
                    child: Text('Noise floor and the radio\'s own measurements '
                        'sit here, sourced line by line.'),
                  ),
                  FilledButton(onPressed: null, child: Text('Connect a radio')),
                  OutlinedButton(onPressed: null, child: Text('Revert')),
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: TextField(
                      decoration: InputDecoration(labelText: 'Frequency (MHz)'),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Wrap(spacing: 8, children: <Widget>[
                      ChoiceChip(label: Text('Hazard'), selected: true),
                      ChoiceChip(label: Text('Water'), selected: false),
                    ]),
                  ),
                  Card(
                      child: ListTile(
                          title: Text('Radio'), subtitle: Text('MeshCore'))),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'the light chrome overflowed at the accessibility floor');
  });
}
