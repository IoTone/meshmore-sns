# Gateway handoff: how MeshMore and LDMUX find each other

Status: design of record, 2026-10-30.

This replaces the clunky part of mesh pairing: typing or scanning a gateway token into LDMUX when
both apps are installed on the same phone.

## The rule

- **Same device, both apps installed: the token is delivered over Binder, never typed.**
- **Different devices (phone to a Linux host gateway): the `ldmux://pair` code stays.**
- **The wire between the apps does not change.** It is still the L2 gateway over loopback TCP. What
  changes is how the credential gets there.

## Why loopback TCP is not the problem — the typed token is

Android's own security guidance says not to put sensitive IPC on localhost ports, on the grounds
that any app on the device can reach them. That is true of the **transport**: any app can
`connect()` to `127.0.0.1:41731`. It is not true of the **credential**: the gateway answers
nothing useful before `PAIR(token)`, the token is 128 bits, compared in constant time, and the
pre-auth path is bounded by `GatewayLimits.preAuthTimeout`.

So the exposure that matters is not "another app can open the socket", it is "the human has to
carry a 32-hex secret across a screen". That is the part being removed.

Keeping the wire unchanged also keeps one codec, one test suite and one ADR for both the phone and
the Linux host gateway. Moving the whole channel onto Binder would fork the protocol in two.

## What replaces it

MeshMore exports a bound service that hands over the running gateway's endpoint and token, and only
apps signed with the same certificate may bind to it.

```
  MeshMore (com.iotone.meshmore_sns_app)      LDMUX (dev.ldmux.mobile)
  ─────────────────────────────────────       ───────────────────────
  <permission                               <uses-permission
    android:name="dev.meshmore               android:name="com.iotone.meshmore_sns_app
      .permission.GATEWAY_HANDOFF"             .permission.GATEWAY_HANDOFF"/>
    android:protectionLevel="signature"/>    <queries><package
                                               android:name="com.iotone.meshmore_sns_app"/>
  <service android:name=".GatewayHandoff       </queries>
    Service"
    android:exported="true"
    android:permission="com.iotone.meshmore_sns_app
      .permission.GATEWAY_HANDOFF"/>
              ▲                                      │
              └──────── bindService(explicit) ───────┘
                       returns: version, port, token, radioKey, peerName
```

### Why a signature permission and not a check in code

- It is declarative, so the platform refuses the bind before any MeshMore code runs. A bug in the
  service cannot leak the token to an unsigned app.
- It needs no user prompt and no app-ops screen: the grant is automatic when the certificates
  match.
- It is the documented mechanism for IPC between apps from one developer.

The service still calls `checkCallingPermission()` on every transaction. Declarative rules are
enforced by the platform, but the receiver must not assume its own manifest is the only caller.

### Why not a ContentProvider

A provider is for structured data. This is a live endpoint and a live secret, both of which change
with the gateway's state, and the caller needs to know *when* it changed. A bound service can push
that; a provider makes the caller poll.

### Why not NSD or mDNS

`NsdManager` discovers services on a network. Two apps on one phone are not a network. It also has
no authentication story: discovery would still need a permission check, which is the mechanism
already chosen, so mDNS would add a step and remove nothing.

### Why not a shared UID

`android:sharedUserId` is deprecated, and it would merge two products' sandboxes — the opposite of
the separation the architecture is built on.

## As built

- Permission: `com.iotone.meshmore_sns_app.permission.GATEWAY_HANDOFF` (package-prefixed, as Android's guidance names them).
- Service: `com.iotone.meshmore_sns_app.GatewayHandoffService`, a hand-written `Binder` with one transaction that returns the `Bundle`. No AIDL, so no generated code to keep in step across two repositories. `checkCallingPermission` runs on every transaction.
- Dart publishes through the `meshmore/gateway_handoff` channel (`publish` / `clear`) on every `GatewayService` notification; the Kotlin side holds it in memory only and clears it when the Flutter engine goes.
- LDMUX asks automatically when it holds the session keys and no token, and on the `fetch token` button in Settings (which may replace a stored token, because pressing it says that one is not working). On a refused or unreachable link the mesh screen offers the same action.

## Contract

`GatewayHandoff` binder reply, a `Bundle` with:

| key | type | meaning |
| --- | --- | --- |
| `version` | int | contract version, 1 |
| `state` | string | `running`, `waitingForRadio`, `off`, `failed` |
| `port` | int | the port actually bound (never assume 41731) |
| `token` | byte[] | 16 bytes (`GatewayLimits.pairingTokenBytes`; the 32 in a code is hex characters), present only in `running` |
| `radioKey` | string | hex public key of the **phone's** radio, when known. Informational: LDMUX's `host radio key` is the *host's* radio and still comes from the `ldmux code` ceremony |
| `peerName` | string | the bound peer's contact name, when known |

`state != running` is a normal answer, not an error: LDMUX shows "MeshMore is not serving yet" and
the reason, instead of a token field.

## Rotation and revocation

- The token is minted on first gateway start and stored in MeshMore's secure storage
  (`mm.gateway.pairing_token.v1`), as today.
- `revoke` mints a new token and drops the active session. Every later handoff carries the new one.
- LDMUX stores what it receives the same way it stores a pasted token today (Keystore-backed), so
  losing the Binder path costs nothing: the last handoff still works.
- A handoff never silently overwrites a **working** pairing. It replaces the token only when LDMUX
  has none, or when the stored token fails to pair and MeshMore offers a different one.

## Failure behaviour

| situation | what LDMUX shows |
| --- | --- |
| MeshMore not installed | "MeshMore is not installed" and the paste/scan path |
| MeshMore installed, gateway off | "MeshMore is not serving" and a button that opens MeshMore's gateway screen |
| bound, but token refused | "MeshMore refused that token" and one retry with a fresh handoff |
| service missing on an old MeshMore | fall back to the paste/scan path, no error |

## Build requirement

Both apps must be signed with the same certificate for the grant to be automatic. Today both use
the debug key, so development works on one machine. A release build of either app must move to a
shared release key, and a build signed with a different key loses only the automatic path — it
falls back to the code.

## What this does not do

- It does not remove the gateway's loopback listener, and does not pretend loopback is private.
  The token is still the gate.
- It does not pair across devices. A phone and a Linux box have no Binder between them.
- It does not weaken the rule that the phone's radio key and the session keys arrive by the
  `ldmux://pair` ceremony. Only the gateway token moves.
