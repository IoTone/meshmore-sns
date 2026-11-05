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
| `0x1B` inbound channel-datagram decode | BUILT | Frame decoded and tested, **no consumer** in the dispatch |
| Channel tag → key normalization | **DEFECT** | APP-A8: `channelPskFromHashtag` hashes the string as typed, so `emergency` and `#emergency` derive different keys, and only the prefixed form matches the ecosystem convention. The weak-tag check on the same screen strips `#` while the derivation does not (`channels_screen.dart:345-352` vs `:378`) |
| `0x42 CMD_RUN_CLI_COMMAND` | TODO | Dual-purpose: CLI when `len >= 2`, FEM-gain GET when `len == 1`. Product call whether to surface |
| `0x19 CMD_SEND_RAW_DATA` / `0x41` raw packet | BUILT in `mesh_carry.dart`, gateway-only | Lift into the app send path |
| `0x91` one-key DM rejected | TODO | 1 + 32 bytes, keymind only; without it a refused stranger's message vanishes |
| `0x4A`/`0x4B` firmware OTA control | TODO | A phone can drive a companion's own OTA; needs a row, a screen and the queue-drain handling |
| Golden vectors | BUILT twice | Same `m1`–`m5` + `interop/SCHEMA.md` in the Dart package and `libmeshcore`. Open: ownership and which is the reference |
| Capability negotiation | TODO | Probe commands, never compare version strings; convention in the app-name tail |
| Path-hash width from `path_len` | BUILT | Width in bits 7–6, hops 5–0 |

## 2. Messenger

| Feature | State | Ruling or document |
| --- | --- | --- |
| Channel and DM send/receive | BUILT | Channel text confirms with `OK`, DM with `SENT` |
| Delivery state per message | BUILT, four rules owed | Never from a sync timeout; never for channel sends; DMs only from `RESP_CODE_SENT`; 30 s grace |
| OS notification for an inbound message | SPECIFIED | D8.20: one channel per message class, high importance so it shows on the lock screen, a dedicated SOS channel, no full-screen intents, DND respected |
| Per-channel notification bundle | TODO | Audio, haptic, OS, TTS, **mentions-only**. D8.13: a mention is the display name as a whole word or `@name`; key-suffix matching is opt-in |
| Composer byte budget | SPECIFIED | D8.3: count **160 bytes for channel text including the `sender: ` prefix** (`MAX_TEXT_LEN`); the firmware truncates silently, so the UI must count the prefix. Other frames: 162 datagram blob, 176 BLE frame, 177 queue slot |
| Encrypted storage + migration | TODO | Plaintext `SharedPreferences` today |
| History threads, export, truncation visibility | TODO | 250-message cap truncates silently |
| Backup, restore, Auto Backup rules | SPECIFIED | D8.8: exclude everything from cloud backup and device transfer — Keystore keys are non-exportable, so ciphertext restore is unreadable — and ship an encrypted export with a user passphrase |
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
| Staged commit + single-use revert | SPECIFIED | Four params as one transaction; previous set to disk first; no dead-man timer |
| BLE MTU check | TODO | Read at connect; **refuse below 179** |
| Capability refusal wording | TODO | The app must explain what the firmware cannot do |
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
| Geofences with hysteresis | SPECIFIED | ±5 % margin, once per continuous stay |
| Inter-node relationship | SPECIFIED | "A is 400 m from B and closing" |
| SOS | SPECIFIED — full spec | D8.4 timings made exact (12 sends at 0–660 s, 10 beacons at 720–3420 s, hard stop 3600 s); a channel ACK is "claimed" and does **not** stop the alarm, only a direct ACK from a target key does; `meshmore-sos-spec.md` §7, §9 |
| Check-in | SPECIFIED — full spec | D8.5: one send, `[CHK:<id6>]`, deadline watched locally; `meshmore-sos-spec.md` §3, §5 |
| Coverage ping | SPECIFIED — full spec | D8.17 pacing plus the cell model: geohash 6, time weights 1.0/0.8/0.5/0.2, contradiction demotion to 0.1, observed-only edges, session-only storage; `meshmore-telemetry-coverage-spec.md` §6–§9 |
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

## 6a. The gateway coupling

| Feature | State | Ruling or document |
| --- | --- | --- |
| L2 loopback server for the paired app | BUILT in part | `lib/meshcore/gateway/gateway_service.dart` (776 lines) wraps `package:meshcore_gateway`; L2 draft v0 in `meshmore-sns-architecture.md` §5.5 |
| BLE link ownership is exclusive | SPECIFIED | The app owns the radio; clients tunnel records and get no companion commands (`architecture.md` §2.4) |
| Pairing token in secure storage | BUILT | `secure_pairing_persistence.dart`; excluded from backup with the Keystore-wrapped key |
| Grants and revocation | TODO | Settings → Connected apps; revocable without a restart (`architecture.md` §7) |
| One client at a time, busy close | SPECIFIED | `CLOSE(busy)` on a second authenticated attempt; 5 s timeout on an unauthenticated one |
| Gateway airtime metering | BUILT in part | Operator policy, both ends meter themselves (`gateway_service.dart:88`) |

## 7. Store and shell

| Feature | State | Ruling or document |
| --- | --- | --- |
| Target API 36 | OPEN, deadline 31 Aug 2026 | Mandatory for updates, no stagger |
| 16 KB pages | OPEN, deadline 1 Feb 2027 | Check RELRO end-padding, not only `zipalign` |
| `connectedDevice` foreground service | BUILT | `FOREGROUND_SERVICE_CONNECTED_DEVICE` + `BLUETOOTH_CONNECT` |
| In-app pair flow + declaration video | TODO | The video must show pairing inside the app, not system settings |
| Companion Device Manager | TODO | Platform recommendation for this exact case |
| Export compliance | TODO | Blocks every track; three triggers |
| Privacy policy and data safety | SPECIFIED in part | D8.18: default build leaves the device only via the radio; packs opt-in and disclosed. Wording still to write |
| Issues link instead of crash reporting | TODO | R10 unbuilt |
| Radio-free demo mode | SPECIFIED | D8.21: every permission denial has a working fallback; the offline path is a first-class first-run choice, not an error. Needed for store review too |
| Seven skins correctness audit | TODO | Every feature in all seven |
| Type scale + colour ratchet | TODO | >250 `fontSize:` literals, 26 colour literals, 19 `Colors.*` |
| Accessibility floors (angular, CJK tiers) | SPECIFIED | Latin 1.2°, kana 1.5°, kanji 1.8°; asserted both directions |

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
