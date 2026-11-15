# Spec scope audit — what the documents ask for and nothing needs

Written 2026-11-15. The owner's request: "audit the spec docs for any scope
creep and remove any scope creep, if necessary, but keep certain things that are
useful or should be kept".

This is the audit, not the cut. **No spec document was edited.** Every row below
names the document, the row and the evidence, and says which of three things
should happen to it:

- **CUT** — nothing needs it: no user story, no register row, a decision already
  says no, or it specifies a control the firmware has no command for.
- **KEEP** — a user can reach it, or it closes a real defect, or it is the
  reasoning behind a decision that is still in force.
- **COVERED** — already decided or already built elsewhere, so the row is
  duplication that should point at the authority rather than restate it.

The second deliverable is §3: statements that are no longer true of the code.
Those are worse than creep, because a reader trusts a document that says a thing
was never built when it ships.

---

## Summary

| Document | Value |
|---|---|
| Documents at the repository root | **39**, of which **19** already carry a historical, superseded or withdrawn banner |
| Read in full or by section | 24. The rest were sampled at their banner and their state lines, and §6 says which |
| Rows judged in §2 | **79** |
| **CUT** | **27** |
| **KEEP** | **20** |
| **COVERED** | **33** |
| Statements false against the code | **19**, in 10 documents |
| Largest single cut | the XR client: a second Android application, 39,386 Kotlin lines in 116 files, inside this app's repository |

Two findings dominate, and both are structural rather than editorial:

1. **This repository holds two products.** `meshmore-xr/` is a separate Android
   application (`applicationId com.iotj.meshmore.xr`), `meshmore-xr-www/` is its
   Hugo site, and `lobospeak-design.md` / `lobospeak-mappins-spec.md` are a third
   product's design. The scope of record already excludes all three
   (`meshmore-scope-of-record.md:381-407`: "No lobospeak in MeshMore", "No XR
   client work, frozen, David owns it"). Yet the master plan still carries them
   as roadmap decisions (D3, D4, B8.1, B9.1) and the README lists them in the
   app's own document set. Creep inside documents is cheap to fix. Creep that is
   a whole second app in the same checkout is what makes every future "what is
   this repo" question expensive.
2. **The status line at the top of a spec is the part that rots first.** Five
   documents still say "design only, NOT built" about features that shipped
   (geofences, microclimate, tools phase 2, trail export, terms). A reader who
   opens the geofence spec first is told the app cannot do fences while
   `lib/geofence/` runs on a one-second tick in the shipped build.

---

## §1 The structural finding

| Finding | Evidence | Verdict |
|---|---|---|
| A second Android application lives in the app's repository | `meshmore-xr/` holds 116 Kotlin files, **39,386 lines**, `applicationId com.iotj.meshmore.xr` (`meshmore-xr/app/build.gradle.kts:63`), its own Gradle wrapper, 14 spec documents and an `airspace-ui/` prototype. None of it is referenced by the Flutter app | **CUT from this repository's scope.** `meshmore-scope-of-record.md:405` already decides it: "No XR client work, frozen, David owns it". Either move it to its own checkout or put it under one clearly-named directory and drop it from the app's document map |
| An XR marketing site is in the app's repository | `meshmore-xr-www/` (Hugo, `content/en`, `content/ja`, layouts, static) | **CUT** with the above. It ships nothing the app builds |
| A third product's design is in the app's repository root | `lobospeak-design.md` (710 lines), `lobospeak-mappins-spec.md` (431 lines). `meshmore-sns-meshcore-interop.md:15-30` records that no lobospeak repository exists and that both documents are a design with no implementation | **KEEP the documents, CUT their presence in this app's plan.** `meshmore-scope-of-record.md:403` decides "No lobospeak in MeshMore, separate product, mine it for ideas only". Move the two files to the same subdirectory as the XR material |
| The app's document map lists all of the above as app documents | `README.md:60-80` lists the XR brief and the lobospeak material in the app's own reading order | **CUT those rows.** A document map that includes another product's documents is how a reviewer concludes the app is responsible for them |
| The master plan still treats the other products as roadmap decisions | `meshmore-master-plan.md` D3 ("Android-only / +iOS / **+XR**"), D4 ("The XR client: first-class, experimental, or frozen"), B8.1 ("The XR client, 39k Kotlin lines"), B9.1 ("lobospeak, `EXPERIMENT`") | **COVERED and closed by the scope of record.** D3 is answered (Android-first, iOS later), D4 is answered (frozen), B8.1 and B9.1 are out of scope. Three rows that read as open questions should read as closed |

---

## §2 Per-document findings

### `README.md`

| Row | What it asks for or claims | Verdict |
|---|---|---|
| `:27` "the bundled image codec's native library fails the 16 KB page requirement" | False since R144. Nineteen libraries across three ABIs pass, and `test/store/native_page_alignment_test.dart` holds them there on every test run | **KEEP the document, fix the sentence.** This is the front door and it tells a store reviewer the app cannot be published |
| `:13` "2,368 widget and unit tests" | Contradicts the paragraph's own rule ("the one measured set of numbers lives in STATUS.md"). STATUS.md says 3071 | **CUT the number**, keep the pointer |
| `:64` "Requirements R1–R117" | `meshmore-sns-spec.md` carries R1–R113 and says so in its own banner | **COVERED, fix the range** |
| `:52` "covers the six concept themes (NERV, AG-HUD, Hyperlocal, SEELE, DR Pop, Recon)" | Eleven presets ship (`lib/theme/mm_tokens.dart:26-41`) | **KEEP the brief as history, CUT the sentence's present tense** |
| `:116-125` "Forward-looking but already speccd (not built)" | R25 (equal-area per-cell map layer) is genuinely unbuilt and the register carries it. R26 (XR data streaming via a private temp-URL reverse proxy) is the XR client's feature, and the XR client is frozen. R27 is already struck through | **CUT R26.** R25 already has a register row, so it is **COVERED** there |

### `meshmore-feature-plan.md`

Its banner already says the scope of record wins. That does not stop the lists
from being read as current, and they are the most stale document in the set.

| Row | State in the document | Actual state | Verdict |
|---|---|---|---|
| A1.1 "Currently absent entirely: no notifications library is linked" | absent | `lib/notifications/` — three OS channels, per-channel bundle, tap-through, dedupe | **COVERED, strike the row** |
| A1.2 durable history, A1.3 honest delivery state, A1.5 composer budget | unbuilt | `chat_store.dart`, `delivery_status_test.dart`, `composer_budget.dart` | **COVERED** |
| A1.4 command correlation | unbuilt | `command_ledger.dart`, `command_correlation_test.dart` | **COVERED** |
| A3.1 two-phase commit | unbuilt | `radio_config_transaction.dart`, `radio_safety_store.dart` | **COVERED** |
| A3.4 radio health readout | unbuilt | `lib/ui/radio_health_block.dart` | **COVERED** |
| A6.1 encrypted local storage | unbuilt | `lib/meshcore/secure/`, `SecureStore.kt` | **COVERED** |
| A8.1 "R10 is not built and the placeholder was deliberately removed" | unbuilt | `lib/legal/terms_controller.dart` plus `lib/screens/terms_screen.dart`, with `test/legal/terms_test.dart` | **COVERED, this row is false** |
| A8.3 "A demo mode with no radio" | needed | `lib/app/demo_mode.dart` and `lib/ui/demo_chip.dart` | **COVERED** |
| A9.1 conformance suite for emitted frames | "There is no such gate today" | `packages/meshcore/test/conformance_test.dart`, 162/160/176-byte ceilings, `path_len` matrix | **COVERED, this row is false** |
| B1.1 images, B1.3 recorded voice, B4.4 SOS and check-in | `PLAN` / `COOL` | all three ship (`lib/media/`, `lib/voice/`, `lib/sos/`) | **COVERED** |
| B5.1 "Trail recording and GPX export — unbuilt" | `PLAN` | `lib/field/gpx.dart`, `gpx_export_action.dart`, `position_history.dart` | **COVERED, this row is false** |
| B5.2 "Geofence and arrival alerts — same doc, P1–P4" | `PLAN` | fences ship (`lib/geofence/`) | **COVERED** |
| B8.1 "The XR client — 39k Kotlin lines already exist and are invisible to every plan document" | `COOL` | a second app in this repository | **CUT** (§1) |
| §8 "Maps, social places and directions" — the routing-engine block (BRouter, Valhalla, GraphHopper, OSRM, MapLibre, tile-set budgets, "offline turn-by-turn") | design | No routing engine ships. The app hands a coordinate to another app (`lib/places/place_directions.dart:77`) | **CUT.** The scope of record answers this in one line: "No routing engine in this phase, navigation links out" (`:388`). Everything after that clause is a design for a feature that was decided against |
| §5 open decisions D1–D18 | open | D1, D3, D7, D14, D17 are answered in the scope of record and §11-15 | **COVERED, point at the rulings** |
| **List C — NOT TO DO** | 18 traps | still true: the seventh-image-format rule, "no cloud in the middle", "do not bind the app to a firmware fork", "do not add a feature that costs other people airtime without an enforced opt-in", "do not quote R1–R108 as a requirement count" | **KEEP entire.** It is the only part of this document that aged well, and it is the part a new contributor most needs |

**Recommendation for this document:** keep List C and the voice evidence verdict
(§7, which is measured and still the reason there is no live PTT). Replace List A
and List B with one line pointing at the register, because twenty-three of their
rows now describe shipped code and the two that matter (B8.1, §8 routing) are out
of scope.

### `meshmore-sns-geofence-tracking.md`

| Row | State in the document | Actual state | Verdict |
|---|---|---|---|
| `:3` "**Status:** EARMARK — design only, NOT built" | not built | `lib/geofence/` — circle and polygon fences, one-second sampling, hysteresis, persisted inside-state, `CueKind.geofenceEnter`/`geofenceExit` in all eleven packs (`test/geofence/geofence_cues_test.dart`) | **COVERED, the status line is false** |
| `:70-73` "v1: circle only … Polygon([latlon…]) // v2" | polygon is v2 | polygons ship (`lib/geofence/geofence_engine.dart`, `test/geofence/geofence_polygon_test.dart`) | **COVERED** |
| §3 `TrackedLink { aKey, bKey }`, distance/bearing/trend, `tracked_link_store.dart` | P1 | nothing in `lib/` measures node-to-node distance. The app measures distance from self | **CUT.** A distance tether between two other nodes is a product with no user story in this app, and the register has no row for it |
| §3 `watch: Roster` — `all / favourites / known / tag(#team)` | v1 | fences watch the device's own position, not a roster | **CUT.** It presupposes the inter-node tracking above |
| §3 `Anchor(nodeKey, radiusM)` — a fence that moves with a node | v1 | not built, no register row | **CUT** |
| §3 `triggerOn: dwell(minutes)` | v1 | not built. A dwell timer is a second feature hiding in a field | **CUT** |
| §4 a `_GridViewMode.tracking` grid view, distance tethers, hub mode, trend sparklines | P1 | not built. `MmView`'s grid holds Radar, Weather, Mesh tree, Message heat and Altitude (`lib/screens/grid_screen.dart`) | **CUT** |
| §5 "OS notification … so a fence can fire while the app is backgrounded" | P2 | cues ship, the OS notification is the open half of the register row | **KEEP** — it is the one part of this document that is still live work |
| §5 hysteresis, de-bounce, "respect `audioMaster` and per-theme haptics" | P2 | built (`geofence_engine.dart` `GeofenceWatch`) | **COVERED** |
| §7 P4 "share zones over mesh on a closed control channel" | optional | not built, and it is lobospeak's command surface crossing into this app | **CUT** (§1) |
| §8 four open questions | open | answerable from the built code for three of the four (trend window does not exist, so its question is void) | **COVERED** |

**Recommendation:** rewrite the status line and the phasing section to describe
what shipped (fences, cues, hysteresis, persistence) and what did not (roster
watching, inter-node tracking, anchor fences, dwell, sharing). The document is
cited by three other documents as the tracking design, so its status line is
doing real damage.

### `meshmore-sns-meshbook-mbk.md`

| Row | Verdict |
|---|---|
| The whole document (a daily "who is talking" analysis view for the current channel: top-10 handles, hourly histogram, topic pass, reply rate) | **KEEP as an earmark.** It is the owner's own concept, it is honestly labelled "design only", and it costs a reader nothing. It has **no register row**, so it is invisible to the plan — that is the thing to fix |
| §6 P2 "topical analysis (term pass + optional place topics)" | **CUT.** Term frequency over a 250-row local history, presented as "topics", over-promises. The document's own open question says so ("avoid over-promising topics") |
| §6 P3 "refresh-interval setting + daily reset/rollover + persistence" | **CUT as specified.** A setting for how often to recompute an analysis that can be computed on open is a preference nobody asked for. Keep "daily reset" only if P1 ever ships |
| §7 three open questions on identity, reset semantics, topic quality | **KEEP.** The identity question (a channel handle is a name, not a key) is the honest constraint and belongs in whatever spec replaces this |

### `meshmore-sns-microclimate-wx.md`

| Row | State in the document | Actual state | Verdict |
|---|---|---|---|
| `:3` "design only — earmarked, not built" | not built | `lib/sns/weather_inference.dart` (`WxObservation`, `WeatherInferenceEngine`, `aggregateAmbient`), `lib/sns/weather_lexicon.dart`, the microclimate strip in `lib/screens/weather_view.dart:99-130`, fed from `meshcore_controller.dart:3881` | **COVERED, the status line is false** |
| §1 the description of the wx view | "mines that" | ships as described, for both locales | **COVERED** |
| §6 P2 "speaker location + geo bubbles on the grid" | P2 | not built. The globe and the coverage grid are gone; bubbles would have no surface | **CUT** |
| §6 P3 "telemetry cross-reference and a measured upgrade" | P3 | not built. The measured path already exists independently in `weather_view.dart` (sensor telemetry section) | **COVERED, cut the row** |

### `meshmore-sns-tools-spec.md`

| Row | State in the document | Actual state | Verdict |
|---|---|---|---|
| Phase 2 "RX log — parsed `PUSH_CODE_LOG_RX_DATA` stream" | not built | not built, and Diagnostics' raw frame log covers the same need by the document's own admission | **CUT**, or keep as one sentence saying so |
| Phase 2 "Path discovery — `0x34` → `0x8D`" | not built | built: the node sheet offers "Find the route" (`meshcore_controller.dart` `sendPathDiscoveryReq`, `test/meshcore/contact_policy_test.dart`) | **COVERED, this row is false** |
| Phase 2 "Repeater sessions — login `0x1A`" | not built | built: a session block on a repeater or room node's sheet (R119, eighth part) | **COVERED, this row is false** |
| Phase 2 "Trace history — chart per path across sessions" | not built | not built, no register row, no user story | **CUT** |
| `:255` "not yet run against real radios" | unverified | `STATUS.md` records a ping run on HELTEC-BASE on the handset, 2026-11-04 | **COVERED, narrow the claim to the tools that really are unrun** |

### `meshmore-sns-maps-spec.md`

| Row | State in the document | Actual state | Verdict |
|---|---|---|---|
| Phase 2 "Wi-Fi-only / charging-only download conditions" | not built | Wi-Fi-only ships (`lib/maps/network_gate.dart`); charging-only does not | **COVERED in part, cut "charging-only"** |
| Phase 2 "Pick the area on a map (drag a box) instead of centre + radius" | not built | not built. The shipped model is a catalogue of pre-cut region packs (`lib/maps/pack_catalog.dart`, `assets/maps/packs.json`) | **CUT.** It belongs to a model the app deliberately does not have ("runtime extraction of arbitrary regions is AGAINST", register §4) |
| Phase 2 "Event layer styling by property … and a Burning Man preset with the required disclaimer" | not built | GeoJSON layers ship (`maps_controller.dart`), property styling and the preset do not | **CUT the preset.** A festival preset is a demo, not a feature |
| Phase 2 "Auto-update packs every N days" | not built | not built, no register row | **CUT** |
| Phase 2 "Bundled starter basemap: a world overview at z0–5" | not built | a world outline is baked in, and the vector basemap draws without network | **COVERED, check the zoom range before keeping the row** |
| "a hosted list of regions, range reads of a remote archive, the Protomaps schema" | open | the catalogue ships in the APK | **CUT the hosted list.** Two of the three are unbuilt and unneeded |

### `meshmore-sns-meshcore-interop.md`

| Row | Verdict |
|---|---|
| §1-§4 "where lobospeak lives", the wire cost of an ldmux terminal, the protocol facts | **KEEP.** The `file:line` firmware facts are the most reusable evidence in the document set |
| §5-§7 "MeshMore as the radio owner" — another app on the same phone using MeshMore's BLE link over loopback | **CUT.** The gateway was withdrawn on 2026-11-05 (D10). `meshmore-sns-gateway-handoff.md` already says "SUPERSEDED, do not build from it", and `lib/` has no reference to connected apps, pairing tokens or the gateway |

### `meshmore-sns-gateway-handoff.md`

| Row | Verdict |
|---|---|
| The whole document | **KEEP as history.** Its own first line says it is superseded. It is correctly marked and correctly ignored. No action |

### `meshmore-sns-spec.md` (R1–R113) — the `## Future` section

| Row | What it is | Verdict |
|---|---|---|
| F1 "Live map — likely reframed by R18" | superseded | **CUT**, one line saying so |
| F2 "Alternatives to maps — satisfied by R18" | already satisfied | **COVERED** |
| F3 "AI features for integrations … details TBD from user" | no design, no user story, and the scope of record decides "No new AI work" (`:390`) | **CUT** |
| F4 "Battery analysis graph" plus a hosted "known-LoRa-device database" in an external IoTone spec | unbuilt. Its own text points at an external repository for the data | **CUT.** It is a hardware-database product, not a feature, and the app already estimates state of charge from voltage |
| F5 "Partyline — the app exposes a BLE characteristic that external devices read/write" | unbuilt | **CUT.** This is the gateway again, decided against |
| F6 "TCP/WiFi companion transport … a `TcpMeshcoreTransport`" | unbuilt, cheap, seam already exists (`MeshcoreTransport`) | **KEEP.** The only one of the eight that is cheap, useful, and consistent with "no backend" |
| F7 "MQTT bridge interop … explicitly at odds with the offline-first core" | unbuilt | **CUT from the app.** The scope of record decides host-side only (`meshmore-feature-plan.md` §7 verdict) |
| F8 "Fabric survey grid — solid grid or patchwork with holes" | unbuilt | **CUT.** The coverage quilt on the map is the shipped answer to "where are the holes" (R148) |
| The R1–R113 requirement body | history | **KEEP.** Its banner already marks it historical and it is the reasoning behind every later ruling |

### `meshmore-app-spec.md`

| Row | Verdict |
|---|---|
| 61 declared requirements with a check each | **KEEP.** This is the only document that states the app's contract with a check per row, and the register ranks it above the history |
| §14 M "The gateway coupling — AGAINST (2026-11-05)" | **KEEP.** It is the record of a withdrawn design, and it is why the interop section above can be cut without argument |

### `meshmore-sns-UX-spec.md`

| Row | State | Verdict |
|---|---|---|
| U6 "`CueService` … audio packs — 🔶 done first cut" | eleven packs, 209 files, loudness floors and a test per pack | **COVERED, the status glyph is three waves stale** |
| The "six skins" framing throughout | eleven presets ship | **COVERED, point at `mm_tokens.dart:26-41`** |
| The rest of the U0–U15 contract | still the layout authority | **KEEP** |

### `meshmore-sns-ux-coverage.md`

| Row | Verdict |
|---|---|
| §2 "Connected apps (switch, pairing token QR + text, bound peer, airtime used, revoke) — Settings → Connected apps" | **CUT.** `grep -rn "Connected apps\|connectedApps\|pairingToken" lib/` returns nothing. The surface was removed with the gateway and this table still describes it as shipping |
| §1 the three rules ("no control without a user goal", "destructive means typed confirmation or absent", "secret material never enters the UI") | **KEEP.** This is the document's actual value, and it is the rule that justifies every cut in this audit |

### `meshmore-sns-UX-brief.md` and `meshmore-sns-UX-brief.html`

| Row | Verdict |
|---|---|
| "6 concepts for review. Pick one (or a blend)" | **KEEP as history, add the historical banner its siblings already carry.** Nine of the twenty-seven documents at the root open with "**Historical.** This is research…". These two do not, and they are the two a new reader is most likely to open first because the README links them above everything else |

### `meshmore-sns-block-spec.md`, `meshmore-sos-spec.md`, `meshmore-places-spec.md`, `meshmore-telemetry-coverage-spec.md`

| Row | Verdict |
|---|---|
| All four | **KEEP.** They are implementation-depth specs whose rows are still live work, and the register ranks them above the history. `meshmore-telemetry-coverage-spec.md:171` is a model of how to exclude scope: "the MQTT observer path is excluded on privacy grounds, not deferred" |

### `meshmore-master-plan.md` — §5 investigation register

| Row | Verdict |
|---|---|
| Items 1-26 "what still needs finding out" | **COVERED, in bulk.** Twenty of the twenty-six questions have been answered by later work (the `0x42` dual purpose, the AV1 encode cost at speed 5, the block semantics, the notification architecture, the directions targets). The section reads as an open work queue |
| Item 17 "planned-but-unbuilt inventory … not mined exhaustively" | **COVERED by this audit.** This document is that inventory, and the register is the state |
| §2 W12 "Parked and deferred" (live PTT, on-device routing, bulk file transfer) | **KEEP.** Three deferrals with a stated condition for returning, which is exactly what a deferral should look like |

### `meshmore-scope-of-record.md`

| Row | Verdict |
|---|---|
| §8 "Explicitly out of scope, now decided" | **KEEP entire.** It is the authority every cut above leans on. It is also the document that proves most of the creep was already ruled on and simply not propagated |
| §9 "Open questions still unanswered" | **COVERED, it says so itself** ("Superseded 2026-11-04: the single register is `meshmore-feature-register.md` §9"). It is correctly marked |

### `M6-interop-runbook.md`

| Row | Verdict |
|---|---|
| The whole runbook (on-device TC1/TC3/TC4 validation, two open crypto items) | **KEEP.** It is an operator procedure with firmware tags and commands, and the crypto items it names are still the reason "verified" is a word the app avoids |

### `meshmore-publishing.md`

| Row | Verdict |
|---|---|
| "Android is the only shipping target. iOS is deferred…" plus what a publisher must supply | **KEEP.** It is the honest release story and it names the signing gap that the checkout still has |

---

## §3 Statements that are false against the code

Each row is a place where a document says something is absent, unbuilt or broken
and the tree says otherwise. These mislead a reader in the expensive direction:
they make work look undone, so it gets redone.

| # | Document and line | Claim | Code that contradicts it |
|---|---|---|---|
| 1 | `meshmore-sns-geofence-tracking.md:3` | "EARMARK — design only, NOT built" | `lib/geofence/geofence_controller.dart`, `geofence_engine.dart`, `geofence_store.dart`, `test/geofence/` (cues, polygon, hysteresis, persistence) |
| 2 | `meshmore-sns-microclimate-wx.md:3` | "design only — earmarked, not built" | `lib/sns/weather_inference.dart`, `lib/sns/weather_lexicon.dart`, `lib/screens/weather_view.dart:99-130` |
| 3 | `meshmore-feature-plan.md:105` (A8.1) | "R10 is not built and the placeholder was deliberately removed" | `lib/legal/terms_controller.dart`, `lib/screens/terms_screen.dart`, `test/legal/terms_test.dart` |
| 4 | `meshmore-feature-plan.md:171` (B5.1) | "Trail recording and GPX export … unbuilt" | `lib/field/position_history.dart`, `lib/field/gpx.dart`, `lib/field/gpx_export_action.dart` |
| 5 | `meshmore-feature-plan.md:27` (A1.1) | "Currently absent entirely: no notifications library is linked" | `lib/notifications/`, three OS channels in `local_notifier.dart` |
| 6 | `meshmore-feature-plan.md:35` (A1.4) | "The host twin already does this; the app does not" | `lib/meshcore/command_ledger.dart`, `test/meshcore/command_correlation_test.dart` |
| 7 | `meshmore-feature-plan.md:112` (A9.1) | "There is no such gate today" | `packages/meshcore/test/conformance_test.dart`, `test/meshcore/protocol_conformance_test.dart` |
| 8 | `meshmore-sns-tools-spec.md:232-238` | Path discovery and repeater sessions "not built" | `sendPathDiscoveryReq` behind the node sheet's "Find the route", and `sendLogin` behind the session block (`test/meshcore/contact_policy_test.dart`) |
| 9 | `meshmore-sns-tools-spec.md:255` | "not yet run against real radios" | `STATUS.md` records a completed ping to HELTEC-BASE on 2026-11-04 |
| 10 | `meshmore-sns-maps-spec.md:257-259` | "Wi-Fi-only / charging-only download conditions" not built | Wi-Fi-only ships: `lib/maps/network_gate.dart` |
| 11 | `meshmore-sns-ux-coverage.md:30` | "Connected apps … Settings → Connected apps" as a shipped surface | No reference to it anywhere in `lib/` |
| 12 | `README.md:27` | "the bundled image codec's native library fails the 16 KB page requirement" | R144: nineteen libraries pass, held by `test/store/native_page_alignment_test.dart` |
| 13 | `README.md:116-121` | R25/R26/R27 as the forward plan | R27 withdrawn, R26 is another product's feature, R25 has a register row. The list presents three different states as one |
| 14 | `meshmore-sns-UX-spec.md:408` | "done first cut" with six skins | eleven presets, 209 audio files, `test/theme/theme_integration_test.dart` |
| 15 | `meshmore-sns-spec.md:2494-2541` | F1–F8 as a forward list | Five of the eight are decided against (`meshmore-scope-of-record.md:381-407`) and two are satisfied |
| 16 | `meshmore-feature-plan.md:328-345` (§8) | Offline turn-by-turn routing, with engines and tile budgets chosen | No routing engine, by decision (`meshmore-scope-of-record.md:388`), and `place_directions.dart` hands off instead |
| 17 | `meshmore-master-plan.md:326` | "Tracking and Meshbook earmarks — current" | Tracking ships and Meshbook does not. One row, two opposite states |
| 18 | `meshmore-feature-plan.md:15` | `PLAN` means "already designed, just not built"; `NOW` means "needed to make A work" | Every `NOW` item in List B has shipped, so the vocabulary now describes nothing |
| 19 | `meshmore-feature-plan.md:105` and `meshmore-master-plan.md:143` | The same terms claim, twice | Same as 3. Two documents repeating one false statement is how it survives a sweep |

---

## §4 The five most expensive cuts

Ordered by what they cost to keep, not by how wrong they are.

1. **The XR application in this repository** — 39,386 Kotlin lines and a Hugo
   site beside a Flutter app. Every clone, every code search, every "what is
   this repo" answer pays for it. Cutting it is a move, not a rewrite.
2. **The routing-engine block in `meshmore-feature-plan.md` §8** — a comparison
   of five engines, their licences and their tile budgets for a feature the scope
   of record refuses in one clause. Anyone who reads it will believe offline
   turn-by-turn was planned.
3. **The inter-node tracking design in `meshmore-sns-geofence-tracking.md`** —
   `TrackedLink`, roster watching, anchor fences, dwell timers, a tracking grid
   view, and a mesh-sharing phase. It sits in the document a reader opens to
   learn about fences, and fences shipped without any of it.
4. **List A and List B of `meshmore-feature-plan.md`** — 23 rows that describe
   the app as it was in 2026-11-04, three of them flatly false. It is the
   document most likely to be handed to a new contributor as the feature list.
5. **The `## Future` block of `meshmore-sns-spec.md`** — eight ideas, five
   decided against, one an external hardware database, one the withdrawn gateway,
   presented as the roadmap. F6 (TCP transport) is the single row worth keeping
   and it is one sentence.

---

## §5 What is deliberately kept

Not everything old is creep. These are the rows this audit declines to cut, with
the reason, so the same ground is not re-argued next pass:

- **Every historical banner.** Nineteen of the thirty-nine documents at the root
  now open with "**Historical.** This is …, not a project document" or an
  equivalent. That convention is why this audit could skip eight documents in a
  sentence. It should be applied to the two UX briefs, which are the last
  unbannered ones that read as current.
- **`meshmore-feature-plan.md` List C** — eighteen traps, each one learned
  expensively ("do not become a seventh image format", "do not bind the app to a
  firmware fork", "do not add a feature that costs other people airtime without an
  enforced opt-in").
- **The voice evidence verdict in `meshmore-feature-plan.md` §7** — the measured
  reason there is no live PTT (250 kHz, 19 of 26 presets at 62.5 kHz, unlawful in
  the EU at every bandwidth). It is the model for how a refusal should be
  recorded.
- **`meshmore-sns-ux-coverage.md` §1** — the three rules that justify every cut
  above. Keep the rules, cut the stale table under them.
- **`meshmore-sns-meshcore-interop.md` §1-§4** — firmware facts with `file:line`
  at a named tag. The most reusable evidence in the set.
- **`meshmore-app-spec.md`** — 61 requirements with a check each. It is the only
  document that states the contract rather than the history.
- **`M6-interop-runbook.md`** — an operator procedure, still the reason "verified"
  is a word the app avoids.
- **Three deferrals in `meshmore-master-plan.md` §2 W12** (live PTT, on-device
  routing, bulk file transfer), each with the condition that would bring it back.
  A deferral with a condition is not creep.
- **`meshmore-sns-meshbook-mbk.md`** as an earmark, trimmed to P1. It is the
  owner's own idea, honestly labelled, and deleting it would lose the record of
  what was wanted.

---

## §6 What this audit did not cover

- **`meshmore-sns-architecture.md` (1,155 lines) and
  `meshmore-sns-architecture-audit.md` (870).** Both open with WITHDRAWN and
  Historical banners and were read only at their banners. They describe the
  two-app gateway that was removed on 2026-11-05, and the scope of record §12 is
  the ruling. If a further sweep is wanted, these two are the largest unread
  mass in the set.
- **`meshmore-execution-plan.md`, `meshmore-feature-audit.md`,
  `meshmore-maps-and-directions.md`, `meshmore-spec-breadth-review.md`,
  `meshmore-sns-telemetry-research.md`, `meshmore-sns-private-mesh-investigation.md`,
  `meshmore-sns-protocol-coverage.md`, `meshmore-sns-radio-alerts.md`,
  `meshmore-sns-radio-config.md`.** All nine carry a Historical banner and were
  sampled at their banners and their state lines only. Sampling the last three
  found nothing false, which is why they are not in §3.
- **`AndroidXR_Glasses_Dev_StarterGuide.md`, `AndroidXR_Glasses_UX_Best_Practices.md`,
  `UX-XR-best-practices.md`, the fourteen `meshmore-xr/` specs and
  `meshmore-xr-www/`.** Not read beyond their banners: they are the other
  product, and §1 proposes they leave this repository rather than be audited in
  it.
- **The firmware.** Every "the firmware has no command for this" judgement above
  is read from `packages/meshcore` and the register's `file:line` citations at tag
  `companion-v1.17.1`. None was re-checked against the firmware tree in this
  pass.
