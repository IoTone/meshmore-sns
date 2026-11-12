// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import 'mm_skin.dart' show MmShape;
import '../ui/mm_shape.dart' show kSquareRadius;

/// The six design-concept themes (UX brief A–F). **D "SEELE Monolith"
/// = [MmThemePreset.seele]** is the high-contrast accessibility
/// benchmark ([kDefaultPreset] is the quiet one, STUDIO). Screens are
/// built against the semantic [MmTokens] names only — never hard-coded
/// colours — so every preset works (R14).
///
/// R63 adds a seventh, [MmThemePreset.studio]: a clean-dark,
/// professional-tool skin (layered greys, hairlines, square corners,
/// one restrained accent). It is the only preset that *uses* the layered
/// surface stack added in R63; the other six derive it (see [MmTokens]).
///
/// R115 added an eighth, Studio Light, as the tool language on paper. It
/// is gone: with the LDMUX light looks (Air, Daybreak) it was the third
/// paper ground, it shared Studio's layout, type and audio pack exactly,
/// and its palette was the closest in the app to Daybreak's — a preset
/// switch bought a ground colour and nothing else. The lessons it taught
/// are a standing contract for every light preset, held in
/// `test/theme/light_ground_test.dart`.
enum MmThemePreset {
  nerv,
  agHud,
  hyperlocal,
  seele,
  drPop,
  recon,
  studio,
  // The owner's own looks, ported from LDMUX (2026-11-09). Four palettes
  // whose every role was measured before it was drawn, including the
  // control-boundary role this app had been missing.
  forest,
  air,
  daybreak,
  umber,
}

extension MmThemePresetX on MmThemePreset {
  String get label => switch (this) {
        MmThemePreset.nerv => 'NERV Terminal',
        MmThemePreset.agHud => 'AG-HUD',
        MmThemePreset.hyperlocal => 'Hyperlocal',
        MmThemePreset.seele => 'SEELE Monolith — default · high-contrast',
        MmThemePreset.drPop => 'DR Pop',
        MmThemePreset.recon => 'Recon Night',
        MmThemePreset.studio => 'Studio Dark — clean · square',
        MmThemePreset.forest => 'Forest — dark pine · one green',
        MmThemePreset.air => 'Air — white page · blue',
        MmThemePreset.daybreak => 'Daybreak — white page · vermilion',
        MmThemePreset.umber => 'Umber — gruvbox browns',
      };

  /// Asset-folder slug for the R12 per-theme audio pack. Used by
  /// `AssetAudioPack` to resolve `assets/audio/<key>/<cue>.wav`.
  /// Also matches the slugs used in `brand/_audio_pack.py` and in
  /// the per-theme grid mockups (`brand/_grid_mockup.py`).
  String get audioPackKey => switch (this) {
        MmThemePreset.nerv => 'nerv',
        MmThemePreset.agHud => 'aghud',
        MmThemePreset.hyperlocal => 'hyperlocal',
        MmThemePreset.seele => 'seele',
        MmThemePreset.drPop => 'drpop',
        MmThemePreset.recon => 'recon',
        // R63 — deliberately ALIASES the Hyperlocal pack (the calmest
        // existing one). No studio audio exists and synthesising it is
        // out of scope; see `assets/audio/` and the R63 spec entry.
        MmThemePreset.studio => 'hyperlocal',
        // Same reason again: these four change colour, not the cue set.
        MmThemePreset.forest => 'hyperlocal',
        MmThemePreset.air => 'hyperlocal',
        MmThemePreset.daybreak => 'hyperlocal',
        MmThemePreset.umber => 'hyperlocal',
      };
}

/// Preset-independent semantic colour contract. Every preset supplies
/// the nine core colours; screens reference only these names.
///
/// R63 — the **layer stack** (a window base, a panel, a raised control,
/// a selected/hover state), a **hairline**, a **disabled** text tier and
/// the label colour **on the accent**. These are *optional* at
/// construction and **derived** when omitted, from the nine core colours,
/// to exactly what the app already drew:
///
/// | getter          | derived (omitted) as | why that is neutral |
/// |-----------------|----------------------|---------------------|
/// | [raised]        | [surfaceAlt]         | the theme already used `surfaceAlt` for `surfaceContainerHigh` |
/// | [selected]      | [surfaceAlt]         | and for `surfaceContainerHighest` |
/// | [hairline]      | [line]               | every divider/border already used `line` |
/// | [edge]          | [line]               | R14: the control boundary was `line`; a preset that does not state one keeps drawing exactly what it drew |
/// | [onAccent]      | [base]               | the theme already put `base` on `accent` |
/// | [fgDisabled]    | [fgMuted] at 50 %    | new; nothing reads it for the six old presets |
///
/// So a preset that supplies none of them is *by construction* the
/// colour it always was (pinned by `test/theme/mm_layers_test.dart`);
/// only a preset that wants a real stack (Studio) supplies them.
@immutable
class MmTokens {
  const MmTokens({
    required this.base,
    required this.surface,
    required this.surfaceAlt,
    required this.line,
    required this.fg,
    required this.fgMuted,
    required this.accent,
    required this.alert,
    required this.ok,
    Color? raised,
    Color? selected,
    Color? hairline,
    Color? onAccent,
    Color? fgDisabled,
    Color? onAlert,
    Color? link,
    Color? warn,
    Color? edge,
    Color? alertInk,
  })  : _warn = warn,
        _edge = edge,
        _alertInk = alertInk,
        _link = link,
        _onAlert = onAlert,
        _raised = raised,
        _selected = selected,
        _hairline = hairline,
        _onAccent = onAccent,
        _fgDisabled = fgDisabled;

  final Color base;
  final Color surface;
  final Color surfaceAlt;
  final Color line;
  final Color fg;
  final Color fgMuted;
  final Color accent;
  final Color alert;
  final Color ok;

  /// R97 — the colour of a live radio link. Deliberately NOT [ok]:
  /// `ok` is a per-preset success token that is grey-beige in SEELE, cyan in
  /// AG-HUD and amber in Recon, so a "Linked" chip was not green in most
  /// skins and disagreed with Studio's own dashboard dot. A connection state
  /// is a state, not decoration, so it keeps one hue everywhere: green.
  final Color? _link;

  /// Caution: a reading that is not yet a fault. `accent` means selection and
  /// `alert` means danger, so a gauge with "35 % left" had no role to wear and
  /// the battery screen carried two literals instead — an amber and a red that
  /// were tuned on a dark ground and are 1.9:1 on paper. Derived as that amber
  /// for every preset that does not state one, so the dark skins are unchanged.
  final Color? _warn;

  Color get warn => _warn ?? const Color(0xFFFFB020);

  Color get link => _link ?? const Color(0xFF3DDC84);

  final Color? _raised;
  final Color? _selected;
  final Color? _hairline;
  final Color? _edge;
  final Color? _alertInk;
  final Color? _onAccent;
  final Color? _fgDisabled;
  final Color? _onAlert;

  /// R68 — label drawn on a filled [alert]. Derived as [fg] (what
  /// `ColorScheme.onError` always was), so the six older presets are
  /// unchanged. Studio's alert is a pale tint, so light text on it was
  /// 1.5:1; Studio supplies a dark one.
  Color get onAlert => _onAlert ?? fg;

  /// Controls (buttons, keys, inputs) sitting on a [surface] panel.
  Color get raised => _raised ?? surfaceAlt;

  /// Hover / pressed / selected row. One step above [raised].
  Color get selected => _selected ?? surfaceAlt;

  /// The 1px region separator (see `MmShape.hairlineWidth`).
  Color get hairline => _hairline ?? line;

  /// The outline of something you press: a button, an input, a card's side.
  ///
  /// D11.5 — ported from the owner's LDMUX project, which is the reason this
  /// role exists at all. A divider and a control's boundary were one value
  /// (`line`), so on the older dark presets an "outlined" control was outlined
  /// at 1.26:1 to 2.75:1 against the layer it sits on — under the 3:1 that
  /// WCAG 1.4.11 asks for a non-text boundary, and invisible in practice. On a
  /// paper ground the same value happened to pass, which is why the defect read
  /// as a difference in taste between skins.
  ///
  /// Each preset states the smallest blend of its own `line` toward its own
  /// `fg` that clears 3:1 on both the page and the raised layer, so a skin
  /// keeps its hue and the change is as small as the floor allows. Derived as
  /// `line` when a preset states nothing, so an unstated preset draws exactly
  /// what it drew before.
  ///
  /// Measured before/after is in `meshmore-scope-of-record.md` D11.5;
  /// `test/theme/edge_floor_test.dart` recomputes it.
  Color get edge => _edge ?? line;

  /// [alert] as **text**, rather than as a fill or a graphic.
  ///
  /// One colour was doing two jobs with two different floors. As a fill or an
  /// icon an alert needs 3:1 against the page (WCAG 1.4.11, a graphical
  /// object) and every preset's alert already clears it. As *text* it needs
  /// 4.5:1, and the three darkest alerts did not: seele 3.13:1, nerv 3.34:1,
  /// recon 2.79:1 against the panel they were written on. Those presets are
  /// saturated crimsons chosen to shout as a block, which is the right choice
  /// for a fill and the wrong one for a sentence.
  ///
  /// So the fill keeps its colour and the ink is lifted into the same family
  /// until it can be read. Derived as [alert] when a preset states nothing, so
  /// the eight presets that were already legible draw exactly what they drew.
  Color get alertInk => _alertInk ?? alert;

  /// Label drawn on a filled [accent].
  Color get onAccent => _onAccent ?? base;

  /// Disabled text/icons, below [fgMuted].
  Color get fgDisabled => _fgDisabled ?? fgMuted.withValues(alpha: .5);

  /// True when this preset supplies a real layer stack of its own
  /// (rather than the derived single `surfaceAlt` step).
  bool get hasLayerStack => _raised != null && _selected != null;

  /// R115 — a light ground needs a light Material scheme, not a dark one
  /// with pale paint over it: `Brightness` decides dozens of framework
  /// defaults (elevation tints, ink, splash alpha), so it is derived from
  /// the ground the preset actually draws rather than passed in beside it.
  bool get isLight => base.computeLuminance() > 0.5;

  /// The stack, lowest to highest: base, surface, raised, selected.
  List<Color> get layers => <Color>[base, surface, raised, selected];
}

/// Catalogued from `meshmore-sns-UX-brief.md` (per-concept palettes).
const Map<MmThemePreset, MmTokens> kMmPresets = <MmThemePreset, MmTokens>{
  // G (R63) — Studio: a clean, professional, readable dark skin: a
  // real four-step grey stack (each step >= ~1.1:1 luminance over the
  // one below), a hairline rule visible on every layer, and NO hue at
  // all. R68 (owner direction): the accent is a light grey (#D0D0D0,
  // saturation 0) so active/selected/primary is carried by LIGHTNESS,
  // never by colour; alert and ok are low-saturation tints (HSV
  // saturation <= 0.30) that still read as warning/success without being
  // the loudest thing on a grey screen. R65 raised the rule to #4A4A4A.
  // `onAlert` is dark because a pale alert fill needs dark text.
  // `surfaceAlt` is the raised step so Material's own container roles
  // land on the stack.
  MmThemePreset.studio: MmTokens(
    base: Color(0xFF141414),
    surface: Color(0xFF202020),
    surfaceAlt: Color(0xFF2B2B2B),
    line: Color(0xFF4A4A4A),
    fg: Color(0xFFE2E2E2),
    fgMuted: Color(0xFFA0A0A0),
    accent: Color(0xFFD0D0D0),
    alert: Color(0xFFD6A7A1),
    ok: Color(0xFFA9C4A7),
    raised: Color(0xFF2B2B2B),
    selected: Color(0xFF363636),
    hairline: Color(0xFF4A4A4A),
    onAccent: Color(0xFF141414),
    fgDisabled: Color(0xFF808080),
    onAlert: Color(0xFF141414),
    // D11.5 — a control's outline, not a rule: `line` was 2.08:1 on the
    // page, so an outlined control here was outlined in a colour nobody
    // could see. Smallest blend of this preset's own line toward its own
    // fg that clears 3:1 on the page and the raised layer: 3.94 / 3.49 / 3.03.
    edge: Color(0xFF747474),
  ),
  // D — default.
  MmThemePreset.seele: MmTokens(
    base: Color(0xFF000000),
    surface: Color(0xFF0E0E0C),
    surfaceAlt: Color(0xFF15140F),
    line: Color(0xFF2A2A26),
    fg: Color(0xFFEDE6D6),
    fgMuted: Color(0xFFBCB6A8),
    accent: Color(0xFFEDE6D6),
    alert: Color(0xFFC8102E),
    ok: Color(0xFFBCB6A8),
    // D11.5 — a control's outline, not a rule: `line` was 1.46:1 on the
    // page, so an outlined control here was outlined in a colour nobody
    // could see. Smallest blend of this preset's own line toward its own
    // fg that clears 3:1 on the page and the raised layer: 3.44 / 3.17 / 3.02.
    edge: Color(0xFF64625B),
    // The disabled tier is the quietest value that is still legible: as
    // far from the second voice as the 3:1 floor on every layer allows.
    fgDisabled: Color(0xFF67645C),
    // The same red, lifted until it can be read as text (4.5:1 on the
    // page and the panel). `alert` stays the fill and the graphic.
    alertInk: Color(0xFFD34E5F),
    // The label on a filled alert: cream reads better on this crimson than
    // the ground does (4.73:1 against 3.57:1).
    onAlert: Color(0xFFEDE6D6),
  ),
  MmThemePreset.nerv: MmTokens(
    base: Color(0xFF0A0E1A),
    surface: Color(0xFF121826),
    surfaceAlt: Color(0xFF1B2436),
    line: Color(0xFF243049),
    fg: Color(0xFFE6ECF5),
    fgMuted: Color(0xFFA6B2C8),
    accent: Color(0xFFFF7A00),
    // Was #E6005C: 4.14:1 against this skin's near-black `onAlert`, under the
    // 4.5 every label is held to. One step brighter keeps the NERV magenta.
    alert: Color(0xFFFA1F6E),
    ok: Color(0xFF9CFF00),
    // D11.5 — a control's outline, not a rule: `line` was 1.46:1 on the
    // page, so an outlined control here was outlined in a colour nobody
    // could see. Smallest blend of this preset's own line toward its own
    // fg that clears 3:1 on the page and the raised layer: 3.75 / 3.46 / 3.03.
    edge: Color(0xFF646E82),
    // The disabled tier is the quietest value that is still legible: as
    // far from the second voice as the 3:1 floor on every layer allows.
    fgDisabled: Color(0xFF666F81),
    // The same red, lifted until it can be read as text (4.5:1 on the
    // page and the panel). `alert` stays the fill and the graphic.
    alertInk: Color(0xFFE64085),
    // The label on a filled alert: the ground is the better of the two
    // candidates on this fill, where the derived fg is not.
    onAlert: Color(0xFF0A0E1A),
  ),
  MmThemePreset.agHud: MmTokens(
    base: Color(0xFF05060B),
    surface: Color(0xFF10131F),
    surfaceAlt: Color(0xFF161B2A),
    line: Color(0xFF20283B),
    fg: Color(0xFFDDF6FF),
    fgMuted: Color(0xFF9AACC0),
    accent: Color(0xFF22D3EE),
    alert: Color(0xFFFF2D78),
    ok: Color(0xFF22D3EE),
    // D11.5 — a control's outline, not a rule: `line` was 1.38:1 on the
    // page, so an outlined control here was outlined in a colour nobody
    // could see. Smallest blend of this preset's own line toward its own
    // fg that clears 3:1 on the page and the raised layer: 3.56 / 3.26 / 3.02.
    edge: Color(0xFF5B6878),
    // The disabled tier is the quietest value that is still legible: as
    // far from the second voice as the 3:1 floor on every layer allows.
    fgDisabled: Color(0xFF5E6A78),
    // The label on a filled alert: the ground is the better of the two
    // candidates on this fill, where the derived fg is not.
    onAlert: Color(0xFF05060B),
  ),
  MmThemePreset.hyperlocal: MmTokens(
    base: Color(0xFF0B0F17),
    surface: Color(0xFF161B26),
    surfaceAlt: Color(0xFF1E2533),
    line: Color(0xFF263041),
    fg: Color(0xFFDDE7EF),
    fgMuted: Color(0xFFA4B0C4),
    accent: Color(0xFF35E0F0),
    alert: Color(0xFFFF3B6B),
    ok: Color(0xFF7CFF6B),
    // The same red, lifted until it can be read as *text* on the raised layer.
    // `alert` is 4.45:1 on `surfaceAlt`, which is under the 4.5 floor and is
    // where every destructive label in a sheet lands; the fill keeps its own
    // saturated value, because a fill is a graphic and answers to 3:1.
    alertInk: Color(0xFFFF4371),
    // D11.5 — a control's outline, not a rule: `line` was 1.44:1 on the
    // page, so an outlined control here was outlined in a colour nobody
    // could see. Smallest blend of this preset's own line toward its own
    // fg that clears 3:1 on the page and the raised layer: 3.77 / 3.38 / 3.01.
    edge: Color(0xFF656F7D),
    // The disabled tier is the quietest value that is still legible: as
    // far from the second voice as the 3:1 floor on every layer allows.
    fgDisabled: Color(0xFF67707F),
    // The label on a filled alert: the ground is the better of the two
    // candidates on this fill, where the derived fg is not.
    onAlert: Color(0xFF0B0F17),
  ),
  MmThemePreset.drPop: MmTokens(
    base: Color(0xFF101014),
    surface: Color(0xFF1C1C24),
    surfaceAlt: Color(0xFF24242E),
    line: Color(0xFF33333F),
    fg: Color(0xFFF2F0E6),
    fgMuted: Color(0xFFB0B0C0),
    accent: Color(0xFFFF2E88),
    // Was the accent itself (#FF2E88): an attention colour that is also the
    // primary action is not an attention colour, and an unread count drawn in it
    // disappeared into a selected chip of the same colour. A hot red-orange
    // keeps DR Pop's loudness and says "look here" instead of "press me".
    alert: Color(0xFFFF5A3C),
    ok: Color(0xFFD7FF00),
    // D11.5 — a control's outline, not a rule: `line` was 1.52:1 on the
    // page, so an outlined control here was outlined in a colour nobody
    // could see. Smallest blend of this preset's own line toward its own
    // fg that clears 3:1 on the page and the raised layer: 3.74 / 3.34 / 3.03.
    edge: Color(0xFF6E6E73),
    // The disabled tier is the quietest value that is still legible: as
    // far from the second voice as the 3:1 floor on every layer allows.
    fgDisabled: Color(0xFF6E6E79),
    // The label on a filled alert: the ground is the better of the two
    // candidates on this fill, where the derived fg is not.
    onAlert: Color(0xFF101014),
  ),
  MmThemePreset.recon: MmTokens(
    base: Color(0xFF000000),
    surface: Color(0xFF0A0A07),
    surfaceAlt: Color(0xFF141414),
    line: Color(0xFF6E4E00),
    fg: Color(0xFFFFB000),
    fgMuted: Color(0xFFC79433),
    accent: Color(0xFFFFB000),
    // Was #B8302C: 3.50:1 on black, the worst of the set. Lifted along its own
    // ramp so the pair clears 4.5 without turning into a different red.
    alert: Color(0xFFD24540),
    ok: Color(0xFFFFB000),
    // D11.5 — a control's outline, not a rule: `line` was 2.75:1 on the
    // page, so an outlined control here was outlined in a colour nobody
    // could see. Smallest blend of this preset's own line toward its own
    // fg that clears 3:1 on the page and the raised layer: 3.43 / 3.24 / 3.01.
    edge: Color(0xFF815B00),
    // The disabled tier is the quietest value that is still legible: as
    // far from the second voice as the 3:1 floor on every layer allows.
    fgDisabled: Color(0xFF7F5F21),
    // The same red, lifted until it can be read as text (4.5:1 on the
    // page and the panel). `alert` stays the fill and the graphic.
    alertInk: Color(0xFFCD5314),
    // The label on a filled alert: the ground is the better of the two
    // candidates on this fill, where the derived fg is not.
    onAlert: Color(0xFF000000),
  ),
  // --- The four LDMUX looks (2026-11-09) -------------------------------
  //
  // Ported from the owner's LDMUX project, where every neutral is a Radix
  // Colors 3.0 value and every role has a stated contrast floor. The mapping
  // into this app's roles is the same for all four, and it is the part worth
  // reading before changing a number:
  //
  //   LDMUX edge -> line      a control and panel boundary, held to 3:1
  //   LDMUX line -> hairline  a divider, meant to be barely there
  //   LDMUX dim  -> fgMuted   the second voice, held to 4.5:1
  //   LDMUX muted             NOT mapped: this app has no third *legible*
  //                           text tier, and its `fgDisabled` is a disabled
  //                           style rather than a note. Recorded in
  //                           `test/theme/ldmux_presets_test.dart` so the
  //                           value is not lost.
  //   LDMUX chosen            NOT mapped as a fill: it is a 3:1 *outline*
  //                           for a chosen control, and this app draws that
  //                           state with `accent` plus a rule.
  //
  // Values moved off the LDMUX literal, each one step in the same family,
  // because this app draws roles on layers LDMUX does not have:
  //
  //  * Daybreak's `accent` and `alert`, and Umber's `alert`: 4.26 / 4.46 /
  //    4.03 on `surfaceAlt`, under the label floor. 4.5 is measured on
  //    `base` and `surface` in LDMUX; this app also writes labels on a panel.
  //  * Both light themes' `edge`: 2.86 and 3.02 on `surfaceAlt`, under the
  //    control-boundary floor, one step darker in the same grey.
  //  * Air's `surfaceAlt` and `alert`, and Daybreak's `surface`,
  //    `surfaceAlt` and `hairline`: the light-ground contract in
  //    `test/theme/light_ground_test.dart` wants every layer step at 1.08:1
  //    and a hairline visible on the page (1.6:1), and the ported values
  //    landed at 1.065 / 1.077 and 1.57 / 1.41. The alert then had to follow
  //    one step darker to keep 4.5:1 on the darker panel.
  //
  // `test/theme/ldmux_presets_test.dart` pins the literals that did not move.
  MmThemePreset.forest: MmTokens(
    base: Color(0xFF121514),
    surface: Color(0xFF1A211D),
    surfaceAlt: Color(0xFF232C27),
    // edge, not line: a row or control boundary has to be visible at 3:1.
    // LDMUX's divider value: a rule is meant to be barely there.
    line: Color(0xFF2F3A33),
    // LDMUX's edge value, under this app's name for it: the outline of a
    // control, held to 3:1 on every layer it is drawn on.
    hairline: Color(0xFF2F3A33),
    edge: Color(0xFF7C8884),
    fg: Color(0xFFEDF2EE),
    fgMuted: Color(0xFFAEBBB2),
    accent: Color(0xFF7FC98A),
    alert: Color(0xFFE58A84),
    // Not a green the palette names: LDMUX has no success role, and its
    // accent is already green, so `ok` is a paler leaf tint that reads as
    // "fine" without becoming a second accent.
    ok: Color(0xFFA6D189),
    raised: Color(0xFF232C27),
    selected: Color(0xFF2F3A33),
    onAccent: Color(0xFF0E1512),
    // The LDMUX muted grey, blended halfway to the page exactly as the
    // derived tier would be, then nudged so it clears 3:1 on every layer with
    // headroom (the answer above is 3.83 / 3.68 / 3.22).
    fgDisabled: Color(0xFF7B847E),
    onAlert: Color(0xFF121514),
    warn: Color(0xFFE6C177),
  ),
  MmThemePreset.air: MmTokens(
    base: Color(0xFFFFFFFF),
    surface: Color(0xFFF4F6F9),
    // One step darker than slate-3: `surface` → `surfaceAlt` was 1.065:1, and
    // a panel step under 1.08 does not read as a panel.
    surfaceAlt: Color(0xFFE8ECF1),
    // LDMUX's edge #8B8D98 is 2.86:1 on this theme's raised fill, under the
    // control-boundary floor; one step darker in the same blue-grey.
    // LDMUX's divider value: a rule is meant to be barely there.
    line: Color(0xFFC4C6D0),
    // slate-7 is 1.57:1 on white, which is not a rule you can see on a phone
    // in daylight; one step darker in the same blue-grey, 1.70:1.
    // LDMUX's edge value, under this app's name for it: the outline of a
    // control, held to 3:1 on every layer it is drawn on.
    hairline: Color(0xFFC4C6D0),
    edge: Color(0xFF7E808A),
    fg: Color(0xFF1C2024),
    fgMuted: Color(0xFF4D525A),
    accent: Color(0xFF0A68BA),
    // red-11 (#CE2C31) is 4.43:1 on the darkened panel above, under the label
    // floor; one step darker in the same red.
    alert: Color(0xFFC92A2F),
    ok: Color(0xFF17703A),
    raised: Color(0xFFE8ECF1),
    selected: Color(0xFFCDCED6),
    onAccent: Color(0xFFFFFFFF),
    fgDisabled: Color(0xFF6D7178),
    onAlert: Color(0xFFFFFFFF),
    link: Color(0xFF17703A),
    warn: Color(0xFF8A5A00),
  ),
  MmThemePreset.daybreak: MmTokens(
    base: Color(0xFFFFFFFF),
    // Olive-2 is 1.077:1 off the page, just under the step floor this app's
    // light grounds are held to; one step darker.
    surface: Color(0xFFF3F5F1),
    surfaceAlt: Color(0xFFE8EBE7),
    // LDMUX's divider value: a rule is meant to be barely there.
    line: Color(0xFFC2C6C1),
    // olive-7 is 1.41:1 on white: invisible as a rule on paper. One step
    // darker in the same warm grey, 1.73:1.
    // LDMUX's edge value, under this app's name for it: the outline of a
    // control, held to 3:1 on every layer it is drawn on.
    hairline: Color(0xFFC2C6C1),
    edge: Color(0xFF7A7F79),
    fg: Color(0xFF1D211C),
    fgMuted: Color(0xFF4D524B),
    // LDMUX tomato-11 (#D13415) is 4.26:1 on this theme's raised fill, under
    // the label floor; one step darker in the same vermilion.
    accent: Color(0xFFBE2C11),
    // Same correction for danger: red-11 is 4.46:1 on the raised fill.
    alert: Color(0xFFC4272C),
    ok: Color(0xFF17703A),
    raised: Color(0xFFE8EBE7),
    selected: Color(0xFFD7DAD7),
    onAccent: Color(0xFFFFFFFF),
    fgDisabled: Color(0xFF767A74),
    onAlert: Color(0xFFFFFFFF),
    link: Color(0xFF17703A),
    warn: Color(0xFF8A5A00),
  ),
  MmThemePreset.umber: MmTokens(
    base: Color(0xFF211D1B),
    surface: Color(0xFF2B2521),
    surfaceAlt: Color(0xFF38312B),
    // LDMUX's divider value: a rule is meant to be barely there.
    line: Color(0xFF4A403A),
    // LDMUX's edge value, under this app's name for it: the outline of a
    // control, held to 3:1 on every layer it is drawn on.
    hairline: Color(0xFF4A403A),
    edge: Color(0xFF8C7F73),
    fg: Color(0xFFE7D7AD),
    fgMuted: Color(0xFFC5B18D),
    accent: Color(0xFFE78A4E),
    // gruvbox red #EA6962 is 4.08:1 on the raised fill; lightened one step.
    alert: Color(0xFFF07A74),
    // gruvbox-material's aqua, which is this family's own "good" colour.
    ok: Color(0xFF89B482),
    raised: Color(0xFF38312B),
    selected: Color(0xFF4A403A),
    onAccent: Color(0xFF282828),
    fgDisabled: Color(0xFF9C8C70),
    onAlert: Color(0xFF211D1B),
    warn: Color(0xFFD8A657),
  ),
};

/// The skin a fresh install opens on. STUDIO: the quiet, sans-face,
/// square-control preset. The technical presets are a deliberate choice in
/// Personalisation, not the first thing a new user meets.
const MmThemePreset kDefaultPreset = MmThemePreset.studio;

MmThemePreset presetFromId(String? id) => MmThemePreset.values.firstWhere(
      (MmThemePreset p) => p.name == id,
      orElse: () => kDefaultPreset,
    );

/// Build a Material 3 [ThemeData] from a token set.
///
/// R115 — the scheme's [Brightness] is derived from the ground the preset
/// draws ([MmTokens.isLight]) rather than fixed to dark: a light preset with
/// a dark scheme gets dark-theme framework defaults (elevation tints, splash
/// alpha, ink on disabled controls) over pale paint, which is the washed-out
/// look a real light theme must avoid.
///
/// Binds **every** commonly-used colour role + the text/icon themes to
/// the tokens — including the M3 surface-container roles that
/// `ColorScheme.dark(...)` would otherwise leave at fixed defaults.
/// Without this, switching presets only nudged a couple of accents
/// (the "themes don't change" bug); now the whole UI re-skins.
///
/// [shape] (R63) only matters for [MmShape.squareControls]: when true,
/// chips/cards/segmented buttons/dialogs/sheets are square. When null or
/// false the output is byte-for-byte what it was before R63.
ThemeData buildMmTheme(MmTokens t, {String? fontFamily, MmShape? shape}) {
  // R98 — "square" is a 1 px corner, not 0 (see `kSquareRadius`).
  final bool square = shape?.squareControls ?? false;
  final BorderRadius squareRadius = BorderRadius.circular(kSquareRadius);
  final RoundedRectangleBorder? squareBorder =
      square ? RoundedRectangleBorder(borderRadius: squareRadius) : null;
  // R71 -- Material 3 gives Filled/Outlined/Text/Elevated buttons, FABs,
  // popup menus and text fields their own rounded default (a stadium
  // pill for buttons), independent of the chip/card/dialog shapes set
  // below. Left alone, a square skin showed two control families side
  // by side (pill "Scan area" over square "Starred" chips). When
  // [MmShape.squareControls] is on, every one of them is square too.
  final ButtonStyle? squareButton = square
      ? ButtonStyle(
          shape: WidgetStateProperty.all<OutlinedBorder>(
              RoundedRectangleBorder(borderRadius: squareRadius)))
      : null;
  // R114 — a text button must look like a control in every preset, not only in
  // the square one. A bare `TextButton` on these grounds is indistinguishable
  // from a label (Connect, Retry, Configure, Details, Unblock, Edit), which is
  // the defect `MmAction` was built to fix per site; giving the theme the shape
  // fixes the class once. The label sits on `surfaceAlt`, one tonal step above
  // the page, inside a hairline in the skin's own corner, at the app's 48 dp
  // minimum. Dialog and sheet action rows keep TextButtons and now inherit the
  // same boundary, which is the pairing convention rather than a change to it.
  final double controlCorner = square
      ? kSquareRadius
      : ((shape?.cornerSize ?? 8).clamp(2, 8)).toDouble();
  final BorderRadius controlRadius = BorderRadius.circular(controlCorner);
  final ButtonStyle affordanceTextButton = ButtonStyle(
    minimumSize: WidgetStateProperty.all<Size>(const Size(0, 48)),
    padding: WidgetStateProperty.all<EdgeInsetsGeometry>(
        const EdgeInsets.symmetric(horizontal: 12)),
    shape: WidgetStateProperty.all<OutlinedBorder>(
        RoundedRectangleBorder(borderRadius: controlRadius)),
    side: WidgetStateProperty.resolveWith<BorderSide>(
      (Set<WidgetState> states) => BorderSide(
        color: states.contains(WidgetState.disabled)
            ? t.line.withValues(alpha: .5)
            : t.line,
        width: shape?.borderWidth ?? 1,
      ),
    ),
    backgroundColor: WidgetStateProperty.resolveWith<Color>(
      (Set<WidgetState> states) => states.contains(WidgetState.disabled)
          ? t.surfaceAlt.withValues(alpha: .4)
          : t.surfaceAlt,
    ),
    foregroundColor: WidgetStateProperty.resolveWith<Color>(
      (Set<WidgetState> states) =>
          states.contains(WidgetState.disabled) ? t.fgMuted : t.fg,
    ),
  );
  OutlineInputBorder squareField(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: squareRadius, borderSide: BorderSide(color: c, width: w));
  final Brightness brightness = t.isLight ? Brightness.light : Brightness.dark;
  final ColorScheme scheme = ColorScheme(
    brightness: brightness,
    surface: t.base,
    onSurface: t.fg,
    surfaceContainerLowest: t.base,
    surfaceContainerLow: t.surface,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.raised,
    surfaceContainerHighest: t.selected,
    surfaceDim: t.base,
    surfaceBright: t.surfaceAlt,
    onSurfaceVariant: t.fgMuted,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer: t.surfaceAlt,
    onPrimaryContainer: t.accent,
    secondary: t.accent,
    onSecondary: t.onAccent,
    secondaryContainer: t.surfaceAlt,
    onSecondaryContainer: t.fg,
    tertiary: t.ok,
    onTertiary: t.base,
    // Material's `error` is what an error *reads* as, and this app draws it as
    // text in 37 places, so it is the ink rather than the saturated fill the
    // skin uses for a block. `onError` is what is written on that ink.
    error: t.alertInk,
    onError: t.base,
    // The container pair is the filled variant; it is used by one control (the
    // destructive confirm) and that control now takes the ink itself.
    errorContainer: t.alertInk,
    onErrorContainer: t.base,
    // Material's `outline` is the boundary of a control; `outlineVariant` is
    // the quieter divider beside it. They were the same value, which is the
    // same defect D11.5 fixes in the tokens.
    outline: t.edge,
    outlineVariant: t.line,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xCC000000),
    inverseSurface: t.fg,
    onInverseSurface: t.base,
    inversePrimary: t.base,
    surfaceTint: t.accent,
  );
  // R55 — the active skin's display face becomes the app-wide default,
  // so every screen (not just the migrated components) reads in the
  // brand type. Telemetry/mono text sets its own family explicitly.
  final TextTheme base = ThemeData(brightness: brightness).textTheme.apply(
      bodyColor: t.fg,
      displayColor: t.fg,
      decorationColor: t.fg,
      fontFamily: fontFamily);
  // The bundled display face (Saira) renders *light* at the regular
  // weight, so non-bold body/label text read dim and thin on the dark
  // grounds. Nudge the base weight up to medium for legibility (paired
  // with the brighter `fgMuted` tokens for secondary text).
  TextStyle? med(TextStyle? s) => s?.copyWith(fontWeight: FontWeight.w500);
  final TextTheme text = base.copyWith(
    bodyLarge: med(base.bodyLarge),
    bodyMedium: med(base.bodyMedium),
    bodySmall: med(base.bodySmall),
    labelLarge: med(base.labelLarge),
    labelMedium: med(base.labelMedium),
    labelSmall: med(base.labelSmall),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.base,
    canvasColor: t.base,
    dividerColor: t.line,
    cardColor: t.surface,
    textTheme: text,
    primaryTextTheme: text,
    iconTheme: IconThemeData(color: t.fg),
    primaryIconTheme: IconThemeData(color: t.fg),
    cardTheme: CardThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      // R66: a square (Studio) card gets a visible edge, since surface on base
      // is only ~1.13:1 and has no boundary otherwise. D11.5: that edge is
      // `edge`, the control-boundary role held to 3:1, not the divider it used
      // to borrow. Null side / unchanged shape for every other preset, which
      // draws its own elevation.
      shape: square
          ? RoundedRectangleBorder(
              side: BorderSide(color: t.edge, width: shape!.hairlineWidth),
              borderRadius: squareRadius)
          : null,
    ),
    filledButtonTheme:
        square ? FilledButtonThemeData(style: squareButton) : null,
    outlinedButtonTheme:
        square ? OutlinedButtonThemeData(style: squareButton) : null,
    textButtonTheme: TextButtonThemeData(style: affordanceTextButton),
    elevatedButtonTheme:
        square ? ElevatedButtonThemeData(style: squareButton) : null,
    floatingActionButtonTheme: square
        ? FloatingActionButtonThemeData(
            shape: RoundedRectangleBorder(borderRadius: squareRadius))
        : null,
    popupMenuTheme: square ? PopupMenuThemeData(shape: squareBorder) : null,
    inputDecorationTheme: square
        ? InputDecorationTheme(
            // An input is a control: its resting border is `edge`, at 3:1.
            // `disabledBorder` stays the quiet divider, because a control you
            // cannot press has no boundary worth finding.
            border: squareField(t.edge),
            enabledBorder: squareField(t.edge),
            disabledBorder: squareField(t.line),
            focusedBorder: squareField(t.accent, 2),
            errorBorder: squareField(t.alert),
            focusedErrorBorder: squareField(t.alert, 2),
          )
        : null,
    dialogTheme: square ? DialogThemeData(shape: squareBorder) : null,
    bottomSheetTheme: square ? BottomSheetThemeData(shape: squareBorder) : null,
    appBarTheme: AppBarTheme(
      backgroundColor: t.base,
      foregroundColor: t.fg,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: t.fg),
      titleTextStyle: text.titleLarge,
      elevation: 0,
      // R95 — every preset ends the app bar, and the view strip inside it,
      // with the same rule. R66 did this for Studio only, at 1 px of
      // `t.hairline`, which is near-black on the calm presets and invisible.
      // 2 logical px of `fg` at low alpha reads as a chrome bar over the page
      // without becoming a decoration in its own right.
      //
      // On paper that same 22 % is 1.35:1, so the chrome had no boundary at all
      // — the page simply continued under the tab strip. Paper takes the border
      // tier at one pixel, which is also the rule a group header opens with, so
      // the two coincide instead of stacking.
      shape: Border(
        bottom: BorderSide(
            color: t.isLight ? t.line : t.fg.withValues(alpha: .22),
            width: t.isLight ? 1 : 2),
      ),
    ),
    listTileTheme: ListTileThemeData(iconColor: t.fgMuted, textColor: t.fg),
    dividerTheme: DividerThemeData(color: t.line, space: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
          s.contains(WidgetState.selected) ? t.accent : t.fgMuted),
      trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
          s.contains(WidgetState.selected)
              ? t.accent.withValues(alpha: .4)
              : t.surfaceAlt),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.all(t.accent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: t.accent,
      thumbColor: t.accent,
      inactiveTrackColor: t.line,
    ),
    // The M3 default fills the selected segment with `secondaryContainer`
    // (here a near-surface tone) — too subtle to read at a glance. Use a
    // solid accent fill + dark text for the selected segment so the
    // active choice reads unambiguously across every settings toggle.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? t.accent : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? t.base : t.fgMuted),
        iconColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? t.base : t.fgMuted),
        overlayColor: WidgetStateProperty.all(t.accent.withValues(alpha: .12)),
        // The group's own edge is a control border, so it is the border tier
        // and not the hairline: a hairline is 2.1:1 on paper (and 1.4:1 on the
        // dark grounds), so an unselected segment read as body text in a row
        // rather than as a choice you can press.
        side: WidgetStateProperty.all(BorderSide(color: t.edge)),
        shape: square
            ? WidgetStateProperty.all<OutlinedBorder?>(squareBorder)
            : null,
        textStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w600)),
      ),
    ),
    // A chip is a fill and a label decided as a pair: solid accent fill with
    // the ink the accent was defined against (`onAccent`), so the selected
    // chip stands out rather than blending into the row.
    //
    // Flutter merges ONE `labelStyle` into every state of a chip
    // (`chip.dart`, `resolveAs` over a plain Color), so a chip cannot get its
    // selected label from here: every chip in the app is built through
    // `MmFilterChip`/`MmChoiceChip`, which state both halves. A bare
    // `FilterChip` in this app paints `fg` on `accent` and, on a pale-accent
    // skin, vanishes — `test/ui/chip_label_contrast_test.dart` forbids one.
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: t.accent,
      checkmarkColor: t.onAccent,
      side: BorderSide(color: t.edge),
      labelStyle: TextStyle(color: t.fg),
      secondaryLabelStyle: TextStyle(color: t.onAccent),
      shape: squareBorder ??
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
