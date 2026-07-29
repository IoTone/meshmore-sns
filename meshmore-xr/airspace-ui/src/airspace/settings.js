// AiRspace UI — the settings model.
//
// Three classes of setting, and the distinction is load-bearing:
//
//   THEME  the theme owns the default; it is part of the theme's identity
//          (audio pack, motion amount, terrain render mode, reel depth).
//          The user may override, and the override survives a theme switch.
//
//   USER   the theme NEVER touches it (handedness, locale, TTS on/off).
//          These describe the person, not the look.
//
//   A11Y   the theme may never override it, AND it CLAMPS other settings.
//          This is the one that would otherwise be a serious bug: a user
//          enables reduce-motion, switches to a motion-heavy theme, and the
//          theme default silently turns motion back on. Clamps run last and
//          nothing can outrank them.
//
// Resolution order (later wins), with one exception:
//
//   globalDefault  ->  theme default  ->  user pin  ->  a11y pin  ->  CLAMPS
//                                                                     ^^^^^^
//   Clamps are applied unconditionally at the end. They are not a layer that
//   can be overridden; they are an invariant.

export const CLASS = { THEME: 'theme', USER: 'user', A11Y: 'a11y' };

// station: which CONSOLE station presents it. widget: which AiRspace widget.
export const SCHEMA = {
  // ---- THEME-owned ---------------------------------------------------------
  'audio.pack': { cls: CLASS.THEME, type: 'enum', values: ['Sonar', 'Mission Control', 'Velocity', 'Tribunal', 'Pure Phase', 'Codec', 'Arcade', 'Bloom', 'Teletype'], station: 'voice', widget: 'Tumbler' },
  'audio.enabled': { cls: CLASS.THEME, type: 'bool', def: true, station: 'voice', widget: 'Detent' },
  'audio.packetDensity': { cls: CLASS.THEME, type: 'enum', values: ['off', 'sparse', 'standard', 'dense'], def: 'standard', station: 'voice', widget: 'Tumbler' },
  'motion.amount': { cls: CLASS.THEME, type: 'enum', values: ['none', 'minimal', 'standard', 'full'], def: 'standard', station: 'access', widget: 'Tumbler' },
  'hud.density': { cls: CLASS.THEME, type: 'enum', values: ['off', 'micro', 'full'], def: 'micro', station: 'theme', widget: 'Tumbler' },
  'hud.dim': { cls: CLASS.THEME, type: 'range', min: 0, max: 100, step: 10, def: 70, station: 'theme', widget: 'Rail' },
  'reel.depth': { cls: CLASS.THEME, type: 'range', min: 5, max: 24, step: 1, def: 12, station: 'voice', widget: 'Rail' },
  'reel.grouping': { cls: CLASS.THEME, type: 'enum', values: ['mixed', 'perChannel'], def: 'mixed', station: 'voice', widget: 'Tumbler' },
  'cuff.autoClear': { cls: CLASS.THEME, type: 'bool', def: false, station: 'voice', widget: 'Detent' },
  'terrain.render': { cls: CLASS.THEME, type: 'enum', values: ['mesh', 'contour'], def: 'mesh', station: 'theme', widget: 'Tumbler' },
  'terrain.exaggeration': { cls: CLASS.THEME, type: 'range', min: 1, max: 5, step: 0.5, def: 2.5, station: 'theme', widget: 'Rail' },
  'tts.rate': { cls: CLASS.THEME, type: 'range', min: 0.6, max: 1.6, step: 0.05, def: 1.0, station: 'voice', widget: 'Rail' },

  // ---- USER-owned (theme never touches) -----------------------------------
  'hand.system': { cls: CLASS.USER, type: 'enum', values: ['right', 'left'], def: 'right', station: 'access', widget: 'Tumbler' },
  'locale': { cls: CLASS.USER, type: 'enum', values: ['en', 'ja'], def: 'en', station: 'access', widget: 'Tumbler' },
  'compass.cardinalScript': { cls: CLASS.USER, type: 'enum', values: ['latin', 'kanji'], def: 'latin', station: 'access', widget: 'Tumbler' },
  'tts.enabled': { cls: CLASS.USER, type: 'bool', def: false, station: 'voice', widget: 'Detent' },
  'audio.masterGain': { cls: CLASS.USER, type: 'range', min: 0, max: 100, step: 5, def: 60, station: 'voice', widget: 'Rail' },
  'haptic.scale': { cls: CLASS.USER, type: 'range', min: 0, max: 200, step: 10, def: 100, station: 'access', widget: 'Rail' },
  'gesture.reelScroll': { cls: CLASS.USER, type: 'enum', values: ['thumbIndex', 'airSwipe', 'dwell'], def: 'thumbIndex', station: 'access', widget: 'Tumbler' },
  'mic.pttOnly': { cls: CLASS.USER, type: 'bool', def: true, station: 'voice', widget: 'Detent' },
  'uplink.autoSync': { cls: CLASS.USER, type: 'bool', def: true, station: 'uplink', widget: 'Detent' },

  // ---- A11Y-owned (theme may never override; these CLAMP) -----------------
  'a11y.reduceMotion': { cls: CLASS.A11Y, type: 'bool', def: false, station: 'access', widget: 'Detent' },
  'a11y.textScale': { cls: CLASS.A11Y, type: 'range', min: 1, max: 2, step: 0.1, def: 1.0, station: 'access', widget: 'Rail' },
  'a11y.seatedArc': { cls: CLASS.A11Y, type: 'enum', values: ['360', '120'], def: '360', station: 'access', widget: 'Tumbler' },
  'a11y.visualHapticOnly': { cls: CLASS.A11Y, type: 'bool', def: false, station: 'access', widget: 'Detent' },
  'a11y.dwellOnly': { cls: CLASS.A11Y, type: 'bool', def: false, station: 'access', widget: 'Detent' },
};

// Clamps: an accessibility choice forcing other settings, applied LAST.
//
// These are the reason the three-class split exists. Without them, "theme sets
// defaults" and "user needs reduced motion" are in direct conflict and the
// theme wins by accident of ordering.
export const CLAMPS = [
  {
    reason: 'reduce-motion is an accessibility guarantee, not a theme preference',
    when: (s) => s['a11y.reduceMotion'] === true,
    set: { 'motion.amount': 'none', 'audio.packetDensity': (v) => (v === 'dense' ? 'standard' : v) },
  },
  {
    reason: 'visual+haptic only means no audio, whatever the theme pack is',
    when: (s) => s['a11y.visualHapticOnly'] === true,
    set: { 'audio.enabled': false },
  },
  {
    reason: 'dwell-only users cannot perform the thumb-along-index gesture',
    when: (s) => s['a11y.dwellOnly'] === true,
    set: { 'gesture.reelScroll': 'dwell' },
  },
  {
    reason: 'the seated 120 arc cannot reach a 360 horizon; HUD must carry more',
    when: (s) => s['a11y.seatedArc'] === '120',
    set: { 'hud.density': (v) => (v === 'off' ? 'micro' : v) },
  },
];

export const themeOwnedKeys = () =>
  Object.entries(SCHEMA).filter(([, d]) => d.cls === CLASS.THEME).map(([k]) => k);

/**
 * Resolve the effective settings.
 * @param theme    a THEMES entry (its `.defaults` supplies theme-class values)
 * @param userPins keys the user has explicitly chosen — survive theme switches
 */
export function resolve(theme, userPins = {}) {
  const out = {};

  // 1. global defaults from the schema
  for (const [k, d] of Object.entries(SCHEMA)) if ('def' in d) out[k] = d.def;

  // 2. theme defaults — THEME-class keys only. A theme that tries to set a
  //    user- or a11y-class key is a bug, and we refuse it rather than honour it.
  for (const [k, v] of Object.entries(theme.defaults || {})) {
    const d = SCHEMA[k];
    if (!d) continue;
    if (d.cls !== CLASS.THEME) continue;
    out[k] = v;
  }

  // 3. user pins — these are why switching theme does not wipe your choices
  for (const [k, v] of Object.entries(userPins)) {
    if (SCHEMA[k]) out[k] = v;
  }

  // 4. clamps, unconditional and last
  for (const c of CLAMPS) {
    if (!c.when(out)) continue;
    for (const [k, v] of Object.entries(c.set)) {
      out[k] = typeof v === 'function' ? v(out[k]) : v;
    }
  }
  return out;
}

/** Which theme-class keys a theme fails to specify. Should always be empty. */
export function missingThemeDefaults(theme) {
  const have = new Set(Object.keys(theme.defaults || {}));
  return themeOwnedKeys().filter((k) => !have.has(k));
}

/** Keys a theme illegally tries to own. Should always be empty. */
export function illegalThemeKeys(theme) {
  return Object.keys(theme.defaults || {}).filter(
    (k) => SCHEMA[k] && SCHEMA[k].cls !== CLASS.THEME
  );
}
