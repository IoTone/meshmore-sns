# Overview

This is the Meshmore SNS UX.

> **Plan of record, not current behaviour (2026-10-23).** This file is the
> U0–U15 implementation plan as written. Three parts of it were overtaken by
> later work, and `meshmore-sns-spec.md` is the authority where they differ:
> the shell has **six** views with Docs and About moved under Settings (R85,
> R86), body swipe paging is back but gated per pan surface (R109, reversing
> R95's second half), and the grid's chrome was regrouped (R89). Sections
> below still describe the eight-view swipe shell on purpose, as history.

## Design Intent

We want to build a Meshcore client that has a chat interface, and has a dashboard view as the default home screen to summarize the network status, active nodes, etc., for hyperlocal discovery.  Design theme should be inspired by Wipeout 2097 and Evangolion.

## References

- Wipeout_2097 — https://en.wikipedia.org/wiki/Wipeout_2097
- Neon Genesis Evangelion — https://en.wikipedia.org/wiki/Neon_Genesis_Evangelion
- TDR · Wipeout — https://www.thedesignersrepublic.com/project/wipeout
- "How a PlayStation game inspired a generation of graphic designers"
  — https://www.creativebloq.com/news/wipeout-design-inspiration
- WipEout logo history —
  https://imjustcreative.com/wipeout-logo-history/2023/01/18
- Evangelion typography (Fonts In Use) —
  https://fontsinuse.com/uses/28760/neon-genesis-evangelion
- NERV-UI / MAGI convention — https://github.com/lotap/magi-theme
- Bitmap/terminal fonts — https://korigamik.dev/blog/bitmap_fonts/

The sourced design-research synthesis (TDR, Evangelion, cyberpunk
terminal lineage, the Eurostile shared-DNA insight) and the
OSS/Flutter typography plan live in `meshmore-sns-UX-brief.md`.

## Proposals

### Information architecture

Eight primary views (Dashboard, Chat, Nodes, Mesh survey, Map, Settings, Docs, About), navigated via horizontal swipe (R11). Each is a top-level
page in a `PageView`; secondary screens (pair device, edit channel, etc.) are
pushed via `go_router`.

| # | View | Purpose | Maps to spec |
|---|------|---------|---|
| 1 | **Dashboard** (default home) | Network status, RSSI/SNR gauges, peer count, link state, recent events, active-channel summary. Each skin keeps its own layout, paint and block order, every block drawing from one vocabulary (`MmCollapsibleSection`, `MmSectionHeader`, `MmSpace`). Blocks stay on the screen that owns them: a pinning mechanism that moved a block onto the dashboard existed for one day and was removed on 2026-11-05 for want of a use case. | R6, R8, R114 |
| 2 | **Chat** | Full chat for the active channel, with channel-selector chip strip on top. Per-channel TTS toggle in the header. | R6, R5 |
| 3 | **Nodes** | Discovered peers with signal strength, distance estimate, last-heard, and a hook for the future live map (F1). | R6 |
| 3a | **Hyperlocal grid** | Six views at one level, chosen from a single picker row — Radar, Coverage, Weather, Mesh tree, Heat, Altitude — with no sheet to open and no fourth row routing to another tab (both removed 2026-11-05 at the owner's direction, along with the globe; the equal grid was deleted in R117). Every view says what it answers in one muted line, and each states its own empty case. Offline = empty radar + "Not Connected to Mesh"; the view choice lasts the session and launch resets to radar. A left/right swipe changes screen. The views that pan or zoom carry a **Swipe ⇄ Pan** toggle: swipe mode holds the view still so the drag is the shell's, pan mode gives the view every drag and locks the shell, and every visit starts in swipe mode (R109). A node with no reported position is drawn hollow, and no layer on this tab shows a bearing the radio cannot supply. | R18, R25, R109, R116, R117 |
| 3b | **Map** | The street map as its own page after the grid (R61). Pan/zoom owns every horizontal drag, so while this page is the current view the shell's `PageView` does not page (R109) and nothing contests the map's middle of the screen. A 24dp **edge band** on each side (R67) changes view by an inward fling — exactly one view, because the page does not also drag: left edge to the previous view, right edge to the next. Back and the view strip also leave. A corner button opens Settings → Offline maps. Same in every skin: `HomeShell` does not read the skin to build pages. | R25, R61, R109 |
| 4 | **Settings** (hub) | Entry point to the three sub-screens below. | R3,R4,R5,R7,R12,R13,R14 |
| 5 | **About / Terms** | App info + legal. | R9, R10 |

The **Settings** view is a hub that pushes three concept-agnostic
sub-screens via `go_router` (they re-skin to the active theme; not
swipe pages):

| Sub-screen | Purpose | Maps to spec |
|---|---|---|
| **Device configuration** | Meshcore radio (freq/BW/SF/CR/TX power), identity/advert (name, lat/lon, self-advert), channels + PSK / QR import, other params + tuning, device info/battery/time, and **Contact table** (R119: the radio's own add policy — chat/repeater/room/sensor, overwrite-oldest, hop limit — with the count and a way into the radio's contact list, plus the bands it will relay in). Drives the M4 protocol surface. | R7, R119 |
| **App settings** | BLE auto-reconnect (M7 backoff), language EN/JA, TTS global (off by default), notification/critical parity, diagnostics export (M6), About/Terms links. | R3,R4,R5 |
| **Profile & personalization** | Theme preset (the six concepts incl. D high-contrast & F night, plus the R63 **Studio** clean-dark skin) + custom palette, font family & **size scale**, density, **audio alerts master + per-event**, haptics + pattern preview, **accessibility switches incl. one-tap "visual + haptic only"**, identity/advert name. Persisted via `shared_preferences`. | R12,R13,R14 |

### Navigation gestures (R11)

- Horizontal swipe between the primary views (locked while a pan/zoom map is showing: the Map tab, and the grid's street-map/globe views). On the Map tab an inward fling from a 24dp screen-edge band still changes view (R67); the grid's panning views have no edge band yet and are left by Back or the view strip.
- **Swipe is the way.** There is no menu, sheet or drawer that switches
  views (R64; the long-press quick-nav sheet and the hamburger were
  removed). Under the app bar a **view strip** shows one icon per view with
  the current one in the accent. Each icon is a 48x48 button with the
  view's title as its semantic label and tooltip and `selected` on the
  current one, so it is the non-gesture path for screen readers, switch
  access and the locked Map tab. The six cells share the full
  width equally (R86), with no dead space at either edge; it scrolls
  sideways only below 6x48dp (288dp) and keeps the current view in sight.
- **Six views (R85).** Dashboard, Chat, Nodes, Grid, Map, Settings. Docs and
  the information page used to be the seventh and eighth tabs, which put
  static content on the same footing as the things a person switches
  between mid-conversation. They are now rows in the Settings hub, as
  peers (R86): **Docs** (`/settings/docs`) and **Information**
  (`/settings/about`, the brand/version block and the licences page).
  Nothing was deleted, it moved.
- App-bar trailing area shows live status pills: BLE link state, channel,
  TTS on/off.

### Text-to-speech UX (R5)

- TTS is **off by default** (per spec).
- Two scopes:
  - **Global toggle** in Settings (parent switch).
  - **Per-channel toggle** in the Chat header (only enabled when global is on).
- Voice picker (lists native TTS voices via `flutter_tts`); language follows
  the locale unless overridden.
- Critical system messages (e.g. lost BLE link, low battery) get an audible
  alert prefix when TTS is on.

### Audible theme pack (R12)

- Each design concept ships a **matching audible theme pack** — a
  curated set of short UI/event sounds (message in/out, node
  discovered, link up/down, send, critical/alert) plus a TTS voice
  character that matches the visual identity. Six candidate packs
  ("Mission Control", "Velocity", "Sonar", "Tribunal", "Pure Phase",
  "Codec" — one per concept A–F) are previewable by live synthesis in
  `meshmore-sns-UX-brief.html`; the chosen one is specified here once
  the concept is picked.
- The pack is a first-class deliverable, not an afterthought, and is
  **mutable independently of TTS**. A **"visual + haptic only"**
  mode is a shipped setting (default audio = on at low volume;
  honours OS silent / reduce-sound).
- Hard rule: **no sound carries information alone** — every cue has
  the visual + (optional) haptic parity defined below. Implemented as
  a single cue service: `event → {sound, visual, haptic}` so parity
  cannot drift.

### Localization (R4)

- ARB-based localization (`flutter_localizations` + `intl`), one source of
  truth for strings.
- Locales: `en` (default), `ja`.
- Settings exposes an explicit language override; otherwise follow the
  device locale.

### Personalization & theme system (R14)

The chosen design concept is the **default theme**, not a one-time
lock-in. The Profile & personalization sub-screen lets the user
customise appearance and behaviour; settings persist via
`shared_preferences`.

- **Theme presets:** the six concepts (A NERV, B AG-HUD, C
  Hyperlocal, D SEELE High-Contrast, E DR Pop, F Recon Night) ship
  as selectable `ThemeData`/token sets. **Custom** preset = a palette
  editor over the token names (`mm.base/surface/accent/alert/…`).
- **Typography:** font family from the OSS set; **font-size scale
  (S–XL)** layered on top of OS `textScaleFactor`; comfortable /
  compact density.
- **Audio (R12):** master toggle + per-event toggles
  (message/node/link/critical) + volume + pack selector.
- **Accessibility (R13):** high-contrast, reduce-motion,
  one-tap "visual + haptic only", captions, large targets, follow-OS
  bold-text — all live here (single source of truth).
- Implementation: a `ThemeController` (Provider) exposing the active
  token set + text-scale + flags; the `CueService` reads the audio/
  haptic prefs so parity can't drift. D and F are literally the
  high-contrast and low-power/night presets, so accessibility and
  field modes are *themes*, not separate code paths.

### Spacing contract (binding, enforced by a test)

Every gap in the app is a **job**, not a number. `MmSpace`
(`lib/theme/mm_skin.dart`) names the jobs and resolves each to one step of the
ladder (2, 4, 6, 8, 12, 16, 20, 24, 32):

| Job | Step | Used for |
| --- | --- | --- |
| `insideText` | 2 | label to value, title to subtitle |
| `labelToControl` | 4 | a label and the control it names, below a chip row |
| `rowGap` | 8 | between the rows of one list |
| `rowInset` | 12 | a row's own padding, a compact panel's inset |
| `screenEdge` | 16 | a screen's one edge inset, a full panel's inset, a sheet's inset |
| `sectionGap` | 24 | before a new group |
| `emptyState` | 32 | around an empty state |

The rule that makes a group visible: a between-gap is always strictly larger
than the within-gap it contains (rows 8, blocks 16, groups 24).

Companion rules:

- One edge inset per screen (16). A sheet uses 16, never 8.
- `MmListRow` is 12/12 in both paint modes: card and flat differ in paint, not
  in metrics, so a list does not move when the skin changes.
- A divider marks a group boundary, never a row boundary inside a list. A rule
  inside a settings block whose rows carry their own labels is noise: use the
  group gap and the section label instead. A card-mode row carries no
  hairline, so a list never shows a row hairline under a list divider.
- `test/ui/mm_spacing_test.dart` holds an exact per-file count of off-ladder
  numbers in `EdgeInsets` and in `SizedBox(height|width:)`, checked in both
  directions, plus
  assertions that the shared tokens and the job getters are ladder members and
  that a row's leading gap is the same in all eight presets. A new literal has
  to move its file's baseline in the same commit.

### Accessibility & sensory parity (hearing-impaired-first) — design guideline

This is a binding design guideline for **every** screen and the audio
pack (R13). The audible theme pack (R12) must never imply
sound-dependence.

- **Triple-channel parity.** Every notable event is expressed on up
  to three channels — **visual** (always), **audible** (R12,
  mutable), **haptic** (configurable, independent). Visual is the
  baseline; audio and haptic are augmentations. A deaf user must lose
  *zero* information with sound fully off.
- **No sole carriers.** Information is never conveyed by sound alone
  *or* colour alone. Critical/alert states use **icon + text +
  motion** together; status uses shape/label, not just hue.
- **Visible alert region.** A persistent status/alert area surfaces
  link-lost / low-battery / new-message visually (badge + text +
  brief motion), mirroring whatever the audio pack would play.
- **TTS** (R5) is off by default and is an augmentation only; any
  spoken content has its on-screen text/transcript.
- **Respect the platform.** Honour `MediaQuery` `boldText`,
  `textScaleFactor` (to large), high-contrast, and
  **`disableAnimations`/reduce-motion** (scanline, gauge sweeps,
  swipe-sweep all degrade gracefully); honour OS silent / reduce
  sound for the audio pack.
- **Contrast & targets.** AA+ (target ≥7:1 for primary text on the
  dark grounds); interactive targets ≥ 48 dp; one-handed reach;
  usable with gloves. (R69: the last 28-36dp icon buttons, in chat/DM message actions,
  the dashboard refresh, the equal-grid and fabric-survey controls and the
  dense audio toggle, are 48x48; the glyphs are unchanged.)
- **Semantics.** All actionable widgets carry `Semantics` labels;
  swipe navigation (R11) has an accessible equivalent (the R64 view strip:
  labelled 48dp buttons) so it is not gesture-only.
- **Settings.** Independent toggles for audio pack, haptics, TTS,
  reduce-motion override, and high-contrast; a one-switch
  "visual + haptic only" mode.

## Design

### Chosen direction: **D "SEELE Monolith" — default; all six as presets**

**Decision (locked).** Concept **D "SEELE Monolith"** is the
**default theme**: Evangelion *"SOUND ONLY"* brutalism — cream on
true black, one dominant numeral per screen, ruthless hierarchy,
near-zero chrome, status as a full-width slab that colour-inverts to
red on alert. D is *also* the high-contrast / sunlight accessibility
benchmark, so the default is the most legible option.

All **six concepts ship as selectable theme presets** (a seventh, **Studio**, was added by R63, and an eighth, **Studio
Light**, by R115, both below) via the R14
theme system (see *Personalization & theme system*): a single
`ThemeController` swaps a token set + type + motion flags at runtime;
D is just the default token set. The other presets — A NERV, B
AG-HUD, C Hyperlocal, E DR Pop, F Recon Night — are defined token
sets, not separate code paths. (Per-preset palettes are catalogued in
`meshmore-sns-UX-brief.md`; screens are built against the *token
names* below, never hard-coded colours, so every preset works.)

#### Studio Light (R115) — the same tool language on paper
An eighth preset, and the app's only light ground. It exists because every
other preset is dark and a phone in daylight needs the opposite. It is not a
dark skin with pale paint:

- **Ground and ink.** The page is warm paper, not pure white (a white page is
  the one surface a phone cannot dim), and the ink is near-black. The stack
  runs from the page down to the selected state, so a container reads as cut
  into the page; each step is >= 1.08:1 and the four are monotonic.
- **Brightness follows the ground.** `MmTokens.isLight` is derived from the
  base colour's luminance, and `buildMmTheme` takes the scheme's `Brightness`
  from it. A light palette over a dark scheme inherits dark-theme framework
  defaults (elevation tints, splash alpha, disabled ink) and reads washed out.
- **Contrast is recomputed, not inherited.** The shared live-link green is
  1.7:1 on paper, so this preset supplies its own. Every pair the UI draws is
  asserted at WCAG AA: ink >= 7:1 on every layer, muted ink >= 4.5:1, accent,
  alert and ok >= 4.5:1 as text on every layer, label-on-fill >= 4.5:1, and the
  rule colours visible (>= 2.4:1) but subordinate (< 2.6:1 for a hairline).
  The accent is a vermilion that carries selection; the alert is a deeper red
  so a warning never looks like a selection.
- **The map inverts with the theme.** Peer and self markers outline in the
  skin's foreground instead of white, which is invisible on a light basemap,
  and the basemap is not dimmed (dimming pushes a bright map under dark chrome;
  on paper the map belongs to the page). The bundled vector style is a dark
  palette, so this skin keeps raster tiles.
- **The tool rules still hold.** Square control family (1 px floor), words in
  the UI face and monospace for machine data, a tinted group header instead of
  a rule, no ornament.

#### Studio (R63) — clean-dark professional-tool skin
A seventh preset in the language of Blender / GIMP / Photoshop. It is the
only skin that supplies a real **layer stack** (`MmTokens.raised`,
`selected`; base < panel < raised < selected, each step >= 1.08:1
luminance), a `hairline` (1px, `MmShape.hairlineWidth`) and
`onAccent`/`fgDisabled`; the six older presets *derive* these from their
nine colours and look exactly as before. `MmShape.squareControls` makes
Material's own controls square for Studio only. Grouped surfaces use
`MmCollapsibleSection` (label + chevron, 48dp row, content not built when
closed, marked by ONE rule in the border tier above the header (R116)): the
header is never filled and the group draws nothing at its end, so a boundary
is drawn once and the same way in all eight presets. A divider never sits
between a header and its own content. Applied to Location settings, Device configuration
and Personalization. Which groups are folded is persisted per stable id
(R65, `MmCollapseController`, default open). Studio cards and the
app bar (with its view strip) end in a 1px hairline (R66). Studio reuses the
Hyperlocal audio pack and the neutral haptic profile.
From R68 Studio has **no hue at all**: the accent is a light grey (`#D0D0D0`),
alert and ok are low-saturation tints, and selection is shown by lightness.
Studio has its own dashboard (R68): a quiet status row, peers in range, then
collapsible Radio / Location / Recent sections, with the type rule *words are
sans, only machine data is mono*.

#### Routes in the node sheet (R119)
The sheet answers "how does this node reach me" two ways, and they are different questions. **Last advert came via** reads the route the contact's last advertisement took, from the radio's own record (`CMD_GET_ADVERT_PATH`, 0x2A): no mesh traffic, so it is a read, and a zero-length path is shown as *direct* rather than as no route. **Find the route** asks the mesh (`CMD_SEND_PATH_DISCOVERY_REQ`, 0x34), which costs airtime, so it is a tap; the reply carries both directions and both are shown, because an asymmetric link is the answer worth reading. One request of each kind is in flight at a time: the advert-path reply does not name the node, and the discovery reply names only its prefix, so a second answer could not be told apart from the first.

#### Type rule (Studio, R71-R74): words sans, machine data mono

Studio (`MmType.sansLabels`) draws **words in the UI sans face** and
**machine data in JetBrains Mono**. The older six skins keep their own
type unchanged (mono is their identity), so the rule is a Studio rule.

| Mono (machine data) | Sans (words) |
|---|---|
| pubkeys, short ids, hashes, channel keys and PSK hex, share URIs | message bodies, sender and channel names |
| frequency, bandwidth, SF, CR, TX power, voltage, battery % | button, tab, section and chip labels |
| latitude / longitude, altitude, distances | descriptions, help text, empty states, dialogs |
| SNR / RSSI, hop counts and paths, `flood`, packet or JSON hex | docs hub titles and card text |
| timestamps | boot overlay lines, readout labels, status pills |

R75 adds two rules the device pass forced:

- **A mono column is self-aligning, so it needs no fixed width.** A
  fixed-width stamp box (`SizedBox(width: 64/70)`) is narrower than its
  own 8-character `HH:MM:SS` stamp at 12pt, leaving ~3dp of gap and no
  headroom for text scaling. Recent rows are now `Text(stamp)` +
  `SizedBox(width: 10)` + `Expanded(body)`.
- **Brand copy comes from the arb, never a literal.** The splash
  subtitle was a hardcoded Japanese string, so an English device showed
  Japanese while `appSubtitle` already had `Socialrobot Network
  Service`. The splash is the `home:` of a `MaterialApp` that installs
  the locale delegates, so `AppLocalizations.of(context)` resolves
  there.

Mechanism: prose that older skins set in mono uses `skin.type.wordsMono`
(null under Studio, `monoFamily` otherwise); data keeps `monoFamily` or a
literal `'JetBrains Mono'`. Chat rows: `StudioMessageRow` (sender above
body, time and meta mono). Enforced by `test/ui/type_rule_guard_test.dart`
(which skins turn words sans, a docs-hub probe, and a per-file ratchet on
literal `'JetBrains Mono'`). Judging whether a literal is data or prose
is not testable; sites left in mono on purpose are listed in STATUS.

#### Palette — token contract (preset-independent)

Screens reference only these semantic tokens; each preset supplies
values. **Default = D "SEELE Monolith":**

| Token | D default | Use |
|---|---|---|
| `mm.base` | `#000000` | App background (true black) |
| `mm.surface` | `#0E0E0C` | Cards, panels |
| `mm.surfaceAlt` | `#15140F` | Elevated panels, inputs |
| `mm.line` | `#2A2A26` | Hairlines, dividers |
| `mm.fg` | `#EDE6D6` | Primary text (cream) |
| `mm.fgMuted` | `#9A958A` | Secondary text (bone) |
| `mm.accent` | `#EDE6D6` | Primary accent (D = cream; e.g. C → `#35E0F0`) |
| `mm.alert` | `#C8102E` | Critical slab / warnings (SEELE red) |
| `mm.ok` | `#9A958A` | Healthy/neutral (D keeps it austere) |

Every preset defines the same nine tokens (A–F values in the brief).
A light theme is out of scope; presets are dark (D/F darkest).

#### Typography (OSS-only; reference faces are inspiration, not bundled)

The project is MIT-class licensed → **Eurostile/Microgramma,
Matisse EB, Helvetica, Futura are inspiration only, never bundled.**
Substitutes are OFL/MIT and Japanese-capable (R4). Full rationale,
licensing table, per-concept assignment and the Flutter bitmap
constraint are in `meshmore-sns-UX-brief.md`.

- **Display / titles:** **Saira / Saira Condensed** (OFL) — the
  free Eurostile-class squared face; condensed weights deliver the
  Evangelion "mechanical compression". (Alt: Chakra Petch / Michroma
  / Orbitron for the Wipeout team-logo geometry.)
- **Telemetry / console:** **Departure Mono** (OFL 1.1) — modern
  pixel/bitmap mono for the NERV/cyberpunk console layer; lock sizes
  to its 11px grid for crispness. (Alt: Terminus TTF / Cozette.)
- **Japanese + mono:** **M PLUS 1 Code** (OFL) — the linchpin:
  monospace techno *with full Japanese*, covering the console layer,
  R4 localization, and the Wipeout "kanji-as-graphic" motif in one
  license-clean family.
- **Body / fallback:** IBM Plex Sans/Mono (OFL) or system.
- Numerals on telemetry use an outlined **slashed zero** (the
  Evangelion "SOUND ONLY" monolith motif).
- Vendor TTFs under `assets/fonts/` (deterministic/offline) or via
  `google_fonts`.

#### Components

- **Chamfered containers** — panels use a 12 px corner-cut clip-path instead
  of rounded corners (Wipeout panels).
- **Warning chevron headers** — section headers on critical panels use a
  diagonal stripe band (NERV-style "DANGER" header).
- **HUD gauges** — radial gauges for RSSI/SNR, painted in `mm.hud`.
- **Scanline overlay** — dashboard has a very subtle animated scanline
  (1 frame per ~80 ms; opacity ~0.04) for the CRT vibe.
- **Status pills** — `[ BLE • LINK ]`, `[ CH 0 • PUBLIC ]`, `[ TTS • OFF ]`
  in the app-bar trailing area.

#### Motion

- Page transitions: 250 ms ease-out, with a faint colored sweep matching
  the destination view's accent.
- "Acquired/lost" events animate the relevant gauge with a flash.

### UI implementation plan (U-series, app-side)

Mirrors the protocol M-plan discipline (small, analyzed, tested,
committed to the `meshmore-sns` submodule branch).

| ID | Deliverable | Status |
|----|-------------|--------|
| U0 | Theme foundation: `MmTokens` + all 6 presets (D default), `ThemeController` (Provider, persisted via `shared_preferences`), wired into `MaterialApp`; a Personalization screen with the live preset/font/accessibility picker | ✅ done (submodule `cbb80b9`; 24 app tests) |
| U1 | Nav shell: `PageView` swipe + labelled view strip (R11, R64); Settings hub → 3 sub-screen routes (go_router) | ✅ done (submodule `1ef39df`; 27 app tests) |
| UD | **Diagnostics & connect** screen (parallel, unblocks hardware): real Connect/disconnect, live state, raw frame log, test sends, in-app M6 channel-tail oracle + fixture export | ✅ done (submodule `pending`; 30 app tests) |
| U2 | Dashboard (D "monolith" layout) wired to `MeshcoreController` (link/peers/channel/events) | ✅ done — submodule `259a8cb`; 40 app tests |
| U3 | Chat (collapsible, channel switch, R6) + TTS toggle wiring (R5) | ✅ done — ChatScreen wired to `MeshcoreController`: collapsible channel chip strip, per-channel scrollable message list, composer → `SEND_CHANNEL_TXT_MSG` (0x03) + optimistic outgoing, channels probed via `GET_CHANNEL`/named from `CHANNEL_INFO`. `TtsController` (pluggable speaker seam, OFF by default, persisted global + per-channel mute) — functional SPEECH switch in App settings + per-channel toggle in the Chat header; inbound messages spoken through the gate (`ec6e1c6`; 54 app tests) |
| U4 | Nodes screen; Device configuration screen → M4/R7/R15 commands | ✅ done — U4(a+) mesh scan: contacts + adverts + RF-log SNR/RSSI, "Scan area", in-range (`add0649`); U4(b) LoRa region/radio config (R15) — US/EU868 (freq-only) + **Japan/ARIB STD-T108** (920.8 MHz · BW125 · SF12 · CR4/8 · ≤13 dBm, full preset, MeshCore #460) + Custom; freq/BW/SF/CR/TX pre-filled from SelfInfo, wired to `setRadioParams`/`setRadioTxPower` (`1e1e8d3`; 42 app tests). **Channels** built as a dedicated screen (`/settings/channels` `54f5253`: slots, set-active, name+PSK via Public/#hashtag/hex). Advertise flood/zero-hop chooser (`3a53e01`); R16 battery on Dashboard/Diagnostics (`c8fcce9`). Identity/Advert (SET_ADVERT_NAME/LATLON) + Device info (DEVICE_QUERY) built (`1a92509`); only OTHER PARAMS/tuning **editing** remains (currently read-only) → later U-step |
| U5 | App settings + About/Terms (R9/R10); l10n EN/JA (R4) | ☐ |
| U6 | `CueService` (event→sound+visual+haptic parity, R12/R13); audio packs | 🔶 done first cut (`cc8e851`) — CueService + AudioPack/HapticBackend interfaces, default SystemSound + HapticFeedback backends, CueBridge wires MeshcoreController→cues, grid anonymous-channel ripple. Per-theme audio assets (Mission Control / Velocity / etc.) deferred to a later polish (asset authoring). 103 tests |
| U7 | Polish: motion + reduce-motion, conformance/widget tests, a11y audit | ☐ |
| U8 | **Background-safe delivery (R17)**: ✅ done — pt1 `onAppResumed()` + HomeShell `WidgetsBindingObserver` (`8f32eb0`); pt2 Android foreground service via `BackgroundKeepalive` (flutter_foreground_task `connectedDevice`, opt-in default-on, App-settings switch, manifest) (`a7b552f`; 87 tests). iOS = reconnect-on-foreground; not live push. **Native FGS UNVERIFIED in sandbox — needs on-device test + clean Android rebuild** | ✅* |
| U9 | **Hyperlocal grid (R18)** — visual-notification grid (concrete F2). 🔶 done w/ caveats (`1070de5` + `cc8e851` + `c8e7f9a`): radial range-rings, hybrid GPS→RSSI→hash positioning, recency-brightness 24h, pulse=known, rapid-blink=favourite, reduce-motion fallback, theme-driven colour, anonymous-channel ripple, **own tab after Nodes** (was a radar icon on Nodes — moved, issue #4), **toggleable legend overlay**, **tap-to-select** opening `NodeDetailSheet` (summary + Message / Favourite / stub-link to R25 geocoded map + Copy pubkey), cue parity via CueService (default sounds/haptic). Pending: live-radio-params outer-range scale; per-theme audio assets; **R25 reverse-geocoded equal-grid map** as a second view in the picker | 🔶 |
| U10 | **P2P direct messages (R6 extension)** + chat→channels shortcut | ✅ done (`34fc0c4`; 107 tests) — `ChatMessage.peerPubKeyHex`; controller `sendDirectText` (`CMD_SEND_TXT_MSG` 0x02, 6-byte pubkey prefix) + `_ingestDm` (prefix→pubkey resolution + `incomingDirectMessages` stream) + `dmHistoryFor`; `DmScreen` at `/dm/:pubkey` reached by tapping a Nodes row; `CueBridge` fires `dmIn`. Chat header gains a "Manage channels" icon (channel mgmt was wired but not discoverable from the chat context). Inbound DMs continue to mark senders **known** (R18 pulse) |
| U11 | **Chat message actions (R20)** — long-press a chat row → context menu with **Reply** (quoted prefix into the composer, no thread semantics in protocol), **Copy** (clipboard), **Delete** (local-only — MeshCore has no recall; the UI must say so). Also a trailing per-row affordance for accessibility (a11y-safe alternative to long-press). Applies in both ChatScreen (channel) and DmScreen. `ChatStore` prunes + re-persists on delete | ✅ done (`7d6aaeb`) — `chat_actions.dart` helper; ChatMessage gained stable id (`i` JSON key); long-press + overflow icon both open the sheet; 109 tests |
| U12 | **Permissions UX (R21)** — first-run intro screen explains required perms (BLE; notifications when background mode is opted in); proactive request via `permission_handler`; offline mode is first-class (every screen renders disconnected; connection-requiring actions show a clear "Grant + connect" affordance with a deep-link to OS settings on permanent denial). Notification perm requested only when "Stay connected in background" is enabled | ✅ done (`8ff6e0a`) — `PermissionsService` interface + Platform/Noop impls; `FirstRunController`; intro Grant/Skip; BG-keepalive toggle asks for notifs just-in-time; App-settings Permissions tile + "show intro again" debug action; 116 tests |
| U13 | **Location sources for advert lat/lon (R22)** — Identity/Advert section of Device config gets two explicit buttons: **"Use phone location"** (one-shot `geolocator` fix, requests `ACCESS_FINE_LOCATION` / iOS when-in-use just-in-time) and **"Read device location"** (`SelfInfo.latitude/longitude` re-loaded into the fields). Set ≠ broadcast — user still taps "Set advert location" to push (`SET_ADVERT_LATLON` 0x0E). Improves R18 grid (switches RSSI-rings → GPS bearing+distance once own lat/lon is set) | ✅ done (Phase A `28215a8` + Phase B `80adf94`) — `LocationService` interface + GeolocatorLocationService + Noop; `mc.ownLocation` resolves device-first → phone-fallback; Dashboard LOCATION tile w/ Configure CTA; per-node distance on Nodes; two Device-config buttons. 123 tests |
| U14 | **Diagnostics: bounded RAW FRAME LOG scroll (R23)** — replace the bottom of the single page-scroll `ListView` with a fixed-height inner pane (its own `ListView.builder` + scrollbar) so the frame log scrolls independently from the State / Sends / Channel-tail / capture sections above it. Pure UX polish, no protocol/test changes | ✅ done (`1e38859`) — 360 dp bounded inner pane with Scrollbar; full 256-cap buffer browsable in place; 107 tests still green |
| U15 | **Per-channel notification settings (R24)** — `ChannelNotificationPrefs` (per-slot persisted overrides: audio, haptic, TTS, system-notification; default inherits global). Channel-management screen grows a Notifications section per slot; chat header gets a quick toggle. `CueService` consults the override for channel-msg cues; existing `TtsController.toggleChannelMute` folds into the bundle | ☐ |
| U17 | **Tools (R60, issue #7)** — Settings hub gains **Tools**: Radio stats, Ping, Trace path, Discover nearby, Soak test, Range test. UI spec in `meshmore-sns-tools-spec.md` | ✅ built — codec (GET_STATS / STATUS_REQ / TRACE_PATH / RESET_PATH / discover), `ToolsController` (one tool at a time, poller held), six screens EN+JA. **Unverified on hardware** |
| U18 | **Offline maps (R61, issue #5)** — Settings hub gains **Offline maps**: storage budget, region downloads, event maps (GeoJSON), map sources; street map gets a basemap picker + attribution + event overlays. UI spec in `meshmore-sns-maps-spec.md` | ✅ built — `MapsController` (tile store, packs, layers, budget, expiry), cached `TileProvider` on all three map views, two screens EN+JA. **Unverified on device** |
| U16 | **Channels & encryption polish (R6 extension + R33)** — Encryption explainer banner ("Public = well-known key; private slots = AES-128 with your PSK"). Edit dialog gains: **Random PSK** generator via `Random.secure` 16 bytes (Hex mode) + **Copy PSK** button when complete, **#tag strength hint** (length <8 OR common-word denylist EN+JA → amber-tertiary warning), **slot-0 overwrite warning** dialog when about to write non-Public PSK into Public, **Show current key** reveal (per-dialog latched, `SelectableText` 32-hex), **Clear slot** action (pragmatic: overwrites back to `kPublicChannelPsk` since the protocol has no `CLEAR_CHANNEL` opcode — confirm dialog explains the semantic), **key-source detection on re-open** (Hex pre-filled when slot's PSK ≠ Public). R33 default-channel preference: per-row `star` toggle + `DEFAULT`/`既定` badge; preference persisted in `mm.defaultChannel`; controller pre-loads at startup and one-shot applies on first reach-ready. | ✅ done (`f568b59` + `6621874` + `7cde693`) — `_channelPsks` cache (controller) seeded by `ChannelInfoFrame` ingest + optimistic on `setChannel`; slot 0 pre-seeded to `kPublicChannelPsk`. `DefaultChannelStore` keyed `mm.defaultChannel`. ~25 new arb keys per locale. 133 tests, analyze clean. |

### Hyperlocal grid (R18) — design

A glanceable spatial notification surface; **our node is the
reference** (centre). Realises F2 (and likely reframes F1's "live
map"). All visual identity comes from the active theme — this spec
fixes only the *rules*, never colours.

- **Positioning (hybrid, decided):** advert GPS lat/lon → true
  bearing + distance when both we and the peer have a fix; else
  RSSI/SNR → distance **ring** with a *stable arbitrary* bearing
  (hash of pubkey, so a node doesn't jump around); else an abstract
  outer slot. ⇒ geometry is **radial range-rings** (rings =
  distance bands scaled to the theoretical practical range; angle =
  bearing or stable hash). Outer-ring scale derived from current
  radio params (SF/BW/freq) where possible, else a nominal.
- **Recency → brightness:** 100 % on register, decays to 0 % at
  >24 h, then removed. Brightness is the primary information
  channel (works under any palette; R13-safe — never colour-only).
- **Animation semantics:** *known* node → steady **pulse**;
  **favourited** contact → **rapid blink**. Reduce-motion (R13):
  substitute a static ring/badge + brightness; no flashing.
  **"Known" = a node that has communicated directly/attributably
  to us** (received DM / direct exchange) — node-level, *not*
  human identity, *not* conferred by anonymous channel/Public
  traffic (user-clarified).
- **Audio:** theme audible pack (R12) on register, with visual +
  optional haptic parity (R13). Honour reduce-sound / silent.
- **Constraint — anonymous channel traffic:** MeshCore
  channel/Public messages carry **no sender identity**, so they
  cannot mark a specific node *known* or be placed at its cell.
  Represent as a generic, non-attributed pulse (e.g. a brief
  centre/whole-ring ripple). Only DMs, our outbound DMs, adverts
  and contacts attribute to a node.
- **Dependencies:** a persisted **favourite-contact** flag (new,
  small); the R12 **CueService** (U6) for the audio/haptic side;
  optional GPS plumbing for the geographic tier.

### Open questions for design review

1. Do we vendor Rajdhani/Eurostile locally or fall back to a permissive
   open-source equivalent (e.g. **Saira Condensed**)?
1. ~~(R18) grid geometry / range scale~~ — **RESOLVED**: radial
   range-rings; outer-range scale from live radio params (nominal
   fallback).
1. ~~(R18) anonymous channel/Public representation~~ — **RESOLVED**:
   generic non-attributed centre/ring ripple; never marks "known".
1. ~~(R17) eventual vs live-background~~ — **RESOLVED**: eventual is
   the contract; Android gets a foreground service (persistent
   notification accepted) to make it reliable under Doze; not live
   push. iOS = reconnect-on-foreground.
2. ~~Should the Chat overlay on the Dashboard be a collapsing bottom
   sheet vs a fixed-height bottom panel?~~ — **SUPERSEDED**: Chat
   became a dedicated PageView tab in U3 (`ec6e1c6`); the
   Dashboard-overlay direction was dropped.
3. ~~Live map (F1) — reserve a Nodes-header tab slot?~~ —
   **SUPERSEDED**: F1 reframed by R18 (hyperlocal grid, U9) reached
   from a dedicated `/grid` route + a Nodes-header grid icon; since
   issue #4 it is a primary tab after Nodes and both are gone.
