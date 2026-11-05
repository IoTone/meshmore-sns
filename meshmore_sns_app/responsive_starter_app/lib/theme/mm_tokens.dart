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
/// R115 adds an eighth, [MmThemePreset.studioLight]: the same tool
/// language on paper, because every other preset is dark and a phone in
/// daylight needs a light one. Ink is near-black, the ground is warm
/// paper, and the accent is a vermilion that carries selection and
/// emphasis without relying on saturation alone.
enum MmThemePreset {
  nerv,
  agHud,
  hyperlocal,
  seele,
  drPop,
  recon,
  studio,
  studioLight,
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
        MmThemePreset.studioLight => 'Studio Light — paper · square',
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
        // R115 — same reason: a light skin changes colour, not the cue
        // set. The calm pack is the one that fits a paper ground.
        MmThemePreset.studioLight => 'hyperlocal',
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
  })  : _link = link,
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

  Color get link => _link ?? const Color(0xFF3DDC84);

  final Color? _raised;
  final Color? _selected;
  final Color? _hairline;
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
    fgDisabled: Color(0xFF6A6A6A),
    onAlert: Color(0xFF141414),
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
  ),
  MmThemePreset.nerv: MmTokens(
    base: Color(0xFF0A0E1A),
    surface: Color(0xFF121826),
    surfaceAlt: Color(0xFF1B2436),
    line: Color(0xFF243049),
    fg: Color(0xFFE6ECF5),
    fgMuted: Color(0xFFA6B2C8),
    accent: Color(0xFFFF7A00),
    alert: Color(0xFFE6005C),
    ok: Color(0xFF9CFF00),
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
  ),
  MmThemePreset.drPop: MmTokens(
    base: Color(0xFF101014),
    surface: Color(0xFF1C1C24),
    surfaceAlt: Color(0xFF24242E),
    line: Color(0xFF33333F),
    fg: Color(0xFFF2F0E6),
    fgMuted: Color(0xFFB0B0C0),
    accent: Color(0xFFFF2E88),
    alert: Color(0xFFFF2E88),
    ok: Color(0xFFD7FF00),
  ),
  MmThemePreset.recon: MmTokens(
    base: Color(0xFF000000),
    surface: Color(0xFF0A0A07),
    surfaceAlt: Color(0xFF141414),
    line: Color(0xFF6E4E00),
    fg: Color(0xFFFFB000),
    fgMuted: Color(0xFFC79433),
    accent: Color(0xFFFFB000),
    alert: Color(0xFFB3231F),
    ok: Color(0xFFFFB000),
  ),
  // R115 — Studio Light: the tool language on paper. The stack runs from the
  // brightest step (the page) down to the selected state, because on a light
  // ground a container is *cut into* the page rather than raised out of it;
  // that also keeps the four steps monotonic, which is what makes a panel
  // read as a panel instead of a smudge.
  //
  // The ground is a warm paper rather than pure white: a white page at full
  // brightness is the one surface a phone cannot dim, and every glyph on it
  // sits in glare. The accent is a vermilion red that carries selection and
  // emphasis and still reads as text on every layer (4.97:1 on the darkest).
  //
  // `link` is supplied because the shared live-link green (#3DDC84) is 1.7:1
  // on paper: a link state is still green in this skin, just a green a light
  // ground can carry. `alert` is a deeper red than the accent so the two are
  // never mistaken for each other, and both carry an icon and a word.
  MmThemePreset.studioLight: MmTokens(
    base: Color(0xFFFBFAF6),
    surface: Color(0xFFF2EFE8),
    surfaceAlt: Color(0xFFE8E2D3),
    line: Color(0xFF8A8474),
    fg: Color(0xFF16181C),
    fgMuted: Color(0xFF4E525A),
    accent: Color(0xFFA81B0B),
    alert: Color(0xFF8C1018),
    ok: Color(0xFF175B33),
    raised: Color(0xFFE8E2D3),
    selected: Color(0xFFDAD3BF),
    hairline: Color(0xFFA9A290),
    onAccent: Color(0xFFFFFFFF),
    fgDisabled: Color(0xFF8E9196),
    onAlert: Color(0xFFFFFFFF),
    link: Color(0xFF16603A),
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
  final double controlCorner =
      square ? kSquareRadius : ((shape?.cornerSize ?? 8).clamp(2, 8)).toDouble();
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
      (Set<WidgetState> states) => states.contains(WidgetState.disabled)
          ? t.fgMuted
          : t.fg,
    ),
  );
  OutlineInputBorder squareField(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: squareRadius,
      borderSide: BorderSide(color: c, width: w));
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
    error: t.alert,
    onError: t.onAlert,
    errorContainer: t.alert,
    onErrorContainer: t.onAlert,
    outline: t.line,
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
      // R66: a square (Studio) card gets a hairline edge, since
      // surface on base is only ~1.13:1 and has no visible boundary.
      // Null side / unchanged shape for every other preset.
      shape: square
          ? RoundedRectangleBorder(
              side: BorderSide(color: t.hairline, width: shape!.hairlineWidth),
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
            border: squareField(t.line),
            enabledBorder: squareField(t.line),
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
      shape: Border(
        bottom: BorderSide(
            color: t.fg.withValues(alpha: .22), width: 2),
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
        side: WidgetStateProperty.all(BorderSide(color: t.hairline)),
        shape: square
            ? WidgetStateProperty.all<OutlinedBorder?>(squareBorder)
            : null,
        textStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w600)),
      ),
    ),
    // ChoiceChip (chat channel selector): same idea — solid accent fill
    // with dark label + checkmark when selected, so the active chip
    // stands out rather than blending into the unselected row.
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: t.accent,
      checkmarkColor: t.base,
      side: BorderSide(color: t.line),
      labelStyle: TextStyle(color: t.fg),
      secondaryLabelStyle: TextStyle(color: t.base),
      shape: squareBorder ??
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
