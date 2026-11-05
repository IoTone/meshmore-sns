# MeshMore — critical audit of what exists, 2026-11-04

Evidence base: `meshmore_sns_app/` (Flutter app + three pure-Dart packages), `meshmore-xr/` (Kotlin/Compose),
`libmeshcore/` + `libmeshcore-android/` (Java), and the ~736 KB of markdown specs at the repo root.
Read in full: `meshmore_sns_app/STATUS.md`, `meshmore-sns-spec.md`, the architecture doc and its audit, the
maps/tools/radio/coverage/lobospeak/gateway docs, and the app source by area. Every claim below carries a
`file:line` or a doc reference. Where this audit contradicts a document, the code wins and the document is named.

Two whole products were **not** audited line by line and are flagged in §7: `meshmore-xr/` (116 Kotlin files,
39,386 lines) and `libmeshcore/` (the Java protocol port). They change the definition of "the app".

---

## §1 What "MeshMore" actually is — four artefacts, not one

- **The Flutter app** — `meshmore_sns_app/responsive_starter_app/lib`, ~172–188 Dart files, 65k–103k lines
  depending on how generated files are counted, ~128 test files. This is the product.
- **Three pure-Dart packages** — `packages/meshcore` (protocol codec: frames, opcodes, CayenneLPP, crypto),
  `packages/meshcore_gateway` (the L2 tunnel wire contract), `packages/meshcore_host` (the same gateway over
  USB serial, with CLI tools and a systemd unit).
- **`meshmore-xr/`** — a second client: Kotlin/Compose for Android XR glasses, 116 Kotlin files, 39k lines,
  plus 14 spec docs and a Hugo site in `meshmore-xr-www/`. Its own `MeshmoreXR-design-brief.md:8` still says
  "No production Android code exists yet" while `MeshLink.kt` alone is 2,216 lines.
- **`libmeshcore/` + `libmeshcore-android/`** — a Java 17 port of the same companion protocol (26 encoders,
  `MeshcoreFrameCodec.java:85-591`, ~40 tests) plus an Android BLE session layer, feeding the XR client.

**Consequence for planning:** "add a feature to MeshMore" means up to four implementations. Protocol work lands
in Dart, Java and Kotlin unless the shared-code story is decided. That is the single largest hidden cost in the
repo and it is not recorded anywhere as a decision.

**Licence, and why it matters now:** the app and both packages are **MIT** (`meshmore_sns_app/LICENSE:1`,
`packages/meshcore/LICENSE:1`). The best reference implementations in the ecosystem —
`meshcore-open-tak` (FEC reference plus frozen vectors) and `wadamesh-tak` (VOX wire, OTP interop test) — are
**GPL-3.0**. Formats are not copyrightable; reference code and test-vector files are. So "copy the reference
implementation verbatim", which the research notes recommend in three places, is **not available** to an MIT
project. Codes and wire layouts can be adopted; code and vector files must be reimplemented from the spec text
or dual-licensed by asking. No document in the repo records this constraint.

---

## §2 Feature inventory — what actually ships

Status vocabulary: **SHIPPED** (runs, with tests or device evidence), **PARTIAL** (a documented piece is
missing), **STUB** (UI exists, behaviour does not), **UNVERIFIED** (implemented, never run on hardware per the
code or STATUS).

### Connection, transport, background

| Capability | Status | Evidence | Limit |
| --- | --- | --- | --- |
| BLE scan/pair/connect, bonded-radio preference | SHIPPED | `ble_connector.dart:45-71` | — |
| Bond repair on repeated failure, capped at one attempt per run | SHIPPED | `ble_connector.dart:452-520` | deliberate: a needless repair leaves a second bond record |
| One notification = one frame, no reassembly | SHIPPED | `ble_meshcore_transport.dart:12-17` | correct for BLE, wrong for any stream transport |
| Auto-reconnect with 6 s floor | SHIPPED | `meshcore_controller.dart:92-94` | floor exists to stay inside Android 17's silent scan throttle |
| Android foreground service for background keep-alive | SHIPPED | `background_keepalive.dart:41-84` | native behaviour "unverified in this environment" (`:68`) |
| iOS background BLE | ABSENT | no `UIBackgroundModes` in `ios/Runner/Info.plist` | R17 met on Android only |
| Second transport (TCP/WiFi, serial, WebSocket) | ABSENT | only `BleMeshcoreTransport` exists | seam is ready (`transport.dart:16-34`) |

### Messaging

| Capability | Status | Evidence | Limit |
| --- | --- | --- | --- |
| Channel + DM send/receive | SHIPPED | `meshcore_controller.dart:1362` | channel text is confirmed by `OK` (0x00), not `SENT` (0x06) |
| Per-message delivery state `sending→sent→delivered/failed` | SHIPPED | `chat_message.dart:17` | ACK-before-SENT ordering handled |
| Reply / copy / delete-local / retry / jump-to-newest | SHIPPED | `chat/chat_actions.dart:15-63` | — |
| Channel lifecycle: slot list, PSK by public/#hashtag/hex, random PSK, show key, clear-by-overwrite, QR | SHIPPED | `channels_screen.dart:625,745` | tag-derived slots re-open as Hex because bytes are not reversible |
| Per-channel TTS mute, per-peer TTS tri-state | SHIPPED | `tts_controller.dart:199-245` | — |
| **OS notification for an inbound message** | **ABSENT** | `flutter_local_notifications` is not a dependency | the only notification is the foreground service's persistent one |
| Per-channel notification bundle (audio/haptic/OS) | PARTIAL | R24; only TTS mute exists | R24 itself marks its OS line as future |
| Composer length guard / byte budget display | ABSENT | no `maxLength` in chat | the firmware clamps channel text to `MAX_TEXT_LEN` = **160 bytes including the `sender: ` prefix** and **truncates silently** (`BaseChatMesh.h:9`, `BaseChatMesh.cpp:766-773`); the app neither counts nor warns |
| Durable history | PARTIAL | `chat_store.dart:20-21` | **250 messages total**, JSON in `SharedPreferences`, plaintext, no search, no export |
| In-flight send survives relaunch | ABSENT | `chat_message.dart:116-118` | a persisted `sending` row resolves to `failed`, reason "app closed before the radio confirmed" |
| Text compression | ABSENT | no codec | — |
| **Block or mute a sender** | **ABSENT** | no keyed store; only per-channel TTS/notification mutes exist | no firmware has a per-sender block or mute, so this is app-side only; the radio still receives, relays and stores a blocked key's channel messages |
| `0x91 PUSH_CODE_ONE_KEY_DM_REJECTED` decode | **ABSENT** | `grep 0x91` → no match in the app tree | keymind-only frame, 1 + 32 bytes; without it a refused stranger's message vanishes with no explanation |

### Nodes, contacts, fabric

| Capability | Status | Evidence | Limit |
| --- | --- | --- | --- |
| Contact sync, advert ingestion, favourites, tags | SHIPPED | `meshcore_controller.dart:1745`, `node_tags_store.dart` | — |
| `path_len` unpacked correctly (width in bits 7–6, hops in 5–0, `0xFF` flood) | SHIPPED | `contact.dart:72-99` | the MCO "69 hops" bug is not present |
| Per-contact telemetry permission write-back via `ADD_UPDATE_CONTACT` | SHIPPED | `contact.dart:107-126` | the only lever the app has on the responder side |
| Identity reconciliation when a returning contact's key changes | SHIPPED | `meshcore_controller.dart:1745` | with a manual re-key escape hatch `node_detail_sheet.dart:648` |
| Contact exchange (share/export/import) usable in the UI | PARTIAL | encoders exist `frame_codec.dart:530-556` | **no call site in `lib/`** |
| `0x8F` contact-deleted / `0x90` contacts-full surfaced | PARTIAL | decoded `frame_codec.dart:1009,1044` | UI surfacing not verified |
| Capability negotiation with the firmware | ABSENT | — | no app-name-tail `;cap=` convention |

### Device and radio control

| Capability | Status | Evidence | Limit |
| --- | --- | --- | --- |
| Radio params, TX power, path-hash size, region presets, advert name/location, other params, custom vars | SHIPPED | `device_config_screen.dart:47-59` | — |
| Region presets: US, EU868, Japan/ARIB, Custom | SHIPPED | `region_presets.dart` | 14 presets missing vs the live API; Japan needs firmware LBT the app cannot set |
| Battery: voltage→SoC by OCV curve, drain regression, time-to-empty | SHIPPED | `battery_model.dart:9-105` | device DB has **5 entries and excludes the reference T1000-E** (`device_power_specs.json:5-74`) |
| **Advert location "Pinned"** | **STUB** | `device_config_screen.dart:30-37` | firmware defines only NONE and SHARE (`NodePrefs.h:9-10`), so **"Pinned" does not pin** |
| Two-phase commit / rollback for a stranding radio change | ABSENT | no `rollback`/`last known good` in `lib/` | a frequency change that strands the device cannot be undone from the app |
| Device CLI (`0x42 CMD_RUN_CLI_COMMAND`) | ABSENT | not declared in `constants.dart` | blocks `powersaving`, `radio2.*`, `radio.rxps`, `dutycycle`, `tx.ssh`, `path.hash.mode` |
| Firmware OTA from the app | ABSENT | — | — |
| Destructive admin (reboot, factory reset, key export, PIN) | CODEC-ONLY | encoders `frame_codec.dart:563-691` | deliberately not exposed (`ux-coverage.md:44-66`) |
| Repeater/room administration (login, status, CLI) | CODEC-ONLY | `frame_codec.dart:619,704,720` | **zero call sites** in `lib/` |

### Location, maps, grid

| Capability | Status | Evidence | Limit |
| --- | --- | --- | --- |
| Device-first / phone-fallback own location | SHIPPED | R22 | — |
| Opt-in periodic position beacon | SHIPPED | `auto_publish_controller.dart:37-38` | default off |
| Tile cache with ETag, per-source backoff, fetch gate (4 concurrent) | SHIPPED | `maps_controller.dart:373-396`, `fetch_gate.dart:17-53` | — |
| Region packs (tile boxes), GeoJSON event layers, storage budget, per-pack expiry, park/resume offline | SHIPPED | `maps_controller.dart:102-108,546` | OSM/OpenTopoMap are view-cache only by their tile policy |
| Vector basemap (OSM Shortbread style, drawn not recoloured) | SHIPPED | `vector_basemap.dart:41-83` | **bundled style, not bundled tiles** — offline needs region files |
| PMTiles region archives (resumable, SHA-256 + schema verified, read by seek) | PARTIAL | `map_archive.dart:19` | **hidden behind `kRegionFilesEnabled = false`**; no file is published; import needs a picker dependency |
| 11-check map self-test | SHIPPED | `maps_self_test.dart` | passes on SH-53D 2026-10-15 |
| Ten grid views (radar, globe, equal-grid, street map, fabric survey, elevation, mesh tree, sns-cells, weather, meshbook) | SHIPPED | `grid_screen.dart:43-54` | only radar/globe/equal-grid have tests |
| Place inference from channel text (33k-city gazetteer, ≥0.80 confidence) | SHIPPED | `place_inference.dart:108-120` | follow-ups open: tap-marker source sheet, X→Y connector, finer gazetteer |
| Meshbook daily analysis, sns-cells heat, weather inference | SHIPPED | `meshbook.dart:100-160`, `sns_frame.dart:14-26` | heuristics only, nothing transmitted |
| Geofence / trail capture / GPX | ABSENT | only a country-box→region suggestion | R37 and `geofence-tracking.md` P1–P4 unbuilt |

### Telemetry, sensors, weather

- Self and peer telemetry decode (GPS, temperature, humidity, pressure, luminosity, battery) — SHIPPED,
  `node_telemetry.dart:13-75`.
- Background poller, opt-in, held while a tool owns the radio — SHIPPED, `meshcore_controller.dart:2926-2932`.
- **Environment telemetry on the reference radio — BLOCKED, not a bug.** The T1000-E needs a sensor firmware
  build; `SET_OTHER_PARAMS` env bits are clamped back to 0, so no app change can surface data the radio never
  emits (`STATUS.md` "Known constraints", verified twice on hardware).
- Consequence: **Telemetry Phase 3 (per-node trends/sparklines) is shelved** and the whole
  poller→decode→weather chain has never been confirmed on hardware.
- Peer telemetry is contact-only (firmware drops requests for advert-only nodes).

### Tools, diagnostics, docs

- Six tools (stats, ping, trace path, discover nearby, soak, range), one radio holder at a time, exports
  JSON/CSV — SHIPPED, `tools/tools_controller.dart:14-19`, all **UNVERIFIED on hardware**, and frame layouts
  are newer than the codec pin so unsupported commands say so.
- Diagnostics: live state, bounded raw frame log, channel-tail oracle, fixture export, bot soak — SHIPPED,
  `diagnostics_screen.dart:18-22,391-397`; the dev panels are **English-only on purpose**.
- Docs reader: four sections (protocol, firmware, app, devices) — SHIPPED, `docs_repository.dart:20`; the App
  section is one summary doc, not per-feature help.

### Gateway / connected apps (the LDMUX subsystem)

- Loopback-only listener, one client at a time, 16-byte token in secure storage, constant-time compare,
  pre-auth timeout — SHIPPED (`gateway_service.dart:14-110`).
- Airtime governor at 1 % duty (two named policies `onePercentDutyCycle` / `ownedChannel`) — SHIPPED.
- Android Binder handoff behind a `signature` permission, in-memory, token only while running — SHIPPED in code
  (`GatewayHandoff.kt:1-70`, `AndroidManifest.xml:87-90`), **never exercised across two signed apps**.
- USB-serial host twin with a serialisation queue + systemd unit — SHIPPED (unpublished, `0.1.0`).
- **`MeshCarryCodec` (raw/binary/rawpacket encoders) is reachable only through this path** — the app's own send
  path never touches it.
- Declared but not enforced: `creditWindow = 8` / capability `recvCredit` claim "the gateway enforces" while
  `session.dart:18,38` advertises only `statusPush`.

### Appearance, audio, accessibility, localisation

- Seven skins as bundles (colour + type + shape + ornament), per-skin dashboards, `context.skin`, persisted
  collapse state — SHIPPED; rendering under Studio is theme-tested but **not device-verified**.
- Six audio packs × 19 cues = 114 WAVs, looped scan drone, system-sound fallback — SHIPPED.
- Five per-peer signature slots on DM arrival — SHIPPED (`cue_service.dart:60-79`); DM-arrival substitution not
  hardware-verified because an inbound signed DM cannot be manufactured on demand.
- TTS off by default, per-channel mute, per-peer tri-state — SHIPPED; per-peer voice/pitch is a **STUB**
  (`peer_profiles.dart:40-43` "still design").
- "TTS using the GPU" (R5) is **platform TTS**, not an on-device neural model.
- Accessibility (no info by sound/colour alone, ≥48 dp, reduce-motion, high-contrast, semantic labels) —
  SHIPPED and treated as a requirement.
- EN + JA in lock-step with guard tests — SHIPPED; dev panels excluded by decision.

---

## §3 The protocol surface — three distinct states, commonly conflated

**Wired end to end (~20 commands):** appStart, getContacts, deviceTime get/set, syncNextMessage, channel text,
DM text, selfAdvert, setAdvertName, setAdvertLatLon, setOtherParams, setRadioParams, setRadioTxPower,
setPathHashMode, get/setChannel, get/setCustomVar, getBatteryStorage, deviceQuery, sendTelemetryReq, getStats,
sendStatusReq, sendTracePath, sendControlData (discover), resetPath, addUpdate/removeContact.

**Codec-complete but zero UI call sites (21):** sendLogin, logout, hasConnection, signStart/Data/Finish,
export/importPrivateKey, setDevicePin, reboot, factoryReset, set/getAutoAddConfig, sendAnonReq, getAdvertPath,
get/setTuningParams, setFloodScopeKey, set/getDefaultFloodScope, getAllowedRepeatFreq,
share/export/importContact, getContactByKey, sendPathDiscoveryReq. All verified present in
`frame_codec.dart:530-769`.

**Absent entirely (2):** `CMD_SEND_CHANNEL_DATA` **`0x3E`** (constant declared at `constants.dart:273`, no
encoder anywhere) and `CMD_RUN_CLI_COMMAND` **`0x42`** (not even declared).

**Decoded then discarded:** `ChannelDataFrame` from `0x1B` (`frame_codec.dart:1024-1039`) has **no consumer
outside its own test**. Inbound channel datagrams are parsed and dropped. `kPayloadTypeGrpData = 0x06` is
declared and unused.

**Parsed then discarded:** the "via" byte on `0x84` (byte 3) and `0x1B` (byte 2) — wadamesh fills these
`0xA0` main / `0xA1` radio2 and MeshMore reads them as `reserved`. Two lines make radio2 observable.

**Why this matters more than any other finding:** every image, voice, PTT, file and SSH format in the MeshCore
ecosystem rides the channel datagram. One missing encoder plus one missing dispatch branch is the entire
distance between MeshMore and that ecosystem — and the receive half is already decoded and tested.

**Two hazards already known:** a `0x3E` with an empty payload is byte-identical to `CMD_SYNC_SINCE` and can
dump the whole history ring to the host; and the firmware routes raw-custom packets to a second frequency by
**first byte only** (`0x56`, `0x57`, `0x72`, `0x53`), which the app cannot observe or override.

---

## §4 Defects and limits, ranked by user impact

1. **No notification when a message arrives.** A messenger that cannot tell you it received a message while
   backgrounded. Nothing else on this list is as consequential, and it is not in the requirement set at all.
2. **No media or voice, and no transport that could carry one.** Not "unbuilt" — unreachable.
3. **History is 250 messages in plaintext `SharedPreferences`**, oldest dropped, no search, no export, and an
   in-flight send is reported as *failed* after a relaunch even if it was delivered.
4. **Radio settings have no rollback.** A frequency or bandwidth change can strand a node with no way back from
   the app. The ecosystem's answer (two-phase confirm + reset sweep) is documented and unimplemented.
5. **"Pinned" advert location does not pin.** The firmware only knows NONE and SHARE; the UI offers three values.
6. **`OK`/`ERR` carry no correlation tag**, so an unregistered command's `OK` can be credited to a pending
   channel send. The host twin solves this with a serialisation queue; the app does not.
7. **Environment telemetry is unreachable on the reference device**, so the weather chain is unverified and
   Phase 3 is shelved. Correct diagnosis, correct behaviour, dead feature until a sensor node exists.
8. **iOS is structurally incomplete**: no background BLE, no bond list, keepalive is a no-op, gateway handoff is
   a no-op, and `NSMotionUsageDescription` is missing so shake-to-derive cannot work.
9. **Region files are built and hidden** behind `kRegionFilesEnabled = false`; the only route to real offline
   vector maps is switched off.
10. **No composer length guard**, so an over-long message silently becomes an over-ceiling frame.
11. **Channel HMAC tail is zero-filled and unverified app-side** (`channel_crypto.dart:33-37`) — correct for
    sending because the device encrypts, wrong for any local verification.
12. **Tools are unverified on hardware** while their frame layouts are newer than the codec pin.
13. **Binder handoff never run across two signed apps**; both currently use the debug key.
14. **Adapter/services disagreement on gateway bind**: the adapter refuses a path longer than 14 bytes rather
    than clamping as the architecture doc describes — the code is stricter and the doc is stale.

---

## §5 Documentation drift — the spec is not the map of the app

This is a finding in its own right: **planning from the spec would under-count the product by roughly
two-thirds and mis-date about a third of what remains.**

- **The requirement namespace is broken.** R1–R37 then jumps to R52. **R38–R51 have no requirement text
  anywhere**; they survive only as test names and code comments. R42, R43, R46 appear nowhere at all. R51 names
  two different things. R56/R57 exist only as change-record prose. "R1–R108" is not a requirement count.
- **Eight requirements live outside the spec file** (R60 in the tools spec, R93 in the maps spec, R79 in STATUS,
  R56/R57 as prose), and the spec's own document map lists 9 documents while the directory holds ~25.
- **"Future" is a label, not a state, and it is wrong in both directions.** Shipped while marked future:
  F1 live map, F4 battery analysis, F8 fabric survey, R25 equal-grid, R27 globe, R28 tags, R32 shake-to-derive,
  R36 movement publish, R59 bot. Not built and **not** marked future: R30 brightness cycle.
- **Shipped and never named in the spec**: the loopback gateway, saved radio Networks (`mesh_network.dart`,
  `networks_screen.dart`), the airtime policy meter (`airtime_prefs.dart`), connected-app pairing, the USB host
  twin, ten grid views, six tools, the background telemetry poller, Meshbook, microclimate, place inference, the
  bot, the Java protocol port, and the entire XR client.
- **Two documents contradict each other on the same day.** `protocol-coverage.md:53-61` says "21 opcodes still
  missing"; `ux-coverage.md:2` says "speaks the whole firmware surface". The codec is complete and the UI
  refuses 21 by policy — both docs are describing different passes and neither says so.
- **One document contradicts itself 130 lines apart.** `radio-config.md:37` records path-hash support as
  corrected; `radio-config.md:169-176` says "not supported at all". The code ships it.
- **Three published test counts**: README header 1,014, README build block 125, STATUS 940. 128 test files exist.
- **Two documents still open with "design only — NOT built"** for shipped features (`meshbook-mbk.md:3`,
  `microclimate-wx.md:3`).
- **STATUS.md is the most reliable single source in the repo** — it names file-level causes that match the code
  — and it still carries a stale header date and a stale test count.

---

## §6 Cross-cutting weaknesses

- **No shared-core decision.** Protocol logic exists in Dart (reference), Java (port, 26 encoders), and Kotlin
  (consumes the Java layer). Any protocol addition is three implementations or an explicit non-goal.
- **No conformance gate.** 128 test files, mostly widget and controller tests. There is no golden-vector suite
  for the frames the app emits, and no test asserts the airtime formula, `path_len` unpacking, or the four
  ceilings — the things that break silently.
- **Almost no `TODO`/`FIXME` in the code.** The honesty lives in `///` docstrings that admit limits, which is
  better practice but means grep for "not supported"/"unverified"/"only" rather than for markers.
- **Stale docstrings that contradict shipped assets** — three found: `meshbook.dart:11`, `mm_skin.dart:25`,
  `asset_audio_pack.dart:18`.
- **The XR and Java artefacts are invisible to every plan document.** They are real code with real tests.

---

## §7 What this audit did not cover

- `meshmore-xr/` — 116 Kotlin files and 14 specs read only at the level of existence, size and the TODO markers
  (`MeshmoreXR-map-views-TODO.md:3` and `MeshmoreXR-node-identity-TODO.md:3` both say "FLAGGED, NOT BUILT").
- `libmeshcore/` + `libmeshcore-android/` — counted and sampled, not read.
- `meshmore-sns-UX-brief.html` (the per-theme SVG mockups) and `brand/` generators.
- No device was available, so every "UNVERIFIED" above stays unverified.
- No measurement was attempted; the reliability evidence in this programme is in
  `~/Documents/mesh-research/notes/topics/mcsim-measured-reliability.md`.
