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
///   grid     → line
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

  factory VizPalette.of(MmSkin skin) => VizPalette(
        hot: skin.color.alert,
        cool: skin.color.fg,
        node: skin.color.fgMuted,
        self: skin.color.accent,
        inferred: skin.color.accent,
        accent: skin.color.accent,
        grid: skin.color.line,
      );
}
