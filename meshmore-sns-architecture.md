# MeshMore × LDMUX × lobospeak: the architecture of record

**Status:** design, 2026-10-24. Nothing implemented, nothing published.
Supersedes the architecture sections of
[`meshmore-sns-meshcore-interop.md`](./meshmore-sns-meshcore-interop.md),
which remains the protocol-facts reference (every firmware claim there has
`file:line` evidence at `companion-v1.17.1`).

**Decisions taken (user, 2026-10-24):**

- LDMUX stays a **separate app**. It is not merged into MeshMore.
- The **UI is not shared** between the two apps. What is shared is the
  **backend** — the MeshCore protocol capability — in a clean, robust,
  supported way.
- MeshMore is the **protocol and IO handler** for the radio on the phone.

Everything below follows from those decisions plus the platform and
firmware constraints, each of which is stated with its evidence so it can be
re-checked.

---

## 1. The hard constraints (why the shape is what it is)

These are not preferences. Each one eliminates options.

### 1.1 The radio's BLE link is single-central

The companion radio exposes one BLE peripheral (Nordic-UART service). One
central connects. Two apps cannot co-own the link.

Consequence: **exactly one app on the phone may hold the radio.** That is
MeshMore. It already owns the connection, the reconnect logic and the
SYNC-drain (`meshmore_sns_app/responsive_starter_app/lib/meshcore/ble_connector.dart`,
`meshcore_connection.dart`, `background_keepalive.dart:9-15`), and it already
declares the right foreground service
(`android/app/src/main/AndroidManifest.xml:36-37,76-79`:
`FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_CONNECTED_DEVICE`,
`connectedDevice` service).

### 1.2 Dart and Kotlin do not share code

MeshMore's backend is Dart. LDMUX's mobile client is **Kotlin Multiplatform**
(`ldmux/packages/mobile`, native Compose + a JNI shim over libghostty-vt,
Android device-verified, `ldmux/docs/STATE.md`). There is no supported path
for a KMP app to embed the Dart VM, and no supported path for a Dart app to
call a KMP library. AIDL would require writing a **Kotlin service inside the
MeshMore Android layer** — i.e. adding a native tier to a pure-Dart app — and
it would be unusable by any future Dart client.

Consequence: the only cross-framework, cross-platform shared surface is a
**wire contract**: a versioned binary protocol plus test vectors,
implemented independently in Dart and Kotlin. "Sharing the backend"
therefore means sharing the **contract and the gateway service**, not the
code.

### 1.3 `dart:io` cannot do what iOS wants natively, and vice versa

- `dart:io` `Socket` supports TCP and UDP only. There is no Unix-domain-socket
  API in Dart on any platform.
- Apple's App Groups entitlement explicitly authorises UNIX domain sockets
  between app-group members
  (`developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups`),
  but a Dart app cannot create one.
- Loopback TCP works in Dart on both Android and iOS, and in Kotlin on both.
  It is the **only** transport both sides can speak natively.

### 1.4 The MeshCore payload budget is small and the firmware is picky

From the interop doc (all `file:line` at `companion-v1.17.1`):

- Binary request app payload: **143 B** (176-byte companion frame − opcode − 32-byte pubkey).
- **One** outstanding binary request (`pending_req`); sends are serialised.
- Unknown binary request types are **dropped** by stock firmware.
- Raw custom is **direct-route only** (flood forwarding commented out).
- Binary payloads are **zero-padded to 16 B** — framing must self-delimit.
- Channel datagrams (165 B, `DATA_TYPE_DEV`) exist for broadcast.

Consequence: any app-to-app traffic carried over the mesh must be chunked,
self-delimiting, and serialised. That is a property of the **gateway**, not
of the client apps.

### 1.5 Android: loopback is not gated; the permission that sounds scary is not

- `ACCESS_LOCAL_NETWORK` is **added in API level 37** (Android 17) and
  scoped to "an IP network that utilizes a broadcast-capable network
  interface, such as Wi-Fi or Ethernet" — loopback is not in that class, so
  it is outside the permission's scope
  (`developer.android.com/reference/android/Manifest.permission`,
  `developer.android.com/privacy-and-security/local-network-definition`).
  Apps targeting ≤36 need nothing; on 37+ the permission is for LAN, not
  127.0.0.1.
- **Android 17 separately blocks cross-profile loopback** (work/personal),
  unconditionally on A17 devices; **same-profile loopback is unaffected**
  (`developer.android.com/about/versions/17/behavior-changes-all`).
  MeshMore and LDMUX are both in the personal profile.
- Binding a `ServerSocket` on 127.0.0.1 requires no declared permission
  (only `INTERNET`, granted at install).
- Residual risk (documented, not resolved by a quote): no official page
  states the loopback exemption verbatim; it follows from the
  interface-based definition. **Verify once on a real device** with the
  privacy toggle off.

### 1.6 iOS: no loopback gate, but a suspended app cannot serve the socket

- iOS has no `ACCESS_LOCAL_NETWORK`-style gate that reaches loopback. Apple's
  TN3179 defines local network as broadcast-capable interfaces (Wi-Fi,
  Ethernet); loopback is not one, and the operations table shows
  **listening/accepting TCP requires no local-network access at all**
  (`developer.apple.com/documentation/technotes/tn3179`).
- App Group UNIX sockets are authorised by Apple — but both apps would have
  to be native, and MeshMore is Dart, so they are unavailable to this pair.
- **The iOS constraint is MeshMore's background BLE liveness**, not the
  socket:
  - MeshMore would need `UIBackgroundModes: bluetooth-central` (it does not
    have it today; the keep-alive is an Android foreground service,
    `background_keepalive.dart`).
  - The widely repeated "mandatory persistent notification" rule is
    **not in any Apple document**: the archived CoreBluetooth guide presents
    the connection/disconnection/notification alerts as opt-in ("Include
    this key if you want"), and App Review guideline 2.5.4 is a single
    sentence about using background modes for their intended purposes
    (`developer.apple.com/app-store/review/guidelines`, archived
    `InfoPlistKeyReference` iOS Keys). Treat the folklore as dead.
  - Each background wake gets **~10 seconds**; overrun gets throttled or
    killed.
  - **iOS 26 gates state-restoration relaunch on AccessorySetupKit**
    (TN3115 note 5, updated 2025-09-15): if the radio link is
    load-bearing after the app is killed, the accessory must be set up
    through AccessorySetupKit, or iOS will not relaunch the app.
  - iOS 26 also allows a **Live Activity started before backgrounding** to
    restore full foreground-equivalent BLE privileges in the background.
  - Force-quit is never restored. Memory pressure kills the app
    regardless.
- **CORRECTION (2026-10-24, audit E1): this section previously concluded
  that the iOS constraint was only BLE liveness. It is not.** A suspended
  iOS app's process is frozen, so `ServerSocket.accept()` does not run and
  a connecting LDMUX times out. `bluetooth-central` wakes the app for BLE
  events only, for about 10 s, which cannot serve an interactive terminal
  client. The consequence is that **the two-app gateway is Android-only as
  designed**; on iOS either the gateway runs only while MeshMore is in the
  foreground, or LDMUX reaches the host directly. See O1 in §11. The
  AccessorySetupKit and Live Activity findings below remain correct and
  independent of this problem.

### 1.7 Precedent: "one app is the node, other apps are clients" is the established pattern

- **Meshtastic** ships exactly this: a core app owns the radio, other tools
  talk to it. Its AIDL `IMeshService` is **deprecated in favour of a
  localhost service on `127.0.0.1:8087`** (`core/api/.../IMeshService.aidl`
  deprecation notice).
- **Okta Verify** runs loopback-based invocation in production and broke
  only when Android 17 added the cross-profile block — proof that
  same-profile loopback IPC is a live, shipping pattern
  (`support.okta.com`, 2026-08-17).
- Google's own Security checklist says localhost ports are reachable by any
  app and recommends IPC "where authentication is possible" — i.e. it
  endorses the pattern **with caller authentication**, which the gateway
  must therefore provide (pairing token, §7).

Conclusion: the two-app node shape is not exotic. It is the documented
industry shape, and the hardware constraint (§1.1) forces it here.

---

## 2. The architecture

Four layers, each with a single owner and a versioned contract:

```
  L4  lobospeak payload codec          (spec + vectors; Dart + Kotlin + robot FW)
  L3  ldmux wire protocol              (EXISTING: 8-byte header frames, pairing,
                                         bearer token — crates/protocol)
  L2  gateway tunnel protocol          (NEW: pairing, capabilities, payload
                                         send/recv to named peer, raw-subscribe)
  L1  MeshCore companion protocol     (EXISTING: packages/meshcore Dart pkg +
                                         pinned firmware behaviour)

  LDMUX (KMP)        MeshMore (Dart/Flutter)        radio      host
  ────────────      ──────────────────────         ──────     ────
  terminal UI       owns BLE link (L1)
  gateway client ──L2 over 127.0.0.1──▶ gateway server ──L1──▶ mesh ──▶ ldmuxd
  (no BLE, no L1)   (no app state leaked)             (L3/L4 chunked,
                                                        serialised, padded)
```

### 2.1 What MeshMore adds (Dart only)

1. **`packages/meshcore-gateway`** — a new pure-Dart package (no Flutter
   imports): the L2 server. `dart:io` `ServerSocket` on 127.0.0.1, a free
   port, one client at a time (it can serve LDMUX and future Dart clients
   from the same process). Pure Dart so it runs under `dart test` with no
   device.
2. **Client registry + grants** — per-client pairing token, capability set,
   revocation, "connected apps" settings surface.
3. **MeshMore app** imports the package and wires the socket into the isolate
   that already owns the BLE link. No Kotlin, no native code, no new
   permission (loopback needs nothing, §1.5/1.6).

### 2.2 What LDMUX adds (Kotlin only)

1. **`MeshMoreGatewayClient`** — a KMP shared-module class: TCP connect to
   127.0.0.1:port, send the pairing token as the first frame, then send and
   receive L2 frames. It carries **L3 ldmux frames** (already
   transport-agnostic: one 8-byte header, `crates/protocol/src/frames.rs`)
   over the tunnel. Roughly a few hundred lines. **No BLE, no companion
   protocol, no radio knowledge.**
2. A settings screen: gateway address (fixed `127.0.0.1:41731`, §5.5),
   pair/re-pair by scanning MeshMore's QR, connect/disconnect, link status.

### 2.3 What is shared, precisely

- The **L2 specification document** (opcodes, framing, pairing, error
  codes, capability bits) — written once, with **shared test vectors**
  (hex) that both the Dart and Kotlin implementations run in CI.
- The **L3 protocol** is shared by construction between LDMUX's KMP client
  and the Rust daemon, but it is **not** what crosses the mesh. `crates/protocol`
  encodes control frames as JSON (`crates/protocol/src/frames.rs:95-105`)
  with a 16 MiB payload ceiling (`:45`), which cannot survive a 142 B
  record. The mesh profile needs its own compact encoding of the subset it
  actually uses, defined end-to-end inside the Noise session. An earlier
  draft said the gateway "just carries those frames", which was wrong
  (audit G1).
- The **L4 lobospeak codec** is shared the same way: spec + vectors,
  implemented in Dart (MeshMore/robots) and Kotlin (LDMUX pin UI).

Nothing else is shared. The two apps never exchange Dart/Kotlin code.

### 2.4 What is NOT shared (deliberately)

- UI: LDMUX keeps its native terminal (libghostty-vt via JNI — the whole
  point of its design, `ldmux/docs/NATIVE-TERMINAL.md`). MeshMore keeps its
  Flutter shell.
- MeshMore's app state (contacts, chat, channels, prefs): the gateway
  exposes **no** companion commands to clients. A client cannot read
  contacts, send chat, or change radio settings (§7).

---

## 3. The rejected options, with their pros and cons

Each option was considered seriously. The record is here so the decisions
can be re-opened with the costs visible.

### 3.1 Port LDMUX to Flutter — REJECTED

| Pro | Con |
|---|---|
| One phone-client codebase | Loses libghostty-vt: the terminal becomes a Dart emulator or a WebView, contradicting ldmux's "light by construction" design (`docs/STATE.md`, `docs/NATIVE-TERMINAL.md`) |
| Flutter BLE stack already exists | The KMP client is **already built and device-verified on Android** (`STATE.md`); porting discards working native code |
| | Dart terminal rendering is the heaviest possible implementation of a VT; ldmux's whole cost model assumes native rendering |
| | The radio link is still MeshMore's, so the port shares nothing — it only re-implements the client |

Verdict: the port buys one codebase and destroys the design. Not worth it.

### 3.2 Fork MeshMore into LDMUX — REJECTED

| Pro | Con |
|---|---|
| Total control of the phone client | Kotlin cannot run Dart code: the fork means **re-implementing the companion protocol in Kotlin** (codec, contacts, sync, reconnect — the pinned protocol alone is 101 opcodes, `packages/meshcore/lib/src/codec/constants.dart`) |
| | Two apps would fight for the **single-central BLE link** (§1.1): LDMUX connected means MeshMore cannot be used, and vice versa |
| | Every MeshMore fix (reconnect policy, keep-alive, sync-drain — all hard-won, device-tested) must be re-done in Kotlin and kept in sync forever |
| | Contradicts the user's own goal: MeshMore as the protocol/IO handler |

Verdict: the fork is the most expensive option and the only one that breaks
the hardware constraint.

### 3.3 AIDL bound service on MeshMore — REJECTED as primary

| Pro | Con |
|---|---|
| `signature`-level caller verification for free (Google's documented recommendation for same-developer IPC, `developer.android.com/training/articles/security-tips`) | Requires a **Kotlin tier inside the MeshMore Android app** (AIDL Stub + MethodChannel bridge to Dart) — native code in a pure-Dart app |
| | Unusable by future Dart clients; useful to exactly one client (LDMUX) |
| | The closest precedent **abandoned it**: Meshtastic deprecated `IMeshService` in favour of `127.0.0.1:8087` |
| | iOS has no AIDL; the loopback socket is what both platforms share anyway, so AIDL becomes a second, Android-only surface |

Verdict: keep it as the **upgrade path** if a future requirement demands
signature-gated callers. Not worth building now.

### 3.4 Shared native library (Rust/C++) — REJECTED

| Pro | Con |
|---|---|
| One implementation of the protocol stack | MeshMore's BLE stack is Dart (`flutter_blue_plus`); extracting it to native rewrites the most-tested part of the app |
| | KMP↔Dart FFI in both directions is a large, new, long-term maintenance surface |
| | The protocol payload is 143 B at a time; the "shared stack" is a handful of frame codecs, not a system |

Verdict: the shared surface is small enough that a spec + vectors is cheaper
than a shared binary.

### 3.5 One app, two shells (terminal inside MeshMore) — REJECTED by decision

The user chose separate apps. The technical case also agrees: a terminal
shell in Flutter means a Dart VT (see 3.1), and it would couple LDMUX's
release train to MeshMore's.

### 3.6 iOS App Group UNIX domain sockets — REJECTED for this pair

Apple explicitly authorises them (`com.apple.security.application-groups`
entitlement; path in the group container; `SOCK_MAXADDRLEN` cap). But
MeshMore is Dart and `dart:io` has no UDS API, so the channel cannot exist
on the MeshMore side. (If MeshMore ever gains a native tier, this becomes
the iOS-only fast path.)

### 3.7 The radio's own WiFi/USB transport — REJECTED

ESP32 companion builds listen on TCP 5000 (`examples/companion_radio/main.cpp:36-37,209-210`),
which would let LDMUX talk to the radio with no phone-side gateway. But:
single client, absent on the nRF52 (the Wio), competes with MeshMore's BLE
ownership, and leaves MeshMore out of the loop — the opposite of the
stated goal.

---

## 4. What "make MeshMore modular" concretely means

MeshMore is **already more modular than assumed**:

- `packages/meshcore` — pure Dart: `codec` (101 pinned opcodes), `crypto`,
  `model`, `transport` interface, diagnostics. No Flutter imports. This is
  the L1 contract in code.
- `responsive_starter_app/lib/meshcore/` — the BLE orchestration
  (`ble_connector.dart`, `reconnect_policy.dart`, `meshcore_connection.dart`,
  `background_keepalive.dart`) plus app state (`chat_store.dart`, etc.).

Plan:

1. **Keep `packages/meshcore` as the L1 authority.** Any protocol change
   (e.g. the binary req/resp encoders added for lobospeak) lands here first,
   with `flutter test` vectors.
2. **Create `packages/meshcore-gateway`** (L2 server, pure Dart) as above.
3. **Do not extract the BLE layer** now. It is only needed by Dart clients;
   the only Dart client is MeshMore, which already has it in-process. If a
   second Dart app appears, extract `lib/meshcore/`'s connection code into
   `packages/meshcore-ble` at that time — a bounded, well-bounded refactor
   of files that already sit in one directory.
4. **Freeze the L2 contract on first external client** (LDMUX). After that
   it is a protocol, versioned and additive-only.

---

## 5. The gateway's job on the mesh side (the hard part)

Cross-checked against ldmux's own mesh design
(`ldmux/docs/MESH-TRANSPORT.md`, `ldmux/docs/adr/0020-mesh-link-security.md`,
both 2026-10-06, design-only), the gateway is **simpler than a general
transport**: it is a **blind carrier**.

### 5.1 What the gateway carries

- The end-to-end session is **Noise IKpsk2** between the LDMUX app and the
  host, per ADR-0020. The gateway is not an endpoint of it.
- The session's **record layer** (ADR-0020 §3: 24 B fixed overhead, one
  record per packet, counter in the clear) is produced by the endpoints,
  not the gateway.
- The gateway ships **one record per packet** and never parses, chunks,
  decrypts, or rewraps session content.
- **The gateway does not retransmit.** ADR-0020 §3 is explicit: "a
  retransmission is a *new* record with a new counter; duplicates are
  removed by the application sequence number, not by resending
  ciphertext." A blind relay that resent identical ciphertext would reuse
  the counter and the receiver's 64-record replay window would drop it as
  a duplicate. ARQ therefore lives **end-to-end**, and the gateway's only
  mesh-side job is to serialise whole records onto a radio that permits
  one outstanding request.
- Large items (the optional ML-KEM stage, 1,184 B / 1,088 B) are
  fragmented **end-to-end**, above the record layer, by the session.

This is the correction of an earlier draft that gave the gateway an
outgoing ARQ and a per-record ACK. See `meshmore-sns-architecture-audit.md`
findings A2 and B1.

### 5.2 The carriage: two phases, because one of them is much cheaper

**Corrected 2026-10-24 after reading `src/Mesh.cpp:589-603` and
`MyMesh.cpp:801-824`:** raw custom is not the host's private option. Both
ends can use it, and on **stock companion firmware** — `onRawDataRecv`
is wired for `PAYLOAD_TYPE_RAW_CUSTOM` and pushes it to the app as
`PUSH_CODE_RAW_DATA` (0x84). No firmware fork is needed on either end for
this.

Raw custom is also **exact-length**: `createRawData` copies bytes verbatim,
with no cipher and no padding. That removes the delimiter problem
entirely, and it carries more: a `CMD_SEND_RAW_DATA` frame is
`[25][path_len][path][payload]` inside 176 bytes, so the datagram is
`174 − path_len` and a 3-hop path still allows 171.

The catch is routing: `RAW_CUSTOM` is direct-only, in both directions
(`src/Mesh.cpp:292-297` delivers it only when `isRouteDirect()`, and the
flood forward is commented out). So there must be a path before it can be
used, and a path is learned by a flooded exchange.

| | **Phase A — discovery** | **Phase B — established** |
|---|---|---|
| When | no path known, or the path went stale | a path is known |
| Uplink | `CMD_SEND_BINARY_REQ` (0x32), **flooded** | `CMD_SEND_RAW_DATA` (0x19), direct |
| Downlink | the firmware's flooded `PATH + RESPONSE` return | `PAYLOAD_TYPE_RAW_CUSTOM`, direct |
| Cipher / padding | AES-ECB, zero-padded to 16 B | **none, exact length** |
| Datagram | 143 B app data | 174 − path_len (171 at 3 hops) |
| Record | 142 B (1 B length + record) | **172 B** |
| Application bytes | 118 B | **148 B** |

Phase A exists to teach both ends a path, and it does so in one exchange:
a flooded request makes the responder build a `PATH + RESPONSE` return and
flood it back, which delivers the answer and the reverse path at the same
time (`src/helpers/BaseChatMesh.cpp:286-306`). The Noise handshake
(121 B then 50 B, ADR-0020 §2) fits in Phase A's 118 B.

Phase B is where the throughput lives: **148 B of application per record
against 118**, and no delimiter at all.

Three caps stack on the uplink and the smallest binds:

| Cap | Bytes | Source |
|---|---|---|
| Companion frame | 176 | `src/helpers/BaseSerialInterface.h:5` |
| → app data after opcode + pubkey | 143 | `MyMesh.cpp:1678-1684` |
| `sendRequest` guard | 163 | `src/helpers/BaseChatMesh.cpp:633` |
| `createDatagram` guard | 163 | `src/Mesh.cpp:487-489` |

143 binds only because the companion frame is the smallest of the three.

**Delimitation, and why it is only a Phase A problem.** Binary payloads
are AES-ECB encrypted and zero-padded to 16 B, and the decryptor does
**not** strip the padding (`src/Utils.cpp:62-90`; `src/Utils.h:41` warns
"dest may contain trailing zero bytes in final block"). So a Phase A
record cannot be recovered by length, and "the 16 B tag guarantees a
non-zero tail" is false one time in 256. Phase A therefore carries an
**explicit one-byte record length** as the first byte of the datagram.
Phase B needs nothing: raw custom is exact.

**Path refresh.** The radio learns better paths as traffic flows and
signals it with `PUSH_CODE_PATH_UPDATED` (0x81), which carries **only the
peer's public key** (`MyMesh.cpp:404-410`) — the app must re-read the
contact to get the new `out_path`. The firmware's own comment warns the
app may not be connected when the push happens, so MeshMore also
re-reads contacts on reconnect. A stale path does not error: the radio
sends into the void. The gateway therefore treats "no response within the
session's timeout" as a path failure, issues `CMD_RESET_PATH` (0x0D) to
force the next send to flood, and returns to Phase A.

The endpoints size records to the carriage; the gateway checks "does this
record fit" and queues.

### 5.3 The gateway's mesh-side mechanics

- **Serialisation**: one outstanding `pending_req` (firmware,
  `MyMesh.cpp:1688-1689`); the gateway queues records per session, one
  in flight at a time.
- **No ARQ, no delivery ACK.** The gateway reports only what the firmware
  reports: `RESP_CODE_SENT` (with its route flag), `est_timeout`, or an
  `ERR_CODE_*`. Whether a record arrived is a question only the
  end-to-end session can answer.
- **Phase switching** is the gateway's main piece of state: it holds the
  peer's `out_path` from MeshMore's contact store, uses Phase A until a
  path exists, then Phase B, and drops back to Phase A on
  `CMD_RESET_PATH` or on a session timeout.
- **Delimitation**: a one-byte length prefix in Phase A only (§5.2).
  Phase B is exact-length and needs no delimiter.
- **Backpressure**: the gateway applies a credit window of 8
  records; a client that exceeds it is
  stalled, not buffered without bound (audit C2).

### 5.4 Timers (aligned to ldmux's mesh profile)

ldmux's mesh-profile timers (MESH-TRANSPORT.md "Review", item 7):
client ping ≥60 s, idle sweep ≥5 min, claim grace ≈60 s.

- L2 carries **no** heartbeat of its own. TCP keepalive plus `STATUS` is
  enough, and L3 already has `PING`/`PONG` (audit B7).
- The mesh-side idle question is answered by the end-to-end session's own
  timers, not by the gateway.
- `est_timeout` is an **estimate** from `calcFloodTimeoutMillisFor` /
  `calcDirectTimeoutMillisFor` (`src/helpers/BaseChatMesh.cpp:645-653`),
  not a measurement, and the gateway cannot see repeater retransmissions
  or collisions. It is labelled an estimate wherever it is surfaced.

This work is independent of the phone apps. It is the largest single
piece and is where most of the schedule risk lives.

---

### 5.5 L2 gateway protocol - draft v0 (the contract P1 freezes)

Draft, for review. Freezes when P3 lands (see §9 for why the order
changed). Written to be implementable in Dart (server) and Kotlin
(client) with no further discussion.

Revised 2026-10-24 against `meshmore-sns-architecture-audit.md`: no
gateway ARQ, no delivery ACK, no ML-KEM capability bits, a version byte,
`HELLO` before `PAIR`, little-endian lengths, and flow control.

### Framing

One frame per message. Magic first so a wrong-version peer is
identifiable before any field is interpreted:

```text
  offset  size  field
  0       2     magic    0x4D 0x47  ("MG")
  2       1     version  (1 in v0)
  3       1     type
  4       1     flags    (must be 0 in v0)
  5       2     length   (u16 little-endian, payload byte count, max 512)
  7       N     payload
```

Max frame 519 B. Little-endian matches the rest of the MeshCore
ecosystem, so there is one byte-order convention in the codebase
(audit B8).

The socket is plain TCP on `127.0.0.1`, port **41731**. One mechanism,
not three: the port is fixed and documented, and if it cannot be bound
MeshMore reports the failure in Settings rather than silently moving.
No TLS: the socket is loopback-only and the pairing frame authenticates
the caller, with the limits in §7.

### Types

| type | name | direction | payload |
|---|---|---|---|
| 0x01 | HELLO | client→gw | version (1), capability bits (1) |
| 0x02 | HELLO_OK | gw→client | version (1), capability bits (1), radio state (1) |
| 0x03 | HELLO_ERR | gw→client | 1-byte reason |
| 0x10 | PAIR | client→gw | 16-byte pairing token |
| 0x11 | PAIR_OK | gw→client | none |
| 0x12 | PAIR_ERR | gw→client | 1-byte reason |
| 0x20 | BIND | client→gw | 32-byte peer pubkey (the host node) |
| 0x21 | BIND_OK | gw→client | capabilities (1), largest uplink record the path allows (1) |
| 0x30 | RECORD | client→gw | seq (1), one record |
| 0x31 | RECV | gw→client | one record |
| 0x32 | SEND_RESULT | gw→client | seq (1), result (1): sent_direct / sent_flood / err_not_found / err_busy / err_too_long / local_timeout |
| 0x40 | STATUS | gw→client | radio state (1), rssi (1), battery (1), gateway TX airtime used this hour (2, 0.1 s units) |
| 0x60 | CLOSE | either | 1-byte reason |

Rules:

- `HELLO` is the first frame on every connection. A version mismatch gets
  `HELLO_ERR(version)` before any other field is interpreted (audit B6).
- `PAIR` follows `HELLO_OK`. The token is compared in constant time
  against the persisted, revocable grant. No other frame is processed
  before `PAIR_OK`.
- `BIND` selects the mesh peer for the session's records. One `BIND` per
  connection in v0 (one client, one peer). BIND fails with
  `BIND_ERR(not_a_contact)` when the peer is not already a MeshCore
  contact; adding a contact is **not** something the gateway does (§2.4).
- `SEND_RESULT` describes the radio's own send outcome, nothing about
  delivery. The gateway never reports `delivered` or `dup` because it
  cannot know either (audit B1).
- `RECV` carries records the radio heard; ordering and de-duplication are
  the session's problem (ADR-0020's counter window), not L2's.
- **`RECORD` carries a one-byte sequence number and `SEND_RESULT` echoes
  it.** Added after audit: a queue can hold several records while one is in
  flight, and a refused record must be attributable. Without the echo a
  client cannot tell which of its records failed, and would retry the wrong
  one.
- **`BIND_OK` advertises the real uplink capacity.** Raw data accepts
  `174 − path_len`, so a long path silently shrinks what fits. A session
  that sized to the absolute ceiling would spend airtime on sends the radio
  refuses. The receiver sizes to the advertised number, with a floor of
  160 B that still fits a 14-hop path.
- Unknown type: the gateway ignores the frame and does not close. A
  malformed length or a bad magic closes with `CLOSE(reason=protocol)`
  (audit decision D6/unknown-frame policy).
- One connection at a time. A second connection attempt is accepted and
  immediately sent `CLOSE(reason=busy)`. A connection that has not
  authenticated within 5 s of opening is closed, so an idle local socket
  cannot deny the legitimate client (audit C2).

### Pairing token

- 128 bits, generated by MeshMore at pairing time, shown as a QR in
  Settings → Connected apps.
- Stored in platform secure storage (Android Keystore-backed, iOS
  Keychain), never in `SharedPreferences`. Android backup rules must
  exclude it regardless of where it lands — today both rule files exclude
  only `maps/` (audit D1).
- Revocable from Settings, per-pairing. A re-pairing issues a new token
  and kills the old one.
- Compared in constant time.

### Capability bits (v0)

| bit | name | meaning |
|---|---|---|
| 0 | recv-credit | gateway enforces the 8-record credit window (§5.3) |
| 1 | status-push | gateway pushes `STATUS` on change |

Reserve the rest. **Only gateway capabilities appear here.** The ML-KEM
bits an earlier draft put in L2 are gone: a blind gateway cannot know or
attest the host's crypto capabilities, and those belong inside the
end-to-end session (audit B3).

### The duty-cycle governor

**Corrected 2026-10-24: an airtime budget is per-transmitter and local.
The carrier never throttles somebody else's transmissions.**

An earlier draft gave the gateway a budget frame and a `throttled` flag,
which implies the phone decides how much the host may transmit. It cannot:
the host's transmissions are the host's airtime, counted against the host's
own duty cycle. So each end enforces the same policy on itself:

| | Phone side | Host side |
|---|---|---|
| Metered | the gateway's own uplink records | the host gateway's own downlink records |
| Default | 36 s of airtime per hour | 36 s of airtime per hour |
| Enforced by | MeshMore's gateway | ldmux's mesh gateway process |
| Reported | `STATUS` (informational) | ldmux's own diagnostics |

`STATUS` therefore reports what the phone's gateway has spent, for the UI.
There is no `BUDGET` frame and no `throttled` flag: a client cannot grant
itself airtime, and the gateway has no authority over the peer's.

The meter accumulates the firmware's `est_timeout`, which is an **estimate**
from `calcFloodTimeoutMillisFor` / `calcDirectTimeoutMillisFor`
(`src/helpers/BaseChatMesh.cpp:645-653`), and cannot see repeater
retransmissions or collisions. It is labelled an estimate wherever shown.

MeshMore's own companion traffic (chat, telemetry, sync) never crosses L2
and is outside this policy. So is lobospeak.

### 5.5a What this link is, stated honestly

The numbers decide the UX, and the honest description is **not** "a terminal".

| Preset | Records/hour | A command with a 5-record reply | So |
|---|---|---|---|
| SF7/500 kHz | 450 | 6 records | about 75/hour |
| SF7/125 kHz | 120 | 6 records | about 20/hour |
| SF10/250 kHz | 40 | 6 records | about 6/hour |
| SF11/62.5 kHz | 4.8 | 6 records | **cannot complete one** |

At the longest-range preset the budget does not even afford one
command-and-reply per hour. So the mesh profile is a **low-rate command
channel**: send a command, receive the last lines of its output, minutes
later. It is not an interactive shell, and presenting it as one would be a
lie the transport tells every keystroke.

This is not a defect to design around. ldmux already reached the same
conclusion from its own measurements: the `mesh` profile is "plain lines",
"one uplink per command", "backlog never replayed", and the client's
terminal engine is **unused** (`ldmux/docs/MESH-TRANSPORT.md`). The plan
here agrees with it.

What follows for the UI:

- No live cursor, no per-keystroke echo, no spinner that implies a second.
- Show the budget in **operations left this hour**, not seconds, because
  that is the number the user can act on.
- Show a timestamp on every reply, because "minutes later" is normal.
- Never imply delivery.

### 5.6 Why the budget needs no raise mechanism: the output is bounded at the source

36 s per hour sounds generous until it is converted into packets, and the
conversion is preset-dependent. Airtime per packet below is ADR-0020's
estimate (Semtech formula, **not measured**), and 136 B is the downlink
application payload from §5.2:

| Preset | s/packet | Records per hour | KB per hour | A 2 KB snapshot needs |
|---|---|---|---|---|
| SF7/500 kHz | 0.08 | 450 | 66.6 | 1 s |
| SF7/125 kHz | 0.30 | 120 | 17.8 | 4 s |
| SF10/250 kHz | 0.90 | 40 | 5.9 | 13 s |
| **SF11/62.5 kHz** | **7.50** | **4.8** | **0.7** | **110 s** |

148 B is the Phase B application payload (§5.2); the discovery phase is
smaller and only used for the handshake.

The last row is the whole argument. On the longest-range preset, 36 s of
airtime per hour buys **under five packets**. A single terminal snapshot
would consume three hours of budget. So no raise mechanism can rescue a
profile that sends history, and a "long transfer" scenario must not exist
by design.

It does not need to. ldmux's own measurement said it already: `ls -laR` is
514,758 bytes but the user sees 24 lines, and substituting state for
history turns that into one ~2,000 B snapshot (`docs/WIRE-COST.md` §1).
The mesh profile goes further and sends **the state of now only, never
replayed history** (`docs/MESH-TRANSPORT.md`, the `mesh` column of the
two-profile table).

The bound is therefore applied where the output is produced, on the host:

- cap a mesh reply at **1,500 B**, and
- further cap it to what the remaining budget actually affords:
  `floor(budgetRemaining / airtimePerPacket) * 148` bytes.

On SF7/125 kHz that is the 1,500 B cap (about 10 records, 3 s). On
SF11/62.5 kHz it is roughly 550 B (4 records, 30 s), which a screenful of
last-lines still fits inside.

Consequence for the plan: the governor needs **no raise path in v1**,
because the output profile guarantees every operation is small. The user's
own framing — "a reasonably small amount of history, up from the bottom"
— is the design, not a limitation to be escaped. If a genuine need for a
larger transfer ever appears, an owner-only raise in MeshMore's settings is
an additive change.

### Failure behaviour

- Client disconnect: the gateway releases the single `pending_req` slot
  and clears the queue.
- Radio drops: the gateway holds up to 8 records (the credit window), and
  reports `STATUS(radio_lost)` when the link returns. It does not drop or
  pretend delivery.
- MeshMore process death: the socket dies with it; LDMUX reconnects with
  backoff and re-authenticates with its stored token. Pairing survives app
  updates.

## 6. Per-platform manifest/entitlement surface

| | MeshMore (Dart) | LDMUX (KMP) |
|---|---|---|
| Android today | FGS `connectedDevice` already declared (`AndroidManifest.xml:36-37,76-79`) | `INTERNET` (install-time, for the loopback connect) |
| Android 37+ | Nothing for loopback (§1.5) | Nothing for loopback (§1.5) |
| iOS today | **`UIBackgroundModes: bluetooth-central` — new**; `NSBluetoothAlwaysUsageDescription` | Nothing (loopback is ungated, §1.6) |
| iOS 26 | Radio must be set up via **AccessorySetupKit** (non-MFi-capable, §10) for state-restoration relaunch; `bluetooth-central`; restore identifier + `willRestoreState`; force-quit never restored; ~10 s per wake; Live Activity optional best-effort. **No gateway listener** — LDMUX on iOS is tailnet only (O1) | Nothing (loopback ungated) |

The iOS line is the biggest new work in the whole plan and it is all on the
MeshMore side. It also carries the one blocker the plan does not yet
answer: see O1 in §11.

---

## 7. Security model (loopback has no caller identity)

Because any app with `INTERNET` can reach a loopback port, the tunnel
authenticates at the first frame:

- **Pairing:** per-pairing token, generated by MeshMore, shown as a QR;
  LDMUX enters/scans it. Not logged, and **not stored in
  `SharedPreferences`**: both Android backup rule files currently exclude
  only `maps/`, so a prefs-stored token would be cloud-backed and
  restorable onto another device (audit D1). It goes to platform secure
  storage, and the backup rules get an explicit exclusion regardless.
  Compared in constant time.
- **Denial of service:** one connection at a time; a second attempt gets
  `CLOSE(busy)`. An unauthenticated connection is closed after 5 s, so a
  local app cannot hold the single slot forever (audit C2).
- **Capability scoping:** a client can (a) send a payload to a named peer,
  (b) receive responses tagged to its own requests, (c) subscribe to raw
  pushes it requested. It **cannot** send companion commands, read
  contacts, sync messages, or change radio settings. This kills the
  "confused deputy" class (Google names it explicitly: "Don't leak
  permission-protected data", `security-tips`).
- **Revocation:** per-client grant, shown and revocable in
  Settings → Connected apps, with bytes-in/out counters.
- **One client at a time** on v1 (matches the single `pending_req` on the
  mesh side; multi-client is additive later).
- The radio-side crypto (companion protocol, MeshMore↔radio) is unchanged.

Three security layers, each against a different threat:

| Layer | Protects | Against | Owner |
|---|---|---|---|
| L2 pairing token | the local socket | other apps on the phone | MeshMore gateway |
| E2E Noise IKpsk2 (ADR-0020) | the session content | the mesh, repeaters, RF observers | LDMUX app + host; **gateway is blind** |
| Companion protocol crypto | MeshMore↔radio | BLE observers | firmware |

The gateway sees only the record layer's 6 clear bytes (type/version,
session index, counter). It never sees application bytes.

**What the loopback token does not protect.** It is a bearer token on a
local socket, so it does not survive a compromised device: any process
that can read MeshMore's secure storage or attach to the socket already
has the phone. It also does not authenticate the *client* beyond "knows
the token". Both limits are acceptable because the content is separately
end-to-end encrypted and the gateway grants no companion-level authority.
A client that steals the token can waste airtime, not read the mesh.

**Confused deputy.** The gateway accepts `BIND` for any peer pubkey but
performs **no** companion writes (no contact add, no chat send, no
settings change), so a malicious local client cannot turn MeshMore into a
proxy for radio authority. `BIND` on a non-contact fails with
`BIND_ERR(not_a_contact)` (audit B2).

---

## 8. Decisions taken (2026-10-24, user)

- **Architecture accepted:** the two-app gateway design stands. MeshMore
  Flutter + radio owner; LDMUX KMP client; shared wire contract + test
  vectors, no shared code.
- **Gateway clients, v1:** one at a time.
- **GOTO coordinate scale:** integer degrees x1e-7 (degE7).
- **Halt policy:** `allowAnonymousHalt` **deny by default**, revocable.
- **Scope cut (user):** **no robot/lobospeak functionality is built now.**
  Only the general infrastructure - the L1 encoders, the L2 gateway, the
  LDMUX client, the mesh-side carry - is in scope. lobospeak v0 (GOTO/HALT/
  telemetry, the L4 codec) is **spec-only, deferred**; the decisions above
  are recorded for when it starts.
- **iOS is a near-term target** (user, 2026-10-24). The iOS line moves from
  OPTIONAL into the plan: `bluetooth-central` background mode,
  `NSBluetoothAlwaysUsageDescription`, the ~10 s wake budget, and the iOS 26
  AccessorySetupKit question (see §10.1).
- **Phone-as-bridge is primary daily use** (user, 2026-10-24). LDMUX's mesh
  mode gets full UX weight, not fallback treatment.
- **Conservative airtime budget, scoped to LDMUX (user, 2026-10-24):**
  the strict budget applies **specifically to LDMUX mesh traffic**,
  because a terminal stream is the one traffic class that could become a
  mesh hog if unmanaged. It does **not** apply to MeshMore's own
  companion traffic (chat, telemetry, sync) or to lobospeak/robot
  traffic. The gateway meters per bound L2 session, and since L2 is one
  client at a time, the budget is simply "the active session's budget":
  default EU868-equivalent (**36 s of airtime per hour**, ~101
  packets/hour at 354 ms each, per ldmux `docs/MESH-TRANSPORT.md`),
  visible in L2 STATUS, revocable. MeshMore's own traffic never crosses
  the L2 data plane, so it is outside the governor by construction.

### 8.1 What "client" means (topology, stated plainly)

A gateway **client** is an **app on the same phone** connecting to
MeshMore's loopback socket. Nothing else.

- LDMUX on phone A is a client of phone A's MeshMore.
- A **second phone** is not a client of phone A: it runs its own MeshMore
  and its own radio, and joins as a **mesh peer** (L1), not a gateway
  client.
- A **computer/host** is not a client of the phone's gateway: it reaches
  the mesh through its own radio (or the phone's radio as a bridge node),
  speaking the L3 ldmux protocol over the mesh, not over the phone's
  loopback socket.
- So "one client at a time" means: one local app (LDMUX today) per phone,
  matching the firmware's single outstanding `pending_req`. Multi-client
  (two apps on one phone) is an additive change later.

### 8.2 The mesh topology, who is what

- **The host** is the desktop/server running `ldmuxd` (the terminal
  daemon + keeper). It has **its own MeshCore radio**, a full node: the
  firmware runs on the board, the host machine talks to it over
  serial/USB/WiFi, and the ldmux gateway process sits next to the daemon
  (MESH-TRANSPORT.md "Review" item 2).
- **The phone** has its **companion radio** (the Heltec/Seeed board
  paired with MeshMore over BLE). MeshMore is its node's owner.
- **Both ends are mesh peers.** "Companion" vs "full node" is not a mesh
  role - it is only how the local machine attaches to its own radio:
  the phone over the BLE companion protocol; the host over serial/USB
  (the companion protocol is transport-agnostic and also works over
  serial, so a companion board on the host would work too, but a full
  node is the natural host choice).
- The mesh is a line (host node - phone node), extendable to more nodes
  later. One line, two radios, each owned by its machine.
- **Fleet fact (user, 2026-10-24):** there are **two radios** in the
  deployment - the host's and the phone's. (Consistent with the radio
  alert work: the owner's own Heltec V4.3 OLED is the phone-side unit,
  and a second Heltec exists in the fleet.)

## 9. Phased plan

Ordered by dependency, not by enthusiasm. The order changed on
2026-10-24 after the audit: an earlier draft froze the L2 contract at P1
and only discovered the transport shape at P3, which is backwards (audit
H1). The contract is now frozen against a transport that is known to work.

| Phase | Content | Deps | Notes |
|---|---|---|---|
| **P0** | L1 encoders in `packages/meshcore`: `CMD_SEND_BINARY_REQ` (0x32), `PUSH_CODE_BINARY_RESPONSE` (0x8C — *not* 0x85), `CMD_SEND_RAW_DATA`/`CMD_SEND_RAW_PACKET`, `RESP_CODE_SENT` decode, length-prefix helper, hex vectors | none | Unblocks everything; no contract dependency |
| **P3** | Mesh-side carry proven end to end: one-byte delimitation, serialisation, discovery (flooded both ways), the reply-size-shrinks-with-hops rule, the estimate-based governor | P0 | **Moved before P2.** The transport shape must be known before the contract freezes |
| **P1** | L2 contract v1 + `packages/meshcore-gateway` + pairing + grants + in-app debug client | P0, P3 | **Contract freezes here** |
| **P2** | LDMUX KMP `MeshMoreGatewayClient` + settings screen | P1 | ~500 lines Kotlin; no BLE |
| **P6 (near-term)** | MeshMore iOS as a standalone radio app: AccessorySetupKit pairing flow, `bluetooth-central`, restore identifier + `willRestoreState`, force-quit tolerance, optional Live Activity. **No gateway listener on iOS.** | iOS target accepted 2026-10-24; unblocked by O1 | Findings in §10 |
| **DEFERRED** | lobospeak v0: L4 codec, robot handler, GOTO/HALT in MeshMore | P0, P3 | **Spec-only; no robot functionality built now** |
| **OPTIONAL** | Firmware forwarding patch upstream (including the `out_frame` overflow guard, audit N3); channel-broadcast commands; `CMD_SEND_RAW_PACKET` uplink so both directions reach ~172 B; AIDL if signature-gated callers ever needed | various | |

P0 is usable alone and unblocks every other phase. P3 and P1 are the
schedule risk.

## 10. Platform research: the iOS background model

### 10.1 iOS AccessorySetupKit (investigated 2026-10-24)

- **No MFi gate.** AccessorySetupKit works with third-party BLE-only
  peripherals whose advertisements match the app's Info.plist
  declarations (`NSAccessorySetupKitSupports` +
  `NSAccessorySetupBluetoothCompanyIdentifiers/Names/Services`). Every
  documented filter operates on unprivileged BLE advertising fields;
  Apple's own sample and three independent practitioner builds (Punch
  Through, Uy Nguyen, Per Friis) all use plain custom service UUIDs, with
  no certification and no entitlement.
- **The gate is declaration-and-match, enforced by crash:** a discovery
  filter that does not match the Info.plist terminates the app (Apple,
  stated twice).
- **The iOS 26 relaunch gate (TN3115 note 5, 2025-09-15):** "starting in
  iOS 26 and iPadOS 26, only apps that use AccessorySetupKit to setup
  Bluetooth accessories will be relaunched." Relaunch happens "if and only
  if" the app was waiting on a specific Bluetooth event that has now
  occurred. **Force-quit is never restored.**
- **The Live Activity lever is documented but narrow:** iOS 26, an
  instantiated CBManager plus a Live Activity started before
  backgrounding grants foreground-equivalent *scanning privileges*. It is
  a privilege, not a lifecycle, so it does not make the app
  relaunch-eligible. Field evidence (m-Path, 2026-08-03) shows it is
  best-effort: system-killable at low battery, killed by camera
  activation, a ~5-minute confirmation dialog, extra battery drain.
- **MeshMore's iOS requirements:** `bluetooth-central`, a stable
  `CBCentralManagerOptionRestoreIdentifierKey`, a `willRestoreState`
  implementation that reconciles restored peripherals against MeshMore's
  paired-device registry, and tolerance of force-quit (the link dies, the
  radio keeps its state, MeshMore re-establishes on next launch).
- **Descriptor caution:** the radio advertises the generic Nordic-UART
  service UUID, which thousands of unrelated devices share, and on nRF52
  the device name lives in the scan response. A descriptor keyed on the
  service UUID alone will produce a very noisy picker.
- **Lead to verify on the 26.5 SDK:** a framework named
  `AccessoryLiveActivities` exists in the iOS 26.5 SDK (`dotnet/macios`
  wiki, 2026-03-31), contents unconfirmed.

## 11. Resolved decisions (2026-10-24, user)

**O1 — iOS and the gateway: RESOLVED.** LDMUX on iOS is **tailnet only**
and gets **no MeshCore support**. The two-app gateway is Android-only.
Consequences:

- LDMUX iOS work is the existing KMP socket client against the tailnet
  session, with no radio, no L2, and no pairing. It does not depend on any
  of this plan.
- MeshMore on iOS stays a standalone radio app: AccessorySetupKit
  pairing, `bluetooth-central`, restore identifier + `willRestoreState`,
  force-quit tolerance. It runs **no gateway listener at all**, which
  removes the loopback-server problem from the iOS side entirely.
- P6 shrinks to "MeshMore is a first-class iOS radio app". The gateway
  piece leaves P6.
- The single-radio-owner rule still holds on every platform, which is why
  this costs nothing in design terms.

**O2 — contact provisioning: RESOLVED.** MeshMore's UI gains an explicit
"add host node as contact" step at bind time. The gateway still performs
**no** companion writes, so §2.4 and the security model are untouched.
`BIND` fails with `BIND_ERR(not_a_contact)`, and the Settings UI offers
the add-contact action next to that error rather than the gateway doing
it silently.

**O3 — governor authority: RESOLVED, and the question was asking the
wrong thing.** Airtime is per-transmitter (§5.5): each end meters its own
transmissions, and the carrier has no authority over the peer's. There is
no `BUDGET` frame and no raise path, because the output is bounded at the
source instead (§5.6). On the longest-range preset 36 s/hour buys under
five packets, so no raise can rescue a profile that sends history, and the
profile does not send history. An owner-only raise is deferred as additive.

**O4 — unknown-frame policy: RESOLVED.** Ignore unknown types, close only
on malformed framing or a bad version. Both sides ship together, and the
frame set must be able to grow without a flag day.

**O5 — pairing token lifetime: RESOLVED.** Per-pairing, revocable, in
platform secure storage, constant-time compare, with an Android backup
rule exclusion regardless of where it lands.

**O6 — LDMUX iOS: CLOSED** by O1. Tailnet only; no mesh work there.

Decided earlier and closed: GOTO scale (degE7), halt policy (deny by
default, revocable), client policy (one at a time), architecture (two-app
gateway).

**Nothing in this section waits on the user. The plan is unblocked.**

## 12. Fresh-eyes corrections to earlier assumptions

| Earlier assumption | Correction | Evidence |
|---|---|---|
| "AIDL is the safe choice; Meshtastic's loopback move is a fad" | Meshtastic's move is the direction of travel; AIDL is deprecated *in the closest precedent*, and it is structurally unavailable to a Dart server + KMP client pair | `IMeshService.aidl` deprecation notice; §1.2 |
| "iOS requires a persistent notification for background BLE" | No Apple document requires it; the alerts are opt-in keys, and guideline 2.5.4 is one sentence about intended purposes | Archived CoreBluetooth guide; `app-store/review/guidelines` 2.5.4 |
| "Loopback on Android needs ACCESS_LOCAL_NETWORK" | The permission is API 37+, LAN-scoped by interface definition; loopback is outside it; the real A17 change is cross-profile, which does not apply | `Manifest.permission`; `behavior-changes-all` |
| "Share the backend = share the code" | Dart and Kotlin cannot share code; the shareable unit is the contract + the gateway service | §1.2 |
| "LDMUX might become a Flutter app" | It is already a device-verified KMP app with a native VT; porting discards working code and the design | `ldmux/docs/STATE.md` |
| "The MeshCore protocol layer needs building" | It already exists as `packages/meshcore` (pure Dart, 101 opcodes, pinned) | `packages/meshcore/lib/src/` |
| "The ldmux wire protocol needs a transport adapter" | It is already transport-agnostic: one 8-byte header frame, bearer-token pairing, `GET /ws` today | `crates/protocol/src/frames.rs`, `STATE.md` |
