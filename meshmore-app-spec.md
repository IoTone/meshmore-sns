# MeshMore SNS — normative application specification

Written 2026-11-04. This is the **specification**, not the plan. The plan
(`meshmore-master-plan.md`) records reasoning and evidence; the scope of record
(`meshmore-scope-of-record.md`) records decisions; the register
(`meshmore-feature-register.md`) records state. **This document states what the app must do**, in
terms a test can check, against the seams that exist in the code today.

Authority: where this document and the scope of record disagree, the scope wins and this document is
wrong. Where this document and the code disagree, the code is wrong unless the requirement carries a
`(build)` marker, meaning the seam does not exist yet and must be created.

---

## 0. How to read a requirement

Each requirement has an id (`APP-<group><n>`), a normative word, a statement, and a **check** — the
test or inspection that proves it. MUST / MUST NOT / SHOULD / MAY carry their usual RFC 2119 force.

A requirement without a check is not a requirement, it is a wish. Every row below has one.

Groups: **A** connection and capability · **B** inbound · **C** send · **D** composer · **E** stores ·
**F** blocking · **G** places and map · **H** field operations · **I** media · **J** notifications ·
**K** accessibility and localisation · **L** diagnostics · **M** the gateway coupling.

---

## 1. Architecture as built

The app is two layers in two Dart packages, and the split matters for every requirement below.

```
responsive_starter_app/            Flutter app — UI, stores, controller
  lib/meshcore/meshcore_controller.dart   MeshcoreController (ChangeNotifier)
  lib/meshcore/*_store.dart                persistence, static helpers over SharedPreferences
  lib/screens/*.dart                       UI
  packages/meshcore/                       pure-Dart protocol package
    lib/src/transport/transport.dart       abstract interface MeshcoreTransport
    lib/src/client/meshcore_connection.dart  frame send/receive client
    lib/src/codec/frame_codec.dart         byte-exact encode/decode
    lib/src/model/*.dart                   contact, channel, device config, diagnostics
```

**Verified seams.**

| Seam | Location |
| --- | --- |
| Transport contract | `packages/meshcore/lib/src/transport/transport.dart:19` — `Stream<Uint8List> incoming`, `Stream<bool> connected`, `Future<void> send(Uint8List)` throwing `StateError` when not connected, `close()` |
| BLE implementation | `lib/meshcore/ble_meshcore_transport.dart:18`; connector `ble_connector.dart:36` with `scanAndConnect` `:126` and `connectToRemoteId` `:224`; `reconnect_policy.dart:17` |
| Transport injection | `meshcore_controller.dart:75` (`transportFactory`), `:507`, `:880` |
| Inbound dispatch | `meshcore_controller.dart:183` `_ingestDm`, `:186` `_ingestChat`; handlers `:1938`, `:1980` |
| Send | `sendDirectText` `:1849`, `sendChannelText` `:3199`; optimistic row `:1861-1870`; registration `:1873`; failure `:1882-1885` |
| Composer | `lib/screens/chat_screen.dart:120-125` `_send`, `:334` `TextField` |
| Fake transport | `test/meshcore/fake_transport.dart` |
| Byte-exact tests | `packages/meshcore/test/frame_codec_test.dart`, `interop_replay_test.dart`, `fuzz_test.dart`, `test/vectors/` |

**Five structural gaps the requirements have to work around** — each is why a `(build)` marker exists:

1. **No store layer.** Persistence is `abstract final class XStore` static helpers called from the
   controller's own methods. There is no interface to hang a migration or a filter on.
2. **No capability probe.** `isReady` is one boolean (`:1851`). It cannot express "this firmware has no
   offline queue" or "this radio cannot do two profiles".
3. **No send correlation or timeout.** `_Expect.sent` is registered and failed only on a thrown
   exception; a send that is accepted and never confirmed has no terminal state.
4. **Composer has no byte accounting.** No `maxLength` at `:334`, no measurement in `_send`. An
   over-budget message reaches the codec and fails there.
5. **UI sends fire-and-forget.** `chat_screen.dart:123` `unawaited(mc.sendChannelText(t))`, so the screen
   cannot show a pre-flight rejection — only a later row-status change.

---

## 2. A — Connection and capability

**APP-A1.** The app MUST expose link state as an enumerated type with at least
`disconnected`, `connecting`, `ready`, `degraded`, `unauthorised`. A boolean is not sufficient, because
`ready` and `connected` differ: a bonded radio with an unread MTU is connected and not ready.
(`(build)` — no state enum exists; `isReady` is a boolean.)

*Check:* a widget test drives the fake transport through each state and asserts the UI label and the
composer's enabled state for each.

**APP-A2.** The app MUST read the BLE MTU after service discovery and MUST refuse to send frames whose
encoded length exceeds `MTU - 3` when the negotiated MTU is below **179**. The refusal MUST name the
actual MTU. (`(build)` — no read-back exists today.)

*Check:* fake transport reports MTU 23; the composer disables send and the banner reads the number.

**APP-A3.** Reconnect MUST be governed by `reconnect_policy.dart` and MUST be bounded: a documented
maximum attempt count, exponential backoff with jitter, and a user-visible "reconnect now" action after
the bound is hit. It MUST NOT spin at a fixed interval.

*Check:* unit test on the policy's delay sequence; widget test on the post-bound action.

**APP-A4.** Capability MUST be a per-feature probe, not a boolean: a map from feature id to
`supported | unsupported | unknown`, filled from device info and the firmware version code. Every gated
control MUST consult it and MUST say why it is disabled rather than fail on tap.

*Check:* golden test on the capability map for three firmware versions; a disabled control's tooltip
names the reason.

**APP-A5.** A frame the codec cannot decode MUST NOT be dropped silently. The app MUST count undecodable
frames by type byte and MUST expose the count in diagnostics. `0x91` is currently undecoded and MUST
either be decoded or counted as an unknown type — not ignored. (`(build)` for the `0x91` decoder.)

*Check:* the fake transport emits a frame with an unknown type byte; the counter increments and nothing
throws.

**APP-A8.** A channel tag MUST be normalized to the canonical `#`-prefixed form **before** the key is derived, or the
app MUST refuse the tag and say why. `channelPskFromHashtag` hashes the string it is given, so `emergency` and
`#emergency` derive **different** keys — and only the prefixed form matches the ecosystem convention
(`SHA-256("#emergency")[0:16]`). Today the field passes the text through unchanged (`channels_screen.dart:378`), while
the weak-tag check on the same screen strips the `#` (`:345-352`), so the two halves of one form disagree about what the
tag is. Two people who both type "emergency" land on a channel nobody else can join, with no error.

*Check:* entering `emergency` and `#emergency` produces the same key, or the second is refused with a message naming
the canonical form; a unit test asserts `channelPskFromHashtag('#emergency')` equals keymind's
`EMERGENCY_CHANNEL_SECRET` bytes and that the unprefixed input is normalized to the same value.

**APP-A6.** The protocol package is codec-complete for 21 commands with no UI. Nine MUST have one, because a
codec-complete command with no surface is how a protocol rots: flood scope set/get and scope key (D8.1 needs
them), auto-add configuration, advert path and path discovery ("show route"), contact share/export/import and
lookup by key, allowed repeat frequencies (read-only), reboot (with confirmation), device PIN (Security), and a
repeater session screen (login/logout/has-connection).

*Check:* each of the nine has a reachable control and a widget test that exercises its happy path.

**APP-A7.** Twelve commands MUST NOT be exposed in the app: private-key export and factory reset (a key export and
a wipe belong on the radio's own UI, not behind a phone gesture), signing start/data/finish and anonymous request
until their semantics are documented. Exposure is a security decision, not a convenience one.

*Check:* a grep test over `lib/screens` and the controller's public surface asserting no call site.

---

## 3. B — Inbound path

**APP-B1.** Every inbound frame MUST pass through one ordered pipeline: decode → identify sender →
**block filter** → deduplicate → store → notify. A surface that renders content MUST NOT read a store
that the filter did not write.

*Check:* with a blocked key in the store, an inbound DM from that key increments no unread count,
writes no row, and fires no notification. The seams are `_ingestDm` `:1938` and `_ingestChat` `:1980`.

**APP-B2.** The filter MUST be applied on **contact-list replay as well as on arrival**, because a
reconnect replays contacts and announces strangers. An arrival-only filter leaks on every reconnect.

*Check:* replay a contact list containing a blocked key; no contact row appears.

**APP-B3.** Inbound text MUST be stored with its frame type and the sender's full 32-byte key when the
frame carries it. A display name MUST NOT be used as an identity key — names are user-typed and collide.

*Check:* two contacts with the same display name remain distinct rows.

**APP-B4.** `channelIdx: -1` is the DM sentinel in `ChatMessage`. New row kinds MUST NOT overload it; a
place or system row MUST carry an explicit kind field. (`(build)` — the enum does not exist yet.)

*Check:* a place row and a DM row are distinguishable without reading `channelIdx`.

---

## 4. C — Send lifecycle

**APP-C1.** Every send MUST carry a correlation id from the app, persisted with the row, so that a
relaunch can reconcile an in-flight send. A send with no correlation id cannot be reconciled and MUST
NOT be created. (`(build)` — today only the optimistic row exists, `:1861-1873`.)

*Check:* kill the app mid-send, relaunch, and the row resolves to a terminal state rather than `sending`.

**APP-C2.** A send MUST have a timeout that produces a terminal state. Four rules bind the timeout:

1. A sync-poll timeout MUST NEVER mark a message failed.
2. A channel send MUST NEVER be marked failed from a timeout — channel data has no ACK at all.
3. A DM MAY be marked failed only from an explicit `RESP_CODE_SENT` rejection (`0x06`) or after the
   grace period below.
4. A 30-second grace MUST precede the timeout so a late ACK resolves to delivered.

*Check:* three unit tests — channel send never times out to failed; DM with a late ACK becomes delivered;
DM with a rejection becomes failed with the reason.

**APP-C3.** "Unknown" MUST be a distinct terminal state from "failed". A send that was in flight when the
link dropped MUST read unknown, because the app cannot know whether the radio transmitted it.

*Check:* drop the link mid-send; the row reads unknown, not failed.

**APP-C4.** A retry MUST reuse the row, not create a second one, and MUST be idempotent: two taps produce
one send.

*Check:* double-tap retry; the transport records one frame.

---

## 5. D — Composer

**APP-D1.** The composer MUST count bytes against the **160-byte channel text budget including the
`sender: ` prefix**, and MUST NOT allow a send that exceeds it. The firmware truncates silently instead of
rejecting (`BaseChatMesh.cpp:766-773`), so an over-budget send loses text with no error. (`(build)` —
no counting exists.)

*Check:* type 161 bytes; send is disabled and the counter reads over budget by name.

**APP-D2.** The composer MUST name which quantity its counter shows. Four different limits exist and
conflating them is how the previous 176-byte figure was wrong: **160** channel text including prefix,
**162** datagram blob, **176** BLE frame, **177** offline queue slot.

*Check:* the counter's tooltip states "160 bytes, including your name"; no surface says "176" about text.

**APP-D3.** Drafts MUST survive navigation away and app restart, per channel and per DM thread.
(`(build)` — no draft store exists.)

*Check:* type into a channel, navigate away, return; text is present. Kill and relaunch; text is present.

---

## 6. E — Stores and privacy

**APP-E1.** Chat history is currently **plaintext JSON** in `shared_preferences` under `mm.chat.v1`, capped
at 250 messages (`chat_store.dart:18-21`). The specification requires encryption at rest: history MUST be
encrypted with a key held in the platform keystore, and the key MUST be non-exportable. (`(build)` —
today it is plaintext.)

*Check:* inspect the preferences file after a session; no message text appears in it.

**APP-E2.** The store MUST be bounded and the bound MUST be visible: text 20 MB, places 30 days, trail
14 days, media 200 MB with pinning. Eviction is oldest-first and MUST NOT evict pinned media or a starred
place.

*Check:* fill the text store past its bound; the oldest row is gone and the settings screen shows the
current size.

**APP-E3.** Cloud backup MUST be excluded for the chat store. The mechanism exists and currently excludes the
wrong things for this purpose: `res/xml/backup_rules.xml` and `data_extraction_rules.xml` (wired at
`AndroidManifest.xml:51-52`) exclude `maps/` and the gateway pairing token, but **not `mm.chat.v1`** — so
plaintext message history is backed up to the cloud today. Add the chat preferences to both sections of both
files. An explicit encrypted export with a user passphrase MUST replace backup as the way to move history.

*Check:* the rules XML excludes the chat key in cloud and device-transfer; the export decrypts with the
passphrase and not without it. Inspection of a backup set contains no message text.

**APP-E4.** A changed radio key MUST be treated as a new radio. The app MUST offer one-tap carry-over of
tags, favourites and blocks, and MUST keep history attributed to the radio it came from. (`(build)`.)

*Check:* pair radio B after radio A; the prompt offers carry-over and A's history stays readable.

**APP-E5.** One active radio session at a time. Switching MUST be explicit, and a send in flight at switch
time MUST read unknown. (`(build)`)

*Check:* switch radios mid-send; the row reads unknown and the new radio's queue is untouched.

**APP-E6.** Message search MUST query the **stored history only** — never a radio-side index, because
none exists — and MUST return, per hit, the message text, its channel or thread, the sender, the time and the
row's delivery state. Four rules bind it:

1. Search MUST run through the **same block filter** as every other surface (block spec §5): a blocked key's
   text, name and thread MUST NOT appear in results or in hit counts. "3 hidden" is shown beside the total.
2. Search MUST NOT build a persistent full-text index outside the encrypted store. A plaintext index beside
   encrypted history is the leak that makes the encryption pointless.
3. Search MUST be bounded to the retention window (D8.6, text 20 MB) and MUST say when results were truncated.
4. Search MUST be case- and accent-insensitive for Latin text at minimum, and MUST match substrings, not only
   prefixes — a person searching "ford" expects "Waterford" to be findable but ranked lower.

*Check:* with a blocked key in the store, its message text and name are absent from results and the hidden
count appears; killing the app and searching again returns the same results with no index file created; a
search returning more than the display cap reports truncation.

**APP-E7.** A draft MUST be persisted per channel and per DM thread, keyed by channel id or peer key,
and MUST be encrypted with the same key as history (APP-E1) — a draft is message text and leaks the same way.
Four rules bind it:

1. Saving MUST be debounced (no write per keystroke) and MUST survive process death.
2. Sending MUST clear the draft atomically with the send being accepted, so a failed send leaves the text
   recoverable — the draft is restored to the composer, not lost.
3. A draft MUST be discarded when its channel or peer is deleted, and MUST be **kept but hidden** when the peer
   is blocked; unblocking restores it. A draft is not the blocked party's content, so deleting it would punish
   the user.
4. A draft MUST NOT travel to another radio or device. It belongs to the thread it was typed in, on the device
   it was typed on (D8.9: one active radio owns the queue and the history).

*Check:* type, navigate away, return — text present; kill and relaunch — text present; send while the radio is
disconnected — the row reads unknown and the draft is restored; block the peer — the draft is not shown and
survives unblocking.

---

## 7. F — Blocking

Normative detail lives in `meshmore-sns-block-spec.md`. Three requirements bind this document to it:

**APP-F1.** A block MUST be keyed by the full 32-byte public key, never a display name.

*Check:* two contacts sharing a display name are blocked independently; blocking one leaves the other's
messages visible.

**APP-F2.** A block MUST hide the key's content on every surface in the block spec's ten-row matrix,
including search results, coverage-ping results and the contact list.

*Check:* the ten-row surface matrix test in `meshmore-sns-block-spec.md` §10.

**APP-F3.** The UI MUST state what a block cannot stop: the radio still receives and relays the packet,
the device's own buzzer still sounds unless the fork's consent gate is on, and the block does not travel to
another device.

*Check:* the copy assertions in the block spec's §7; the surface matrix test in its §10.

---

## 8. G — Places and the map

**APP-G1.** A place MUST carry coordinates, a label, a type, a TTL and a deterministic id. The id MUST be
`sha256(pubkey ‖ latE7 ‖ lonE7 ‖ type)` truncated to 8 hex characters, with **no time component**, so a
renewal keeps the id (decision D8.2). Where the report arrives as channel text there is no public key, so the
id MUST use the sender's name bytes and the row MUST be marked **unkeyed** and say so in the detail sheet.

*Check:* two renewals of the same place share an id; two places 1 m apart differ; a channel-sourced place is
marked unkeyed and its id is stable across restarts.

**APP-G2.** The wire form MUST be the text convention `[PLACE]<lat>,<lon> <label> [<type>] [TTL:<duration>]`,
because no client parses `[PLACE]` and the suffix is therefore safe — while inside `[WAY]` a suffix would
corrupt the label. A received place MUST resolve from the text alone.

*Check:* round-trip a place through the text form and parse it back with no other state.

**APP-G3.** Expiry MUST be final: an expired place moves to a local history list and nowhere else. A local
"keep" extends the copy on that device only and MUST NOT re-broadcast. Renewal is an explicit re-broadcast
with the same id and a new timestamp.

*Check:* after TTL the pin leaves the map and appears in history; keep does not send a frame.

**APP-G4.** Place posts MUST be rate-limited to **6 per hour per node, burst 2 in 5 minutes**, enforced at
the send path rather than the UI (D8.16).

*Check:* the seventh post in an hour is refused with a named reason.

**APP-G5.** The bundled basemap MUST be the default and MUST need no network: Natural Earth 110 m
(97 KB) and GeoNames `cities15000.bin` (812 KB). Online packs MUST be opt-in behind a consent screen that
names the source and what it discloses. The privacy claim is true by default and honest when packs are on
(D8.18).

*Check:* fresh install with no network shows a map; enabling packs shows the consent screen first.

**APP-G6.** The type token MUST be a closed set so two clients render the same pin the same way:
`hazard`, `water`, `fuel`, `med`, `rally`, `view`, `camp`, `look`, `other`. Tokens are short because they spend
channel bytes: `[med]` is 5 bytes where `[medical]` is 9. A bracketed word **in the type position** (anchored
before the TTL, or last) is a type; if it is not in the set it renders as `other` while the token itself is
retained in the row and shown in the detail sheet — so filtering still works and the human still reads the
intent. A bracketed word anywhere else is part of the label. Exact grammar and the position rule:
`meshmore-places-spec.md` §3, §4.

*Check:* round-trip each of the nine; `[shelter]` in the type position renders as `other` with "shelter" shown;
`Old [ford] marker` keeps "[ford]" in the label.

---

## 9. H — Field operations

**APP-H1.** SOS MUST be bounded to **12 sends and 10 beacons in 57 minutes**, with a hard stop at 3600 s:
sends at 0–660 s in 60 s steps, beacons at 720–3420 s in 300 s steps. It MUST NOT loop until acknowledged.
An ACK MUST stop the alarm **only** when it arrives as a direct message from a target contact's key and its
id matches the request id; a channel ACK carries only a display name and MUST be shown as "claimed" without
stopping the alarm. An "I'm safe" cancel MUST send one final `[SAFE:<id6>]`. Exact schedule, grammar and
attribution table: `meshmore-sos-spec.md` §5, §7, §9.

*Check:* fake-clock test asserts 12 sends and 10 beacons at the stated offsets and nothing after 3600 s; a
channel ACK leaves the state active; a direct ACK from a non-target key leaves it active.

**APP-H2.** A fix older than **1 hour** MUST NOT be sent as an SOS position. The alarm itself MUST still be
sent, in the `NOFIX` form, and the copy MUST say there is no recent fix. Fix age suppresses the position,
never the alarm.

*Check:* with a 90-minute-old fix the alarm sends, no coordinate appears in the text, and no pin is drawn on a
receiver.

**APP-H3.** Check-in MUST be one bounded send with a deadline; overdue MUST be marked locally and notified,
with no radio-side feature.

*Check:* the deadline passes; the row is overdue and a notification fires.

**APP-H4.** Coverage pings MUST be paced at **1 per 30 seconds and 1 per geohash-6 cell per hour**, jittered
by ±20 %, and MUST correlate replies on the exact 8-character ID. An unmatched reply MUST be counted
separately, never attributed to a responder. Edges MUST be observed only — no line to a nearest repeater, ever
(D8.17). Cell model and storage decision: `meshmore-telemetry-coverage-spec.md` §6–§9. (`(build)` — no pacing
exists.)

*Check:* two pings 5 seconds apart produce one frame; a reply with a mismatched id increments unmatched and
creates no edge; a nearby repeater that never replies produces no edge.

**APP-H5.** An SOS MUST default its destination to the radio's `#emergency` channel when one exists, and MUST offer a
private channel or direct messages as the alternative. The copy MUST state that the channel's key is **derivable from
its name (`SHA-256("#emergency")[0:16]`) and therefore public**, so anyone who knows the name can compute the key and
read the alarm. The app MUST NOT create the channel without an explicit user action, and the add action's copy MUST
name the public key and the radio channel slot it consumes. On that channel the radio itself holds a zero-path flood
and re-sends it once after about two minutes, so the app's copy MUST say that one repeat outlives the app while the
rest of the schedule does not (D8.23).

*Check:* with an `#emergency` channel present, a raised SOS targets it by default and the public-key copy is shown;
with none present, the composer offers a channel or DMs and no default is silently chosen and no channel is created;
`channelPskFromHashtag('#emergency')` equals keymind's `EMERGENCY_CHANNEL_SECRET` bytes in a unit test.

**APP-H6.** The radio's device-side alert engine MUST be reachable only through a **narrow whitelist** of
notification commands, never raw CLI. The app MUST offer "buzz for #emergency" as a one-tap setting. It MUST NOT
expose the engine's `remote` permission by default, because that lets a contact reconfigure the radio's alerts over a
DM. It MUST NOT claim "buzz only for SOS" — a channel selector fires on every message on that channel (D8.24).

*Check:* a raw-CLI command outside the whitelist is refused; the `remote` field is absent from the settings surface;
the copy for "buzz for #emergency" states that every message on the channel triggers it.

---

## 10. I — Media

**APP-I1.** Channel images MUST use one AV1-class format on the `0x5643` envelope. A third image format MUST
NOT be added. (`0xAE1C` is optional and MUST NOT be the default.)

*Check:* a grep test asserting one image content type in the send path; the encoder's golden output starts with
the `0x5643` type byte.

**APP-I2.** Fragments MUST be paced at **350 ms**, and `ERR_CODE_TABLE_FULL` MUST be treated as normal
backpressure — wait and continue, not fail. FEC MUST be Cauchy Reed–Solomon over GF(256), block 20,
~10 % parity for images and ~15 % for voice. Every resend MUST be salted so a repeat is not deduplicated.

*Check:* a 20-fragment image transfers at 350 ms pacing; a table-full response resumes rather than aborts.

**APP-I3.** An image send MUST refuse to start without a known path from a prior routed exchange, because
`CMD_SEND_RAW_DATA` refuses to flood (`MyMesh.cpp:1315-1329`). The refusal MUST name the reason.

*Check:* with no known path, the send is refused and suggests a DM first.

---

## 11. J — Notifications

**APP-J1.** Notification settings MUST be per channel and per peer, with audio, haptic, OS and TTS
independently controllable, plus a **mentions-only** mode.

*Check:* four toggles per channel produce four independent effects in a widget test; mentions-only suppresses a
plain message and admits a mention.

**APP-J2.** A mention MUST be the display name as a whole word or an `@name` form. Key-suffix matching MUST
be opt-in, because a suffix is short enough to collide.

*Check:* unit tests for whole-word, `@name`, substring-not-a-mention, and a colliding suffix with the opt-in off.

**APP-J3.** A blocked key's messages MUST NOT produce a notification on any channel.

*Check:* mention detection unit tests; a blocked key's channel message produces no notification.

---

## 12. K — Accessibility and localisation

**APP-K1.** The app currently has **zero `Semantics(` widgets in `lib/screens`** (eight exist elsewhere in `lib/`). Every interactive
control MUST expose a semantic label, and the send/receive states MUST be announced — a message arriving
while the screen is not visible is exactly the case screen readers fail.

*Check:* an accessibility test asserting labels on the composer, the send button and the message row.

**APP-K2.** Text scaling MUST be honoured to 200 % without clipping the composer or the message row.
`main.dart:264-268` multiplies the OS scale by a user font scale and applies **no floor**; the requirement is that the product honours up to 2.0 and never drops below 1.0.

*Check:* golden at 2.0 scale; no overflow errors.

**APP-K3.** Two locales exist (`app_en.arb`, `app_ja.arb`). Every new user-facing string MUST go through
the ARB files; a hard-coded string in a screen is a defect. RTL MUST NOT be claimed until an RTL locale
exists — the layout must not be described as RTL-ready without one.

*Check:* the `no_binary_sources_test.dart` pattern generalised — a test that greps screens for literal
user-facing strings and fails on new ones.

---

## 13. L — Diagnostics

**APP-L1.** Diagnostics MUST include: undecodable frame counts by type, MTU, firmware version, capability
map, store sizes, and the maps self-test result (`lib/maps/maps_self_test.dart` is the pattern to copy —
it already writes a versioned report).

*Check:* a golden test on the report's field list; every field present when the fake transport reports each state.

**APP-L2.** Diagnostics MUST NOT include message text, key material or precise location unless the user
exports it explicitly.

*Check:* the report generator's golden output contains no message text.

---

## 14. M — The gateway coupling

The app is one half of a pair. It owns the single BLE link and runs an L2 server on loopback so the paired app
can tunnel end-to-end-encrypted records through the radio. `lib/meshcore/gateway/` (776 lines) already wraps
`package:meshcore_gateway`; the architecture document is `meshmore-sns-architecture.md`.

**APP-M1.** The app MUST own the BLE link exclusively. No second app may open the radio's connection. The
gateway MUST NOT expose companion commands to its clients: a client cannot read contacts, send chat, or change
radio settings. This is the confused-deputy boundary and it MUST NOT be relaxed for convenience.

*Check:* the gateway's command surface contains no companion opcode; a client request for a contact list is
refused with the documented error.

**APP-M2.** Pairing MUST be a bearer token generated by the app, shown as a QR, stored in platform secure storage
and compared in constant time. It MUST NOT be written to `shared_preferences`, logged, or included in a
diagnostics bundle.

*Check:* the token's storage backend is the secure store; a diagnostics export contains no token bytes.

**APP-M3.** The listener MUST accept one client at a time. An authenticated session MUST NOT be displaced; a
second attempt gets `CLOSE(busy)`. An unauthenticated connection MUST be closed after 5 seconds and evicted
immediately when another arrives, so a local app cannot squat on the slot.

*Check:* three connection tests — busy on second authenticated attempt, 5-second timeout, immediate eviction.

**APP-M4.** A grant MUST be visible and revocable in Settings → Connected apps, naming the client and what it may
do. Revocation MUST take effect without restarting the app.

*Check:* revoke, then the client's next frame is refused.

**APP-M5.** The gateway MUST meter its own airtime under the operator's policy and MUST NOT assume the other end
meters. Two ends that both assume the other is polite is how a duty cycle gets exceeded.

*Check:* the airtime governor's unit tests; a policy change applies to the next send.

**APP-M6.** The gateway MUST run only when the user has enabled it and the radio is connected, and MUST end in a
reported failure state rather than an exception on a taken port or a secure-storage error.

*Check:* `GatewayRunState` transitions for all four states; a taken port produces `failed` with a message.

---

## 14a. N — Cross-cutting requirements the feature groups assume

These are the requirements that no single feature owns and every feature depends on. They were missing from the set
until a breadth review asked what a complete specification needs beyond the feature list.

**APP-N1.** Schema versioning and migration. Every store MUST carry a schema version, and a migration MUST be
specified as a sequence with a defined failure point. The plaintext-to-encrypted migration (APP-E1) is the first one
and the hardest: read plaintext, write ciphertext, verify a sample decrypts, then delete plaintext — in that order, so
a crash at any step leaves a readable store. A migration MUST be idempotent and MUST NOT run twice on the same data.
A downgrade (older app, newer store) MUST refuse to open the store and say so rather than corrupt it.

*Check:* a migration test that kills the process between each step and asserts the store is readable afterwards; a
downgrade test that opens a v2 store with a v1 reader and gets a refusal, not a crash.

**APP-N2.** One error catalogue. Every refusal the app can show MUST come from one table mapping a cause to a
user-facing sentence and a next action. The firmware's `ERR_CODE_*` values, the transport's failures and the app's own
refusals MUST all resolve through it. A raw code MUST NOT reach the user, and a refusal MUST NOT be a bare "failed".

*Check:* a test that every `ERR_CODE_*` the codec can decode has a catalogue entry; a grep test that no screen
interpolates a numeric code into user text.

**APP-N3.** One time model. The app MUST distinguish three clocks and never mix them: the phone's wall clock, the
radio's clock (which can be unset or wrong), and a message's own timestamp. A radio clock that is unset MUST be
flagged, not trusted. Every displayed time MUST say which clock it came from when the two disagree by more than a
minute.

*Check:* with the radio clock unset, a received message renders "time unknown" rather than a 1970 date; a place's
expiry uses the sender's timestamp clamped to now, per the places spec.

**APP-N4.** Degraded modes are specified, not discovered. Four states MUST each have defined behaviour and copy:
radio disconnected, storage full, clock unset, battery critical. In each, the app MUST remain usable for what still
works and MUST say what does not. "Storage full" MUST NOT silently drop the oldest message without telling the user.

*Check:* one test per state asserting the banner, the disabled controls and that no data is lost silently.

**APP-N5.** Export format is a format, not a button. The encrypted export (D8.8) MUST specify its container: a version
byte, a KDF identifier and parameters, a salt, a nonce, and the ciphertext with an authentication tag. It MUST be
self-describing so a future version can read it, and it MUST refuse a wrong passphrase with a clear message rather
than a parse error.

*Check:* a golden export fixture decrypts with the documented parameters; a wrong passphrase produces the refusal, not
a crash; a v1 reader refuses a v2 container by version byte.

**APP-N6.** Performance budgets. Cold start to a usable channel list MUST be under 2 s on the reference low-end
device, and a 500-message thread MUST scroll without dropped frames. These are budgets, not aspirations: a change that
breaks one is a regression.

*Check:* a startup timing test on the reference device; a scroll jank measurement on a 500-message fixture.

**APP-N7.** Interop matrix. The app MUST state which firmware families and versions it supports and what degrades
outside them. The capability probe (APP-A4) is the mechanism; the matrix is the promise. A feature that needs a fork
the user does not have MUST be shown as unavailable with the reason, never as broken.

*Check:* the matrix exists as data, and a test asserts every capability id in the probe appears in it.

**APP-N8.** Notification permission is a flow, not a flag. On Android 13+ the app MUST request `POST_NOTIFICATIONS` at
the moment a notification would first be useful, MUST explain the consequence of refusal, and MUST keep working with
in-app banners when refused. A refusal MUST NOT disable the foreground service's own notification.

*Check:* a test that refusal leaves the service notification present and the in-app banner shown.

---

## 15. Traceability

| Requirement | Decision or evidence |
| --- | --- |
| A1–A3 | Plan §9.10 defect 4; `MTU ≥179` measurement; `reconnect_policy.dart` |
| A4, N7 | Capability probe; firmware version codes |
| A5 | `0x91` undecoded; unknown-type counting |
| A6, A7 | D8.15 orphan-command split |
| A8 | `channel_crypto.dart:68`; `channels_screen.dart:345-352` vs `:378`; `SHA-256("#emergency")[0:16]` |
| B1–B4 | Block spec; `BaseChatMesh.cpp:249-329` auto-add scope |
| C1–C4 | `companion-behaviour.md:128-136` four failed-state rules |
| D1–D3 | `BaseChatMesh.h:9` `MAX_TEXT_LEN` 160; `:766-773` truncation |
| E1, E3 | `chat_store.dart:18-21` plaintext; `res/xml/backup_rules.xml` + `data_extraction_rules.xml`, manifest `:51-52` |
| E2 | D8.6 retention |
| E4, E5 | D8.7, D8.9 |
| E6, E7 | Block spec §5 (search surface); D8.8 (export) |
| F1–F3 | Block spec; `BaseChatMesh.cpp:334-367` |
| G1–G4, G6 | D8.2, D8.16; `place-report-encoding.md:43-51`; `meshmore-places-spec.md` §3–§7 |
| G5 | D8.18; bundled basemap assets |
| H1–H4 | D8.4, D8.5, D8.17; `places-sos-prior-art.md:118-120`; `meshmore-sos-spec.md` §7, §9; `meshmore-telemetry-coverage-spec.md` §6–§9 |
| H5 | D8.23; `MyMesh.cpp:387-390`; `MediaMeshCore.h:880` |
| H6 | D8.24; `CompanionNotificationPolicy.h`; `Notifications.cpp:131-155` |
| I1–I3 | AV1 decision; `MyMesh.cpp:1315-1329` flood refusal |
| J1–J3 | D8.13; meshcore-open `ChannelNotificationMode` |
| K1–K3 | zero `Semantics(` in `lib/screens`, eight in `lib/`; `main.dart:264-268` |
| L1, L2 | `lib/maps/maps_self_test.dart` report pattern |
| M1–M6 | `meshmore-sns-architecture.md` §2.1–2.4, §7; `lib/meshcore/gateway/gateway_service.dart:20-100` |
| N1 | `chat_store.dart` `mm.chat.v1`; D8.8 |
| N2 | firmware `ERR_CODE_*` set; `meshmore-sns-protocol-coverage.md` |
| N3 | `companion-behaviour.md` §5 (radio clock); places spec §8 |
| N4 | D8.21 permission fallbacks; D8.6 retention |
| N5 | D8.8 passphrase export |
| N6 | reference low-end device class (plan §9.14 M1) |
| N8 | Android 13 `POST_NOTIFICATIONS`; D8.20 |

---

## 16. What this document does not specify

Radio configuration screens beyond the nine commands D8.15 schedules; the voice codec's parameters; the
XB/XR client; firmware changes; the choice of AV1 encoder implementation; the retention numbers' empirical
basis. Those live in the plan or are measurement items.

**Four measurements still gate the numbers in this document**, and each is marked where it appears: AV1
encode cost on low-end hardware (I1–I3 pacing), `meshbench` determinism under an external driver (C2
timeouts), bulk-transfer reliability (I2), and collision behaviour at load (H4 pacing). Until they run,
the numbers here are best-practice defaults, not measurements — and the spec says so rather than implying
otherwise.
