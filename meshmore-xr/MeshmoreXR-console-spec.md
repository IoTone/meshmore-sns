# MeshmoreXR — THE CONSOLE

**Settings as a projected hologram. Spec only; nothing built.**
Written 2026-08-02. Extends `MeshmoreXR-design-brief.md` §9 (settings) and §5
(surfaces). Supersedes nothing — §9.6 THE RACK becomes a *bay* of this surface
rather than a destination of its own.

---

## 1. What this is, and the problem it solves

MeshmoreXR can currently configure the radio and nothing else. There is no
profile, no channel editing, no app settings, and the diagnostics log is an
unhoused panel floating in the room. Meshmore SNS has all of it, organised into
five hub entries, and a user who knows the phone app should find the same five
things in the same order on the glasses.

The naive port is a settings list. §6.3 of the brief bans that outright, and
§9.3 already commits to the alternative — *"enums are TUMBLERs, ranges are
RAILs, booleans are DETENTs. Nothing is a row in a list."* What §9.3 never
specified is **how you choose between stations**, and that is what this document
is: the selector, plus the discipline the bays behind it inherit.

---

## 2. Why a hologram, and why it is not a costume

The brief's §1.3 states the display constraint that governs everything:

> On see-through glasses you cannot draw dark — you can only add light.

Every conventional UI metaphor fights that. A *panel* wants an opaque ground it
cannot have. A *card* wants a shadow it cannot cast. A *sheet* wants to occlude
what is behind it, and on additive optics it simply cannot. We have already paid
for this twice — the rack had to be redrawn as edges and light (§9.6.2), and the
tier R text surfaces are transparent-ground by construction.

A Star Wars hologram is the one visual language in popular culture that is
**already** what this hardware does: self-luminous, semi-transparent, no black,
edge-lit, floating free of any surface, and unmistakably *projected from
somewhere* rather than pasted onto the view.

> **This is not a theme applied to a menu. It is the display's native idiom,
> and the reference happens to be famous.**

That distinction matters for what follows: every holographic device specified
below has to earn its place by doing a job. The ones that only look good are
listed in §9 as rejected.

---

## 3. Parity with Meshmore SNS — the five plates

SNS's settings hub, verbatim from `app_en.arb`, mapped to this surface and to
the brief's existing CONSOLE stations (§9.3):

| SNS hub entry | Plate mark | Bay contents | Brief station |
|---|---|---|---|
| Device configuration | **mast + arcs** | THE RACK, unchanged | RADIO (§9.5/9.6) |
| App settings | **three rails** | connection, language, notifications, permissions, data, background | UPLINK + part of VOICE |
| Profile & personalization | **swatch ring** | theme preset, type size, audio master + alerts, a11y | THEME + ACCESS |
| Channels | **hash** | slots · name + PSK · #hashtag · active | *new station* |
| Diagnostics & connect | **trace + link arc** | connect a radio · frame log · M6 capture | *new station* |

The marks mirror SNS's own icons — `router_outlined`, `tune`, `palette_outlined`,
`tag`, `bluetooth_searching` — redrawn as contours in the app's register, through
the same `PathParser` pipeline as `AslIcon`. Parity of *symbol*, not of artwork.

Two are worth calling out. **Three rails** for APP is not a borrowed slider icon;
RAIL is already this app's word for a range control (§9.3), so the mark says
what the bay contains. **The swatch ring** for PROFILE renders the *current
theme's* palette, so it previews the thing its bay changes and is the one mark
that is not static.

Three notes on the mapping:

- **Two plates span more than one brief station.** APP and PROFILE each cover
  two. That is fine and expected — SNS groups by *what the user came to do*, the
  brief grouped by *what the setting is*. The invariant from §9.3 still holds
  and should still be asserted by test: **every setting has exactly one home**,
  and the test now walks plates rather than stations.
- **The words are SNS's words, exactly.** Because only one label is ever
  visible (§3.1), the readout can carry the full hub string —
  "Diagnostics & connect / Connect a radio · frame log · M6 capture" — instead
  of a one-word abbreviation. Icon-first *restores* wording parity that a
  text-first stack would have had to sacrifice.
- **DIAG contains "connect a radio", which is S2 LINK.** Building this surface
  therefore delivers a real piece of the P2 phase flagged as unfinished in
  `MeshmoreXR-course-correction.md` §1. Worth knowing when sequencing it.

---

## 3.1 Icons carry identity; words carry detail

The rule this surface is built on, and it is a general one:

> **The resting state must carry identity. Whatever carries it does not have to
> be a word.**

This is the reconciliation of two decisions that otherwise look contradictory.
The dock's pips were made to show their names permanently on 2026-08-02, because
seven identical rings carry *no* identity at rest — position was the only thing
distinguishing them, and that is a memory test. The console's plates carry a
distinct mark each, so identity is already present at rest and the word is free
to wait for focus.

The mechanism is proven. Focus-revealed captions were broken for three rounds of
debugging and are now correct: panels honour their pixel raster, billboard in
yaw and pitch, and brighten on focus. What follows is a design consequence of
that fix rather than a hope.

**What icon-first buys, concretely:**

| | Text-first | Icon-first |
|---|---|---|
| Plate width | 14.4° (one word at 1.2°) | **3.0°** |
| Stack silhouette | a slab across the view | a narrow column |
| Label wording | abbreviated to one word | **the full SNS string** |
| Labels visible at once | five | one |

The second row is the one that matters most. §2.1 rule 2 says *more room does
not mean more UI, it means a bigger protected world window* — and a settings
menu that occupies 14° of arc per row is the exact failure that rule names. A
column of marks leaves the room visible behind it, which on additive optics it
was going to be anyway.

**Where the word appears.** In a **fixed readout slot at the base of the cone**,
by the emitter — not attached to each plate. Two reasons: in a vertical fan,
per-plate labels sit on a common axis and collide with their neighbours; and a
label that moves as focus moves is a label you have to chase. The dock can get
away with per-pip captions because a horizontal row spreads them naturally. A
vertical stack cannot, and the difference is geometry, not preference.

---

## 4. Anatomy — the PROJECTOR

Three parts, in the app's existing naming register (MOTE, HALO, SPUR, RAIL,
TUMBLER, DETENT, REEL, RACK):

```
                    ┌──────────┐   ← PLATE  (one choice)
                  ┌─┴────────┐ │
                ┌─┴────────┐ │ │      the STACK, fanned
              ┌─┴────────┐ │ │ │
            ┌─┴────────┐ │ │ │ │
            └──────────┘ │ │ │ │
                 ╲    ╲  ╲ ╲ ╲       ← the CONE (volumetric, scanlined)
                  ╲    ╲  ╲ ╲ ╲
                   ╲____╲__╲_╲_╲
                     ◉  EMITTER      ← the dock's SETUP pip
```

**EMITTER** — a dock pip, at one end of the row and set slightly apart from the
other seven. §5's hand-menu spec puts the settings gear *outside* the swipe ring
"so you can never land on settings by accident while cycling"; the dock inherits
that rule as physical separation plus its own guard (§7).

**CONE** — a faint volumetric cone from emitter to stack. It is the Star Wars
signature and it does two jobs: it says *where this came from*, which makes
collapse-to-origin the obvious dismissal; and it gives the floating stack a
physical parent, without which a menu in mid-air has no story about why it is
there. Scanlines crawl **up** the cone, from emitter toward stack — the
direction encodes projection rather than decoration.

**STACK** — the widget. Specified separately below because CHANNELS reuses it.

---

## 5. The STACK — a reusable primitive

A fixed, small set of choices presented as physical laminae. Two states.

### 5.1 Collapsed (at rest)

Plates compressed into a puck ~0.03 m above the emitter, edge-on, 0.006 m
apart. Reads as a cartridge of slides waiting to be projected. This is the
"stacking widget": the resting form carries the promise of the expanded one, so
the expansion is legible as *the same object*, not a replacement for it.

### 5.2 Fanned (summoned)

Plates rise and splay into a shallow fan facing the eye.

| Property | Value | Why |
|---|---|---|
| Stack centre distance | 0.90 m | Arm's length, past the dock, short cone |
| Stack centre elevation | 11° below eye | Continuous with the dock at −30°; leaves the true centre clear |
| Plate mark | 0.047 m ≈ 3.0° | See §8 — anchored to a measured icon, not a guess |
| Plate pitch | 0.085 m ≈ 5.4° | Selection separation — below ~5° hand tracking cannot reliably distinguish adjacent targets |
| Depth splay | 0.02 m per plate | The nearest plate is the top of the deck |
| Fan span (5 plates) | 0.34 m ≈ 21.5° | Fits the vertical budget; see §8 |

**Pitch is set by the hand, not by the mark.** At 3.0° the marks would pack into
15° of arc, but hand tracking cannot reliably separate targets closer than ~5°,
so the plates sit further apart than they need to be and the gaps are empty.
That is the correct trade and worth stating so nobody later "tightens" it: the
binding constraint on a selectable stack is the pointer, not the artwork.

**The fan is ordered, not radial.** A carousel or an orrery was considered and
rejected: it looks better in a screenshot and it destroys the one thing a
settings menu must have, which is a stable *order* the user can learn. SNS's
five are in a fixed order; so are these.

### 5.3 Focus and selection

- **Focused** plate: advances 0.03 m toward the eye, goes to full luminance,
  and writes its name into the readout slot (§3.1). Neighbours dim to 0.55.
  The readout is never empty while the stack is fanned — it shows the focused
  plate, or the last focused one, because a blank label slot reads as a fault.
- **Selected** plate: advances to the front of the fan; the others **recede and
  dim but do not disappear**. They are the breadcrumb — §5 of the brief calls
  knowing where you are "the thing that is genuinely hard in a headless spatial
  UI", and keeping the unchosen plates visible answers it without a title bar.
- **Descend**: the selected plate *develops* into its bay — the plate is the
  bay's substrate, growing into the instruments rather than being replaced by
  them. For DEVICE this is the rack unfolding; `Unfold.kt` already exists.

### 5.4 Recursion

CHANNELS is a STACK of channel plates inside a STACK plate. This is the argument
for building it as a primitive rather than as part of the console: one widget,
two depths, and the interaction the user learned at the top level is the one that
works inside. Nesting is capped at **two**, matching the lens-stack decision — a
third level is a filesystem, not a console.

---

## 6. Interaction

| Action | Primary | Parity path (§8.2 requires both) |
|---|---|---|
| Summon | Pinch the SETUP pip | Gaze + dwell on the pip |
| Traverse | Point; focus follows the ray | Gaze + dwell moves focus |
| Select | Pinch the focused plate | Dwell 700 ms on it |
| Back one level | ASL **B**, either hand | Pinch/dwell the emitter |
| Dismiss | Pinch the emitter | Dwell on the emitter |

**Gaze-and-dwell is not optional here.** §8.2 lists it as non-negotiable and it
is currently unbuilt everywhere; the console is the right place to introduce it
because a settings surface is stationary, deliberate, and forgiving of a 700 ms
dwell in a way that node selection on a live mesh is not.

Collapse always returns the stack **to the emitter**, along the cone, so the
dismissal is visibly the inverse of the summon.

---

## 7. Guarding — this surface can break the radio

Four fields in the DEVICE bay can leave the hardware deaf in the field, and two
broadcast the wearer's position (§9.6.1). The console must not make those
*easier* to reach than the rack made them.

- The SETUP pip is **separated** in the dock row and **does not respond to a
  brushing pointer** — it requires the same deliberate pinch as everything else,
  but with no hover-fire grace period.
- The DEVICE plate opens the rack **with its guards intact**. The console
  changes how you *reach* the rack; it changes nothing about how you operate it.
- **Recommendation: the dock's RADIO pip is retired** and the rack is reached
  only through the console. The user's original objection — *"this UI is sitting
  in a place where it will get misconfigured"* — is better served by one guarded
  entrance than two. The cost is one extra step to the rack, which for a surface
  you touch once per deployment is the correct trade. **This is decision D1.**

---

## 8. Legibility budget

Applying §4.1 (no text below 1.2° at any distance), and the lesson from
`MeshmoreXR-course-correction.md` §2 that fixed metre sizes chosen by eye come
out under the floor — **so these are derived, not picked**:

### 8.1 Icons

§4.1's 1.2° floor is a **text** rule: you must resolve strokes to tell `8` from
`B`. An icon in a set of five needs only to be told apart from four others,
which is a far easier discrimination, so the text floor does not transfer — but
icons need a floor of their own and it should come from a measurement rather
than from a round number that sounds right.

**We have one.** The ASL hand diagrams on the help card are 0.085 m at 1.5 m =
**3.25°**, and at that size finger separations resolve on the Aura — confirmed
in capture on 2026-08-01, on the specific display this ships to. That is the
hardest icon discrimination in the app (which of several similar hand shapes),
so it is a conservative anchor for five distinct silhouettes.

**Proposed rule: no icon below 3.0° of visual angle**, pending the same
build-and-look every other threshold in this project has had. At 0.90 m that is
a 0.047 m mark.

### 8.2 Text

Only the readout carries text, at 0.85 m, where 1.2° = 0.0178 m cap.

| Element | Cap | Angle | |
|---|---|---|---|
| Readout title | 0.022 m | 1.48° | SNS hub string verbatim |
| Readout subtitle | 0.020 m | 1.35° | SNS subtitle verbatim |
| Bay instrument legends | ≥0.0178 m | ≥1.20° | the rack's current 0.010 m is **illegal** and must be raised when it becomes a bay |

**The readout wraps to at most two lines of ~20 characters.** At legal size,
20 characters is 25–27° of arc, which is the practical width of one line; the
longest SNS subtitle ("Connect a radio · frame log · M6 capture", 39 characters)
is 47° on one line and must wrap. Two lines in a fixed slot is a *label*, not a
list — the distinction being that it describes one thing rather than enumerating
several.

This is the whole payoff of §3.1. A text-first stack had to choose between legal
type and SNS's actual wording, and would have shipped five abbreviations. One
label at a time can be full size *and* say what the phone app says.

**The console may use the protected centre.** §2.1 rule 2 reserves 34°×20°
against anything *persistent*; the console is summoned and dismissed. It and
FOCUS are the only surfaces with that permission, and it should be written into
§2.1 as an explicit exception rather than left as an inference.

---

## 9. Holographic devices — what earns its place, and what does not

**Kept, each with a job:**

| Device | Job |
|---|---|
| Scanlines | Reduce total emitted light while preserving edge legibility — genuinely useful on additive optics — and read as *projection* rather than *screen* |
| Cone | Names the origin; makes dismissal obvious |
| Edge glow / bloom | Additive-native; carries silhouette where a fill cannot |
| Translucency + grain | Honest about the display; lets the room through, which §1.3 says we cannot prevent anyway |
| Monochrome per theme | One projection hue per theme — see below |

**Rejected:**

- **Leia-style luminance flicker on text.** The signature is tempting and the
  chassis may shimmer very slightly, but **text never flickers**. Flickering
  legibility is not an aesthetic, and the brief already calls flicker on a
  hand-anchored element "the most nauseating failure mode available in XR".
  The console is world-anchored, which makes a *chassis* shimmer tolerable and
  a *text* shimmer still wrong.
- **Rotation / orbiting.** Looks like the Death Star briefing, destroys learnable
  order (§5.2).
- **A projected 3D "figure".** There is nothing to depict. A hologram of a gear
  is a skeuomorph of an icon of a metaphor.

**Nine themes, nine projections.** The hologram is a *render mode*, not a
palette — each theme supplies one projection hue and one grain, which keeps §7's
claim that the theme system is genuinely data. HALO FIELD gets canonical cyan;
RECON AMBER gets amber and, being the night-vision theme, gets the lowest
scanline duty cycle; TERMINAL VOID gets phosphor green and no bloom at all.

**Reduce-motion clamps** (§9.1): scanline crawl → static, shimmer → off, fan
transition → instant cut. The collapsed and fanned states both remain, because
the *state* is information; only the tweening goes.

---

## 10. How each bay avoids being a list

The selector is the easy half. This is the half that decides whether the whole
thing is honest.

- **DEVICE** — solved. THE RACK, §9.6.
- **PROFILE** — theme preset is a **TUMBLER** of nine coins, each rendering a
  live swatch of its own palette; type size is a **RAIL** with the 1.2° floor
  marked as a red zone it cannot go below; audio master and the three a11y flags
  are **DETENT**s, with the clamping ones (`reduceMotion`, `visualHapticOnly`)
  physically guarded because they override theme identity (§9.1).
- **APP** — language is a TUMBLER; notifications, background and data are
  DETENTs; connection state is a **lamp**, not a row. Permissions are the one
  genuinely OS-shaped item and should hand off to the system prompt rather than
  be re-skinned.
- **CHANNELS** — a nested STACK, one plate per slot. Name and #hashtag are
  short text; the PSK is the hard case and is deliberately **not** editable by
  air-typing 64 hex characters. Import by QR (§10 of the brief keeps `QrCode`
  for exactly this: contact and channel-key exchange off a phone screen), or
  from the paired radio. Manual hex entry stays on the phone app, and the
  console says so rather than offering a bad affordance.
- **DIAG** — see below.

### 10.1 Diagnostics: the one honest exception

**Decision taken 2026-08-02: diagnostics stays ON.** My earlier recommendation
to default it off is withdrawn — the objection was never that the log is
unwanted, it is that it is an unhoused scrolling panel with no parent. Housing
it fixes that.

A frame log is a **time series**, and time is legitimately linear — this is the
one place in the app where a scrolling thing is the truthful representation
rather than a failure of imagination. So it is specified as a **TAPE**: a
paper-tape ribbon emerging from the emitter and curling away, newest at the
emitter end. It scrolls because time does, and its form says so.

The tape may live outside the console while the console is closed, which is what
it does today. What changes is that it gains a home, an owner, and an off
switch that is somewhere findable.

---

## 11. What this does not decide

- **D1 — Retire the dock's RADIO pip?** §7. My recommendation is yes.
- **D1b — Does §3.1 apply back to the dock?** It offers a third answer to the
  dock-caption problem in `MeshmoreXR-course-correction.md` §2, which currently
  has only two bad options (four-character abbreviations, or a two-row stagger).
  If each pip carried a **mark** at ≥3.0°, identity would live in the icon, the
  permanent caption could retire, and the focus-revealed caption could be full
  size and legal in a slot below the row — the 0.83° violation disappears rather
  than being negotiated. This does **not** contradict the 2026-08-02 decision:
  that decision was that *seven identical rings* must be labelled, and it is
  correct. The question §3.1 raises is whether they should have been identical.
  Not to be acted on without a call — the dock is the surface you have actually
  been using.
- **D2 — Does the console replace the HAND MENU, or sit inside it?** The brief
  §5 gives the settings gear to the hand menu; we built a dock instead. This is
  the same open question as D3 in the course-correction note and should be
  settled once, for both.
- **D3 — Dwell duration.** 700 ms is a starting number from the literature, not
  a measurement. It needs a build-and-look like every other threshold in this
  project, and it interacts with `a11y.dwellOnly`.
- **D4 — Does PROFILE's theme picker switch themes live?** A live switch is the
  best demo in the app and also the biggest rebuild-everything event. Possibly
  worth a deliberate transition rather than an instant one.
- **Geometry in §5.2 is derived, not verified.** Every number in this document
  that describes where something sits is arithmetic. The project's standing rule
  is that such numbers are settled on hardware, and none of these have been.

---

## 12. Sequencing note

This is a large surface — five bays, a new primitive, a new input path
(gaze-dwell), and the first nested navigation in the app. It should **not**
displace S3 NODE FOCUS, which is smaller, closes P2, and is the thing that makes
the mesh usable rather than merely visible.

Suggested order: **S3 NODE FOCUS → the STACK primitive + selector shell →
DIAG (which carries S2 LINK) → PROFILE → CHANNELS → APP**, with DEVICE simply
re-parented into the console when the shell exists.
