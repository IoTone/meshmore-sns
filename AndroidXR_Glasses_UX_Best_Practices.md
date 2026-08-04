# Android XR Glasses — UX Best Practices (field-learned)

Practical, hard-won guidance for building UX on **Android XR optical see-through
glasses** (Xreal Aura class), captured from building the RobotARme client. Every
item here cost a real bug, crash, or confused first-time user. Dates/versions
reference the RobotARme field log so you can trace the original incident.

Target device profile: monocular-ish FOV ~45–50°, passthrough (the real room is
visible), hand tracking + head (device) tracking via ARCore for Jetpack XR, a
Jetpack Compose spatial UI layer **plus** an optional native OpenXR/Vulkan layer
for heavy rendering (e.g. gaussian splats). Much of this generalizes to other
Android XR headsets.

> **Read §0 first if you are on optical glasses.** This document originally
> described **video passthrough** (RobotARme, 2026-07). A second app —
> MeshmoreXR on Xreal Aura, 2026-08 — is **additive optical see-through**, and
> several rules below *invert* on that hardware. Items are tagged `[VIDEO]` or
> `[ADDITIVE]` where the two disagree. Everything untagged holds for both.

---

## 0. Know which display you are drawing on — half these rules depend on it

**Video passthrough** composites your UI over a camera feed. Black is black; you
own every pixel; contrast works the way it does on a screen.

**Additive optical see-through** (Aura class) *adds* light to the room. It can
make things brighter and can never make anything darker. Consequences, all of
them load-bearing:

| | `[VIDEO]` | `[ADDITIVE]` |
|---|---|---|
| RGB(0,0,0) | black | **invisible** — it is the room |
| Dark halo behind small UI | ✅ raises contrast | ❌ **impossible**; a dark backing is either nothing or an occluding hole |
| Filled shapes | ✅ read cleanly at any angle | ⚠️ read as a **lump of emitted light** |
| Thin outlines / line art | ⚠️ foreshorten into broken arcs | ✅ read as **diagrams**; the preferred idiom |
| Ensuring legibility | raise contrast against the feed | **raise angular size** — it is the only lever you have |

⚠️ **This directly contradicts §4 and §5 below**, which are correct for video
passthrough and wrong for additive optics. Both are kept, because most teams
will ship on one or the other and need to know which paragraph is theirs.

✅ On additive optics the rule that replaces "add a dark backing" is: **make it
bigger, and draw it as strokes**. See §13.

---



---

## 1. The first-time-XR-user is your hardest user

Most people who put on glasses have **never used XR**. They don't know the
gestures, they can't tell what's tappable, and they can't tell whether the
device even registered their input. Design for that person, not for yourself.

- **Every selection needs BOTH an audible and a visible cue.** On glasses,
  visual feedback alone is easy to miss (small FOV, busy passthrough behind the
  UI). A click sound + a hover/press highlight together make "it worked"
  unambiguous. This was an explicit owner directive and it holds up.
- **Make the tap target obvious as a target.** A control should look interactive
  before it's touched (rim, fill, shadow, hover-light), and change on hover and
  on press. Flat text is not obviously a button in passthrough.
- **Don't rely on system gestures for primary actions.** The hold/pinch/back
  gesture is hard for newcomers to execute reliably. Give critical actions
  (BACK, SCAN, CONFIRM) a literal on-screen or on-hand button.

## 2. Audio: you almost certainly have to build it, and route it as MEDIA

- Android XR gives you **no built-in UI sound**. If your design needs audio (see
  §1, it does), you build it. Porting a procedural synth (oscillators + noise +
  envelopes) is a good approach: zero binary assets, no localization, and it
  unit-tests as pure math (assert non-silent, right length, expected dominant
  frequency).
- **Route playback as `USAGE_MEDIA`.** Assistant/sonification usages can be
  routed or ducked unpredictably on the headset; media is the most reliably
  audible output. (Field: a spoken readout was inaudible under
  `USAGE_ASSISTANCE_SONIFICATION`-style routing until switched to
  `USAGE_MEDIA`.)
- **Carry one sound identity across surfaces.** If the same account uses a phone,
  a browser, and glasses, read the audio profile (enabled / sound-set) from the
  server and honor it everywhere so the user's sound follows them.
- **Default audio ON during pre-login flows.** The user has no profile yet;
  silence there just reads as "broken."

## 3. Head-lock UI orientation; hand-anchor only its POSITION

The single most repeated bug in hand/head-anchored UI: **inheriting the wrong
transform's rotation.**

- A panel that rides the hand should take its **position** from the hand joint
  but its **orientation from the head** (billboard toward the eye). If you
  compose the panel pose with the *hand's* rotation, then when the user looks at
  the back of their hand the panel is edge-on to the eye — it foreshortens into
  an unreadable sliver. (Field 2026-07-25: "icon huge", then "1/5 of a red
  semicircle" — both were foreshortening.)
- Offset the panel a few cm **along the hand→head vector**, not along a hand
  local axis. Using only the two world points (hand joint + head center) makes
  placement independent of wrist rotation *and* of any parent-space scale. A
  fixed local-axis offset swings the panel off the hand as the wrist turns.
- Offset **enough to clear the hand** (~6 cm toward the eye). Too little and the
  hand occludes part of the UI; the user sees a partial shape and thinks it's
  broken.

## 4. Solid shapes beat thin outlines in a see-through FOV `[VIDEO]`

- A **thin ring** or thin stroke viewed slightly off-axis foreshortens into an
  **arc** — users read it as a broken/partial glyph. A **filled disc** looks the
  same from any angle. Prefer solid fills for anything small or hand/head-locked.
  (Field: the "1/5 red semicircle" was a white ring around a dot; a solid red
  disc fixed it.)
- Passthrough backgrounds are bright and cluttered. Give small UI a **dark halo
  / backing** so it holds contrast over anything behind it, and keep a crisp rim.
  ⚠️ `[ADDITIVE]` **Not available to you.** A dark backing emits nothing, and if
  it is a `PanelEntity` it still writes depth and punches a hole in whatever is
  behind it. Use size and stroke weight instead (§13).
- A **3D primitive** (e.g. a sphere as a "physical button") is the most
  foreshorten-proof option of all — it looks identical from every angle. Worth it
  for a signature control the user reaches for constantly.

## 5. Panel surfaces are not free-floating decals `[VIDEO]`

- SceneCore `PanelEntity` surfaces are generally **not alpha-transparent** — the
  pixels outside your drawn content can show the panel's raw (often grey)
  surface, so a "transparent PNG floating in space" look leaks a grey rectangle.
  **Paint your own backing** (a shaped fill) instead of relying on transparency.
- Pose panels in **`Space.REAL_WORLD`, not `Space.ACTIVITY`**, when you derive
  the pose from a world source (head/hand pose). A movable/resizable SpatialPanel
  carries a scale in its parent transform (field: ~1.75×) that will corrupt a
  world-derived pose placed in ACTIVITY space — the element ends up mis-sized or
  behind you.

## 6. Perception (ARCore) work must stay off the main thread

- `session.configure()`, `ArDevice.getInstance()`, and `Hand.*` acquisition are
  **blocking IPC** into the XR runtime. Calling them on the main dispatcher in a
  polling loop stalls the main thread and **ANRs** the app ("Waited 15004ms for
  FocusEvent") — every button goes dead afterward. Acquire on
  `Dispatchers.Default`.
- **Configure at most once, then bound your retries.** Don't re-configure every
  frame or hammer `getInstance` forever; after N misses, park a fixed fallback
  and stop.
- **`Config` REPLACES the whole config; it does not merge.** A bare
  `Config(handTracking = …)` will silently turn off the head tracking another
  feature needs. Every configure in the app should pass the **superset** of
  tracking modes in use (e.g. `handTracking = BOTH` + `deviceTracking = SPATIAL`)
  so features can't clobber each other.

## 7. Managed ↔ unmanaged space transitions are async and lossy

- Full-space round-trips (entering/leaving an immersive native activity, home
  space ↔ full space) **re-grant capabilities asynchronously**. Code on the
  return path must **poll** for the capability/permission to come back, not check
  it once — a one-shot check right after the transition sees the pre-grant state
  and mis-branches.

## 8. Exit an immersive/native session in ORDER, or you crash the compositor

If you own a native OpenXR/Vulkan activity, a sloppy exit takes the **whole OS
compositor** down (field 2026-07-25: systemui `VulkanSwapChain::acquire`).

- On a voluntary exit (BACK button/gesture): call **`xrRequestExitSession()`**
  and keep pumping events so the runtime drains `RUNNING → STOPPING (you
  `xrEndSession`) → EXITING`; only then finish the activity and destroy Vulkan.
- **Never** finish the activity and tear down Vulkan while the session is still
  RUNNING — the compositor still references your swapchains and faults when they
  vanish. Add a bounded timeout so a runtime that never reaches EXITING can't
  hang you.
- Respect the `android_native_app_glue` contract: to leave voluntarily, call
  `ANativeActivity_finish()` and **keep pumping the looper** until
  `APP_CMD_DESTROY` arrives; returning from `android_main` early deadlocks the
  onDestroy handshake.

## 9. Ship risky native GPU features OFF, behind runtime flags

- Native Vulkan features (foveation, custom overlays, hand-tracked geometry) can
  crash hard and are **not** validated by "it compiles." Gate each behind a
  **runtime flag defaulting OFF** (a flags file the app writes + a debug system
  property for bisecting), so the stable path always ships and you can enable one
  feature at a time on real hardware.
- Prefer **data-only** optimizations that can't crash the GPU when they exist.
  (Field: importance-prefix LOD — reordering splats by importance so any prefix
  is a valid lower-detail model — gave most of the perf win with none of
  foveation's risk. Foveation stayed flag-gated until its crash was root-caused.)
- **Foveation gotcha:** with `VK_EXT_fragment_density_map` and
  `fragmentDensityMapNonSubsampledImages` OFF, **every** attachment in the
  foveated render pass must be a subsampled image
  (`VK_IMAGE_CREATE_SUBSAMPLED_BIT_EXT`). Runtime color images get it from the
  swapchain's foveation flag automatically; your **own depth/aux images do not**
  and must set it, or the GPU page-faults mid-render (crashes only when foveation
  is on + real geometry draws).

## 10. Permissions and graceful degradation

- Hand tracking needs its runtime permission (`HAND_TRACKING`) actually
  **granted** — a denied permission returns "no hands", not an error. A hand
  menu that "doesn't show" is usually a denied permission, so **request it before
  the flow that needs it** and log the grant state.
- **Every XR capability path must fail safe.** No hands → no hand menu, but the
  screen is still fully operable by panel buttons. No device tracking → park the
  HUD at a fixed forward pose. A missing extension → the plain render path. Never
  let a DP capability gap crash the app.

## 11. The emulator lies about hands (and more)

- The **Google Aura / Android XR emulator's simulated hands do not match** how a
  real headset tracks — joint positions, handedness, and stability differ. Tune
  hand-relative placement against **real hardware**; the emulator is fine for
  compile/flow/logic but will send you chasing phantom placement bugs.
- Instrument everything with **logcat lifecycle logs** (a consistent tag +
  "[feature] STATE" lines at every decision point). A feature that silently
  early-returns (muted, permission denied, fetch failed) is undebuggable on a
  device you're wearing. The first question is always "did it even fire?" — make
  the log answer it.

## 12. Perf is a UX feature — make it visible

- Put an **FPS/HUD readout in the camera view** (a corner) on any screen showing
  point clouds / models / splats. On glasses, "is it smooth?" is a primary
  quality signal and you want it visible during every test, not buried in a log.
- Budget aggressively: a comfortable framerate matters more than detail. Splat
  scenes especially — reach a stable frame time first (LOD/prefix, then
  foveation once stable), then add fidelity.

## 13. Size everything in DEGREES, and do the arithmetic before you build

The single highest-yield habit from MeshmoreXR. Metres are meaningless on their
own; what the eye resolves is **angular size**, so derive every dimension from
the distance the thing will actually sit at.

```
size_metres = 2 · distance · tan(angle / 2)      # ≈ distance · angle_radians
usable_width = 2 · distance · tan(FOV / 2)
```

**Floors that held up on Aura-class optics:**

| Element | Floor | Basis |
|---|---|---|
| Text | **1.2°** absolute, **1.30°** house standard | you must resolve strokes to tell `8` from `B` |
| Icons / marks | **3.0°** | measured datum: ASL hand diagrams resolve finger separations at 3.25° |

⚠️ The text floor does **not** transfer to icons. Telling seven distinct
silhouettes apart is a far easier discrimination than reading a glyph, so icons
get their own floor — anchored on something you have actually confirmed on
device, not on a ratio someone liked.

### ✅ Check the layout fits *before* you build it

Three separate surfaces in one project shipped overlapping text because nobody
multiplied. One line of arithmetic finds it in seconds:

```
crown buttons, 5 labels, at the message card's distance
  0.32 m → 34° field   =  19.6 cm usable
  labels total          =  36.2 cm
  → they overlap. Always did. No amount of restyling fixes it.
```

The same sum killed the message reel's first layout (five full messages at
0.19 m each on 0.09 m centres) and the dock's permanent captions (a
9.6° caption on a 5.6° pitch). **A layout that does not fit is arithmetic, not
taste** — and it is much cheaper to discover in a calculator than on your face.

### ✅ Pick the distance for the INTERACTION, not for the anchor

A surface you point at and pinch wants to be **about an arm away (~1 m)**.
Hanging actions off an element that lives 0.3 m from the eye is uncomfortable to
aim at *and* gives you a third of the angular room. Elements can belong to each
other logically without sharing a position.

### ✅ Constant angular size beats perspective for depth

If content recedes (a thread, a corridor, a list going back in time), scale the
cap height **with distance** so every item subtends the same angle. Otherwise
the far end drops under the legibility floor and "older items are unreadable"
ships as a feature. Carry depth with position, occlusion and offset instead.

---

## 14. Gestures: make detection visible, or you will debug it blind

- ⚠️ **A gesture that fails silently gets reported as "I couldn't figure out how
  to do it", never as a bug.** Those need opposite fixes and you cannot tell
  which you have.
- ✅ **Show the detection, not just the outcome.** A live indicator that says
  "I can feel your thumb" separates *not detected* from *detected, nothing to
  do*. One line of state on screen replaced several round trips through the
  headset.
- ✅ **Undocumented gesture = absent gesture.** Twice in one project a working
  gesture was reported as missing because nothing on any surface mentioned it.
- ✅ **Draw the gesture; do not describe it.** A help row reading
  `A = FIST, THUMB ALONGSIDE` taught nobody; the drawn hand shape did. For a
  *motion* (a thumb sliding along a finger) draw the path with **arrowheads on
  both ends** if it is bidirectional — one arrowhead states a restriction that
  isn't there. And draw the hand in the pose people actually adopt (a curled
  finger, not a straight one).
- ✅ **Hysteresis is mandatory for any hand-anchored reveal.** Use two
  thresholds — reveal high, hide lower — because a single one makes the surface
  strobe as the wrist hovers at the boundary, and flicker on a hand-anchored
  element is the most nauseating failure mode available in XR. The gap is the
  feature, not tuning slack.
- ✅ **~5° minimum separation** between independently selectable hand targets.
- ⚠️ **The touch target must BE the drawn shape.** A fixed hit box under labels
  of varying width means the thing you aim at and the thing you hit are
  different rectangles — which reads as "the buttons are unreliable".

---

## 15. Rotary and paged controls

- ✅ **A clutch, not an absolute mapping.** A thumb travels ~9 cm; mapping that
  onto a full turn of a 12-position ring puts detents 7 mm apart, below what a
  thumb can reliably place. Move a fraction per stroke and let the user lift and
  re-place — the gesture a scroll wheel makes, and why a scroll wheel works.
- ⚠️ **Step through the CONTENTS, not the capacity.** A 12-slot ring holding 2
  messages stepped through all 12 positions: ten detents selected nothing and
  the display went blank, which is indistinguishable from a broken gesture. Size
  the control by what is in it.
- ⚠️ **Scale the gain to the content too.** "Half the ring per stroke" is one
  message when there are two — a full sweep of the finger to move at all, which
  reads as a control that only goes one way.
- ⚠️ **A paging control nothing invokes is not paging.** A corridor had `older()`
  written, tested and never wired to any input for weeks. Grep your surfaces for
  public methods with no callers.

---

## 16. Text that has to fit a radio, a frame, and a field of view

- ⚠️ **Word packing never reaches `cols × lines`.** A line ends when the next
  word will not fit, so a 14-column line holding `abc abc abc` wastes three
  characters. Sizing an input limit against the raw product silently drops the
  tail of long messages.
- ✅ **Mark truncation.** Losing the tail is survivable when the full text lives
  somewhere else; losing it *silently* is not — the reader sees a sentence that
  stops and cannot tell a terse message from a cut one. An ellipsis is the
  difference between "that's all they said" and "there's more of this".
- ✅ **Keep every clip in the pipeline in agreement.** A feed clipping to 12
  characters upstream of a card that holds 42 shrinks the card invisibly.
- ✅ **Show composition ceilings while composing, and enforce them at the
  source.** A limit that only greys out a counter while the recogniser keeps
  listening teaches people the limit is advisory; the truncation is then a
  surprise. Stop the input, not just the display.

---

## 17. Anything that transmits needs a second act

For any app that puts data on a shared channel — a radio, a broadcast, a group
message — this is a UX requirement, not a politeness:

- ⚠️ **Never send on the first pick.** Quick-reply buttons that transmit the
  instant they are chosen mean a pinch landing one slot off puts words on a
  shared band. Every route should produce a **draft**.
- ✅ **Make confirm its own screen with exactly two answers.** "What do you want
  to say" and "shall this go out" are different questions; a confirm step with a
  third thing to pinch is one somebody will misfire on.
- ✅ **Say what happened, in words, every time.** A mesh radio has no delivery
  receipt, so "did that send?" has no other answer.
- ✅ **Distinguish "it failed" from "it is not allowed"** and show the reason
  verbatim. Only one of those is worth retrying.
- ✅ **Enforce authorisation at the transmitter, not in the UI.** A guard living
  in a surface is one the next surface forgets.

---

## 18. Audio you can live with

- ✅ **Per-conversation, not per-app, and off by default.** One global switch
  forces a choice between a busy channel narrated at you all afternoon and the
  direct message that is the reason you are wearing the thing — and people
  resolve that by turning audio off forever.
- ⚠️ **Unprompted speech is startling in a way a visual notification is not.**
  You can look away from a light; you cannot un-hear a voice in a room with
  other people in it. Opt in, once, explicitly.
- ✅ **Say WHO before WHAT.** A disembodied sentence in your ear is worse than
  no audio.
- ✅ **Flush, don't queue.** Two messages arriving together should leave you
  hearing the newer one. A backlog you cannot skip is why people mute things.
- ✅ **Prefer on-device recognition/synthesis.** If the product's premise is
  working where there is no network, speech that needs a server fails in exactly
  the conditions the product exists for.
- ✅ **Ask for the microphone at the moment of speaking**, never at startup. A
  mic prompt on first launch reads as the app wanting to listen to the room.
- ✅ **A repeating tick must be the least eventful sound you own.** A detent tone
  fires six times a second during a scrub; a sound that is satisfying once is
  intolerable at that rate.

---

## 19. Recurring failure shapes worth naming

Each of these bit more than once across two apps:

- **Two writers on one value.** A veil, a caption, a focus flag — one owner,
  resolved once per frame, announced once. Symptoms are flicker and repeated
  sounds, and it is never where you first look.
- **Empty is a state, not an absence.** A surface gated entirely on having
  content draws *nothing* when empty, which from the outside is exactly what a
  broken surface looks like. Say "no messages yet".
- **Persistence is not optional just because nobody wrote it yet.** An in-memory
  log dies with the process, and XR apps are killed by the system far more often
  than they are closed by a person. Write on arrival, not in `onDestroy`, and
  never re-announce restored history — it rings every arrival channel for things
  the user read yesterday.
- **Toggle labels must read as state.** `VOICE OFF` looks like a button that
  turns voice off; `VOICE: ON` reads as the switch it is. And **name what it
  acts on** — "VOICE ON FOR THIS" leaves the user guessing what "this" was.
- **Measure, don't reason.** Every long-lived bug in both projects was closed by
  drawing what the code believed or logging a number, not by thinking harder
  about what it should be doing.

---

---

## Quick checklist for any new XR surface

- [ ] Audible **and** visible feedback on every interactive element
- [ ] Hand/head-locked UI: position from the anchor, **orientation from the head**
- [ ] Offset hand UI ~6 cm toward the eye; solid fills, not thin rings
- [ ] Paint your own panel backing (don't assume transparency)
- [ ] Pose world-derived transforms in `REAL_WORLD`
- [ ] All ARCore acquisition off the main thread; configure once; superset config
- [ ] Fail safe when a capability/permission is missing
- [ ] Native exit via `xrRequestExitSession` drain; risky GPU features flag-gated OFF
- [ ] Lifecycle logging on a consistent tag; validate hand placement on real hardware
- [ ] Perf HUD visible wherever heavy content renders
- [ ] Display technology identified; `[VIDEO]` vs `[ADDITIVE]` rules chosen (§0)
- [ ] Every size derived from **distance × angle**; text ≥1.3°, icons ≥3.0°
- [ ] Layout width summed against the usable field **before** building it
- [ ] Pointable surfaces at ~1 m, not hung off a close anchor
- [ ] Hit volume identical to the drawn shape
- [ ] Hand-anchored reveals use two thresholds (hysteresis)
- [ ] Gesture detection visible, and the gesture drawn in Help
- [ ] Nothing transmits without a draft and a two-answer confirm
- [ ] Audio opt-in per conversation; ask for the mic at point of use
- [ ] Truncation is marked; clip limits agree end to end
- [ ] Empty states say something

---

### Field sources
- **RobotARme** (2026-07) — video passthrough, Compose spatial + native
  OpenXR/Vulkan. §§1–12.
- **MeshmoreXR** (2026-08) — Xreal Aura, additive optical see-through,
  SceneCore + ARCore hands, LoRa mesh companion. §0 and §§13–19.

### See also
- `AndroidXR_Glasses_Dev_StarterGuide.md` — toolchain, APIs, and the
  device-proven SceneCore rendering rules (§4a) behind §0 here.
- `UX-XR-best-practices.md` — the WebXR/three.js stack, plus TUI and web.
