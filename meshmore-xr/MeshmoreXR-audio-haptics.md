# MeshmoreXR — Audio & Haptics Specification

Nine themes, one event taxonomy, one notification model.
Companion to `MeshmoreXR-design-brief.md` and `AiRspace-UI.md`.

---

## 1. Principles

1. **Android XR gives you no built-in UI sound.** If the design needs audio — and
   per L3 it does — we build all of it.
2. **Procedural synthesis, zero audio assets.** Oscillators + noise + envelopes.
   No binary files, no localization, no licensing, and it **unit-tests as pure
   math** (assert non-silent, correct duration, expected dominant frequency).
   This is the single best decision available here and it is already proven in
   the RobotARme port.
3. **Route everything as `USAGE_MEDIA`.** Assistant and sonification usages get
   ducked or misrouted on headsets — field-confirmed, a spoken readout was
   inaudible until switched.
4. **No information by sound alone.** Every cue has a synchronised visual and an
   optional haptic. The audio pack is an augmentation channel.
5. **Sound identity follows the user.** Read the audio profile from the server so
   the same account sounds the same on phone, browser, and glasses.
6. **Audio ON by default during pre-login/first-run.** The user has no profile
   yet; silence there reads as broken.

---

## 2. The event taxonomy

All nine themes implement **all sixteen** events. A theme may render an event as
*deliberate silence* (SEELE, §4.4) but may never leave it unimplemented — the
visual and haptic channels still fire.

### Interaction (immediate, < 30 ms budget)

| # | Event | Fires when | Duration |
|---|---|---|---|
| E1 | `PROXIMATE` | Hand enters 15 cm of a control | 40 ms |
| E2 | `HOVER` | Gaze or hand acquires a control | 40 ms |
| E3 | `COMMIT` | Selection confirmed | 90 ms |
| E4 | `DENY` | Action invalid or unavailable | 140 ms |
| E5 | `DETENT` | One step of a Rail / Tumbler / Ratchet | 25 ms |
| E6 | `SEAT` | A Detent settles into a well | 70 ms |

### Mesh (ambient, may be dense)

| # | Event | Fires when | Duration |
|---|---|---|---|
| E7 | `NODE_FOUND` | New peer enters the mesh | 250 ms |
| E8 | `NODE_LOST` | Peer ages out | 200 ms |
| E9 | `PACKET` | Any RX/TX — the mesh breathing | 30 ms |
| E10 | `MSG_CHANNEL` | Channel message received | 300 ms |
| E11 | `MSG_DIRECT` | **DM received — must be sonically distinct from E10** | 400 ms |
| E12 | `MSG_ACK` | Our message acknowledged | 120 ms |

### System (rare, high-salience)

| # | Event | Fires when | Duration |
|---|---|---|---|
| E13 | `LINK_UP` / `LINK_DOWN` | BLE radio connects / drops | 500 ms |
| E14 | `TIER_CHANGE` | Mesh ↔ Uplink transition | 600 ms |
| E15 | `QUEUE_FLUSH` | Queued messages sent on reconnect | 400 ms |
| E16 | `CRITICAL` | Safety, emergency, lobospeak HALT | 1200 ms |

### 2.1 Density control — mandatory

`E9 PACKET` on a busy mesh can fire dozens of times per second. Without limits
the app becomes unwearable. Three mechanisms, all always-on:

- **Rate ceiling.** E9 is capped at 4/second; excess events are *counted*, not
  queued, and the count drives a visual density change instead.
- **Voice stealing.** Maximum 6 concurrent voices. Newest wins for interaction
  events; oldest is stolen for mesh events.
- **Ambient decay.** After 20 s of continuous traffic, E9's gain floors at −18 dB
  and only recovers after 10 s of quiet. The mesh should *feel* busy without
  becoming fatiguing.

`E16 CRITICAL` is exempt from all three, ducks every other voice by 12 dB, and
is the only event permitted to interrupt.

---

## 3. Haptics — the honest version

**Optical see-through glasses in this class generally have no haptic actuator.**
Some have a temple touchpad; none have a reliable body actuator. So haptics
cannot be assumed, and the fallback is not an edge case — **it is the likely
default.** This needs verifying against the actual Aura hardware before any of
it is built.

### 3.1 Routing tiers

| Tier | Path | Latency | Use for |
|---|---|---|---|
| **H0** | No actuator anywhere | — | **Assume this.** Audio + visual must be fully sufficient on their own. |
| **H1** | Paired phone in pocket, via the companion link | ~40–120 ms | Confirmations and alerts **only** |
| **H2** | Wrist wearable | ~15–40 ms | Everything except E1/E2 |
| **H3** | On-frame actuator, if the hardware has one | < 10 ms | Everything |

### 3.2 The consequence, stated plainly

At H1 — the realistic best case for most users — **haptics are too slow for
hover.** A 40–120 ms delayed buzz after a hover cue does not read as feedback;
it reads as lag, and it actively degrades the interaction.

So the rule is:

> **Haptics fire on E3, E4, E6, E11, E13, E14, E16 only.**
> E1, E2, E5, E7–E10, E12, E15 are audio + visual.

This contradicts a naive reading of the triple-cue law (L3), and the resolution
is worth being precise about: L3 requires that **no channel is load-bearing
alone**, not that all three fire on every event. An event carried by two
synchronised channels satisfies it. An event carried by one does not.

### 3.3 Vocabulary

Built on Android's `VibrationEffect.Composition` primitives so patterns are
portable and cheap:

| Pattern | Composition | Feel |
|---|---|---|
| `tick` | `PRIMITIVE_TICK` | Detent, step |
| `click` | `PRIMITIVE_CLICK` | Commit |
| `thud` | `PRIMITIVE_THUD` | Seat, land |
| `refuse` | `CLICK` ×2 @ 60 ms | Denial — deliberately unpleasant |
| `rise` | `PRIMITIVE_QUICK_RISE` | Link up, tier gain |
| `fall` | `PRIMITIVE_QUICK_FALL` | Link down, tier loss |
| `summon` | `THUD` → 180 ms → `THUD` | DM — a "someone wants you" heartbeat |
| `alarm` | `CLICK` ×4 @ 90 ms, full amplitude | Critical only. Never themed. |

Intensity is user-scalable 0–200%, and **`alarm` ignores the scale** — a safety
signal is not a preference.

---

## 4. Spatial notifications

The notification model is **identical across all nine themes**. Only the
character of the sound differs. This is deliberate: a user who switches themes
must not have to relearn what "someone is messaging you" means.

### 4.1 The core idea

> A notification is not a card. It is a **direction**.

When a message arrives, the sound is **spatialized to the true bearing of the
sender**, and an EMBER ignites at the viewport edge on that side. You turn
toward it to read it. Nothing ever appears in front of your face uninvited.

This is the whole notification design, and it is only possible in XR. It is
also, not incidentally, how humans already handle "someone said your name across
the room."

### 4.2 Three salience levels

| Level | Sound | Visual | Haptic | Enters forward FOV? |
|---|---|---|---|---|
| **AMBIENT** | none | HORIZON mote brightens + PULSE | none | never |
| **DIRECTIONAL** | spatialized, at sender's bearing | EMBER at the matching viewport edge, ~3 s decay | `summon` (H1+) | never |
| **INTERRUPT** | non-spatial, ducks everything | INTERPOSE approaches | `alarm` | **yes — the only one** |

Defaults: channel traffic is AMBIENT. DMs and favourited-node events are
DIRECTIONAL. **INTERRUPT is reserved for safety** — lobospeak HALT, geofence
breach, critical device state — and is not user-assignable to a chat channel.
The temptation to let people set a group chat to INTERRUPT is exactly how
notification systems become hostile.

### 4.3 Bearing-unknown fallback

A node with no position estimate has no bearing to spatialize to. It **must not**
be given a fake one. Such notifications play **non-spatially** (dead centre,
equal both ears) and their EMBER appears in the dedicated unlocated arc. The
user learns that "centred = position unknown," which is real information.

### 4.4 Silence as a design choice

SEELE MONOLITH renders E1, E2, E5, E7, E9, and E12 as **actual silence** — not
a quiet sound, no sound at all. This is legitimate under §1.4 because the visual
channel carries them fully (the monoliths change), and it is the theme's entire
thesis. Any theme may declare an event silent; **no theme may declare E16
silent.**

---

## 5. The nine packs

Each: **palette of timbre · the six interaction events · mesh character ·
notification character · haptic bias · TTS voice.**

Frequencies are starting points for the synth, not gospel.

---

### 5.1 HALO FIELD — "Sonar"

- **Timbre.** Sine and triangle, soft attack, long release. One filtered noise
  band for texture. Nothing harmonically complex.
- **Interaction.** `PROXIMATE` 880 Hz sine, −24 dB, 40 ms. `HOVER` 1046 Hz,
  −18 dB. `COMMIT` 1318→1568 Hz rising two-tone. `DENY` 220 Hz square, short
  decay. `DETENT` 60 Hz-modulated click. `SEAT` 392 Hz with body.
- **Mesh.** `NODE_FOUND` is the signature: a **sonar ping** — 720 Hz sine, fast
  attack, 250 ms exponential decay, slight pitch droop. Sonically mirrors the
  HORIZON. `PACKET` is a −30 dB tick you feel more than hear.
- **Notification.** `MSG_CHANNEL` a gentle two-note figure (523 → 659 Hz).
  `MSG_DIRECT` the same interval *inverted and doubled* — instantly
  distinguishable, obviously related. Spatialized.
- **Haptic bias.** Light. `tick`/`click`, nothing heavier than `thud`.
- **TTS.** Calm, natural, rate 1.0. The reference voice.

### 5.2 NERV SPATIAL — "Mission Control"

- **Timbre.** Square and pulse waves, hard gates, no reverb. Deliberately
  synthetic — this is a machine talking to you.
- **Interaction.** `HOVER` a 2 kHz data chirp, 30 ms. `COMMIT` a three-step
  ascending gated pulse. `DENY` a descending minor third with a klaxon edge.
- **Mesh.** `NODE_FOUND` a MAGI-style four-pulse burst. `PACKET` a telemetry
  tick on a 4 Hz grid — the mesh becomes a **rhythm**, and the tempo *is* the
  traffic rate.
- **Notification.** Announced, not suggested: a two-tone attention signal then
  the EMBER. Under a long operation, an audible **countdown tick** runs.
- **Critical.** The theme's showpiece — the palette inverts to red, the scanline
  triples, and a three-tone alert cadence repeats until acknowledged. The most
  unmissable state in the app.
- **Haptic bias.** Sharp. `click` on everything eligible; `alarm` feels at home.
- **TTS.** Clipped, procedural, rate 1.15.

### 5.3 AG-SYSTEMS — "Velocity"

- **Timbre.** Filtered saw sweeps, short reverb tails, doppler pitch bends.
  Glossy and produced.
- **Interaction.** `HOVER` a 30 ms upward filter sweep. `COMMIT` a doppler
  *whoosh-tick* — pitch rises then snaps. `DETENT` a resonant blip whose cutoff
  tracks the value.
- **Mesh.** `NODE_FOUND` a craft passing: stereo-panned doppler across the
  bearing. `LINK_UP` the three-note race-start triad (the theme's hook).
- **Notification.** Arrives *with motion* — the sound sweeps in from the sender's
  bearing to the edge as the EMBER ignites. The only theme where the
  notification moves.
- **Haptic bias.** `rise`/`fall` heavy — momentum is the identity.
- **TTS.** Smooth, announcer-adjacent, rate 1.05.

### 5.4 SEELE MONOLITH — "Tribunal"

- **Timbre.** Sub-bass sine (40–90 Hz) and one low choral pad. Nothing above
  400 Hz, ever.
- **Interaction.** `PROXIMATE`, `HOVER`, `DETENT` are **silent**. `COMMIT` is a
  single 60 Hz strike with a long tail. `DENY` is a 45 Hz double strike.
- **Mesh.** `PACKET`, `NODE_FOUND`, `MSG_ACK` **silent**. The monoliths change;
  that is the notification.
- **Notification.** `MSG_DIRECT` gets one low choral swell, ~2 s, and nothing
  else. Channel messages are silent — the slab changes.
- **Critical.** The only loud thing this theme ever does, and it is genuinely
  startling by design.
- **Haptic bias.** Heavy and rare. `thud` only. One firm pulse means something.
- **TTS.** Slow, grave, rate 0.85, pitch −15%.
- **Note.** This is the accessibility benchmark *because* it is near-silent —
  every event is fully carried visually, which is the parity requirement proven
  by construction.

### 5.5 DR POP — "Pure Phase"

- **Timbre.** TR-909-adjacent drums, vinyl crackle bed, detuned saw stabs,
  bit-crushed. Maximalist and musical.
- **Interaction.** `HOVER` a 909 rimshot. `COMMIT` a stab chord. `DENY` a record
  scratch. `DETENT` a hi-hat tick.
- **Mesh.** `PACKET` is a **quantized 16th-note hat** — the mesh literally
  becomes a beat, and the tempo tracks traffic. `NODE_FOUND` is a filtered riser
  resolving to a stab.
- **Notification.** Arrives on the next beat, not immediately. Up to ~180 ms of
  latency, deliberately, so notifications land *musically*. The one place we
  trade latency for character, and it works because DIRECTIONAL notifications
  are never urgent (§4.2).
- **Haptic bias.** Rhythmic. `tick` patterns doubled for syncopation.
- **TTS.** Bright, lightly formant-shifted, rate 1.1.
- **Care.** Loudest pack by a distance; ships at −6 dB relative to the others and
  needs the most aggressive density limiting (§2.1).

### 5.6 RECON AMBER — "Codec"

- **Timbre.** Band-limited 300–3400 Hz — a radio channel. Every sound passes the
  same filter, so the pack is **sonically monochrome exactly as the palette is
  visually monochrome.** The best-integrated theme in the set.
- **Interaction.** `HOVER` a squelch tick. `COMMIT` a PTT key-up chirp. `DENY` a
  squelch burst.
- **Mesh.** `NODE_FOUND` a codec-style two-tone ring. `PACKET` a faint carrier
  crackle whose density *is* the traffic rate.
- **Notification.** An incoming-call codec ring, spatialized. Unmistakable and
  entirely in character.
- **Haptic bias.** Minimal, matching the low-power thesis.
- **TTS.** Flat, band-limited through the same filter, rate 1.0.

### 5.7 VECTORLINE — "Arcade"

- **The standout.** Every interaction is a **musical note quantized to a scale**,
  and the scale shifts with mesh state: quiet mesh → minor pentatonic; busy mesh
  → major; critical → diminished. **The mesh's health is audible as harmony.**
- **Timbre.** Pure geometric waves — sine, triangle, square — with additive
  harmonics mirroring the additive rendering. No noise, no reverb.
- **Interaction.** `HOVER` is the root. `COMMIT` is the fifth. `DENY` is a
  tritone. `DETENT` walks the scale, so a Rail literally plays a run.
- **Mesh.** `NODE_FOUND` is an arpeggio whose length encodes hop count.
  `PACKET` plays a scale degree chosen by the node's bearing — **the mesh is a
  generative composition and its spatial layout is its melody.**
- **Notification.** A two-note motif transposed to the sender's bearing —
  regular users will learn to recognize *who* is messaging by pitch alone.
- **Haptic bias.** On the beat.
- **TTS.** Clean synthetic, slight formant shift, rate 1.0.
- **Risk.** The most ambitious pack and the one that most needs a real
  implementation to judge. Prototype before committing.

### 5.8 BIOLUME — "Bloom"

- **Timbre.** Granular. Every sound is a cloud of short grains from a breath/
  wood/glass source, with randomized grain position, pitch (±3%), and density.
  **Generative — no two events are identical**, but each class holds a stable
  timbral centre so it stays learnable.
- **Interaction.** `HOVER` a soft breath. `COMMIT` a bloom that opens and
  settles. `DENY` a grain cloud that collapses inward.
- **Mesh.** `NODE_FOUND` a bloom rising in pitch as the mycelial thread grows —
  **the sound and the visual are the same event**, which is the theme's thesis.
  `PACKET` is a single grain; a busy mesh sounds like light rain.
- **Notification.** A chime cluster, spatialized, with a slow 4 s decay. The
  least alarming notification in the set — deliberately, because this theme is
  for wearing all day.
- **Haptic bias.** Soft. `thud` with low amplitude, long ramp.
- **TTS.** Warm, unhurried, close-mic'd, rate 0.95.
- **Note.** Lowest listener fatigue of the nine, and the only pack that never
  repeats itself.

### 5.9 TERMINAL VOID — "Teletype"

- **Timbre.** Filtered noise bursts and mechanical transients. Aggressively
  lo-fi; 8-bit quantized on purpose.
- **Interaction.** `HOVER` a key travel tick. `COMMIT` a full key clack. `DENY`
  a real **BEL** (`0x07`). `DETENT` a platen ratchet.
- **Mesh.** `PACKET` a single teletype character strike — **a busy mesh sounds
  like a room full of teletypes**, which is both correct and delightful.
  `NODE_FOUND` a carriage return + line feed.
- **Notification.** BEL, then the message types itself in. Non-spatialized by
  default (a teletype has no bearing) — the one theme that opts out of §4.1, and
  the honest justification is that its whole identity is a 2D terminal, which is
  also why it is the Vectrex exception (`AiRspace-UI.md` §5).
- **Haptic bias.** Mechanical. `click` at full amplitude, short.
- **TTS.** Classic formant synthesis — an affectionate DECtalk reference,
  rate 1.0.

---

## 6. Parity, settings, and defaults

- **Audio pack is independent of TTS.** Two separate switches. TTS defaults
  **off**; the audio pack defaults **on**.
- **"Visual + haptic only" mode** is a shipped setting, not an accessibility
  afterthought.
- **Per-event mute** — a user who wants the mesh silent but confirmations audible
  can have that. Sixteen events, six toggle groups.
- **Respect the OS silent / reduce-sound setting.** When silenced, DIRECTIONAL
  notifications escalate their **visual** salience to compensate, so the
  information is not simply lost.
- **Master gain, per-pack normalization.** Every pack is loudness-matched at
  build time so switching themes doesn't change how loud the app is.
- **Ducking:** TTS ducks the pack by 9 dB; `E16 CRITICAL` ducks everything by
  12 dB.

## 7. Testing

Procedural synthesis is testable, and this is most of the argument for it:

- **JVM unit tests, no device.** For each of 9 packs × 16 events: assert
  non-silent, assert duration within tolerance, assert expected dominant
  frequency via FFT, assert peak amplitude within the normalization window. That
  is 144 cases and they run headless in under a second.
  Set `unitTests.isReturnDefaultValues = true` so audio stubs no-op instead of
  throwing `"Stub!"`.
- **Parity test.** A lint rule asserting every event has a registered visual cue.
  A pack that adds a sound without a visual should fail the build.
- **Density test.** Simulate 200 packets/sec and assert the rate ceiling, voice
  stealing, and ambient decay all engage.
- **Instrumented.** Only routing (`USAGE_MEDIA`), spatialization, and actual
  haptic availability need a device — and haptic availability is the open
  hardware question in §3.
