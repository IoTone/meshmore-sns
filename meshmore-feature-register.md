# MeshMore feature register — one list, one state, one owner ruling

Written 2026-11-04 as the entry point to the document set. Features were previously spread across the master plan's
W1–W12 rows, the §8 delta, the §9.6 order, the scope of record's §5 and §6, and R1–R108 in the original spec. This
page is the list; the other documents hold the reasoning.

## How to read the set, and which document wins

| Order | Document | Authority |
| --- | --- | --- |
| 1 | `meshmore-scope-of-record.md` | **Decisions.** If a ruling is here, it wins over everything below |
| 2 | `meshmore-master-plan.md` | **Plan and evidence.** §9 supersedes §8, which supersedes §2 and §4 for anything they both cover |
| 3 | `meshmore-app-spec.md` | **Normative requirements.** APP-A…APP-N, 66 requirements, a check per row. Where it and the scope disagree, the scope wins |
| 4 | `meshmore-sns-block-spec.md`, `meshmore-sos-spec.md`, `meshmore-places-spec.md`, `meshmore-telemetry-coverage-spec.md` | **Feature specs at implementation depth.** The block spec is the depth template; the other three follow its shape |
| 4a | `meshmore-spec-breadth-review.md` | **Breadth.** What a complete specification needs beyond the feature list, what was missing, and what is deliberately out |
| 5 | `meshmore-feature-audit.md` | **What exists.** Measured against source; a "SHIPPED" here beats a plan row's assumption |
| 6 | `meshmore-sns-spec.md` | **History.** R1–R108 plus the change record. Not authoritative where 1–4 disagree, and it still carries stale requirements (see R2) |
| 7 | `mesh-research/notes/topics/` | **Field evidence.** 53 notes; `INDEX.md` is the map |

Two rules that were being violated: a claim of "shipped" needs the audit, and a claim of "decided" needs the scope of
record. Nothing else counts as either.

**One carve-out:** for *build order* the master plan's §9.6 governs, not this table's authority order — §9.6 was
written against the measured dependencies and supersedes the four earlier orderings (M1–M7, §6 of the scope, §6 of
`meshmore-feature-plan.md`, and its own §8 delta).

## State vocabulary

`BUILT` verified in code · `SPECIFIED` decided and written, not built · `TODO` decided and unbuilt, no design work
left · `OPEN` a decision or a design is owed · `BLOCKED` depends on something unbuilt · `AGAINST` decided not to
build · `DROPPED` withdrawn after being planned. "Not built" and "not decided" are different states; conflating them
is how a register stops being trusted.

## 1. Protocol and transport

The state column answers one question: can work start? `TODO` means yes, the design exists.

| Feature | State | Ruling or document |
| --- | --- | --- |
| `0x3E CMD_SEND_CHANNEL_DATA` encoder | TODO — **unblocked** | The single highest-leverage missing line; gates every channel media format. Unblocked by D8.22: any first blob byte is safe, the type comes from the `0xFFxx` dev band |
| `0x1B` inbound channel-datagram decode | BUILT | Frame decoded and tested; the profile byte is now `RxVia` (R112) and Diagnostics reads it out (channel, radio, data type). The datagram itself still has no application consumer — that is W3 |
| Channel tag → key normalization | BUILT | R110: `MeshcoreChannelCrypto.canonicalHashtag` trims and `#`-prefixes before the hash and the PSK derivation, the weak-tag warning reads the same canonical string, and a bare tag saves the canonical name to the slot. Case stays case-sensitive because the firmware hashes literal bytes. Slots written before the fix keep their old key and are not the public `#name` channel — recorded, not migrated, because the tag was never stored. Tests: both typed forms equal the `#test` KAT |
| `0x42 CMD_RUN_CLI_COMMAND` | BUILT (whitelist only) | `cli_command.dart`: a closed set of typed commands (buzzer, vibration) with named refusals for shell syntax, `remote`, unmodelled commands and bad arguments. No raw text path, no screen yet — D8.24's `notify.<selector>` rule still needs its grammar read from firmware |
| `0x19 CMD_SEND_RAW_DATA` raw send | BUILT | `lib/meshcore/mesh_sender.dart` (send, OK/ERR outcome, per-contact record budget) over `MeshCarryCodec.sendRawData`; tests `test/meshcore/mesh_sender_test.dart` |
| `0x41` raw packet / `0x32` binary request | BUILT in the codec, no caller | `MeshCarryCodec.sendRawPacket` / `sendBinaryReq` encode and are vector-tested; nothing in the app calls them yet |
| `0x91` one-key DM rejected | BUILT (decode) | `OneKeyRejectedFrame`, 1 + 32 bytes (`MyMesh.cpp:2602-2611`); truncated and trailing-byte frames are named failures. No UI surface yet |
| `0x4A`/`0x4B` firmware OTA control | SPECIFIED — status only, gate built | Commands modelled and a named start refusal (`firmware_ota.dart`): an install consumes the offline queue to `OTA_RETAINED_OFFLINE_FRAMES` (`MyMesh.cpp:607-611`), which the app cannot yet re-sync. A screen remains |
| Golden vectors | BUILT twice | Same `m1`–`m6` + `interop/SCHEMA.md` in the Dart package and `libmeshcore`. Open: ownership and which is the reference |
| Conformance ceilings | BUILT | `packages/meshcore/test/conformance_test.dart`: 160 B channel text (refused at the encoder, `ChannelTextLimits`), 162 B datagram blob, 176 B frame (refused at `MeshcoreConnection.sendCommand`), 177 B queue slot as the bound text must stay under; each with a boundary test and the firmware line. Also the packed `path_len` matrix, the airtime arithmetic, and an encoder-inventory ratchet (three encoders still unexercised: `getAllowedRepeatFreq`, `getDefaultFloodScope`, `removeContact`) |
| Capability negotiation | BUILT (model) | `capability.dart`: per-radio, learned by reply, probe or `ERR_CODE_UNSUPPORTED_CMD`; unlearned is `unknown` and refused. A source-scan test forbids any version constant in the decision. Probes are not yet wired to a screen |
| Path-hash width from `path_len` | BUILT | Width in bits 7–6, hops 5–0 |

## 2. Messenger

| Feature | State | Ruling or document |
| --- | --- | --- |
| Channel and DM send/receive | BUILT | Channel text confirms with `OK`, DM with `SENT` |
| Delivery state per message | BUILT, four rules owed | Never from a sync timeout; never for channel sends; DMs only from `RESP_CODE_SENT`; 30 s grace |
| OS notification for an inbound message | SPECIFIED | D8.20: one channel per message class, high importance so it shows on the lock screen, a dedicated SOS channel, no full-screen intents, DND respected |
| Per-channel notification bundle | TODO | Audio, haptic, OS, TTS, **mentions-only**. D8.13: a mention is the display name as a whole word or `@name`; key-suffix matching is opt-in |
| Composer byte budget | SPECIFIED | D8.3: count **160 bytes for channel text including the `sender: ` prefix** (`MAX_TEXT_LEN`); the firmware truncates silently, so the UI must count the prefix. Other frames: 162 datagram blob, 176 BLE frame, 177 queue slot |
| Encrypted storage + migration | BUILT | `lib/meshcore/secure/encrypted_store.dart`: one sealed file (`MMS1`, format version, sealed payload) whose AES-256-GCM key the Android Keystore generates and does not export (`SecureStore.kt`, channel `meshmore/secure_store`); Dart never holds the key. `ChatStore` migrated off `mm.chat.v1` with a read-back comparison before the plaintext is removed, resumable and idempotent (`test/meshcore/chat_store_migration_test.dart`). Places, drafts and the block list move onto the same named-record store as those stores land |
| History threads, export, truncation visibility | TODO | 250-message cap truncates silently |
| Backup, restore, Auto Backup rules | BUILT in part | D8.8: both rule files exclude every domain (`root file database sharedpref external`) in cloud backup and device transfer, asserted by `test/store/store_declarations_test.dart`. Encrypted export exists (`lib/meshcore/secure/store_export.dart`: `MMEX` header carrying KDF id, iteration count and salt; PBKDF2-HMAC-SHA256 210 000 → AES-256-GCM; wrong passphrase and altered file both refuse). **Remaining: the Settings entry and share sheet that call it** |
| Retention and storage growth | TODO | No rule for places, media or trail |
| Message search | SPECIFIED — needs build | APP-E6: stored history only, no radio index, through the block filter with a hidden count, no plaintext index outside the encrypted store, bounded by retention, substring matching. Four checks written |
| Channel unread counts | TODO | Only DM unread is tracked |
| Quoting and forwarding | TODO | Reply/copy/delete exist |
| Drafts and composer state | SPECIFIED — needs build | APP-E7: per channel and per thread, encrypted with the history key, debounced, restored on a failed send, hidden-but-kept when the peer is blocked, never travels to another radio. Four checks written. Composer byte accounting is APP-D1/D2 |
| Blocking a key | SPECIFIED | `meshmore-sns-block-spec.md`; app-side store, delete and hide, counted nodes. D8.12: no cross-device sync — there is no radio-side record to share. D8.11: expose `dm.one_key` where the fork supports it, consent default |
| Report a message | SPECIFIED | Separate from blocking; a share-sheet bundle, because there is no server |
| Terms acceptance at first use | TODO | Store obligation |
| False "failed" on relaunch | TODO | See the four rules above |

## 3. Radio

| Feature | State | Ruling or document |
| --- | --- | --- |
| Two-profile radio2 control | TODO | Measured contract exists: 96–99 % primary vs 96–100 % secondary; the app must say what it costs |
| Staged commit + single-use revert | BUILT | Four parameters travel as one ordered transaction (`lib/meshcore/radio_config_transaction.dart`): the stranding tuple first, TX power second, path-hash size last, each step waiting for the reply that claims it. The previous operating point is written to disk before the first frame, keyed to the radio's own key (`radio_safety_store.dart`), and the undo consumes that record before rewriting, so a failed undo cannot arm a second rewrite of stale values. No dead-man timer: a timer that fires while the phone sleeps would strand the radio in the dark. Screen and copy in `device_config_screen.dart`; the predicted merge into `feat/app-completion` ran 1349 tests green (2026-11-05) |
| BLE MTU check | BUILT | R111: read at open (before subscribe), refused below **179** = `MAX_FRAME_SIZE` 176 + 3 bytes of notification overhead, and the refusal is typed with the negotiated number so the screen says it (`BleMtuTooSmall`, `MeshcoreBle.requiredMtu`). Not retried: the same radio negotiates the same value |
| Capability refusal wording | BUILT | The device screen names the step and the answer: refused (with the radio's error code), silent after five seconds, or not in this firmware build (`deviceRadioRefused/Silent/Unsupported`, EN+JA). The capability record learns from the same reply, so a command this build lacks is refused locally on the next attempt instead of being sent again (`packages/meshcore/lib/src/codec/capability.dart`) |
| Radio health readout | BUILT | `lib/ui/radio_health_block.dart` on Diagnostics: noise floor, last-packet RSSI/SNR, battery voltage and uptime, each line naming the frame it came from, and "not reported by this firmware" where the radio sends nothing rather than a zero. The read is local (no exclusive tool slot), so opening Diagnostics cannot steal the radio from a run in progress |
| Firmware OTA from the app | SPECIFIED | D8.19: status only this phase; no install start until the queue-drain handling exists, because OTA consumes the offline queue to `OTA_RETAINED_OFFLINE_FRAMES`. Full mOTA source flow (`0x4B`) deferred |
| Identity replacement | SPECIFIED | D8.7: a changed radio key is a new radio; offer one-tap carry-over of tags, favourites and blocks; history stays with the radio it came from |
| Multi-radio ownership | SPECIFIED | D8.9: one active session; switching is explicit; an in-flight send at switch time reads unknown, never failed |
| Codec-complete commands with no UI | SPECIFIED | D8.15: schedule flood scope, auto-add config, route display, contact share, allowed freqs, reboot, device PIN and a repeater session screen; refuse key export, factory reset, signing and anon request |
| `#emergency` channel as the SOS default | SPECIFIED | D8.23: the key is `SHA-256("#emergency")[0:16]`, so it is derivable from the name and public by construction — keymind hardcodes those bytes, wadamesh-tak derives them, and the app's existing tag-key source produces them. Joining seeds a "#EMERGENCY" notice; a received zero-path flood is re-sent once by the radio after ~2 min + jitter. Default SOS destination when present, copy states the key is public, never created silently |
| Device-side alert engine reachable from the app | SPECIFIED — whitelist only | D8.24: `set notify.<selector>` is reachable via `0x42`. Expose a **typed whitelist**, never raw CLI. Offer "buzz for #emergency". Do **not** expose `remote` (a contact could reconfigure the radio over a DM). "Buzz only for SOS" is not expressible — a channel rule fires on every message |
| Request-slot ordering (login/status/telemetry/discovery/binary) | SPECIFIED | D8.26: self telemetry answers synchronously and never contends; one live peer request plus 8 remembered guards; `Trace` does not take the slot. Background polling yields silently; user-initiated waits visibly; no silent pre-emption |

## 4. Places and maps

| Feature | State | Ruling or document |
| --- | --- | --- |
| Place text convention | SPECIFIED — full spec | `[PLACE]<lat>,<lon> <label> [<type>] [TTL:<duration>]`, one message, TTL anchored last; `meshmore-places-spec.md` §3 |
| Place object with TTL | SPECIFIED — full spec | Ten duration tokens 15 m–7 d, per-type default, expiry final, receiver clamps a future or stale timestamp; `meshmore-places-spec.md` §3, §8 |
| Place type and deterministic id | SPECIFIED — full spec | D8.2 plus the closed nine-token set (`hazard water fuel med rally view camp look other`); id `sha256(pubkey‖latE7‖lonE7‖type)` first 8 hex, no time, unkeyed when the source is channel text; `meshmore-places-spec.md` §4, §5 |
| Place renewal, confirmation, correction | SPECIFIED — confirmations now specified | Renewal is a re-broadcast with the same id and a new timestamp (`meshmore-places-spec.md` §6). `[CONFIRM:<id8>]` / `[REFUTE:<id8>]` per `meshmore-places-spec.md` §11 — key-bound from a DM, "claimed" from a channel, never extends the TTL, shares the 6-per-hour budget. **Correction remains open** |
| Photo on a place, fetched on demand | SPECIFIED | Text first, photo later; the photo does not extend the TTL |
| Directions handoff | SPECIFIED | D8.10: generic `geo:lat,lon?q=lat,lon(label)` first, then OsmAnd, Organic Maps, Google, Apple where installed; copy coordinates when there is no fix |
| Offline map stack (R61) | BUILT | Disk-first tiles, packs, tile budget, 50,000-tile cap, self-test |
| Map-pack sources and attribution | TODO | Fetch from a permitting source; emit an ODbL notice beside every pack |
| Map fetches and the privacy claim | SPECIFIED | D8.18: bundled basemap default (no network), online packs opt-in with a consent screen naming the source and the disclosure |
| Place-ledger export | SPECIFIED | After-action record, one row per place with final state; `meshmore-places-spec.md` §10 |

## 5. Field operations

| Feature | State | Ruling or document |
| --- | --- | --- |
| Position history | TODO | Only the current fix is plotted |
| Trail and GPX export | TODO | In memory only; export through the app's own transport |
| Geofences with hysteresis | SPECIFIED — engine built, screen owed | ±5 % margin, once per continuous stay. `lib/geofence/geofence_engine.dart`: enter at 95 % of the radius, leave at 105 %, sticky in between, so boundary chatter fires nothing; a sample with no fix changes nothing |
| Inter-node relationship | SPECIFIED | "A is 400 m from B and closing" |
| SOS | SPECIFIED — engine built, screen owed | D8.4 timings made exact (12 sends at 0–660 s, 10 beacons at 720–3420 s, hard stop 3600 s); a channel ACK is "claimed" and does **not** stop the alarm, only a direct ACK from a target key does; `meshmore-sos-spec.md` §7, §9. Built: `lib/sos/sos_schedule.dart` (22 packets, ±3 s jitter), `lib/sos/sos_engine.dart` (state machine, attribution, restore without replay), `lib/sos/sos_message.dart` (grammar, 160-byte refusal, NOFIX, salt) |
| Check-in | SPECIFIED — engine built, screen owed | D8.5: one send, `[CHK:<id6>]`, deadline watched locally; `meshmore-sos-spec.md` §3, §5. Built: `lib/sos/checkin.dart` (one send, overdue at the deadline, an answer after it does not un-pass it) |
| Coverage ping | SPECIFIED — engine built, screen owed | D8.17 pacing plus the cell model: geohash 6, time weights 1.0/0.8/0.5/0.2, contradiction demotion to 0.1, observed-only edges, session-only storage; `meshmore-telemetry-coverage-spec.md` §6–§9. Built: `lib/telemetry/{geohash,coverage_pacing,coverage_model}.dart` |
| Operational export | SPECIFIED | One bundle per time window |
| Fun angle: treasure hunts, map weather, ghost-trail replay | OPEN, parked | Kept in the design space, no milestone slot, not promised this phase. **Nine of eleven candidates cost zero airtime** (scope of record §7's cost table); the real blockers are position history and the `0x3E` encoder, not budget |

## 6. Media

| Feature | State | Ruling or document |
| --- | --- | --- |
| Channel images | SPECIFIED | AV1-class, `0x5643` (VE3 envelope), `0xAE1C` optional, never a third format |
| Recorded voice messages | SPECIFIED | Codec2 1200, 156-byte packets, ≤20 s, ≤20 packets, 250 kHz preset |
| Transport robustness | SPECIFIED | Salt every resend; marked packets; completion receipt; 350 ms pacing; FEC RS GF(256) block 20 |
| Media off by default on Public | SPECIFIED | Enforced at the send path |
| Broadcast media scoping | SPECIFIED | D8.1: inherit and show the radio's default flood scope; explicit unscoped send with a warning; DMs and known channels default for media. Unscoped floods are allowed by default (`flood_max_unscoped = 64`) |
| Live PTT | AGAINST this phase | Needs 250 kHz, fork firmware, unlawful in the EU |
| Bulk file transfer | AGAINST this phase | — |

## 6a. The gateway coupling — removed 2026-11-05

Decided: D10.1 in `meshmore-scope-of-record.md` §12. The consumer stopped existing, so the product carries no server.

| Feature | State | Ruling or document |
| --- | --- | --- |
| L2 loopback server for another app | AGAINST (2026-11-05) | D10.1. Server, sessions, grants, one-client rule and busy close all left with it |
| Pairing token in secure storage | DROPPED (2026-11-05) | No token exists to protect; `flutter_secure_storage` is no longer a dependency |
| Binder handoff and its signature permission | DROPPED (2026-11-05) | Service, permission and the Dart method channel removed from the manifest and `MainActivity` |
| Connected-apps screen and settings row | DROPPED (2026-11-05) | Screen, route and 20 EN/JA strings removed |
| Gateway airtime governor | DROPPED (2026-11-05) | It metered a client's records; there is no client. The app-side estimator and policy stay (`lib/meshcore/airtime.dart`) |
| Raw/binary send capability | BUILT | `lib/meshcore/mesh_sender.dart`; the codecs were never gateway code (`packages/meshcore/lib/src/codec/mesh_carry.dart`) |
| Airtime meter for the app's own sends | TODO | Was the gateway governor, so nothing meters now. Build on `estimatorFor` + `AirtimePolicy`; not scheduled in a wave yet |

## 7. Store and shell

| Feature | State | Ruling or document |
| --- | --- | --- |
| Target API 36 | **BUILT 2026-11-05** | Was already 36 through Flutter 3.47.4's defaults; now **pinned** in `android/app/build.gradle` so a toolchain change cannot move a Play obligation. Measured from the built APK: `aapt2 dump badging` → `targetSdkVersion:'36'`, `compileSdkVersion='36'` |
| 16 KB pages | **BUILT 2026-11-05** | `tool/check_16k.sh` checks all ten shipped `.so` files (every `PT_LOAD` ≥ 16 KB, `GNU_RELRO` ends at or before the next load once rounded up) and the archive (`zipalign -c -P 16`): all pass on the debug APK. No plugin ships a failing prebuilt library; re-run after any dependency bump. Table in `meshmore_sns_app/TOOLING.md` §3a |
| `connectedDevice` foreground service | BUILT, now regression-guarded | `FOREGROUND_SERVICE_CONNECTED_DEVICE` + `BLUETOOTH_CONNECT`; type `connectedDevice`, `exported=false`, notification states why it runs. `test/store/store_declarations_test.dart` fails if the declaration, the type or the copy drifts |
| In-app pair flow + declaration video | TODO | The video must show pairing inside the app, not system settings |
| Companion Device Manager | TODO | Platform recommendation for this exact case |
| Export compliance | TODO | Blocks every track; three triggers |
| Privacy policy and data safety | **BUILT 2026-11-05, data-safety form still owed** | `lib/screens/terms_screen.dart` states what the build actually does — nothing leaves the device except radio traffic, map packs the user turns on, and files the user exports; backup and device transfer are off for the app's own data. Acceptance is a first-use gate recorded with a version, so changed wording is read again before the app opens; Settings shows the same text read-only. The Play data-safety form is filled from this text and is a console step, not code |
| Issues link instead of crash reporting | TODO | R10 unbuilt |
| Diagnostics redaction (L1–L2) | **BUILT 2026-11-05, MTU/firmware lines pending** | `lib/screens/diagnostics_redaction.dart` masks by **field name**, because a 32-byte ciphertext and a 32-byte key are indistinguishable: a secret-named field keeps four bytes and its width, a coordinate coarsens to about a kilometre unless a caller asks otherwise, and the encrypted frames pass through untouched because they are the evidence. The interop fixture's `psk_hex` was the real leak — it was copied to the clipboard in full. Non-JSON masks instead of throwing. APP-L1's raw counts and the MTU line come from the D4 work; the firmware-version line is still to add |
| Radio-free demo mode | **BUILT 2026-11-05** | D8.21. `lib/app/demo_mode.dart` is read before the widget tree exists, because it decides whether launch reaches for a radio at all; the app bar carries a DEMO chip on every view, because an empty fabric with no radio and one with a dead radio look alike. Nothing is simulated — no invented peers, messages or signal levels. Leaving the mode reconnects a paired radio without a relaunch. First-run's offline path writes it; `test/app/demo_mode_test.dart` covers the read, the write and the chip |
| Seven skins correctness audit | TODO | Every feature in all seven. The places layer and the type ladder now prove their own seven-preset rendering; the audit across every feature is still open |
| Type scale + colour ratchet | BUILT 2026-11-05 | `MmType` size roles (10/11/12/13/16/20/24/34 over a per-skin `typeScale`) and `size(step)` for the off-ladder values; `MmSpace` ladder 1..9 = 2,4,6,8,12,16,20,24,32; `kRadiusXs/Sm/Md` replace the sub-6 px corner literals. `test/theme/mm_ratchet_test.dart` holds two **lower-only** baselines — 302 literal type sizes in 46 files, 32 colours in 11 — and forbids a bare `BorderRadius.circular` outside the token layer. Measured before this wave: 318 type sizes in 50 files and 42 colours in 12; the older "more than 250 / 26 / 19" was stale, and the shared widgets plus two pattern-setters are migrated, so the rest dwindle screen by screen |
| Accessibility floors (angular, CJK tiers) | **BUILT for the measurable half 2026-11-05** | `test/screens/a11y_floors_test.dart` pumps the six primary views and the thirteen Settings routes at **320 dp and 200 % text** and fails on a RenderFlex overflow; the harness is proved to bite (a 900 dp child in a 320 dp Row fails with "overflowed by 100 pixels"). It also pins the shell's two icon-only surfaces: every strip cell is a named, selected-aware button and the link chip names its state. The angular floors (Latin 1.2°, kana 1.5°, kanji 1.8°) are distance/target thresholds and are still unasserted. Icon-only controls **inside screens** are not yet labelled — that is the remaining half, and it is the W9 tail rather than a promise kept |

## 8. Out of scope, decided

No accounts, cloud, analytics or crash reporting **for MeshMore** (the XR client is David's product with its own
policy) · no payments · no role or team model · no repeater administration · no routing engine · no hosting of packs
· no live PTT · no bulk transfer · no new AI work · no lobospeak · no XR client work · no KISS/Meshtastic bridge · no
eighth image format · no firmware fork dependency · no device list. iOS is deprioritised.

## 9. The single open-questions register

The three lists that used to exist (scope §9, plan §5, plan §9.7) are merged here. Grouped by what the answer
changes, not by topic.

**Blocks a milestone**

1. ~~Broadcast media scope~~ **Decided D8.1** — inherit and show the radio's default flood scope; what remains is the warning copy.
2. ~~Place type token and deterministic-id derivation~~ **Decided D8.2 and closed in `meshmore-places-spec.md`** — trailing tokens, id without time, nine-token closed set. New sub-question surfaced by the spec: whether an **unkeyed** place (channel text, id derived from a name) is shown by default or only behind a per-channel "keyed only" filter. Shown and labelled for now; the filter is unbuilt.
3. ~~SOS copy, cancellation and ACK grammar; check-in~~ **Decided D8.4 and D8.5, made exact in `meshmore-sos-spec.md`** — 12 sends at 0–660 s, 10 beacons at 720–3420 s, hard stop 3600 s. The spec resolves the attribution problem the decision implied: a channel ACK carries only a display name, so it is shown as *claimed* and does **not** stop the alarm; only a direct-message ACK from a target key does. Remaining sub-question: whether the alarm should also drive the firmware's own device-side alert engine, which would survive app death but would let an on-air admin change an alarm. Not adopted.
4. ~~Which first blob byte avoids the management-page shape, and whether the app-data type must be registered.~~
   **Closed D8.22** — the question is malformed. `validPage` reads its magic from `payload[0..2]`, which for a
   normal datagram is the channel hash plus the 2-byte HMAC; the app's blob starts at `payload[6]`, past every
   byte checked. No blob byte can prevent the collision, the false-positive rate is about 2⁻⁹⁶ per datagram, and
   the failure is a silent drop of one datagram. **Encoder is unblocked: any first blob byte is safe.** Type
   value: unknown `data_type` is forwarded, not dropped (`BaseChatMesh.cpp:602-616`), so build on the `0xFFxx`
   dev band and request a numeric allocation in `0x0150–0xFEFF` before publishing. No ASCII mnemonic.

**Changes a guarantee**

5. ~~Does the map stay online-first, or ship packs~~ **Decided D8.18** — the bundled basemap is the default and
   needs no network; online packs are opt-in with a consent screen naming the source and what it discloses. The
   privacy claim is true by default and honest when packs are enabled.
6. ~~Identity replacement: follow the new radio key, or detach~~ **Decided D8.7** — a changed key is a new radio,
   with one-tap carry-over and history staying with the old radio.
7. ~~Backup and restore~~ **Decided D8.8** — exclude everything from Auto Backup; ship an encrypted export with a
   user passphrase, because Keystore keys cannot be exported.

**Changes a screen**

8. ~~Directions handoff targets~~ **Decided D8.10** — generic `geo:` first, then the four map apps where installed.
9. ~~Block: `dm.one_key` exposure and cross-device sync~~ **Decided D8.11 and D8.12** — expose where the fork
   supports it with consent as the default; no cross-device sync.
10. ~~Which of the 21 orphan commands get UI~~ **Decided D8.15** — nine scheduled, twelve refused.

**Changes a number**

11. ~~Place report rate limit per node per hour~~ **Decided D8.16** — 6 per hour, burst 2 in 5 minutes.
12. ~~AV1 encode timing and peak memory on a low-end device.~~ **Protocol written** (plan §9.14 M1): lower-mid
    2021-class device, monotonic clock around the native call, 20 encodes per cell, median and p95, pass = median
    ≤ ⅓ of transfer time and p95 RSS ≤ 64 MB. **Not yet run** — no device in this pass.
13. ~~`meshbench serve` determinism under an external driver, and the wall-time cost of a per-packet assertion.~~
    **Protocol written** (plan §9.14 M2): same seed twice must be byte-identical; a jittered driver must *change* the
    result or the harness is ignoring timing; report the simulated-time multiplier and the `-junit` overhead.
    **Not yet run** — needs a GPU path this box cannot exercise.
14. ~~Coverage ping on a busy mesh~~ **Decided D8.17 and specified in `meshmore-telemetry-coverage-spec.md`** — app-side pacing of 1 per 30 s and 1 per geohash-6 cell per hour, jittered; no firmware-side reply cap was found in the code read. The spec also fixes the cell model (time weights, contradiction demotion to 0.1, observed-only edges) and decides **session-only** storage, because persisting positions is a privacy commitment the data-safety declaration has to carry.

**Raised by the full specs, and now decided by investigation (round 9)**

- ~~Telemetry request ordering~~ **Decided D8.26** — corrected first: self telemetry answers synchronously and never
  contends for the slot; only a peer request does, and `Trace` has its own guard path. Background polling yields
  silently, a user-initiated request waits visibly, and nothing is pre-empted without the user seeing it.
- ~~Place confirmation wire grammar~~ **Decided D8.25** — `[CONFIRM:<id8>]` / `[REFUTE:<id8>]`, key-bound from a DM and
  "claimed" from a channel, one count per key per id, never extends the TTL, shares the 6-per-hour budget.
- ~~Whether SOS drives the alert engine~~ **Decided D8.23 and D8.24** — the engine is receive-side only, so an outgoing
  SOS cannot make its own radio buzz; and the `#emergency` channel's key is derivable from its name (two forks agree)
  with a two-minute client-side repeat hold, which makes it the right default destination and a partial answer to app death.

**Genuinely open, and worth naming**

- ~~Whether the app should create the `#emergency` channel itself~~ **Decided D8.23** — it offers a one-tap add and
  never creates silently. The key being derivable means creation leaks nothing, but a slot is consumed and a public
  channel appears in the user's list unasked.
- **Whether an unkeyed place gets a per-channel "keyed only" filter.** D8.25's companion decision shows unkeyed places
  by default and says a block cannot filter them, because a block is keyed. The filter is the honest middle ground and
  is not built.
- **Whether a key-bound refutation should shorten the TTL for everyone.** Deliberately not: it would let three
  colluding names clear a real hazard.

**Research, not decisions**

15. ~~Bulk-transfer reliability; collision behaviour at load~~ **Protocol written** (plan §9.14 M3): 19 of 20 runs
    complete with ≤3 repairs, and ≥80 % of one-packet texts still arrive with 10 concurrent senders. **Not yet run.**
    Remaining research: ITM/DEM never exercised; 40 of the 52 firmware forks unread; 13 telemetry sites unqueried.

---

*This register is the list. If a feature is missing here, it is missing from the plan — say so rather than starting a
new document.*
