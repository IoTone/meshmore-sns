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

/// The paper ground is a standing contract, not a fact about one skin.
///
/// R115 audited the app's first light ground and found the failures a light
/// theme exposes: a disabled tier that read as a smudge, a subtitle tier under
/// AA, an accent that was legible on the page but not on a panel, a divider
/// that vanished, and a Material scheme that stayed dark under pale paint.
/// Those findings were written down as a test against that one preset.
///
/// The preset is gone (it was the third paper ground and the closest palette
/// in the app to Daybreak's). The findings are not: this file holds every
/// light preset to them, by iterating the tokens rather than naming a skin, so
/// a light theme added later inherits the audit instead of repeating the bugs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Every preset whose own ground is light, derived from the tokens.
  final List<MmThemePreset> light = <MmThemePreset>[
    for (final MmThemePreset p in MmThemePreset.values)
      if (kMmPresets[p]!.isLight) p,
  ];

  double ratio(Color a, Color b) {
    final double la = a.computeLuminance();
    final double lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// The layers a role is actually drawn on: the page, a panel, a raised
  /// control. `selected` is a container fill that carries `fg` text only, which
  /// the next two cases cover — a semantic colour written on it would be a
  /// different pair and a different floor.
  List<Color> surfaces(MmTokens t) => <Color>[t.base, t.surface, t.surfaceAlt];

  test('there is at least one light ground, and each declares itself light', () {
    expect(light, isNotEmpty,
        reason: 'a phone in daylight needs a paper ground');
    for (final MmThemePreset p in light) {
      expect(kMmPresets[p]!.isLight, isTrue, reason: p.name);
      expect(mmSkinFor(p).color.isLight, isTrue, reason: p.name);
    }
  });

  test('Material brightness follows the ground, on every preset', () {
    // Brightness decides dozens of framework defaults (elevation tints, ink,
    // splash alpha), so it is derived from the page rather than declared
    // beside it: a light preset that inherits a dark scheme is the washed-out
    // look a real light theme has to avoid.
    for (final MmThemePreset p in MmThemePreset.values) {
      final MmTokens t = kMmPresets[p]!;
      final ThemeData td = buildMmTheme(t,
          fontFamily: mmSkinFor(p).type.displayFamily,
          shape: mmSkinFor(p).shape);
      expect(td.brightness,
          t.isLight ? Brightness.light : Brightness.dark,
          reason: p.name);
      expect(td.colorScheme.brightness, td.brightness, reason: p.name);
      expect(td.scaffoldBackgroundColor, t.base, reason: p.name);
      expect(td.colorScheme.onSurface, t.fg, reason: p.name);
    }
  });

  test('the stack runs from the page down, and every step is visible', () {
    for (final MmThemePreset p in light) {
      final MmTokens t = kMmPresets[p]!;
      expect(t.hasLayerStack, isTrue,
          reason: '${p.name} declares a paper stack');
      final List<Color> layers = t.layers;
      expect(layers, hasLength(4), reason: p.name);
      for (int i = 1; i < layers.length; i++) {
        expect(layers[i].computeLuminance(),
            lessThan(layers[i - 1].computeLuminance()),
            reason: '${p.name}: a light container is cut into the page, '
                'step $i');
        expect(ratio(layers[i], layers[i - 1]), greaterThanOrEqualTo(1.08),
            reason: '${p.name}: step $i must be visible');
      }
      // A raised control is the panel step, not a fourth tone of its own.
      expect(t.raised, t.surfaceAlt, reason: p.name);
    }
  });

  test('text on every layer of the stack', () {
    for (final MmThemePreset p in light) {
      final MmTokens t = kMmPresets[p]!;
      for (final Color layer in t.layers) {
        expect(ratio(t.fg, layer), greaterThanOrEqualTo(7),
            reason: '${p.name}: ink on $layer');
        expect(ratio(t.fgMuted, layer), greaterThanOrEqualTo(4.5),
            reason: '${p.name}: muted ink on $layer');
      }
    }
  });

  test('accent, alert and ok read as text on the page and on a panel', () {
    for (final MmThemePreset p in light) {
      final MmTokens t = kMmPresets[p]!;
      for (final Color layer in surfaces(t)) {
        for (final Color c in <Color>[t.accent, t.alert, t.ok]) {
          expect(ratio(c, layer), greaterThanOrEqualTo(4.5),
              reason: '${p.name}: $c on $layer');
        }
      }
    }
  });

  test('a filled control carries its own label', () {
    for (final MmThemePreset p in light) {
      final MmTokens t = kMmPresets[p]!;
      expect(ratio(t.onAccent, t.accent), greaterThanOrEqualTo(4.5),
          reason: p.name);
      expect(ratio(t.onAlert, t.alert), greaterThanOrEqualTo(4.5),
          reason: p.name);
    }
  });

  test('the live-link green is rebuilt for paper, and stays green', () {
    // The shared #3DDC84 is 1.7:1 on paper, so a light ground has to state its
    // own: a link state has to be readable in the theme it is read in.
    final Color shared = kMmPresets[MmThemePreset.seele]!.link;
    for (final MmThemePreset p in light) {
      final MmTokens t = kMmPresets[p]!;
      expect(t.link, isNot(shared), reason: p.name);
      expect(ratio(t.link, t.base), greaterThanOrEqualTo(4.5), reason: p.name);
      final HSVColor hsv = HSVColor.fromColor(t.link);
      expect(hsv.hue, inInclusiveRange(90, 165), reason: p.name);
      expect(hsv.saturation, greaterThan(0.30), reason: p.name);
    }
  });

  test('rules are visible on paper, and stay subordinate', () {
    // On a light ground a rule is the only thing separating two blocks. This
    // is the pair that a ported palette gets wrong most often: a Radix step-7
    // grey is 1.4-1.6:1 on white, which is invisible on a phone in daylight.
    for (final MmThemePreset p in light) {
      final MmTokens t = kMmPresets[p]!;
      for (final Color layer in surfaces(t)) {
        expect(ratio(t.line, layer), greaterThanOrEqualTo(2.4),
            reason: '${p.name}: line on $layer');
      }
      final double hair = ratio(t.hairline, t.base);
      expect(hair, greaterThanOrEqualTo(1.6),
          reason: '${p.name}: a hairline has to be visible on the page');
      expect(hair, lessThan(2.6),
          reason: '${p.name}: a hairline is not a border');
      expect(ratio(t.hairline, t.selected), lessThan(ratio(t.line, t.selected)),
          reason: '${p.name}: the hairline stays weaker than the border tier');
    }
  });

  test('disabled ink is legible where a disabled control sits', () {
    // Disabled text is exempt from AA, but a control that is off must still be
    // readable as a control: R115's first paper ground drew it at 2.1:1 on a
    // container and it read as a smudge.
    for (final MmThemePreset p in light) {
      final MmTokens t = kMmPresets[p]!;
      for (final Color layer in surfaces(t)) {
        expect(ratio(t.fgDisabled, layer), greaterThanOrEqualTo(3.0),
            reason: '${p.name}: disabled ink on $layer');
      }
      expect(ratio(t.fgMuted, t.base),
          greaterThan(ratio(t.fgDisabled, t.base)),
          reason: '${p.name}: "off" still reads below secondary text');
    }
  });

  test('caution is a role of its own, and readable on paper', () {
    for (final MmThemePreset p in light) {
      final MmTokens t = kMmPresets[p]!;
      expect(t.warn, isNot(t.accent), reason: p.name);
      expect(t.warn, isNot(t.alert), reason: p.name);
      for (final Color layer in surfaces(t)) {
        expect(ratio(t.warn, layer), greaterThanOrEqualTo(3.0),
            reason: '${p.name}: a caution stroke on $layer');
      }
    }
    // The dark presets keep the amber they were drawn with.
    expect(kMmPresets[MmThemePreset.studio]!.warn, const Color(0xFFFFB020));
  });

  test('the secondary text tier clears AA on every layer', () {
    for (final MmThemePreset p in light) {
      final MmTokens t = kMmPresets[p]!;
      final MmSkin skin = mmSkinFor(p);
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
            reason: '${p.name}: secondary text on $layer');
      }
    }
  });

  test('alert and accent are never the same colour', () {
    for (final MmThemePreset p in light) {
      final MmTokens t = kMmPresets[p]!;
      expect(t.accent, isNot(t.alert), reason: p.name);
      expect(ratio(t.alert, t.accent), greaterThan(1.02),
          reason: '${p.name}: a warning must not look like a selection');
    }
  });

  test('the map and the grid keep their meaning on paper', () {
    for (final MmThemePreset p in light) {
      final MmTokens t = kMmPresets[p]!;
      final MmSkin skin = mmSkinFor(p);
      // The peer and self glyphs used to outline in white, which is invisible
      // on a light basemap; the ring is the skin's foreground now.
      expect(t.fg, isNot(const Color(0xFFFFFFFF)), reason: p.name);
      final VizPalette viz = VizPalette.of(skin);
      expect(viz.grid, t.line, reason: p.name);
      expect(viz.cool, t.fg, reason: p.name);
      expect(ratio(viz.grid, t.base), greaterThanOrEqualTo(2.4), reason: p.name);
      expect(ratio(viz.cool, t.base), greaterThanOrEqualTo(7), reason: p.name);
      // The two dominant tones of a light basemap (land, water) both carry the
      // chrome that sits over them.
      expect(ratio(t.fg, const Color(0xFFF2EFE6)), greaterThanOrEqualTo(7),
          reason: p.name);
      expect(ratio(t.fg, const Color(0xFFAAD3DF)), greaterThanOrEqualTo(4.5),
          reason: p.name);
    }
  });

  test('paper keeps no dimmed basemap', () {
    // Dimming exists to push a bright basemap under dark chrome; on paper the
    // basemap belongs to the page.
    for (final MmThemePreset p in light) {
      expect(mmSkinFor(p).shape.dimmedBasemap, isFalse, reason: p.name);
    }
  });

  testWidgets('the chrome holds 320 dp at 200 % text on every light ground',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    for (final MmThemePreset p in light) {
      final ThemeController tc = ThemeController();
      await tc.setPreset(p);
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
                      child: Text('Noise floor and the radio\'s own '
                          'measurements sit here, sourced line by line.'),
                    ),
                    FilledButton(
                        onPressed: null, child: Text('Connect a radio')),
                    OutlinedButton(onPressed: null, child: Text('Revert')),
                    Padding(
                      padding: EdgeInsets.all(12),
                      child: TextField(
                        decoration:
                            InputDecoration(labelText: 'Frequency (MHz)'),
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
          reason: '${p.name} overflowed at the accessibility floor');
    }
  });
}
