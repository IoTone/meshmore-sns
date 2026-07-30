# MeshmoreXR — Design Brief

**Offline first · Always-on mesh · Online superpowers**

A native Android XR client for the MeshCore LoRa mesh, built for optical
see-through glasses (Xreal Aura class). Package root `com.iotj.meshmore.xr.*`.

> Status: **proposal for review.** No production Android code exists yet. A
> working Three.js prototype of the spatial widget layer, the symbology, the
> HUD and the nine themes lives in `airspace-ui/` — it exists to test this
> document, and has already falsified several parts of it.
>
> The purpose of this brief is to fix the paradigm, the surface set, and the
> nine themes so a default can be chosen and one theme driven top-to-bottom.
>
> **Companion documents:** `AiRspace-UI.md` (the widget library) ·
> `AiRspace-HUD-and-symbology.md` (volumetric primitives, HUD, MICROHUD
> geometry) · `MeshmoreXR-audio-haptics.md` (16-event taxonomy × 9 packs) ·
> `MeshmoreXR-i18n-ja.md` (Japanese/English) · `MeshmoreXR-themes.html`
> (visual theme picker).

---

## 0. The one-paragraph brief

You are wearing glasses. The mesh is *already on* — it has been on since you put
them on, and it will stay on when the internet does not exist. The room around
you is annotated with the people and things on your mesh, at their true
bearings, at their true distances, whether or not you are looking at them. You
do not open an app to see the mesh; you turn your head. When broadband appears,
the world gains detail it could not otherwise have — real terrain under the
pins, centimetre-accurate shared anchors, a voice note instead of 140 bytes of
text — and when broadband leaves, all of that degrades to the mesh baseline
without a single dialog, error, or dead control. **Nothing that works offline
may ever stop working when connectivity drops.**

---

## 1. What changed from Meshmore SNS (read this first)

Three corrections to the working assumptions behind this project. Each one
changes the plan.

### 1.1 The Java port is already done

The brief said "the libmeshmore api should be ported to Java." It already is,
and it is better than a fresh port would be:

| Module | What it is | Reuse verdict |
|---|---|---|
| `libmeshcore/` | Pure-Java (`io.iotone.meshcore`), Java 17 records + sealed types. Frame codec (total — never throws), CayenneLPP, `ChannelCrypto`/`DmCrypto`/`IdentityCrypto`, `MeshcoreTransport` SPI. Validated against the same JSON golden vectors as the Dart reference → provably byte-identical. 98 tests. | **Consume as-is** via composite build. Zero port work. |
| `libmeshcore-android/` | `AndroidBleTransport` (Nordic BLE 2.10.1), `MeshcoreSession` (handshake → drain → dispatch), `SessionListener`, `SessionState`. `minSdk 26`, `compileSdk 35`. README already says "Android/**AndroidXR**". | **Consume as-is.** Raise `compileSdk` to 36 for XR alignment. |

Implication: **there is no JNI case for the protocol layer.** It is pure Java,
its symmetric crypto is `javax.crypto` (hardware-backed on device), and its
Ed25519/X25519 is BouncyCastle's lightweight math API used *without* JCE
registration so it coexists with Android's provider. A JNI rewrite would add
crash surface and lose the golden-vector guarantee. Don't.

The two places native code genuinely pays are named in §6.4.

### 1.2 The XR SDK moved — the starter guide's snippets are stale

Verified against the release notes on 2026-07-30:

| Artifact | Latest | Released |
|---|---|---|
| `androidx.xr.scenecore:scenecore` | **1.0.0-beta01** | 2026-07-15 |
| `androidx.xr.arcore:arcore` | **1.0.0-beta01** | 2026-07-15 |
| `androidx.xr.runtime:runtime` | **1.0.0-beta01** | 2026-07-15 |
| `androidx.xr.compose:compose` | **1.0.0-alpha16** | 2026-07-15 |

> **"Developer Preview 4" vs. these versions — they are different clocks.**
> DP4 is the *SDK bundle* branding and shipped **2026-05-19** (which is also
> when `xr.compose` alpha14 landed). The individual `androidx.xr.*` artifacts
> then kept their own cadence: alpha15 on 06-17, and on **07-15** the three
> core libraries went to **beta**. So targeting the table above is **two release
> waves ahead of DP4**, not behind it. Quote artifact versions in this project,
> not the DP number.

**Tooling:** Android XR tools ship only in **Android Studio Canary**
(stable/preview channels may not include them), plus latest Build-Tools,
Emulator, Platform-Tools and *Layout Inspector for API 31–36*. Already-installed
SDK tools must be **re-selected and re-applied** to actually update.

> ⚠️ **Do not let Canary set `JAVA_HOME`.** Canary's bundled JBR can be Java 25,
> which AGP and the Kotlin plugin reject (`IllegalArgumentException: 25.0.2`).
> Use Canary for XR tooling but keep the build pinned to the **stable** Studio's
> JBR 17 (`/Applications/Android Studio.app/Contents/jbr/Contents/Home`), per
> §6.2.

Breaking changes since the guide was written — budget for these on day one:

- **`Session.create` is now a suspend function.** The guide's
  `(Session.create(activity) as? SessionCreateSuccess)?.session` pattern is
  gone. This is *good*: it kills the guide's own §6 warning about blocking IPC
  on the main thread by making it structurally impossible.
- **`AnchorEntity` → `AnchorSpace`.** Renamed.
- **`movable()` / `transformingMovable()` deprecated** → single `movePolicy`
  parameter; two resize modifiers collapsed into one `ResizePolicy`.
- **`TrackingState` is an enum now**, not ints; `TRACKING_DEGRADED` removed
  from public API.
- **New and directly useful:** `QrCode` detection (alpha15) — this is our
  contact/channel-key exchange mechanism, see §5 S2. `Geospatial` /
  `GeospatialSurface` — this is Tier-2 shared world anchors, see §3.
  `XrLog` — adopt as the single logging tag per the guide's §9.

Three of four artifacts are at **beta**, not alpha. The API churn is largely
behind us; this is a better moment to start than three months ago.

### 1.3 On see-through glasses you cannot draw dark — you can only add light

This is the single biggest reason the six SNS themes cannot be ported, only
re-cast. An optical see-through display is **additive**: the panel emits light
that sums with the real world. **`#000000` renders as perfectly transparent.**
Every SNS theme is "hi-vis on near-black" — and on glasses that near-black
ground is *nothing at all*. The theme evaporates and you are left with only the
lit marks, floating over an uncontrolled, possibly sunlit backdrop.

So MeshmoreXR has **two rendering substrates with opposite contrast physics**,
and every theme must specify both:

| | **Panel substrate** | **Additive substrate** |
|---|---|---|
| What | `SpatialPanel` / `PanelEntity` — a real rendered quad | glTF geometry, particles, lines in open space |
| Physics | Surface actually renders. Dark backgrounds work. | Black = invisible. Only emissive marks read. |
| Contrast from | Ink on a painted ground (the 2D language survives) | Luminance headroom + the device dimmer |
| Trap | Panels are **not** alpha-transparent — undrawn pixels show raw grey. **Paint your own backing.** (field-confirmed) | A "dark halo" cannot subtract real-world light. Use a **bright keyline**, not a dark one. |

The field note in `AndroidXR_Glasses_UX_Best_Practices.md` §4 ("give small UI a
dark halo") is correct **for the panel substrate** and does not transfer to the
additive substrate. Both notes are right; they describe different surfaces.

This gives us the primary axis for organizing the nine themes (§7): each is
**PANEL-LED**, **ADDITIVE-LED**, or **HYBRID**. A theme's substrate class
predicts its sunlight legibility, its GPU cost, and how much of it survives a
bright afternoon.

---

## 2. The paradigm: the room is the UI

> "We don't intend to ever position anything in the user's view the way we would
> in a mobile app staring at lists. We need a new paradigm."

Agreed, and here it is. **Five spatial zones**, each with a fixed anchoring rule
and a fixed job. Every surface in §5 is composed only from these zones. Nothing
in MeshmoreXR is allowed to be "a screen."

```
                    plan view — you at centre, facing north
                    ────────────────────────────────────────

                              ·  HORIZON  ·
                   ·                                   ·
              ·          ╭─────────────────╮                ·
                         │                 │
         ·               │     FOCUS       │                     ·
                         │   (1.2 m,       │
                         │  world-locked)  │
         ·               ╰─────────────────╯                     ·
                                 △  ← EDGE (head-locked, viewport rim)
              ·             ▓▓▓▓▓▓▓                        ·
                            ▓ YOU ▓
                   ·        ▓▓▓▓▓▓▓                   ·
                          ◉ ← HAND (palm, 6 cm toward eye)
                              ·           ·
                    ┌───────────────────────────┐
                    │   GROUND (floor plane,    │
                    │   walk-around map table)  │
                    └───────────────────────────┘
```

| Zone | Anchor rule | Job | Never |
|---|---|---|---|
| **HORIZON** | Body-locked, **yaw-only**, r ≈ 2.5 m, at/just below eye level, full 360° | The always-on mesh. Every node sits at its **true bearing**. The resting state of the app. | Never enters the forward FOV as a wall of content. Never scrolls. |
| **FOCUS** | World-locked at ~1.2 m, spawned along current gaze, user-movable, explicitly dismissed | Exactly **one** thing you selected. The only place dense text is allowed. | Never more than one at a time. Never auto-spawns. |
| **HAND** | **Position** from hand joint, **orientation from head**, offset ~6 cm along the hand→head vector | Persistent status + the 3–4 controls you reach for constantly. | Never composed with the hand's rotation (foreshortens to a sliver — field-confirmed). |
| **EDGE** | Head-locked at the outer viewport rim, ~0.8 m | Transient progress and alerts only. Auto-dismisses ≤ 3 s after terminal state. | Never load-bearing. Never the only record of anything. |
| **GROUND** | World-locked to the detected floor plane | The map table. Walk around it, crouch to it, reach into it. | Never follows the user. |

### 2.1 The five paradigm rules

1. **Bearing is the primary index, not order.** A node is not row 7 of a list;
   it is 40° to your left at 300 m. Sorting is a Tier-2 luxury, never the
   primary access path.
2. **The forward FOV belongs to the world.** The target optic is **70°
   diagonal** (XREAL Aura class, FHD 16:9) ≈ **61° H × 34° V** — nearly double
   the horizontal budget the earlier field notes assumed. The temptation that
   creates is exactly the wrong instinct: *more room does not mean more UI, it
   means a bigger protected world window.* HORIZON lives at and below eye level
   and thins to nothing in the centre-forward arc; the HUD reserves a
   **34° × 20°** centre in which nothing persistent may ever appear.
   See `AiRspace-HUD-and-symbology.md`.
3. **One FOCUS at a time.** Every additional floating panel is a step back
   toward the phone. Selecting a second thing replaces the first.
4. **Everything reachable without turning around.** See §8.2 — position must
   never be the *only* channel, both for accessibility and for seated use.
5. **Glanceable in under one second, or it belongs in FOCUS.** If a state can't
   be read from HORIZON or HAND in a glance, it is not ambient information.

---

## 3. Connectivity tiers — the spine of the whole design

Three tiers. The tier is **always visible**, in every theme, in a way that is
never a modal, never an error, and never blocks anything.

| | **TIER 0 — DARK** | **TIER 1 — MESH** | **TIER 2 — UPLINK** |
|---|---|---|---|
| Have | Glasses only | Glasses + BLE radio | Glasses + radio + broadband |
| The mesh | Last known, frozen, honestly timestamped | **Live** | Live |
| Messaging | Read history; compose and **queue** | Send/receive text, channels, DMs | + voice notes, images, translation |
| Map | Cached PMTiles + dropped pins | Same + live node positions | + region download, terrain, VPS anchors |
| Voice | Offline STT + offline TTS | Same | + high-quality cloud STT/TTS, EN↔JA |
| Feels like | A field notebook | **Home** | A field notebook with a satellite |

**The invariant:** Tier 2 is *purely additive and always revocable*. Every Tier-2
feature must define its Tier-1 degradation at design time, and the degradation
must be a **quiet reduction in fidelity, never a failure**. Concretely:

- Cloud STT unavailable → Vosk transcribes locally. The user sees a slightly
  different confidence treatment, not an error.
- VPS anchors unavailable → pins fall back to local plane anchors + GPS. They
  move a little. They do not disappear.
- Terrain tiles unavailable → the GROUND table renders the cached basemap at
  whatever zoom was last downloaded, with an honest edge-of-data boundary.

**Anti-pattern, explicitly banned:** a "you are offline" screen, toast, or
overlay. Offline is the *design centre*, not an exception. The tier indicator
is a state, drawn with the same visual weight at all three levels.

### 3.1 What "online superpowers" actually buys us

Ranked by how much they justify the tier at all:

1. **Region basemap download** (PMTiles) — grab a 200 MB region on hotel wifi,
   then have full offline vector cartography forever. The single highest-value
   Tier-2 action.
2. **ARCore Geospatial / VPS anchors** — pins that are centimetre-accurate and
   *shared across users' devices* at the same real location. Impossible on mesh
   alone (mesh gives you ~GPS accuracy at best).
3. **Off-mesh payloads** — a 3-second voice note or a photo, relayed by URL
   reference. LoRa physically cannot carry these; the mesh carries the pointer.
4. **Translation EN↔JA** on message send/receive.
5. **Mesh↔internet bridge** — relay a mesh message out to SMS/Matrix for someone
   not on the mesh.
6. **Radio firmware OTA** + authoritative time sync.
7. **Traffic summarization** — "what happened on the mesh while I was asleep."
   On-device Gemini Nano where available; cloud otherwise.
8. **R26 XR data streaming** via the private temp-URL reverse proxy already
   spec'd in `meshmore-sns-spec.md`.

---

## 4. Symbology — one primitive set, nine restylings

Same discipline as `brand/_gen.py`: **one mark system, restyled per theme.** But
the XR primitive set is chosen for a hard physical constraint: *thin strokes
foreshorten into broken arcs when viewed off-axis* (field-confirmed — the "1/5
of a red semicircle" bug was a white ring around a dot; a solid disc fixed it).

**Seven primitives. All foreshorten-proof — and all genuinely volumetric.**
Geometry alone is not enough: an unshaded sphere is a flat circle. Every
primitive carries a fixed-direction lambert body term plus a view-dependent
fresnel rim. Full rationale in `AiRspace-HUD-and-symbology.md` §1–2.

| Glyph | Form | Means | Rule |
|---|---|---|---|
| **MOTE** | **Fresnel-shaded sphere** | One node | ≥ 0.6° angular. An *unshaded* sphere renders as a flat circle — the rim term is what makes it read round. |
| **HALO** | **Torus** | Range ring / geofence | Tube ≥ 0.25° angular. **Never a `RingGeometry` annulus** — that is a flat disc with a hole, and it collapses to a line at a grazing angle. |
| **SPUR** | **Three concentric additive tubes** (core / glow / halo) | A link, a path, a bearing ray | **Never `LineBasicMaterial`-class 1px lines.** Core ≥ 6 mm, halo ≥ 45 mm — under ~1 cm is invisible in bright passthrough. Drawn from a point *in front of* the user, never from the eye. |
| **SHARD** | **Bevelled box**, real thickness, lit edge; text insets into its face | Any text surface | The volumetric replacement for a panel. Paint the backing — panels are not alpha-transparent. |
| **CARET** | **Cone** | Direction / bearing-to / elevation | A flat triangle disappears edge-on; a cone points in real 3D from every angle. |
| **PULSE** | **Expanding torus, tube thins as it grows**, ≤ 700 ms | A packet event — RX, TX, advert | The one motion primitive. Scaling the whole mesh inflates the band into a donut; thin the tube so it reads as a shockwave. Must respect reduce-motion. |
| **BAR** | **Extruded box segments** | RSSI, SNR, battery, queue depth | Segmented, never continuous — readable at a glance without a scale, and legible at an angle. |

**Universal rules, all themes:**

- Orientation from the **head**, position from the anchor. Always.
- World-derived poses go in **`Space.REAL_WORLD`**, never `Space.ACTIVITY` — a
  movable panel carries a ~1.75× parent scale that corrupts them.
- Every interactive element: **visible cue AND audible cue AND haptic**, all
  three, always. Hover state must be dramatic — a 15% opacity bump is invisible
  through passthrough. Minimum: opacity 70→100%, bright keyline appears, scale
  1.0→1.05.
- **Solid fills over outlines**, everywhere, at every size.

### 4.1 Type

Same license constraint as SNS: reference faces (Eurostile, Matisse EB,
Helvetica, Futura) are **inspiration only**; we bundle OFL/MIT families with
full Japanese coverage. XR adds one hard rule the 2D app did not have:

> **No text below 1.2° of visual angle**, ever, in any theme, at any distance.
> At 1.2 m that is ≈ 25 mm cap height. This is roughly 3× what a phone
> designer's instinct produces, and it is the most common reason XR text is
> unreadable.

Carried forward: **Saira / Saira Condensed** (Eurostile-class squared display),
**Departure Mono** (pixel-mono telemetry, sizes locked to multiples of 11),
**M PLUS 1 Code** (the linchpin — techno monospace *with full Japanese*, covers
console + JA L10n + kanji-as-graphic in one OFL family), **Michroma / Orbitron**
(race-team geometry). New for XR: **Nova Square** and **Syncopate** for the
vector theme, **Outfit** and **M PLUS Rounded 1c** for the organic theme.

---

## 5. The surfaces

Not screens. Thirteen **surfaces**, each a composition of zones from §2. `S1` is
the resting state; everything else is entered from it and returns to it.

Two elements are **persistent chrome** rather than surfaces — the **MICROHUD**
and the **HAND MENU** — and are specified after S12.

---

### S0 · FIRST LIGHT — onboarding, permissions, calibration

**Zones:** EDGE (guidance) → world-space calibration → HAND (first contact)

The first-time XR user is the hardest user; most have never used XR. This
surface teaches the paradigm by *doing it*, not by explaining it.

1. A single **MOTE** appears at arm's length. "Touch it." That is the entire
   first instruction — it teaches gaze + pinch + confirms hand tracking works,
   with audible + visible + haptic confirmation.
2. Floor plane detection, narrated in-environment: *"look down, then slowly
   look around."* Live coverage readout, never a bare spinner.
3. Permissions requested **just in time and each with a stated why**:
   `HAND_TRACKING` (the palm console), `BLUETOOTH_*` (the radio),
   `ACCESS_FINE_LOCATION` (your own position on the mesh), `RECORD_AUDIO` (only
   when the user first reaches for voice).
4. HORIZON initializes empty and honest: *"no radio linked."*

**Fail-safe:** every permission denial has a working path. No hand tracking →
gaze + head-dwell selection and everything reachable from a FOCUS panel. No
location → mesh-relative bearings only, GPS panel says so plainly.

---

### S1 · HORIZON — the always-on mesh *(home; not a screen)*

**Zones:** HORIZON + HAND. This is the app's resting state and where the user
spends 90% of their time.

```
                plan view — 12 nodes, true bearings, distance = radius
                ─────────────────────────────────────────────────────

                        kanako.1 ●              ● relay-nw
              ·                                              ·
       davi1 ●          ╭ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ╮
                        ╎ forward FOV 61°×34° ╎          ● t1000-e
   ·                    ╎  DELIBERATELY       ╎                    ·
                        ╎  KEPT CLEAR         ╎
       hab-2 ●          ╰ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ╯      ● gate-cam
                                 ▓▓▓▓▓
              ·                  ▓YOU▓                       ·
                                 ▓▓▓▓▓
                        ◉ palm: TIER · PEERS 12 · CH0 · MUTE
                   ·                                    ·
              ● shed              ● (stale, 40 m ago)      ● ridge
                        ▁▁▁▁ HALO: 100 m · 1 km · 10 km ▁▁▁▁
```

- Each peer is a **MOTE** at its true bearing. Radius maps distance across three
  **HALO** range bands (100 m / 1 km / 10 km, log-compressed).
- **Recency is brightness.** A node heard 5 seconds ago is at full luminance; at
  30 minutes it is a dim ghost with a visible age label on gaze. Staleness is
  never hidden.
- **PULSE** on every RX/TX — the mesh visibly breathes. This is the "always-on"
  made perceptible, and it is the single most important wow moment in the app.
- Nodes with no position estimate park in a **dedicated unlocated arc** behind
  the user's dominant shoulder, at a fixed bearing, clearly marked as
  "bearing unknown" — never faked into a plausible-looking wrong direction.
- **Palm console (HAND):** tier indicator, peer count, active channel, mute.
  Four controls, all solid spheres/discs, all reachable one-handed.

**Interaction:** gaze a MOTE → it swells + audible cue; pinch → S3 FOCUS.

**Tier behaviour:** T0 — every MOTE renders as a ghost with a frozen timestamp.
T1 — live. T2 — MOTEs gain VPS-accurate placement where available.

---

### S2 · LINK — companion radio pairing

**Zones:** FOCUS (one panel) + EDGE (progress)

The one surface where a conventional panel is correct: it is a one-time,
text-heavy, dense-information task. Wraps `AndroidBleTransport` +
`MeshcoreSession`'s `DISCONNECTED → CONNECTING → HANDSHAKING → READY`.

- Discovered radios as a short list of **SLABs** (this is a list, and that is
  fine — it is bounded, transient, and never the home surface).
- `CMD_APP_START` → `RESP_CODE_SELF_INFO` handshake shown as literal steps with
  step semantics (`STEP 2/4`), never a spinner.
- **Use the new `QrCode` API here.** Contact and channel-key exchange by
  looking at a QR code on another operator's phone or a printed card is
  dramatically better than typing a base64 key in XR. This is the strongest
  single argument for being on `arcore:1.0.0-beta01`.
- Auto-reconnect with backoff is silent and ambient — a palm-console state
  change, never a modal.

**Fail-safe:** BLE off / denied → the app still opens at Tier 0 with full
history, map, and pins. The radio is a peripheral, not a prerequisite.

---

### S3 · NODE FOCUS — one peer

**Zones:** FOCUS + a persistent **SPUR** from the user to the node's true bearing

Selecting a MOTE spawns exactly one FOCUS panel at 1.2 m along gaze — and, more
importantly, paints a **SPUR** through the real world toward that node. The
panel is reference; the spur is the actual answer to "where are they?"

Contents: callsign · distance estimate · bearing · RSSI/SNR **BAR**s · battery ·
last-heard age · path (direct / N hops) · actions [DM] [PIN THEIR POSITION]
[FAVOURITE] [MUTE].

**Tier:** T1 gives RSSI-derived distance with honest error bounds. T2 adds a
true-position fix and a terrain-following spur that drapes over the actual
ground rather than pointing through a hill.

---

### S4 · SPEAK — messaging, voice-first

**Zones:** HAND (REEL triage + push-to-talk) + FOCUS (full thread) + EDGE (send
state)

Typing in XR is miserable. Voice is the primary input; text is the fallback.

- **Push-to-talk is an explicit, physical gesture** — press and hold the palm
  console sphere. **Never always-listening.** The mesh is always on; *the mic
  never is.* State this in the product copy — it is a trust feature.
- STT transcribes live into a **SLAB** above the palm. Release → review →
  confirm. Never auto-send.
- **Two reading layers, two jobs.** *Triage* happens on the hand: turn the chat
  palm up and the **REEL** appears — an oval ring buffer of the last ~12
  messages, rotated with thumb-along-index, ~5 legible across the front arc.
  *Reading* happens in FOCUS: the full thread is a **vertical spatial stack** at
  ~1.2 m, newest at eye level, older messages receding upward and back in depth.
  You look up to read history rather than scrolling.
- The reel is a **view of the last N, never the archive** — the shape is a ring
  buffer and it says so honestly. "Older" hands off to the FOCUS thread.
- **Per-message actions are a CROWN** spawned around the selected slot: Reply ·
  Read aloud · Copy · Delete here · DM sender · Pin sender's location.
  **"Delete here" is local-only and the label must say so** — there is no unsend
  on a mesh, and a plain "Delete" invites the belief that a packet already
  relayed through nodes we will never speak to again has been recalled.
  (R20 carried forward from SNS, with the wording tightened.)
- TTS reads incoming messages when enabled, **off by default**, with the
  message text always visible — spoken content always has a visible transcript.
- Sender identity is carried by **theme livery** (per-channel accent, §7), not
  by an avatar.

#### Arrival — four channels, none of them load-bearing alone

A message landing fires all of these at once, and the design survives losing any
one of them:

| Channel | What happens |
|---|---|
| **Audio** | `E10 MSG_CHANNEL` / `E11 MSG_DIRECT`, **spatialized to the sender's bearing** (audio spec §4) |
| **CUFF** | The wrist ring lights — a single arc segment for a channel message, the **whole cuff pulsing** for a DM |
| **MICROHUD** | The unread counter increments in the bottom band |
| **EMBER** | A mote at the viewport edge on the sender's bearing, decaying over ~3 s |

Nothing appears in front of your face, and nothing demands acknowledgement. The
mesh is ambient; you look when you choose to.

**Channel vs. DM is distinguished by form in every channel** — a different
interval in audio, a different cuff geometry, a different MICROHUD glyph — and
never by colour alone.

**Tier:** T0 composes and queues, with the queue depth on the palm **BAR**.
T1 sends text. T2 adds voice notes, images, and inline EN↔JA translation.

---

### S5 · CHANNELS — bands, not tabs

**Zones:** HORIZON (a second concentric band) + HAND

Channels are rendered as **arcs of the HORIZON above the node band** — each with
its own livery accent (the Wipeout fictional-corporate-identity idea, applied
spatially). Turn your head to a channel arc, pinch, and it becomes the active
channel; its colour immediately re-tints the corresponding MOTEs.

Per channel: unread **BAR**, TTS toggle, notification level, mute. Anonymous /
public channel gets a distinct ripple treatment inherited from the SNS grid.

---

### S6 · TERRAIN — floor-scale maps

**Zones:** GROUND (hero) + FOCUS (pin detail)

#### S6.0 · What actually ports from Meshmore SNS — and what must not

The SNS map is **not offline**, and porting it as-is would carry that forward:

| SNS asset | Offline? | Port verdict |
|---|---|---|
| `assets/data/cities15000.bin` — GeoNames, 812 KB, CC-BY 4.0, 1° bucket reverse-geocode, <1 ms | **Yes, genuinely** | **Port as-is.** Proven, tiny, already licensed and attributed |
| `assets/data/world-110m.geojson` — Natural Earth, 97 KB | **Yes** | Port for GLOBE scale |
| `street_map_view.dart` — `flutter_map` → `tile.openstreetmap.org` / `opentopomap.org` | **No.** No tile-cache package in `pubspec.yaml`, no tile store in `lib/`; `NetworkTileProvider` caches in memory for the session only | **Do not port.** Replace with PMTiles |
| R25 equal-grid view | n/a | **Do not port** — see below |

Two reasons the tile approach cannot simply be given a cache:

1. **The OSM tile usage policy forbids bulk downloading and prefetching.**
   R25's proposal to "pre-pull tiles for the area surrounding our location and a
   ring of N km out" would violate it. That is not a licence detail to sort out
   later; it invalidates the strategy.
2. Raster tiles are the wrong substrate for a 3D table anyway — we need vector
   geometry we can drape over relief, and elevation we can turn into a mesh.

**PMTiles is the correct answer** and was already the recommendation in §6.3: a
single file, range-read off device storage, no server, explicitly designed for
exactly this.

**R25's equal-grid map does not port, and should not.** Equal-area cells exist
because a phone screen is small and you need comparability between buckets. At
floor scale you have a real map and real space, so the abstraction has nothing
to buy. Its three *purposes* survive in better form: density collapse becomes
marker clustering, cell labels come from the ported gazetteer, and its type
glyphs (dot = companion, triangle = repeater) are already unified into the
MICROHUD symbology table. **Port the purpose, not the workaround.**

#### S6.1 · The scale ladder

One map, three scales, continuous between them — never a modal switch.

| Scale | Form | Span | Where you are |
|---|---|---|---|
| **TABLE** | ~1.2 m across, waist height | 100 m – 5 km | Outside it. Walk around, crouch to it, reach in |
| **FLOOR** | the room itself, projected on the actual floor | 1 – 50 km | **Standing on your own position** |
| **GLOBE** | ~0.8 m sphere at waist height | planetary | Outside it (R27, ported) |

Two-handed spread moves continuously along the ladder. TABLE grows until its
edges pass you and it becomes FLOOR; FLOOR shrinks and lifts to become GLOBE.

#### S6.2 · FLOOR scale is the hero, and it is bearing-locked

At FLOOR scale the map is drawn on the real floor at 1:N with **true north on
the map aligned to true north in the room.**

That single constraint makes everything agree:

- A node's position on the floor is at the **same bearing** as its MOTE on the
  HORIZON and its marker on the MICROHUD ribbon. Three representations, one
  direction. Look down at the floor, then up at the horizon — the same peer is
  in the same place.
- **Walking is panning.** Two metres north across the room is 2 m × N north on
  the map. You navigate the map with your feet.
- Turning to face something on the floor turns you to face the real thing.

This is the map view that cannot exist on a phone, and it is why floor-scale is
worth building rather than just making the table bigger. The map must therefore
**never auto-rotate to heading-up** — north-up is not a preference here, it is
the mechanism.

#### S6.3 · Terrain in three dimensions

Relief is real geometry, not a shaded texture: the DEM becomes a mesh the table
carries, and nodes stand at their true altitude above it.

- **Vertical exaggeration is mandatory and must be labelled.** At 1:10 000 real
  terrain is nearly flat — a 300 m hill is 3 cm. Default exaggeration **2.5×**,
  adjustable. It is printed on the map edge (`V×2.5`) at all times, because
  **unlabelled vertical exaggeration is a lie about the terrain**, and this is a
  navigation instrument people may make route decisions with.
- **Low-power themes get contours, not a mesh.** RECON AMBER and TERMINAL VOID
  render contour lines derived from the same DEM: no mesh, no shading, no
  normals. Consistent with the low-power claim (`AiRspace-UI.md` §5).
- Terrain is **draped** with the vector basemap, so labels and roads follow the
  relief rather than floating flat above it.
- Nodes as **MOTE**s standing above the surface; the stalk length encodes
  altitude uncertainty, so a node with no altitude fix visibly floats rather
  than pretending to sit on a hill.

#### S6.4 · Pins, geofences, and clustering

- Pins, waypoints and geofences from `lobospeak-mappins-spec.md` render here
  natively — this surface is where that spec finally has a good home. Geofence
  polygons are extruded volumes, not outlines (L2).
- **Clustering** replaces R25's density collapse: above ~8 markers within a
  screen-space threshold, collapse to a single volumetric badge carrying the
  count and the dominant role glyph. Gaze it to expand in place.
- Two-handed grab to pan / zoom / rotate about the vertical axis only — **never
  tilt**. Tilting a floor-anchored map breaks the bearing lock in §6.2.

**Tier:** T0/T1 — cached packs, with an **honest edge-of-data boundary** where
the region ends: the map visibly stops rather than fading into a plausible
blank. T2 — region download, higher-resolution DEM, imagery drape.

---

### S7 · WAYFIND — navigation painted on the real world

**Zones:** world-space **SPUR** + minimal EDGE

Choose a node or pin → the route is painted **on the actual ground in front of
you** as a series of world-anchored CARETs and a SPUR, following the terrain.
No minimap. No turn-by-turn card in your face. Distance-to-target lives on the
palm.

This is the clearest expression of the paradigm: the navigation UI *is the
street*.

**Tier:** T1 — straight-line bearing + distance, honestly labelled as
as-the-crow-flies. T2 — actual routed path over real terrain, VPS-corrected.

---

### S8 · PINS & TRIGGERS — drop a thing in the real world

**Zones:** world-space placement + FOCUS (authoring)

Point, pinch, drop a pin **where you are actually standing**. Name it by voice.
Optionally attach a rule from `lobospeak-mappins-spec.md` §5 (templates first,
DSL never — the templates were the right call).

Rule authoring is the one genuinely dense task in the app and gets a full FOCUS
panel with no apology. Everything else is spatial; this is a form, and forms are
fine when they are rare, bounded, and explicitly entered.

**Safety:** trigger rules that command physical things (the lobospeak robot
case) require explicit confirmation with a distinct, unmistakable audible +
visible + haptic signature that is *identical across all nine themes*. Safety
signals are not themeable.

---

### S9 · TELEMETRY — radio config and diagnostics

**Zones:** FOCUS (multi-tab panel)

Device identity, advert name, advert lat/lon source (none / pinned / device
GPS), radio params (freq, SF, BW, CR, TX power), battery, and the bounded
**RAW FRAME LOG** (R23) — which on glasses becomes genuinely great: a scrolling
column of decoded frames anchored beside you while you walk around the radio.

Also hosts the **perf HUD** (FPS, frame time, node count, draw calls) — always
available, on by default in debug, because on glasses "is it smooth?" is a
primary quality signal.

---

### S10 · UPLINK — the superpowers surface

**Zones:** FOCUS

The only surface that is *about* connectivity. Shows the current tier, what is
unlocked, and what is queued for the next uplink window. Actions: download
region basemap, sync queued voice notes, pull firmware, resolve VPS anchors.

**Design rule:** this surface makes Tier 2 feel like a *supply drop*, not a
requirement. Framing throughout is "what you can grab while you're here," never
"what you're missing." Copy discipline matters more than pixels on this one.

---

### S11 · THEME & VOICE — identity picker

**Zones:** HORIZON (live preview) + FOCUS (controls)

Theme switching previews **live on the actual HORIZON**, not in a swatch. You
see your real mesh restyled in place, hear the theme's audio pack fire on a
sample event, and feel its haptic signature. Pick by living in it for five
seconds.

Also: TTS voice + rate, audio pack on/off (independent of TTS), haptic
intensity, **visual + haptic only** mode, reduce-motion, text scale, seated
mode, EN/JA.

---

### S12 · ABOUT · TERMS · SAFETY

**Zones:** FOCUS

R9/R10 carried forward, plus XR-specific safety copy: do not use while driving,
be aware of your surroundings, the passthrough is not a substitute for looking,
and a plain statement of the mic policy from S4.

---

### MICROHUD — persistent chrome across every surface

**Zone:** EDGE (head-locked, rigid). Present on **all** surfaces, at all three
tiers, in all nine themes.

The MICROHUD is the default HUD. It is two thin bands that **bracket** the world
window — a compass ribbon above, connected-node stats below — and nothing else.
The earlier full HUD's left and right rails are folded into the bottom band and
demoted to an optional FULL density for stationary diagnostic work.

```
   ── FOV top edge ────────────────────────────────────────────────  +17.0°
                        (safe-area gap — nothing here)
   ┌──────────────────────────────────────────────────────────────┐ +15.1°
   │  1.2k    340         2.4k                                    │  distance
   │   ▮       ●           ◆              ⬢          ●            │  markers
   │ ──┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼── │  ticks
   │  030     045      060     075      NE      105     120       │  bearings
   └──────────────────────────────────────────────────────────────┘ +11.9°
                                                                    
                    W O R L D   W I N D O W                          ±10.0°
                34° × 20° — NOTHING PERSISTENT, EVER                 
                                                                    
   ┌──────────────────────────────────────────────────────────────┐ −12.2°
   │ ✉3 ⊚1   ◈ t1000-e   4.10V   915.0 SF7   17dBm   SNR +8.5  ⇅3 │
   └──────────────────────────────────────────────────────────────┘ −14.8°
                        (safe-area gap — nothing here)
   ── FOV bottom edge ────────────────────────────────────────────  −17.0°
```

#### Why it is inset from the FOV edges

"Between the top and bottom edge" is load-bearing, for two physical reasons:

1. **The optic degrades at the extreme edge.** Birdbath optics vignette and
   lose focus in the last few degrees. Information placed there is *technically*
   on screen and practically unreadable.
2. **Glasses move on your face.** Content at the true edge clips in and out as
   the frame shifts on the nose. A **safe area — 8% inset, so ±15.5° vertical**
   — is the same discipline as broadcast title-safe, and for the same reason.

Everything in the MICROHUD lives between ±11.9° and ±15.1° of elevation:
outside the protected ±10° world window, inside the ±15.5° safe area.

#### The compass ribbon (top band)

**The ribbon maps bearing to screen position 1:1 with the world**, so a marker
sits *directly above the thing it refers to*. That alignment is the ribbon's
entire value; everything below follows from protecting it.

- **Tangent mapping, not linear-in-angle.** Screen offset is `D · tan(Δbearing)`,
  because that is how perspective projection places the actual node behind it.
  Linear-in-angle mapping looks correct at the centre and drifts ~10% by 15°
  off-axis — enough that a marker visibly fails to sit over its node.
  *(The current prototype has this bug; see §Verification below.)*
- **No smoothing, no easing, no damping.** Any filter makes the ribbon lag during
  head motion, which is exactly when alignment matters. It tracks 1:1 or it is
  worthless.
- **Ticks:** minor every **5°**, major every **15°**. Stroke width ≥ 0.25° (L7).
- **Bearing labels:** three digits (`030`, `105`) on major ticks. Latin digits in
  every locale.
- **Compass points every 45°** — `N NE E SE S SW W NW` — replacing the number at
  those bearings. **The intercardinals are required, not decorative:** with only
  N/E/S/W the spacing is 90°, and a ~56° visible window would frequently contain
  *no* lettered reference at all. At 45° spacing at least one is always in view.
- **Off-FOV nodes are culled, not clamped.** A clamped marker piles up at the
  edge and lies about direction. Count them in an edge chevron instead.

#### Marker symbology — mapped to real protocol roles

The role comes from the advert type nibble (`flags & 0x0F`) that `libmeshcore`
already decodes. These are the actual wire values, not invented categories:

| Wire | `MeshcoreConstants` | Product name | Marker | Silhouette logic |
|---|---|---|---|---|
| 1 | `ADV_TYPE_CHAT` | **Companion** | ● sphere | round |
| 2 | `ADV_TYPE_REPEATER` | **Repeater** | ▮ tall capped bar | vertical mast |
| 3 | `ADV_TYPE_ROOM` | Room server | ⬢ cube | angular |
| 4 | `ADV_TYPE_SENSOR` | Sensor | ◆ diamond | rotated cube |
| 0 | `ADV_TYPE_NONE` | Unknown | ○ hollow ring | deliberately incomplete |

> **Naming note.** The protocol calls the phone/glasses client role **chat**;
> the product calls it **companion**. The table is the mapping — do not let the
> two drift in code.

Markers are ~1–1.5° tall, so they must differ by **gross silhouette — aspect and
count — never by fine detail or by colour alone.** Round vs. vertical vs. angular
survives 20 pixels; a glyph with interior detail does not. `ADV_TYPE_NONE` is the
one place a hollow ring is permitted (L2 otherwise forbids it), precisely because
"unknown" should read as incomplete.

**Deliberately excluded from the ribbon:** hop count, SNR, battery, favourite
state, unread count. A microhud answers *who is where*, not *everything about
everyone*. All of it is one gaze away in S3 NODE FOCUS.

#### The distance indicator (above each marker)

A 2–4 character distance sits above the marker: `340`, `1.2k`, `12k`.

**"Tiny" has a hard floor.** Text may not go below **1.2° of visual angle**
(1.8° for kanji) — about 22 mm at the HUD plane. That is physiology, not taste.
So the way to make the ribbon feel light is **fewer labels, not smaller ones**:

- Show distance for **at most three markers**: the nearest node, plus any marker
  within 4° of gaze centre.
- All other markers show the symbol alone.
- **Unknown distance shows nothing** — no `?`, no dash, and never a fabricated
  number. A contact only carries lat/lon if it advertised `ADV_LATLON`; many do
  not.
- **Unknown bearing means no ribbon marker at all.** Those nodes live in the
  unlocated arc (§S1) and must never be given a plausible-looking fake bearing.

#### Connected-node stats (bottom band)

"Your connected node" is the companion radio paired over BLE. One line, all real
fields already decoded by `libmeshcore`:

| Field | Source | Notes |
|---|---|---|
| role + name | `SelfInfo.advType`, `SelfInfo.name` | same symbology as above |
| battery | `BatteryStorage.batteryMillivolts` | shown as volts |
| frequency + SF | `SelfInfo.frequencyMhz`, `.spreadingFactor` | the two params that change behaviour |
| TX power | `SelfInfo.txPowerDbm` | |
| SNR of last packet | `ContactMessage.snrDb` / `ChannelMessage.snrDb` | **nullable** |
| queue depth | session state | outbound, unsent |
| **unread** | message store | `✉n` channel, `⊚n` direct — **absent when zero** |

**Unread sits at the end of the band nearest the chat hand** — left by default,
mirroring with the handedness setting — so the counter is on the side of the
viewport you will turn toward anyway. Each segment appears **only when non-zero**;
zero unread shows nothing at all, never a `0`. The DM segment comes first,
because a DM outranks channel traffic. This is the same discipline applied to
SNR below: a field with nothing to say does not hold space.

**Two honest data constraints, and they change the design:**

- **SNR is null on the legacy 0x07 / 0x08 frame variants** — it only arrives on
  the V3 0x10 / 0x11 forms.
- **RSSI is not generally available at all.** It reaches us only through
  `RfLog` (the `0x88` RF-log prefix), which requires RF logging to be enabled on
  the radio.

So the bottom band **must not present a live signal meter**, because on a
typical device it would sit dead. It shows `SNR —` when there is no value, never
`0`, never an empty bar that reads as "no signal." RSSI appears only when RF
logging is on, and is otherwise absent rather than blank. A field that is usually
unavailable does not earn permanent space.

#### Behaviour

- **Head-locked, rigid.** Not lazy-follow — a lazy indicator reads as "a tiny
  window off in the distance at a strange angle" (field, 2026-07-09).
- **Dimmable to zero**, and never the only channel for anything (§8.1).
- **Reduce-motion:** the ribbon still tracks the head 1:1 (that is not
  decoration); only the marker fade-in and the distance-label swap are stilled.
- **Localization:** bearings, units, callsigns and protocol tokens stay Latin in
  both locales. Only the two or three word-labels translate.
  **Open question:** cardinal letters — Latin `N/E/S/W` in both locales (the
  international convention Japanese charts also use, and half the band height),
  or kanji `北東南西` (1.8° floor, and 北 vs 比 is a real confusion risk at this
  size)? I recommend Latin with a JA option, but this wants a native reviewer.
- **In TERMINAL VOID there is no MICROHUD** — the flat vector overlay already
  *is* the HUD. Rendering a separate band over it would contradict the
  low-power claim (`AiRspace-UI.md` §5).

Precise angular geometry and the implementation notes are in
`AiRspace-HUD-and-symbology.md` §5.

---

### HAND SURFACES — navigation, chat, and the wrist

**Zone:** HAND. Present on every surface. Default **right** = system, **left** =
chat; configurable, and they swap together.

#### The complete hand model

Four surfaces across two hands. **One hand runs the system, the other runs the
conversation** — and each hand's two faces can never collide, because a hand only
has one side toward you at a time.

| Hand | Face | Surface | Job |
|---|---|---|---|
| **System** (default right) | Palm | Palm console | Status + the 3–4 controls you reach for constantly |
| **System** | Back | **Hand menu** | Where am I, move between views, get to settings |
| **Chat** (default left) | Palm | **REEL** | The last ~12 messages — triage and act |
| **Chat** | Wrist | **CUFF** | Unread indicator; visible at any hand orientation |

**You turn your wrist to switch faces.** No gesture to learn, no mode to
remember — it is the motion you already make to check a watch.

The split is not arbitrary. Navigation and status are things you do *to the
app*; messages are things that arrive *from other people*. Keeping them on
separate hands means an incoming message can never disturb a control you are
mid-way through operating, and you can hold a message up in one hand while
navigating with the other.

The **CUFF is on the wrist rather than the back of the hand** for one reason: a
ring encircling the wrist is legible whichever way the hand is turned, so an
unread indicator cannot be accidentally faced away from. A flat badge can.

```
      chat hand, palm up — the REEL
      ─────────────────────────────

              ╭───────────────────────────────╮
         ⌜ kanako.1 ⌝   ⌜  davi1  ⌝   ⌜ relay ⌝
        ╱  12:03      ╲ ╱ 12:04     ╲ ╱ 12:06 ╲
       │  weather      │ on my way   │  ack    │      ← front arc, legible
        ╲             ╱ ╲           ╱ ╲       ╱
         ╰───────────────────────────────────╯
              ·  ·        (8 more around)   ·  ·
       ═══════════════════════════════════════════
                    ◍ CUFF — ⊚1 unread
```

#### The REEL

Turning the chat palm up reveals an **oval ring buffer** of the last ~12
messages, ~5 legible across the front arc. Full widget spec in
`AiRspace-UI.md`; the design points that matter here:

- **The shape is the data structure.** A ring buffer is bounded, so there is no
  scrollbar, no infinite scroll, and no "load more" — a closed loop cannot lie
  about how much there is, which a scrolling viewport does by construction. The
  reel is a *view of the last N*, never the archive; the full thread lives in
  S4 FOCUS.
- **Oval, not circular**, because the viewport is 61° × 34°: an ellipse fits more
  legible slots across the horizontal without eating the scarce vertical budget.
- **Rotation is thumb-along-index**, mirrored from the HAND MENU — the same
  gesture vocabulary on both hands, with the same self-haptic advantage. *Not* a
  wrist roll: that is supination, which is already the palm-up reveal, and the
  two would fight each other.
- **Gaze a slot to bring it forward; pinch or dwell to open a CROWN** around
  that message — Reply · Read aloud · Copy · Delete here · DM sender · Pin
  sender's location.
- **Sized for the kanji floor (1.8°)**, not the Latin one. Message bodies are
  user content in any script, and a reel sized for English will not hold
  Japanese (`MeshmoreXR-i18n-ja.md` §1).
- **Reduce-motion** snaps between slots rather than spinning.

```
        back of right hand, ~0.35 m, oriented to the head
        ────────────────────────────────────────────────

             ┌────────────────────────────────┐
        ‹    │   H O R I Z O N                │    ›     ⚙
             │   ● ● ● ○ ○ ○ ○     3 / 7      │
             └────────────────────────────────┘
              ↑                              ↑     ↑
        dwell target              dwell target   settings
                                                (thumb side)
```

- **Current view name in text** — the thing that is genuinely hard in a
  headless spatial UI is knowing where you are. This says it, in words.
- **Position dots** — which of N views, so cycling has a shape.
- **Chevrons ‹ ›** — the swipe affordance, and the gaze-dwell targets (L6).
- **Settings gear** — jumps straight to the CONSOLE. Deliberately **not in the
  swipe ring**, so you can never land on settings by accident while cycling.

The swipe ring is the surfaces: HORIZON · SPEAK · CHANNELS · TERRAIN · WAYFIND ·
PINS · TELEMETRY. Settings and About are reached explicitly, never by cycling.

#### The gesture: thumb along the index finger

Swipe left/right is **the thumb sliding along the side of the index finger of
the same hand** — not an air swipe, and not the other hand's finger drawn across
the back of the hand.

Rejected alternatives and why:

- *Opposite-index swipe across the back of the hand* — the obvious reading of
  "swipe", and it needs simultaneous two-hand tracking plus contact precision
  that hand tracking does not reliably deliver. It will work in the demo and
  fail in the field.
- *Air swipe* — reliable to detect, but easy to trigger accidentally while
  gesturing or walking, and it has no felt boundary.

The thumb-on-index gesture wins on a property none of the others have:

> **Your hand provides its own haptics.** Thumb sliding on finger is real
> tactile feedback — felt, not simulated. Given that glasses in this class
> generally have **no haptic actuator at all** (H0 is the likely default,
> `MeshmoreXR-audio-haptics.md` §3), this is the one interaction in the entire
> app that gets genuine haptic confirmation for free. It is also
> proprioceptive: you can do it without looking.

Each detent fires `DETENT` (audio + visual), and the felt ridge of the knuckle
gives the third channel that hardware cannot.

**Fail-safe, per L6 and §8:** gaze + dwell on the chevrons does the same job. If
hand tracking is denied or unavailable entirely, view switching falls back to
dwell targets at the MICROHUD ribbon edges — the hand menu is never the only
route to a view.

#### Reveal rule and the flicker trap

The menu appears when the back of the hand faces the user, computed from the
palm normal against the hand→head vector.

**Hysteresis is mandatory:** reveal above `dot > 0.6`, hide below `dot < 0.45`.
A single threshold makes the menu strobe on and off as the wrist hovers at the
boundary, and **flicker on a hand-anchored element is the most nauseating
failure mode available in XR** — worse than the element being absent. The gap
between the two thresholds is not tuning slack; it is the feature.

Fade in over ~120 ms. Never pop.

#### Placement and sizing

- **L1 applies without exception:** position from `MIDDLE_METACARPAL`,
  **orientation from the head**, offset ~6 cm along the hand→head vector. Never
  composed with the hand's rotation — that is the foreshortening bug twice
  field-confirmed.
- Working distance ~0.35 m (where people naturally hold a watch-check).
- Menu width ≈ **1.4× hand width** (~110 mm ≈ 18° at 0.35 m), so it slightly
  overhangs the hand and view names fit in both locales.
- Text at the locale floor: 1.2° Latin, **1.8° kanji**. Japanese drives the band
  height — `ホライズン` is wider than `HORIZON`. Design at the JA size
  (`MeshmoreXR-i18n-ja.md` §1).

#### Handedness

Default **right** for the system hand, which puts the REEL and CUFF on the left.
Configurable in CONSOLE → ACCESS, and **the two swap together** — you cannot end
up with navigation and chat on the same hand.

Switching **mirrors** each layout so the settings gear stays on the thumb side,
the chevrons stay under the thumb's travel, and the MICROHUD unread counter
moves to the band end nearest the new chat hand. This is an accessibility
setting as much as a preference — it must not be buried, and it must not require
a restart.

---

### Surface × zone summary

| Surface | HORIZON | FOCUS | HAND | EDGE | GROUND |
|---|:--:|:--:|:--:|:--:|:--:|
| **MICROHUD** *(all surfaces)* | – | – | – | **●** | – |
| **HAND SURFACES** *(all surfaces)* | – | – | **●** | – | – |
| S0 First Light | ○ | ○ | ● | ● | ○ |
| **S1 Horizon** | **●** | – | ● | ○ | – |
| S2 Link | – | ● | ○ | ● | – |
| S3 Node Focus | ○ | ● | ○ | – | – |
| S4 Speak | – | ● | **●** | ○ | – |
| S5 Channels | ● | – | ● | – | – |
| S6 Terrain | ○ | ○ | ○ | – | **●** |
| S7 Wayfind | ○ | – | ● | ○ | ○ |
| S8 Pins | – | ● | ● | ○ | ○ |
| S9 Telemetry | – | ● | – | ○ | – |
| S10 Uplink | – | ● | ○ | ● | – |
| S11 Theme | ● | ● | ○ | – | – |
| S12 About | – | ● | – | – | – |

● hero · ○ supporting · – unused

---

## 6. Technical design

### 6.1 Module layout

```
meshmore-xr/
├─ settings.gradle.kts        # includeBuild("../libmeshcore")
│                             # includeBuild("../libmeshcore-android")
├─ app/                       com.iotj.meshmore.xr
├─ core/                      com.iotj.meshmore.xr.core      domain, tier state machine
├─ mesh/                      com.iotj.meshmore.xr.mesh      libmeshcore adapter, session, store
├─ spatial/                   com.iotj.meshmore.xr.spatial   the 5-zone framework (§2)
├─ symbol/                    com.iotj.meshmore.xr.symbol    the 7 primitives (§4)
├─ theme/                     com.iotj.meshmore.xr.theme     9 themes as data
├─ audio/                     com.iotj.meshmore.xr.audio     procedural synth, 9 packs
├─ voice/                     com.iotj.meshmore.xr.voice     STT/TTS tiering
├─ atlas/                     com.iotj.meshmore.xr.atlas     MapLibre/PMTiles, pins, geofence
└─ uplink/                    com.iotj.meshmore.xr.uplink    Tier-2 services
```

Note: the app namespace is `com.iotj.meshmore.xr.*` as specified; the consumed
libraries keep their published `io.iotone.meshcore` namespace. That is correct —
they are separately published artifacts, not vendored source.

### 6.2 Toolchain

`JDK 17–21` (pin it — >21 fails with a bare version string), `compileSdk 36`,
`minSdk 34`, `targetSdk 35`, NDK `28.0.13004108`, CMake `3.22.1`. A `bin/`
wrapper script pinning `JAVA_HOME` and `ANDROID_HOME` from day one.

### 6.3 Third-party reuse

| Need | Use | Licence | Why |
|---|---|---|---|
| MeshCore protocol | **`libmeshcore`** | MIT | Ours, done, golden-vector verified |
| BLE transport | **`libmeshcore-android`** | MIT | Ours, done |
| Spatial UI | `androidx.xr.compose` alpha16 | Apache-2.0 | Panels |
| 3D scene | `androidx.xr.scenecore` beta01 | Apache-2.0 | Entities, glTF, Filament-backed |
| Perception | `androidx.xr.arcore` beta01 | Apache-2.0 | Head, hands, planes, **QrCode**, **Geospatial** |
| Offline maps | **MapLibre Native Android ≥ 11.7** + **PMTiles** | BSD-2 / BSD-3 | `pmtiles://file://`, no tile server |
| Basemap data | **Protomaps basemaps** (OSM) | ODbL data | Single-file offline region |
| Offline STT | **Vosk** (+ on-device `SpeechRecognizer` API 33+ where available) | Apache-2.0 | Guaranteed-offline floor, EN + JA |
| Offline TTS | Android `TextToSpeech` offline voices; **Piper** for a consistent themed voice | — / MIT | Per-theme voice character |
| On-device LLM | ML Kit GenAI / Gemini Nano **where present** | — | Tier-1.5 summarization; strictly optional |

**Reuse verdict:** the only genuinely new engineering is the spatial zone
framework, the symbology renderer, and the nine themes. Everything below the
UX line already exists.

### 6.3.1 Terrain, place and POI data — the investigation

All of these are open and redistributable. Checked 2026-07-29.

**Elevation / 3D topography**

| Source | Coverage | Resolution | Format | Licence | Use |
|---|---|---|---|---|---|
| **AWS Terrain Tiles** (Terrarium) | global | z0–15 | RGB-encoded PNG, plain `z/x/y`, **no auth** | open data | **Default global relief.** Simplest possible path to 3D terrain |
| **Copernicus DEM GLO-30** | global | 30 m | Cloud-Optimized GeoTIFF | open (AWS Open Data) | Source when we build our own packs |
| **GSI 標高タイル** (DEM5A/5B) | **Japan** | **5 m** | PNG / text tiles, same `z/x/y` scheme | **attribution only**, no application needed | **Japan detail.** Six times the resolution of the global set, in a launch market |
| **USGS 3DEP** | USA | 1–10 m | COG | public domain | US detail |
| GEBCO 2025 | ocean | — | grid | open | Bathymetry, if ever needed |

Terrarium encoding is the pragmatic choice: elevation is decoded client-side
from the RGB triple with ~3 mm precision, no server-side processing, and the
tiles drop straight into the same PMTiles container as the basemap.

> **GSI is the standout finding.** A 5 m DEM over the whole of Japan, free,
> attribution-only, on standard tile coordinates. For a product launching in
> Japan this is a materially better terrain experience than the 30 m global set,
> for the cost of one attribution line and a region-specific pack.

**Places and POIs**

| Source | What | Licence | Use |
|---|---|---|---|
| **Protomaps basemaps** (PMTiles) | OSM vector basemap **including a POI layer** | ODbL (data); icons MIT | The basemap and its POIs, one file |
| **GeoNames `cities15000`** | ~33 k cities | CC-BY 4.0 | **Already bundled in SNS (812 KB) — port unchanged** |
| **Overture Places** | ~59 M POIs with stable GERS ids | CDLA-Permissive-2.0 (Foursquare-sourced parts Apache-2.0) | Optional richer POI pack; the most permissive licence of the three |
| **Natural Earth** | coastlines, admin | public domain | GLOBE scale (already shipping as `world-110m.geojson`) |

**POIs are filtered to field-relevant categories** — water, shelter, trailhead,
peak, bridge, ford, power infrastructure, emergency services, transport. Not
restaurants and shops. A mesh field app's points of interest should be the
things that matter *when the network is down*; anything else is clutter bought
at the cost of pack size.

### 6.3.2 Offline caching

Same principle the gazetteer already proves: **single file, immutable,
range-read, no server.**

| Pack | Contents | Source |
|---|---|---|
| `basemap-<region>.pmtiles` | vector basemap + POIs | Protomaps / OSM |
| `terrain-<region>.pmtiles` | Terrarium elevation tiles | AWS Terrain Tiles, or GSI in Japan |
| `places.bin` | GeoNames cities15000 | **bundled in the APK** |
| `world-110m.geojson` | coastlines | **bundled in the APK** |

- **Bundled packs ship in the APK** so a fresh install is useful with no network
  at all — the offline-first baseline, exactly as the SNS gazetteer does today.
- **Region packs are a Tier-2 action**, surfaced as S10 UPLINK → *grab region*.
  Downloaded whole, versioned, and **atomically swapped**: a pack is either
  complete or absent, never partially valid.
- **Eviction is manual and explicit.** Never silently evict a region — a user
  who downloaded Fukuoka before going off-grid must still have Fukuoka. Show
  size, coverage and age; let them delete.
- **The data edge is visible.** Where a pack ends, the map ends — a drawn
  boundary, never a fade into plausible blankness.

**Attribution obligations** (S12 ABOUT, and non-negotiable): © OpenStreetMap
contributors (ODbL) for basemap and POIs; GeoNames (CC-BY 4.0); Geospatial
Information Authority of Japan (地理院タイル) when the JP terrain pack is
installed; Overture / Foursquare if that pack ships.

### 6.4 Performance — and where native actually pays

**Start fully managed.** SceneCore is Filament-backed and will carry the
majority of this design. The starter guide's advice ("skip native unless you
must") is correct and we should follow it.

The two places native genuinely pays, both **flag-gated OFF by default**:

1. **The HORIZON mote field** at high node counts. 300+ nodes × (MOTE + halo +
   pulse) will not survive as individual entities. Solution order: (a) instanced
   rendering of a single billboarded quad — data-only, no crash surface;
   (b) only if that fails, a native draw path.
2. **BIOLUME's particle field** (§7.8) — the one theme with a genuine
   hundreds-of-thousands-of-primitives budget.

**Do not** write a native OpenXR/Vulkan activity in phase 1. It buys nothing
this design needs and imports the full exit-ordering hazard — a sloppy exit
takes the **OS compositor** down with it. If it ever becomes necessary:
`xrRequestExitSession()` → keep pumping until `EXITING` → *then* finish and
destroy Vulkan, with a bounded timeout.

Prefer **data-only optimizations** always (LOD by distance, importance-ordered
prefixes, culling the rear arc). They deliver most of the win with none of the
GPU-crash surface.

**Budget:** stable frame time first, fidelity second. Perf HUD visible on every
surface that renders heavy content (§S9).

### 6.5 The known traps, pre-empted

Collected from the field docs so they are decided rather than rediscovered:

- One **superset `Config`**, configured **once**, off the main thread. `Config`
  replaces rather than merges — a bare `Config(handTracking=…)` silently kills
  device tracking.
- World-derived poses in **`Space.REAL_WORLD`**.
- Hand UI: position from hand, **orientation from head**, offset along the
  hand→head vector, ~6 cm.
- Paint every panel's own backing.
- Route all audio as **`USAGE_MEDIA`** — other usages get ducked or misrouted.
- Poll for capability restoration after full-space transitions; a one-shot check
  reads the pre-grant state.
- **The emulator lies about hands.** Tune hand placement on real hardware only.
- Single `XrLog` tag, `[surface] STATE` at every branch including silent
  early-returns.

---

## 7. The nine themes

Each theme specifies: **name · one-liner · substrate class · palette · type ·
symbology treatment · motion · audio pack (or its absence) · TTS voice ·
guidelines · honest risk.**

All nine honour §8 parity guarantees without exception. Seven of the nine differ
only in visual language, density, motion, and sonic character — never in what
information is available or how it is reached. **Two differ in posture as well**
(§7.0), and for those the guarantee narrows precisely: every piece of
information is still *available*, but the route to it changes.

**Substrate classes:** **PANEL-LED** (survives sunlight best, cheapest, most
conventional) · **ADDITIVE-LED** (most spectacular, most fragile in bright
light, highest GPU) · **HYBRID**.

---

### 7.0 · Posture — the second axis

A theme has always been a *skin*: palette, type, symbology treatment, motion,
sound. **Posture** is a second, orthogonal axis, and it is a bigger claim: it
decides **which zones a theme lights up at all, and at what scale.**

The reason to have it is that "wearing the mesh" is not one activity. Sitting at
a desk reviewing a network and walking a ridge line with a pack on are different
enough that the same surface budget serves neither well. Rather than bolt modes
onto every theme, two themes *are* the modes.

| Posture | Zones live | Content scale | Built for |
|---|---|---|---|
| **FIELD** *(default — seven themes)* | HORIZON · FOCUS · HAND · EDGE · GROUND | HORIZON at r ≈ 2.5 m | Standing, walking, stopping to look. The general case. |
| **TABLETOP** | **GROUND · FOCUS · HAND** (no HORIZON) | Everything inside ~0.8 m | Seated, indoors, stationary, powered |
| **TRANSIT** | **MICROHUD · HAND** (nothing else, ever) | Peripheral band + palm | Moving, hands busy, eyes on the world |

Three rules that keep posture from becoming a licence to fragment the app:

1. **Posture never removes information, only routes.** Anything a FIELD theme
   shows on the HORIZON must be reachable in TABLETOP and TRANSIT — from the
   GROUND map and the hand menu respectively. §8 parity is unchanged.
2. **Posture is a theme property, not a mode toggle.** Choosing RECON AMBER *is*
   choosing TRANSIT. There is no orthogonal switch, because a posture the skin
   was not designed for looks like a bug.
3. **Angular sizing makes scale free.** The type and symbology floors are
   specified in *degrees* (§6, and `MeshmoreXR-typography.md` §5), so a 1.75° em
   is 76 mm on a 2.5 m HORIZON and 18 mm on a 0.6 m tabletop with no separate
   spec and no per-posture constants. This is exactly what the angular
   discipline was bought for.

---

### 7.1 · HALO FIELD — *recommended default*

> **The mesh as a calm horizon.** Everything at its true bearing, nothing
> shouting, legible in direct sun. The one you can wear for eight hours.

- **Substrate:** HYBRID — additive HORIZON, panel FOCUS.
- **Palette:** ground `#070B10` · surface `#101722` · accent cyan `#35E0F0` ·
  live `#7CFF6B` · warn `#FFB020` · alert `#FF3B6B` · text `#DDE7EF`
- **Type:** Saira Condensed (display) · M PLUS 1 Code (mono + JA) · Departure
  Mono (range labels only)
- **Symbology:** solid discs with a 1-px-equivalent bright cyan keyline; HALOs
  as soft filled annuli; SPURs thin-cored and understated. Restraint is the
  brand.
- **Motion:** minimal. PULSE only on real events. Nothing idles.
- **Audio — "Sonar":** a soft sonar ping on discovery (sonically mirrors the
  HORIZON), a gentle two-note figure for messages, low sustained tones for link
  state. Sparse by design so it survives eight hours outdoors without fatigue.
- **TTS voice:** calm, natural, neutral rate.
- **Guidelines:** never more than three luminance levels on screen at once.
  Recency-fade is the primary information channel. If you are adding a
  decoration, delete it.
- **Risk:** low. This is the safe, correct default.

---

### 7.2 · NERV SPATIAL

> **The command deck, wrapped around you.** Evangelion's MAGI console as a
> 360° operations ring. Countdown telemetry, hexagonal brackets, and an
> emergency state you cannot miss.

- **Substrate:** PANEL-LED.
- **Palette:** ground `#0A0E1A` · surface `#121826` · accent orange `#FF7A00` ·
  alt green `#9CFF00` · alert `#E01B24` · text `#E6ECF5` · line `#243049`
- **Type:** Saira ALL-CAPS compressed (headers) · Departure Mono (all telemetry)
  · M PLUS 1 Code (kanji callouts) · outlined slashed-zero numerals
- **Symbology:** every MOTE gets hexagonal corner brackets. SLABs carry
  scanlines and a `PHASE_02`-style coded label. Range HALOs are graduated with
  tick marks.
- **Motion:** scanline drift; bracket snap on selection; on critical alert the
  **whole palette inverts to red and the scanline rate triples** — the canonical
  NERV emergency, and a perfect non-audible parity cue.
- **Audio — "Mission Control":** MAGI-style data chirps, a three-tone alert
  cadence, countdown ticks under long operations. Busy but structured.
- **TTS voice:** clipped, procedural, slightly fast.
- **Guidelines:** density is the aesthetic — but density lives on **panels**,
  never in open space. The forward FOV stays clear regardless.
- **Risk:** medium. Easiest theme to overbuild into an unreadable wall.

---

### 7.3 · AG-SYSTEMS

> **Wipeout's craft HUD at 900 km/h.** Velocity chevrons, race-team livery per
> channel, glossy and fast. The showpiece for demos.

- **Substrate:** HYBRID.
- **Palette:** ground `#05060B` · surface `#10131F` · accent cyan `#22D3EE` ·
  alt magenta `#FF2D78` · text `#DDF6FF` · line `#20283B`
- **Type:** Michroma / Orbitron (display) · Saira (body) · JetBrains Mono
  (values)
- **Symbology:** CARETs become swept chevrons. SPURs are the full 3-cylinder
  additive beam at maximum glow. Each channel is a **fictional race-team
  livery** — its own mark, accent, and stripe geometry, applied to every MOTE on
  that channel.
- **Motion:** everything eases with momentum. Selection produces a doppler
  sweep. Panels arrive from off-axis, never fade in.
- **Audio — "Velocity":** filtered sweeps, doppler whooshes, a three-note
  race-start triad on link-up. Confident and glossy.
- **TTS voice:** smooth, announcer-adjacent.
- **Guidelines:** motion carries the identity, so **reduce-motion must be
  designed, not bolted on** — the static fallback needs its own pass or this
  theme becomes the least accessible of the nine.
- **Risk:** medium-high. Highest motion-sickness surface area.

---

### 7.4 · SEELE MONOLITH

> **Type is the entire UI.** Black slabs floating in your room, cream numerals a
> foot tall, near-zero chrome. The sunlight and accessibility benchmark.

- **Substrate:** PANEL-LED (maximally).
- **Palette:** ink `#000000` · cream `#EDE6D6` · SEELE red `#C8102E` (alert
  only) · bone `#9A958A` · line `#2A2A26`
- **Type:** oversized Saira numerals · M PLUS 1 Code for sparse text ·
  slashed zero. Nothing else.
- **Symbology:** the primitives are almost suppressed. A node is a **number**.
  The HORIZON is a ring of floating monoliths bearing callsigns, not discs.
  Alert is a full slab colour-inversion.
- **Motion:** none. Monoliths appear and vanish; they never animate.
- **Audio — "Tribunal":** deep resonant sub-bass strikes for critical events, a
  single low choral swell, and **near-silence otherwise.** The most restrained
  pack.
- **TTS voice:** slow, grave, committee.
- **Guidelines:** if it can be a number, make it a number. If it can be removed,
  remove it. Highest contrast ratios in the set; largest type; best in direct
  sun.
- **Risk:** low. Ship this as the guaranteed high-contrast alternate regardless
  of which theme wins default.

---

### 7.5 · DR POP

> **The Designers Republic's maximalist half.** Flat colour blocks, fake
> corporate sub-brands, katakana as pure graphic. Loud, Y2K, unapologetic.

- **Substrate:** PANEL-LED.
- **Palette:** ink `#101014` · magenta `#FF2E88` · acid `#D7FF00` · cyan
  `#00E5FF` · cream `#F2F0E6` · line `#33333F`
- **Type:** Michroma / Orbitron (display) · M PLUS 1 Code (katakana run as
  graphics, not as language) · very bold numerals
- **Symbology:** MOTEs sit inside flat colour-blocked cartouches. Each channel
  gets a fabricated sub-brand mark and a coded label (`MESH_SYS/04`). Halftone
  bursts on PULSE.
- **Motion:** hard cuts, no easing. Elements snap.
- **Audio — "Pure Phase":** Y2K rave stabs, vinyl crackle, TR-909-adjacent
  blips, a filtered riser on channel switch. The most musical pack.
- **TTS voice:** bright, slightly processed.
- **Guidelines:** hi-saturation on neutral, angular, layered. **Colour is
  decoration here and must never be the sole carrier of state** — this theme
  needs the most deliberate accessibility work of the nine, and the katakana is
  ornamental so it must never displace real localized text.
- **Risk:** high on accessibility. Beautiful, and the most work to do right.

---

### 7.6 · RECON AMBER

> **Single-hue night operations.** Amber phosphor, nothing else. Lowest power,
> lowest light pollution, works at 3 a.m. without ruining your night vision.

- **Substrate:** HYBRID, minimal.
- **Palette:** black `#000000` · amber `#FFB000` · dim amber `#6E4E00` · blood
  `#B3231F` (alert only). **Four values total.**
- **Type:** Departure Mono / M PLUS 1 Code throughout. No display face.
- **Symbology:** all seven primitives rendered in one hue at four luminance
  steps. Information is carried by **brightness and form**, never by colour.
- **Motion:** a slow radar sweep on the HORIZON; nothing else.
- **Audio — "Codec":** squelch bursts, a codec-style ring for incoming, morse-
  adjacent confirmation clicks. Monochrome sound to match monochrome light.
- **TTS voice:** flat, radio-filtered, band-limited.
- **Posture: TRANSIT.** This is the **physically active** theme, and it is the
  only one that never puts anything in front of you. Two surfaces exist and no
  others: the **MICROHUD** band between the upper and lower FOV edges, and the
  **hand map** on the palm. Nothing occupies the central FOV, because the
  central FOV is where the trail, the traffic, and the person you are talking to
  are. You do not look *at* this theme; you glance at its edge, or you turn your
  hand over.
  - The HORIZON is not drawn. Bearing lives in the microhud's compass ticks.
  - Node detail is reached by turning the palm up, not by selecting in space.
  - The hand map is the GROUND surface, shrunk to palm scale.
  - Microhud text is **Latin and numerals only, permanently** — kanji at
    microhud size is a smudge, so a Japanese string routes to the hand menu
    TITLE instead (`MeshmoreXR-typography.md` §5.4).
- **Guidelines:** a single hue is the constraint *and* the feature — because
  brightness already carries all state, this theme is automatically the most
  colour-blind-safe of the nine. Dimmest emission, best battery. Every one of
  those properties is what you want when you are three hours into a walk, which
  is why TRANSIT landed here rather than on AG-SYSTEMS: a craft HUD is still
  something you look *through*, and this is something you look *past*.
- **Risk:** low, and posture lowers it further — the smallest surface budget in
  the set is also the least to build and the least to get wrong.

---

### 7.7 · VECTORLINE

> **Tempest, Rez, Battlezone.** Pure glowing vector geometry in a black void —
> which on see-through glasses means pure glowing geometry **in your actual
> room**. The UI is an instrument you play.

- **Substrate:** ADDITIVE-LED (the purest expression of §1.3).
- **Palette:** void `#000000` (= transparent, by design) · electric
  `#00FFC8` · violet `#B14BFF` · hot `#FF3D00` · white-hot `#FFFFFF` for peaks
- **Type:** Nova Square / Syncopate (display) · Departure Mono (data) —
  stroke-forward faces that read as drawn vectors
- **Symbology:** every primitive rebuilt as **extruded additive tube geometry**
  — the 3-cylinder core/glow/halo construction, never flat strokes. MOTEs are
  glowing wireframe polyhedra (solid enough to be foreshorten-proof, open enough
  to read as vector). Additive blending everywhere; overlaps bloom to white.
- **Motion:** everything is on a beat. Elements draw themselves on in stroke
  order.
- **Audio — "Arcade":** the standout. **Every interaction is a musical note
  quantized to a scale**, and the scale shifts with mesh activity — a busy mesh
  literally sounds richer. Discovery is an arpeggio; the app becomes an
  instrument.
- **TTS voice:** clean synthetic, lightly formant-shifted.
- **Guidelines:** because black is transparent, **the real world is your
  background and you do not control it.** Every mark must be legible against a
  white wall *and* a bright sky. Requires the device dimmer where available and
  a mandatory luminance floor per mark.
- **Risk:** **high, and worth stating plainly.** This is the most spectacular
  theme and the one most likely to be unusable outdoors at noon. Prototype it
  against real sunlight before committing.

---

### 7.8 · BIOLUME

> **The mesh as a living organism.** Not cyberpunk at all. Drifting spores,
> mycelial threads propagating between nodes, soft breathing light. The one that
> makes people say "oh" out loud.

- **Substrate:** ADDITIVE-LED.
- **Palette:** deep `#04100E` · surface `#0B1F1A` · spore `#5FFFC2` · bloom
  `#9B6BFF` · warm `#FFD08A` · alert coral `#FF6B5F`
- **Type:** Outfit (display) · M PLUS Rounded 1c (body + JA) · IBM Plex Mono
  (the little data there is)
- **Symbology:** MOTEs are soft-edged glowing spores that drift a few
  centimetres and breathe. SPURs are **mycelial threads that visibly grow** from
  sender to receiver when a packet propagates — the single best visualization of
  a mesh network anyone has built. HALOs are diffuse bloom, not rings.
- **Motion:** continuous, slow, organic, generative. Nothing is ever perfectly
  still. Reduce-motion freezes the field to static positions and keeps every
  meaning.
- **Audio — "Bloom":** granular textures, breath, soft chimes. **Generative —
  no two events sound identical**, but each event class keeps a stable timbral
  identity so it stays learnable. The least fatiguing pack.
- **TTS voice:** warm, unhurried, close-mic'd.
- **Posture: TABLETOP.** This is the **small-scale, compact** theme: the entire
  mesh is a living diorama on a real table, roughly 0.6–0.8 m across, and there
  is no HORIZON at all. You sit down to it. You lean in. You walk around the
  table rather than turning your head.
  - GROUND is the whole experience — the TABLE map scale, always on.
  - FOCUS spawns *above* the table, not at 1.2 m along gaze.
  - HAND keeps the palm console; the hand menu switches map scale rather than
    view.
  - Because content sits at ~0.6 m instead of 2.5 m, every mark is ~4× smaller
    in millimetres at the same visual angle. Nothing in the spec changes (§7.0
    rule 3) — but this is the theme that proves the angular discipline was worth
    it.
- **Guidelines:** this theme argues that a mesh network is *alive*, and every
  design decision must serve that. It is also the strongest counter-programming
  to "another dark cyberpunk app" — worth having in the set for that reason
  alone. Growth, drift and breathing all read far better on a compact object you
  can lean into than on a 5 m ring you scan, which is the second reason TABLETOP
  belongs here.
- **Risk:** medium-high GPU (the one real particle budget in the set) — largely
  neutralised by TABLETOP, which is a seated, stationary, usually-powered
  posture where thermals and battery stop being the binding constraint. Its
  other stated risk, reading as insufficiently "operational" for field use, is
  answered by simply not being a field theme.
- **Runner-up considered:** NERV SPATIAL. A command deck *is* a desk, but its
  V.High density is the opposite of compact — it wants a wall of readouts, not a
  small object. Density, not scale, is what ruled it out.

---

### 7.9 · TERMINAL VOID

> **Phosphor text floating in space. No panels, no chrome, no graphics.** The
> power-user, lowest-power, highest-legibility, most honest theme in the set.

- **Substrate:** ADDITIVE-LED (text only).
- **Palette:** void `#000000` · phosphor `#33FF66` (user-selectable P1 green /
  P3 amber / white) · dim `#0A3D17` · alert `#FF4444`
- **Type:** Departure Mono at native pixel-grid multiples of 11 · M PLUS 1 Code
  for JA. Nothing else, ever.
- **Symbology:** **the primitives are replaced by glyphs.** A node is
  `●davi1  -71dBm  340m  042°`. The HORIZON is a ring of floating text lines at
  true bearings. Zero geometry.
- **Motion:** typewriter reveal; a blinking block cursor. Nothing else.
- **Audio — "Teletype":** mechanical key clacks, a real BEL, a carriage-return
  ding. Deliberately lo-fi.
- **TTS voice:** classic formant synth (a deliberate, affectionate DECtalk
  reference).
- **Guidelines:** if it cannot be expressed in monospace text, it does not
  exist. Lowest GPU cost, lowest emission, longest battery of the nine, and the
  best theme for debugging the app itself.
- **Risk:** low technically; narrow appeal. Ship it as the developer/field
  fallback and let the enthusiasts find it.

---

### 7.10 Theme comparison

| # | Theme | **Posture** | Substrate | Hero metaphor | Density | Audio pack | Sunlight | Accessibility | GPU | Effort |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **HALO FIELD** | Field | Hybrid | Calm bearing ring | Med | Sonar | High | **Best** | Low | **Lowest** |
| 2 | NERV SPATIAL | Field | Panel | Command deck | V.High | Mission Control | Med | Med | Med | High |
| 3 | AG-SYSTEMS | Field | Hybrid | Craft HUD | Low | Velocity | High | Med⚠ | Med | Med-High |
| 4 | SEELE MONOLITH | Field | Panel | Giant numeral | Minimal | Tribunal | **Highest** | **Highest** | **Lowest** | Low |
| 5 | DR POP | Field | Panel | Colour-block brands | High | Pure Phase | Med | Needs care⚠ | Low | Med |
| 6 | RECON AMBER | **Transit** | Hybrid | Single-hue sweep | Low | Codec | **Highest** | High | **Lowest** | Low |
| 7 | VECTORLINE | Field | Additive | Glowing vectors | Med | **Arcade** | **Low ⚠** | Med | High | High |
| 8 | BIOLUME | **Tabletop** | Additive | Living organism | Low | Bloom | Med | High | **Highest** | High |
| 9 | TERMINAL VOID | Field | Additive | Text in space | High | Teletype | High | High | **Lowest** | Low |

### 7.11 Recommendation

> **DECIDED (2026-07-30): HALO FIELD is the default theme.**

**Default: HALO FIELD (1).** It is the only theme that is simultaneously the
lowest-effort, the most legible in the field, the most accessible, and the most
faithful to "offline first, always-on mesh." It is the right thing to build
top-to-bottom first because it exercises every zone and every primitive without
any exotic rendering.

Then, in order:

- **SEELE MONOLITH (4)** as the guaranteed high-contrast / accessibility
  alternate. Nearly free once the theme system exists, and it is the one that
  works at noon in July.
- **RECON AMBER (6)** as the night/low-power variant. Also nearly free.
- **VECTORLINE (7)** or **BIOLUME (8)** as the showpiece — but only after a
  **sunlight prototype**, because §1.3 is a real physical constraint and both
  themes bet everything on emission. Build one small additive test scene and
  take it outside before committing to either.

The other five are separable and can land in any order. Theme is data (§6.1
`theme/`), so the marginal cost of each after the first is styling, not
architecture — provided the primitive set in §4 is built as a genuine
abstraction from day one. **That is the load-bearing engineering decision in
this brief.**

---

## 8. Accessibility & sensory parity

Carried forward from the SNS brief without weakening, plus what XR adds.

### 8.1 Inherited, non-negotiable

- **No information by sound alone.** Every audible cue has a synchronised
  equivalent **visual** cue and an optional **haptic** pattern. Audio packs are
  an augmentation channel, never the only one.
- TTS off by default; spoken content always has visible text.
- Critical events by **icon + text + motion**, never colour alone.
- Haptics as an independent third channel.
- Respect bold-text, text scale, high-contrast, **reduce-motion**, and the OS
  silent setting.
- A shipped **"visual + haptic only"** mode.
- Contrast **AA+ (≥ 7:1)**; touch targets ≥ 48 dp equivalent.

### 8.2 New for XR, and equally non-negotiable

- **No information by position alone.** A node behind you must be reachable
  without turning around. Every HORIZON element has an equivalent entry in a
  FOCUS list view. This is both an accessibility requirement and a seated-use
  requirement.
- **Seated / limited-mobility mode.** HORIZON compresses from 360° to a
  ~120° forward arc with bearing shown as an explicit label rather than as
  actual direction. Nothing becomes unreachable.
- **Gaze-and-dwell as a full alternative to pinch**, for users who cannot
  reliably pinch and for when hand tracking is denied or degraded.
- **No text below 1.2° visual angle** in any theme (§4.1).
- **Motion sickness:** no involuntary camera motion, ever. Nothing moves the
  user. Reduce-motion is a designed state per theme, not a disabled animation.
- **Mic honesty:** push-to-talk only, with an unmistakable always-visible
  indicator whenever the mic is live.
- **Safety signals are not themeable** (§S8) — physical-actuation confirmations
  are identical in all nine themes.

---

## 9. Settings, and what still needs a decision

The open decisions from earlier drafts are now **real settings with real
defaults** — except the ones that genuinely cannot be, which are listed honestly
in §9.4.

Implemented in `airspace-ui/src/airspace/settings.js`, defaults in
`theme.js`, invariants asserted by `npm run test:settings`.

### 9.1 Three classes of setting, and why the split matters

| Class | Who owns the default | Theme may change it? |
|---|---|---|
| **THEME** (12) | The theme — it is part of the theme's identity | Yes, that is the point |
| **USER** (9) | Global default; describes the person, not the look | **Never** |
| **A11Y** (5) | Global default, and it **clamps** other settings | **Never** |

Resolution order, later winning:

```
globalDefault  →  theme default  →  user pin  →  a11y pin  →  CLAMPS
                                                              ^^^^^^
```

**The clamps are the reason this split exists.** Without them, "themes set
defaults" and "this user needs reduced motion" are in direct conflict, and
whichever runs last wins by accident of ordering. Concretely: a user turns on
reduce-motion, later switches to AG-SYSTEMS — whose entire identity is
`motion.amount: full` — and the theme default silently re-enables motion. That
is an accessibility regression nobody would catch until someone reported nausea.

So clamps are applied **last and unconditionally**. They are not a layer that
can be outranked; they are an invariant, and there is a test that walks all nine
themes to prove it.

| A11Y setting | Clamps |
|---|---|
| `a11y.reduceMotion` | `motion.amount → none`, dense packet audio → standard |
| `a11y.visualHapticOnly` | `audio.enabled → false`, whatever the theme's pack |
| `a11y.dwellOnly` | `gesture.reelScroll → dwell` |
| `a11y.seatedArc: 120` | `hud.density` may not be `off` — a seated user cannot reach a 360° horizon, so the HUD has to carry more |

That last one is why TERMINAL VOID, which ships `hud.density: off` because its
flat overlay *is* the HUD, still gets a HUD in seated mode.

**A user pin survives a theme switch.** That is its whole purpose: unpinned keys
follow the theme, pinned keys are yours. Both halves are tested — if every theme
resolved the same value, theme profiles would be decorative.

### 9.2 Per-theme defaults

The twelve theme-owned settings, as each theme's identity expressed as data:

| | motion | packet audio | HUD | dim | reel | grouping | cuff clear | terrain | V× | TTS |
|---|---|---|---|---|---|---|---|---|---|---|
| **HALO FIELD** | minimal | sparse | micro | 70 | 12 | mixed | – | mesh | 2.5 | 1.00 |
| NERV SPATIAL | standard | **dense** | **full** | 85 | 18 | perChannel | – | mesh | 2.5 | 1.15 |
| AG-SYSTEMS | **full** | standard | micro | 80 | 12 | mixed | – | mesh | 3.0 | 1.05 |
| SEELE MONOLITH | **none** | **off** | micro | 100 | **5** | mixed | – | mesh | 2.0 | 0.85 |
| DR POP | standard | **dense** | micro | 75 | 12 | perChannel | – | mesh | 2.5 | 1.10 |
| RECON AMBER | minimal | sparse | micro | **40** | 10 | mixed | – | **contour** | 3.0 | 1.00 |
| VECTORLINE | **full** | **dense** | micro | 90 | 12 | mixed | – | mesh | 3.5 | 1.00 |
| BIOLUME | **full** | standard | micro | 60 | 12 | mixed | **on** | mesh | 2.5 | 0.95 |
| TERMINAL VOID | minimal | standard | **off** | 50 | **24** | mixed | – | **contour** | 3.0 | 1.00 |

The defaults are arguments, not filler:

- **SEELE ships `packetDensity: off` and `motion: none`** — its thesis is
  near-silence and stillness, so the settings say so rather than the prose only.
- **SEELE also has the shallowest reel (5)** and **TERMINAL VOID the deepest
  (24)**: monospace text is nearly free to render, monoliths are not.
- **RECON dims the HUD to 40** (night vision) and is the only theme besides VOID
  that defaults to **contours** — and its **exaggeration goes up to 3.0**,
  because contour lines need vertical separation to carry relief that a shaded
  mesh would have carried by shading.
- **BIOLUME is the only theme with `cuff.autoClear: on`**, because it is the
  theme designed for all-day wear and a cuff glowing since breakfast is noise.
- **VECTORLINE ships dense packet audio** because in that theme the mesh *is* a
  generative composition — turning it down removes the theme.

### 9.3 Where they live

Every setting maps to a CONSOLE station and an AiRspace widget — asserted by
test, so a setting cannot exist without a home:

| Station | Settings |
|---|---|
| VOICE | audio pack/enable/density/gain, TTS enable/rate, PTT-only, reel depth + grouping, cuff auto-clear |
| THEME | HUD density + dim, terrain render + exaggeration |
| ACCESS | handedness, locale, cardinal script, haptic scale, reel gesture, and all five A11Y settings |
| UPLINK | auto-sync |

Enums are TUMBLERs, ranges are RAILs, booleans are DETENTs. Nothing is a row in
a list.

### 9.4 Still a decision, not a setting

These cannot honestly be runtime toggles — they change what gets built or
shipped, and pretending otherwise would just hide the question:

1. ~~**Default theme.**~~ **DECIDED 2026-07-30 — HALO FIELD.** Build this one
   top-to-bottom first; it exercises every zone and primitive with no exotic
   rendering. `theme.js` already ships it as `THEMES[0]`.
2. **Build all nine themes, or three plus the theme SDK?** HALO FIELD + SEELE +
   RECON proves the abstraction cheaply. I would not build nine before the first
   is validated on hardware.
3. **`libmeshcore` `compileSdk` → 36.** Trivial, but it is shared with the SNS
   app, so it needs your sign-off.
4. **Do the lobospeak robot-control surfaces (S8 triggers) ship in v1?** The
   safety design is real work.
5. **Which terrain packs ship bundled vs. downloaded?** A coarse global relief
   pack (z0–8) is tens of MB and makes TERRAIN useful on a fresh install with no
   network. Beyond that, region downloads. Where is the line?
6. **Is the JP 5 m GSI pack a launch feature?** Materially better terrain in a
   launch market for one attribution line — which argues for launch.
7. **Do we ship Overture Places at all?** Protomaps' POI layer may suffice. My
   default is no for v1.

And two that are **validation tasks**, not decisions — they need hardware, and
the answer changes a default rather than the design:

8. **Sunlight prototype before committing to VECTORLINE or BIOLUME.** ~2 days,
   de-risks the two most expensive themes.
9. **The thumb-along-index gesture.** Recommended on reasoning — self-haptics,
   proprioception, single-hand — not on measurement. If ARCore cannot resolve
   thumb-to-index travel reliably, `gesture.reelScroll` falls back to `airSwipe`
   and the design gets worse. The HAND MENU and the REEL share the gesture, so
   **one test settles both.** This belongs in P2, not P4.

---

## 10. Proposed sequencing

### P0 — DONE, verified on hardware 2026-07-30

All three checkpoints passed on a Google XR Puck (Aura class) against a live
MeshCore radio.

| | Result |
|---|---|
| **1** builds, installs, launches | toolchain + JBR pinning + composite build **links at runtime** |
| **2** `Subspace { SpatialPanel { } }` | spatial UI renders; Home Space → Full Space transition works |
| **3** BLE handshake from the glasses | `CMD_APP_START` → `RESP_CODE_SELF_INFO` decoded by `libmeshcore` |

Checkpoint 3 is the one the project rested on, and it holds: Nordic's BLE stack,
`AndroidBleTransport`, `MeshcoreSession` and the pure-Java codec all work
**unmodified** on XR hardware — the same code as the Flutter app's Java twin, on
the same pinned firmware. The radio reported
`910.525 MHz · SF7 · BW 62.5 · CR 5 · TX 22 dBm · advType=1 (ADV_TYPE_CHAT)`.
**Everything downstream is UI work.**

#### Five findings that cost time, or would have

1. **`xr.immersive` is `no` on the Aura** while `xr.api.spatial` and
   `xr.api.openxr` are `YES`. The starter guide's
   `<uses-feature android:name="android.software.xr.immersive" android:required="true"/>`
   would have **rejected the APK at install**. Gate on
   `LocalSpatialCapabilities`, never on the immersive feature.
2. **An XR app starts in Home Space** — an ordinary 2D window where
   `isSpatialUiEnabled` is false. Full Space must be *requested*, and
   `requestFullSpace()` is a **suspend** call returning a result that can be a
   refusal. Spatial UI is a state you transition into, never one to assume.
   MeshmoreXR requests it itself at startup; the 2D path stays fully functional.
3. **The radio requires a bonded BLE link.** `AndroidBleTransport` never
   initiates bonding, so an unpaired client connects, discovers services, sends
   `APP_START` — and hangs in `HANDSHAKING` forever, indistinguishable from a
   protocol bug. Worth fixing upstream in `libmeshcore-android`.
4. **BLE pairing variants need different responses.** Answering a
   passkey-confirmation with `setPin()` fails silently. Read
   `EXTRA_PAIRING_VARIANT` and branch: PIN/passkey → `setPin()`,
   confirmation/consent → `setPairingConfirmation(true)`.
5. **`androidx.lifecycle` 2.11.0 requires AGP 9.1+ and compileSdk 37.** AGP is
   pinned at 8.10.1 to match `libmeshcore-android` (a composite build cannot
   sensibly load two AGP versions), so lifecycle is force-held at 2.10.0.
   **AGP is now at 9.3.1** — migrating is a real decision that must move
   `libmeshcore-android` too, since it is shared with the Flutter SNS app.
   Separately, BouncyCastle (via `libmeshcore`) collides with jspecify on
   `META-INF/versions/*/OSGI-INF/**` and must be excluded in `packaging`.

#### S2 LINK, revised by what we learned

The radio's PIN is **random per boot** whenever it has a display
(`MyMesh.cpp:932`), shown on a 64×48 OLED. Reading six digits off a 13 mm panel
and entering them in XR is exactly the misery S2 LINK exists to remove — it cost
two cycles to a single misread digit on the night we built it.

**A QR on the radio's own screen is not the answer.** At a 0.210 mm pixel pitch,
QR v1 with its mandatory quiet zone yields 0.210 mm modules — below the ~0.25 mm
a close-range camera needs — and dropping the quiet zone to reach 0.419 mm
breaks most decoders. Micro QR M2/M3 fits at 0.419 mm but is poorly supported,
including by ARCore's `QrCode`. The binding constraint is focus anyway: headset
cameras are fixed-focus for scene distance and will not macro-focus on a 6 mm
target.

So: `QrCode` stays in S2 LINK for **contact and channel-key exchange between
operators** — off a phone screen or a printed card, where the code is 30 mm+.
For pairing, the options are the on-screen PIN (entered once, then the bond
persists) or a **static PIN** on rigs you control.

---


| Phase | Deliverable | Proves |
|---|---|---|
| **P0** | Gradle skeleton, composite build, `Subspace { SpatialPanel { } }` renders, `libmeshcore` handshake to a real T1000-E over BLE from glasses | The stack is real end-to-end |
| **P1** | The five-zone framework + the seven primitives, HALO FIELD only | **The load-bearing abstraction** |
| **P2** | S1 HORIZON + S2 LINK + S3 NODE FOCUS live on hardware | The paradigm works, or doesn't |
| **P3** | S4 SPEAK with offline STT/TTS; audio pack #1; MICROHUD; HAND MENU; full parity pass | The interaction model |
| **P4** | S6 TERRAIN: TABLE → FLOOR scale ladder, bearing-locked floor map, Terrarium DEM → mesh, ported GeoNames gazetteer, PMTiles packs + S8 PINS | Spatial mapping, and whether the floor bearing-lock feels as good as it reads |
| **P5** | SEELE + RECON themes | The theme system is genuinely data |
| **P6** | S10 UPLINK + Tier-2 services | Superpowers |
| **P7** | Sunlight prototype → pick and build the showpiece theme | The wow |

**P1 and P2 are the whole risk.** If the zone framework and the HORIZON don't
feel right on real hardware, everything downstream changes — so get to P2 before
building anything else, and validate on the device, not the emulator (it lies
about hands).

---

## References

Internal: `AiRspace-UI.md` · `AiRspace-HUD-and-symbology.md` ·
`MeshmoreXR-audio-haptics.md` · `MeshmoreXR-i18n-ja.md` · `airspace-ui/README.md` ·
`AndroidXR_Glasses_Dev_StarterGuide.md` · `AndroidXR_Glasses_UX_Best_Practices.md` ·
`UX-XR-best-practices.md` · `meshmore-sns-UX-brief.md` · `meshmore-sns-spec.md` (R25/R26/R27) ·
`lobospeak-design.md` · `lobospeak-mappins-spec.md` · `libmeshcore/README.md` ·
`libmeshcore-android/README.md`

External: [Jetpack Compose for XR](https://developer.android.com/jetpack/androidx/releases/xr-compose) ·
[SceneCore](https://developer.android.com/jetpack/androidx/releases/xr-scenecore) ·
[ARCore for Jetpack XR](https://developer.android.com/jetpack/androidx/releases/xr-arcore) ·
[XR Runtime](https://developer.android.com/jetpack/androidx/releases/xr-runtime) ·
[MapLibre Android PMTiles](https://maplibre.org/maplibre-native/android/examples/data/PMTiles/) ·
[Protomaps basemaps](https://github.com/protomaps/basemaps) ·
[PMTiles for MapLibre](https://docs.protomaps.com/pmtiles/maplibre) ·
[Vosk offline STT for Android](https://alphacephei.com/vosk/android) ·
[AWS Terrain Tiles (Terrarium)](https://registry.opendata.aws/terrain-tiles/) ·
[Copernicus DEM GLO-30](https://registry.opendata.aws/copernicus-dem/) ·
[GSI 標高タイル (Japan DEM)](https://maps.gsi.go.jp/development/demtile.html) ·
[GSI tile terms of use](https://maps.gsi.go.jp/development/siyou.html) ·
[Overture Maps — attribution & licensing](https://docs.overturemaps.org/attribution/) ·
[Protomaps basemap data licence](https://github.com/protomaps/basemaps/blob/main/LICENSE_DATA.md) ·
[XREAL Aura 70° hands-on](https://roadtovr.com/xreal-aura-ar-glasses-android-xr-hands-on-preview/)
