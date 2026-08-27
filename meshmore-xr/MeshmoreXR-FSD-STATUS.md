# MeshmoreXR — FSD STATUS

**Against `MeshmoreXR-design-brief.md`, as of 2026-08-25 · 0.3.0-debug.143 ·
686 unit tests, 0 failures.**

The design brief is the FSD. Its own status header said *"no production Android
code exists yet"* until today, which was true on 2 August and has been wrong for
three weeks. This file is the running answer to "what is built, what is not, and
what is deliberately not".

Status vocabulary, used exactly:

| Mark | Means |
|---|---|
| **BUILT** | In the app, exercised on the Aura or on a live mesh |
| **BUILT — UNWORN** | In the app and unit-tested; never confirmed by a wearer |
| **PARKED** | Deliberately not built. The reason is stated and still holds |
| **NOT BUILT** | Owed, no decision against it |

---

## 1. The thirteen surfaces

| | Surface | Status | Where |
|---|---|---|---|
| S0 | FIRST LIGHT | **BUILT** | `spatial/FirstLight.kt`, `spatial/Beckon.kt` |
| S1 | HORIZON | **BUILT** | `spatial/Horizon.kt`, `MeshNodes.kt`, `Hud.kt` |
| S2 | LINK | **BUILT** | `MeshLink.kt`, `spatial/Advice.kt` |
| S3 | NODE FOCUS | **BUILT** | `spatial/Focus.kt`, `spatial/RadialMenu.kt` |
| S4 | SPEAK | **BUILT** | `spatial/Crown.kt`, `Dictation.kt`, `Autopen.kt` |
| S5 | CHANNELS | **BUILT** | `spatial/Bands.kt`, `Channels.kt`, `spatial/TagPad.kt` |
| S6 | TERRAIN | **PARKED** | `MeshmoreXR-map-views-TODO.md` |
| S7 | WAYFIND | **PARKED** | — |
| S8 | PINS & TRIGGERS | **PARKED** | — |
| S9 | TELEMETRY | **BUILT** | `spatial/Rack.kt`, `TelemetryPerms.kt`, `TelemetryAsk.kt` |
| S10 | UPLINK | **NOT BUILT** | — |
| S11 | THEME & VOICE | **BUILT** | `spatial/ThemePicker.kt`, `Synth.kt`, `Motifs.kt` |
| S12 | ABOUT · TERMS · SAFETY | **BUILT** | `aboutRows`, `PRIVACY.md` |

**Ten of thirteen are built.** The three parked ones share one cause and it is
worth stating plainly rather than thirteen times: **S6, S7 and S8 all need a
terrain substrate and world-locked anchors that do not exist on this hardware
yet.** Two of the platform's three geospatial modes SIGSEGV the Aura, so there
is no true north and no earth-fixed frame to hang a map, a route or a dropped
pin on. They are not late; they are blocked on the device.

S10 UPLINK is the "online superpowers" tier. It is out of scope for a beta whose
entire pitch is offline-first, and nothing else depends on it.

---

## 2. Built beyond the brief

Things the FSD did not ask for, which the work produced anyway. Every one came
from a measurement or an operator report, and each is load-bearing now:

| What | Why it exists |
|---|---|
| **Delivery ledger** (`TxLog.kt`) | The app said "sent" for messages that never arrived. 1-in-10 loss proved real, over the air |
| **Meshbook** (`Meshbook.kt`) | What kind of day the mesh had, from messages already on the device. Now with topics |
| **WX from chat** (`Wx.kt`) | Every radio ships telemetry DENY, so measured weather returns nothing. People say it is raining instead |
| **Signal reports** (`SignalReport.kt`) | Other people's bots measure our transmitter for free, and the app was discarding it as text |
| **Node identity** (`NodeTags`, `Search`) | Favourites, tags and search over 350 peers |
| **Alerts** (`Alerts.kt`) | Things worth recording that are not worth a card in your face |
| **Audio** (`Synth`/`Motifs`/`Audio`) | 14 motifs, 9 timbre packs, generated — no shipped assets |
| **Japanese** (`values-ja`) | Full second locale, cell-width aware, parity enforced by a failing build |
| **Hands / ASL** (`Hands.kt`, `HandSign.kt`) | A dead tracker presented as five different surfaces being broken |

---

## 3. What remains before a beta

Ordered by whether it blocks a public build.

### 3.1 Blocking — needs a decision from the operator

1. ~~The transmit allow-list.~~ **RESOLVED 2026-08-25, build 143.**
   `ALLOWED_SUFFIXES` is gone. See §5 for what replaced it.
2. **Play App Signing.** Irreversible at first upload. See
   `RELEASE-SIGNING.md` and playbook §3.
3. **Japanese, or English-only for beta.** The reviewer's pass has not come
   back, and **nine** strings were added after they received the form — five for
   WX and Meshbook, four for claiming a node.

### 3.2 Blocking — work, not decisions

4. **`targetSdk` is 35**; `compileSdk` is already 36. Play enforces a minimum
   target API for new submissions and it moves annually — confirm the current
   floor in Play Console before building the bundle. The bump is small; the
   behaviour changes it brings are not automatically safe.
5. **Store assets** — icon, feature graphic, screenshots, and the video. See
   playbook §5.
6. **A hosted privacy policy URL.** `PRIVACY.md` exists and says the right thing
   ("we collect nothing"); Play needs it at a public URL.

### 3.3 Not blocking, but owed

- **Wearer confirmation** of the reach trail, the bay back-stack, menu
  exclusivity, the audio, floor reset and the compass cycle — all BUILT —
  UNWORN. The punch list carries these as glass checks.
- **`altM`** is implemented and has never been observed carrying a value.
- **Direct-vs-flood** still needs a third listening radio to settle.
- **The delivery bay** goes stale if left open.
- **Documented worst-case round trip** in `MeshLink` says 1.6 s; the 23 August
  soak measured 3,558 ms.

---

## 4. The brief's own open questions (§9), answered

| Question | Answer |
|---|---|
| Telemetry reciprocity gate | **Ruled out.** Asking is fine without sharing; the app offers to turn sharing on |
| Channel transmit | **On**, operator-authorised. PUBLIC can never be soaked |
| Silent theme | **Still open.** VOID is the candidate; `Cue.enabled` is the seam |
| Boot cover on a half-loaded horizon | **Still open** |
| Theme differentiation | **Still open** — waiting on the operator, not on work |
| Distribution channel | **Being answered now:** Google Play open beta |

---

## 5. The transmit rule, as it now stands

The hardcoded allow-list is removed. What replaced it is not a longer list — it
is a different question. The old rule asked *which peer is this*; the new one
asks **who is doing the asking**.

| | May transmit to | Gate |
|---|---|---|
| **A person** — picked a node, typed a message | anyone the radio can address | the crown's arm/confirm step |
| **The app** — soak, path probe, anything unattended | only **claimed** nodes | `MeshLink.isOwnNode`, a pinned 32-byte key |

The protection the operator originally asked for is intact and in fact
stricter. A four-character suffix is something a stranger's key can collide
with — and did: a contact called `7182`, 12,486 km away, was messageable
because its key ended in `d563`. A full-key pin cannot collide.

**Claiming** is a new spoke on the node menu (`MINE`), reversible, transmits
nothing, and requires a full key — a claim on an advert prefix would claim
whatever else shares it. The operator's own `ab60`/`d563` radios were already
pinned by the old code and stay claimed; nothing needs redoing on this device.

`AllowListTest` was deleted rather than adapted. It held a private copy of the
old rule and therefore **kept passing after the rule was deleted** — the most
dangerous shape a green test can have. `OwnNodeTest` replaces it and is written
against the requirement rather than the implementation.
