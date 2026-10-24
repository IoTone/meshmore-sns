# MeshCore as a shared transport: lobospeak, ldmux, and MeshMore as the radio owner

**Status:** investigation + design, 2026-10-24. Nothing implemented, nothing
published. All firmware claims below were read from
`meshcore-fw-alerts` at tag `companion-v1.17.1` (commit `d929643`), with
`file:line` given so each one can be re-checked. Claims from the web are
marked as unverified.

Three questions are tangled together and this document separates them:

1. **lobospeak** — David's robot control plane. Does the protocol it assumes
   exist? (Partly no: see §2.)
2. **ldmux over MeshCore** — what a terminal actually costs on a 143-byte
   payload, and what has to change on the host side.
3. **MeshMore as the radio owner** — how another app on the same phone can
   use MeshMore's BLE link, and whether that is better than merging the
   feature into MeshMore.

---

## 1. Where lobospeak lives

There is no lobospeak repository. The only artifacts found:

- `lobospeak-design.md` — 700 lines, wire format, command set, trust model,
  network scoping, name shifting, interaction diagrams.
- `lobospeak-mappins-spec.md` — 429 lines, pins/waypoints/triggers.

Both are in this repo, authored by **David J. Kordsmeier**
(`dad005a`, `fb82f7b`, `4d9c93e`; dates 2026-05-27 and 2026-06-12). No repo,
branch or org named lobospeak or `1805PK` exists under the accessible GitHub
account (`gh search repos`, `gh search code`, `gh api orgs/IoTone/repos`,
`git ls-remote origin`). If a remote exists it is private and outside the
current token's visibility, or it has not been pushed yet.

This matters for the plan: the spec is a design document with no reference
implementation, so its two protocol assumptions (§2.2 and §2.3) have never
been exercised against a radio.

---

## 2. What the companion protocol actually exposes

All numbers below are hard limits in the firmware, not preferences.

### 2.1 Frame budget

| Limit | Value | Evidence |
|---|---|---|
| Companion frame (BLE/serial/TCP) | **176 B** | `src/helpers/BaseSerialInterface.h:5` |
| Write larger than that | rejected, returns 0 | `src/helpers/ArduinoSerialInterface.cpp:25-28` |
| Read larger than that | truncated at 176 | `:60-66` |
| OTA packet payload | 184 B | `src/MeshCore.h:20` |
| OTA wire unit | 255 B | `src/MeshCore.h:23` |
| Group datagram payload | 165 B | `MAX_GROUP_DATA_LENGTH = 184-16-3`, `MeshCore.h:21` |

Consequence that bites every design below: **the companion frame is the
binding limit, not the 184-byte OTA packet.**

### 2.2 Binary request/response (the path lobospeak is built on)

| Fact | Value | Evidence |
|---|---|---|
| `CMD_SEND_BINARY_REQ` | 50 (`0x32`) | `examples/companion_radio/MyMesh.cpp:50` |
| Frame layout | `[0x32][pubkey 32][app data]` | `:1678-1684` |
| Destination lookup | must be an existing **contact**, else `ERR_CODE_NOT_FOUND` | `:1680`, `:1696-1698` |
| **Max app data** | **143 B** (176 − 1 − 32) | arithmetic on `:1678` |
| OTA-side cap | 163 B after `sendRequest`'s 168 guard and `createDatagram`'s padding guard | `src/helpers/BaseChatMesh.cpp:633`, `src/Mesh.cpp:489-490` |
| `RESP_CODE_SENT` | 10 B: `[0x06][route][tag u32][est_timeout u32]` | `:1690-1694` |
| `PUSH_CODE_BINARY_RESPONSE` | `[0x8C][0][tag u32][peer data…]` | `:740-746` |
| Outstanding requests | **one** (`pending_req`), cleared on every send | `:1688-1689`, `:736` |

Two consequences the lobospeak document does not have:

- **No fan-out.** "Each tag is independent, responses can arrive in any
  order" (lobospeak §"Multi-robot fan-out") is false on this firmware. The
  second send clears the first tag, so the first response is dropped by the
  `tag == pending_req` check. Requests must be serialised, one robot at a
  time, or broadcast via the channel path (§2.5).
- **143 B, not ~180 B.** Every size claim in both lobospeak documents
  ("~180 B of lobospeak payload to play with", "payload budget ~180 B",
  "~18 legs/packet" for ROUTE) is 20 % optimistic. A `GOTO` leg is
  `4+4+2+1 = 11 B` plus command overhead, so ~12 legs fit in one packet, not
  18.

### 2.3 Inbound requests are dropped (the blocking finding)

`MyMesh::onContactRequest()` handles exactly one application type,
`REQ_TYPE_GET_TELEMETRY_DATA`, and returns 0 for everything else
(`MyMesh.cpp:627-676`). There is **no generic forwarding of unknown binary
requests to the companion app**.

So the lobospeak happy path —

> `PRadio->>PApp: PUSH_CODE_RAW_DATA(0x84) + sender pubkey + tag + payload`

— does not exist on stock firmware. A robot radio running
`companion-v1.17.1` receives a lobospeak `PING`, finds no handler, sends no
reply, and the operator app sees a timeout. lobospeak cannot work on stock
MeshCore at all, on either architecture A or B, without a firmware change.

### 2.4 Raw custom packets (works today, but carries no identity)

This is the path the firmware does expose opaquely.

| Fact | Value | Evidence |
|---|---|---|
| Inbound push | `[0x84][snr×4][rssi][0xFF][payload…]` | `:801-815` |
| Sender identity in that frame | **none** | same |
| `CMD_SEND_RAW_PACKET` | 65, injects a whole serialised packet + priority | `:64`, `:2003-2008` |
| `CMD_SEND_RAW_DATA` | 25, direct path only, flood "not supported (yet)", min 4 B | `:1519-1534` |
| `PAYLOAD_TYPE_RAW_CUSTOM` | `0x0F`, "custom encryption", no MeshCore cipher | `src/Packet.h:32`, `src/Mesh.cpp:292` |

So a stock radio *will* deliver arbitrary raw-custom traffic to its attached
app and *will* transmit app-built packets. But the receiving app gets no
pubkey, no MAC, and no encryption — all of lobospeak's trust argument
("by the time lobospeak sees a request, the sender's pubkey identity is
cryptographically established") is untrue on this path.

### 2.4a Routing behaviour: raw custom is direct-only, multipart is ACK-only

Two routing facts change the carriage choice.

- **Raw custom is not flood-routed by this firmware.** `Mesh::onRecvPacket`
  only delivers `PAYLOAD_TYPE_RAW_CUSTOM` when the packet is direct-route,
  and the repeater-side forwarding is commented out with "don't flood route
  these (yet)" (`src/Mesh.cpp:292-296`). A raw-custom packet therefore
  travels only along a **known path**; first contact with an unknown robot
  needs path discovery or a flooded request. `CMD_SEND_RAW_DATA` matches
  this: its handler rejects a flood path outright with "flood, not
  supported (yet)" (`MyMesh.cpp:1532-1533`).
- **`PAYLOAD_TYPE_MULTIPART` is not fragmentation.** In 1.17.1 it exists to
  shotgun an ACK burst, and `Mesh::onRecvPacket` only reassembles it when
  the embedded type is `PAYLOAD_TYPE_ACK` (`src/Mesh.cpp:300-320`). There is
  no general reassembly layer to exploit for larger payloads, so chunking
  stays an application concern.

The practical consequence: a flooded request (`CMD_SEND_BINARY_REQ` to a
contact with `out_path_len == OUT_PATH_UNKNOWN` calls `sendFloodScoped`,
`BaseChatMesh.cpp:646-648`) is the thing that reaches an unknown node, and
raw custom is the thing that is cheap once a path is known.

### 2.5 Channel datagrams (the broadcast path lobospeak's open question 3 asks for)

| Fact | Value | Evidence |
|---|---|---|
| `CMD_SEND_CHANNEL_DATA` | 62 (`0x3E`), `[62][ch][path_len][path][data_type u16][payload]` | `:1158-1198` |
| Receive | `RESP_CODE_CHANNEL_DATA_RECV` (27) `[27][snr][rssi][ch][data_type][len][payload]` | `:98`, `:594-601` |
| Payload caps | frame-side 167, radio-side **165** | `:101`, `MeshCore.h:21` |
| Developer namespace | `DATA_TYPE_DEV = 0xFFFF` | `src/helpers/TxtDataHelpers.h:10` |

This is a real one-to-many path with a channel PSK, already in 1.17.1. It
answers "broadcast commands" without new firmware, but it is a **channel**
broadcast: every node holding the PSK sees it, and replies still need the
unicast path.

### 2.6 Padding: binary payloads are not length-delimited

`Utils::encrypt()` zero-pads to 16 bytes (`src/Utils.cpp:85-101`) and the
receiver's length is the padded length. Any lobospeak or ldmux payload that
ends in a partial block arrives with trailing zeros. Every payload must be
self-delimiting (explicit length field or fixed layout). Neither lobospeak
nor ldmux's frame format says this.

### 2.7 Connections and sessions

The firmware has a keep-alive session concept (`startConnection`,
`RESP_SERVER_LOGIN_OK`, `PUSH_CODE_LOGIN_SUCCESS`) used for room servers and
remote administration (`BaseChatMesh.cpp:686`, `MyMesh.cpp:693`). It is not a
general stream and is tied to server ACLs, so it is not a shortcut for a
terminal.

---

## 3. Correcting lobospeak

The design is sound as a *shape*: small command codes, per-command versions,
status byte, owners set, closed channel. What needs to change is the
transport assumption and the size arithmetic.

| # | lobospeak says | Firmware says | Fix |
|---|---|---|---|
| 1 | Requests reach the peer app via 0x84 | Unknown request types are dropped (`:627-676`) | Firmware forwarding hook, or move to raw-custom |
| 2 | Sender identity is established by the OTA layer | 0x84 carries no pubkey | Carry pubkey + app-level signature in the payload |
| 3 | ~180 B payload | 143 B (binary), 165 B (channel), 174 B (raw packet) | Re-derive every budget |
| 4 | Parallel fan-out with independent tags | one `pending_req` slot | Serialise, or broadcast via 0x3E |
| 5 | Response correlated by tag | true, but no source check | Also verify the responder pubkey at app level |
| 6 | Broadcast commands are v2 | already possible: `CMD_SEND_CHANNEL_DATA` + `DATA_TYPE_DEV` | make it v1 for "all robots" |
| 7 | Payloads are as long as they are | zero-padded to 16 B | self-delimiting framing |

Two viable v0 targets follow.

**A. lobospeak-over-raw-custom (no firmware changes).** The sender builds a
`PAYLOAD_TYPE_RAW_CUSTOM` packet (own header, own AEAD or signature) and
sends it with `CMD_SEND_RAW_PACKET`; the robot's app receives it as 0x84 and
verifies the signature itself. Works on every stock companion build, keeps
lobospeak's owners model because the pubkey is inside the signed body, and
restores "never on Public" by using the private channel PSK *inside* the
payload. Cost: lobospeak owns its crypto (~one AEAD + one signature
verification on each side), it loses MeshCore's per-DM encryption, and §2.4a
means it needs a known out-path — so it is a *second* message, not the way
to find a robot for the first time.

**B. lobospeak-over-binary-req with a firmware patch.** Add one push code
("unknown request" with sender pubkey + tag + body) and a hook in
`onContactRequest` that forwards anything it does not handle. Then lobospeak
keeps ECDH encryption and contact identity for free, at the cost of a
firmware fork on every robot radio — which is already the model for the Wio
(our silent-alert build) and could be upstreamed as an opt-in.

Recommendation: **B for robots (they are ours to flash), A as the
interoperability path for third-party hardware.** Both share the same
payload codec, so the codec is written once. In practice a hybrid is
forced by §2.4a anyway: flooded binary request to discover/verify, then
raw custom for the steady state if the crypto cost is acceptable.

---

## 4. ldmux over MeshCore

ldmux already answered the feasibility question in `docs/MESH-TRANSPORT.md`
(a grid never works, a line can). The firmware numbers let that be made
concrete rather than estimated.

| Workload | Bytes on the wire | Packets at 143 B | Notes |
|---|---|---|---|
| keystroke echo | 9 | 1 | fits nine times over |
| one 80-column line | ~82 | 1 | the mesh profile's unit |
| `seq 1 100` | 477 | 4 | needs chunking + resync |
| 24-line screen | 1.9–2.4 KB | 14–17 | at SF7/125 kHz ≈ 0.3 s/packet, ~5 s per repaint |
| `ls -laR` | 515 KB | 3 600 | not a mesh workload at any cadence |

What the host side needs, beyond what ldmux has:

1. **A binary gateway protocol, not JSON.** `attach`, `list`, `sessions`
   responses are hundreds of bytes; at 143 B each becomes a fragment storm.
   A compact opcode + varint encoding, versioned, is required.
2. **Line mode as the only mode.** No alternate screen, no VT stream.
   ldmux's own review already reaches this conclusion.
3. **No per-keystroke uplink.** One uplink per command, client-side line
   assembly.
4. **Timers.** `est_timeout` from `RESP_CODE_SENT` is the correct deadline
   source (it is computed from airtime and hop count). Idle sweeps and claim
   grace must scale to tens of seconds.
5. **ARQ and de-duplication above the record layer.** MeshCore floods
   duplicate and reorder. ldmux's ADR-0020 says this is unspecified; it
   remains the largest unbuilt piece.

Because `pending_req` is single-slot, a gateway must hold **one outstanding
binary request** and queue the rest. That is compatible with line mode (one
line at a time) and incompatible with "keystroke per packet" designs.

---

## 5. Who owns the radio on the phone

The BLE link is a single session. MeshCore's BLE transport is one NUS
peripheral with one active central (community reports of a second central
being accepted but not serviced are unverified; the firmware frame buffers
are shared and single-session by construction, `MultiSerialInterface.h`).
MeshMore already owns that link, and already runs a `connectedDevice`
foreground service for it (`android/app/src/main/AndroidManifest.xml:74-79`,
`lib/meshcore/background_keepalive.dart`), which is the prerequisite for
being a gateway.

So a second app on the same phone has exactly these options.

| Option | How it works | Buy | Cost |
|---|---|---|---|
| **A. Merge into MeshMore** | ldmux client becomes a MeshMore feature | No IPC, one process, shared theme/state, no new attack surface | MeshMore grows a native terminal engine (libghostty-vt via JNI), two products become one release train |
| **B. MeshMore as a local API** | MeshMore exposes a framed socket (loopback + token) or an AIDL service; other apps are clients | One radio owner, any client, reusable for robots and future apps | Android background/FGS work, a security surface, two codebases to version together |
| **C. Radio's own WiFi/USB transport** | ESP32 companion builds listen on TCP 5000 | Zero Android work; works with any device | Single client, WiFi power, absent on nRF52 (the Wio), competes with MeshMore's BLE |
| **D. Hand the BLE link over** | not possible | — | BLE peripheral is single-central |

**Option B is the right long-term shape**, for the same reason Meshtastic
arrived there: their AIDL `IMeshService` is now marked deprecated in favour
of a localhost service on `127.0.0.1:8087`
(`core/api/src/main/aidl/.../IMeshService.aidl`, unverified scrape but
consistent across three forks). One radio owner, many clients, no client
speaks BLE.

But B is not free, and the honest split is:

- **If only LDMUX needs it, and LDMUX is ours, merge it (A).** An in-app
  "Remote terminal" view is one screen, one settings page, and no IPC. It is
  also the only version that works with the app closed, because MeshMore
  already keeps the radio alive.
- **If the goal is "MeshMore is the MeshCore IO handler for other apps"
  (the stated goal), B is required** and should be designed once, not
  grown out of the LDMUX feature.

### 5.1 The security problem with B, stated plainly

The companion protocol is a **single-consumer command stream**. Chat sync is
pull-based (`CMD_SYNC_NEXT_MESSAGE` consumes the queue). A gateway that lets
another app write arbitrary companion frames can therefore corrupt MeshMore's
own state: steal messages, change channels, reset the radio.

So the gateway must not expose the companion protocol. It must expose a
**capability-scoped tunnel**:

- the client can send lobospeak/ldmux payloads to a destination it names;
- the client receives only responses tagged to its own requests, and raw
  packets it subscribed to;
- the client cannot send companion commands, sync messages, read contacts,
  or change config;
- every capability is granted per client in Settings and revocable;
- the token is per-install, shown as a QR to pair, never logged.

That is a much smaller API than "share the radio", and it is the only version
that is safe to ship.

### 5.2 Carrier choice for B

| Carrier | Good | Bad |
|---|---|---|
| **AIDL bound service**, `signature` permission | Strongest auth (same signing key), no network permission, death recipients, no port | Kotlin-only, deprecated by the closest precedent, needs `<queries>` |
| **Loopback TCP/WebSocket** + bearer token | Language-agnostic, debuggable, versionable, works from a WebView | Needs `ACCESS_LOCAL_NETWORK` attention (mandatory at targetSdk 37; loopback exemption disputed in secondary sources), token handling, port conflicts |
| Unix domain socket in app-private dir | Fast, no port, filesystem permissions | Not reachable cross-app on modern Android (per-app SELinux domains) |
| ContentProvider | URI grants, simple | Wrong shape for a stream |

Recommendation: **one wire protocol, two carriers.** AIDL for first-party
apps signed by us (LDMUX), loopback framed socket for third-party or
cross-language clients, both behind the same capability model. The codec is
shared; the carrier is a 200-line adapter.

Note the open risk: Android 17 (API 37) makes `ACCESS_LOCAL_NETWORK`
mandatory and the official page could not be read in this session, so whether
loopback is exempt is **unverified**. Test it on the Android 16 device before
committing to the loopback carrier; AIDL has no such risk.

---

## 6. What MeshMore would gain, and what it costs

Gains, in order of value:

1. **A second product can use the radio without touching BLE.** LDMUX,
   robots, a desktop client, a test harness.
2. **The same tunnel carries lobospeak**, so MeshMore becomes the operator
   console for robots with no new radio code.
3. **It makes MeshMore the protocol surface**, which is what the "mobile IPC
   so MeshMore can be the protocol/MeshCore IO handler" note asks for.

Costs:

1. Codec work MeshMore does not have: `CMD_SEND_BINARY_REQ`/`0x8C` and
   `CMD_SEND_RAW_PACKET`/`0x84` encoders/decoders (today the codec has
   neither; grep of `packages/meshcore` shows no `0x32`/`0x8C`).
2. A request queue with per-request deadlines, because `pending_req` is one
   slot.
3. A client registry, capability grants, revocation, and an audit line.
4. A stable API contract — the moment a second app ships, the frame format
   is frozen. That is the real long-term cost, and the reason to design it
   once rather than bolt it on per feature.

---

## 7. Phased plan

**P0 — codec and request queue (no UI).**
Binary req/resp encode/decode, `RESP_CODE_SENT` parsing, tag → request map
with `est_timeout` deadlines, strict serialisation of sends. Tests against
hex vectors captured from the real radio. This is also the first lobospeak
implementation milestone.

**P1 — tunnel core.**
Capability model, per-client queues, self-delimiting framing (padding-safe),
and the wire protocol (opcode + varint + CRC). One in-process client to
start: a debug screen that pings a node through the tunnel.

**P2 — first carrier.**
AIDL service with `signature` permission, behind Settings → Connected apps
(grant, revoke, show active client, show bytes sent). LDMUX binds to it.

**P3 — ldmux mesh mode, host side.**
Gateway process on the host, compact binary protocol, line mode, chunking
with resync, ARQ. This is the largest piece and is independent of MeshMore
except for the tunnel on the phone.

**P4 — lobospeak v0.**
Shared payload codec; raw-custom carriage for third-party radios; robot-side
handler (firmware or SBC). Map pin → `GOTO` in MeshMore once the codec exists.

**P5 — optional.**
Firmware forwarding patch upstream (makes §2.3 go away for everyone),
channel-broadcast commands, loopback carrier for third-party apps.

Each phase is usable alone. P0 is worth doing regardless of whether the
tunnel ever ships, because binary req/resp is how telemetry and later
robot work reach the app at all.

---

## 8. Decisions needed from the user and from David

1. **LDMUX: merge or tunnel?** Merge is less work and better UX for one app.
   Tunnel is the stated goal and serves everything after it. Doing both is
   the expensive path: tunnel first, merge later only if the UX demands it.
2. **lobospeak carriage:** raw-custom (stock firmware, lobospeak owns crypto)
   or binary-req with a forwarding patch (firmware forks, MeshCore crypto
   free). This decides whether robots need flashing.
3. **GOTO coordinate scale** (lobospeak open decision 5): degE7 vs
   microdegrees. Unverifiable from the docs alone; needs David.
4. **`allowAnonymousHalt` default** in closed fleets (lobospeak §trust).
5. **Who signs the tunnel clients.** If LDMUX is ours, AIDL + signature is
   trivially safe. If third parties are in scope, the loopback carrier and
   its permission risk come back.

---

## 9. Appendix: constants worth memorising

| Constant | Value | Where |
|---|---|---|
| Companion frame | 176 B | `BaseSerialInterface.h:5` |
| Binary req app payload | **143 B** | 176 − 1 − 32 |
| OTA packet payload | 184 B | `MeshCore.h:20` |
| Channel datagram payload | 165 B | `MeshCore.h:21` |
| Text message payload | 160 B | companion doc |
| Contacts required for binary req | yes | `MyMesh.cpp:1680` |
| Outstanding binary requests | 1 | `MyMesh.cpp:1688` |
| Unknown request types forwarded | no | `MyMesh.cpp:627-676` |
| Raw packet sender identity | none | `MyMesh.cpp:801-815` |
| Padding | 16 B zero | `Utils.cpp:85-101` |
| `est_timeout` | from airtime + hops | `BaseChatMesh.cpp:645-653` |
