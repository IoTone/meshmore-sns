# MeshMore — master plan, 2026-11-04

Everything planned for the app: features, amendments to what already ships, and the non-feature work that has
to exist for either to be safe. This is the build document. `meshmore-scope-of-record.md` is the decision
record; `meshmore-feature-audit.md` is the evidence; `meshmore-maps-and-directions.md` is the map design;
`meshmore-feature-plan.md` is the analysis trail. Where this document and another disagree, this one is the
plan and the scope of record decides the argument.

Status: **planned, not started.** Nothing here has been implemented in this pass. No research was run for it.

---

> **Entry point:** `meshmore-feature-register.md` holds the single feature list, the document authority order and the
> merged open-questions register. Read it first; this document holds the reasoning behind each row.

## §1 The plan at a glance

| Milestone | Theme | Ends when |
| --- | --- | --- |
| **M1** | Foundations | The app can emit and consume a channel datagram, correlate every command reply, store secrets encrypted, and prove its own frames against golden vectors |
| **M2** | Messenger correctness | A message that arrives while the app is backgrounded produces a notification; a delivered message never reads "failed"; history is encrypted and exportable |
| **M3** | Radio safety | Every stranding setting can be reverted from the app; the app knows what the connected radio can do and says so instead of failing |
| **M4** | Places and the social map | A user can long-press the map, drop a place with a TTL, share it as text, tap a received place, and hand off directions to another app |
| **M5** | Media | Channel images and recorded voice messages arrive in pieces and can be repaired; a blocked key's content is hidden on every surface |
| **M6** | Field operations | Position history, trail with GPX, geofences with arrival cues, inter-node relationship, SOS and check-in, operational export |
| **M7** | Store readiness | Terms, privacy policy, data-safety declaration, demo mode, issues link, store assets — all in place |

Order is dependency order, not preference order. M1 is not optional and nothing above it is safe without it.

---

## §2 Workstreams

### W0 — Corrections that change earlier decisions (added 2026-11-04, second pass)

These came out of reading the firmware rather than the documents. They are listed first because three of them
change what other workstreams should build.

| Correction | Evidence | Consequence |
| --- | --- | --- |
| **The repeater firmware exists** — in `mikecarper/MeshCore`, not in the fork. The discovery trailer answer is implemented (`simple_repeater/MyMesh.cpp:3676-3690`), and `MEDIAMESH.md`'s "proposed addition" is stale | test-results + repeater source | Read-only repeater visibility is technically reachable; radio2 discovery can be expected from repeaters, never from companions |
| **`0x42` is dual-purpose, not duplicated** — CLI when `len >= 2`, FEM-gain GET when `len == 1`; both reachable | `CompanionHardwareCommandCompat.h:32-34`, `MyMesh.cpp:7811` | Treat it as arbitrary device CLI. A one-byte frame is a different command |
| **Budgets are 167 inbound / 165 outbound in keymind, 163 in meshcore-open** | `CompanionFrameLimits.h:5`, `MeshCore.h:30-31`, `MyMesh.cpp:294` | Chunk size is a per-fork constant. Sizing everything to 163 wastes 2 bytes per chunk |
| **Protocol versions are not comparable across forks** — 14 here, 27 in meshcomod, with identical "v14+" comments, and the version byte gates only message frame format | `MyMesh.h:12` vs `meshcomod/MyMesh.h:14` | Capability detection must probe commands, not compare version numbers |
| **Play's UGC policy asks for reporting and blocking, not pre-screening** | UGC policy | The work is a block action and an in-app report |
| **No stock firmware has a per-sender block list; the keymind fork adds a `dm.one_key` consent gate** | `meshcore-keymind/examples/companion_radio/MyMesh.cpp:1373`, `NodePrefs.h:121`; absent from meshcore-open, wadamesh, meshcore-team | Blocking is a radio consent gate plus an app-side store, not a protocol feature |
| **radio2 costs main-mesh reception** — 96–99 % primary vs 96–100 % secondary over 100 packets | `radio2-measured.md` | If radio2 is enabled by default, the app must say what it costs |
| **Nothing in the ecosystem implements place TTL** | three independent formats | No interop to inherit; the field must be additive and ignorable |
| **A new text tag carrying a trailing TTL is safe, and a `[WAY]` one is not** | `GeoUtils.h:102-105,128-136`; `place-report-encoding.md:43-71` | Use `[PLACE]<lat>,<lon> <label> [TTL:<duration>]` in one message: no existing client parses `[PLACE]`, so the suffix cannot corrupt a label. Inside `[WAY]` it would |

### W1 — Protocol foundations

| Item | Why | Depends on | Done when |
| --- | --- | --- | --- |
| `0x3E CMD_SEND_CHANNEL_DATA` encoder | The single highest-leverage missing line; gates every channel media format in the ecosystem. The inbound `0x1B` frame is already decoded and tested with no consumer | — | A channel datagram is emitted, received, and dispatched to the controller; both halves tested against golden vectors |
| `0x91 PUSH_CODE_ONE_KEY_DM_REJECTED` decode | 1 + 32 bytes, pushed only on a verified refusal; without it a stranger whose DM was refused sees it vanish | keymind only | A refused DM is explained in the UI, naming the refusing key |
| `0x4A`/`0x4B` firmware OTA control | A phone can drive an install-capable companion's own OTA session; without it a protocol fix needs a USB computer | `companion_protocol.md:242-243,438-471` | Status shown, install started, and the offline-queue drain explained (see below) |
| Inbound `ChannelDataFrame` dispatch | Parsed and discarded today | the encoder | A received datagram reaches a handler and a test proves the path end to end |
| Command correlation | `OK`/`ERR` carry no tag; an unregistered command's OK can be credited to a pending channel send | — | Every reply is attributed to the command that caused it; a serialisation queue or equivalent guard |
| "via" byte consumption on `0x84`/`0x1B` | radio2 traffic is currently invisible; two lines make it observable | — | The byte is read and surfaced; no longer treated as `reserved` |
| Conformance suite | No test covers the four ceilings, `path_len` unpacking, or the airtime formula; all fail silently | — | Golden vectors for every emitted frame; ceilings and path decoding asserted |
| `MeshCarryCodec` lifted into the app's send path | **Done 2026-11-05.** `0x19` is the app's own send path now (`lib/meshcore/mesh_sender.dart`); `0x41`/`0x32` encode and are vector-tested with no caller yet | correlation | The app can send raw without a gateway; binary/rawpacket have an encoder and a caller when a feature needs one |
| `0x42 CMD_RUN_CLI_COMMAND` decision | Not declared at all. It gates MediaMesh control and the buzzer toggle — and the buzzer has no CLI verb, so the "unlocks the buzzer" claim is stale | — | A decision recorded: expose behind an expert gate, or leave absent. If exposed, version-gated |
| Shared protocol core decision | Frame logic exists in Dart, Java and Kotlin | — | One reference implementation named; the other two either generated, hand-kept, or formally frozen |
| Licence register | MIT project; the best reference code is GPL; Codec2, AV1 and models each have their own terms | — | A one-page register naming every third-party artefact, its licence and its obligation |

### W2 — Messenger correctness

| Item | Why | Done when |
| --- | --- | --- |
| Inbound OS notifications | Absent entirely; the only notification today is the foreground service's persistent one | A backgrounded message notifies, routes per channel and per peer, taps through to the thread |
| Queue consumed by firmware work | An OTA session drains the offline queue down to `OTA_RETAINED_OFFLINE_FRAMES`, notifying the UI per consumed frame (`MyMesh.cpp:607-611`) | A message consumed by a firmware operation is reported as lost, not silently absent |
| False "failed" fix | A delivered message resolves to failed on relaunch | In-flight sends persist with correlation and reconcile. **Four rules:** never derive failed from a sync-poll timeout; never for channel sends at all; DMs only from `RESP_CODE_SENT` (`0x06`); keep the 30 s grace so a late ACK resolves to delivered (`companion-behaviour.md:128-136`) |
| Composer byte budget | No guard. **The firmware silently truncates:** channel text is clamped to `MAX_TEXT_LEN` = 10 × cipher block = **160 bytes including the `sender: ` prefix** (`BaseChatMesh.h:9`, `BaseChatMesh.cpp:766-773`), and the app does not count the prefix | Remaining bytes shown against the frame's real limit — **160 for channel text less the name prefix**, 162 for a channel datagram's blob, 176 for a BLE frame, 177 for a queue slot. Truncation is visible, never silent |
| Encrypted storage + migration | History and PSKs are plaintext `SharedPreferences` | One migration, keys in Keystore/Keychain, no plaintext residue |
| Backup, restore and Auto Backup rules | Nothing exists. Auto Backup gives **25 MB per user**; over quota the system calls `onQuotaExceeded()`, creates **no** cloud backup and retries later — silent loss with no user-visible error. Settings, `files/`, databases and external files are backed up by default; cache and `getNoBackupFilesDir()` never are; `<exclude>` wins over `<include>`, and supplying any `<include>` disables the default set. Target API 31+ means `dataExtractionRules` with separate `cloud-backup` / `device-transfer` sections — the split lets a file skip Drive but still move device-to-device | Explicit rules, an export the user can hold, restore tested against a fresh install, and a size check against the quota |
| Retention and storage growth | 250 messages total, and no rule for places, media or trail | Per-category retention stated, eviction visible, and a size the app reports rather than guesses |
| History correctness now, archive later | 250-message cap truncates silently | Export and per-peer threads exist; truncation is visible; archive deferred by decision |
| Per-channel notification bundle | Only the TTS mute exists | Audio, haptic, OS and TTS independently per channel, **plus a mentions-only mode** (prior art: meshcore-open `ChannelNotificationMode { all, mentionsOnly, muted }`) |
| Message search and channel unread counts | Neither exists; only DM unread is tracked | Search over history, and a per-channel unread count, both of which the block filter must then also cover |
| Message-level actions | Reply/copy/delete exist; quoting and forwarding do not | Quoted excerpt travels in the frame; forward preserves attribution |
| Blocking a key | No firmware has a per-sender block or mute; the app is the only place one can exist | A keyed store deletes and hides a key on every surface, on arrival **and on contact-list replay**; blocked nodes are counted, not vanished; the copy names what it cannot stop (§9.8, spec in `meshmore-sns-block-spec.md`) |

### W3 — Radio safety and capability

| Item | Why | Done when |
| --- | --- | --- |
| Capability detection | The app cannot say "your firmware cannot do this" | Board and firmware version detected; features gated; refusal explains itself |
| BLE link integrity | Long frames become silent corruption below the MTU | MTU read at connect and **refused below 179**, with the actual value shown |
| Identity replacement | Identity is the radio's key, so a reset or a swapped radio orphans every keyed record | Tags, favourites, blocks, DM unread and history follow the new key or are explicitly detached, and the app says which happened |
| Multi-radio ownership | Saved networks ship, but nothing says which radio owns the queue, the history or a send in flight | One radio owns the active session; switching stops the old session cleanly and states what is stranded |
| Two-phase commit + revert sweep | Frequency/bandwidth/path-hash changes are fire-and-forget; a stranding change cannot be undone | Every stranding setting confirms on the radio, keeps a last-known-good, and offers one-tap revert |
| "Pinned" advert location fix | The firmware defines only NONE and SHARE, so "Pinned" does not pin | Either the option is removed or the firmware gains the value — no third state that lies |
| Region presets and legality text | 14 presets missing vs the live set; Japan needs firmware LBT the app cannot set | Presets match reality; the LBT gap and "every node must match" are stated at the point of change |
| Radio health readout | Duty, airtime, queue depth, retries, last-heard exist as fragments | One screen answers "is my radio OK" with a reason in words |
| Read-only repeater visibility | Configured nowhere; keep out unless David built something | Either read-only visibility ships or the row stays absent |

### W4 — Places and the social map

| Item | Why | Done when |
| --- | --- | --- |
| Long-press to create a place | Nothing can be created on the map; no tap or long-press handler exists | Long-press drops a pin, opens naming and type |
| The `Place` object | Favourites are pubkeys; the only persisted place-like thing is a coverage cell | Named, typed, described, optional photo reference, provenance, reporter, created-at, TTL, confirmations |
| Place layer on the street map | Places have nowhere to live | Tappable, countdown badges, clustering once markers stop being sparse |
| Text convention first | A pin is a broadcast message; inbound parsing already resolves coordinates at 0.95 | A canonical convention carrying type, name, TTL and a deterministic id; frozen examples; parses in any client |
| Confirm and refute | A map of unverified pins becomes a lie | Independent reporters add or remove weight; "3 confirmations" is shown and costs almost nothing on the wire |
| Correction of inferred places | The only action today is dismiss | A user can confirm, correct or refute an inferred place |
| Directions handoff | Today's launch opens a pin, not directions | A directions URI to the user's maps app, with the honest "needs a connection or another app" caveat |
| Place echoes | The inference engine already mines place names from chatter | A place report can be seeded by what people already say, without anyone deliberately pinning |
| Place-ledger export | The after-action record | What was reported, by whom, when, whether confirmed, exported for a debrief |

### W5 — Media

| Item | Why | Done when |
| --- | --- | --- |
| Channel images | Requested and defensible | AV1-class image on `0x5643` (VE3 envelope; `0xAE1C` optional, never a third format), quality tiers, arrival in pieces, repair on request |
| Transport robustness | Three documented failure modes make naive transfer fail | Every resend salted; marked packets so the receiver knows when the answer ends; a completion receipt. **Measured constants:** 350 ms between fragments (~2.86 packets/s) and treat `ERR_CODE_TABLE_FULL` as normal backpressure; FEC Cauchy RS GF(256), block 20, ~10 % parity for images and ~15 % for voice |
| Recorded voice messages | Cheaper in airtime than the cheapest image; the field-appropriate input | VE3 on `0x5643`, ≤20 s, ≤20 packets, FEC on the stored copy, fetch ladder salted |
| Place photos | A place with a photo is the compelling combination | Photo reference on a place, fetched on demand, text as the fallback |
| Media off by default on Public | Enforced at the send path, not the UI | A photo or voice note on Public requires an explicit override that says why |
| PTT — deferred | Needs 250 kHz, fork firmware, and is unlawful in the EU | Gated behind a capability check; refused in EU presets; documented as deferred |

### W6 — Field operations

| Item | Why | Done when |
| --- | --- | --- |
| Position history | Every map view plots only the current fix | A ring per node, sampled on advert arrival, persisted |
| Trail + GPX export | In memory only today, lost on restart | A track survives restart and exports as GPX 1.1 |
| Geofences with hysteresis | Designed, nothing built; the only "geofence" string in `lib/` is a region suggestion | Enter/exit/dwell with a ±5 % margin, fired once per continuous stay, cue with visual and haptic parity |
| Inter-node relationship | All distances are "from me" today | "A is 400 m from B and closing", with a signed trend |
| SOS and check-in | No design exists anywhere in the repo | Long-press with confirm; **bounded** sends (12) plus a beacon that outlives them; ACK bound to a key; defined expiry. Check-in still needs a design |
| Operational export | Only tool runs export today | Chat transcript, positions and alerts for a time window, as one bundle |
| Compass and bearing cue | Bearing maths exists; nothing consumes it for guidance | A chosen target shows bearing and range on the map and in the node sheet |

### W7 — Store readiness and legal

| Item | Why | Done when |
| --- | --- | --- |
| Terms and Conditions | R10 unbuilt; the placeholder was deliberately removed | A real document, reachable from Settings |
| Privacy policy | Mandatory for the store. **"Nothing leaves the device" is false as written** — map tiles and pack downloads contact third-party servers and disclose IP and area of interest | Published, linked in-app and in the store listing, naming the two things that do leave: the radio and map fetches |
| Play data-safety declaration | Mandatory | Declares no accounts, no analytics, no telemetry; map fetches declared as the one outbound request, or removed by shipping packs pre-loaded |
| Radio-free demo mode | Needed for review and for evaluation | The app runs without a radio, against a fake transport, through the normal code paths |
| Issues link in Settings | Replaces crash reporting | Opens the public issue tracker |
| Store assets | Release by David | Screenshots per skin, description, support contact |

### W8 — Map infrastructure

| Item | Why | Done when |
| --- | --- | --- |
| Region files switched on or the claim removed | `kRegionFilesEnabled = false`; machinery exists with no published file | Either a public source is fetched with checksum and size shown before download, or "offline maps" stops being claimed |
| Public pack fetch | Decision: fetch, never host | A source list, a checksum, a size estimate, a resumable download, a refusal that explains itself |
| Storage budget re-cut | 500 MB default is shared by tiles, packs and places | Per-feature budgets with a visible breakdown |
| Honest offline story outside the US | Only two built-in sources allow packs and both are US-only | The UI says where offline works before the user starts |
| Basemap zoom honesty | Shortbread stops at z14, shown to z17 by upscaling | The ceiling is stated and the upscaling is visible |

### W9 — Interoperability

| Item | Why | Done when |
| --- | --- | --- |
| ~~Gateway: finish and freeze~~ | **AGAINST 2026-11-05** — the client owns its own radio link, so there is nothing to serve (`meshmore-scope-of-record.md` §12, D10.1) | Withdrawn with the server, the token and the Binder handoff |
| ~~Host twin: product or developer tool~~ | **AGAINST 2026-11-05** — the host daemon was the gateway over USB serial and left with it | Withdrawn |
| TAK/CoT and MQTT: host-side only, later | Both are credential and privacy liabilities in a phone app | A host-side publisher design, off by default, not started |

### W10 — Design system correctness

| Item | Why | Done when |
| --- | --- | --- |
| Seven-skins audit | David owns them and there are things he wants; all seven stay and every feature must work in all seven | Contrast, layout, missing states and device rendering checked; defects listed and fixed |
| Stale docstrings | Three contradict shipped assets | Corrected |
| Accessibility bar held | R13 already treats it as a requirement | New features carry semantic labels and non-audio equivalents |
| l10n parity | EN+JA in lock-step, guards exist | New strings added in both; dev panels stay English by decision |

### W11 — Documentation repair

| Item | Why | Done when |
| --- | --- | --- |
| Requirement numbering | R38–R51 do not exist; R51 means two things; eight requirements live elsewhere | Defined or retired; the namespace repaired |
| "Future" section | Wrong in both directions; eight items marked future are shipped | Rewritten to match the code |
| Document map | Lists 9 documents; the directory holds ~25 | Completed |
| Self-contradictions | Four named in the audit | Corrected, with the old claim visible |

### W12 — Parked and deferred

| Item | State | Revisit when |
| --- | --- | --- |
| Live PTT | Deferred | A lawful 250 kHz setup exists and voice reliability is measured |
| On-device routing | Deferred | Someone publishes per-region packs and the storage budget allows |
| Bulk file transfer | Deferred | Media proves itself and a dedicated frequency story exists |
| AI | Keep what David built; add nothing; clean up what is not good | The owner defines "not good" |
| lobospeak | Parked; mine for ideas only | Its carriage question is decided |
| XR client | Frozen; David owns it | The core product is solid |
| KISS modem, Meshtastic bridge, public map upload | Refused this phase | A user asks with a reason |
| Battery device database | Five entries and excludes the reference T1000-E | A device database worth having exists |

---

## §3 Needs — the non-feature work

These are not features. Nothing above is safe or shippable without them.

- **N1 Golden vectors and fixtures** for every emitted frame, plus frozen place-text examples. *Half closed 2026-11-04:* the set **already exists twice** — identical `m1`–`m5` plus `interop/SCHEMA.md` in the Dart package and in `libmeshcore`. The open part is ownership and which implementation is the reference.
- **N2 A capability-negotiation convention.** The app must learn what the radio can do without guessing from a version string. No convention exists in the ecosystem; the honest fallback is "probe and cache".
- **N3 Encrypted storage and one migration.** Before history grows and before places exist.
- **N4 — A block store keyed by the full 32-byte public key.** Stock firmware offers contact removal only; the keymind fork adds a `dm.one_key` consent gate for unknown senders. Neither is a blocklist. The app must hold the list and apply it to every surface, and the copy must say what blocking cannot stop.
- **N5 Codec2 licence clearance and per-ABI native packaging.** Android ships no Codec2; voice messages need a bundled native library. Licence terms unchecked.
- **N6 The place text convention, specified with examples.** It is the whole sharing story before `0x3E` exists, and it must carry type, name, TTL and a deterministic id.
- **N7 A map-pack source register** — URL, checksum, size, licence and update cadence per region. The project fetches and never hosts, so a dead URL is a product failure.
- **N8 Store package** — privacy policy, data-safety answers, screenshots per skin, support contact, a demo-mode build.
- **N9 A device test matrix** — Android versions in use, the radios actually owned (reference: Seeed T1000-E and Heltec V4), boards the app claims. Nothing in the field set has been run against real radios except the maps self-test and the first live pass.
- **N10 The shared protocol core decision** — one reference, two derivatives, or three independents. *Half answered:* three consumers exist (Dart, Java `libmeshcore`, the XR client) and two already agree byte-for-byte against the shared vectors, so the contract is the vectors, not a codebase. Decide ownership, not architecture.
- **N11 A licence register** — MIT project; GPL reference code cannot be copied; Codec2, AV1, image codecs and ODbL map data each carry obligations.
- **N12 Documentation repair** (W11) as its own pass, because plans keep being derived from documents that are wrong.
- **N13 A measurement plan** for the two gaps the research left open: bulk-transfer reliability, and collision behaviour under load. The tools exist (`mcsim`); the experiments do not.
- **N14 Accessibility and l10n guard expansion** so "every feature works in all seven skins" is enforced rather than remembered.
- **N15 A store-policy review of the block action** — what blocking must do to satisfy Play's UGC policy, and what it honestly cannot do: stop the radio receiving, relaying or storing a packet.

---

## §4 What "done" means, per milestone

- **M1** — a channel datagram is emitted and consumed in the app; every command reply is correlated; secrets are encrypted; the conformance suite fails when a frame changes unexpectedly.
- **M2** — a message arriving while the app is closed produces a notification; a delivered message never reads failed; history is encrypted and exportable; a long message cannot silently exceed a ceiling.
- **M3** — every stranding setting can be reverted from the app; the app refuses a feature the radio cannot do with a specific reason; "Pinned" either works or is gone.
- **M4** — long-press creates a place; the place has a TTL and shows a countdown; the place is shareable as text and tappable when received; directions leave for another app; confirmations accumulate; expired places leave the layer but survive locally.
- **M5** — an image and a voice message both survive a lost packet and repair on request; nothing media-related sends on Public without an explicit override; a blocked key's content is deleted from the app and hidden from every surface, and the copy said so first.
- **M6** — a track survives restart and exports as GPX; a geofence fires once per stay with hysteresis; A-to-B distance and trend are shown; SOS stops after its bounded sends and its beacon; a time-window bundle exports.
- **M7** — Terms, privacy policy, data-safety declaration, demo mode and issues link all exist and are reachable; the store listing is complete.

---

## §5 Investigation register — what still needs finding out

Every entry is a question with the decision it changes. Most have not been researched; the two that have say so.

### A. Protocol and wire

1. **What the research set already knows that the plan has not absorbed** — the five notes on protocol, frames, wire layouts, the command table and the group-data registry have not been re-read against this plan. *Changes:* which opcodes to expose, which to avoid, and the hazards list.
2. **The `0x42` opcode question** — *answered in W0 and §9.2:* it is dual-purpose, CLI when `len >= 2` and the FEM-gain GET when `len == 1`, both reachable. What remains is whether to surface it at all, which is a product call.
3. **Group-data type registration** — what is registered, what is squatting, what MeshMore should register for places and media. *Changes:* whether place reports get a registered type or ride text forever.
4. **The `0x3E` frame layout against real hardware** — verified from third-party implementations and firmware source, never exercised on the reference device. *Changes:* the encoder's correctness gate.
5. **Upstream direction** — multipart's stalled state and the US 500 kHz question. *Changes:* whether to build a private chunking scheme and how to do airtime arithmetic.

### B. Media

6. **Media constants and failure modes in the notes** — the pipeline mechanics, transports and text-compression notes have not been re-read against this plan. *Changes:* image budgets, FEC parameters, envelope formats, and what text compression is worth.
7. **AV1 encode cost on low-end Android** — decode is measured elsewhere; encode timing and peak memory are not.
   *Changes:* whether the 320×240 floor and speed 8–10 are affordable on a 4-core device.
9. **AV1 decoding in Flutter on Android** — which decoder, what licence, what latency and memory. *Changes:* image quality tiers and whether images are usable on low-end devices.

### C. Field, radio and legality

10. **Retry and session rules** — the retries note has not been re-read; it carries the anti-patterns, Karn, path-cache expiry and the salt rule. *Changes:* the send path's retry design.
11. **Legality specifics** — which presets are unlawful where, the US 500 kHz argument, EU duty cycles, Japan LBT. *Changes:* what the app refuses, warns about, or hides.
12. **Power and PHY** — what a phone app can influence, what "power saving" costs, whether FLRC matters. *Changes:* whether any battery feature is honest.
13. **Field design patterns** — slotted reply timing, dynamic staleness, beacon rate floors, radio silence, late-ACK grace. *Changes:* the alerting and beacon designs.

### D. Security and privacy

14. **Channel key enumeration and the AES-ECB/no-IV issue** — what the app can and cannot verify locally, and what the UI must say. *Changes:* whether the app ever claims local verification.
15. **The 16-byte HMAC tail and the zero-fill workaround** — correct for sending, wrong for verification. *Changes:* what "verified" means anywhere in the UI.
16. **The device-wide sync word** — what it means for "private" meshes. *Changes:* the private-mesh wording and the honest threat model.

### E. The repo's own documents

17. **Planned-but-unbuilt inventory** — the tools phase 2, maps phase 2, radio alerts layers, protocol coverage refusals, UX coverage, geofence P1–P4, meshbook P3, microclimate P2–P4, lobospeak, gateway handoff and the architecture phases have not been mined exhaustively. A previous pass truncated its middle. *Changes:* items missing from this plan.
18. **David's documentation** — the XR repo's 14 specs, the Java protocol port, and material outside this repository. *Changes:* the map, place and role design; and whether anything here duplicates his work.
19. **Whether David built anything in repeater/room administration** — *Changes:* whether read-only visibility ships at all.

### F. Maps and directions

20. **Map-pack sources** — exact URLs, checksums, sizes, licences and update cadence for tiles and routing packs. *Changes:* the offline story and the refusal wording.
21. **Directions handoff targets** — which apps to offer first and what URIs they accept. *Changes:* the share sheet and the fallback.

### G. Product and process

22. **Skins correctness criteria** — what counts as broken: contrast, layout, missing states, or all three. *Changes:* the audit's definition of done.
23. **AI cleanup criteria** — what "not good" means, so removal is a decision and not a taste call. *Changes:* what gets deleted.
24. **Block semantics against the device** — *answered in §9.8.* What remains: the copy's exact wording and whether the keymind `dm.one_key` consent gate is exposed as a setting. *Changes:* the block UI.
25. **Notification architecture on current Android** — permission flow, foreground-service types, doze, and what survives a locked screen. *Changes:* whether the messenger claim is true.
26. **Bulk-transfer and collision measurements** — the two open reliability gaps. *Changes:* any promise about media delivery times.

---

## §6 Risks this plan carries

- **Blocking is app-side, so it cannot be enforced on the radio.** A blocked key's channel messages still arrive and are stored on the device. The firmware has no per-sender mute either: `setNotificationOutputMute` takes an output (`Sound`, `Vibration`), not a key (`meshcore-keymind/examples/companion_radio/MyMesh.h:334`), so silencing a blocked key is the app's job. The honest block is three actions: a keyed store the app filters on every surface, contact removal, and the keymind `dm.one_key` consent gate where that fork is present.
- **`0x3E` is verified only against third-party implementations.** The first real-hardware test is a milestone gate, not a detail.
- **Media and places both depend on W1**, and W1 is unglamorous work with no user-visible output. It is the most likely thing to be skipped and the most expensive thing to skip.
- **The seven-skins requirement multiplies every feature by seven.** It is a deliberate choice; it should be priced as one.
- **Fetching packs from public sources makes a third party's URL a product dependency.** A dead URL is a support ticket nobody can fix.
- **Nothing in the field set has been run against real radios** except two documented passes. Every "SHIPPED" in the audit means "runs in tests", not "runs in the field".
- **Documentation keeps being the weakest link.** Plans derived from the spec have been wrong by two-thirds; plans derived from the "Future" list have been wrong in both directions.

---

## §7 Document map

| Document | Role | Status |
| --- | --- | --- |
| `meshmore-feature-register.md` | **Start here.** One list of features with a state each, the authority order, and the merged open-questions register | current |
| `meshmore-master-plan.md` | This document — everything planned | current |
| `meshmore-scope-of-record.md` | Decisions taken, with consequences | current |
| `meshmore-feature-audit.md` | Evidence: what exists, what is broken, where docs lie | current |
| `meshmore-maps-and-directions.md` | Map stack, places, routing options and licences | current |
| `meshmore-app-spec.md` | **The normative app specification:** fourteen requirement groups, a check per row, traceability to decisions, five structural gaps named | current |
| `meshmore-sns-block-spec.md` | The block feature: three actions, the keyed store, surfaces, state machine, copy, tests. **The depth template** | current |
| `meshmore-sos-spec.md` | SOS and check-in: grammar, exact 12-send/10-beacon schedule, the channel-vs-direct ACK attribution rule, ten tests | new |
| `meshmore-places-spec.md` | Places: anchored grammar, nine-token closed type set, id derivation without time, renewal, rate limit, ten tests | new |
| `meshmore-telemetry-coverage-spec.md` | Telemetry decoding table and coverage cell model: request/push, noise code table, pacing, observed-only edges, ten tests | new |
| `meshmore-feature-plan.md` | Analysis trail and full candidate pool | superseded in part |
| `meshmore-sns-spec.md` | Original requirements and change record | needs repair (W11) |
| `meshmore-sns-architecture.md` + `-audit` | Architecture and its self-corrections | current, with stale sections |
| `meshmore-sns-maps-spec.md` | Map detail behind R81/R83/R93 | current |
| `meshmore-sns-tools-spec.md` | Tools and phase 2 | current |
| `lobospeak-design.md`, `lobospeak-mappins-spec.md` | Separate product, parked | parked |
| `meshmore-sns-radio-config.md` | Radio settings and the two-phase commit | current |
| `meshmore-sns-protocol-coverage.md` | Which protocol surfaces are covered by the app | current |
| `meshmore-sns-ux-coverage.md`, `meshmore-sns-UX-spec.md`, `meshmore-sns-UX-brief.md` | UX coverage, U0–U15 spec and the design brief | current |
| `meshmore-sns-radio-alerts.md` | Radio chime and firmware alert design | current |
| `meshmore-sns-telemetry-research.md`, `meshmore-sns-microclimate-wx.md` | Telemetry and weather | current |
| `meshmore-sns-meshcore-interop.md`, `meshmore-sns-architecture.md`, `-audit` | Shared-transport architecture and its adversarial review | current |
| `meshmore-sns-geofence-tracking.md`, `meshmore-sns-meshbook-mbk.md` | Tracking and Meshbook earmarks | current |
| `meshmore-sns-private-mesh-investigation.md`, `meshmore-sns-gateway-handoff.md` | Private mesh; the gateway handoff is **superseded 2026-11-05** | private mesh current, handoff history |
| `M6-interop-runbook.md` | The interop runbook | current |
| `AndroidXR_Glasses_Dev_StarterGuide.md`, `AndroidXR_Glasses_UX_Best_Practices.md`, `UX-XR-best-practices.md` | XR platform material, David's track | reference |
| `meshmore-sns-block-spec.md`, `meshmore-feature-register.md` | Block spec and this register | current |

---

## §8 Additions and closures — second investigation pass, 2026-11-04

The first pass read documents; the second read firmware and sources. This section records what changed, so the
plan above stays the baseline and this stays the delta. Evidence lives in
`mesh-research/notes/topics/` (`radio2-measured.md`, `companion-behaviour.md`, `places-sos-prior-art.md`,
`blocking-and-ignore.md`, `coverage-and-simulation-tools.md`, `awesome-list-coverage.md`, `planned-but-unbuilt.md`).

### New work items, by workstream

**W1 — Protocol foundations**

- Emit against **167 inbound / 165 outbound** for keymind firmware, and treat 163 as the meshcore-open figure; make
  the chunk size a capability, not a constant.
- **Probe for capability, never compare protocol versions** — 14 and 27 are both current on different forks.
- Handle `0x42` as **dual-purpose** (`len >= 2` CLI, `len == 1` FEM-gain GET) and never as a MediaMesh-only surface.
- Add the **Wireshark dissector as a conformance oracle** in CI where a witness capture exists — run it, never
  vendor it (GPLv2). Its tests already assert the packed `path_len` separately from the raw byte.

**W2 — Messenger correctness**

- **A sync-poll timeout means unknown, not empty.** A frame is removed only after the transport accepted it; a
  missing reply means poll again.
- **Channel datagrams can be silently dropped** when the offline queue is full of direct messages — the firmware
  ignores the enqueue result on that path. Media needs its own completion evidence.
- Show **battery mV, uptime, queue depth, airtime and receive errors** from the stats frames, and turn the four
  `ERR_EVENT_*` bits into words (pool full, CAD timeout, startRX timeout, watchdog recovery).
- Show **self telemetry** (MCU temperature, voltage) from the `0x8B` push, and respect the single-outstanding
  telemetry request slot.

**W3 — Radio safety**

- Say what radio2 **costs**: 96–99 % primary reception against 96–100 % secondary over 100 packets, with the main
  mesh paying. If radio2 is on by default, the cost is on the switch.
- Discovery trailers come from **repeaters, room servers and sensors only** — a companion parses but never emits.
  A three-state parse is mandatory, and "no trailer" means unsupported.
- Surface the **device alert engine** (buzzer, LED, vibration, GPIO) as configurable from the phone — the radio can
  alert when the phone is not there. Note that an authenticated on-air admin can also change it.

**W4 — Places**

- Adopt **one message, one new tag**: `[PLACE]<lat>,<lon> <label> [TTL:<duration>]`, TTL parsed only from the end
  (`place-report-encoding.md:43-71`). The suffix is safe **because** the tag is new — Solo requires an exact `[LOC]`
  and refuses `[WAY]`, meshcore-open parses `m:`, and neither touches `[PLACE]`. Two messages would double airtime
  and reintroduce half-delivery, where a place arrives without its TTL and silently takes the 24 h default.
- **Coordinates are 6 decimal places with a mandatory point**, matching the grammar that refuses integers so plain
  messages cannot move a pin. **Label ≤ 60 characters**, because the budget is 165 bytes including the name prefix.
  **TTL is a duration only** (`1h 6h 24h 72h 168h`, clamped at 168 h) — a deadline would depend on a peer's clock,
  and these clocks are unset. **Absent TTL defaults to 24 h.**
- Add the **store surfaces the UGC policy requires**: terms acceptance before the first upload, an in-app report
  action on any user content, and a real block action (a blocked key's content must vanish from feeds, messages and
  search).
- Adopt the team app's **backlog findings**: colour-code a received place until tapped, show who sent it, and
  validate `lastSeen` defensively so a still node never reads "1d ago".

**W5 — Media**

- **AV1 encode is the open media cost.** Decode is measured elsewhere; encode timing and peak memory are not.
  `avif_native` + `flutter_libavif`, 320×240 floor, speed 8–10.
- **Block surfaces are separate from the wire.** Terms acceptance, an in-app report action and a real block keyed
  by public key, applied to every surface. None of them change the transport.

**W6 — Field operations**

- **SOS: bounded sends (12), a 5-minute beacon that outlives them, a one-hour-old-fix limit, and an ACK bound to a
  key** — not "retry until acknowledged", which cannot terminate on a flood.
- **Coverage / "who can hear me":** a zero-hop advert plus `DISCOVER_REQ` with an 8-character ID, correlating
  `0x84`/`0x8E` replies. Time-weighted geohash cells (1.0 / 0.8 / 0.5 / 0.2) with contradiction demotion to 0.1,
  and edges drawn only from observed response paths.
- **Trail:** streaming Reumann–Witkam with a 0.5 corridor anchored at the last committed vertex, segment flags for
  pauses, and a GPX export through MeshMore's own transport — never a raw serial stream sharing the port.
- **History:** batch commits 60 s from the first unsaved change, settle 60 s before finalising a record, key channel
  records by channel key, and make records walkable from the end by carrying their own length.
- **Bearing:** gate on movement, or a stationary node's arrow spins.

### New needs

- **N16 — A coverage-ping harness.** The mechanism exists and needs no protocol work; what is missing is a screen,
  storage and a confidence surface.
- **N17 — `meshbench serve` in CI.** The only way to exercise the send path against a real routing stack with
  terrain. It cannot model media or radio2, so the assertion is per-packet, not per-image.
- **N18 — An attribution emitter for map packs.** Every pack ships an ODbL notice; the ecosystem's tile tooling
  writes none, which is why it cannot be imitated.
- **N19 — A UGC compliance surface.** Terms acceptance, in-app report, and a real block keyed by public key, applied to every surface.
- **N20 — A licence register that distinguishes code, weights and data.** Three separate grants; a permissive repo
  badge says nothing about the other two.

### Closures

- **G2 (awesome-list coverage) is closed** as a measured finding: 214 slugs, 115 covered, **99 not**, grouped with a
  reason each might matter. Coverage means "cloned or mentioned" — of 115, 47 are cloned and ~13 read in depth.
- **The repeater half of MediaMesh is no longer unknown.** It exists in `mikecarper/MeshCore`; the fork contains
  companion code only.
- **radio2 reliability has a number**, and it is not 197/200: 96–100 % secondary / 96–99 % primary over 100 packets
  at mismatched PHYs, 40/40 matched, switch 400–1,176 µs.
- **Place TTL has no prior art**, confirmed from three independent formats — so no interop is inherited and the field
  must be ignorable by existing clients.
- **Blocking has no radio support**, so it is an app-side store keyed by public key; the keymind fork's
  `dm.one_key` is the only consent gate any firmware offers, and no firmware offers a per-sender mute.

### New open questions

**Superseded 2026-11-04:** merged into `meshmore-feature-register.md` §9.

1. **What a block must suppress, and what it cannot.** The radio still receives, relays and stores a packet; only
   the app surfaces can hide it.
2. **Whether the keymind `dm.one_key` consent gate is worth depending on**, given it exists in one fork only and
   defaults off (`MESH_ENABLE_ONE_KEY_DM 0`, `MyMesh.h:124`).
3. ~~Does a both-formats place tag with a separate TTL tag get read correctly by other clients~~ **Answered: use one
   new tag with a trailing TTL** (`place-report-encoding.md:43-71`). **Still open:** whether the *type* travels as a
   token or stays unstructured in the label, and the time-bucket width for the deterministic id.
4. **Is `meshbench serve` deterministic enough for CI** once a phone app drives it, and what does a per-packet
   assertion cost in wall time.
5. **How does a coverage ping behave on a busy mesh** — the four-per-two-minutes repeater reply limit means a dense
   area saturates quickly.
6. **Should the app expose the device alert engine** given that an authenticated on-air admin can change it too.

---

## §9 Final investigation pass, 2026-11-04 — the baseline changes

Everything above was written as if this were a build. It is not. The repository holds a **working app**: ~172–188 Dart files
(389 counting generated and package files), ~128 test files, 940 tests, `1.0.193+9`, seven implemented skins, 22 routes with no orphans, offline maps,
telemetry, six tools, a docs reader, a bot responder, a loopback gateway, and a pure-Dart protocol package pinned
to `companion-v1.15.0`. The plan below this line is therefore a **delta against shipped code**, and the honest
estimate for the map, telemetry, tools, docs and skin work is "fix and verify", not "implement".

### 9.1 Four defects found by reading the code, in priority order

| # | Defect | Why it ranks here |
| --- | --- | --- |
| 1 | **The app negotiates protocol version 1.** `frame_codec.dart:393` defaults `appTargetVer = 1`, and both call sites pass nothing, so `MyMesh.cpp:1647,2333` never emits the V3 message frames. They are the only frames carrying **per-message SNR** | One default argument silently disables a whole response family, and the V3 decoders in the package are unreachable. Fix this before diagnosing any "no signal shown" report |
| 2 | **The channel datagram's `reserved1` is the radio profile, and the decoder discards it.** `MyMesh.cpp:2423` writes `rxViaTag(pkt, 0)`; `frame_codec.dart:1029` reads it into nothing | It is the only field that says whether a datagram arrived on primary or radio2. Without it, media attribution is impossible |
| 3 | **`decode` never checks it consumed the frame.** `CHANNEL_INFO` reads a fixed 16-byte PSK while the firmware can send 32 (`MyMesh.cpp:7629-7634`) | Every future field-width divergence will be silent rather than loud |
| 4 | **BLE assumes one notification is one frame** (`transport.dart:14-18`) with **no MTU read-back** | The firmware requests 179 bytes (`SerialBLEInterface.cpp:734-736`) but the Android central decides; a 176-byte frame at a 23-byte MTU decodes as nine garbage frames, quietly |

Two smaller ones: `isPush` is `code >= 0x80`, so the two frames that are *never* replies (27 `CHANNEL_DATA_RECV`,
29 `CLI_REPLY`) are classified as replies; and `interop_replay_test.dart:35` is an empty passing test, so there is
**zero device-derived conformance evidence** anywhere in the package.

### 9.2 The media prerequisite is smaller than it looked, and one blocker is smaller than it looked

- **`CMD_SEND_CHANNEL_DATA` (62) is implemented in the firmware** (`MyMesh.cpp:6949-7002`), so the encoder is the
  only missing half. The decoder already exists and is field-for-field correct. **Inbound channel datagrams are
  currently decoded and dropped** — nothing consumes `ChannelDataFrame`.
- **The payload budget is 162 bytes, not 165 and not 163.** 165 is the datagram cap; `[data_type u16 LE][len u8]`
  takes 3 of it (`BaseChatMesh.cpp:785-800`).
- **Unknown `data_type` is not dropped by the radio**, so a 16-bit app namespace needs no registration — but a blob
  whose first bytes parse as a plaintext management page is diverted before decryption (`Mesh.cpp:1428-1436`), so
  the first blob byte must be chosen to avoid that shape.
- **The blocker, corrected 2026-11-04: unscoped floods are allowed by default.** The gate fires only when the packet
  arrives with no matching region **and** the wildcard carries `REGION_DENY_FLOOD` **and** no regionless scope or
  channel-scope bypass applies (`simple_repeater/MyMesh.cpp:1184-1189`, `:2826-2836`). Stock defaults are
  `flood_max_unscoped = 64` (`:3922`) and `flood_channel_data_enabled = 1` (`:3949`). So broadcast media fails by
  **repeater configuration**, not by protocol: a wildcard that denies flood, or a channel-scope table that requires
  a region. **Decided:** inherit and display the radio's own default flood scope rather than invent a region concept;
  offer an explicit unscoped send with the warning; keep DM-and-known-channel mode as the safe default for media.
  What remains unknown is undiminished — **the app cannot discover a repeater's configuration**, so it cannot
  promise delivery on any broadcast.
- `ERR_CODE_TABLE_FULL` is **normal backpressure** (packet pool of 16), not an error. The dedup window is 160 hashes,
  so a retransmission after 160 packets is flooded twice. Channel data has **no ACK at all**.

### 9.3 A decision closed by evidence

**AV1 is confirmed and the format question resolves by shipping the decoder.** Flutter does not decode AVIF
(`dart:ui` guarantees JPEG/PNG/GIF/WebP/BMP/WBMP only, and the engine deliberately externalises codecs because the
binary cost cannot be tree-shaken). A mesh app cannot negotiate a format with a receiver that may fetch the image
years later, so **the app must ship the decoder**, which means hardware AV1 support stops being a requirement and
becomes a power optimisation. Use `flutter_libavif` for display (real `ImageProvider`s, `cacheWidth` folded into the
native decode so a thumbnail never allocates full-resolution RGBA) and `avif_native` for encode (`libavif` + `dav1d`
+ `aom`). Reject `imcodec_native` (unbuildable beside `avif_native`; its LGPL clause was withdrawn 2026-11-05, see scope-of-record D11.3) and `flutter_avif` on maintenance. Encode at speed 8–10, **320×240 floor**:
container overhead is 200–350 bytes, and above q85 AVIF is *larger* than JPEG, so the small-image regime only works
at the low-bitrate end where the app actually is.

### 9.4 The store gates, as build requirements rather than policy reading

- **Target API 36.** Mandatory for new apps *and updates* since 31 August 2026. No stagger, no exemption.
- **16 KB pages.** Blocking from 1 February 2027. The Flutter engine is aligned to 64 KB; **plugins are the risk**.
  A build can pass `zipalign -c -P 16`, pass `check_elf_alignment.sh`, and still be rejected on **RELRO
  end-padding** (`PT_GNU_RELRO` `VirtAddr + MemSiz` not on a 16 KB boundary), which is inserted at link time and
  cannot be repaired locally. Add RELRO to the release checklist; the failure is invisible until submission.
- **`connectedDevice` foreground service:** `FOREGROUND_SERVICE` **and** `FOREGROUND_SERVICE_CONNECTED_DEVICE`
  unconditionally, plus any one of the Bluetooth runtime permissions. No 6-hour timeout — that is `dataSync` and
  `mediaProcessing` only, which is why `dataSync` for a BLE link is a self-inflicted failure.
- **The declaration video is a screen, not a document.** Play requires a video showing *"the user pairing and
  connecting to an external device directly inside the app… not system settings."* MeshMore needs an in-app
  scan-and-pair flow that is demonstrable end to end. Evaluate **Companion Device Manager** as the architecture: the
  platform recommends it for exactly this case, it removes the location entanglement (`neverForLocation` is
  build-time and irrevocable, and filters some beacons), and it restores background service start.
- **Export compliance blocks every track** until answered, and MeshMore triggers it three ways (TLS, encrypted
  storage, JWT signing).
- **UGC obligations are separate from the transport:** non-skippable terms before the first upload, an in-app report action, and a real block action keyed by public key.

### 9.5 The theme problem, because every new screen makes it worse

The seven skins are real — `nerv, agHud, hyperlocal, seele, drPop, recon, studio` — and the preset switch is
exhaustive, so an eighth preset is a compile error until its bundle exists. **It now has one:** Studio Light
(`studioLight`, R115, 2026-11-05) is the eighth, and `mmSkinFor` deliberately has no `default:` clause, which is
what turned "an eighth is a compile error" into a checklist rather than a hope. But **`MmType` has no size, spacing or
radius scale**, so every type step is a literal: >250 `fontSize:` values in `lib/screens` (grep hit its cap), 26

`Color(0x…)` literals across nine files, 19 `Colors.*`, and 79 `fontFamily: 'JetBrains Mono'` which *are* ratcheted
by a test. Colours are not.

**Add the type scale to the tokens and a colour ratchet before adding any feature screen**, or "every feature works
in all seven skins" becomes unenforceable within a release.

**Done (W2, 2026-11-04):** the scale exists — `MmType.size`/`typeScale`, `MmSpace` (insideText 2, labelToControl 4,
rowGap 8, rowInset 12, screenEdge 16, sectionGap 24, emptyState 32), `kRadiusXs/Sm/Md` with the 1 px floor, and the
guards that hold them (`test/ui/mm_spacing_test.dart`, `mm_ratchet_test.dart`, `radius_floor_test.dart`,
`tap_affordance_guard_test.dart`). The numbers above are the state this section found, kept as written.

### 9.6 Revised order, by dependency

1. **Fix the four defects** (§9.1). Small, independent, and one of them is a default argument.
2. **Skin tokens: type scale + colour ratchet.** Prerequisite for everything visual.
3. **In-app pair flow** and CDM evaluation — required by the store, and it is the first-run experience.
4. **Media: `0x3E` encoder + `ChannelDataFrame` consumer + reassembly with a request-missing-chunks path.** The
   decoder half already exists; the broadcast-vs-DM scope decision (§9.2) gates which modes ship.
5. **Block surfaces**, Terms and in-app report in the same release as the first photo path.
6. **AVIF encode and display.** `avif_native` + `flutter_libavif`, 320×240 floor, speed 8–10.
7. **Places with TTL** as one `[PLACE]` message with a trailing `[TTL:<duration>]` (`place-report-encoding.md`),
   because the new tag is what makes the suffix safe.
8. **SOS**, bounded sends plus an outliving beacon, ACK bound to a key.
9. **Coverage ping**, advert plus `DISCOVER_REQ` with an 8-character ID, correlating `0x84`/`0x8E`.
10. **Verify the ~40 unverified behaviours on hardware.** Nothing in the repository substitutes for this.

### 9.7 Open questions, unresolved after the full pass

**Superseded 2026-11-04:** the single register is `meshmore-feature-register.md` §9. Kept for the record.

1. **Broadcast media versus scopes.** Require a region, double-send, or restrict to DMs and known channels?
2. **Which first blob byte avoids the management-page shape**, and does the chosen app-data type need to be
   registered anywhere to be safe from a future firmware collision?
3. **Does the app's protocol version bump to 3 break any shipped behaviour** in the app's own tests, given they were
   written against V1 frames?
4. **CDM or a permanent foreground service** for the link, given the store video requirement and the background-start
   exemption.
5. ~~What does a block do to a queued message already in the offline queue~~ **Decided: discarded on sight, and
already-stored rows for that key are deleted when the block is set.** Unblocking restores nothing.

### 9.8 Blocking a key, as a spec

- **What the radio can do: nothing keyed.** Stock firmware offers contact removal and no per-sender mute; the
  keymind fork adds `dm.one_key`, a consent gate that holds DMs from unknown senders. `setNotificationOutputMute`
  takes an output (`Sound`, `Vibration`), never a key (`meshcore-keymind/examples/companion_radio/MyMesh.h:334`).
- **What the app must do.** Store blocked keys as the full 32-byte public key, never a display name (a name is
  user-typed and collides). Filter on every surface that renders content: channel timeline, DM list, threads,
  search, map places, and the app's own notifications.
- **What a block cannot do.** It cannot stop the radio receiving the packet, relaying it for others, or writing it
  to the device's own message store. The device's alert engine runs on the radio and may still buzz. Copy must say
  so, or the first blocked message that buzzes reads as a broken feature.
- **The store obligation is the block action plus a report action and terms acceptance**, not a filter. Play's UGC
  policy asks for "robust, effective and ongoing" moderation *including* in-app reporting and blocking; it does not
  ask for screening before publication.
- **The consent gate is fork-specific.** `dm.one_key` exists only in meshcore-keymind and defaults off
  (`MESH_ENABLE_ONE_KEY_DM 0`, `MyMesh.h:124`); its hold queue is 15 entries and consumes offline queue capacity
  (`MyMesh.h:1162`, `:1495`). An app that needs consent-on-first-contact cannot assume it.
- **A blocked key's messages are hidden and discarded**, decided 2026-11-04. The app deletes its own rows and drops
  arrivals; the radio's copy is untouched. Unblocking restores nothing, and the copy says so. Blocked nodes are
  counted ("3 hidden"), excluded from coverage results, and still counted as reception evidence.

### 9.9 What the XR client already solved — copy it, do not rebuild it

David's client (`meshmore-xr/`, ~75 Kotlin files) speaks the **same companion protocol over BLE** and is further
along than its own header admits: P0, P1 and S1 HORIZON are done and verified on the glasses. "Frozen" in the scope
of record is a *scope* decision, not a code state. These are its solved problems, in the order they save work:

1. **Staged commit for radio settings.** Four LoRa parameters as one transaction; the previous set is written to
   disk **before** the command goes out; REVERT is **single-use**; a dead-man timer was **rejected** because "hearing
   nothing proves nothing on a mesh that is regularly quiet". That is W3's design, already argued.
2. **Identity discipline.** A full key always wins; a name match *pins* the key so it resolves once; a key-suffix
   match with no name match is **refused and logged** — "four hex characters are not an identity". A live incident
   had a stranger named `7182` whose key ended in `d563` treated as the operator's own hardware across 350 contacts.
   This is the rule N4's block store must obey.
3. **The telemetry permission byte.** Bits 0–1 battery, 2–3 location, 4–5 environment, three levels each, unit-tested
   because a mis-shift grants a permission nobody intended.
4. **Notification salience and density.** AMBIENT / DIRECTIONAL / INTERRUPT, with INTERRUPT reserved for safety and
   not user-assignable to a chat channel; density capped 4/s, 6 voices, −18 dB floor after 20 s. "A notification is
   not a card, it is a **direction**."
5. **"No information by position alone" and "no information by sound alone"**, each with a list equivalent — and an
   angular floor with CJK tiers (Latin 1.2°, kana 1.5°, kanji 1.8°) plus "the floor cuts both ways: oversized is as
   much a defect". A test asserts the budget in both directions.
6. **Map honesty rules.** One continuous TABLE→FLOOR→GLOBE ladder, never a modal switch; FLOOR bearing-locked to
   true north so walking is panning; **vertical exaggeration mandatory and labelled**; node stalk length = altitude
   uncertainty so an unfixed node visibly floats; an honest edge-of-data boundary instead of a fade to blank.
7. **A pin model** (`lobospeak-mappins-spec.md` §1): id, degE7 lat/lon, alt, label, kind, tags, source, createdAt,
   createdByPubKey, and **no TTL field** — which independently confirms TTL is genuinely new.
8. **Privacy-policy structure** — "we collect nothing" plus "two things that do leave and are not ours": system
   dictation and the radio. Declares no `INTERNET` permission; `BLUETOOTH_SCAN neverForLocation`.
9. **Contact GC exclusion order** — own nodes, favourites (both kinds), anything without a usable position
   ("unknown is not far"), then distance.
10. **Autopen's constraints** — proposes and never sends, marked as generated at compose *and* confirm, clipped to
    the frame's word budget, degrades to absence, and four false positives found only by replaying real traffic.

**Do not copy:** the nine-theme system (a different substrate), the ASL layer, the holographic rack idiom,
server-backed audio profiles, "audio on during pre-login", the one-byte-path conclusion (it is true of that config;
the firmware encodes hash size in `path_len >> 6`), and "the SNS map is not offline" — stale, R61 shipped the
offline stack.

**Conflicts, one now resolved:** the "no accounts, no cloud" policy governs **MeshMore only** — the XR client is
David's product with its own policy — so MeshMore's privacy declarations describe MeshMore and inherit none of the
XR server dependencies. Remaining calls: the XR design's server-backed audio
profile, cloud STT/TTS and private temp-URL proxy; "no lobospeak in MeshMore" against the XR client rendering
lobospeak pins and geofences natively; "seven skins" against "the six SNS themes cannot be ported"; "no AI work"
against the shipped Autopen. Two factual corrections applied to his brief: `CMD_SET_ADVERT_LATLON` is **14 = 0x0E**,
not `0x0C`, and the offline-map claim above.

### 9.10 The deliverables of this pass are documents, not code — and the next phase is the defect list

Recorded 2026-11-04 because the appetite question is easy to misread. **No implementation starts in this pass.**
The output is the document set: the plan, the scope of record, the block spec and the research notes. The app stays
at its current build.

When implementation does start, the order in §9.6 stands and its first item is the four defects in §9.1 — the
protocol version negotiation, the discarded radio-profile field, the decoder's missing full-consumption check, and
the BLE MTU read-back. Those four are hours of work and one is a default argument; they precede every feature
because two of them make features *appear* to work while doing nothing.

What "keep specifying" and "finish the defect list" differ in, stated plainly: the first changes documents, the
second changes the app. This pass does the first, and leaves the second ready to begin with no further decisions
outstanding except the ones listed in §9.7.

### 9.11 Consolidation: one register, one authority order, and what still needs raising to spec depth

Applied 2026-11-04, after a session-history audit found that the owner asked for "our list of features" three times
and no list existed.

- **`meshmore-feature-register.md` is now the entry point.** Every feature with a state (`BUILT`, `SPECIFIED`,
  `OPEN`, `BLOCKED`, `AGAINST`, `DROPPED`), the authority order between documents, and **one merged open-questions
  register** replacing the three lists that used to disagree (scope §9, §5 here, §9.7 here).
- **Depth is now even across the four features chosen for this phase.** The block spec carries a data model, a
  state machine, copy and ten tests; and as of 2026-11-04 so do SOS/check-in, places and telemetry/coverage
  (`meshmore-sos-spec.md`, `meshmore-places-spec.md`, `meshmore-telemetry-coverage-spec.md`). Every other row
  stays at one line and is raised when work starts on it. The difference matters: these four were raised because
  writing them *changed* decisions — the SOS arithmetic in D8.4 did not close, the place id's time bucket
  contradicted renewal, and the ACK attribution rule could not be honoured on a channel. A row that survives
  being written down without changing anything did not need the depth.
- **Authority order, stated once:** scope of record > this plan (§9 over §8 over §2/§4) > block spec > feature audit
  > original spec > research notes. "Shipped" needs the audit; "decided" needs the scope of record.
- **Two requirements were stale and are now corrected:** the original spec's R2 claimed iOS (the owner deprioritised
  it), and the privacy claim "nothing leaves the device" was falsified by map tile and pack fetches. The privacy
  policy and the data-safety declaration now name the two things that leave: the radio and map fetches.
- **Firmware OTA is now a workstream row**, with its trap recorded: an OTA session drains the offline queue down to
  `OTA_RETAINED_OFFLINE_FRAMES` and notifies per consumed frame (`MyMesh.cpp:607-611`). The corpus note that said a
  phone cannot do this (`sound-link-and-lora-ota.md:95`) is corrected — protocol v14 gives `0x4A`/`0x4B`.

### 9.12 Round 8: decisions taken by investigation, so the register stops growing

Recorded in full in `meshmore-scope-of-record.md` §11. The short version, with the evidence that produced each:

- **Broadcast media scoping is configuration, not protocol.** Unscoped floods are allowed by default
  (`flood_max_unscoped = 64`, `flood_channel_data_enabled = 1`); the gate only fires when the wildcard denies flood
  or a channel-scope rule requires a region. So the app shows the radio's default scope and keeps DMs and known
  channels as the media default. This replaces "the top open question" in §9.2.
- **Channel text truncates silently at 160 bytes, not 176.** `MAX_TEXT_LEN` is 10 × cipher block, and the firmware
  shortens rather than rejects, including the `sender: ` prefix in the budget. A composer counting 176 over-runs by 16.
- **Place id excludes time**, because renewal must keep the id while changing the timestamp; the type rides as a
  trailing token before the TTL.
- **SOS: 12 sends at 60 s, 10 beacons at 5 min, hard stop at 1 h, explicit cancel.** Check-in is one bounded send with a deadline. Made exact in `meshmore-sos-spec.md`; the original "12 minutes plus a 60-minute beacon" did not add up and D8.4 was amended.
- **Map privacy resolves by default:** the bundled basemap needs no network, so "nothing leaves the device" is true
  until the user opts into online packs; the consent screen names the source and the disclosure.
- **Backup is excluded from Auto Backup** — Keystore keys cannot be exported, so ciphertext restore is unreadable —
  and replaced by a user-passphrase encrypted export.
- **The fun angle is parked, not cut** — treasure hunts, map weather and ghost-trail replay stay in the design space
  with no milestone slot, so nothing is promised and nothing is lost.
- **Identity replacement, multi-radio, directions handoff, `dm.one_key` exposure, cross-device block sync, mentions,
  channel key rotation, retention, place rate limit, coverage pacing, OTA scope, notification behaviour on a locked
  screen and permission-denial fallbacks** each got a stated default with its reversal cost. The codec-complete
  commands split: flood scope, auto-add, route display, contact share, allowed frequencies, reboot, device PIN and a
  repeater session screen get UI; key export, factory reset, signing and anon request stay on the radio.

What remains needs measurement, not a decision: AV1 encode cost on low-end hardware, `meshbench` determinism under an
external driver, bulk-transfer reliability, and collision behaviour at load.

### 9.12a Round 9: five more decisions, four of them from firmware nobody had read

The four design rows the specs left open turned out to be answerable from source, and one search changed the picture
rather than closing a gap.

- **The `#emergency` channel's key is derived from its name, not merely hardcoded.** keymind's constant
  (`MyMesh.cpp:387-390`) is exactly `SHA-256("#emergency")[0:16]` (`e1ad578d25108e344808f30dfdaaf926`), wadamesh-tak
  derives the same bytes from the name (`resolveAliasKey`, `MediaMeshCore.h:880`), and the app already computes them
  through `channelPskFromHashtag` (`packages/meshcore/lib/src/crypto/channel_crypto.dart:68`), whose documented
  `#test` vector reproduces. Two forks agreeing on the key makes it a convention rather than one fork's choice.
  Joining one seeds a notice, and a received zero-path flood on it is held and re-sent once after two minutes plus
  jitter — a firmware-side repeat nobody in this document set had found, which changes what SOS can honestly claim
  about app death (D8.23). Because the key is computable from the name, the channel is public by construction, and
  the app offers a one-tap add rather than creating it silently.
- **The device-side alert engine is receive-side only and reaches the app through `0x42`.** So an outgoing SOS cannot
  make its own radio buzz, but a responder's radio can buzz without a phone — through a narrow whitelist, never raw
  CLI, and without the `remote` permission that lets a contact reconfigure the radio over a DM (D8.24).
- **Place confirmations get a text convention** with the same attribution rule as the SOS ACK (D8.25).
- **Request ordering is the app's job** because the firmware has no priority, and the mechanism is one live request
  plus eight remembered guards, not "one pending request" (D8.26). Self telemetry does not contend at all, which the
  telemetry spec had wrong.

The three measurements are now protocols with device classes, repeat counts and pass/fail thresholds rather than a
standing "needs measurement" (§9.14). They still have not been run — the difference is that the next person can run
them without inventing the method.

### 9.13 From proto-spec to normative spec — what writing it exposed

Writing `meshmore-app-spec.md` against the code rather than against the plan changed four things, and each is the
kind of error a document set makes when it describes itself instead of the software.

- **The transport interface is not in the app.** It is `abstract interface class MeshcoreTransport` in
  `packages/meshcore/lib/src/transport/transport.dart:19`, and the app's BLE layer implements it. An earlier
  read reported a `lib/meshcore/transport.dart` that does not exist — a plausible path, not a real one.
- **Chat history is plaintext.** `mm.chat.v1` is JSON in `shared_preferences`, cap 250 (`chat_store.dart:18-21`),
  while the milestone row promised "history is encrypted and exportable". That is now APP-E1 with a `(build)`
  marker rather than an assumed property.
- **Accessibility was absent from every document.** `lib/screens` has **zero** `Semantics(` widgets; eight exist
  elsewhere in `lib/`. A messaging app whose whole value is delivery status cannot ship without announcing that
  status. Now APP-K1–K3.
- **The place type set was a placeholder in the scope of record.** The spec closes it to nine tokens with an
  unknown-token fallback (APP-G6), which is what "carries type" should have meant all along.

**Two more findings from writing against the code, not the plan.**

- **The gateway is a whole subsystem the register barely mentioned.** `lib/meshcore/gateway/` was 776 lines
  across four files wrapping a third package, `package:meshcore_gateway`, and the architecture document is 1,126
  lines about the two-app pair. The register's 94 rows carried **one** gateway mention. A subsystem with its own
  security model — bearer token, one client at a time, no companion commands to clients — had no state rows. It
  gained section 6a and requirement group M, and then both were withdrawn on 2026-11-05 (D10.1) when the client
  stopped needing it.
- **The backup exclusion exists and excludes the wrong things for chat.** `res/xml/backup_rules.xml` and
  `data_extraction_rules.xml` (wired at `AndroidManifest.xml:51-52`) exclude `maps/` and the secure-store
  ciphertext. They do not exclude `mm.chat.v1`, so **plaintext message history is currently backed up to the cloud**.
  That is worse than "backup exclusion is unbuilt": the mechanism is there and pointed at the wrong data.

**And the send path's terminal states were weaker than the plan implied.** `_Expect.sent` is registered at
`meshcore_controller.dart:1873` and failed only on a thrown exception at `:1882-1885`; there is no timer between.
So "a delivered message never reads failed" needs a correlation id and a timeout that do not exist yet. APP-C1–C4.

### 9.14 The three measurements, as protocols rather than promises

Three numbers in the specification are best-practice defaults because nobody measured them. "Needs measurement" is
not a plan, so each gets a protocol with a device class, an instrument, a repeat count and a pass/fail threshold. None
of them can run without hardware or a GPU path, which is exactly why they are written down now: the person who runs
them should not have to invent the methodology.

**M1 — AV1 encode cost on low-end hardware.** Gates the image tiers in the media spec.

- **Device class:** a 2021-or-later lower-mid Android, 4 GB RAM, Cortex-A55/A53-class cores — not a flagship. One
  device is enough for a threshold; three make it a claim.
- **Instrument:** a monotonic clock around the native encode call, not around the Dart future, plus peak RSS sampled
  before and after. Report the encoder's own library version.
- **Cells:** 1024×768 and 640×480, at each quality tier the app ships, with JPEG at matched visual quality as the
  control. 20 encodes per cell, discard the first as warm-up, report median and p95 — **p95 is the number that
  matters**, because a user feels the slow one.
- **Pass:** median encode ≤ one third of the image's transfer time at the shipped pacing, so encoding never dominates
  the wait; p95 RSS delta ≤ 64 MB on the 4 GB device.
- **Fail action:** drop a quality tier or cap the long edge. Both are reversible and neither changes the wire format.

**M2 — `meshbench serve` determinism under an external driver.** Gates every timeout and retry number.

- **Fixed:** seed, topology, node count, and a scripted client that sends N chunked transfers at fixed offsets.
- **Run A:** same seed, same script, twice. **Pass:** per-packet delivery logs are byte-identical.
- **Run B:** same seed, driver timings jittered by ±1 s. **Pass:** results *differ* — proving determinism is
  seed-plus-driver-order and not seed alone. If B is identical to A, the harness is ignoring the driver's timing and
  no conclusion about load behaviour is valid.
- **Cost:** wall time divided by simulated time at 1, 5 and 20 nodes; and `-junit` on versus off for the per-packet
  assertion overhead. Report the multiplier so a CI budget can be set rather than guessed.

**M3 — bulk-transfer reliability and collision at load.** Gates the 350 ms pacing and the FEC ratio.

- **Reliability:** 3 repeaters, one 20-fragment image at the shipped pacing, 20 runs. **Pass:** at least 19 of 20
  runs complete, with a mean of ≤3 fragments needing repair. One failure in twenty is a pacing problem to fix; two
  is a claim the spec cannot make.
- **Collision at load:** 10 concurrent senders on one channel, then measure delivery of a single one-packet text.
  **Pass:** ≥80 % of those texts arrive. This is the "can I still talk" test, and it matters more than image
  throughput — an image that takes a minute is a nuisance, a text that never arrives is a failure.
- **Fail action:** raise pacing, shrink the fragment, or publish a concurrency cap. All three are settings, not
  protocol changes.

**What none of these measure:** the two-profile cost (MeshBench has no two-profile support at all), and how media
behaves on a *real* radio with a real antenna. The radio2 measurements already in `radio2-measured.md` cover the first
from hardware; the second needs a field test and is not a simulation question.

### 9.15 Breadth: the concerns no feature owns

A feature-by-feature review says the set is complete. A breadth review asks what every feature silently depends on, and
that is where the real gap was. Eight cross-cutting requirements were missing and are now group N in the app spec:
schema versioning and migration (the plaintext-to-encrypted move had a milestone and no procedure), one error catalogue
(so no raw `ERR_CODE_*` reaches a user), one time model (phone clock, radio clock, message timestamp — three clocks
that were being mixed), four degraded modes with defined copy, an export container format rather than "a button", two
performance budgets, an interop matrix, and the Android 13 notification-permission flow.

The review also found six inconsistencies, all corrected: the `#emergency` key described as a hardcoded constant when
it is derived from the name; the SOS schedule that ended at 72 minutes; the place id carrying a time bucket that
contradicted renewal; self telemetry said to contend for the request slot; two requirements using a label style that
broke every mechanical count; and a live defect where `emergency` and `#emergency` derive different channel keys.

`meshmore-spec-breadth-review.md` holds the checklist and the deliberate exclusions. The pattern worth keeping: every
one of the six came from a document asserting something the code did not say.

