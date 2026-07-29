# AiRspace — Volumetric Symbology & the HUD

Companion to `AiRspace-UI.md`. Implemented in
`airspace-ui/src/airspace/materials.js` and `airspace-ui/src/surfaces/Hud.js`.

---

## 0. The FOV correction

Every angular budget in the earlier documents assumed a **45–50°** optic, taken
from the RobotARme field log. The target hardware is wider:

| | Value |
|---|---|
| Device | XREAL Aura (ex-Project Aura), Android XR, Fall 2026 |
| Optic | **70° diagonal**, optical see-through birdbath, FHD 16:9 |
| Derived | **≈ 61° horizontal × 34° vertical** |
| Launch markets | US, UK, Canada, **Japan**, South Korea |

Two consequences run through everything below.

**First: 70° is diagonal, not horizontal.** A `PerspectiveCamera` takes a
*vertical* fov, so the correct number in code is **34**, not 70. Getting this
wrong by using 70 makes every angular-size calculation in the app wrong by a
factor of two, in the direction that makes text look fine on a monitor and
illegible on the device.

**Second, and more important: more room is not more UI.** The instinct a wider
FOV creates — fill it — is exactly backwards. The extra horizontal budget goes
into a **bigger protected world window**, not more chrome. Someone wears
see-through glasses to look at the world; the moment the UI colonises the centre
they would be better served by a phone.

---

## 1. Why v1's "3D" symbology was flat

The v1 primitives were spheres, tubes and discs — geometrically 3D, and
foreshorten-proof as L2 requires. They still rendered as **flat coloured
shapes**, because they used an unshaded material. A sphere with no shading term
is a circle. Every mote, bead, slug and pebble was a 2D disc that happened to be
built from triangles.

Lighting is the obvious fix and the wrong one. Most of this symbology is
**emissive** — an additive see-through display adds light rather than reflecting
it — and a lambert-only emissive sphere still flattens at the silhouette, which
is precisely where roundness has to be legible.

What reads as volume on a glowing object is the **fresnel rim**: the edge
brightening you see on anything round and self-luminous. So every primitive gets
two terms:

- a **fixed-direction lambert body term**, so the volume shades consistently no
  matter where the head is (symbology must not flicker as you turn);
- a **view-dependent fresnel rim**, which is what makes an emissive sphere read
  round rather than as a disc.

One cheap shader, no scene lights, identical behaviour on panel and additive
substrates.

## 2. The volumetric primitive set

| Glyph | v1 (flat) | **v2 (volumetric)** | Why |
|---|---|---|---|
| **MOTE** | unshaded sphere | fresnel-shaded sphere | Reads as a lit orb, not a dot |
| **HALO** | `RingGeometry` annulus | **`TorusGeometry`** | A ring annulus is a flat disc with a hole; at a grazing angle it collapses to a line and reads as an artefact. A torus has a tube whose roundness survives any angle |
| **PULSE** | flat expanding ring | **expanding torus, tube thins as it grows** | Reads as a shockwave losing energy rather than a donut inflating |
| **SPUR** | one cylinder | **three concentric tubes** (core/glow/halo), additive | WebGL line width is ignored on most platforms; under ~1 cm radius is invisible in bright passthrough |
| **CARET** | flat triangle | **cone** | A triangle disappears edge-on; a cone points in real 3D from every angle |
| **BAR** | flat rect | **extruded box segments** | Discrete, glanceable without a scale, and legible at an angle |
| **SLAB** | flat quad | **SHARD** — bevelled box, real thickness, lit edge | The volumetric replacement for "a panel"; text insets into its front face |

**Text is the one deliberate exception.** Glyphs stay flat billboarded planes —
a bevelled letterform is a novelty, not a legibility win, and extruded CJK is
impractical at any glyph count. What must not be flat is the thing text sits
**on**: `makeShardLabel()` mounts a label on a shard so the assembly reads as an
object rather than a decal.

### 2.1 New information carried by the volume

Volume is not decoration; it bought two channels that flat symbology could not
express:

- **Hop count as an equatorial band.** A second torus encircling the mote, so
  "two hops away" is structure you see on a sphere rather than a number you read.
- **Elevation as a cone.** A caret above or below the mote pointing toward the
  node's true altitude, so "the ridge station is above you" is a fact you
  perceive rather than a figure you parse.

---

## 3. The HUD — FULL density

> **Superseded as the default.** The **MICROHUD** (§4) is now the default HUD:
> two thin bands bracketing the world window, with the left/right rails below
> folded into its bottom band. What remains here is the **FULL** density —
> an option for stationary diagnostic work, not what the user wears while
> walking around. §3.3–3.5 apply to both densities.

```
+---------------------------------------------------------------+  ^
|            C O M P A S S   T A P E  (full width, 3°)           |  |
+---------------------------------------------------------------+  |
|  tier  |                                             | channel |  |
|  link  |          W O R L D   W I N D O W            | unread  | 34°
|  batt  |          34° x 20° — NOTHING                | queue   |  |
|        |          PERSISTENT MAY ENTER HERE          |         |  |
+--------+---------------------------------------------+---------+  |
|              transcript line (only while speaking)              |  |
+---------------------------------------------------------------+  v
<---------------------------- ~61° ----------------------------->
```

Head-locked, rigid — not lazy-follow. A lazy-follow indicator reads as "a tiny
window off in the distance at a strange angle" (field, 2026-07-09).

### 3.1 The compass tape

The hero element, and the only part of this HUD that could not exist on a phone:
a bearing ribbon carrying true north **and every peer at its actual bearing**.
Glance up, see who is where, without turning your head. It is the HUD's tie back
to HORIZON — the same information, sampled into the periphery.

Markers outside the FOV are **culled, not clamped**. A clamped marker piles up at
the edge and lies about direction, which is worse than showing nothing.

### 3.2 The rest

- **Left rail** — tier, link quality, battery. Segmented volumetric BARs.
- **Right rail** — channel, peers, queue depth.
- **Bottom** — live transcript, and only while speaking. The one element allowed
  near the lower world window, because people look down less than up and a
  transcript must be readable without hunting.

### 3.3 The two rules

1. **The world window is inviolable.** 34° × 20°, dead centre, nothing
   persistent, ever. This is the rule that erodes one convenient exception at a
   time, so the prototype has an automated test asserting it
   (`npm test` → "HUD keeps the 34°×20° world window clear").
2. **The HUD is never the only channel.** It dims to zero and every piece of
   information remains reachable elsewhere.

### 3.4 Sizing for the worst case

A label sized for the HUD plane distance shrinks as it slides toward the edge of
the tape, because the **corner of the viewport is further away than the centre**.
Sizing for the centre distance put edge labels under the readability floor. Every
HUD label is therefore sized for `sqrt(D² + halfH² + halfV²)` — the far corner.
Floors are floors, not targets, so the centre labels being slightly larger than
strictly necessary is correct, not waste.

### 3.5 In the Vectrex theme there is no HUD

TERMINAL VOID drops the volumetric layer entirely, and that includes this. Its
flat vector overlay **is** the HUD. A low-power theme that renders a separate
volumetric HUD on top of its flat plane would be lying about being low-power.

---

## 4. MICROHUD geometry

Product-level spec is in `MeshmoreXR-design-brief.md` § MICROHUD. This is the
arithmetic.

Everything is expressed in **degrees of visual angle from centre**, which is
device-independent; the metre figures are that angle evaluated at the HUD plane
`D = 1.05 m` and are provided only for implementation.

| Band | Elevation | Height | At D = 1.05 m |
|---|---|---|---|
| FOV edge | ±17.0° | — | ±0.321 m |
| **Safe area** (8% inset) | ±15.5° | — | ±0.291 m |
| **Compass ribbon** | +11.9° … +15.1° | 3.2° | +0.221 … +0.283 m |
| **World window** | ±10.0° | 20.0° | ±0.185 m |
| **Node stats** | −12.2° … −14.8° | 2.6° | −0.227 … −0.277 m |
| Horizontal safe | ±28.0° | — | ±0.558 m |

Vertical budget check: `15.1 < 15.5` (ribbon inside safe area) and `11.9 > 10.0`
(ribbon outside the world window). Both bands clear both constraints, with
0.4° and 1.9° of margin respectively. Those margins are small on purpose — the
bands are as far out as they can safely go.

### 4.1 The mapping, and a bug this spec exposed

Bearing → screen offset must be

```
x = D * tan(bearing − headYaw)
```

**not** the linear-in-angle form `x = (Δ / halfFovH) * halfWidth`.

The two agree at 0° and at the FOV edge by construction, and diverge in between:

| Δ off-axis | linear-in-angle | tangent (correct) | error |
|---|---|---|---|
| 5° | 0.101 m | 0.092 m | +10% |
| 15° | 0.304 m | 0.281 m | +8% |
| 25° | 0.507 m | 0.490 m | +3.5% |

A marker misplaced by 8–10% of half-width does not sit over its node, which
destroys the one property that makes a 1:1 ribbon worth having.

**`airspace-ui/src/surfaces/Hud.js` currently uses the linear form** — see
`place()`. That is a real defect in the prototype, found by writing this spec
rather than by running it, because "the marker is roughly in the right place"
passes every test we have. Fixing it requires a companion assertion: project a
node's world position with the camera matrix and assert the ribbon marker lands
within ~0.3° of the same screen x.

### 4.2 Tick and label budget

Visible bearing span within the horizontal safe area is `2 × 28° = 56°`.

| Element | Interval | Visible at once |
|---|---|---|
| minor tick | 5° | 11–12 |
| major tick + 3-digit bearing | 15° | 3–4 |
| compass point letter | 45° | **1–2, never 0** |

The "never 0" guarantee is why the eight-point scheme is mandatory: at 90°
spacing (N/E/S/W only) a 56° window contains no lettered reference roughly 38%
of the time, and the ribbon degenerates into unlabelled ticks.

Marker size ~1.0–1.5° — above the 0.6° target floor, below the 4.5° horizon-mote
ceiling. Distance labels at the 1.2° Latin floor (1.8° if ever rendered in
kanji), capped at three on screen.

### 4.3 Test hooks this needs

The existing world-window assertion already covers the bands (they are outside
±10° by construction). Three more are needed and are **not yet written**:

1. **Ribbon alignment** — project a known node through the camera and assert the
   marker's screen x is within 0.3° (this is what would have caught §4.1).
2. **Label budget** — assert ≤ 3 distance labels are visible regardless of node
   count, so density degrades by dropping labels rather than by overlapping.
3. **Compass-point coverage** — sweep yaw through 360° in 5° steps and assert at
   least one lettered compass point is visible at every step.

---

## 5. Verifying it

`npm test` drives the real page in Chromium with a real WebGL context. The checks
that earn their keep are the ones with a **numeric ceiling and floor**, because
"it rendered something" passes for almost any defect:

- text within its locale's angular band (§ `MeshmoreXR-i18n-ja.md`)
- reach-space controls ≥ 2° and ≤ 14°
- horizon motes ≤ 4.5°
- the world window empty
- the Japanese face actually resolved (tofu throws nothing)

The prototype **letterboxes to 16:9**. A browser window is whatever shape it was
dragged to, and rendering the device's vertical FOV into a wider window silently
widens the horizontal FOV — which is what pushed the HUD rails, correctly sized
for 61°, off the edge of the screen. Letterboxing makes what you see what the
optic shows, and makes the world-window claim verifiable rather than
aspirational.
