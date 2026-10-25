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

### 1.6 iOS: no loopback gate; the real constraint is keeping the BLE owner alive

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
2. A settings screen: gateway address (port from a QR shown by MeshMore),
   connect/disconnect, link status.

### 2.3 What is shared, precisely

- The **L2 specification document** (opcodes, framing, pairing, error
  codes, capability bits) — written once, with **shared test vectors**
  (hex) that both the Dart and Kotlin implementations run in CI.
- The **L3 protocol** is already shared by construction: LDMUX's KMP client
  and the Rust daemon both implement `crates/protocol`; the gateway just
  carries those frames.
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

The tunnel is only half the system. The other half is carrying L3/L4 frames
over a 143-byte, single-request, zero-padded, direct-only mesh:

- **Chunking** with sequence numbers and resync (ldmux's own
  `docs/MESH-TRANSPORT.md` already concluded line-mode + chunking is the
  only viable shape; the firmware numbers in the interop doc fill in the
  arithmetic).
- **Serialisation**: one outstanding `pending_req`; the gateway queues.
- **Self-delimiting framing** because of 16-byte zero padding.
- **Deadlines** from `est_timeout` (`RESP_CODE_SENT`), which the firmware
  computes from airtime + hops.
- **Discovery first, then raw custom**: a flooded binary request reaches an
  unknown peer; raw custom is the cheap steady state once a path is known
  (interop doc §2.4a).

This work is independent of the phone apps. It is the largest single piece
and is where most of the schedule risk lives.

---

## 6. Per-platform manifest/entitlement surface

| | MeshMore (Dart) | LDMUX (KMP) |
|---|---|---|
| Android today | FGS `connectedDevice` already declared (`AndroidManifest.xml:36-37,76-79`) | `INTERNET` (install-time, for the loopback connect) |
| Android 37+ | Nothing for loopback (§1.5) | Nothing for loopback (§1.5) |
| iOS today | **`UIBackgroundModes: bluetooth-central` — new**; `NSBluetoothAlwaysUsageDescription` | Nothing (loopback is ungated, §1.6) |
| iOS 26 | Radio must be set up via **AccessorySetupKit** for state-restoration relaunch, or use the **Live Activity** lever to keep full background BLE privileges; force-quit is never restored; ~10 s per wake | Nothing |

The iOS line is the biggest new work in the whole plan and it is all on the
MeshMore side.

---

## 7. Security model (loopback has no caller identity)

Because any app with `INTERNET` can reach a loopback port, the tunnel
authenticates at the first frame:

- **Pairing:** per-install token, generated by MeshMore, shown as a QR;
  LDMUX enters/scans it. Token is not logged.
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

## 9. Phased plan (in scope per the scope cut)

| Phase | Content | Deps | Notes |
|---|---|---|---|
| **P0** | L1 encoders: `CMD_SEND_BINARY_REQ`/`PUSH_CODE_BINARY_RESPONSE`, tag map, `est_timeout` deadlines, serialised sends - in `packages/meshcore` with hex vectors | none | General; unblocks everything |
| **P1** | L2 spec + `packages/meshcore-gateway` + pairing + grants + in-app debug client | P0 | Contract freezes here |
| **P2** | LDMUX KMP `MeshMoreGatewayClient` + settings screen | P1 | ~500 lines Kotlin; no BLE |
| **P3** | Mesh-side carry: chunking, serialisation, padding-safe framing, deadlines, discovery then raw-custom | P0 | Largest piece; independent of the phone apps |
| **DEFERRED** | lobospeak v0: L4 codec, robot handler, GOTO/HALT in MeshMore | P0, P3 | **Spec-only; no robot functionality built now** |
| **OPTIONAL** | Firmware forwarding patch upstream; channel-broadcast commands; AIDL if signature-gated callers ever needed; iOS AccessorySetupKit + Live Activity work for MeshMore | various | |

Each phase is usable alone. P0 unblocks everything.

## 10. Open questions

1. **iOS AccessorySetupKit:** is the radio an "accessory" in Apple's sense
   (MFi/protocol declaration), and is the pairing UX acceptable to the
   user? This decides whether MeshMore can be killed and relaunched on
   iOS 26 with the link intact. (Live Activity is the fallback lever.)
   Investigation item, not a user decision.
2. **Pairing token lifetime:** recommend per-pairing, revocable
   (recorded recommendation, not yet a decision).
3. **LDMUX iOS:** not started (`ldmux/docs/STATE.md`). The KMP client is
   shared code, so iOS work is the entitlement-free socket client + UI; the
   hard iOS work is MeshMore's, not LDMUX's.

Decided and closed: GOTO scale (degE7), halt policy (deny by default,
revocable), client policy (one at a time), architecture (two-app
gateway).
## 11. Fresh-eyes corrections to earlier assumptions

| Earlier assumption | Correction | Evidence |
|---|---|---|
| "AIDL is the safe choice; Meshtastic's loopback move is a fad" | Meshtastic's move is the direction of travel; AIDL is deprecated *in the closest precedent*, and it is structurally unavailable to a Dart server + KMP client pair | `IMeshService.aidl` deprecation notice; §1.2 |
| "iOS requires a persistent notification for background BLE" | No Apple document requires it; the alerts are opt-in keys, and guideline 2.5.4 is one sentence about intended purposes | Archived CoreBluetooth guide; `app-store/review/guidelines` 2.5.4 |
| "Loopback on Android needs ACCESS_LOCAL_NETWORK" | The permission is API 37+, LAN-scoped by interface definition; loopback is outside it; the real A17 change is cross-profile, which does not apply | `Manifest.permission`; `behavior-changes-all` |
| "Share the backend = share the code" | Dart and Kotlin cannot share code; the shareable unit is the contract + the gateway service | §1.2 |
| "LDMUX might become a Flutter app" | It is already a device-verified KMP app with a native VT; porting discards working code and the design | `ldmux/docs/STATE.md` |
| "The MeshCore protocol layer needs building" | It already exists as `packages/meshcore` (pure Dart, 101 opcodes, pinned) | `packages/meshcore/lib/src/` |
| "The ldmux wire protocol needs a transport adapter" | It is already transport-agnostic: one 8-byte header frame, bearer-token pairing, `GET /ws` today | `crates/protocol/src/frames.rs`, `STATE.md` |
