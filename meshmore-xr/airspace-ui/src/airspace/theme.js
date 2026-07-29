// AiRspace UI — the nine themes, as pure data.
//
// THE ONE ARCHITECTURAL RULE: no widget knows a colour, a font, or a sound.
// Widgets take a theme token and a Cue sink. This is what makes nine themes
// cost styling instead of nine implementations.
//
// `substrate` drives contrast physics on an additive see-through display:
//   panel    — renders an opaque backing; survives sunlight
//   additive — emissive only; black is transparent; washes out in daylight
//   hybrid   — additive marks over selective panel backings
//
// `render: 'flat'` is the Vectrex exception (see AiRspace-UI.md §5).

export const THEMES = [
  {
    key: 'halo', name: 'HALO FIELD', substrate: 'hybrid', render: 'volumetric',
    ground: 0x070b10, panel: 0x101722, accent: 0x35e0f0, alt: 0x7cff6b,
    warn: 0xffb020, alert: 0xff3b6b, text: 0xdde7ef,
    pack: 'Sonar', wave: 'sine', root: 720, scale: [0, 2, 4, 7, 9],
    tts: 'calm, natural, rate 1.0',
    note: 'Recommended default. Three luminance levels, never more. Recency-fade is the primary channel.',
    // The calm default: standard everything, nothing turned up.
    defaults: {
      'audio.pack': 'Sonar', 'audio.enabled': true, 'audio.packetDensity': 'sparse',
      'motion.amount': 'minimal', 'hud.density': 'micro', 'hud.dim': 70,
      'reel.depth': 12, 'reel.grouping': 'mixed', 'cuff.autoClear': false,
      'terrain.render': 'mesh', 'terrain.exaggeration': 2.5, 'tts.rate': 1.0,
    },
  },
  {
    key: 'nerv', name: 'NERV SPATIAL', substrate: 'panel', render: 'volumetric',
    ground: 0x0a0e1a, panel: 0x121826, accent: 0xff7a00, alt: 0x9cff00,
    warn: 0xffc400, alert: 0xe01b24, text: 0xe6ecf5,
    pack: 'Mission Control', wave: 'square', root: 880, scale: [0, 3, 5, 7, 10],
    tts: 'clipped, procedural, rate 1.15',
    note: 'Density lives on panels, never in open space. Critical inverts the palette to red.',
    // Density is the aesthetic: dense packet audio, full HUD, fast voice.
    defaults: {
      'audio.pack': 'Mission Control', 'audio.enabled': true, 'audio.packetDensity': 'dense',
      'motion.amount': 'standard', 'hud.density': 'full', 'hud.dim': 85,
      'reel.depth': 18, 'reel.grouping': 'perChannel', 'cuff.autoClear': false,
      'terrain.render': 'mesh', 'terrain.exaggeration': 2.5, 'tts.rate': 1.15,
    },
  },
  {
    key: 'aghud', name: 'AG-SYSTEMS', substrate: 'hybrid', render: 'volumetric',
    ground: 0x05060b, panel: 0x10131f, accent: 0x22d3ee, alt: 0xff2d78,
    warn: 0xffd23f, alert: 0xff2d78, text: 0xddf6ff,
    pack: 'Velocity', wave: 'sawtooth', root: 660, scale: [0, 2, 5, 7, 11],
    tts: 'smooth, announcer-adjacent, rate 1.05',
    note: 'Motion carries the identity — so reduce-motion must be designed, not bolted on.',
    // Motion carries the identity — the only theme that defaults to 'full'.
    defaults: {
      'audio.pack': 'Velocity', 'audio.enabled': true, 'audio.packetDensity': 'standard',
      'motion.amount': 'full', 'hud.density': 'micro', 'hud.dim': 80,
      'reel.depth': 12, 'reel.grouping': 'mixed', 'cuff.autoClear': false,
      'terrain.render': 'mesh', 'terrain.exaggeration': 3.0, 'tts.rate': 1.05,
    },
  },
  {
    key: 'seele', name: 'SEELE MONOLITH', substrate: 'panel', render: 'volumetric',
    ground: 0x000000, panel: 0x0e0e0c, accent: 0xede6d6, alt: 0x9a958a,
    warn: 0x9a958a, alert: 0xc8102e, text: 0xede6d6,
    pack: 'Tribunal', wave: 'sine', root: 60, scale: [0, 5],
    tts: 'slow, grave, rate 0.85, pitch −15%',
    note: 'Near-silent by design: hover, detent and packet events are ACTUALLY silent. The parity benchmark.',
    silent: ['PROXIMATE', 'HOVER', 'DETENT', 'PACKET'],
    // Near-silence and no motion, by design. Fewest reel slots in the set:
    // this theme's thesis is that one thing at a time is enough.
    defaults: {
      'audio.pack': 'Tribunal', 'audio.enabled': true, 'audio.packetDensity': 'off',
      'motion.amount': 'none', 'hud.density': 'micro', 'hud.dim': 100,
      'reel.depth': 5, 'reel.grouping': 'mixed', 'cuff.autoClear': false,
      'terrain.render': 'mesh', 'terrain.exaggeration': 2.0, 'tts.rate': 0.85,
    },
  },
  {
    key: 'drpop', name: 'DR POP', substrate: 'panel', render: 'volumetric',
    ground: 0x101014, panel: 0x1c1c24, accent: 0xff2e88, alt: 0xd7ff00,
    warn: 0x00e5ff, alert: 0xff2e88, text: 0xf2f0e6,
    pack: 'Pure Phase', wave: 'square', root: 440, scale: [0, 3, 5, 6, 7, 10],
    tts: 'bright, formant-shifted, rate 1.1',
    note: 'Loudest pack — ships at −6 dB. Colour is decoration and may never be the sole carrier of state.',
    // Loudest pack in the set, so packet audio ships dense but the master
    // normalization pulls it back 6 dB (see audio spec 5.5).
    defaults: {
      'audio.pack': 'Pure Phase', 'audio.enabled': true, 'audio.packetDensity': 'dense',
      'motion.amount': 'standard', 'hud.density': 'micro', 'hud.dim': 75,
      'reel.depth': 12, 'reel.grouping': 'perChannel', 'cuff.autoClear': false,
      'terrain.render': 'mesh', 'terrain.exaggeration': 2.5, 'tts.rate': 1.1,
    },
  },
  {
    key: 'recon', name: 'RECON AMBER', substrate: 'hybrid', render: 'volumetric',
    ground: 0x000000, panel: 0x0a0a07, accent: 0xffb000, alt: 0x6e4e00,
    warn: 0xffb000, alert: 0xb3231f, text: 0xffb000,
    pack: 'Codec', wave: 'square', root: 1000, scale: [0, 7],
    tts: 'flat, band-limited 300–3400 Hz, rate 1.0',
    note: 'One hue at four luminance steps — automatically the most colour-blind-safe theme of the nine.',
    // Night operations: dimmest HUD, contours not mesh, sparse audio.
    // Exaggeration goes UP because contour lines need vertical separation to
    // stay readable where a shaded mesh would have carried the relief.
    defaults: {
      'audio.pack': 'Codec', 'audio.enabled': true, 'audio.packetDensity': 'sparse',
      'motion.amount': 'minimal', 'hud.density': 'micro', 'hud.dim': 40,
      'reel.depth': 10, 'reel.grouping': 'mixed', 'cuff.autoClear': false,
      'terrain.render': 'contour', 'terrain.exaggeration': 3.0, 'tts.rate': 1.0,
    },
  },
  {
    key: 'vector', name: 'VECTORLINE', substrate: 'additive', render: 'volumetric',
    ground: 0x000000, panel: 0x05070a, accent: 0x00ffc8, alt: 0xb14bff,
    warn: 0xffe066, alert: 0xff3d00, text: 0xdffff6,
    pack: 'Arcade', wave: 'triangle', root: 523, scale: [0, 2, 4, 7, 9, 11],
    tts: 'clean synthetic, rate 1.0',
    note: 'Every interaction is a note quantized to a scale; the scale shifts with mesh health.',
    // The mesh is a generative composition, so packet audio is the point.
    defaults: {
      'audio.pack': 'Arcade', 'audio.enabled': true, 'audio.packetDensity': 'dense',
      'motion.amount': 'full', 'hud.density': 'micro', 'hud.dim': 90,
      'reel.depth': 12, 'reel.grouping': 'mixed', 'cuff.autoClear': false,
      'terrain.render': 'mesh', 'terrain.exaggeration': 3.5, 'tts.rate': 1.0,
    },
  },
  {
    key: 'biolume', name: 'BIOLUME', substrate: 'additive', render: 'volumetric',
    ground: 0x04100e, panel: 0x0b1f1a, accent: 0x5fffc2, alt: 0x9b6bff,
    warn: 0xffd08a, alert: 0xff6b5f, text: 0xd8fff0,
    pack: 'Bloom', wave: 'sine', root: 392, scale: [0, 2, 4, 7, 9],
    tts: 'warm, unhurried, close-mic’d, rate 0.95',
    note: 'Generative: no two events sound identical, but each class holds a stable timbral centre.',
    // Least fatiguing pack, meant for all-day wear — hence autoClear on, the
    // only theme where it is. Nothing is ever perfectly still.
    defaults: {
      'audio.pack': 'Bloom', 'audio.enabled': true, 'audio.packetDensity': 'standard',
      'motion.amount': 'full', 'hud.density': 'micro', 'hud.dim': 60,
      'reel.depth': 12, 'reel.grouping': 'mixed', 'cuff.autoClear': true,
      'terrain.render': 'mesh', 'terrain.exaggeration': 2.5, 'tts.rate': 0.95,
    },
  },
  {
    key: 'void', name: 'TERMINAL VOID', substrate: 'additive', render: 'flat',
    ground: 0x000000, panel: 0x020402, accent: 0x33ff66, alt: 0x0a3d17,
    warn: 0xb8ff33, alert: 0xff4444, text: 0x33ff66,
    pack: 'Teletype', wave: 'square', root: 1200, scale: [0],
    tts: 'classic formant synthesis (DECtalk reference), rate 1.0',
    note: 'THE VECTREX EXCEPTION — the volumetric layer is dropped entirely for a flat vector overlay.',
    // The Vectrex exception: the flat overlay IS the HUD, so hud.density is
    // 'off'. Text is cheap, so this theme carries the deepest reel in the set.
    defaults: {
      'audio.pack': 'Teletype', 'audio.enabled': true, 'audio.packetDensity': 'standard',
      'motion.amount': 'minimal', 'hud.density': 'off', 'hud.dim': 50,
      'reel.depth': 24, 'reel.grouping': 'mixed', 'cuff.autoClear': false,
      'terrain.render': 'contour', 'terrain.exaggeration': 3.0, 'tts.rate': 1.0,
    },
  },
];

// Every theme must supply every THEME-class key in settings.js — asserted by
// test/smoke.mjs, because a missing default silently falls back to the global
// one and the theme quietly loses part of its identity.
export const byKey = (k) => THEMES.find((t) => t.key === k) || THEMES[0];
