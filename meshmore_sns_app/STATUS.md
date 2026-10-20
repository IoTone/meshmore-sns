# Meshmore SNS — project status

_Snapshot as of v1.0.146+1 (branch `meshmore-sns`)._

An offline-first Flutter companion app for MeshCore LoRa mesh radios
over BLE. Mesh-first, no backend. Sibling branch `responsive-iot-2026`
holds a de-branded generic BLE/WiFi scanner starter derived from this
codebase.

## Architecture

- **`MeshcoreController`** (`lib/meshcore/`) — the Provider-exposed
  facade over the BLE link + MeshCore companion protocol. Owns nodes,
  chat/DM, channels, telemetry, battery, location, delivery tracking.
  Transport is injectable, so the whole controller is `flutter test`-
  covered with a fake (~296 app-wide tests).
- **`packages/meshcore`** — pure-Dart protocol codec (frames/opcodes,
  CayenneLPP, channel/identity crypto). No Flutter deps.
- UI: `provider` + `go_router`; token-based themes; ARB + `gen-l10n`
  localization (EN + JA, in lock-step).

## Feature inventory

**Connection & shell**
- BLE scan / pair / connect, auto-reconnect (backoff), background
  keep-alive (Android FGS), reconnect on resume.
- Dashboard (R8): peers-in-range, radio/location readouts, battery
  readout (taps → Battery screen), recent activity, **tappable device
  rename** (R52) with re-advertise + SelfInfo refresh.

**Chat (R6/R20)**
- Channel + DM chat; per-message **delivery status** (sending → sent →
  delivered / failed), handling the firmware's ACK-before-SENT ordering.
- Channel sender attribution via the "name: " text prefix.
- Channels: name + PSK, **#hashtag-derived** public channels (SHA256),
  hex PSK, shake-to-derive; QR share.

**Nodes / fabric**
- Nodes list with proximity badges, DM counts, tags (R28), favorites,
  per-row **temperature chip** when telemetry is present.
- Node detail sheet: identity, signal, hops (Direct / N-via / **Flood**
  / unknown), per-node telemetry (altitude + **temp/humidity/pressure**),
  on-tap telemetry query (contacts only).

**Navigation (R64)**
- Swipe between the eight views; no menu/sheet/drawer switches views.
  A **view strip** under the app bar (48x48 labelled icon buttons,
  `selected` on the current one, scrolls under 384dp) is the
  non-gesture path.
- Device configuration (5 groups) and Profile & personalization (2
  groups) fold with `MmCollapsibleSection`, open by default.

**Studio skin (R63)**
- Seventh preset `studio` ("Studio Dark — clean · square"): grey layer
  stack + 1px hairline + square controls + one light-grey accent (R68;
  blue in R63-R65). `MmTokens`
  gained derived `raised/selected/hairline/onAccent/fgDisabled`; `MmShape`
  gained `hairlineWidth`/`squareControls`; the six older skins are
  unchanged by construction (`test/theme/mm_layers_test.dart`).
- `MmCollapsibleSection` groups Location settings (Auto-publish / Beacon
  / Manual). Collapse state is **persisted** per stable group id (R65:
  `MmCollapseController`, `mm.collapse.v1`, default open, loaded before
  `runApp`).
- R65: Studio hairline/line `#4A4A4A`, accent `#70A5DA`, alert `#E8887E`
  so the rule and the coloured text are legible on all four layers (the
  old hairline was 1.06:1 on `selected`). Pinned per layer in
  `test/theme/mm_layers_test.dart`.
- R66: Studio cards get a 1px hairline edge and the app bar (with the
  view strip) ends in a 1px hairline; both null for the six older
  presets. **Unverified on a device** (theme-level tests only).
- R66: a collapsible group with no `MmCollapseController` provider still
  works per session but logs a one-time `debugPrint` on its first toggle.
- R68: Studio is **monochrome**: accent `#D0D0D0` (saturation 0), alert
  `#D6A7A1`, ok `#A9C4A7` (both <= 0.30 saturation), new `onAlert` token
  (dark on the alert fill). The R63/R65 blue is gone. Pinned in
  `test/theme/mm_layers_test.dart`. **Unverified on a device.**
- R68: fixed the shell being mounted twice at launch (BootOverlay swapped
  Stack for a bare child on dismissal); `test/shell/boot_overlay_test.dart`.
- R68: Personalization is uniformly collapsible (4 groups; TYPE and
  Audio alerts fold too).
- R68: Device configuration groups region presets under Americas /
  Europe / Asia-Pacific headings (was one wall of 15 chips).
- R68: the boot overlay is grey under Studio (still NERV for the rest).
- R68: the app-bar link chip is localised (was hard-coded English).
- R68: Studio has its own dashboard (`StudioDashboard`): quiet status row
  (text + dot shape, no colour fill), collapsible Radio / Location /
  Recent. Type rule: words sans, machine data mono (`MmType.sansLabels`).
  The old SEELE "double CONNECT" was one TextButton drawn in the accent on
  the error fill (1.5:1) beside a second OFFLINE in the app bar.
  **Unverified on a device.**
- Audio aliases the Hyperlocal pack; **unverified on a device**.

- R69: the Map tab with no fix shows a world view (20N 0E, zoom 2) plus a
  quiet "no fix" row instead of a blank screen; the grid's street-map mode
  keeps its empty state. **Unverified on a device.**

- R69: the named raw-English strings (Device configuration channel row and
  live-params line, location source label, battery "CHG", Elevation chip,
  Nodes clear-search tooltip, Diagnostics connection block) now follow the
  locale. **Unverified on a device.**

- R69: the 28-36dp icon buttons the R68 pass listed (chat/DM message
  actions, dashboard refresh, equal-grid and fabric-survey controls, dense
  audio toggle + NERV bluetooth sibling) are 48x48. **Unverified on a
  device**: the equal-grid bar is wider now (about 280dp), fabric-survey's
  column is 240dp tall.

- R71: Studio is uniformly square: Material buttons, FAB, menus and text
  fields (theme) plus 49 screen-drawn radii via `mmRadius` and the chat
  jump pill. Older presets unchanged. Guard: `test/ui/square_controls_guard_test.dart`.
  **Unverified on a device.**

**Known issues from the R68 critical pass (not fixed; read from code and phone screenshots)**
- Still English in the Japanese locale (after R69): the Diagnostics SEND /
  M6 interop / fixture-export / bot-soak panels (developer tooling, left
  in English on purpose). Other screens were not swept literal by literal;
  a grep for `Text('Latin...')` finds only brand marks, "BLE", hint URLs
  and the unused `about.dart`.
- R70 (device findings): edge swipe from the physical edge was Android
  system Back (bands now sit inside `systemGestureInsets`, not
  device-verified); the OSM credit line was covered by the no-fix banner
  (fixed); the map control column is 48dp and the band inset is derived;
  Studio draws the basemap dark (`MmShape.darkBasemap`).
- The six older dashboards still show two status displays (the dashboard's
  own slab and the app-bar chip) for one link state.
- `JetBrains Mono` is hard-coded in about 90 places outside the theme
  (largest: `elevation_profile_view.dart`, `dashboard_screen.dart`,
  `grid_screen.dart`, `node_detail_sheet.dart`, `device_config_screen.dart`),
  so Studio's "words sans, data mono" rule holds on the Studio dashboard,
  section headers and collapsibles but not on every screen.
- Studio still uses the accent decoratively in places (about 35
  `color.accent`, 121 `cs.primary` uses); with the grey accent that is
  now a style question only, not a colour or contrast one.
- No serif face is bundled (only Saira and JetBrains Mono). Not added:
  a new font is a new asset with licence and size cost, and a serif at
  11-13 sp on a dark UI reads worse than the platform sans.

**Privacy (R62)**
- The periodic 60 s position-bearing self-advert is **opt-in** (App
  settings → Auto-publish location → *Periodic position beacon*, default
  off). With it off the SelfInfo poll sends `appStart` only — nothing over
  the air.

**Hyperlocal grid (R18/R25/R27) — 9 view modes**
- Its own primary tab, right after Nodes (issue #4). Disconnected, it
  shows the radar with no nodes and "Not Connected to Mesh". The chosen
  view is remembered for the session; every launch opens on the radar.
  While a panning view (street map, globe, …) shows, the shell's swipe
  is locked so drags move the map — leave via Back or the view strip.
- **Map tab (R61)** — the street map viewer as its own page right after
  the grid, in every skin; the middle pans/zooms and the `PageView` swipe is locked, but a 24dp
  edge band on each side (R67) changes view by an inward fling. A corner
  button opens Settings → Offline maps. Eight views in all.
- **Radial "radar"** — range rings (Room…Wide…**City…Region**, Region
  auto-frames the known extent), signal/bearing placement, compass rose
  + heading needle, **north-up/heading-up toggle**, prominent top
  **heading HUD**.
- **Weather (WX)** — environment telemetry at a glance: summary band
  (nodes reporting + min/avg/max temperature on a cold→hot ramp) + a
  warmest-first list of reporting nodes with temp/humidity/pressure +
  freshness; tap → node detail.
- **sns-cells** social heat map — time-decayed message density with
  **last-hour counts** on each square; **place echoes** (R54 inferred-
  place ◇ markers with last-hour ×count, edge-pinned when off-frame,
  + a dismissible "Places" list); a **scale stop** chip (Metro ~20 km /
  Region ~300 km / Mesh fit-all) so distant nodes (Seattle, Vancouver
  BC) can be framed instead of edge-pinned.
- Globe, equal-grid (OSM tiles), street map, fabric survey, mesh tree
  (force-directed, hop slider, Flood as first-class), **Fuji-san**
  elevation profile.

**Telemetry & sensors**
- Self + peer telemetry via `CMD_SEND_TELEMETRY_REQ` / `0x8B`.
- Decodes GPS (alt) + **environment (temperature/humidity/pressure)**;
  surfaced in node detail, Nodes rows, the Fuji-san self chip, and the
  Weather view.
- **Background telemetry poller** (opt-in, App settings → "Gather node
  telemetry", default on): politely cycles synced contacts (one req per
  ~10 s, hop/distance-tiered, 3 attempts/contact, 15-min refresh, then
  quiet). Off = no telemetry traffic from us.
- Self-telemetry zero-prefix replies normalized to our own key; a
  `[telem]` diag log dumps received LPP types.
- Fuji-san polls **self** telemetry on load / on UPDATE (+ a phone-GPS
  one-shot so altitude resolves even when the device omits GPS alt).
- **Telemetry sharing** is a permission (Off/Contacts/Anyone per
  base/loc/env); the radio firmware answers other nodes' scans itself
  (`onContactRequest`, contact-only, base is the master gate). For
  "Contacts" mode, the Node detail sheet grants **per-contact telemetry
  permissions** (writes `contact.flags` via ADD_UPDATE_CONTACT) — the
  only lever the app has on the responder side.

**Tools (R60) — Settings → Tools (issue #7)**
- Radio stats, Ping, Trace path, Discover nearby, Soak test, Range
  test; spec in `meshmore-sns-tools-spec.md`.
- One tool holds the radio at a time and the background telemetry
  poller is held meanwhile (the firmware keeps one pending request).
  Tool requests don't disturb chat SENT/ACK correlation.
- Soak pairs with the R59 echo bot; Soak and Range refuse Public.
  Ping/Soak export JSON, Range exports CSV.
- **Unverified on hardware.** Frame layouts are from current MeshCore
  firmware source (newer than the codec pin); GET_STATS and discover
  need recent firmware and say so when missing.

**Offline maps (R61) — Settings → Offline maps (issue #5)**
- Disk tile cache behind every map view (street map, equal grid, fabric
  survey); region packs; GeoJSON event-map overlays; one storage
  budget; per-pack/layer expiry; setup online-only; downloads park
  while offline and resume on their own. Spec in
  `meshmore-sns-maps-spec.md`.
- **OSM and OpenTopoMap are view-cache only**: their tile policies
  forbid prefetch/offline. Packs come from USGS (US only) or a custom
  tile server the user marks as allowing offline download. Offline OSM
  in bulk is phase 2 (vector extracts).
- Street map's street/topo toggle is now a basemap picker; attribution
  shown on the map.
- **Self-test** (Offline maps → check icon): 11 end-to-end checks
  against the real servers, in a sandbox. All pass on the SH-53D
  (2026-10-15). Headless runner: `tool/maps_selftest_device.dart`.
  Not yet exercised by hand: map pan performance from disk, multi-MB
  packs, behaviour across days.

**Battery (R16)**
- Voltage → SoC via per-device OCV curve; observed-drain regression +
  rated-capacity cross-check; time-to-empty + confidence; persisted
  voltage history; dedicated Battery screen + dashboard summary.

**Docs (R53) — Docs tab (6th primary view)**
- Offline reader for three sections: **Protocol** (MeshCore companion
  radio protocol), **Firmware** (MeshCore README, matched to the
  connected device's fw version), and **App** (self-authored).
- Offline-first snapshots baked in (`assets/docs/`), refreshed
  opportunistically from GitHub (`meshcore-dev/MeshCore`) and cached
  (SharedPreferences); App section never hits the network.
- Futuristic monospace rendering (tracked-caps headings + accent
  rules); markdown parsed with the `markdown` package, rendered to
  widgets in-app (images → alt text). Fetch seam is injectable/tested.

**Skin system (R55) — design-system foundation**
- A **skin is a bundle**, not just a palette: `MmSkin` = colour
  (`MmTokens`) + `MmType` + `MmShape` (sharp/rounded/**chamfer**) +
  `MmOrnament` (scanlines, corner brackets, hazard-stripe headers),
  resolved per preset via `mmSkinFor` and read through **`context.skin`**
  (high-contrast forces SEELE).
- **Bundled OSS type spine** (the brief's faces): **Saira** (Eurostile-
  class display) + **JetBrains Mono** (telemetry, **slashed-zero** via
  `FontFeature`) — variable fonts (~670 KB), OFL, attributed in About.
  Applied **app-wide**: `buildMmTheme` puts the skin's display face on
  the global `textTheme` (every screen, not just migrated components),
  and all telemetry/mono text uses JetBrains Mono.
- **Branded component library** (`lib/ui/`): `MmPanel`, `MmSectionHeader`,
  `MmReadout`, `MmStatusPill`, `MmListRow`, `MmScaffold` +
  `SkinChromePainter` (CRT scanlines + L brackets, suppressed under
  reduce-motion). `context.skin` falls back to SEELE when no
  `ThemeController` is above it, so migrating a screen never forces its
  test harness to wire one.
- **Two migration mechanisms, both proven:**
  1. **Per-skin layout fork** (for screens whose *metaphor* differs):
     the Dashboard is hosted by `DashboardHost`, which dispatches the
     **NERV Terminal** telemetry-grid vs the **SEELE monolith** from one
     `DashboardModel` (slot data).
  2. **Component-driven reskin** (one screen, all skins, no fork): the
     **Nodes** + **Chat** views are wrapped in `MmScaffold` and use the
     components (`MmListRow` cards; Chat's terminal-log mono rows) —
     chamfered + scanline under NERV, flat/clean under SEELE; same code,
     reskinned by bundle.
  Switch live in Personalization.
- **Visualisation painters follow the skin.** Audit finding: the 9 viz
  painters were **already theme-driven** — they read `ColorScheme`
  (which *is* the skin's tokens via `buildMmTheme`), with **zero**
  hardcoded brand-colour literals. Only residuals fixed: the sns-cells
  painter's heat/◇ literals → `VizPalette.of(skin)` (hot→alert,
  cool→fg, self/inferred→accent, grid→line), and two legend swatches →
  theme. Intentionally left theme-independent: the weather temperature
  ramp (a physical cold→hot scale) and the white map-marker outlines
  (cartographic contrast on full-colour OSM tiles).
- **NERV audio identity** (R12): the shared cue motifs read generic, so
  NERV got a bespoke **"Mission Control"** set — crisp upper-register
  messageIn blip, Geiger-counter **discovery ticks**, a descending
  **sawtooth klaxon** (alert ×2 / link-lost), ascending square link-up.
  Two new synth modes (`sweep`, `ticks`) in `brand/_audio_pack.py`
  (pure-stdlib). **Bug fixed:** `CueKind.discovery` had no trigger —
  now `CueBridge` fires it when a newly-heard node appears (suppressed
  during the post-connect sync flood), so the most distinctive NERV cue
  actually plays. (Verified the WAVs ship + audioplayers plays them, not
  the system-sound fallback.)
- _Migrated onto the components: Dashboard (fork), Nodes, Chat, **DM**,
  **Settings hub**, **About** (component-driven). Viz painters
  skin-following; fonts app-wide; NERV audio. Next: settings sub-screens
  + Docs/Battery, then concepts B/C/E/F bundles._

**Platform / settings / a11y**
- About → **Open-source licenses & attributions** (`showLicensePage`):
  bundled-asset licenses registered with `LicenseRegistry` — MeshCore
  docs (MIT), GeoNames cities (CC-BY 4.0), Natural Earth (public
  domain), OpenStreetMap (ODbL) — alongside all package licenses.
- Region presets (R39, baked-in), location settings, diagnostics +
  raw-frame log, personalization (themes, font scale, reduce-motion,
  high-contrast), voice/TTS (R5), per-theme audio cues (R12).

## Known constraints & caveats

- Most recent UI/paint changes are **verified by `flutter analyze` +
  the test suite, not a device render** — eyeball on hardware.
- **Environment telemetry is NOT available on the test device's current
  firmware (confirmed 2026-06-03 on hardware).** The T1000-E's BME280
  needs the MeshCore *sensor firmware* build; standard companion firmware
  sends only battery/GPS. Two independent signals confirmed this:
  1. Self-telemetry replies carry an **empty** CayenneLPP payload
     (`[telem] … types=` blank — no `0x67`/`0x68`/`0x73`).
  2. Writing a non-zero **Environment** value in device config
     (`SET_OTHER_PARAMS`) does not stick — the device **clamps the env
     bits back to 0** and echoes a `SelfInfo` with env=0. A firmware
     with the sensor in its telemetry path would accept the class.
  The app's encode (byte position, no clobber of base/loc) and decode
  (env at SelfInfo byte 46) were both verified correct — this is purely
  a device-side limitation, not an app bug. Resolution is to flash a
  MeshCore sensor firmware build; **no app change can surface data the
  radio never emits.** (BME280 also reads a few °C warm — sits by the
  electronics.) Further firmware investigation is the user's to pursue.
- Peer telemetry is **contact-only** (firmware drops requests for
  advert-only nodes); the background poller respects that.
- **The whole temperature chain (poller → decode → Weather view) is
  unverified on hardware** — it only shows data if a node's firmware
  actually transmits environment telemetry. Confirm via the WX view /
  `[telem]` logs before relying on it.
- The PUSH_CODE_ACK (0x82) wire format isn't in firmware docs we hold;
  decoded as the documented u32 tag, degrades to "sent" if a device
  differs.

## In progress / next

- **Telemetry & weather thrust:** Phase 1 (background poller) ✅ and
  Phase 2 (Weather view) ✅ shipped. **Phase 3 (per-node temperature
  trends / history + sparkline) is shelved** — the test device's
  firmware emits no environment telemetry (see constraints above), so
  there is no source to build history on. The decode/poller/WX chain is
  complete and will light up automatically if a sensor-firmware node
  joins the fabric. Re-open Phase 3 only once a node is confirmed
  transmitting `0x67`-class telemetry.
- **Settings toggle contrast** ✅ (v1.0.125+1) — `segmentedButtonTheme`
  + `chipTheme` give selected controls a solid-accent fill app-wide.

## Backlog (flagged, not started)

- **Real per-feature app docs ("online-help-md")** _(noted, not started)._
  The Docs → App section currently points at `assets/docs/app.md`, a
  single **summary** doc. Replace it with proper per-feature help —
  a new `online-help-md` doc set **with screenshots** — documenting each
  feature, not one overview page. Leave `app.md` in place for now; build
  the real docs as a follow-up. (Docs tab now sits **after** Settings.)


- **R54 — message-derived place inference ("place echoes")** — follow-
  ups only. Scans channel banter for place names/coords, region-scoped
  to the known location, and plots ≥80%-confidence ghost markers on the
  SNS grid. **All three sub-tasks shipped:** (a) ballpark placement
  engine (`lib/sns/place_inference.dart`), (b) per-channel toggle in the
  channel-edit dialog (default on for public #1; `PlaceInferencePrefs`),
  (c) `CityLookup` forward name index + `CityGazetteer` adapter +
  `InferredPlaceStore` (TTL/reinforcement) + dashed-◇ markers on the
  sns-cells painter. ~31 SNS tests. **Remaining follow-ups:** tap-a-
  marker → source-snippet/dismiss UI; the X→Y connector line; and the
  optional finer neighbourhood gazetteer (currently city-centre +
  directional offset only). See spec R54.


- **lobospeak** — closed-network robot control plane over MeshCore
  binary req/resp (design doc exists in `meshmore-sns/`). The big one.
- **F2** — map alternatives. **F3** — AI integrations. (Both flagged
  only; need specifics before design.)
- `responsive-iot-2026` generic starter branch — complete & local-only;
  not pushed to origin.
