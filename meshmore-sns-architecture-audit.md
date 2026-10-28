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

