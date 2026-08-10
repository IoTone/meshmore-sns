# MeshmoreXR — §7 EXPANDED: making a theme an experience

**Status: PROPOSAL, 9 August 2026.** Nothing here is built. This is the document
to argue with before any of it costs build time.

---

## 0. The criticism, accepted

> *"The themes don't really differ much visually, just with colors and sounds.
> In Meshmore SNS there was vast difference in most of the themes. I think we've
> really played it very safe."*

Correct, and the record supports it. Against §7 as written:

| Axis | Specified in §7 | Built |
|---|---|---|
| Palette | yes | **yes** |
| Audio pack | yes, `MeshmoreXR-audio-haptics.md` §5 | partially — 4 of 16 events |
| Node symbology | yes ("one primitive set, nine restylings") | **2 of 9 themes**, 2026-08-09 |
| Typography | yes, a face pairing per theme | no — one face, all nine |
| Motion | yes, per theme | no — the field exists, nothing reads it |
| Posture | yes, §7.0 | no |
| **Transitions** | **NOT SPECIFIED** | no |
| **Menu rendering** | **NOT SPECIFIED** | no |

The last two rows are the important admission. Those are not things we failed to
build — they are things §7 never asked for, which is why every theme's console
fans identically and the crown drops in identically. A theme that restyles the
*content* and leaves the *behaviour* of every menu untouched will always read as
a palette, no matter how many palettes it has.

**So the fix is not more colours. It is three new per-theme axes** — transition
grammar, menu treatment, typography — plus finishing symbology and motion.

### The rule that keeps this from fragmenting the app

§8 parity is unchanged and is the constraint every proposal below is written
against: **no theme may remove information, change what an action does, or make
a control unreachable.** A theme changes how a thing arrives, what it is made
of, and what it sounds like. It never changes what it *is*.

Two supporting rules, both new:

1. **Every transition has a reduce-motion form that keeps the meaning.** Not
   "instant cut" as a fallback — a designed static equivalent. DR POP's
   slam-cut and BIOLUME's growth carry different information about how sudden
   the change was; both have to survive being frozen.
2. **No transition may exceed 400 ms.** Above that a menu stops feeling like a
   response to your hand. This is the one place where the aesthetic loses.

---

## 1. Transition grammar

The single highest-return axis, because it applies to every surface at once —
console, crown, stack, picker, thread, rack — and because we already own the
mechanism (`Unfold.kt`).

A transition is specified as four properties: **entry**, **exit**, **duration**,
and **stagger** (whether elements arrive together or in sequence).

| Theme | Entry | Exit | ms | Stagger |
|---|---|---|---|---|
| **HALO FIELD** | fade-up in place, no movement | fade-down | 180 | none — all at once |
| **NERV SPATIAL** | hard wipe left→right, hex bracket snaps closed around the panel *after* the content lands | bracket opens, content cuts | 220 | 30 ms per row, top-down |
| **AG-SYSTEMS** | slides in from the direction of travel with overshoot and settle | accelerates out the opposite side | 260 | 25 ms, leading edge first |
| **SEELE MONOLITH** | no transition. It is *there*. | it is *not there* | 0 | none |
| **DR POP** | slam-cut at full scale, then a 3-frame colour-block flash behind it | slam-cut out | 90 | none — simultaneity is the point |
| **RECON AMBER** | one-line scan wipe, top to bottom, as if drawn by a beam | reverse wipe | 200 | drawn, not staggered |
| **VECTORLINE** | strokes draw themselves — vertices appear then edges connect | edges retract to vertices, vertices wink | **290** | per-element, 20 ms |
| **BIOLUME** | grows from a point: scale 0→1 with a soft overshoot, threads reaching to neighbours | shrinks to a point and drifts | **270** | **22 ms**, bottom-up |
| **TERMINAL VOID** | types itself, character by character, with a block cursor | clears line by line, bottom-up | **230** | **30 ms**, per line |

**SEELE's zero is not laziness and must not be "fixed" later.** A monolith does
not animate; the absence *is* the identity, and it is also the only theme that
gives a motion-sensitive wearer a first-class option rather than a degraded one.

> **Correction, 9 August 2026 — these numbers were wrong when first published.**
> The durations above are PER ELEMENT, and the rule is about the whole surface.
> On the six-row bays the app actually draws, VECTORLINE totalled 420 ms,
> TERMINAL VOID 410, and BIOLUME **580** — its last row landing more than half a
> second after the surface opened. A per-element budget is not a budget. The
> three marked in bold are the corrected figures, and `RevealTest` now measures
> `duration + stagger × (rows − 1)` for all nine so this cannot recur.
>
> BIOLUME is the interesting one: it keeps its unhurried character from the
> CURVE and the overshoot rather than from wall time, because wall time is
> shared with five other rows and it does not get to spend all of it.

**Implementation note.** Seven of these nine are `scale`, `pose` or `setEnabled`
over time — all cheap, all already animatable. Only VECTORLINE's stroke-draw and
VOID's typewriter need per-element sequencing, and VOID's is nearly free because
`TextRun.setText` already re-lays out cheaply.

---

## 2. Menu treatment

How the STACK, the console fan and the crown column *look*, independent of what
they contain.

| Theme | Plate treatment | Focus | Selected |
|---|---|---|---|
| **HALO FIELD** | dim slab, bright keyline | scale 1.18 | slab brightens |
| **NERV SPATIAL** | hexagonal plate, corner brackets, a running index number per row (`01`…`06`) | brackets close in | plate inverts to alert red |
| **AG-SYSTEMS** | parallelogram, sheared 8°, livery stripe along the leading edge | stripe extends | whole plate slides 2 cm forward |
| **SEELE MONOLITH** | no plate at all — oversized type on nothing, one item per "page" | the type is simply larger | a rule appears beneath |
| **DR POP** | flat saturated block, hard offset drop-shadow block behind in a second hue, ornamental katakana in the margin | block offset doubles | colours swap |
| **RECON AMBER** | no fill, 1-unit amber rule box, corner ticks | box thickens | box fills at 20% |
| **VECTORLINE** | open wire rectangle, vertices marked | vertices brighten and grow | edges pulse once |
| **BIOLUME** | soft rounded lozenge, faint internal gradient | swells | releases a few spores |
| **TERMINAL VOID** | none — a `>` prompt and the text | inverse video block | `>` becomes `»` |

Two of these — **SEELE's one-item-per-page** and **VOID's prompt list** — change
the *shape* of a menu, not just its skin. Both are still bounded and still reach
every item, so §8 parity holds, but they need the Stack primitive to support a
paged mode. That is the one structural piece of work in this section.

---

## 3. Typography

The brief already names pairings per theme (§7.1–7.9) and we ship one face for
all nine. This is the axis with a real cost, so it is specified with the cost
attached.

| Theme | Display | Body / data | New face needed |
|---|---|---|---|
| HALO FIELD | Saira Condensed | M PLUS 1 Code | Saira Condensed |
| NERV SPATIAL | Saira (caps, compressed) | Departure Mono | Departure Mono |
| AG-SYSTEMS | Michroma | JetBrains Mono | Michroma |
| SEELE MONOLITH | Saira (oversized numerals) | M PLUS 1 Code | — reuses |
| DR POP | Michroma | M PLUS 1 Code | — reuses |
| RECON AMBER | *none* | Departure Mono | — reuses |
| VECTORLINE | Nova Square | Departure Mono | Nova Square |
| BIOLUME | Outfit | M PLUS Rounded 1c | Outfit, M PLUS Rounded |
| TERMINAL VOID | *none* | Departure Mono | — reuses |

**Six new faces for nine themes**, because the pairings deliberately overlap.

**Cost, stated honestly.** The APK is 46 MB, dominated by the CJK face already
shipped. A Latin-only subset of a display face is 40–120 KB; M PLUS Rounded 1c
with CJK coverage would be another ~1.5 MB and is the only expensive one. Total
realistic cost: **under 2 MB**, which is not the constraint. The constraint is
that `TypeRules` §7's three prohibitions (no tracking on CJK, no synthetic
weight, no uppercasing a mixed run) must be re-verified per face, and the
angular floors in `MeshmoreXR-i18n-ja.md` are measured against the *current*
face's stroke density.

**Recommendation: two faces first**, not six. Departure Mono (RECON, VOID, NERV
data) and Nova Square (VECTORLINE). Those four themes are the ones whose
identity is most carried by type, and it lets us measure the real per-face
verification cost before committing to the other four.

---

## 4. Motion budget

`Theme.Motion` exists and nothing reads it. What it should mean:

| Level | Idle animation | Event animation | Themes |
|---|---|---|---|
| **STILL** | none, ever | events only, ≤ 200 ms | HALO, SEELE, RECON, VOID |
| **MEASURED** | none | events, plus transitions ≤ 320 ms | NERV, DR POP, VECTORLINE |
| **ALIVE** | continuous, low-amplitude | everything, up to 400 ms | AG-SYSTEMS, BIOLUME |

**ALIVE is the one that needs a hard rule**, and it is not an aesthetic one:
nothing hand-anchored may idle. §5's flicker trap already establishes that
movement on a hand-mounted element is the most nauseating failure available on
this hardware, and an idling reel would be exactly that. BIOLUME breathes on the
HORIZON and the GROUND; the palm stays still.

---

## 5. Audio — the sixteen events, and what we actually fire

Asked for directly: *"we need more sound fx as notification. Even loading
screen?"* The taxonomy already exists (`MeshmoreXR-audio-haptics.md` §2) and
**we implement four of sixteen**.

| Event | Spec'd | Wired today | Notes |
|---|---|---|---|
| E1 `PROXIMATE` | yes | no | hand within 15 cm |
| E2 `HOVER` | yes | **yes** (`recognised`) | |
| E3 `COMMIT` | yes | **yes** (`opened`) | |
| E4 `DENY` | yes | **yes** (`closed`) | |
| E5 `DETENT` | yes | **yes** (`tick`) | |
| E6 `SEAT` | yes | no | a detent settling |
| E7 `NODE_FOUND` | yes | no | **new peer joins the mesh** |
| E8 `NODE_LOST` | yes | no | peer ages out |
| E9 `PACKET` | yes | no | the mesh breathing — density-capped |
| E10 `MSG_CHANNEL` | yes | **no** | ← the actual notification |
| E11 `MSG_DIRECT` | yes | **no** | ← must be distinct from E10 |
| E12 `MSG_ACK` | yes | no | our message got through |
| E13 `LINK_UP/DOWN` | yes | no | radio connected / dropped |
| E14 `TIER_CHANGE` | yes | no | mesh ↔ uplink |
| E15 `QUEUE_FLUSH` | yes | no | queued messages sent |
| E16 `CRITICAL` | yes | no | never silent in any theme |

**E10 and E11 are the gap that matters.** A message arrives and the app is
silent; the cuff lights and an ember burns, but §S4 promised four arrival
channels and audio was one of them. Wiring those two is small and is the single
most noticeable audio change available.

### 5.1 The loading screen — a new event, E0

Not in the spec, and it should be. Proposed:

> **E0 `WAKE`** — fires once, at first light, while the scene builds. The only
> event permitted to exceed 1200 ms.

The argument for it is not decoration. **The scene takes about fourteen seconds
to build on this hardware** — measured, repeatedly, this week — and for most of
that the wearer has a wordmark and no evidence anything is happening. That is
the longest unexplained silence in the product, and it is the first thing anyone
experiences.

E0 should be *progressive*, not a loop: it should audibly resolve as the scene
completes, so it ends because the app is ready rather than because it faded out.
Per theme, one line each:

| Theme | `WAKE` |
|---|---|
| HALO FIELD | a single sonar ping, its return arriving as the horizon lands |
| NERV SPATIAL | three ascending system tones, MAGI boot cadence |
| AG-SYSTEMS | an engine spooling up, resolving to idle |
| SEELE MONOLITH | one deep strike, then silence for the whole build |
| DR POP | a filtered riser |
| RECON AMBER | squelch, then a carrier tone that steadies |
| VECTORLINE | vector-scope sweep, arpeggio resolving to a root note |
| BIOLUME | a breath in, held, released as the mesh appears |
| TERMINAL VOID | teletype chatter that slows to a single carriage return |

**The link steps should get the same treatment.** `STEP 1/4 … 4/4` is already
built and already logs; four ascending tones against those four steps costs
nothing and turns the existing readout into something you can hear go wrong.

### 5.2 Ordering, if we only do some of it

1. **E10 / E11** — arrival. Promised, absent, one line each.
2. **E13 LINK_UP/DOWN** — free, the steps already exist.
3. **E0 WAKE** — the fourteen-second silence.
4. **E7 NODE_FOUND** — genuinely delightful on a live mesh, needs the density
   cap from §2.1 or a busy evening is a hailstorm.
5. Everything else.

**A caution, since it is the failure mode of exactly this kind of change:** the
audio spec's §2.1 density control is *mandatory* and is not yet implemented. E9
`PACKET` on the Portland mesh would fire several times a second. Adding events
without the cap is how a companion app becomes something people mute
permanently — and a muted app has lost all four arrival channels, not one.

---

## 6. What this costs, and the recommended order

| Piece | Size | Risk | Return |
|---|---|---|---|
| E10/E11 arrival sounds | hours | low | **high** |
| Link-step tones + E0 WAKE | hours | low | high |
| Audio density cap (§2.1) | hours | low | prevents the above becoming a hailstorm |
| Transition grammar, 3 themes | 1 day | low | **highest visual** |
| Symbology, remaining 7 | 1 day | medium — touches Horizon | high |
| Menu treatment, non-structural 7 | 1 day | low | high |
| Typography, 2 faces | 1 day | medium — per-face verification | high |
| Menu treatment, SEELE + VOID paged | 1 day | medium — Stack gains a mode | medium |
| Motion budget | half day | low | medium |
| Posture (TABLETOP, TRANSIT) | 2+ days | **high** — changes which zones exist | medium |

**Recommended: everything above the typography line, in that order.** Posture is
the one to defer past launch — it is the only item that changes what surfaces
exist, and that is not a thing to be discovering with testers in the room.
