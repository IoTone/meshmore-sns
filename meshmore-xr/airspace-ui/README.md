# AiRspace UI — reference implementation

Three.js prototype of the spatial widget library specified in
[`../AiRspace-UI.md`](../AiRspace-UI.md). This is the **design prototype and the
spec**; the production target is `com.iotj.meshmore.xr.airspace` on SceneCore.

```sh
npm install
npm run dev        # http://localhost:5180
npm run build
npm run test:settings   # settings invariants — pure logic, no browser
npm test                # settings + Playwright smoke (smoke needs `npm run serve`)
```

- **drag** — look around (stands in for head tracking)
- **hover + click** — operate a widget (stands in for gaze + pinch)
- **drag a bead** — scrub a RAIL
- **HUD** — toggle the head-locked HUD
- **EN / 日本語** — switch locale live
- **SUNLIGHT** — swap the void for a bright real-world backdrop. Black is
  transparent on an additive see-through display, so this is the honest test of
  whether a theme survives daylight.

## What's here

| Path | |
|---|---|
| `src/airspace/constants.js` | `REACH` / `READ` distances and the L7 angular floors — shared so widgets and their host cannot drift |
| `src/airspace/Rig.js` | The five zones. `Reach` rejects content, `Read` rejects controls — L5 enforced by the type system |
| `src/airspace/Billboard.js` | L1: position from the anchor, orientation from the head |
| `src/airspace/Cue.js` | L3: one call fires visual + audible + haptic together |
| `src/airspace/audio.js` | Procedural synth, zero assets, per-theme packs, density limiting |
| `src/airspace/haptics.js` | Haptic vocabulary + the honest H0 fallback |
| `src/airspace/materials.js` | The volumetric primitive set — fresnel/lambert shader, torus halos, shockwave pulses, cone carets, segmented bars, shards |
| `src/airspace/i18n.js` | EN/JA catalogs, the three-tier CJK angular floor, kinsoku shori |
| `src/airspace/widgets.js` | Pebble · Detent · Rail · Tumbler · Column · Ember |
| `src/airspace/theme.js` | The nine themes, as pure data — including each theme's `defaults` block |
| `src/airspace/settings.js` | The settings model: three classes (theme / user / a11y), resolution order, and the **clamps** |
| `src/surfaces/Horizon.js` | S1 — the always-on mesh as a volumetric shell |
| `src/surfaces/Console.js` | Settings as seven stations on a 140° arc |
| `src/surfaces/Hud.js` | The 70° HUD — compass tape, rails, protected world window |
| `src/surfaces/Vectrex.js` | The flat low-power exception |
| `scripts/pack-artifact.py` | Packs `dist/` into one self-contained ASCII-only HTML |

## Testing

`test/smoke.mjs` drives the real page in Chromium with a real WebGL context. It
asserts a clean console, that every theme and surface actually renders, and —
the part that earns its keep — **the L7 angular budget in both directions**:

- text between 1.2° and 30° of visual angle
- controls in reach space ≥ 2° (reachable) and ≤ 14° (not a wall)
- horizon motes ≤ 4.5°

That check exists because "renders non-uniform pixels" is far too weak an
assertion. It caught four real bugs during the first build, all invisible to
`vite build` and all obvious on a headset:

1. `Tumbler` called `setScalar()` on label sprites, discarding the baked
   aspect-corrected scale and blowing labels to ~1.2 m — **90° of visual angle**.
   Hence `scaleLabel()`, which scales relative to the baked size.
2. Motes used a fixed 0.055 m radius, so they subtended 9° up close and 2° far
   away. Now constant angular size (~1.6°).
3. Widgets sized their labels for `dist: 0.55` while `Console` placed them at
   0.62 m, putting every sub-label under the 1.2° readability floor. Hence
   `constants.js`.
4. `navigator.vibrate` fired before any user gesture — blocked and logged on
   every platform we target. Haptics now stay disarmed until first input.
5. Every "3D" primitive used an unshaded material, so spheres rendered as flat
   circles. Hence `materials.js` and the fresnel rim term.
6. The HUD compass pushed off-screen markers to x = 3.65 m before hiding them,
   and the test only checked an object's own `visible` flag rather than its
   ancestors' — so it measured hidden geometry.
7. HUD labels were sized for the plane distance, but the viewport *corner* is
   further away, so edge labels fell under the readability floor.
8. The artifact pack produced UTF-8 with no charset meta, and latin-1 decoding
   mangled the CJK regex ranges into `Range out of order in character class`.
   The packer now emits pure ASCII.

`test/settings.mjs` asserts the settings invariants without a browser. The one
that earns its keep: **reduce-motion must survive a switch to every one of the
nine themes**, including AG-SYSTEMS and VECTORLINE whose identity is
`motion.amount: full`. Without the clamp, a theme default silently re-enables
motion for a user who asked for none — an accessibility regression that would
surface as a nausea report, not a bug report.

`test/diag.mjs` dumps every object by subtended visual angle, largest first —
the fastest way to find the next one of these.

## Known gaps

- `Fan`, `Crown`, `Strand`, `Slate`, `Interpose` are specified in
  `../AiRspace-UI.md` but not yet implemented here.
- Interaction is mouse-driven. Gaze-dwell (L6) is implemented visually on
  `Pebble` but is not wired to a real dwell timer as the input path.
- `Rig.syncHorizon` is a stub: HORIZON is world-stable in the prototype. On
  device it must be **body**-locked and yaw-only (torso, not head).
- The audio packs implement the taxonomy's shape, not the nine distinct sound
  designs in `../MeshmoreXR-audio-haptics.md` §5.
