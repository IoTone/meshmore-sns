# Audit of the MeshMore × LDMUX × lobospeak architecture of record

Audit performed 2026-10-24 against `meshmore-sns-architecture.md` (HEAD `c9f8dd1`),
`meshmore-sns-meshcore-interop.md`, `ldmux/docs/MESH-TRANSPORT.md`,
`ldmux/docs/adr/0020-mesh-link-security.md`, and the MeshCore firmware at
`/home/ldeen/Documents/meshcore-fw-alerts` (`companion-v1.17.1` @ `d929643`).

Read this alongside `meshmore-sns-architecture.md`. Where the two differ, this
document is the evidence and the architecture document is the corrected text.

## Method

- Every budget in §5.2 and §5.5 re-derived from the firmware and from ADR-0020
  §3, not trusted from the prose.
- Every L2 frame type attacked for implementation feasibility against what the
  firmware can actually report.
- Every factual claim in the architecture and interop docs traced to a
  file:line or left flagged as unsupported.
- Rejected options re-checked for factual errors (none found).
- ldmux's own mesh design read in full and compared clause by clause with the
  architecture document.

Severity: **blocker** (the design does not work as written), **major** (works
but is wrong in a way that will be painful to unwind), **minor** (inaccuracy or
unnecessary coupling), **nit** (cosmetic).

## Blockers and majors, first

| # | Sev | Where | Finding |
|---|---|---|---|
| A1 | **blocker** | architecture §5.3 | The "self-delimiting is guaranteed by the 16 B tag" argument is false. Binary payloads are AES-ECB encrypted and zero-padded to 16 B, and the decryptor **does not strip** the padding. A 143 B record becomes 147 + 13 zero bytes, and the receiver cannot tell where the record ends. The claimed non-zero-tail guarantee fails 1/256 of the time (a tag ending in `0x00`), so a strip-trailing-zeros decoder corrupts ~0.4 % of packets. |
| A2 | **blocker** | architecture §5.3 vs ADR-0020 §3 and §5 | Gateway ARQ contradicts ADR-0020. ADR-0020: "the record layer never retransmits" and "a retransmission is a *new* record with a new counter; duplicates are removed by the application sequence number (ARQ), not by resending ciphertext." A blind gateway retransmitting identical ciphertext re-uses the counter, and the receiver's 64-record replay window rejects it as a duplicate. Gateway-side retransmission is only possible by decrypting. |
| B1 | **blocker** | architecture §5.5, `0x32 ACK` | An ACK with status `delivered` / `dup` is unimplementable for a blind carrier. `PAYLOAD_TYPE_RAW_CUSTOM` has no delivery acknowledgement, and the binary response is an application reply, not a transport ACK. The gateway can report only what the firmware told it: `RESP_CODE_SENT` route flag, `est_timeout`, or an `ERR_CODE_*`. |
| E1 | **blocker** | architecture §1.6, §9 P6 | On iOS a suspended app cannot serve a loopback listener: the process is frozen, `ServerSocket.accept()` does not run, and a connecting LDMUX times out. `bluetooth-central` wakes the app for BLE events only (~10 s), which cannot serve an interactive terminal client. The two-app gateway works on Android (the foreground service keeps the process alive) and does not work on iOS as designed. |
| D1 | **major (security)** | architecture §5.5 pairing token | The token's natural home is `SharedPreferences`, which this app already uses. Both Android backup rule files exclude only `maps/`, so shared prefs are cloud-backed by Auto Backup and restorable onto a different device. That is a token leak the security model does not cover. |
| B2 | **major** | architecture §5.5, `BIND` | `BIND` assumes the host is already a MeshCore contact: `CMD_SEND_BINARY_REQ` looks the pubkey up and returns `ERR_CODE_NOT_FOUND` otherwise. Adding a contact is a privileged companion write that §2.4 says the gateway must never perform. Nobody is assigned this step. |
| A3 | **major (arithmetic)** | architecture §5.2 | 143 B is not reachable as a *record* length without padding: `4 + 143 = 147`, padded to 160. For a padding-free record the length must satisfy `(4 + L) mod 16 == 0`, so L = 140 (116 B application). The doc's "143 B (119 B application)" is right for the frame and wrong for the wire. |
| A4 | **major** | architecture §5.2 | Three caps stack: 176 (companion frame) → 143 app; 168 (sendRequest guard) → 163 app; 167 (createDatagram) → 163 app. The interop doc has all three; the architecture doc drops the middle two and never says 143 binds only because the frame is smallest. Sound, but undocumented. |
| A5 | **major (missing option)** | architecture §5.2 | "The phone is companion-constrained to 143 B" holds only for the binary-request path. `CMD_SEND_RAW_PACKET` (65) injects a whole serialised packet and `createRawData` applies no cipher and no padding, giving the phone an exact-length raw-custom path at ~172 B. That removes A1 entirely and makes both directions symmetric. Cost: MeshMore must build the MeshCore packet header and path itself. Never evaluated. |
| G1 | **major (contradiction)** | architecture §2.3 vs interop §4.1 | Architecture: "the L3 protocol is already shared … the gateway just carries those frames." Interop: a binary gateway protocol is required. Both cannot hold: L3 control frames are **JSON** and `MAX_FRAME_PAYLOAD` is 16 MiB, so L3 cannot cross a 143 B link unchanged. |
| G2 | **major (discovery)** | architecture §5.3 | The real discovery mechanism is better than documented. A flooded `PAYLOAD_TYPE_REQ` makes the responder build a `PATH + RESPONSE` return and **flood it back**, which also teaches the requester the return path. The first exchange is flooded both ways, not "flood out, direct back". |
| G3 | **major** | architecture §5.2 | Host→phone is modelled as a fixed 160 B, but a response reply also carries `path_len + path + extra_type`, so the reply budget shrinks with hop count. 160 is hop-independent only for raw custom. |
| C1 | **major** | architecture §5.5 governor | `est_timeout` is an *estimate* from `calcFloodTimeoutMillisFor` / `calcDirectTimeoutMillisFor`, not measured airtime, and a gateway cannot see repeater retransmissions or collisions. The governor meters an estimate presented as a law. With A2 there are also no gateway retransmissions left to count. |
| C2 | **major** | architecture §5.5 | Missing from L2 v0: backpressure (a client can push `RECORD` far faster than one `pending_req` drains; the 64-record buffer is not a protocol), a pre-auth connection limit and timeout (a local app can hold the single slot forever and permanently deny the legitimate client), constant-time token comparison, and a statement of *which* sequence `RECV.seq` is. |
| B3 | **major** | architecture §5.5 capability bit 2 | `ml-kem-ack` means "gateway/host offers the ML-KEM stage", but a blind gateway cannot know or attest the host's capabilities. The bits belong end-to-end inside the session, not in L2. |
| H1 | **major (phasing)** | architecture §9 | P2 (KMP client) depends on P1, which freezes the contract, but P3 (mesh carry) is the phase that will force contract changes (delimitation, ARQ, reply-size shrinking). Freezing L2 before the transport shape is known is the wrong order. |

## Minors and nits

| # | Sev | Where | Finding |
|---|---|---|---|
| B4 | minor | architecture §2/§5.5 | The port is stated three ways: "a free port", "fixed 41731", "port from a QR". Pick one. |
| B5 | minor | architecture §5.5 table | `0x11 HELLO_OK` is labelled `gw→gw`; should be `gw→client`. |
| B6 | minor | architecture §5.5 framing | No magic, no version in the header, and `PAIR` (fixed 16-byte payload) precedes `HELLO`, so a v2 framing change cannot be detected before v2 bytes are parsed as v1. |
| B7 | minor | architecture §5.5 | L2 `PING`/`PONG` duplicates L3's own, and a carrier that already has TCP keepalive plus `STATUS` does not need its own heartbeat. |
| B8 | minor | architecture §5.5 | u16 length is big-endian while the whole MeshCore ecosystem uses little-endian. Not wrong, but a second convention in one codebase. |
| A6 | minor (doc) | interop `PUSH_CODE_RAW_DATA` | `[0x84][snr*4][rssi][0xFF][payload]` reads as a 7-byte header with a 4-byte SNR. It is a 4-byte header: opcode, `(int8_t)(snr*4)`, `(int8_t)rssi`, `0xFF`. Receive cap is therefore **172**, not 169. |
| J1 | minor (doc) | interop §loopback vs architecture §1.5 | The interop text still says loopback needs `ACCESS_LOCAL_NETWORK` attention; the architecture doc has the corrected analysis. Stale. The question is also currently moot: `targetSdkVersion` is `flutter.targetSdkVersion`, i.e. 36 today. |
| J2 | minor (doc) | architecture §10 | Titled "Open questions" but item 1 is headed "investigated … resolved" while others are open. Split into Resolved / Open. |
| J3 | minor (doc) | architecture §9 | Titled "in scope per the scope cut" but contains `DEFERRED` and `OPTIONAL` rows. |
| N1 | nit | interop fix #5 | The binary-response push carries no sender pubkey, so "verify the responder pubkey at app level" is impossible from that frame. Only the end-to-end layer can authenticate the responder. |
| N2 | nit | architecture §5.3 | `pending_req = 0` is the idle sentinel and the tag is firmware-generated, so a tag of 0 would be unmatchable (~2⁻³²). The queue design must treat "no response" as expected, not impossible. |
| P0 | note | — | A `PUSH_CODE_BINARY_RESPONSE` value of `0x85` is wrong: `0x85` is `PUSH_CODE_LOGIN_SUCCESS`. The real value is **`0x8C`**. |

## Corrected arithmetic

### Phone → host, binary request (as specified)

| Step | Bytes | Source |
|---|---|---|
| Companion frame | 176 | `src/helpers/BaseSerialInterface.h:5` |
| − opcode − pubkey | 176 − 33 = **143** app data | `MyMesh.cpp:1678-1684` |
| `sendRequest` guard | app ≤ 163 | `src/helpers/BaseChatMesh.cpp:633` |
| `createDatagram` guard | 4 + app + 2 + 15 ≤ 184 → app ≤ **163** | `src/Mesh.cpp:487-489` |
| Encrypt + pad | `ceil((4 + app) / 16) * 16` | `src/Utils.cpp:85-113` |
| Record overhead | 24 | ADR-0020 §3 |
| **Application bytes at L = 143** | 143 − 24 = **119**, minus an ARQ header (≥ 4) → **≤ 115** | derived |

The padding hazard, concretely: app 143 → `4 + 143 = 147` → padded to **160** →
13 zero bytes appended, and `Utils::decrypt` returns the padded length without
stripping (`src/Utils.cpp:62-90`; the header comment at `src/Utils.h:41` says
"dest may contain trailing zero bytes in final block").

Two workable fixes:

- **Length-prefixed:** one byte inside the datagram, keeps L = 143, yields
  **118 B application**.
- **Block-aligned:** constrain L so that `(4 + L) mod 16 == 0`, i.e. L ∈
  {140, 124, …}, yields **116 B application** at L = 140.

The length prefix wins on both count and simplicity. Recorded as decision D2.

### Host → phone, raw custom (as specified) — sound

| Step | Bytes | Source |
|---|---|---|
| `createRawData` | exact copy, **no cipher, no padding** | `src/Mesh.cpp:589-603` |
| Packet payload ceiling | 184 | `src/MeshCore.h:20` |
| Phone receive push | 4 + payload | `MyMesh.cpp:807-810` |
| Guard | payload + 4 ≤ 177, then frame ≤ 176 → payload ≤ **172** | `MyMesh.cpp:802`, `MyMesh.h:236`, `ArduinoSerialInterface.cpp:25` |

160 is inside 172 by 12 B. **Sound.**

### Phone → host, raw custom (the option the doc never considered)

| Path | Frame | Payload ceiling |
|---|---|---|
| `CMD_SEND_RAW_DATA` (25) | `[25][path_len][path][payload]` | 174 − path_len, direct-only | 
| `CMD_SEND_RAW_PACKET` (65) | `[65][priority][packet]` | packet ≤ 174 |

Both bypass the cipher and the padding. `CMD_SEND_RAW_DATA` rejects flood
(`MyMesh.cpp:1533`); `CMD_SEND_RAW_PACKET` accepts any header but repeaters do
not forward `RAW_CUSTOM` (`src/Mesh.cpp:296`).

### Discovery arithmetic

A flooded REQ reply carries hash and MAC plus `path_len + path + extra_type`
inside the encrypted body (`src/helpers/BaseChatMesh.cpp:291-295`,
`src/Mesh.cpp:466-481`). The reply budget is therefore
`184 − 2 − 2 − pad − 1 − N − 1`, not a fixed 160.

## What the audit confirms is sound

Do not change these.

- The 143 B derivation for the companion frame.
- The 163 B over-the-air cap, verified through both guards.
- The 160 B host→phone figure, conservative against the 172 B receive cap.
- One outstanding `pending_req`, sends serialised.
- Raw custom has no MeshCore cipher and no padding, which is stronger than the
  doc claimed.
- `PAYLOAD_TYPE_MULTIPART` is ACK-only, not a fragmentation layer.
- Unknown binary request types are dropped by firmware.
- The Android loopback reasoning: `ACCESS_LOCAL_NETWORK` is API 37 and
  interface-scoped; `INTERNET` is already declared; `FOREGROUND_SERVICE_CONNECTED_DEVICE`
  and the `connectedDevice` service are already declared;
  `background_keepalive.dart` is process-liveness only.
- AccessorySetupKit needs no MFi credential, only Info.plist keys, and a
  mismatch is fatal by design.
- The rejected-options analysis (§3.1–3.7) has no factual errors.
- The four-layer ownership model and "shared contract, not shared code".

## Firmware findings outside the plan

- `MyMesh.cpp:740-746` copies `len - 4` bytes into `out_frame[6]` with no bounds
  check against `out_frame[177]` (`MyMesh.h:236`). A maximal response would
  write one byte past the member. Stock firmware cannot trigger it; a design
  that sends maximal binary responses can. Worth an upstream guard if a
  forwarding patch is ever filed.
- A flooded REQ reply simultaneously returns the answer and teaches the
  requester the return path, which makes discovery cheaper than the doc assumed.
- Binary request tags are generated by the firmware, not chosen by the client.
- The BLE peripheral advertises the generic Nordic-UART service UUID, shared by
  thousands of unrelated devices, and on nRF52 the name lives in the scan
  response. An AccessorySetupKit descriptor keyed on the service UUID alone
  will produce a very noisy picker.

## Decisions

### Taken on the audit evidence (2026-10-24)

- **D1 — delimitation.** A one-byte record length is carried inside the
  datagram on the binary-request path. 118 B application per record. Rejected
  the block-aligned alternative (116 B, more coupling, fewer bytes).
- **D2 — ARQ ownership.** L2 has no retransmission. The end-to-end session owns
  ARQ per ADR-0020. `0x32 ACK` is renamed `SEND_RESULT` and carries only what
  the firmware can report.
- **D3 — capability bits.** The `ml-kem*` bits are removed from L2. L2 keeps
  only bits describing what the *gateway* can do.
- **D4 — phasing.** P3 (mesh carry, delimitation, ARQ) moves before P2 (KMP
  client) so the contract is frozen against a known transport.
- **D5 — token storage.** The pairing token goes to platform secure storage,
  and shared prefs are excluded from Android backup regardless of where the
  token lands.
- **D6 — framing.** A version byte joins the frame header, and `HELLO` moves
  before `PAIR` so a version mismatch is reportable rather than fatal.

### Open — needs the user

1. **iOS (blocker E1).** A suspended iOS app cannot serve a loopback listener,
   so the two-app gateway does not work on iOS as designed. Options:
   (a) iOS supports the gateway only while MeshMore is foreground;
   (b) LDMUX owns the BLE radio on iOS, which §3.2 rejected;
   (c) iOS has no gateway and LDMUX reaches the host over the tailnet;
   (d) accept Android-first and demote P6.
2. **Contact provisioning (B2).** Options: (a) MeshMore gains an explicit
   "add host node as contact" step at bind time; (b) `BIND` is granted exactly
   one named, auditable companion write as an exception to §2.4; (c) the user
   adds the contact by hand out of band.
3. **Governor authority.** Confirm the governor enforces a labelled *estimate*
   rather than claiming measured airtime, and whether the owner may raise the
   budget from MeshMore's UI (outside L2).
4. **Unknown-frame policy.** Strict close is fail-closed but freezes the frame
   set; ignore-unknown is additive but fail-open. Strict is defensible while
   both sides ship together.

## Re-audit, 2026-10-28 (verified against firmware `companion-v1.17.1` @ d929643 and the live feed)

Nothing from the previous day was trusted. Mechanical and primary-source checks:

| # | Claim checked | Result | Evidence |
|---|---|---|---|
| R1 | "58/58 opcodes" | **True for commands.** All 58 `CMD_*` values, all 6 `ERR_CODE_*` values match `MyMesh.cpp` exactly | script compared every `#define CMD_/ERR_CODE_` against `constants.dart` |
| R2 | "the protocol surface is complete" | **False for inbound.** `PUSH_CODE_RAW_DATA 0x84`, `PUSH_CODE_PATH_UPDATED 0x81`, `PUSH_CODE_NEW_ADVERT 0x8A`, `RESP_CODE_CHANNEL_DATA_RECV 0x1B` had no constant and decoded as `UnsupportedFrame`. Raw data is the only way a Phase B record reaches the app. Fixed (commit `16a3a38`), 7 tests. An orphaned doc comment for `PUSH_CODE_CONTACTS_FULL` had no constant either | `MyMesh.cpp:404-410, 588-618, 801-818, 346-350` |
| R3 | "no companion path to `airtime_factor`" (radio-config §4, private-mesh table) | **False.** `CMD_SET_TUNING_PARAMS` writes `_prefs.airtime_factor = af/1000.0f`, `CMD_GET_TUNING_PARAMS` reads it. The earlier check looked only at `CMD_SET_CUSTOM_VAR`. Corrected in both docs | `MyMesh.cpp`, `grep -n CMD_SET_TUNING_PARAMS` |
| R4 | Governor estimate "conservative at 4 ms/byte" | **False off the USA preset.** 4 ms/B is right only for 62.5 kHz/SF7 (613 ms per 176 B = 3.48 ms/B, recomputed). EU/UK Narrow (62.5/SF8/CR8) is 1656 ms = 9.4 ms/B, EU/UK Deprecated 1673 ms, AU Mid 1000 ms. A gateway on those presets under-counts airtime by 2.4x. Added `AirtimeEstimator.lora` (exact AN1200.13 formula, preamble 32 for SF<=8 else 16 per `RadioLibWrappers.h:56`) | python recompute; `gateway_hardening_test.dart` |
| R5 | 613 ms, 3.48 ms/B, 58.7 records/h at 1 % | **Confirmed** (SF7/500 kHz 77 ms also confirmed) | same recompute |
| R6 | Governor "cannot be bypassed" | **False before the fix.** `session.dart` returned on `!_open` *before* charging, so a record transmitted while the client disconnected was never metered. Charge now precedes the open check | `gateway_hardening_test.dart` "airtime is charged even if the client left" |
| R7 | Bridge failures | A throwing `MeshSender` ended the socket with no frame (exception escaped to the read loop). Now `SEND_RESULT(errBusy)` for a send, `CLOSE(shutdown)` for the contact lookup. `errBusy` is the closest v1 outcome and is an ambiguity, recorded here | tests |
| R8 | Gateway session test "the governor refuses without touching the radio" | **Vacuous**: it paired against a different `PairingStore` and asserted only "not bound". Replaced by real tests that reach `bound` through a shared store | `gateway_hardening_test.dart` |
| R9 | Preset table "mirrored from the canonical table" | Source was a third-party client (see radio-config §7). Table now carries per-preset provenance and `pathHashSize`, 14 missing presets added, compared to a checked-in snapshot of the feed (26 entries) by a test | `region_presets_feed_test.dart` |
| R10 | Private-key export "enabled by default" | **Supported with a limit.** `platformio.ini:34-35` sets both in the shared base flags and the handler is `#if ENABLE_PRIVATE_KEY_EXPORT` (`MyMesh.cpp:1491`). Whether the user's flashed `HELTEC-BASE` binary has it on is **not verified** (verifying means exporting the key) | |

New facts that change the design:

- **Downlink raw data is never queued.** `onRawDataRecv` writes the frame only `if (_serial->isConnected())` and otherwise logs and drops (`MyMesh.cpp:811-816`). A Phase B record arriving while the phone's BLE link is down is lost, with no `MSG_WAITING` and no offline queue (contrast `onChannelDataRecv`, which calls `addToOfflineQueue`). The gateway cannot recover it. Session-layer retransmission is the only remedy, and it was the design already.
- **Pairing-slot denial of service.** Any local app can connect to `127.0.0.1:41731` and hold the single session slot for the 5 s pre-auth window, repeatedly. A legitimate client then gets `CLOSE(busy)`. The token blocks use, not denial. Not fixed (the one-client rule is a decision); mitigation would be to let an unauthenticated socket be displaced by a new connection. Open.
- **`PairingStore` generates a token in its constructor**, so `Gateway.pairingToken` read before `start()` shows a token that `load()` may then replace with the persisted one. Callers must read it after `start()`.

Not validated on hardware: every opcode layout added in the last two days (no radio could be driven: Flutter Linux builds fail on missing gstreamer headers, no ADB device). `0x3D` path hash, `CMD_SET_TUNING_PARAMS` and the new inbound frames are unit-tested against transcribed firmware layouts only.

**R11 (found late, 2026-10-28): "path hash mode must match across a mesh" was false for current firmware.** `path_hash_mode` is "which path mode to use when sending" (`examples/companion_radio/NodePrefs.h:40`); it is passed to `sendFlood(..., mode+1)` (`MyMesh.cpp:491-515`) and stamped into the packet. A forwarder compares and appends hashes using the **packet's** size (`src/Mesh.cpp:89` `isHashMatch(pkt->path, pkt->getPathHashSize())`, `:347-349`), so nodes on different modes interoperate. It had been stated in radio-config §2, the private-mesh investigation, ux-coverage, the app's l10n help/mismatch strings (en + ja) and a code comment, and it justified a "do not apply the hash for USA" test reason. All corrected. What remains true: it sets the originator's directed payload budget `174 - hops*size`. Whether *old firmware* that predates multi-byte hashes mis-parses larger sizes is unverified (no such firmware in the tree). The mismatch line in the UI now only says "not applied yet".

## P1 integration pass, 2026-10-28 (gateway wired into the app)

| # | Claim checked | Result | Evidence |
|---|---|---|---|
| R12 | "A Phase B send is answered by `RESP_CODE_SENT`; `est_timeout` is the deadline" (architecture §5.3, interop §Timers, `MeshSendResult` framing) | **False for `CMD_SEND_RAW_DATA`.** The handler replies `writeOKFrame()` or `writeErrFrame(...)`, never `RESP_CODE_SENT`. `decodeSendResult` is correct for `CMD_SEND_BINARY_REQ` only. The app adapter reads OK/ERR, and a no-answer deadline of 5 s is the sender's own. Docs corrected | `examples/companion_radio/MyMesh.cpp:1519-1534`; `mesh_sender_adapter_test.dart` |
| R13 | `Contact.activePath` "the hops actually in use" | **Wrong.** It used the raw `out_path_len` byte as a byte count. `0xFF` (no path) clamped to a bogus 64-byte chain and any hash size above 1 read the wrong span. Now decoded with `PathLen` (`hops * size`), `0xFF` is empty | `src/Packet.cpp:20-30`; `contact_path_test.dart` (6 tests) |
| R14 | `MeshNetwork.isolatedFromPublicMesh` | **Too narrow.** It compared frequency within 1 kHz, but a receiver decodes a carrier a fraction of the bandwidth off, so 910.526 MHz was called "isolated" from 910.525. Overlap now means within half the bandwidth (a judgement, generous on purpose, not checked against a datasheet) | `mesh_network_test.dart` "a frequency a hair off..." |
| R15 | `bindPeer` / capacity | A contact path longer than 14 bytes leaves under the 160 B floor (`174 - path_len`). The adapter refuses the bind with `BIND_ERR(no_path)` rather than advertise a size the radio would reject (brief said clamp to [160,172]; clamping up would advertise an impossible size) | `MeshCarryLimits.rawDataPayloadMax`; adapter tests |
| R16 | Raw-data OK would be credited to a chat message | **True before a marker was added.** The controller credits the oldest pending OK-expecting send, so a raw OK could confirm a channel message. `sendRawCommand` registers a marker | `mesh_sender_adapter_test.dart` "the OK for a raw send is not credited" |

Open ambiguities and limits (not resolved here):

- STATUS has no "unknown" value in v1. The adapter reports an unread battery as `0xFF` and an unheard RSSI as `-128`. Neither is in the contract.
- `errBusy` stands in for every ERR other than `not_found` (the closest v1 outcome).
- The firmware's OK/ERR carries no correlation tag, so an unrelated OK arriving while a raw send waits can be mistaken for its answer. Sends are serialised, which narrows but does not remove this.
- `ENABLE_PRIVATE_KEY_EXPORT` etc. unchanged: still unverified for the flashed binary.
- `flutter_secure_storage` with `encryptedSharedPreferences` keeps the encrypted token in `shared_prefs/`, which `res/xml/backup_rules.xml` does not exclude (it excludes only `maps/`). The ciphertext is bound to the device Keystore so a restore cannot read it (and the plugin resets on a decrypt error), but audit D5 asked for an explicit exclusion. That is a platform file and was not edited. Suggested lines: `<exclude domain="sharedpref" path="FlutterSecureStorage.xml"/>` in both `backup_rules.xml` and `data_extraction_rules.xml`.
- Hardware: nothing in this pass was run against a radio.


## Closing pass, 2026-10-28 (the three open items from the integration pass)

| # | Item | Resolution | Evidence |
|---|---|---|---|
| R17 | **Pairing-slot denial of service.** Any local socket could hold the single session slot for one pre-auth window after another, and a legitimate client got `CLOSE(busy)`. | **Fixed.** A connection that arrives while the active session is *unauthenticated* now evicts it and takes the slot. An authenticated session is still refused `busy` and never displaced. `_run`'s `identical(_active, session)` guard already stopped the evicted loop from clearing its replacement, so no new synchronisation was needed. Exposed as `hasAuthenticatedSession` for the Settings screen and for tests. | `server.dart` `_onSocket`; `gateway_service_test.dart` "an unauthenticated squatter is evicted" and "a paired connection is never evicted" |
| R18 | **`STATUS` had no "unknown" value**; the adapter invented `0xFF` and `-128`. | **Resolved as a contract fact, not a convention.** `GatewayLimits.unknownRssi = -128` and `GatewayLimits.unknownBattery = 0xFF` are now the documented sentinels, with the round-trip property stated in `status()` and `readStatus` (rssi is written and read as a signed byte, so -128 survives). The adapter references these constants instead of local literals. No wire change. | `constants.dart`; `messages.dart`; `mesh_sender_adapter.dart` |
| D5 | **Backup exclusion for the pairing token.** `backup_rules.xml` excluded only `maps/`. | **Fixed.** Both `backup_rules.xml` (Android 11-) and `data_extraction_rules.xml` (Android 12+, cloud-backup and device-transfer) now exclude the plugin's ciphertext (`FlutterSecureStorage.xml`) and its Keystore-wrapped key (`FlutterSecureKeyStorage.xml`). Excluded explicitly rather than relying on the wrapped key being un-restorable. | `flutter_secure_storage-9.2.4/.../FlutterSecureStorage.java:32` (`SHARED_PREFERENCES_NAME`) and `ciphers/StorageCipher18Implementation.java:19` (`FlutterSecureKeyStorage`); `android/app/src/main/res/xml/{backup_rules,data_extraction_rules}.xml` |

Still open, unchanged by this pass:

- The firmware's OK/ERR carries no correlation tag, so a stray OK can be mistaken for a raw send's answer. Serialising narrows it; only a tagged reply in firmware removes it.
- `errBusy` remains the stand-in for every ERR other than `not_found`.
- No hardware validation of any Phase B wire path (`0x19` answer handling, `0x3D`, `PUSH_CODE_RAW_DATA`) - unit-tested against transcribed firmware layouts only.
- Android loopback with the app backgrounded, and `ACCESS_LOCAL_NETWORK` on Android 16/17, untested (no device attached).
- The gateway lives only as long as the Flutter process, with the existing keepalive foreground service. Not a boot service.

## LDMUX client and session-claim audit, 2026-10-28

Leads were mined from the 46 MB pi thread (`--home-ldeen-Documents-lora--/2026-10-21T16-54-13-984Z_...jsonl`, 21 claim-shaped assistant lines about this project). Code and firmware are the authority.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| S1 | "Stock MeshCore cannot deliver a lobospeak request to the peer app: `onContactRequest()` handles exactly one type" | **Confirmed** | `examples/companion_radio/MyMesh.cpp:627-629` `if (data[0] == REQ_TYPE_GET_TELEMETRY_DATA)` |
| S2 | "Firmware only calls `notify()` when no companion is connected (`UITask.cpp:814`)" | **Contradicted.** `notify()` has no connection gate, and `:814` is the input-handling loop. The corrected radio-alerts doc is right | `UITask.cpp:622-640`; callers `:460,940,944,960` ungated |
| S3 | "SF11/62.5 kHz cannot complete one operation" (ldmux `MESH-GATEWAY.md` §6.1/6.3) | **Wrong for deployed radios.** The row is a proposal, not in the 26-entry feed. Fixed in ldmux commit `8f7687d` | USA/Canada 613 ms, about 10 ops/hour; EU/UK Narrow 1656 ms, about 3.6 ops/hour (formula recomputed, CR 4/8 uses cr index 4) |
| S4 | 613 ms, 3.48 ms/B, 58.7 records/hour, SF7/500 77 ms | **Confirmed** by recomputation | LoRa ToA formula, 176 B, preamble 32 symbols at SF8 and below |
| S5 | "`ldmux status` surfaces `mesh.status`/`mesh.enable`" (investigation doc line 403) | **No such command or RPC exists** | `crates/daemon/src/bin/ldmux.rs:159`, `daemon.rs:1664`; `grep -rni mesh crates/*/src` empty. Recorded in ldmux `MESH-GATEWAY.md` §11 |
| S6 | "Android `allowBackup` is false so the daemon token is not backed up" (`AppPrefs.android.kt` comment) | **Confirmed** | `AndroidManifest.xml:41` `android:allowBackup="false"` |
| S7 | "Path hash mode must match across nodes" | Already corrected as R11 | `NodePrefs.h:40`, `Mesh.cpp:89`. No remaining occurrence in `*.md`/`*.arb` |
| S8 | "Proven on the built binary: `strings firmware.elf` ... 0" (silent buzzer) | **Not re-checked**, needs a build | out of scope |
| S9 | "Gateway enforces the 8-record credit window" (ldmux §8 item 1) | **Not implemented by the reference server.** It advertises `statusPush` only | `session.dart` capabilities; noted in ldmux §11 |

Found while building the LDMUX client: `close()` during the handshake left `connect()` waiting out its whole timeout, because the handshake deferred was a local the teardown could not reach. Caught only by the real-socket test (the in-memory fake hid it). Fixed before commit.

Not done: the other ~1,240 pi sessions and the Claude history were not mined. Claims about hardware behaviour (BLE, Keystore, Android loopback with the app backgrounded) remain unverified.

## Resolutions and new findings, 2026-10-28 (hardware pass)

Append-only, as the earlier rows are. This section closes two and adds five.

### Closed

| Row | What was wrong | Now |
|---|---|---|
| J1 | interop §loopback told the reader `ACCESS_LOCAL_NETWORK` was mandatory from API 37 and the exemption "unverified", contradicting architecture §1.5 | Both interop passages now point at §1.5 and state the permission's own scope (broadcast-capable interfaces, which excludes loopback). What remains is a device check, not an unknown. |
| J2 | a section titled "Open questions" mixed resolved and open items | No such heading survives in the restored document; §10 is "Platform research: the iOS background model" and §11 is "Resolved decisions". Nothing to split. |

### New

| Row | Severity | Finding | Evidence |
|---|---|---|---|
| H1 | **blocker (wire)** | The serial framing had the two header bytes inverted. The firmware accepts `'<'` FROM the app and writes `'>'` TO it. Every unit test passed because the fake radio used the same inversion. | `ArduinoSerialInterface.cpp:31,46`; `SerialWifiInterface.cpp:143`; live: the first byte on a real port produced silence until fixed |
| H2 | **major (correctness)** | `out_path_len == 0` is a direct route with zero repeater hops, not "no path". The host bridge refused it, so a directly reachable neighbour could not be bound. | live: `BIND` answered `no_path` for a contact with `outPathLen 0`; fixed as `Contact.directPath` |
| H3 | major (safety bound) | The governor charged the payload length only. The radio also transmits a MeshCore packet header and path, so every charge was under-counted. | `session.dart` charge site; now `MeshSender.airtimeOverheadBytes` (2 + path), with a test that fails without it |
| H4 | minor (host portability) | `FileMode.writeOnlyAppend` cannot open a TTY (the VM seeks to end of file, the kernel answers `ESPIPE`), `flush()` maps to `fsync` which a TTY rejects with `EINVAL`, and two overlapping writes throw "An async operation is currently pending". | all three observed on `/dev/ttyACM0`; the port class now uses `writeOnly`, no flush, and a write queue |
| H5 | note (firmware) | One radio can register BLE and USB together (`MultiSerialInterface`), but `writeFrame` broadcasts to every enabled interface and there is no client identity, so two attached apps receive each other's replies. | `MultiSerialInterface.h:163-194`; the two-radio fleet is a correctness requirement, not a convenience |

### Measured, not inferred

- HELTEC-BASE, USB companion build: 910.525 MHz / 62.5 kHz / SF7 / CR5,
  `pathHashMode` 0, 350/350 contacts (1 direct, 349 flood), 4366 mV,
  225/3169 kB, 64-byte zero-hop raw frame answered `OK`.
- Airtime estimator for that preset: 612 ms for 176 B. The 613 ms figure the
  documents use is the same number rounded, not a second model.
- End to end, 2026-10-28: `ldmux mesh status` → `ready`, 172 B capacity,
  58 records left this hour, radio connected. The 58 is 36 s ÷ (612 ms + 2 B of
  framing overhead), which is the governor's own arithmetic.

## Separation-of-concerns audit, 2026-10-28 (two-sided)

Read-only inventory of both repositories, then classification of every capability
as radio/mesh-specific (MeshMore), terminal-specific (LDMUX), or generic client
infrastructure. The purpose was the standing question: **is anything being
carried by the wrong product?**

### Verdict

| Capability | Owner | Why (evidence) |
|---|---|---|
| Companion protocol, radio, presets, path hashes, contacts, channels | MeshMore | `packages/meshcore`; §13 matrix |
| Airtime policy and the 36 s/hour bound | MeshMore | `governor.dart:59-61` states that a client computing it would need radio parameters |
| Pairing-grant issuance and the token at rest on the host | MeshMore | it holds the radio, so it is the only party that can issue a mesh grant |
| The L2 tunnel, framing, single-session policy | MeshMore | `meshcore_gateway` (zero runtime deps, no `ldmux` in code) |
| Terminal semantics: PTY, keeper, VT, scrollback, predictive echo | LDMUX | `crates/{keeper,vt-sys,protocol}`, `docs/PREDICTIVE-ECHO.md` |
| Session ownership, claims, takeover, presence | LDMUX | `crates/daemon/src/ownership.rs`; keyed by a device identity that arrives in `hello` |
| Tailnet grant issuance and the client half of any pairing | LDMUX | `crates/protocol/src/pairing.rs`; works with MeshMore absent |
| The end-to-end session (Noise, record layout, ARQ) | LDMUX | ADR-0020; generic in principle, single consumer today |

Nothing that needs radio state lives in LDMUX, and nothing that needs terminal
state lives in MeshMore. The one exception was mechanical and is now removed:
`meshcore_gateway` exported `applicationBytesPerRecord = 148`, an ADR-0020
derivation, pinned by a MeshMore test. The carrier now exports only `recordMax`.

### Decisions taken

- **Two pairing ceremonies are correct, and must be documented as a decision.**
  A tailnet grant belongs to LDMUX because LDMUX must work with no MeshMore
  installed. A mesh grant must be issued by whoever owns the radio. Two grants
  are therefore structural, not an accident. The asymmetry is also visible in
  protection: the mesh token is in Android Keystore, while the daemon token
  (which grants shell control) is still in plain preferences. That is a defect on
  the LDMUX side, recorded there rather than here.
- **Client identity belongs in the session layer, not in L2.** The proposal was to
  add a device identity to the gateway contract so claims survive the mesh route.
  That would be the wrong layer: L2 is two independent hops, each terminated by a
  blind carrier (phone gateway, host gateway), so an identity placed there is
  seen by MeshMore and still does not reach the daemon that keys ownership. The
  identity belongs in the end-to-end session handshake, which LDMUX owns and
  which no other component can read. Consequence: the MeshMore contract does not
  change at all, and the gateway stays blind.
- **The session layer stays LDMUX-private.** Nothing in it may move into
  MeshMore, and it must not be factored for reuse until a second consumer exists.

## Session-history audit, 2026-10-28 (bounded)

Scope: the long `lora` pi thread (`~/.pi/agent/sessions/--home-ldeen-Documents-lora--/2026-10-21T16-54-13-984Z_01a15f62-82df-7406-82fc-01363057b9f4.jsonl`: 441 assistant messages) and the five Claude Code sessions for `ldmux` (`~/.claude/projects/-home-ldeen-Documents-ldmux`, 28 MB; the `lora` project directory has no sessions). Method: extract assistant text with `python3 -I`, search for correction-shaped language (`correction`, `was wrong`, `contradict`, `stale`, `turns out`, ...) and for specific claims about snow, payload sizes and implementation status, then compare against code or firmware. This is a keyword audit, not a read of every message: a false claim that was never corrected and never phrased like a correction is not found by it.

**Result.** 20 of the 441 lora-thread messages carry correction language. Every one was a correction made in that same thread, and each has a landing in a committed document already (the buzzer claims in `meshmore-sns-radio-alerts.md`, the six LoboSpeak payload/pubkey figures, the 125 kHz vs 62.5 kHz preset figure in architecture section 5.6, the truncated architecture file restored in `df698a5`, the ADR-0020 constants in the carrier). No correction was found that has no record. The five Claude sessions yielded no correction-shaped assistant message about mesh or ldmux.

**New findings (not previously recorded).**

| ID | Claim | Source | Evidence against | Fix |
|---|---|---|---|---|
| S1 | `snow` "audited" | An external research summary dispatched 2026-10-28 (flagged untrusted at the time) | `snow-0.10.0/README.md:13`: "This library has not received any formal audit." The Claude `ldmux` session (c05fb9db, message 510) and ADR-0020 section 7 say the same | ADR-0021 states the README line and notes the contradiction. **CORRECTION** to the research summary, which remains wrong |
| S2 | ADR-0020 section 3: raw/custom gives 184-byte packets and 160 application bytes | ADR-0020 `A. raw/custom \| 184 \| 160` | Raw send is `174 - path_len` in a 176-byte frame (`MyMesh.cpp:1515-1530`); carrier ceiling 172, 148 application bytes | Dated correction appended to ADR-0020, original table left visible |
| S3 | "Whether a failed open leaves the counter untouched is unverified" | ADR-0020 section 7 | `StatelessTransportState::read_message(&self, nonce, ...)` holds no counter | Answered in ADR-0020 update and ADR-0021 |
| S4 | SHA-256 chosen because snow's ring resolver lacks BLAKE2 | ADR-0020 section 2 | snow's default resolver offers SHA256 (`src/resolvers/default.rs`, `HashChoice::SHA256`); ring is not needed (`cargo tree` of `ldmux-session` has no `ring`) | ADR-0021; suite unchanged |

**Blind spots.** Messages that stated a wrong fact once and were never revisited. The other pi sessions (1,240 files) were not read. Tool results were not audited, only assistant prose.


## Phone-side session binding, 2026-10-28 (LDMUX)

Scope: how the phone runs the Rust L3 session, and whether wiring it moved any boundary.

### Checked, and what the check proves

| Claim | Command | Result |
|---|---|---|
| The gateway still knows nothing of the session | `rg -i 'noise\|arq\|ldmux' meshcore_gateway/lib` | only L2 "session slot" wording; no L3 term |
| No radio knowledge in the Rust L3 side, now including the FFI crate | `rg -i 'meshcore\|lora\|spreading' crates/daemon crates/keeper crates/session crates/session-ffi` | 0 hits |
| The phone's mesh package carries comments only | `rg -i 'bandwidth\|spreading\|pathHash\|preset' packages/mobile/.../mesh` | 3 hits, all comments (was 2: one more comment in `MeshSession.kt`) |

§13 changed in two cells only: the L3 row now names `crates/session-ffi`, and the mobile hit count
is 3.

### Findings

- **F1 (earlier claim contradicted): "the phone cannot run the session until a product decision is
  made".** ADR-0023 and `STATE.md` said the phone side was blocked on choosing between a Kotlin
  Noise, JNI over the Rust crate, or a different suite. The architecture had already decided
  (one implementation, no hand-rolled crypto, nothing duplicated), so the decision was JNI over
  the Rust crate and nothing was blocked. Corrected in place in ADR-0023 (dated update, original
  text kept) and `STATE.md`.
- **F2 (honesty): flipping `MESH_SESSION_BUILT` alone would have made the route say it works.**
  The session carries bytes for a shell number; the compact terminal encoding and the daemon's
  shell bridge do not exist. A route that resolved to "bound" over a link that cannot show a
  shell is the same dishonest state the old flag existed to prevent. So the flag was split:
  `MESH_SESSION_BUILT = true` (and checked against whether the library loaded on the device),
  `MESH_TERMINAL_BUILT = false`, giving a new problem `TerminalNotBuilt` that is reported before
  `NeedsToken`.
- **F3 (single choke point found, then used): every socket the app opens is built from
  `LdmuxConfig.endpoint`** (`LdmuxClient.kt` and `AttachClient.kt` both do `config.endpoint ?:
  return`). Gating the transport there is one line and covers both clients, instead of an `if` in
  each. A blocked mesh route therefore cannot fall back to the tailnet by any path.
- **F4 (ABI choice, recorded because it is easy to get wrong): double free is made harmless, not
  merely forbidden.** Free functions take a pointer to the caller's handle variable and null it,
  so a second free is a no-op and a use after free is `LDMUX_ERR_NULL`. The test
  `freeing_twice_is_a_no_op_and_a_nulled_handle_is_an_error_not_ub` pins it. This does not defend
  against a copied handle value held elsewhere; the Kotlin class owns its handle and zeroes it.

### Not verified

- The Android `.so` has been built and packaged (`assembleDebug` lists it for arm64-v8a and
  x86_64) and never executed on a phone. The JVM tests load the host build of the same C and Rust
  code, which proves the ABI and the binding, not the Android linker, the 16 KB page alignment
  flag, or the device's ABI.

## Terminal profile pass, 2026-10-28 (host side of the shell over the session)

Scope: ldmux ADR-0025, `crates/protocol/src/mesh_term.rs`, `crates/daemon/src/mesh_bridge.rs`,
the phone's session-key store. MeshMore code was not touched and `meshcore_gateway` /
`meshcore_host` still contain no `mesh_term` and no `ldmux` in code.

- **T1 (claim corrected): "the existing host already knows how to hash/compare rows for the
  client."** It does not. The daemon sends bytes and the keeper's `snapshot` text; a search of
  `crates/daemon` finds no per-row hash or changed-rows computation. The row diff is new
  (`Differ`, plain string equality against the last sent screen). The vocabulary reused is the
  real one: `snapshot`, `cols/rows`, cursor, `alternate_on`, "resync from a snapshot when output
  was lost".
- **T2 (figure restated, not changed): 8.5 KB an hour.** That was 58 x 148. The ARQ header takes
  4 bytes, so the stream carries **144** bytes a record, **8,352** bytes an hour in one direction
  (ADR-0025 table). A complete 200x100 screen is about 20,600 bytes, about 150 records: it cannot
  fit an hour and the profile says so instead of hiding it.
- **T3 (design choice, recorded because the brief left it open): no resize over mesh.** The
  keeper's geometry is canonical (ADR-0018). A phone that resized the pane would resize it for
  every other client, so `Profile` reports the host's geometry and marks resize unsupported.
- **T4 (flag not flipped, and why): `MESH_TERMINAL_BUILT` stays false.** The host half is built
  and tested over the real session. The phone has no port of the encoding and no attach driver,
  and no ceremony that delivers the keys, so no device can hold a mesh pairing. Flipping it
  would change which error is shown, not make anything work.
- **T5 (tests are not proof, checked):** the three integration tests passed on first run. The
  corruption test asserts both that no input reached a shell and that the session counted a
  drop; the budget test is deliberately loose (`<= 1` record on air for a budget of two with one
  spent on the handshake reply), so it proves "never past the budget", not an exact schedule.
- **T6 (numbering): ldmux ADR numbers 0021/0022 were taken** twice in the previous pass and were
  renumbered to 0023/0024 by the parent. This pass used 0025 and checked the directory first.

## Phone-side mesh terminal, key delivery and the attach path, 2026-10-28

Evidence is in the ldmux repository (`feat/meshmore-gateway`); nothing here changes a MeshMore
package. The §13 checks were re-run and still hold: `rg -i 'meshcore|lora|spreading' crates/daemon
crates/keeper crates/session crates/session-ffi crates/protocol` returns 0 hits (two hits this pass
introduced in new comments were reworded), and the mobile `bandwidth|spreading|pathHash|preset`
grep still returns the same 3 comment-only hits. The new phone UI strings say "send budget" in
records and never "airtime" or seconds.

### Findings

- **K1. ADR-0020 §6 promised a "version 2 of the link"; it was built as `v=1` plus optional
  parameters.** CLAIM (ADR-0020, QR additions): a `v=2` link. EVIDENCE: `Pairing.kt parsePairingLink`
  returns null unless `v` is `1` ("a link with a version the app does not know is refused rather than
  guessed at", `crates/protocol/src/pairing.rs` header), so a `v=2` code would have been refused by
  every installed app, including for the tailnet pairing it also carries. The v1 contract already says
  unknown parameters are ignored (the `future=ignored` case in `pairing-links.json`), so `mv=1&mk=&psk=`
  appended to the same `v=1` link gives an older scanner the tailnet pairing unchanged. Dated
  CORRECTION added to ADR-0020 with the original left visible. Also hex, not base64url.
- **K2. A mesh pairing still needs a tailnet host and token.** CLAIM (ADR-0020): "the tailnet host
  restriction in ADR-0017 does not apply to mesh pairing." EVIDENCE: the mesh keys ride on the same
  link, `pairing_problem` still requires a tailnet or loopback `host` and a 64-hex `token`, and
  `LdmuxConfig.isPaired` is defined on them. So a phone with **no tailnet at all** cannot be paired for
  mesh by this ceremony. Not fixed: it is a product question (does a mesh-only phone exist?) and the
  answer changes `isPaired`, which every screen reads. Recorded here as open.
- **K3. The host's radio key had no way to reach the phone.** The phone's gateway `BIND` needs it
  (`MeshGatewayClient(peerPubKey)`), the daemon does not own the radio and cannot learn it, and no
  earlier document named a source. Built: an optional `mr=` parameter, fed by the optional
  `LDMUX_MESH_SELF` environment variable. Without it `hasPeer` is false and the route reports
  `NeedsPeer`. This is operator-supplied, not discovered, and is the weakest link in the ceremony.
- **K4. "hasPeer" meant two things.** `MeshSessionKeyStore.hasPeer` (the phone holds session keys)
  and `resolveRoute(hasPeer)` (the host radio key to bind) shared a name. Split: `resolveRoute`
  gained `hasSessionKeys` and a `NeedsSessionKeys` problem, and `hasPeer` there now means only the
  radio key.
- **K5. The Kotlin port was pinned to the Rust vectors by a comment, not by a test.** CLAIM (ADR-0025
  Consequences): "checked against the same pinned byte vectors (`exact_bytes_are_pinned`)". EVIDENCE:
  that Rust test pins five messages inside Rust only; nothing the Kotlin side could read existed.
  Fixed with `crates/protocol/test/fixtures/mesh-term-vectors.json`, written by the Rust encoder and
  failing the Rust suite when stale; `MeshTermCodecTest` reads it. Swapping the byte order of the
  `u16` fields in the Kotlin encoder fails the suite.
- **K6. Flipping `MESH_TERMINAL_BUILT` makes `resolveRoute` honest, not the route usable.** There is
  no route picker, so nothing can save `route = Mesh`, and there is no scanner for MeshMore's gateway
  token (MeshMore's QR is the bare 32-hex token, `connected_apps_screen.dart:84-130`), so a saved
  mesh route would stop at `NeedsToken`. Both are in `docs/STATE.md`. The mesh screen has been
  compiled and exercised only through the driver tests and one run over the real Rust session in a
  JVM; the Compose screen itself and the Keystore are untested on a device.
- **K7. The shell selector is empty.** ADR-0025 left "which shell the phone attaches" undecided.
  The phone sends an empty selector, which the host answers with `Closed(AMBIGUOUS)` when more than
  one shell runs, and the screen says "more than one shell on the host".

### Verification this pass

`cargo test -p ldmux-protocol` 81, daemon `--lib mesh` 25, `--test mesh_terminal` 3, `--test
mesh_session` 4, `--test mesh_link` 4, session + ffi 49; clippy `-D warnings` clean on protocol,
daemon, session, session-ffi. `./gradlew --offline :composeApp:testDebugUnitTest --rerun-tasks`: 509
pass (441 before); `assembleDebug` succeeds. The 2 `qr::` tests that need `zbarimg` still fail in the
environment, unchanged.

## Reachability pass, 2026-10-29: the mesh route made reachable, and what that found

Scope: split the pairing, give MeshMore's code a structured payload, let the phone choose a shell, and add the entry points. Each finding names the claim, where it was made and the evidence.

| # | Earlier claim or state | Where | What the code showed | Resolution |
|---|---|---|---|---|
| R1 | "The tailnet restriction does not apply to mesh pairing." | ADR-0020 §6 | Every link carried `host` and the daemon's bearer token and a link without them was refused, so a phone that never reaches the tailnet was handed a credential that grants full shell control and cannot use it; and `LdmuxConfig.isPaired` (tailnet only) gated `meshScreenFor`, `routeProblem` and `initialLink` | `ldmux code\|pair --mesh-only`, a parser that takes neither-host-nor-token only with a full key set, and mesh checks that no longer read `isPaired`. ADR-0020 has a dated note, original kept |
| R2 | A mesh-route device with no daemon "reads as Unpaired" | `MeshRouteWiringTest` "the route is a choice beside the pairing..." | That assertion was the contradiction pinned as a requirement | Now `RouteUnavailable`, with a comment saying why |
| R3 | "Unpairing forgets the mesh keys" (so nothing is left behind) | `MeshEnrollment.onUnpaired`, ADR-0020 Revocation | It cleared the session keys and left the MeshMore **gateway token** in the Keystore | Clears both; `unpairing the machine also forgets the gateway token` |
| R4 | MeshMore's QR is "the pairing token" | `connected_apps_screen.dart` | A bare 32-hex token cannot say which port or version, and the phone had nowhere to put an endpoint | `GatewayPairingPayload` (`meshmore://gateway?v=1&host=127.0.0.1:<port>&token=...`), bare token still read, non-loopback refused |
| R5 | The brief asked the driver to "request the list on attach when the selector is empty" | task text | A list costs a round trip of minutes on a link that allows about 58 records an hour, and the host already attaches the one shell when there is exactly one | The driver attaches with an empty selector first and lists only on `Closed(AMBIGUOUS)`. Same user-visible result, fewer records. ADR-0025 states the deviation |
| R6 | "ADR-0025: selecting a shell ... not decided" | ADR-0025 "Not decided" | Decided here | Struck through in place with a pointer |

Evidence and limits.
- Rust: `cargo test -p ldmux-protocol` 87, daemon `--lib mesh` 27, `--lib pairing` 13 passing plus the one `qr::` test that needs `zbarimg` (environmental, unchanged). Kotlin: `./gradlew --offline :composeApp:testDebugUnitTest --rerun-tasks` 542, 0 failed; `:composeApp:assembleDebug` succeeds. Dart: `meshcore_gateway` 68, `meshcore` 291 (+1 skip), `meshcore_host` 30, app `flutter test` 1016.
- §13 re-run: `rg -i 'meshcore|lora|spreading' crates/daemon crates/keeper crates/session crates/session-ffi crates/protocol` 0 hits; the mobile `mesh` package still has only the 3 comment-only radio-word hits; `meshcore_host/lib` 0 `ldmux` hits; `meshcore_gateway/lib` has no `ldmux` import (new `pairing_payload.dart` names LDMUX in doc comments only, and says it carries no key material).
- **Not verified:** nothing here ran on a phone or a radio. The Keystore, the code scanner and the Compose Settings section were compiled and unit-tested through their pure parts only. The claim "the route works only while MeshMore is running on the same phone" is a consequence of the loopback listener and MeshMore's foreground service (`gateway_service.dart`), not something observed on a device.
- The two repositories pin the gateway-code vectors separately (`pairing_payload_test.dart`, `MeshReachabilityTest`). There is no shared fixture, so drift is possible and the test comments say so.

## Voice-path completion, 2026-10-29 (ldmux repository, evidence and corrections)

Scope: the phone's voice mode and the pi extension, in the ldmux repository. Nothing in MeshMore
or the mesh path changed. Kept here because this file is the audit trail of record for the pair.
The §13 matrix is unaffected: the voice code lives entirely in `packages/mobile/.../voice/`,
`crates/daemon` (the `speech` relay) and `packages/pi-voice-extension`, none of which names a
radio term (`rg -i 'meshcore|lora|spreading' crates/daemon crates/keeper crates/session crates/session-ffi crates/protocol` is unchanged).

| # | Earlier claim | Where | What the evidence says | Resolution |
|---|---|---|---|---|
| V1 | "One shared event type reaches `onSpeech` from both channels" (the voice fork's report, 2026-10-28) | `TerminalController.kt`, the report | True and misleading: `onSpeech` was a `var` that **nothing in the app set**, and no `VoiceDriver` was created anywhere. Speech was parsed and discarded. `rg -n "onSpeech\|VoiceDriver" composeApp/src/commonMain` found only the declarations. | `VoiceController` is bound to the shell on screen; `TerminalHandle.setSpeechListener` sets it on that shell only. Commit `52d62be` in ldmux. |
| V2 | "Loads in pi 1.1 without error output; the `/voice` round trip inside a real session was not observed" | `docs/VOICE-MODE.md` §15 | The doubt came from print mode, which shows nothing for a handled slash command. RPC mode surfaces both load errors and extension notifications. Observed on pi 1.4.0: a throwing control extension is reported; `/voice on` appends the entry; request 1 carries `VOICE MODE IS ON`, request 2 does not; exactly one `speech` RPC; setting survives `--continue`; inert outside ldmux; dead socket warns once. | Dated correction in §15, original line quoted. Harness kept as `packages/pi-voice-extension/test/live/live.sh`. Commit `fc07244`. |
| V3 | `VoiceMode` has a `LongSilence` event (the long-silence exit exists) | `VoiceMode.kt` | Nothing produced it. A listening microphone would have stayed open forever. | The machine now exits on `Tick` when `longSilenceMs` passes with no voice. |
| V4 | `VoiceMode`'s thinking timeout works | `VoiceMode.kt` `thinkingSince = 0L`, `now = 0L` | The first `Tick` (a clock value in the billions) minus a made-up 0 read as an expired timeout, and the same would have ended listening at once. Pinned by `the first tick is an anchor, not hours of silence`; stamping the timers with 0 fails 2 tests. | Timers are unset until the first tick. |
| V5 | The Android recogniser's "no speech"/"timed out" are failures | `Voice.android.kt` `onError` | Right for a one-shot button, wrong for a loop: each quiet window would have ended voice mode as `Failed`. Also `onResults` with blank text reported `Idle` and left a dead microphone. | `NoSpeech` state; the machine reopens the recogniser, bounded by `maxIdleRestarts`. The recogniser is released before the state is reported, because a reopen from inside the callback would otherwise be read as a toggle-off. |
| V6 | A cloud-only recogniser is acceptable if the banner says so | `VoiceState.ListeningCloud` | Fine for one dictation. Voice mode listens continuously, so it would stream everything said near the phone, with a banner as the only protection. | Refused by default (`VoicePolicy.allowCloud = false`); `Unavailable` plus a notice. |
| V7 | `package.json` of the extension cites ADR-0022 | `packages/pi-voice-extension/package.json` | ADR-0022 is "the terminal answers its own queries"; the voice ADR was renumbered to 0024 on 2026-10-28. | Fixed. |
| V8 | My code commit message `52d62be` says VoiceLoopTest 21 and VoiceControllerTest 15 | the commit message | The result files say 20 and 16 (47 in total either way). | Corrected in the docs commit; the commit itself is not amended. |

Evidence and limits.
- `./gradlew --offline :composeApp:testDebugUnitTest --rerun-tasks`: 589 pass, 0 fail (542 before); `:composeApp:assembleDebug` succeeds.
- Mutation checks: timers stamped with 0 fails 2 tests; never stopping the barge-in capture fails 2. A third mutation (parsing OSC with no listener) survived: skipping the scan is a cost saving, not an observable rule, and the test was renamed to say only what it proves.
- **Not verified:** nothing here ran on a phone. `AudioRecord` beside `SpeechRecognizer`, barge-in against the phone's own speaker, TTS audio focus and the Compose wiring are compiled and unit-tested through pure logic only. The pi harness uses a stub model that always complies with the prompt, so it proves the hooks, not model obedience.

## Hardware pass, 2026-10-29 (phone only, Android 16)

- **W1. The gateway could not bind its documented port.** `41731` is in the
  device's `ip_local_reserved_ports`, so `bind()` returns EPERM, not EADDRINUSE.
  The failure was invisible to every fake-transport test and fatal on the phone.
  Fixed by treating the port as a preference with an ephemeral fallback; the
  Connected apps payload already carried the real port.
- **W2. Two apps on one phone cannot pair by scanning.** MeshMore's code is shown
  on the same screen LDMUX would scan. A typed/pasted code path is required, not
  optional, and is now the only path that works for the daily case.
- **W3. Confirmed on-device, not just in tests:** loopback gateway on Android 16,
  L2 `HELLO`, token `PAIR`, and the `not_a_contact` refusal at `BIND` for a key
  that is not in the radio's table.
- **W4. Signature continuity.** The installed builds were signed with the debug
  keystore under `ANDROID_USER_HOME=~/.config/.android`; building with the default
  `~/.android` keystore produces an APK that `adb install -r` rejects. Any device
  build must set that variable, or the install destroys app data.

## Phone leg, 2026-10-29 (real Android 16 device)

Findings from running the mesh route on the phone, with one radio and no peer.

- **P1. A fixed gateway port is not safe on Android.** The phone's
  `/proc/sys/net/ipv4/ip_local_reserved_ports` contains `41731`, so
  `ServerSocket.bind` on it returned `EPERM` and the gateway could not start
  (`Could not start: SocketException ... Operation not permitted, errno = 1`).
  The default is now a preference with an ephemeral fallback, and the QR carries
  the real port. No fake-transport test could have found this.
- **P2. Same-phone pairing cannot be scanned.** MeshMore draws the QR and LDMUX
  holds the camera, on one screen. The scan-only ceremony was therefore
  impossible for the primary daily case. Both codes are now accepted as typed or
  pasted text, routed by scheme.
- **P3. The mesh screen ignored system insets** and drew its status line under
  the clock; its header row also squeezed the leave control to one character
  column. Fixed.
- **P4. Debug signatures differ by keystore.** The builds installed earlier were
  signed from `ANDROID_USER_HOME=~/.config/.android`; building from `~/.android`
  refuses to upgrade them. Preserving app data requires the former.
- **Proven on the device:** the loopback gateway runs and reports its port
  (`127.0.0.1:42989`), and the L2 exchange completes over the real stack —
  HELLO, PAIR ok, BIND refused `not_a_contact` for a key the radio does not know.
  Airtime stayed 0.0 s of 36 s, so a session that never binds transmits nothing.
- **Not proven:** a bound session, the terminal profile, and the over-the-air
  leg. They need a second companion radio or a real contact for the host key.

## Two-radio leg, 2026-10-29 (phone + Heltec V4 BLE + Seeed Wio L1 Pro USB)

Setup: phone radio `HELTEC-BASE` `615f431f…` on BLE; host radio `WIOld`
`26f6071f…` flashed to `WioTrackerL1_companion_radio_usb` and set to
910.525 MHz / 62.5 kHz / SF7 / CR5 / 22 dBm. Both heard each other directly:
the Seeed listed the Heltec with `pathLen 0`, and the Heltec listed `WIOld`
with SNR 11.0 / RSSI −12 after five forced flood adverts.

**Where the chain stops.** The desktop half bound cleanly (`state ready`,
capacity 172 B, budget 58 records) and the phone's gateway accepted HELLO and
PAIR, but BIND returned `not_a_contact`. Verified twice through `adb forward`
with a real `GatewayClient`, not by reading UI text. Cause: `bindPeer` consults
MeshMore's contact store (`meshcore_controller.dart:3477`), and a *heard* node is
not a contact. The Nodes sheet does offer `Add to device contacts`
(`meshcore_controller.dart:3497`), but on this radio that add did not take —
the node stayed out of the contact list and the sheet kept saying "Not a device
contact" while showing the contact-only telemetry controls. The most likely
reason is a full table (350/350 was measured on this radio earlier), but it is
**not proven**: the app never surfaced the radio's reply, so the ERR code is
unknown. Stated as hypothesis, not fact.

### Defects observed on the device, in order of seriousness

- **D1. A refused contact write is reported as success.** `addNodeAsDeviceContact`
  caches the contact optimistically (`:3528`) and `send` (`:858`) is a write, not
  an acknowledgement, so a firmware refusal looks like a success until a later
  sync silently reverts it. The gateway then refuses BIND for a node the user
  just "added".
- **D2. `Radio contacts` in the device sheet does not respond.** Four taps across
  three positions, sheet stays open, no navigation, no exception in logcat. The
  control is hit-testable in principle: in the same sheet, `Scan` toggled to
  `Stop` and `Disconnect`/`Forget` are tappable buttons, and `onTap` on that
  `ListTile` (`device_manager_sheet.dart:245-251`) is set. That screen is the only
  UI that can free contact-table slots (`device_contacts_screen.dart:168`), so
  the recovery path for a full table is unreachable from the product.
- **D3. The gateway stops serving when MeshMore is backgrounded.** LDMUX got
  `ConnectException` and `SocketTimeoutException` on the loopback while
  MeshMore's process was alive. `App settings` has "Stay connected in
  background", but its switch renders as off and its subtitle changes meaning
  between modes, so the actual state cannot be read from the control.
- **D4. The gateway switch disagrees with the server.** "Allow other apps on
  this phone" is drawn off while the same screen states `Listening on
  127.0.0.1:42989` — and it is listening.
- **D5. The route preference does not survive a restart.** Mesh was selected,
  the app force-stopped and relaunched, and it dialled `100.127.119.54:7625`
  (tailnet). Selecting `mesh` navigates immediately, so there is no obvious
  moment at which it is saved.
- **D6. No retry after a refusal.** The mesh screen keeps showing
  `mesh · refused` indefinitely; recovery required force-stopping the app.
- **D7. Wrong numbers presented as facts.** A node with no GPS fix showed
  `45.68345, -111.09405` (Montana) and `distance ≈ 914 km`, and a node heard
  minutes earlier showed `last heard 47 min ago`. The distance is derived from
  a coordinate the node never sent.
- **D8. "0 in range" while the row shows RSSI −12 and SNR 11.0** on the same
  node, in the same list.
- **D9. Stale contact status.** After the add attempt the sheet still said
  "Not a device contact" while rendering the contact-only telemetry controls.
- **D10. Device model misread.** A Heltec V4.3 is reported as "Heltec WiFi LoRa
  32 V3" on the battery screen.
- **D11.** `WioTrackerL1_companion_radio_usb` answers `CMD_SEND_SELF_ADVERT` with
  `OK`, but a tool that expects `OK` next can receive `RfLogFrame` or
  `MessagesWaitingFrame` instead — reproduced on the second advert. The
  firmware's OK carries no correlation tag, which is why the host gateway keeps
  its explicit one-command-at-a-time queue.

### What the two-radio leg did prove

- A second companion radio flashed from this tree works over USB serial, and its
  four radio numbers and TX power can be set and read back from the host
  (`tool/configure_radio.dart`).
- Two radios on the same preset discover each other with a direct path, and a
  flood advert from a node with no prior presence lands as a direct neighbour.
- The desktop gateway + daemon bind and report capacity and hourly budget
  correctly against a real radio (`state ready`, 172 B, 58 records).

## Corrections to the two-radio entry above (same day, later)

Two of the eleven entries were wrong, and one had the wrong cause. Written out
rather than edited away, because the correction is the useful part.

- **D2 is RETRACTED. `Radio contacts` works.** The accessibility tree gives the
  row's real bounds: `[40,1805][1040,1925]`. My taps were at y = 1510–1546,
  which land on the non-clickable `MeshCore-HELTEC-BASE` text at
  `[153,1495][732,1568]`. My screenshot-to-device coordinate reading was off by
  about 320 px, and four "attempts" were four repetitions of the same mistake.
  The row opens the screen; `test/screens/device_manager_sheet_test.dart` now
  pins that at both normal and 1.3x text size.
- **D4 is RETRACTED as unconfirmed.** The switch binds `svc.enabled`
  (`connected_apps_screen.dart:112-122`) and the subtitle binds `svc.status`
  (`:89-95`). A test now asserts an enabled, listening service renders ON and a
  stopped one OFF, and it passes (`connected_apps_screen_test.dart`). The stored
  preference was `mm.gateway.enabled.v1=true`, so the screen had every reason to
  draw ON. Most likely I misread a dark-themed switch at screenshot scale. Not
  proven either way, so it does not belong in a defect list.
- **D3 stands, but the cause was the preference, not the product default.** The
  keep-alive defaults **on** (`background_prefs.dart:16`), and the phone's stored
  value is `mm.bg.keepalive=false` — turned off by a tap during this session.
  With it off, Android killed MeshMore and the gateway with it, and LDMUX said
  `mesh · MeshMore not running`, which was accurate. What was still wrong is
  that the gateway never held the keep-alive itself, so a contract with another
  app depended on a setting meant for the user's own foreground experience.
  Fixed: `MeshcoreController.holdKeepaliveForGateway` /
  `releaseKeepaliveForGateway`, reference-counted, best-effort, called by
  `GatewayService` when a gateway starts and stops. Two tests: the gateway holds
  it with the user preference off, and a refused notification permission leaves
  the gateway serving.
- **D1 is narrower than written, and its cause is still open.** The contact did
  land: `Radio contacts` shows `350 of 350 contacts on the radio` with
  `WIOld …26f6071f4650 · direct` in the list. A client `BIND` then succeeded with
  `BIND OK caps=2 max=172`. So the sequence was: add → `BIND_ERR` immediately
  after → later `BIND_OK`. The add is still optimistic (`send` at
  `meshcore_controller.dart:858` is a write, not an acknowledgement), and the two
  views (`_contacts` for the gateway, `_probedContacts` for that screen) can
  disagree in the window between the two. Which exact path repaired `_contacts`
  is not established, so it stays an open question rather than a claimed bug.
  Fresh fact from the same screen: every row carries `Remove from device
  contacts`, so a full table is recoverable, and the banner states the condition
  plainly ("Contact list is full. Remove entries below to add new ones.").

## D1 root-caused and fixed (same day)

The window between the two contact views was the symptom. The cause is that
`BIND` consulted the app's contact cache, and that cache is only as fresh as the
last sync:

- After a MeshMore reinstall the app reported `2 known` peers while the radio
  still held all 350 contacts, including the peer being bound.
- `isContact` (`mesh_sender_adapter.dart`) answered from `_mc.contactRecordFor`,
  so `GatewaySession._onBind` (`session.dart:164`) sent `BIND_ERR not_a_contact`
  and closed the connection. Reproduced twice, before and after the reinstall.
- The radio is the authority for contact records. `MeshcoreMeshSender` now
  syncs on demand on a cache miss (`_contactFor`), at most once every 5 seconds,
  and polls for up to 4 seconds while the frames arrive. `bindPeer` uses the
  same path, so a later `isContact` and a `bindPeer` cannot disagree.

Proof on the phone, cold cache, after reinstall:
`hello ok caps=2 state=0`, `pair ok`, `BIND OK caps=2 max=172`.
Test: `mesh_sender_adapter_test.dart`, "bind syncs the radio when the app has not
cached the contact yet" — asserts `CMD_GET_CONTACTS` goes out on a cache miss and
that the bind resolves once the frames land.

Separately verified the D3 fix on the device: with `mm.bg.keepalive=false`,
`dumpsys activity services` shows `ForegroundService ... isForeground=true
foregroundId=4403` while the gateway is listening, i.e. the gateway holds the
process alive for its client instead of relying on the user's own preference.

## Phone leg re-verified after the fixes, and a measurement trap

Both defects are closed on the device, not just in tests, with the user's
background preference **off** (`mm.bg.keepalive=false`):

- `BIND OK caps=2 max=172` in 1.7 s from a cold contact cache, after a
  force-stop and relaunch.
- The app backgrounded for 90 s (home screen, no foreground UI): `hello_ok` in
  0.02 s and `BIND OK` again, with
  `dumpsys activity services` showing `isForeground=true foregroundId=4403`.

Measurement trap, recorded because it cost two false conclusions: a stale
`adb forward` continues to accept local connections after the remote port stops
listening, and the client then waits out its full frame timeout instead of
failing fast. Two probes "timed out" this way while the gateway was healthy.
The check that removes the doubt is a raw HELLO straight over a freshly created
forward, and reading the port the app actually advertises on screen rather than
assuming the preferred one. `GatewayServer` binds an ephemeral port when the
preferred one is unavailable, so the advertised port is the only truth.

## Airtime modes: specified in prose, absent from the code (2026-10-29)

Question asked: was there a mode for observing a duty cycle and a mode for a
private mesh where the channel is ours and the bandwidth is free?

Answer as found, before any change:

- **Prose existed.** `meshmore-sns-private-mesh-investigation.md` §2 recommends a
  private tuple as the target and gives numeric triggers; `architecture.md` §5.5a
  says US915 has no duty cycle and calls the budget "unlimited in practice" there.
- **No switch existed.** `Governor({Duration budget = 36 s})` was the only source
  of the figure, `Gateway()` constructed it with no argument, and
  `GatewayService._start` passed only `estimator:`. Grep for `budget:` in both
  `packages/` and `lib/` found one unrelated comment in
  `device_config_screen.dart`. No preference, no UI, no test.
- **The host end has no meter at all.** `crates/mesh` reads
  `txAirtimeTenthsThisHour` for display; `crates/daemon/src/mesh.rs` decrements a
  local `records_left` after a send but refuses nothing on airtime grounds. So
  "each end enforces the same policy on itself" (`architecture.md` §5.5) is
  implemented on the phone side only.

What was built: `AirtimePolicy` in `meshcore_gateway` (`onePercentDutyCycle`,
`ownedChannel`), `Governor.forPolicy`, an uncapped governor that still meters,
`airtimePolicy:` on `Gateway`, `mm.airtime.policy` via `AirtimePolicyPrefs`,
`GatewayService.setAirtimePolicy` (rebuilds the gateway so the running governor
follows the choice), and a switch on the connected-apps screen with the
consequence written underneath it. Tests: 3 in the gateway package, 1 service
test that a saved policy is applied at load, 1 screen test that the choice
persists and the governor's budget changes.

The gap that remains is recorded in `architecture.md` §5.5b: the daemon has no
host-side governor, so the mode has no counterpart there yet.
