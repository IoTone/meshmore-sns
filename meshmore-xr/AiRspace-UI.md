# AiRspace UI

**A spatial widget library for optical see-through glasses.**
Reference implementation: `meshmore-xr/airspace-ui/` (Three.js).
Production target: `com.iotj.meshmore.xr.airspace` (SceneCore).

---

## 0. Why this exists

The default Android XR widget vocabulary is Material Design floated into space.
A `Switch` in a `SpatialPanel` is still a switch: a flat rectangle whose entire
affordance is a coloured rounded pill that slides left-right. It carries no
depth, no volume, no mass, and no reason to exist in three dimensions. It is a
phone control wearing a costume.

This is not a rendering complaint. It is a **semantic** one. Material's controls
encode one input model — *a fingertip contacting a plane* — and every one of its
affordances is a consequence of that model. Ripples radiate from a touch point.
Elevation is faked with a drop shadow because there is no real z. Lists scroll
because a 6-inch plane cannot hold more than eight rows. Dropdowns drop *down*
because gravity is a metaphor on a plane and a fact in a room.

On glasses the input model is different in kind: **reach, gaze, and proximity in
a volume you occupy.** Widgets built for a fingertip on glass answer a question
nobody is asking.

So: AiRspace UI. A widget set derived from the actual input model, with a
one-to-one migration path from Material so nothing becomes unbuildable.

> **The continuity concession, stated honestly.** We keep Material's *layout
> engine, focus order, semantics tree, and accessibility contract* — those are
> platform-quality and re-implementing them is how XR projects die. We replace
> only the **presentation and affordance layer**. An AiRspace `Detent` reports
> itself to TalkBack as a switch, participates in the same focus traversal, and
> honours the same state hoisting. It just isn't a pill.

---

## 1. The seven laws

Every widget in this library obeys all seven. A widget that cannot is not a
widget; it is a panel, and panels are a last resort (§6).

**L1 · Billboard.** Position from the anchor, **orientation from the head**,
always. Never compose a widget's pose with the hand's rotation — when the user
looks at the back of their hand the widget goes edge-on and foreshortens into an
unreadable sliver. Field-confirmed, twice.

**L2 · Solid *and volumetric*.** No thin strokes, no wire outlines, no hairline
rims as the primary form — **and no flat-shaded geometry**. A sphere drawn with
an unshaded material renders as a flat coloured circle: foreshorten-proof, but
2D. Every primitive carries a lambert body term and a fresnel rim so it reads as
a volume. See `AiRspace-HUD-and-symbology.md` §1.

A thin ring viewed off-axis reads as a broken arc and users interpret it as a
rendering bug. Spheres, tori, extruded tubes, cones, bevelled solids. A
**sphere is the ideal control surface** — identical from every angle, so it can
never foreshorten.

**L3 · Triple cue.** Every state change emits **visible + audible + haptic**,
synchronised, always, with no exceptions and no "this one is too minor." Any one
channel may be user-disabled; the design may never *depend* on any one.

**L4 · Volume.** A widget must read as an object with depth, not a decal. If its
silhouette is identical to a rectangle drawn on glass, it has failed. Minimum:
visible thickness, a lit edge, or parallax against its own backing.

**L5 · Reach vs. read.** Controls live in **reach space** (0.35–0.7 m). Content
lives in **read space** (1.2–2.5 m). Never put a control in read space, and never
put a paragraph in reach space. Mixing them is the single most common way
spatial UI becomes tiring.

**L6 · Dwell parity.** Every control is operable by gaze + dwell as well as
pinch. Hand tracking is a permission that can be denied and a capability that
degrades; a denied permission returns "no hands," not an error.

**L7 · Angular floor.** Measured in visual angle, not pixels, not dp:
Latin text ≥ **1.2°**, **kana ≥ 1.5°**, **kanji ≥ 1.8°**, any target ≥ **0.6°**,
anything reached-for ≥ **2°**, stroke weight ≥ **0.25°**. At 0.5 m, 2° ≈ 17 mm.
These are floors, not targets — and the floor cuts *both* ways, so an oversized
label is as much a defect as an undersized one. The CJK tiers are not a
courtesy: see `MeshmoreXR-i18n-ja.md`.

---

## 2. The migration table

Every Material control, and what replaces it. **Bold** entries are implemented
in the prototype.

| Material | AiRspace | Physical model |
|---|---|---|
| `Button`, `FAB` | **PEBBLE** | A weighted oblate spheroid. Depresses along the head vector, returns with overshoot. |
| `Switch`, `Checkbox` | **DETENT** | A slug that travels a short track and *seats* into one of two wells. State is read from **position and depth**, not colour. |
| `Slider` | **RAIL** | A bead on a rod. Grab, slide, release. Physical notches at step values. |
| `RadioGroup`, `SegmentedButton` | **TUMBLER** | A rotating drum, combination-lock style. One value faces you. Detents between. |
| `DropdownMenu`, `ExposedDropdown` | **FAN** | Options deal out in a radial arc around the pinch point. Never a vertical list. |
| `NavigationBar`, `TabRow` | **BAND** | Concentric arcs of the HORIZON. You *turn your head* to change section. |
| `LazyColumn` | **STRAND** | Items on a curved rail receding in depth. You push and pull the strand; you do not scroll a viewport. |
| `LazyColumn` (chat) | **REEL** | An oval ring buffer above the palm. You rotate it. Bounded by construction — the shape *is* the data structure. |
| `Badge`, notification dot | **CUFF** | A torus around the wrist that lights. Legible at any hand orientation, so it cannot be turned away from. |
| `TextField` | **SLATE** | A recessed well. Primary input is voice; the keyboard is a fallback that rises to hand height only when summoned. |
| `AlertDialog`, `ModalBottomSheet` | **INTERPOSE** | Nothing overlays. The dialog *physically approaches* and pushes current content back in depth and down in luminance. |
| `LinearProgressIndicator` | **COLUMN** | A vertical volume that fills. Readable from any angle, including from behind. |
| `Snackbar`, `Toast` | **EMBER** | A glowing mote at the viewport edge, on the **bearing of its cause**, decaying over ~3 s. |
| `Card` | **SHARD** | A bevelled solid with real thickness and a visible lit edge. |
| `DropdownMenu` (contextual) | **CROWN** | A radial menu around the hand. Direction selects; distance confirms. |
| `Stepper` | **RATCHET** | A ratcheting wheel with hard detents and a per-step haptic tick. |
| `ColorPicker` | **ORB** | A colour sphere you reach into. Depth is value, surface is hue/chroma. |
| `Scrollbar` | *abolished* | Depth is the scroll. There is nothing to indicate. |
| `Divider` | *abolished* | Space separates. Lines are a 2D crutch. |
| `Tooltip` | *abolished* | If a control needs a tooltip, it is the wrong shape. |
| `Elevation` / shadow | *abolished* | There is real z. Use it. |

### 2.1 Widget specifications

Each entry: **form · states · triple cue · dwell path · failure mode.**

---

#### PEBBLE — the button

- **Form.** Oblate spheroid, 24–40 mm at 0.5 m (≥ 2° per L7). Matte body, one
  bright specular hit that tracks the head so it always reads as lit and always
  reads as *round*.
- **States.** `rest → proximate → hover → press → commit`. **`proximate` is new
  and important**: the pebble responds to the hand approaching *before contact*,
  swelling ~4% at 15 cm. This is what makes spatial controls feel alive and is
  the single cheapest "wow" in the library.
- **Cue.** Visual: swell + specular bloom + rim ignition. Audio: hover blip →
  commit tone (per theme, §3 of the audio spec). Haptic: `TICK` on hover,
  `CLICK` on commit.
- **Dwell.** Gaze ≥ 400 ms fills a ring *around* the pebble (an annulus, not a
  stroke — L2), commit at 900 ms.
- **Failure.** No hands → dwell only. No haptics → audio + visual carry it.

#### DETENT — the toggle

- **Form.** A slug in a short track with two seated wells. Off = seated far, low,
  dim. On = seated near, raised, lit. **The state is legible in silhouette from
  any angle**, which a Material switch is not.
- **Why not colour.** A coloured pill fails for colour-blind users, in direct
  sun, and in the single-hue themes (RECON, TERMINAL VOID). Position + depth
  never fails.
- **Cue.** Visual: travel + seat + luminance step. Audio: a two-part *thunk*
  (release, then seat). Haptic: `LOW_TICK` on unseat, `CLICK` on seat.
- **Dwell.** Gaze + dwell toggles; the slug animates so the change is witnessed,
  never instant.

#### RAIL — the slider

- **Form.** A tube (never a line — L2) with a spherical bead. Track length ≥ 15°
  of arc. Notches are **physical geometry**, not tick marks.
- **Cue.** Audio pitch tracks value continuously while dragging — *the slider is
  audible*, which makes eyes-free adjustment possible. Haptic `TICK` per notch.
- **Dwell.** Gaze the bead to arm, then head-turn scrubs the value, dwell to
  commit. This works and is the only genuinely good no-hands slider we know of.
- **Failure.** Value always has a numeric SLATE readout; the bead is never the
  only representation.

#### TUMBLER — the enum picker

- **Form.** A drum rotating about a horizontal axis, current value facing the
  user, neighbours curving away above and below. 3–9 values.
- **Why.** A radio group is *n* rectangles competing for attention. A tumbler has
  exactly one focal value and shows adjacency for free.
- **Cue.** Detent haptic per value; audio pitch steps up/down the drum.
- **Failure.** > 9 values → FAN. > 24 → STRAND.

#### FAN — the picker

- **Form.** Options deal out in a **radial arc** (±60°) around the pinch point,
  ordered by frequency of use, at a constant radius so all are equidistant to
  reach. Closes on select or on hand-drop.
- **Why not a dropdown.** A vertical list in space forces the user to raise and
  lower their gaze through content they aren't choosing. A radial arc is one
  wrist rotation.

#### CROWN — the contextual menu

- **Form.** A ring of PEBBLEs around the hand at ~12 cm. **Direction selects,
  distance confirms** — push outward through the item to commit. This makes
  accidental selection nearly impossible without a confirmation dialog.
- **Cue.** Each sector has its own pitch; sweeping the hand plays the menu.
- **Item-anchored variant.** Invoked from a REEL slot, the CROWN spawns around
  **the message**, not the hand, so the thing being acted on stays visibly under
  the menu. Same geometry, same commit rule.
- **Message actions:** Reply · Read aloud · Copy · Delete here · DM sender ·
  Pin sender's location.
- **"Delete here" is local-only, and the label must say so.** There is no
  unsend on a mesh — the packet is gone, possibly relayed through nodes we will
  never talk to again. A control labelled plain "Delete" invites a user to
  believe they recalled a message they did not. Destructive actions use the
  push-through commit.

#### STRAND — the list

- **Form.** Items on a curved rail receding **in depth**, not down a plane. Near
  items are large and lit; far items shrink into atmospheric haze. Push and pull
  the strand along its own axis.
- **Why.** This is the crux of "don't stare at lists." A Material list is a
  window onto a long plane. A strand is a physical object with a near end and a
  far end, and its length is *visible* — you can see how much there is.
- **Cue.** Per-item pass tick. Momentum with real friction. Ends have a hard
  physical stop, never a rubber-band.
- **Failure.** Over ~40 items a strand becomes a chore; above that, the data
  wants filtering, and filtering by **voice** is the answer.

#### REEL — the chat ring buffer

- **Form.** An elliptical track floating ~10 cm above the palm, oriented to the
  head (L1). **12 slots, ~5 legible across the front arc.** Each slot carries a
  message SHARD; the front slot is largest and fully legible, and slots receding
  around the ellipse shrink and dim (the TUMBLER treatment).
- **Why a ring, not a list.** It is a *ring buffer*, and the shape is the data
  structure: bounded capacity, oldest rotates off, **no scrollbar, no infinite
  scroll, no "load more".** A closed loop cannot lie about how much there is —
  which a scrolling viewport does by construction.
- **Why an oval, not a circle.** The viewport is 61° × 34° — much wider than
  tall. An ellipse fits more legible slots across the horizontal without growing
  into the vertical budget, and it reads as a physical loop rather than a clock
  face.
- **Rotation.** Thumb-along-index on the reel hand — the same gesture as the
  HAND MENU, mirrored. One detent per slot. *Not* a wrist roll: that is
  supination, which is already the palm-up reveal, and the two would fight.
- **Selection.** Gaze a slot → it advances to the front. Pinch or dwell on the
  front slot → **CROWN** (below).
- **Cue.** `DETENT` per slot, pitch walking the reel. The felt ridge of the
  knuckle supplies the third channel that the hardware cannot.
- **Capacity honesty.** The reel is a *view* of the last N, never the archive.
  Full history lives in the S4 SPEAK thread. Deleting from the reel is local.
- **Sizing.** Message bodies are user content in any script, so the slot is
  sized for the **kanji floor (1.8°)**, not the Latin one. A reel sized for
  English will not hold Japanese.
- **Reduce-motion.** Snaps between slots; never spins.
- **Failure.** No hands → the reel is simply unavailable and S4 SPEAK's FOCUS
  panel carries the same content. It is never the only route to a message.

#### CUFF — the wrist indicator

- **Form.** A **torus around the wrist**, ~6–8 mm tube — not a patch on the back
  of the hand. A ring encircling the wrist is legible at *any* hand orientation,
  so unlike a flat badge it cannot be accidentally turned away from, and it is
  foreshorten-proof by construction (L2).
- **States.** `idle` (dim or absent) → `arrival` (pulse) → `standing` (steady,
  unread present) → `cleared`.
- **DM vs channel is carried by FORM, not colour.** A channel message lights a
  **single arc segment**; a direct message pulses the **whole cuff**. That
  distinction survives the single-hue themes (RECON, TERMINAL VOID), survives
  colour-blindness, and survives bright sunlight — none of which a colour swap
  does.
- **Count.** Up to five lit segments, then a numeral.
- **Reduce-motion.** A step change in luminance instead of a pulse.
- **Never the sole channel.** Arrival always fires audio (E10/E11) *and* the
  MICROHUD counter *and* the CUFF. Any one may be disabled.
- Rides the **chat hand** — the hand opposite the HAND MENU — and mirrors with
  the handedness setting.

#### SLATE — text surface and text entry

- **Form.** A recessed well with a visible lip (L4). For entry: **voice is
  primary**. Push-to-talk, live transcription into the well, review, commit.
- **Keyboard.** A fallback that rises to hand height (reach space, L5) only when
  summoned, and never blocks the forward FOV.
- **Never.** Auto-focusing a text field and popping a keyboard is a phone
  reflex. In XR it is an ambush.

#### INTERPOSE — the dialog

- **Form.** Approaches from 2.5 m to 0.9 m over ~250 ms while the current content
  recedes and dims. **It does not overlay.** When dismissed it retreats; content
  returns.
- **Why.** A modal scrim is a 2D solution to a 2D problem (you cannot move things
  in z on glass). We can move things in z. Do that instead.
- **Safety.** Physical-actuation confirmations (the lobospeak robot case) use a
  **push-through** commit — the user must physically push the confirm PEBBLE
  away from themselves. Deliberately un-accidental, and **identical in all nine
  themes** (safety signals are never themeable).

#### COLUMN — progress

- **Form.** A vertical volume that fills from the base. Always carries **step or
  percentage semantics** — `SCANNING 60%`, `STEP 2/4` — never a bare spinner.
- **Placement.** EDGE zone, head-locked at the outer viewport rim, auto-dismissed
  ≤ 3 s after terminal state. Never load-bearing for correctness.

#### EMBER — the notification

- **Form.** A glowing mote at the viewport edge **on the true bearing of its
  cause**, decaying over ~3 s. See §4 of the audio/haptics spec — the spatial
  notification model is the same across all nine themes; only the character
  changes.

---

## 3. Zones, restated as an API

The five zones from the design brief are the library's layout primitive. There
is no `Box`, no `Column`, no `Row` — **there is no 2D layout in AiRspace.**

```kotlin
Rig {
    Horizon(radiusMeters = 2.5f, yawOnly = true) { /* the always-on mesh */ }
    Reach(radiusMeters = 0.5f, arcDegrees = 140f) { /* controls: Pebble, Rail… */ }
    Read(distanceMeters = 1.4f)                    { /* content: Slate, Strand */ }
    Edge                                           { /* Column, Ember */ }
    Ground                                         { /* the map table */ }
}
```

`Reach` and `Read` are the enforcement mechanism for L5: you *cannot* place a
Pebble in `Read`, because `Read` does not accept controls. The type system
carries the design rule.

---

## 4. THE CONSOLE — settings, spatially

> "Settings need to be spatial."

The Material answer is a `LazyColumn` of `ListItem`s with trailing `Switch`es.
Floating that in space is the exact thing we are rejecting. Here is the
replacement.

**Settings is a place, not a list.** It is an instrument console curved around
you at reach height — the thing a pilot turns to, not a document they scroll.

```
                        plan view — you seated at the console
                        ─────────────────────────────────────

         ╭──────────╮                                  ╭──────────╮
         │  RADIO   │                                  │  VOICE   │
         │ ◉ ◉ ▮▮▮  │      ╭────────────────────╮      │ ◉  ▮▮▮▮  │
         ╰──────────╯      │      IDENTITY      │      ╰──────────╯
                           │   callsign  ◉◉◉    │
    ╭──────────╮           ╰────────────────────╯           ╭──────────╮
    │  THEME   │                                            │  SAFETY  │
    │ ⬢ tumbler│                  ▓▓▓▓▓                     │ ◉ push→  │
    ╰──────────╯                  ▓ YOU ▓                   ╰──────────╯
                                  ▓▓▓▓▓
              ╭──────────╮                    ╭──────────╮
              │  ACCESS  │                    │  UPLINK  │
              │ ◉ ◉ ◉ ▮▮ │                    │  ▮▮▮  ◉  │
              ╰──────────╯                    ╰──────────╯

              seven clusters · 140° arc · reach space (0.5 m)
```

- **Seven clusters, each a physical station** on a 140° arc: IDENTITY · RADIO ·
  VOICE · THEME · ACCESSIBILITY · UPLINK · SAFETY. You turn to face one. The
  others dim and recede but stay visible — **you never lose your place**, which
  is the thing a navigation stack always costs you.
- **Controls are the widgets above.** Radio TX power is a RAIL you slide. Region
  is a TUMBLER you spin. TTS on/off is a DETENT you seat. Theme is a TUMBLER
  whose rotation restyles the *actual HORIZON behind you*, live.
- **No search field, no scroll.** Seven stations is the entire surface. If a
  station needs more than nine controls, the station is wrong and gets split.
- **Voice as a cross-cut.** "Set TX power to 20" moves the actual RAIL bead, with
  its detent sounds, so the user *learns where the control lives* by watching
  the voice command operate it. Voice teaches spatial memory instead of
  replacing it.
- **Accessibility station is a station, not a submenu**, and it is reachable from
  every surface with one gesture.

This is the pattern for every dense surface in MeshmoreXR: **cluster into
stations on an arc, put controls in reach space, keep everything visible,
never stack.**

---

## 5. The Vectrex exception

> "For the low-power theme, we can really just go full 2D vectrex as the
> exception."

Agreed, and it should be a *loud* exception rather than a quiet degradation.

**TERMINAL VOID** (and RECON AMBER's deep-power sub-mode) drops the entire
volumetric layer and renders as a **flat vector overlay at a fixed 1.6 m
plane** — a single billboarded surface, monochrome phosphor, stroke geometry
only. Deliberately, visibly 2D.

Why this is the right exception rather than a cop-out:

- **It is honest.** Low-power means *not lighting a volume*. A theme that claims
  low power while rendering a particle field is lying.
- **It has the best precedent.** The Vectrex is the correct reference: a vector
  CRT whose colour came from a **translucent plastic screen overlay** slotted in
  front of the tube. That maps perfectly to an additive see-through display —
  our "overlay" is a single tinted plane and the real world is the phosphor
  darkness behind it. The historical hack and the modern constraint are the
  same hack.
- **Widget mapping.** The AiRspace widgets have flat vector counterparts with
  **identical semantics, identical focus order, identical audio and haptics** —
  a PEBBLE becomes a filled vector polygon that inverts on press; a DETENT
  becomes a slug that slides along a drawn track; a TUMBLER becomes a scrolling
  numeric readout. Only presentation changes. The migration is a renderer swap,
  not a rewrite, and that is the whole argument for having a widget library at
  all.
- **Measured claim, not a vibe:** stroke-only, single-hue, no particles, no
  glow, one draw plane. This should be the longest-battery mode in the app and
  we should *publish the number* once we can measure it on hardware.

Everything else in the set stays volumetric, and the exception exists to make
the rule visible.

---

## 6. When a panel is still correct

Panels are not banned; they are *budgeted*. A `SpatialPanel` is correct when all
four hold:

1. The task is **dense, textual, and rare** (radio config, terms, rule authoring).
2. It is **explicitly entered and explicitly left** — never ambient.
3. It is **one panel** (the FOCUS zone allows exactly one).
4. It **paints its own backing** — panel surfaces are not alpha-transparent, and
   undrawn pixels show the raw grey surface.

Three surfaces in MeshmoreXR qualify: S2 LINK, S8 PINS rule authoring, S12
ABOUT. That is the budget. Everything else is spatial.

---

## 7. Library architecture

```
airspace-ui/src/airspace/
├─ Rig.js            the five zones; Reach/Read separation enforced
├─ Billboard.js      L1 — position from anchor, orientation from head
├─ Cue.js            L3 — one call fires visual + audio + haptic together
├─ theme.js          9 themes as pure data (no widget knows a colour)
├─ audio.js          procedural synth; per-theme packs
├─ haptics.js        haptic vocabulary + honest fallback (§ audio spec 5)
└─ widgets/          Pebble · Detent · Rail · Tumbler · Fan · Crown ·
                     Strand · Slate · Column · Ember
```

**The one architectural rule:** no widget knows a colour, a font, or a sound.
Widgets take a `theme` token and a `Cue` sink. This is what makes nine themes
cost styling instead of nine implementations, and it is the load-bearing
decision flagged in the design brief.

**Production port.** The Three.js implementation is the design prototype and
the spec. The SceneCore port maps: `Object3D` → `Entity`, billboard → head-pose
compose in `Space.REAL_WORLD`, `Cue` → `SoundPool`(`USAGE_MEDIA`) + `Vibrator`,
and the geometry is authored as glTF rather than procedural primitives.

---

## 8. Open questions

1. **Is `Reach`/`Read` separation too strict?** It forbids a control attached to
   distant content (e.g. a mute button on a far node). Current answer: select the
   node, and its controls come to your hand. I think that is right, but it is a
   real constraint and worth arguing about.
2. **CROWN's push-through commit** — is it too effortful for frequent actions? It
   is clearly right for destructive ones. Possibly two commit modes.
3. **STRAND at scale.** 40 items is my guess at the ceiling. Needs a real test.
4. **Does AiRspace ship as an open library?** It is genuinely useful beyond
   MeshmoreXR, the Android XR default vocabulary is weak, and there is no
   competitor. Separate repo, MIT, same as `libmeshcore`.
