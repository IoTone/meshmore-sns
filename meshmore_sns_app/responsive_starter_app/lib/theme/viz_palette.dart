// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/painting.dart';

import 'mm_skin.dart';

/// W2 — data encodings, not chrome.
///
/// A temperature ramp or a heat cue says what a value *is*, so it does not
/// follow the chrome: a skin switch would change what the picture claims. They
/// live here, once, instead of in each painter, so a screen carries no colour
/// literal and a source scan can see all of them (see
/// `test/theme/mm_ratchet_test.dart`).

/// Cold → mild → hot, for the weather ramp.
const Color kThermalCold = Color(0xFF2E7DEF);
const Color kThermalMild = Color(0xFFE0A02E);
const Color kThermalHot = Color(0xFFE0402E);

/// A message cell heating up, and the chromatic split that marks it.
const Color kCellHeatHot = Color(0xFFFF0040);
const Color kCellHeatCool = Color(0xFF00FFE0);

/// An inferred place, which is not a node and is drawn in neither face colour.
const Color kInferredPlaceMarker = Color(0xFF8A6CFF);

/// The shadow under a map label, so a light or dark basemap cannot swallow it.
const Color kMarkerShadow = Color(0xCC000000);

/// The two inks a heat cell's count can be drawn in.
///
/// A cell's fill is computed from the heat ramp, so the count on it cannot take
/// a skin colour: it has to be the one of these two that contrasts with the
/// fill it lands on. Declared here rather than at the painter, because a
/// literal in a painter is a colour nobody can find again.
const Color kOnHotCell = Color(0xFFFFFFFF);
const Color kOnCoolCell = Color(0xFF000000);

/// R55 — semantic colours for the **visualisation painters** (radar,
/// heat map, maps, charts), derived from the active [MmSkin] so the
/// grid/map views follow the theme instead of baking in literal hex.
///
/// The painters take these roles instead of `const Color(0x…)`, so a
/// theme switch reskins them along with the rest of the UI. Map the
/// viz-semantic roles onto the nine skin colour tokens:
///   hot      → alert (heat peak)
///   cool     → fg    (heat floor — tints with the theme ground)
///   node     → fgMuted
///   self     → accent
///   inferred → accent (distinguished from self/nodes by *shape*)
///   grid     → edge (D11.5: a grid line is a structure you have to see, and it
///              is held to the control-boundary floor on paper; `line` is now
///              the barely-there divider tier)
class VizPalette {
  const VizPalette({
    required this.hot,
    required this.cool,
    required this.node,
    required this.self,
    required this.inferred,
    required this.accent,
    required this.grid,
  });

  final Color hot;
  final Color cool;
  final Color node;
  final Color self;
  final Color inferred;
  final Color accent;
  final Color grid;

  /// The north marker on a dial.
  ///
  /// A fixed red rather than the skin's alert: north is a physical direction,
  /// not a state of the app, and every skin must say it the same way or a
  /// reader who switches theme has to relearn the one marker that never
  /// changes meaning. Deliberately saturated — measured against the dark
  /// dials, the skins' alert reds are muted enough that a 9 px triangle read
  /// as another node.
  static const Color north = Color(0xFFFF2D2D);

  /// A repeater, and a chat node, on the map.
  ///
  /// A node's *type* is data, like a temperature, so it does not follow the
  /// chrome: on this skin set the theme's primary and tertiary are both pale
  /// greys, and a reader could not tell a repeater from a companion except by
  /// squinting at a 13 px shape. Two mid-luminance hues read on the dimmed
  /// vector basemap and on the pale raster one alike, and each glyph keeps the
  /// skin's foreground as its ring so a light ground cannot swallow it.
  static const Color repeater = Color(0xFFF0A030);
  static const Color companion = Color(0xFF40B0FF);

  /// The radar's sweep, in the colour opposite the skin's own.
  ///
  /// The sweep is not data — it is the hand of a clock — so it does not have to
  /// belong to the palette it is drawn on, and it must not be mistaken for one of
  /// the marks. Turning the accent's hue half a circle gives exactly that: the
  /// forest skins get a burnt red against their greens, the NERV skin gets a cyan
  /// against its orange, and the line reads as *the instrument* rather than as
  /// another node.
  ///
  /// Hue only: saturation and lightness are kept, because those are what make it
  /// legible on this skin's dial. A grey accent has no hue to turn, so it falls
  /// back to the skin's warning colour, which is always a hue.
  static Color sweepFor(MmSkin skin) {
    final Color c = skin.color.accent;
    final HSLColor hsl = HSLColor.fromColor(c);
    if (hsl.saturation < 0.12) return skin.color.warn;
    return hsl
        .withHue((hsl.hue + 180) % 360)
        .withSaturation(hsl.saturation.clamp(0.35, 1.0))
        .withLightness(hsl.lightness.clamp(0.45, 0.72))
        .toColor();
  }

  factory VizPalette.of(MmSkin skin) => VizPalette(
        hot: skin.color.alert,
        cool: skin.color.fg,
        node: skin.color.fgMuted,
        self: skin.color.accent,
        inferred: skin.color.accent,
        accent: skin.color.accent,
        grid: skin.color.edge,
      );
}
