// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'mm_tokens.dart';
import 'theme_controller.dart';

/// R54-follow-on — the **skin system**. A skin is more than a palette:
/// it bundles colour ([MmTokens]) with **typography**, **shape**, and
/// **ornament** tokens, so a preset can re-imagine a screen's *feel*
/// (chamfered HUD panels + scanlines vs. cream-on-black brutalism), not
/// just its hues. Screens read the active [MmSkin] via `context.skin`
/// and compose the branded widgets in `lib/ui/`, so reskinning is a
/// matter of defining a bundle — not editing every screen.
///
/// Today colour is fully realised across the app (the ThemeData path);
/// this layer adds the missing dimensions the UX brief specifies
/// (per-concept components, type, and ornament) for screens migrated to
/// the component library.

enum MmCorner { sharp, rounded, chamfer }

/// Typography roles. Families are font names (or null = platform
/// default); the app bundles no custom face yet, so the "futuristic"
/// concepts lean on the platform monospace + tracked uppercase (the
/// established convention) rather than a TTF.
@immutable
class MmType {
  const MmType({
    this.displayFamily,
    this.headingFamily,
    this.monoFamily = 'monospace',
    this.bodyFamily,
    this.upperHeadings = false,
    this.headingTracking = 1.0,
    this.slashedZero = false,
    this.sansLabels = false,
    this.typeScale = 1.0,
  });

  final String? displayFamily;
  final String? headingFamily;
  final String monoFamily;
  final String? bodyFamily;

  /// Multiplier over every size below. 1.0 for all seven presets: a skin may
  /// move the whole scale at once, and the accessibility pass multiplies this
  /// rather than each call site. The steps are seeded from the sizes the app
  /// already sets (11 and 12 carry 61 % of the literals they replace), so
  /// moving a site onto a role does not move a pixel.
  final double typeScale;

  double get sizeMicro => 10 * typeScale;
  double get sizeSm => 11 * typeScale;
  double get sizeBody => 12 * typeScale;
  double get sizeBodyLg => 13 * typeScale;
  double get sizeLg => 16 * typeScale;
  double get sizeXl => 20 * typeScale;
  double get sizeTitle => 24 * typeScale;
  double get sizeHero => 34 * typeScale;

  /// A size with no role yet. It still rides [typeScale], so it moves with the
  /// skin and the accessibility pass like the roles do; the screen waves
  /// replace each one with a role as they revisit the file.
  double size(double step) => step * typeScale;

  /// Render section labels in UPPER CASE (terminal/HUD concepts).
  final bool upperHeadings;

  /// letterSpacing applied to section labels.
  final double headingTracking;

  /// Request the font's slashed-zero feature on telemetry numerals (the
  /// Evangelion "SOUND ONLY" motif). Applied by components via
  /// `FontFeature.slashedZero()` when the face supports it.
  final bool slashedZero;

  /// R68 — draw section labels in the platform UI face instead of the
  /// mono/heading face. Off for the six older presets (their labels are
  /// mono or Saira by design); Studio turns it on so **words are always
  /// sans and only machine data is mono** (the Studio type-role rule).
  final bool sansLabels;

  /// R74 -- the face for *words* that older skins deliberately set in
  /// mono (docs titles, HUD headings, readout labels, boot lines): null
  /// (the theme's UI face) when [sansLabels] is on, [monoFamily] otherwise.
  /// Use it for prose; keep `monoFamily` for machine data.
  String? get wordsMono => sansLabels ? null : monoFamily;
}

/// The spacing ladder, in logical px. Seeded from the paddings the app already
/// uses (12, 16 and 20 are the three most common), so a migrated padding does
/// not move.
@immutable
class MmSpace {
  const MmSpace({this.scale = 1.0});

  /// Multiplier over every step, for the same reason [MmType.typeScale]
  /// exists. 1.0 for all seven presets.
  final double scale;

  /// [step] 1..9 = 2, 4, 6, 8, 12, 16, 20, 24, 32.
  static const List<double> steps = <double>[2, 4, 6, 8, 12, 16, 20, 24, 32];

  double step(int n) {
    assert(n >= 1 && n <= steps.length, 'spacing step $n is 1..9');
    return steps[n - 1] * scale;
  }

  EdgeInsets pad(int n) => EdgeInsets.all(step(n));

  // The jobs. A screen asks for the job, never for a number, so the rhythm
  // cannot drift screen by screen: before this existed, ten screens used eight
  // different top insets and three of them were off the ladder.
  //
  // The rule that makes a group visible: the between-gap is always strictly
  // larger than the within-gap it contains. Rows sit 8 apart, blocks 16,
  // groups 24. When the between-gap equals the within-gap the eye cannot
  // group anything, which reads as "thrown on the page".

  /// Inside a text stack: label to value, title to subtitle.
  double get insideText => step(1); // 2

  /// A label and the control it names, or below a chip row.
  double get labelToControl => step(2); // 4

  /// Between the rows of one list.
  double get rowGap => step(4); // 8

  /// The inner padding of a row, and of a compact panel.
  double get rowInset => step(5); // 12

  /// A screen's one edge inset, and the inner padding of a full panel.
  double get screenEdge => step(6); // 16

  /// Before a new group: a section title, or a block that starts a subject.
  double get sectionGap => step(8); // 24

  /// Around an empty state.
  double get emptyState => step(9); // 32

  /// A row's own padding, horizontal and vertical. Card and flat modes differ
  /// in paint, never in metrics.
  EdgeInsets get padRow => EdgeInsets.symmetric(
        horizontal: rowInset,
        vertical: rowInset,
      );

  /// A scrolling screen's padding: the edge inset, and one group gap at the
  /// bottom so the last row is not flush with the navigation bar.
  EdgeInsets get padScreen =>
      EdgeInsets.fromLTRB(screenEdge, screenEdge, screenEdge, sectionGap);
}

/// Panel/edge treatment.
@immutable
class MmShape {
  const MmShape({
    required this.corner,
    required this.cornerSize,
    required this.borderWidth,
    this.hairlineWidth = 1.0,
    this.squareControls = false,
    this.dimmedBasemap = false,
    this.vectorBasemap = false,
    this.tintedHeaders = false,
  });

  final MmCorner corner;

  /// Radius (rounded) or cut depth (chamfer), in logical px.
  final double cornerSize;
  final double borderWidth;

  /// R63 — width of the region-separating rule (`MmTokens.hairline`)
  /// drawn by [MmCollapsibleSection] and friends. 1.0 matches the
  /// Material `Divider` the app already used, so it is neutral.
  final double hairlineWidth;

  /// R63 — make Material's own controls (chips, cards, segmented
  /// buttons, dialogs, sheets) square. Off for the six older presets,
  /// which keep Material's rounding; [corner] only governs `MmPanel`.
  /// Explicit rather than inferred from `cornerSize == 0`, because
  /// SEELE/DR Pop/Recon are sharp *panels* yet were never square chips.
  final bool squareControls;

  /// R70/R79 — draw map raster tiles through a hue-preserving dim (see
  /// `mmDimTileFilter`) so a pale basemap sits under a dark chrome. It
  /// dims, it does not de-colour: map imagery is content, and the theme's
  /// no-accent rule is about chrome, not about the map. Off for the six
  /// older presets.
  final bool dimmedBasemap;

  /// R80 — render the basemap from a vector style instead of drawing raster
  /// tiles (and instead of [dimmedBasemap], which becomes the fallback if
  /// the bundled style cannot be loaded). Studio only: it is what makes the
  /// map sharp at every zoom, keeps content colour without a filter, and
  /// stores far fewer bytes offline.
  final bool vectorBasemap;

  /// R77 — a collapsible group's header row sits on `MmTokens.raised`, one
  /// tonal step above the page, so the header (not a rule) says where a
  /// group starts. Studio only; the six older presets keep a flat header.
  final bool tintedHeaders;

}

/// Retro-futuristic chrome. All default to "off" so a calm concept
/// (SEELE) gets none; loud concepts (NERV) opt in.
@immutable
class MmOrnament {
  const MmOrnament({
    this.scanlineOpacity = 0.0,
    this.cornerBrackets = false,
    this.warningStripes = false,
  });

  /// 0 = no scanlines; ~0.04–0.08 is a subtle CRT overlay.
  final double scanlineOpacity;

  /// Draw NERV-style L brackets in the screen corners.
  final bool cornerBrackets;

  /// Section headers get a diagonal hazard-stripe bar.
  final bool warningStripes;

  bool get any => scanlineOpacity > 0 || cornerBrackets || warningStripes;
}

/// The full active skin: colour + type + shape + ornament for a preset.
@immutable
class MmSkin {
  const MmSkin({
    required this.preset,
    required this.color,
    required this.type,
    required this.shape,
    required this.ornament,
    this.space = const MmSpace(),
  });

  final MmThemePreset preset;
  final MmTokens color;
  final MmType type;
  final MmShape shape;
  final MmOrnament ornament;
  final MmSpace space;
}

// Shared calm chrome (no scanlines/brackets/stripes) — the loud concepts
// (NERV) opt into ornament; the rest stay calm.
const MmOrnament _calmOrnament = MmOrnament();

/// Build the [MmSkin] bundle for a preset. Colour comes from the shared
/// [kMmPresets]; type/shape/ornament are spec'd per concept. All six
/// brief concepts (A–F) are elaborated, so the switch is exhaustive — a
/// new preset is a compile error until its bundle is defined.
MmSkin mmSkinFor(MmThemePreset preset) {
  final MmTokens color = kMmPresets[preset]!;
  switch (preset) {
    // A — NERV Terminal: chamfered HUD panels, hazard-stripe headers,
    // a subtle scanline, corner brackets, uppercase tracked mono.
    case MmThemePreset.nerv:
      return MmSkin(
        preset: preset,
        color: color,
        type: const MmType(
          displayFamily: 'Saira',
          headingFamily: 'Saira',
          monoFamily: 'JetBrains Mono',
          upperHeadings: true,
          headingTracking: 3.0,
          slashedZero: true,
        ),
        shape: const MmShape(
            corner: MmCorner.chamfer, cornerSize: 12, borderWidth: 1.2),
        ornament: const MmOrnament(
          scanlineOpacity: 0.06,
          cornerBrackets: true,
          warningStripes: true,
        ),
      );
    // D — SEELE Monolith: brutalist, near-zero chrome, sharp edges,
    // ruthless type hierarchy. (The home dashboard already embodies
    // this; the bundle exists for components used elsewhere.)
    case MmThemePreset.seele:
      return MmSkin(
        preset: preset,
        color: color,
        type: const MmType(
          displayFamily: 'Saira',
          monoFamily: 'JetBrains Mono',
          upperHeadings: true,
          headingTracking: 4.0,
          slashedZero: true,
        ),
        shape: const MmShape(
            corner: MmCorner.sharp, cornerSize: 0, borderWidth: 1),
        ornament: _calmOrnament,
      );
    // B — AG Systems HUD: a Wipeout anti-grav cockpit. Big angular
    // display metrics, soft *rounded* livery panels, cyan/magenta accents,
    // minimal chrome (the radial gauges carry the motion, not scanlines).
    case MmThemePreset.agHud:
      return MmSkin(
        preset: preset,
        color: color,
        type: const MmType(
          displayFamily: 'Saira',
          headingFamily: 'Saira',
          monoFamily: 'JetBrains Mono',
          upperHeadings: true,
          headingTracking: 2.5,
          slashedZero: true,
        ),
        shape: const MmShape(
            corner: MmCorner.rounded, cornerSize: 18, borderWidth: 1.4),
        ornament: _calmOrnament,
      );
    // C — Hyperlocal Field: discovery-first, calm and field-legible.
    // Lower visual noise than NERV (no scanlines/brackets/stripes — the
    // node radar is the visual interest), soft rounded panels, Saira
    // headers in mixed case (calmer than the terminal's tracked caps),
    // mono for raw telemetry. AA+ contrast comes from the token set.
    case MmThemePreset.hyperlocal:
      return MmSkin(
        preset: preset,
        color: color,
        type: const MmType(
          displayFamily: 'Saira',
          headingFamily: 'Saira',
          monoFamily: 'JetBrains Mono',
          headingTracking: 2.0,
          slashedZero: true,
        ),
        shape: const MmShape(
            corner: MmCorner.rounded, cornerSize: 14, borderWidth: 1),
        ornament: _calmOrnament,
      );
    // E — DR Pop: Designers-Republic maximalism. Flat saturated colour
    // blocks, bold numerals, katakana-as-graphics, fake per-channel
    // sub-brands. Hard rectangles (sharp), heavy tracked caps; no CRT
    // chrome — the colour blocking is the whole look.
    case MmThemePreset.drPop:
      return MmSkin(
        preset: preset,
        color: color,
        type: const MmType(
          displayFamily: 'Saira',
          headingFamily: 'Saira',
          monoFamily: 'JetBrains Mono',
          upperHeadings: true,
          headingTracking: 1.5,
          slashedZero: true,
        ),
        shape: const MmShape(
            corner: MmCorner.sharp, cornerSize: 0, borderWidth: 1),
        ornament: _calmOrnament,
      );
    // G — Studio (R63): clean dark professional tool. Square everything,
    // a 1px hairline between regions, mixed-case body with small dim
    // upper-case section labels, platform sans (NO new font — the app
    // bundles Saira/JetBrains Mono and Studio uses neither for body, so
    // it reads as the platform UI face, like the tools it echoes),
    // mono only for telemetry. No ornament.
    case MmThemePreset.studio:
      return MmSkin(
        preset: preset,
        color: color,
        type: const MmType(
          monoFamily: 'JetBrains Mono',
          upperHeadings: true,
          headingTracking: 1.2,
          sansLabels: true,
        ),
        shape: const MmShape(
          corner: MmCorner.sharp,
          cornerSize: 0,
          borderWidth: 1,
          hairlineWidth: 1,
          squareControls: true,
          dimmedBasemap: true,
          vectorBasemap: true,
          tintedHeaders: true,
        ),
        ornament: _calmOrnament,
      );
    // H (R115) — Studio Light: the tool language on paper. Same square
    // control family and the same type rule as Studio (words in the UI face,
    // mono for machine data), but the opposite ground, so the ornament is
    // still none and the map is NOT dimmed: dimming exists to push a bright
    // basemap under dark chrome, and on a light page the basemap belongs to
    // the page.
    //
    // `tintedHeaders` is OFF here, and the tonal step it gave the dark skins is
    // not a light-ground device: a beige band on paper is a box, so every
    // collapsible group read as one more rectangle and the page became a stack
    // of them. A hairline rule above the label does the same job on paper,
    // where a rule *is* the table line rather than an apology for one.
    case MmThemePreset.studioLight:
      return MmSkin(
        preset: preset,
        color: color,
        type: const MmType(
          monoFamily: 'JetBrains Mono',
          upperHeadings: true,
          headingTracking: 1.4,
          sansLabels: true,
        ),
        shape: const MmShape(
          corner: MmCorner.sharp,
          cornerSize: 0,
          borderWidth: 1,
          hairlineWidth: 1,
          squareControls: true,
          dimmedBasemap: false,
          vectorBasemap: false,
          tintedHeaders: false,
        ),
        ornament: _calmOrnament,
      );
    // F — Tactical Recon: night-ops codec. OLED-black, single amber
    // phosphor hue, all-mono (Departure-Mono-class) terminal type, sharp
    // edges, glare-/battery-aware (no scanline overdraw on the black).
    case MmThemePreset.recon:
      return MmSkin(
        preset: preset,
        color: color,
        type: const MmType(
          displayFamily: 'JetBrains Mono',
          headingFamily: 'JetBrains Mono',
          monoFamily: 'JetBrains Mono',
          upperHeadings: true,
          headingTracking: 2.0,
          slashedZero: true,
        ),
        shape: const MmShape(
            corner: MmCorner.sharp, cornerSize: 0, borderWidth: 1),
        ornament: _calmOrnament,
      );
  }
}

/// `context.skin` — the active skin bundle. Watches [ThemeController]
/// so widgets rebuild when the preset (or high-contrast) changes.
/// High-contrast forces the SEELE skin (the accessibility benchmark).
///
/// Tolerant of a missing [ThemeController] (e.g. an isolated widget
/// test, or a component used before the provider tree is set up): it
/// falls back to the default SEELE skin rather than throwing, so
/// migrating a screen to the component library never forces its test
/// harness to also wire a ThemeController.
extension MmSkinContext on BuildContext {
  MmSkin get skin {
    MmThemePreset preset = MmThemePreset.seele;
    try {
      final ThemeController tc = watch<ThemeController>();
      preset = tc.highContrast ? MmThemePreset.seele : tc.preset;
    } on ProviderNotFoundException {
      // No ThemeController above us — default skin.
    }
    return mmSkinFor(preset);
  }

  /// R104 — the skin for code that runs OUTSIDE a build (an `onTap`, a
  /// `showDialog` builder before it mounts). Reads the controller without
  /// subscribing, which [skin] cannot do: `watch` asserts outside build.
  MmSkin get skinRead {
    MmThemePreset preset = MmThemePreset.seele;
    try {
      final ThemeController tc = Provider.of<ThemeController>(this, listen: false);
      preset = tc.highContrast ? MmThemePreset.seele : tc.preset;
    } on ProviderNotFoundException {
      // No ThemeController above us — default skin.
    }
    return mmSkinFor(preset);
  }
}
