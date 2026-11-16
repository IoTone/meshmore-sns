# MeshMore — scope of record, 2026-11-04

This is the authoritative record of what MeshMore is going to be, what is changing in the app as it exists
today, and what is being built. It supersedes `meshmore-feature-plan.md` wherever the two disagree; the plan
document remains as the analysis trail, and `meshmore-feature-audit.md` remains the evidence trail.

Every entry is a decision taken on 2026-11-04 by the project owner, with the consequence stated. Entries
marked **[DAVID]** touch work that David owns — the original project, the skins, the XR client and the
Play Store release — and need his agreement before they change.

---

> **Entry point:** `meshmore-feature-register.md` holds the single feature list and the merged open-questions
> register. This document holds the decisions themselves.

## §1 Governance and ownership — read this first

- **This repository is David's project.** The app, the skins, the XR client and the store release are his.
  Scope is being set here; implementation ownership is not being reassigned.
- **David releases to the Play Store.** That makes store constraints requirements, not options.
- **David owns the XR client** (`meshmore-xr/`, 116 Kotlin files, 39,386 lines) — frozen in this scope, not
  abandoned.
- **David owns the skins.** All of them stay; every feature must work in all of them; the skins themselves
  need a correctness audit. **Amendment (2026-11-05):** the app now ships **eight** presets, because Studio Light
  (R115) was added on the owner's direction as the paper-ground counterpart of Studio. Every feature works in all
  eight, and the guards (`test/theme/skin_sweep_test.dart`, the a11y floor sweep's per-preset pass, the ratchets)
  enumerate eight rather than seven.
- **David's documentation and work must be read before any map/place/role design is finalised** — including
  the XR repo's 14 spec documents, the Java protocol port, and material outside this repo. That reading is
  queued, not done.
- **Anything AI-related that David has implemented stays and is kept current**; no new AI work is added, and
  anything AI-related that is not good gets cleaned up or removed.

---

## §2 The product identity

- **MeshMore is a personal messenger and a field-and-operations tool, primarily field operations.**
  It is *not* primarily "the platform other apps use", so the gateway is an integration, not a product surface.
- **Single user only.** No accounts, no organisation model, no role system. The unit is one person, possibly
  with several radios.
- **No accounts ever, and no cloud.** Identity is the radio's key. Anything social happens over the mesh.
- **Android first.** iOS later; keep it compiling with best-practice compatibility, do not invest in iOS
  testing now, and do not claim iOS support in the product.
- **Play Store release.** Terms and Conditions, a privacy policy, a data-safety declaration, a radio-free
  demo mode and a review-safe scope are therefore requirements.
- **Open source, MIT.** Users file issues; there is no crash reporting and no analytics. A link to the issue
  tracker lives in Settings.

---

## §3 Media — narrowed by evidence

- **Voice: recorded messages now, live PTT deferred.** Accepted on evidence: PTT needs 250 kHz while 19 of 26
  live presets are 62.5 kHz; it needs third-party fork firmware; it is unlawful in the EU at every bandwidth;
  no measured multi-hop voice success rate exists; FEC cannot protect live audio because parity arrives after
  the clip; and there is no direct-message binary carrier.
- **Images: in.** AV1-class codec only; the neural codec is ruled out by decode time (124 s for a 128-pixel
  photo on old hardware, 41 minutes at 576 px).
- **Files and bulk transfer: not this phase.** The honest framing when it comes is "an hour, and say so".
- **PTT is deferred, not cancelled.** It returns only behind a capability gate (`get radio2` = `rxtx`, preset
  ≥250 kHz) and is refused outright in EU presets.
- **The prerequisite for all of it is one encoder.** `CMD_SEND_CHANNEL_DATA` (`0x3E`, decimal 62) is declared
  in the app's constants and has no encoder; the inbound `0x1B` frame is already decoded and tested and has no
  consumer. That one encoder plus one dispatch branch is the whole distance to channel media.
- **Media is off by default on Public and `#public`, enforced at the send path, not in the UI.**

---

## §4 Maps, places and directions

- **All map work and visualisation stays in MeshMore, implemented cleanly and well.** Ten grid views already
  exist; the map stack is the app's own (tile cache, region packs, vector basemap, event layers, fetch gate).
- **Navigation itself links out.** A user shares a place; the receiving user taps "directions" and their own
  maps app takes over. No routing engine in this phase.
- **No shipping or hosting of map or routing packs.** Fetch from public sources on demand. The project does
  not become a tile distributor.
- **A pin is a broadcast message**, not a private object and not a shared mutable layer. Social = visible on a
  channel; nothing more.
- **A place is a first-class object**: name, type, description, optional photo, coordinates, precision,
  provenance, reporter, created-at, **time-to-live**, confirmations.
- **Creation is a long-press on the basemap.** No tap handler exists today, so this is real UI work.
- **No payments and no monetisation, ever.** "Place/POI-related work" is what was meant, not a paid tier.
- **Place tags are a good idea and should be extended creatively** — see §7.

---

## §5 What changes in the app as it exists today

Each item is an amendment to shipped behaviour. Ordered by user impact.

### Messaging

1. **Add inbound OS notifications.** Not present at all today; the only notification is the foreground
   service's persistent one. Per-channel and per-peer routing, tap-through, silent/visual-only mode.
2. **Fix the false "failed".** A message delivered before the app closed resolves to *failed* on restart.
   Persist in-flight sends with correlation and reconcile on reconnect; label genuinely unknown as unknown.
3. **Correlate `OK`/`ERR` to the command that caused it.** Today an unregistered command's `OK` can be credited
   to a pending channel send. The host twin already does this with a serialisation queue.
4. **Composer byte budget.** Live remaining-bytes against the active ceiling; no guard exists now.
5. **Encrypt local storage.** History and channel keys are plaintext `SharedPreferences`.
6. **Keep 250 messages for now, but stop silently truncating.** Export and per-peer threads now; archive later.
   Correctness first, architecture later.
7. **Per-channel notification bundle** — audio, haptic, OS, TTS independently. Only the TTS mute exists.

### Radio and device

8. **Two-phase commit and a revert sweep for stranding settings.** Frequency, bandwidth, SF, CR, TX power,
   path-hash mode. Today it is fire-and-forget and a stranding change cannot be undone from the app.
9. **Stop offering "Pinned" advert location, or make it real.** The firmware defines only NONE and SHARE, so
   "Pinned" does not pin. Either the firmware gains the value or the UI loses the option.
10. **State the Japan LBT caveat where the region is chosen**, and surface the "every node must match" warning
    at the point of change rather than in prose.
11. **Add a radio health readout** — duty cycle, airtime, queue depth, retries, last-heard per neighbour. The
    fragments exist; there is no single answer to "is my radio OK".
12. **Detect board and firmware, gate features by capability, and say "your firmware cannot do this"** instead
    of failing.

### Field operations (the primary product)

13. **Add position history.** The only history store today is battery; every map view plots the current fix.
14. **Add trail recording and GPX export.** In memory only today, lost on restart.
15. **Add geofences with hysteresis and arrival/departure cues.** Designed in `geofence-tracking.md`, nothing
    built; the sole "geofence" string in `lib/` is a region-preset suggestion.
16. **Add inter-node relationship** — "A is 400 m from B and closing". The exact limitation the geofence design
    opens with; all distances are currently "from me".
17. **Add SOS and check-in** — reserved type or a text convention, long-press with confirm, repeated sends
    until an answer. No design exists anywhere in the repo, so this is new design.
18. **Keep repeater/room administration read-only.** Show who repeats and path quality; no changes. Confirm
    first whether David has built anything here; if not, keep it out.
19. **Add operational export** — chat transcript, positions, alerts for a time window. Today only tool runs
    export (soak JSON, range CSV, bot report, diagnostics JSON).

### Maps and places

20. **Add a long-press handler to the basemap** and a place creation flow. Nothing can be created on the map now.
21. **Add the `Place` object and its store** — named, typed, described, optional photo, TTL, confirmations.
22. **Add a place layer to the street map**, tappable, with countdown badges and clustering once markers stop
    being sparse.
23. **Fix "Show on map" to offer directions**, not just a pin — an external directions URI to the user's maps
    app.
24. **Turn on region files or remove the claim.** `kRegionFilesEnabled = false` today; machinery exists with no
    published file. Fetch from public sources; do not host.
25. **Persist and surface position provenance** — device / phone / pinned / inferred / received — everywhere a
    position appears.
26. **Let users correct or confirm an inferred place.** Today the only action is dismiss.

### Protocol foundations

27. **Build the `0x3E` channel-datagram encoder and the inbound dispatch branch.** The single highest-leverage
    missing line in the codebase.
28. **Consume the "via" byte** on `0x84` and `0x1B` so radio2 traffic is observable. Two lines.
29. **Add a conformance suite for emitted frames** — golden vectors, the four ceilings, `path_len` unpacking.
    None of these are tested today and all fail silently.
30. **Lift `MeshCarryCodec` out of the gateway path** so the app's own send path can send raw/binary/rawpacket.
31. **Keep the gateway, finish it and freeze it.** Published L2 v1 with vectors, a release-signed Binder
    handoff test, a UI statement that it serves only while MeshMore runs, a watchdog exit, a bounded queue.
    *(Superseded 2026-11-05 — §12 D10.1. Kept as the record of what was decided on 2026-11-04 and why.)*
32. **Do not build a fourth protocol implementation by accident.** Dart, Java and Kotlin all carry frame logic;
    decide the shared-core policy before adding protocol surface.

### Trust, legal and store readiness

33. **Add Terms and Conditions.** R10 is unbuilt and the placeholder was deliberately removed.
34. **Add a privacy policy and a Play data-safety declaration.** **Corrected 2026-11-04:** "nothing leaves the
    device" is false while the map fetches tiles or packs from a third party — the request discloses IP and the
    area being viewed, and Play counts that as *collected*. The policy states what stays local (messages, contacts,
    places, history, keys) and names the two things that leave: the radio, and map fetches. Either ship packs so the
    second is removable, or declare it.
35. **Add an issues link in Settings** in place of crash reporting.
36. **Add a radio-free demo mode** for store review and evaluation.
37. **Audit every preset for correctness** and keep all of them; every feature must work in every preset the enum holds, which is eleven as of
    2026-11-09 (D11.6 withdrew Studio Light, and four LDMUX looks joined).
38. **Repair the documentation set** — the requirement numbering, the "Future" section and the contradictions
    named in the audit.
39. **Add a block action, an in-app report action and first-use terms acceptance.** Play's UGC policy asks for
    "robust, effective and ongoing" moderation *including* in-app reporting and blocking; it does not ask for
    screening before publication. A block is keyed by the full 32-byte public key and hides the key on every
    surface. It cannot stop the radio receiving, relaying or storing a packet, and the copy must say so.
    See §7 for the honest limits and the prior-art position.

---

> **Ordering note, 2026-11-04:** this sequence and the master plan's §9.6 disagree in places (places before media
> here, media before places there). §9.6 is the scheduling decision because it was written against the measured
> dependencies; this list remains the product-level grouping. Where they differ, §9.6 wins.

## §6 What gets built, in dependency order

1. **Foundations** — `0x3E` encoder + inbound dispatch; command correlation; encrypted storage; conformance
   suite. Nothing above this is safe until these exist.
2. **Messenger correctness** — notifications, false-failed fix, composer budget, per-channel notification
   bundle, history export and threads.
3. **Radio safety** — capability detection, two-phase commit and revert, health readout, the "Pinned" fix.
4. **Place system** — long-press creation, `Place` object with TTL, place layer on the map, share as text,
   directions handoff, correction and confirmation.
5. **Media** — channel images via an adopted registered type, then voice messages (VE3, ≤20 s, off on Public).
   Media attaches to places first, because a place with a photo is the compelling combination. **The block,
   report and terms surfaces ship in the same release as the first photo path** — a photo path without them is
   not shippable under this scope.
6. **Field operations** — position history, trail and GPX, geofences and arrival cues, inter-node relationship,
   SOS and check-in, operational export.
7. **Store readiness** — Terms, privacy policy, data-safety declaration, demo mode, issues link.
8. **Parked or later** — PTT behind a capability gate, on-device routing, bulk transfer, TAK/MQTT host-side
   bridges, AI.

---

## §7 New requirement — map items with a short life

**The requirement as stated:** users can create an item on the map with a photo or a description, and the item
has a short, explicitly-not-long time-to-live.

**Why the TTL is the right instinct.** A field map that accumulates unverified pins becomes a lie: the water
source is dry, the bridge is repaired, the hazard is gone. A short TTL makes every pin a *report* with a
timestamp instead of a *fact* with no date. It also removes the deletion problem — nothing needs removing
because nothing persists.

### The item model

| Field | Notes |
| --- | --- |
| `id` | Deterministic from reporter key + coordinates + type, **excluding time** (D8.2), so the same report from two paths merges and a renewal keeps the id |
| `type` | Hazard, water, fuel, medical, rally/meeting, viewpoint, camp, "look here", custom. The type is what makes it actionable |
| `name` | Short, ≤32 bytes |
| `description` | ≤160 bytes; the honest default is one sentence |
| `photo` | Optional reference — a content hash plus a transport hint; the bytes ride the media path once it exists |
| `lat` / `lon` / `precision` | Precision is a user choice; grid-snapping is the privacy default |
| `provenance` | Device GPS / phone / pinned / received / inferred |
| `reporter` | Public key where known; channel text can only carry a name, which is spoofable |
| `created_at` | The radio's clock, plus a "clock was unset" flag |
| `ttl_s` | **Short by default.** Proposed presets: 1 h, 6 h, 24 h, 72 h. Hard ceiling 7 days |
| `confirmations` | Count of distinct reporters who confirmed it, and refutations |
| `expires_at` | Derived; the UI shows a countdown, not a date |

### Decisions taken on this requirement (round 7)

- **Presets 1 h / 6 h / 24 h / 72 h, hard ceiling 7 days.** Decided.
- **A place photo does not travel with the report.** Text first; the photo is a reference fetched on demand.
  Decided.
- **Expiry is final.** An expired item moves to a local history list and nowhere else; there is no "keep past
  TTL" action. Decided. If someone wants the world to know a place is still valid, they renew it deliberately
  as a new report.

### TTL rules

- **Expiry is computed from the sender's timestamp, and the receiver clamps it.** A clock that was unset must
  not create an immortal or already-dead item; clamp to "now" with a flag.
- **Renewal is a re-broadcast**, not a mutation. A renewed item is a new report with the same deterministic id
  and a new timestamp. That keeps the wire stateless and the seen-table happy.
- **Expired items disappear from the map layer and survive in a local history list** until the user clears it.
  Disappearing without trace loses the "we already checked that" knowledge.
- **A local "keep" only pins the row on that device and does not extend the wire TTL.** The item still expires on
  the map for everyone; a keep changes what the user sees in their own history, never what a receiver computes.
  If the user wants others to know a place is still valid, they renew it deliberately as a new report.
- **Rate limits per reporter**, and TTL bounds enforced at the send path. A node that posts twenty pins in a
  minute is the failure mode that makes a channel unusable.
- **The photo does not extend the TTL.** A photo is expensive in airtime; the item should be useful as text
  first and the photo should be fetchable on demand.

### Wire plan — text first, binary second

- **Text convention first**, because it works on any channel, through any number of hops, on any client, and
  inbound parsing already resolves decimal coordinates at 0.95 confidence.
- **The grammar is `[PLACE]<lat>,<lon> <label> [TTL:<duration>]`** in one message, 6 decimal places with a
  mandatory point, label ≤ 60 characters, TTL parsed only from the end and defaulting to 24 h
  (`place-report-encoding.md:43-71`). The suffix is safe **because** the tag is new: no existing client parses
  `[PLACE]`, so it cannot corrupt a label the way a `[WAY]` suffix would.
- **What the text does carry, and what it still cannot prove:** the type token and the TTL are now in the
  grammar (D8.2) as an optional closed-set token immediately before the anchored TTL. The id is derived
  (`sha256(pubkey ‖ latE6 ‖ lonE6 ‖ type)`, first 8 hex), **not transmitted**, so a receiver recomputes it. On
  channel text there is no public key to derive from — the id uses the sender's name and is marked unkeyed.
  That is the one thing the text form cannot fix, and the spec says so rather than implying a verified identity.
- **Binary second**, on the channel-datagram path once `0x3E` exists, with the text announcement as the
  fallback so a non-MeshMore client still sees something readable.
- **Never a new top-level payload type.** Channel datagram with a registered group-data type, or text.
- **Salt every resend.** The seen table hashes type plus payload and drops identical repeats, so a renewal or a
  retry must differ by at least one byte.

### What this makes possible — and what it makes impossible

- Possible: "hazard here, expires in 6 h", "water at this well, expires in 2 days", "rally point, expires in
  12 h", "look at this, photo attached, expires in 1 h".
- Impossible by design: a permanent map of everything; a curated POI database; a place that outlives its
  reporter's knowledge. Those are the traps the TTL exists to avoid.

### The fun angle — exciting capabilities that also do work

**Decided 2026-11-04: parked, not cut.** Treasure hunts, mesh weather on the map and ghost-trail replay stay in the
register as open ideas with no milestone slot. They are not promised in this phase and not removed from the design
space; each would cost airtime before the four defects are fixed.

The owner's framing is explicit: **fun means exciting functionality, not UX garnish.** Candidate capabilities,
each tied to work already planned, none of them decoration:

- **Place reports with a life** — the TTL model above. A map that forgets is a map you can trust.
- **Confirm and refute** — a pin gains or loses weight as independent reporters agree. "3 confirmations" is a
  social signal that costs almost nothing on the wire and turns the map into a consensus instrument.
- **Place echoes** — the existing place-inference engine already mines place names out of channel chatter. A
  place report can be *seeded* by what people are already saying, so the map fills itself without anyone
  deliberately pinning.
- **Photo first, words second** — a photo pinned to a place, fetchable on demand, with the description as the
  fallback when the photo cannot be fetched. This is the combination that makes images worth their airtime.
- **Time-boxed treasure hunts / challenges** — an item type whose TTL is the game: find it before it expires.
  Costs nothing beyond the item model and gives the app a reason to be opened.
- **"Who can hear me" experiment** — a deliberate, bounded broadcast that reports back who received it. The
  trace-path tool already measures this; turning it into a shareable, time-boxed result is a fun framing of a
  serious capability.
- **Distance and closing-trend between two nodes** — "A is 400 m from B and closing". Genuinely exciting in the
  field, and it is the geofence design's opening limitation.
- **Ghost trail** — replay where a node has been over the last hours, with confidence fading. Needs the
  position history that does not exist yet.
- **Place-ledger export** — the after-action record: what was reported, by whom, when, and whether it was
  confirmed. This is what makes the app defensible in a debrief.
- **Mesh weather and microclimate on the map** — already computed from channel text; promoting it onto the
  street map as tappable bubbles is a small change with high delight.
- **Radio-health score with a reason** — "good, because 6 neighbours heard in the last 10 minutes" beats a
  percentage. Diagnostics that read like a sentence.

**What each candidate actually costs**, so the parking decision is informed rather than sentimental. Airtime is
the scarce resource; a candidate that spends it needs a reason.

| Candidate | Airtime cost | New data needed | Blocked by |
| --- | --- | --- | --- |
| Place with a TTL | ~0.35 s per report | None — the places spec | Nothing |
| Confirm and refute | ~0.35 s per confirmation | Wire grammar for a confirmation | Open design row |
| Place echoes | **Zero** — it mines text already received | A parser over the channel timeline | Nothing |
| Photo first, words second | 20–60 s per photo at AV1 tier | The `0x3E` encoder and the fetch ladder | D8.22 is closed; the encoder is next |
| Treasure hunt | Zero beyond the item model | Nothing — a TTL and a type | Nothing |
| "Who can hear me" | 1 ping per 30 s while running | Nothing — the coverage spec | Nothing |
| Distance and closing trend | **Zero** — computed from received positions | Position history | Position history (TODO) |
| Ghost trail | Zero to compute | Position history plus a replay UI | Position history (TODO) |
| Place-ledger export | Zero on air — a local export | The ledger query | Nothing |
| Mesh weather on the map | Zero to compute | The existing text parser promoted to the map | The map layer |
| Radio-health score | Zero | The telemetry decode | Nothing |

**The pattern in that table is the finding:** nine of eleven candidates cost nothing on air, and only two — the
photo and the coverage ping — spend airtime. So "parked because it would cost airtime" is true of exactly one
of them. The real blockers are *data that does not exist* (position history) and *work not done* (the `0x3E`
encoder). That is a cheaper parking decision than it looked, and it is worth revisiting when the four defects
are fixed rather than treating "fun" as a budget line.

---

### Blocking — what the app can enforce and what it cannot (new requirement, round 7)

**Researched 2026-11-04 and rewritten the same day after checking the firmware.** There is no per-sender block
list in any firmware read. Three consequences:

- **The block lives in the app.** A keyed store, keyed by the full 32-byte public key and never by display name,
  filtered on every surface that renders content: channel timeline, DM list, threads, search, map places and the
  app's own notifications. Nothing on the radio enforces it.
- **The radio keeps working regardless.** A blocked key's channel messages still arrive, are still relayed for
  other people, and are still written to the device's own message store. The device alert engine may still buzz.
  The honest block is three actions — the app-side filter, contact removal, and the keymind `dm.one_key` consent
  gate where that fork is present — and the copy names what each one cannot stop.
- **The store obligation is the surfaces, not a filter.** Play's UGC policy asks for "robust, effective and
  ongoing" moderation including in-app reporting and blocking; it does not ask for pre-publication screening. So
  first-use terms acceptance, an in-app report action and a real block action are the requirement. Blocking and
  reporting stay separate actions in the UI: reporting asks someone else to act, blocking acts locally.

**Prior art is thin.** No client in the ecosystem ships a per-sender block: meshcore-open has per-*channel*
notification modes only (`enum ChannelNotificationMode { all, mentionsOnly, muted }`), and meshcore-team and
meshcore-sar have no contact-level block at all. MeshMore would be first, so there is no interop to inherit and no
behaviour to copy — only the key discipline to keep. The room server does have a real per-key ban
(`RoomAccessPolicy.h:73-99`, `isBanned`/`addBan`/`removeBan`, full 64-hex key, applied before password checks), but
no companion command reaches it.

**Decided 2026-11-04:** a blocked key's messages are **hidden and discarded** — not rendered, not stored, and rows
already on the device for that key are deleted when the block is set. Unblocking restores nothing, and the copy says
so before the block is applied. Blocked nodes are **counted, not vanished** ("3 hidden"), excluded from coverage
results while still counted as reception evidence.

**The feature spec is `meshmore-sns-block-spec.md`** — three actions, the keyed store, the ten surfaces, the state
machine, the required copy and the ten tests.

**What the honest block cannot promise**, and the UI must say: channel messages still arrive and are stored on the
radio; blocking is local to this device and tells nobody else; a blocked node can still hear your broadcasts. Do
not present blocking as moderation — it is a one-way, per-device filter.

## §8 Explicitly out of scope, now decided

- **No accounts, no cloud, no analytics, no crash reporting — for MeshMore.** This policy governs the MeshMore
  companion app. David's XR client is his product with its own policy, and its design assumes a server-backed audio
  profile, cloud STT/TTS and a private temp-URL proxy. **The boundary is now explicit:** MeshMore's privacy policy
  and store declarations describe MeshMore only; nothing in MeshMore talks to a server, and the XR client's
  server dependencies are not inherited by it. Where the two share a store or a protocol convention, the shared part
  must be the local one.
- **No payments, no monetisation, no paid packs, no subscriptions.**
- **No role system, no team/org model** — a single user with tags and favourites.
- **No repeater or room-server configuration in the phone app** — read-only visibility at most, and only if
  David has built something there.
- **No routing engine in this phase** — navigation links out.
- **No hosting or shipping of map or routing packs** — fetch from public sources.
- **No live PTT in this phase** — recorded voice messages only.
- **No bulk file transfer in this phase.**
- **No new AI work** — keep what David built, clean up what is not good, no additions.
- **No lobospeak in MeshMore** — separate product; mine it for ideas only.
- **No XR client work** — frozen; David owns it.
- **No KISS modem, Meshtastic bridge or public map upload** in this phase.
- **No eighth image format** — adopt a registered type or join an existing one.
- **No binding to a firmware fork** — stock companion protocol, any board; at most one or two forks, and only
  for a capability stock firmware cannot provide.
- **No firmware baseline or named device list** — support every device that speaks the companion protocol, gate
  by detected capability.

---

## §9 Open questions still unanswered

**Superseded 2026-11-04:** the single register is `meshmore-feature-register.md` §9. This section is kept for the
record; items 7 and 8 were decided in round 8 (§11), and the rest are carried there.

1. **Place report rate limit** — how many per hour per node before the send path refuses?
2. **Directions handoff targets** — which apps to offer first: OsmAnd, Organic Maps, Apple, Google, a generic
   `geo:` URI?
3. **Which one or two forks**, if any, get support, and for which capability.
4. **Skins correctness audit** — what counts as broken: contrast, layout, missing states, or all three?
5. **Where David's documentation lives** — the XR repo's 14 specs, the Java port, and anything outside this
   repository. Reading is queued.
6. **AI cleanup** — what "not good" means in practice, so removal is a defined decision and not a taste call.
7. **What a block must suppress, and what it cannot** — the radio still receives, relays and stores a packet;
   only app surfaces can hide it. The copy depends on this answer.
8. **What a block does to an already-queued message** — the offline queue is device-side and a hidden slot
   cannot be reclaimed by the app.

### Decided in round 7 and now closed

- **TTL presets and ceiling** — 1 h / 6 h / 24 h / 72 h, 7-day ceiling.
- **Photo policy** — text first, photo fetched on demand.
- **Keep past TTL** — no; expiry is final.
- **SOS and inter-node relationship** — both in this phase.
- **Blocking is app-side, keyed by the full 32-byte public key, applied on arrival and on contact-list replay.**
  No firmware has a per-sender block or mute; contact removal is the only radio-side action and it expires at the
  next advert. The copy names what a block cannot stop (reception, relay, device storage, the device's own buzzer).

---

## §10 Documentation debt this creates

- `meshmore-feature-plan.md` — its List A/B are now partly superseded; keep it as the analysis trail and point
  here for the decisions.
- `meshmore-feature-audit.md` — unchanged, still the evidence trail. Its §7 "not covered" list now includes
  David's documentation.
- The spec's requirement numbering, its "Future" section, its document map and its contradictions — to be
  repaired as a separate pass, recorded in `meshmore-feature-audit.md` §5.

---

## §11 Round 8 — decisions taken by investigation, 2026-11-04

Each of these was an open question in the register. Decided here so work can start without another meeting; each
carries its evidence and its reversal cost. Where the decision is a best-practice call rather than an evidence
finding, it says so.

**D8.1 Broadcast media scoping — inherit the radio's own flood scope.**
An unscoped flood is **allowed by default**: the repeater gate only fires when the wildcard region carries
`REGION_DENY_FLOOD` and no regionless scope or channel bypass applies (`simple_repeater/MyMesh.cpp:1184-1189`,
`:2826-2836`), with `flood_max_unscoped = 64` (`:3922`) and `flood_channel_data_enabled = 1` (`:3949`). So the app
does **not** invent a region concept. It shows the radio's default flood scope in the media send path, offers an
explicit unscoped send with a warning, and keeps **DMs and known channels as the default for broadcast media**.
The app cannot discover a repeater's configuration, so it never promises delivery on a broadcast. Reversal cost:
low — it is a default, not a protocol.

**D8.2 Place type and deterministic id — trailing tokens, id without time.**
Grammar: `[PLACE]<lat>,<lon> <label> [<type>] [TTL:<duration>]`, TTL last and anchored, type an optional closed-set
token immediately before it. The **id excludes time** — `sha256(pubkey ‖ latE6 ‖ lonE6 ‖ type)` truncated to 8 hex —
because the scope of record requires renewal to keep the id while changing the timestamp; a time bucket would make
every renewal a new place. Duplicate suppression is per id with the newest timestamp winning, so one row per
reporter per location per type. Reversal cost: medium — ids are persisted.

**D8.3 Composer budget — 160 bytes, not 176.**
Channel text is clamped to `MAX_TEXT_LEN` = 10 × 16 = **160 bytes including the `sender: ` prefix**, and the firmware
**truncates rather than rejects** (`BaseChatMesh.h:9`, `BaseChatMesh.cpp:766-773`). The composer counts 160 minus the
name prefix, and names the frame it counts: 160 text, 162 datagram blob, 176 BLE frame, 177 queue slot. Reversal
cost: low.

**D8.4 SOS timings — 12 sends, 10 beacons, 57 minutes, hard stop at 1 h.**
Amended 2026-11-04 when the full spec was written, because this decision's original parenthetical ("12 at 60 s
(12 minutes)… for 60 minutes") did not add up: 12 sends plus a 60-minute beacon would end at 72 minutes. The
prior art's engine (`SosEngine.h:27-32`) has `MAX_SENDS = 12` as a **total**, so the schedule is: first send
immediate, 11 more at 60 s (last at 660 s), then a beacon every 5 minutes at 720–3420 s, ten of them, hard stop
at 3600 s. Twenty-two packets in 57 minutes. Cancellation is explicit ("I'm safe") and sends one final
`[SAFE:<id6>]`. **Attribution is the correction this decision needed:** a channel ACK carries only a display
name, so it is shown as "claimed" and does **not** stop the beacon; only a direct-message ACK from a target
contact's key with a matching id does. A fix older than 1 h is not sent as a position — the alarm goes out in the
`NOFIX` form instead (reconciled with APP-H2). Reversal cost: low.

**D8.5 Check-in — one bounded send with a deadline, no radio feature.**
A check-in is a single message with a stated deadline; the app marks it overdue locally and notifies the user. No
radio-side timer exists and none is invented. Intervals 15/30/60 minutes. Reversal cost: low.

**D8.6 Retention — per category, oldest-first, visible.**
Text: keep until a 20 MB store cap. Places history: 30 days. Trail: 14 days. Media: 200 MB with manual pinning.
Eviction is oldest-first and the app shows what it dropped. Rationale: a field record is worth more than storage,
but silent loss is not acceptable. Reversal cost: low.

**D8.7 Identity replacement — treat a changed radio key as a new radio.**
If the connected radio's self key differs from the stored one, the app says so and offers a one-tap carry-over of
tags, favourites and blocks to the new key; history stays attached to the radio it came from. Nothing is silently
re-keyed. Reversal cost: medium.

**D8.8 Backup — exclude everything from Auto Backup; export manually.**
Keystore keys are non-exportable, so backing up ciphertext produces an unreadable restore. Set
`dataExtractionRules` to exclude app data from cloud backup and device transfer, and provide an encrypted export with
a user passphrase. Reversal cost: low.

**D8.9 Multi-radio — one active session.**
One radio owns the queue, the history and in-flight sends. Switching is explicit and stops the old session cleanly;
an in-flight send at switch time is reported as unknown, never as failed. Reversal cost: medium.

**D8.10 Directions handoff — generic `geo:` first.**
Offer `geo:<lat>,<lon>?q=<lat>,<lon>(<label>)` as the generic target, then OsmAnd, Organic Maps, Google Maps and
Apple Maps where installed. A place with no fix offers "copy coordinates" only. Reversal cost: low.

**D8.11 `dm.one_key` — expose it, keep consent as the default.**
Where the capability probe finds the CLI verbs, offer "Ask me first" as the default (the firmware default is 0 =
consent required) with a switch to "Allow anyone". Copy states what a refused stranger sees: a signed marker, not a
silent drop. Reversal cost: low.

**D8.12 Cross-device block sync — no.**
No radio-side record exists to share, so a block set on the phone does not travel to the glasses. Stated in the block
spec, not implied.

**D8.13 Mentions — name or `@name`, never a key suffix by default.**
A message is a mention when it contains the user's display name as a whole word or `@name`; key-suffix matching is an
opt-in. Rationale: four hex characters are not an identity, and suffix matching caused a live incident in the XR
client.

**D8.14 Channel key rotation — keep old records, label them.**
Changing a slot's PSK leaves existing history keyed to the old channel key; the app labels those records with the
old key's short hash rather than deleting or re-encrypting them. Nothing re-encrypts history on rotation.

**D8.15 The codec-complete commands with no UI — schedule these, refuse those.**
The audit lists them as "21" with slash-pairs counted as one item; the count is not worth arguing. What matters is
the split. **Schedule:** `set/getDefaultFloodScope` and `setFloodScopeKey` (needed by D8.1), `set/getAutoAddConfig`
(contacts behaviour), `getAdvertPath` and `sendPathDiscoveryReq` (node detail: "show route"),
`share/export/importContact` and `getContactByKey` (contact sharing as text or QR), `getAllowedRepeatFreq`
(read-only in device info), `reboot` (with confirmation), `setDevicePin` (Security settings), and
`sendLogin`/`logout`/`hasConnection` (a repeater session screen). **Refuse in the app:** `exportPrivateKey` and
`factoryReset` — a key export and a wipe belong on the radio's own UI, not behind a phone gesture — plus
`signStart/Data/Finish` and `sendAnonReq` until their semantics are documented. "Codec-complete but invisible" is how
a protocol surface rots.

**D8.16 Place report rate limit — 6 per hour per node, burst 2 in 5 minutes.**
A place message is ~90–120 bytes, roughly a third of a second of airtime at SF7/125 kHz, so the limit is about
channel politeness rather than cost. The failure mode the limit prevents is one node posting twenty pins in a minute
and making a channel unusable. Enforced at the send path, not the UI.

**D8.17 Coverage ping pacing — 1 per 30 seconds, 1 per area per hour, jittered.**
The app paces itself because no firmware-side reply cap was found in the companion or repeater code read; the
wardrive prior art paces by sampling every 5 m and weighting by age. Jitter avoids synchronised pings from several
phones in one place. A ping is a zero-hop advert plus `DISCOVER_REQ`; replies correlate on the 8-character ID.

**D8.18 Map privacy — the bundled basemap is the default; online packs are opt-in and disclosed.**
The app already ships a genuinely offline basemap (Natural Earth 110 m, 97 KB; GeoNames `cities15000.bin`, 812 KB,
CC-BY 4.0) and a disk-first tile stack from R61. So "nothing leaves the device" is **true by default** and false only
when the user turns on online packs. The privacy policy and the data-safety declaration say exactly that: bundled
data, no network; optional packs fetch from a named public source and disclose IP and the area requested. The
consent screen for enabling packs names the source. This resolves the compliance question without giving up the map.

**D8.19 Firmware OTA — status only in this phase.**
Read and display OTA state (`0x4A` with the status family); do not start an install until the queue-drain handling
exists, because an OTA session consumes the offline queue down to `OTA_RETAINED_OFFLINE_FRAMES` and the app currently
has no way to report messages lost that way. The full mOTA source flow (`0x4B` attach/enumerate) is deferred with the
same reason. Reversal cost: low, and it avoids a data-loss bug shipped as a feature.

**D8.20 Notifications on a locked screen — high importance, no full-screen intents.**
A separate notification channel per message class, `IMPORTANCE_HIGH` for the default channel so a heads-up appears on
the lock screen, and a dedicated SOS channel at high importance. No full-screen intents: the platform reserves those
for calls and alarms, and a mesh alert is neither. The foreground service's own notification stays ongoing and
undismissable while the link is up. Do-not-disturb is respected — the app cannot bypass it without policy access and
will not ask. Silence per channel is a channel setting, not a global switch.

**D8.21 Permission denial — every denial has a working fallback.**
Bluetooth scan/connect denied: the app opens in offline/demo mode with an explainer and one button to system
settings. Notifications denied: an in-app banner states what will not appear. Location denied: the map still works,
"my location" is unavailable and a manual pin replaces it. Permanent denial: deep-link to app settings, never a dead
end. The first-run screen offers the offline path as a first-class choice, not as an error.

**D8.22 The management-page collision — the app's first blob byte is irrelevant, so the row is closed.**
The register's open question was "which first blob byte avoids the management-page shape". Reading the
receive path shows the question cannot be answered as asked, and needs no answer.

`Mesh.cpp:1433-1438` short-circuits a `GRP_DATA` packet whose payload parses as a management page, **before
channel decryption**, so a colliding datagram is routed as management and never delivered as channel data. But
`validPage(pkt->payload, pkt->payload_len, true)` reads the magic from `payload[0..2]`
(`ManagementReport.h:120-127`: `(magic & 0xffffff) != 0x52474d` → the bytes `M`,`G`,`R`, then a version byte
of `'1'` or `'2'`). For a **normal** channel datagram the payload layout is `[channel_hash(1)][MAC(2)]
[ciphertext…]` (`Mesh.cpp:1443-1444`, `Packet.cpp` keeps `transport_codes` out of `payload`), so:

- `payload[0]` is the **channel hash**, derived from the channel secret — the app does not choose it.
- `payload[1..2]` is the **2-byte HMAC** of the ciphertext — the app does not choose it either, and cannot
  predict it without reimplementing channel encryption.
- The app's blob begins at `payload[6]` (`1 + 2 + [type_lo, type_hi, len]`), **past every byte `validPage`
  inspects for the magic**.

So no blob byte can affect the collision. What remains is a probabilistic false positive requiring the magic
`MGR`, a version byte in {`1`,`2`}, a payload length in `{131,147,163,179}` (because `floodSize` forces
`len ≡ 3 mod 16` and `MAX_PAYLOAD = 179`), five specific zero bytes at `payload[78..82]`, and up to 15 zero
trailing bytes — roughly 2⁻⁹⁶ per datagram, and the failure mode is a **silent drop of one datagram**, not
delivered garbage. It cannot be engineered away from the app side without replicating AES-CBC plus HMAC in
Dart and pre-checking every send, which buys nothing measurable.

**Decisions taken:** (1) **the app MUST NOT chase a "safe first blob byte"** — there is none to chase, and a
documented rule to the contrary would be a false comfort; (2) **channel datagrams are therefore not claimed
reliable**, and the places spec's text-first rule stands for that reason too; (3) **a resend salts the
plaintext**, so a colliding send and its retry are independent events.

**The type value, which is the real half of that row.** Unknown `data_type` values are **not dropped**:
`BaseChatMesh.cpp:602-616` reads the u16 type, checks only `data_len <= available`, and forwards the blob to
`onChannelDataRecv`, so no radio-side registration is needed for reception. Registration matters for the
social contract, not the wire. The registry's own document (`docs/number_allocations.md`) says to build in the
`FF00–FFFF` dev band and request an allocation before publishing; free space is `0150–FEFF`. So: **develop on
`0xFFxx`, request a numeric allocation in `0x0150–0xFEFF` before the Play release, and do not use an ASCII
mnemonic** — every mnemonic type in the field (`VC`, `VT`, `SS`, `AE1C`) is unregistered, which is precisely
how `0x5643` became a de facto standard with no registry row. The channel-media type stays `0x5643` for
interop; app-data takes its own allocated number.

**D8.23 The emergency channel's key is *derived from its name*, so the convention is real and the key is public by construction.**
Corrected same day: an earlier version of this decision called `EMERGENCY_CHANNEL_SECRET` a "hardcoded secret" and
stopped there. It is not a magic constant. It is exactly `SHA-256("#emergency")[0:16]` — byte for byte
(`MyMesh.cpp:387-390`: `e1 ad 57 8d 25 10 8e 34 48 08 f3 0d fd aa f9 26`; computed
`e1ad578d25108e344808f30dfdaaf926`). Two independent forks reach the same key by different routes, which is what
makes it a convention rather than one fork's choice:

1. **keymind hardcodes the bytes** (`examples/companion_radio/MyMesh.cpp:387-390`).
2. **wadamesh-tak derives them from the name** — `resolveAliasKey` (`src/helpers/MediaMeshCore.h:880`) replaces an
   app-derived key with the name-derived one, so `#r2-emergency` and `#emergency` land on the same 16 bytes, and a
   custom PSK or a 256-bit key is kept as-is.
3. **the app already implements the derivation**: `channelPskFromHashtag` (`packages/meshcore/lib/src/crypto/channel_crypto.dart:68`)
   is `SHA-256(utf8(tag))[0..16]`, hashing the tag **with** its leading `#`, and its own documented vector
   (`#test` → `9cd8fcf22a47333b591d96a2b848b73f`) reproduces exactly. So typing `#emergency` as the tag in the
   existing "Key derived from the tag (sha256)" PSK source yields keymind's exact secret — no new crypto code.

Three consequences, corrected from the earlier text:

1. **The key is public because it is computable from the name, not because someone published a constant.** Anyone who
   knows the channel is called `#emergency` can derive its key. An SOS on it is readable by anyone in range with the
   firmware — for an emergency broadcast that is the point, not a flaw. But no surface may call it private or encrypted.
2. **The radio performs one delayed repeat on its own.** A received **zero-path flood** on the channel is held and
   re-sent after `EMERGENCY_CLIENT_REPEAT_HOLD_MS = 120000` plus up to 15 s jitter, with a 63-entry key table
   (`:350-354`, `:2253-2285`). Joining one seeds a notice — "#EMERGENCY: This is an emergency channel. Do not use for
   testing or small talk." — sent with `notify=false`. The name match goes through the alias parser, so a hashtag alias
   whose tail is `emergency` also qualifies (`isEmergencyNoticeChannelName`).
3. **SOS defaults to `#emergency` when the radio has the channel, and offers a private channel or DMs as the
   alternative.** Reach is the whole reason to raise an alarm. The app **does not create the channel silently**: that
   consumes a radio channel slot and puts a public channel in the user's list unasked. It offers a one-tap "add the
   emergency channel" whose copy states the key is public and what a slot costs. Revised from the earlier text, which
   left creation entirely open.

**D8.24 SOS does not drive the radio's alert engine — it offers the engine's own rules, narrowly.**
The device-side alert engine (`CompanionNotificationPolicy.h`) is **receive-side only**: its `Selector` matches
`kind` (`All`/`Contact`/`Channel`), a key and a `when` (`Any`/`Online`/`Offline`), with no text matching at all. So an
**outgoing** SOS cannot make its own radio buzz — the engine fires on what arrives. What the app *can* do is set the
rules that make a **responder's** radio buzz without their phone. That path already exists: `handleNotificationCommand`
(`Notifications.cpp:131-155`) parses `set notify.<selector> …`, reachable through `CMD_RUN_CLI_COMMAND 0x42`.
Decisions: expose a **narrow whitelist** of notify commands through a typed API, never raw CLI; offer "buzz for
#emergency" as a one-tap setting; and **do not expose the `remote` field (`FRemote`)** by default, because it lets a
contact reconfigure the radio's alerts over DM — "contact-only permission, never a wildcard" is the firmware's own
warning (`CompanionNotificationPolicy.h:70`). Also honest: a `channel:` rule fires on *every* message on that channel,
so "buzz only for SOS" is not expressible.

**D8.25 Place confirmations get a text convention — key-bound where a key exists, "claimed" where it does not.**
No prior art exists for votes on mesh places; the nearest material is waypoint transport, which has no tally. A
confirmation is cheap and worth having, so it gets the same shape as the other reply tags:
`[CONFIRM:<id8>] <callsign>` and `[REFUTE:<id8>] <callsign>`, where `<id8>` is the place's 8-hex id. Rules: count once
per key per id; a confirmation arriving as a **direct message** is key-bound and counts fully; one arriving as
**channel text** carries only a name and counts as "claimed" — the same attribution rule as the SOS ACK. A
confirmation **must not extend the TTL**: it is weight on the pin, not a renewal. Display at most five confirmations
and count the rest; never relay a confirmation. Reversal cost: low, it is text.

**D8.26 Request-slot ordering — user intent beats background polling, and nothing is silently pre-empted.**
The mechanism is not "one pending request" but one **live** request plus eight remembered `(peer, tag)` guards
(`CompanionDelayedReplies.h:16-18`): kinds `Login`, `Status`, `Telemetry`, `Discovery`, `Binary` contend for the live
slot, while `Trace` has its own guard path and does **not** take it. A duplicate `Login` to the same peer while one is
held is refused. There is no priority in the firmware, so order is the app's decision. Decided: background telemetry
polling **yields silently** (does not queue); a user-initiated request **waits with a visible state**; a user-initiated
login may **abandon a background request** (`abandonRequest()` exists) but must never abandon a user-initiated one.
No silent pre-emption — a dropped request that the user asked for is a bug the user cannot see.

**D8.27 The second radio profile is reported, never written (2026-11-08).** A two-profile radio splits one
antenna's transmit time between two channel configurations and tags every received frame with the profile that heard
it (`0xA0` primary, `0xA1` second, on `0x1B` and `0x84`). The companion protocol has **no command that sets or reads
a second profile's parameters** — the only mentions of the profile in `packages/meshcore/lib/src/codec/frame_codec.dart`
are the two receive tags — so a staged switch through `radio_config_transaction.dart`, which the residue row asked
for, could not be staged or reverted even with a screen in front of it. Decided: the app follows the tag, says when
a frame was last heard on the second profile, and states the cost beside it (96–99 % of the radio's transmit time,
measured over 100 packets), and offers no switch. Silence reads "nothing heard this session", never "one profile",
because a quiet second profile looks exactly like none. What would change the decision: a firmware that publishes a
command for the second profile's parameters, at which point the switch inherits the primary's single-use revert and
this row's cost line stays as the warning on it.

**Raised to full spec depth 2026-11-04:** `meshmore-sos-spec.md`, `meshmore-places-spec.md` and
`meshmore-telemetry-coverage-spec.md`. Each carries its data model, state machine, exact schedule or algorithm,
required copy, a ten-test list, and an explicit "what this does not do". The depth template is
`meshmore-sns-block-spec.md`.

**What is still open after this round:** AV1 encode cost on low-end hardware, `meshbench` determinism under an
external driver, and the bulk-transfer and collision measurements. Three need measurement, not a decision — and each
now has a protocol with a device class, a repeat count and a pass threshold in the plan's §9.14.

**Round 9, same day:** D8.23–D8.26 close the four design questions the full specs raised. The emergency channel's
hardcoded key, the receive-side alert engine, the confirmation grammar and the request-slot ordering were all
answerable from firmware already in the tree. What remains open is three questions that the evidence says are
judgement calls rather than findings: whether the app creates `#emergency` itself, whether unkeyed places get a
"keyed only" filter, and whether a key-bound refutation should shorten a TTL for everyone.


---

## §12 Round 10 — 2026-11-05: the inter-app gateway is removed

**D10.1 The gateway leaves the product; the raw send stays.**

Decided by the project owner on 2026-11-05, superseding item 31 of §5 and the architecture document's §8:
"nothing else yet needs to connect to another app. Maybe in the future we'd have this functionality … right
now it's not needed, so it could be toggled off and on in settings, or it could be removed completely."

What made the decision safe is that the consumer stopped existing. The one application that used the handoff
now owns the radio link itself, from its own vendored copy of the Android transport, and its own state
document calls the phone-side handoff historical. Nothing in this repository has a client left to serve.

Removed: the loopback L2 server and its session/grant machinery, the pairing token and its secure-storage
record, the Binder handoff service with its signature permission and manifest entry, the Connected-apps screen
and its settings row, the gateway's airtime governor, and the two packages that carried them
(`meshcore_gateway`, `meshcore_host`).

Kept, because it is the app's own capability and not the gateway's: sending one opaque record to a contact as
a direct raw-data packet (`0x19`), with the radio's OK/ERR as the outcome and the radio's real parameters as
the airtime estimate. It lives in `lib/meshcore/mesh_sender.dart` (the send, the record budget per contact
path, the overhead a meter must count) and `lib/meshcore/airtime.dart` (the two policies, the LoRa estimator).

What is *not* built now: a running airtime meter. The only implementation was the gateway's governor, which
measured the records a client pushed through it. The app's own sends are not metered today; the estimator and
the policy are the parts the meter will be built from, and the register carries the meter as an unbuilt row
rather than as dead code in the tree.

Reversal cost: high for the socket and its security model, low for the capability — the wire encoders were
never gateway code, and a future client would be a new feature with a new decision, not a resurrection of this
one.

---

## §13 Round 11 — 2026-11-05: one AVIF dependency, because the decided pair cannot be installed

**D11.1 `avif_native` alone carries both directions of the image codec.** The plan named a pair —
`flutter_libavif` for display and `avif_native` for encode — and the pair is impossible: `flutter_libavif 0.1.1`
depends on `code_assets >=1.0.0 <2.0.0` while `avif_native 0.2.0` depends on `code_assets ^2.0.0`, so any
resolution of both fails at the version solver. Independently, `libavif`'s build hook compiles its vendored
dav1d with Meson, and this host has no Meson or nasm, so the decode half could not have been built here either.

`avif_native` is MIT and bundles libavif 1.4.2, dav1d 1.5.3 and libaom 3.14.1 as a prebuilt archive per ABI,
verified against the package's own `archiveSha256` and `librarySha256`. It encodes *and* decodes, so the seam
(`MediaCodec`) is satisfied by one library with one set of notices. Display goes through a small `ImageProvider`
built on `decodeAvif(..., premultiplyAlpha: true)`, which is the same property the plan wanted from
`flutter_libavif` — a real provider with `cacheWidth` folded into the native decode.

Unchanged by this: one AV1-class image format (`0x5643`) and no third image codec. **The licence clause is
withdrawn — see D11.3.**

**D11.2 The bundled library fails the 16 KB page check today, and the register carries it.** Measured on the
debug APK built 2026-11-05 with `tool/check_16k.sh`: `libavif_native.so` has load segments aligned to 4 KB, not
16 KB, on arm64-v8a, armeabi-v7a and x86_64, and its `GNU_RELRO` range ends past the next load segment on all
three. Every other shipped library passes and the archive itself passes `zipalign -P 16`. The store requires
16 KB support from 1 Feb 2027, so this is a build requirement with a deadline, not a defect in the app: the
options are a libavif build aligned with `-Wl,-z,max-page-size=16384`, a vendor rebuild of the same, or
dropping media before that date. Recorded rather than worked around.

**D11.3 Copyleft is acceptable (owner, 2026-11-05), which retires the licence half of two earlier decisions.**
The owner withdrew the rule that the app may not take a copyleft dependency: "LGPL we don't have to, we can use
copyleft software. My statement about that earlier is now not true." One verdict changes and one keeps its verdict but loses an argument.

- `imcodec_native` is no longer excluded for being LGPL. It stays excluded because the AVIF pair it belonged to
  could not be installed together (`code_assets ^1` against `^2`, D11.1), which is a build fact and has nothing to
  do with licensing.
- Recorded voice messages stop being blocked by policy. Codec 2 is LGPL 2.1, so it is now permitted; what remains
  is the work, not a rule. See the register's voice row for the pinned implementation.
- The duties that come with it are real and cheap here: a notice that the library is used and is LGPL, a copy of
  the licence, and the library's source available plus a way to relink. For a public MIT repository that already
  carries its notices in `lib/licenses/asset_licenses.dart`, that is a notice, the licence text, the pinned
  upstream commit and a build script. Pin Codec 2 at tag `1.2.0` (`06d4c11`), not `main`: the project declares
  itself not actively maintained outside the 3200 mode, and upstream's own `FetchContent` example tracks `main`.

**D11.4 The image encoder spends CPU to buy airtime (owner, 2026-11-08).** In the owner's words: "whatever
compression we should use should be the maximum ... the cost of encoding/decoding would be faaar less no matter
what than the crazy latency we get right now." The app's encoder default was `speed: 9` on a 0–10 scale where lower
is slower and smaller, chosen to save encoding time on a phone. That optimises the resource this app has most of and
spends the one it has least of: one datagram goes out every 350 ms with 150 bytes of payload, so a full-budget 4 KB
photo is 27 datagrams and about nine seconds of channel time, on a channel shared with every node in range, against
a USA/Canada preset whose whole hourly transmit budget is 36 seconds.

Measured rather than assumed, with the bundled libavif/libaom on this tree, a 320×240 gradient photo at quantiser 18
(the ladder's first step):

| speed | bytes | encode | datagrams | channel time |
| --- | --- | --- | --- | --- |
| 9 (the old default) | 1390 | 7 ms | 10 | 3.5 s |
| 6 | 887 | 22 ms | 6 | 2.1 s |
| **5 (decided)** | **784** | **90 ms** | **5** | **1.75 s** |
| 4 | 796 | 131 ms | 6 | 2.1 s |
| 0 (the maximum) | 749 | 818 ms | 5 | 1.75 s |

The curve has a knee at 5. "The maximum" is speed 0, and it is only 35 bytes better than 5 for nine times the CPU —
and the encode is synchronous, so on a phone that is a frozen frame, not a slower one. So the decision is **5**, which
is 44 % smaller than what shipped, and the reason the owner's rule does not land on 0 is his other rule: a control
that appears to hang is a defect. The numbers are content-dependent (a high-entropy photo lands near the ladder's
ceiling, where every speed produces about the same bytes), so this is an effort setting and not a promise about any
one picture.

What this does not settle: the same curve on a phone. The encode is synchronous and the ladder returns the first
fitting step, so M1's measurement (median encode at most a third of the transfer time, p95 RSS at most 64 MB on a
lower-mid device) is also the gate that keeps 5 honest on hardware; if a phone's encode at 5 exceeds about a second,
the honest response is to move the encode off the frame thread rather than to lower the effort again.
`test/media/media_codec_settings_test.dart` pins the effort, the ladder's shape, and the 350 ms / 150 B / 27-datagram
arithmetic this reasoning rests on.


---

## §14 Round 12 — 2026-11-09: the owner's own themes, and the role this app was missing

The four looks from LDMUX (Forest, Air, Daybreak, Umber) are ported, and the improvement that came with
them is worth more than the palettes: LDMUX separates a **divider** from a **control's edge**, and holds
each to its own floor.

**D11.5 A control's edge is its own role, at 3:1 (owner, 2026-11-09).** Meshmore used one value, `line`,
for both. The register has carried the consequence since 2026-11-05 without fixing it — on the older dark
presets the border tier runs 1.26:1 to 2.75:1 against the layer it is drawn on, so an "outlined" control
is outlined in a colour nobody can see. On a paper ground the same value happens to pass, which is why the
defect read as a taste difference between skins rather than as a floor nobody met.

Measured on this tree before the change, `line` against `base` / `surfaceAlt`:

| preset | line vs base | line vs surfaceAlt | edge, blended until 3:1 | edge vs base / surfaceAlt |
| --- | --- | --- | --- | --- |
| studio | 2.08 | 1.84 | `#757575` | 4.00 / 3.07 |
| seele | 1.46 | 1.34 | `#64625B` | 3.44 / 3.02 |
| nerv | 1.46 | 1.35 | `#646E82` | 3.75 / 3.03 |
| agHud | 1.38 | 1.26 | `#5B6878` | 3.56 / 3.02 |
| hyperlocal | 1.44 | 1.30 | `#66707E` | 3.82 / 3.06 |
| drPop | 1.52 | 1.36 | `#6E6E73` | 3.74 / 3.03 |
| recon | 2.75 | 2.60 | `#815B00` | 3.43 / 3.01 |
| forest | 5.00 | 4.47 | LDMUX's own `edge` | 5.00 / 3.91 |
| air | 3.93 | 3.63 | LDMUX's own `edge` | 3.93 / 3.41 |
| daybreak | 4.09 | 3.79 | LDMUX's own `edge` | 4.09 / 3.49 |
| umber | 4.30 | 3.89 | LDMUX's own `edge` | 4.30 / 3.29 |

Decided: `MmTokens` gains an `edge` role, derived as `line` when a preset does not state one, so the change
lands preset by preset and nothing breaks in between. Each dark preset states the smallest blend of its own
`line` toward its own `fg` that clears 3:1 on the page *and* on the raised layer, which keeps every skin's
hue and makes the change as small as the floor allows. The four LDMUX presets carry that palette's own two
values unchanged. `line` stays the divider value everywhere.

Where it is drawn: control outlines, input borders, card sides and Material's `outline` role take `edge`;
dividers, group rules and separators keep `line`. Reversal cost: low — one optional role, one derived
default, one test that recomputes the table.

**D11.6 One paper ground too many: Studio Light is withdrawn (owner, 2026-11-09).** The owner asked for a
redundant preset to be found and removed. Measured across all twelve presets on `base + surface + fg +
accent`, the closest pair in the app was **studioLight vs daybreak** (sum of channel deltas 102, against
113 for the next closest). Studio Light also shared Studio's exact layout, type bundle and audio pack, so a
switch between the two changed the ground and nothing else, and it was the third light ground out of five
once Air and Daybreak arrived. It was added by the owner (R115), not one of David's six concepts, and the
owner is the one asking for the reconsideration.

Removed: the enum value, label, audio key, tokens and skin. **Kept:** the paper-ground audit it prompted
(the `fgDisabled` floor, the border tier, brightness derived from the ground, the 320 dp floor). That audit
is a standing contract about light grounds, so it moved to `test/theme/light_ground_test.dart` and now
iterates over every preset whose tokens report `isLight` instead of naming one. A stored preference holding
the removed name falls back to the default preset rather than to an arbitrary one, with a test.

**D11.7 A role's floor follows what it is drawn as, and the dark grounds were failing two of them
(owner, 2026-11-09).** The owner asked that the single dark look be checked "correctly and properly".
Done by recomputing every role against every layer the app can draw it on, for every preset, which
found three floors that only the light grounds met — because each had been found on paper and fixed on
paper:

| defect | measured before | presets affected |
| --- | --- | --- |
| disabled ink under 3:1 where a disabled control sits | 2.22–2.72:1 on the raised and selected layers (2.54–2.86:1 on the page for agHud and recon) | all eleven |
| an alert written as a sentence under 4.5:1 | seele 3.13:1, nerv 3.34:1, recon 2.79:1 on the panel | three |
| the label on a filled alert under 4.5:1 | nerv 3.91:1, agHud 3.17:1, hyperlocal 2.75:1, drPop 3.06:1, recon 3.61:1 | five |

Two roles were doing two jobs, which is why the floors were missed:

- **`alert` was both a fill and a sentence.** As a fill or an icon it needs 3:1 (a graphical object) and
  every preset's alert already cleared it. As text it needs 4.5:1 and three saturated crimsons did not
  — they were chosen to shout as a block, which is right for a fill and wrong for a sentence. The ink
  is now its own role, `alertInk`, lifted into each skin's own family until it can be read; `alert`
  keeps the colour the skin chose. Material's `error` is the ink too, because this app draws it as text
  in 37 places, while the one control that fills with it (the destructive confirm) fills with the ink
  and writes the ground on it, which clears 4.5:1 in every preset by construction.
- **The disabled tier was a blend rather than a value.** `fgMuted` at 50 % alpha composites to 2.2:1 on
  a raised fill, so a disabled control was the least findable thing on the screen. Each preset now
  states the quietest value that still clears 3:1 on all four layers — as far from the second voice as
  the floor allows, not as close to it as possible.

`test/theme/role_floors_test.dart` holds the whole contract, per role and per layer, for every preset,
so a floor cannot be met by one skin family and missed by another again. It states the table, not just
the numbers: which role is drawn as text, which as a fill, which as a boundary, and which has no floor
at all because a divider is meant to be barely there.

---

## §15 Round 13 — 2026-11-09: the owner's rulings on type, media, voice and the alert engine

Five questions were put to the owner because the app could not answer them, and each answer is recorded
here with the evidence it rests on. Everything else in this round was decided from the app and the
published practice, as he asked.

**D11.8 The monospace face belongs to the theme, and the dark one is Fira Mono (owner, 2026-11-09).**
His words: "make dark theme fira mono, others have other mono fonts (use the ones that LDMUX uses and
others)". The mapping, taken from LDMUX's own `Fonts.android.kt` and applied to Meshmore's presets:

| Meshmore preset | face | source |
| --- | --- | --- |
| `studio` | Fira Mono | the owner's request, and LDMUX `Dark` |
| `forest` | Fira Mono | LDMUX `Forest` |
| `air` | JetBrains Mono | LDMUX `Air` (already bundled) |
| `daybreak` | Source Code Pro | LDMUX `Daybreak` |
| `umber` | Geist Mono | LDMUX `Umber` |
| `nerv` | Cascadia Code | LDMUX `Nerv` — the one preset that maps 1:1 |
| `seele`, `agHud`, `hyperlocal`, `drPop`, `recon` | JetBrains Mono, unchanged | David's concepts, no LDMUX counterpart |

LDMUX's own source contradicts itself on Forest: its `Faces` map uses Fira Mono and its `loadTypeface`
uses IBM Plex Mono. The Compose path that actually draws text is `Faces`, so Fira wins, and the
disagreement is noted rather than copied. All four new faces are SIL OFL 1.1 and are already vendored in
the owner's LDMUX tree with licences recorded, so they come across with their notices rather than from a
fresh download.

**D11.9 AVIF stays, and the 16 KB fix is a rebuild of the bundled library (owner, 2026-11-09).** Asked
whether AVIF is the right library at all, the answer from first principles is yes: at 320×240 and a 4 KB
budget the app is choosing between image codecs at roughly 0.3 bits/pixel, and AV1-in-AVIF is the
strongest open option there — WebP lossy and baseline JPEG both spend more bytes for the same picture at
that size, and JPEG XL is better per byte but has no bundled Flutter decoder and no native-asset story
that does not mean shipping a second codec. The measured curve in D11.4 stands: 784 bytes for a
gradient photo at encoder effort 5, which is five datagrams. What is wrong is not the format but the
artefact: `libavif_native.so` is the one shipped library failing the 16 KB check, and the owner chose the
rebuild over waiting for the vendor or dropping media. The package ships its own `CMakeLists.txt` and
`tool/native/build_unix.sh`, so this is a build with `-Wl,-z,max-page-size=16384` and an aligned RELRO
rather than a rewrite, and `tool/check_16k.sh` becomes the gate that proves it.

**D11.10 Recorded voice notes: the plan is pinned, and the work starts now (owner, 2026-11-09).** He
said "start the codec work now", and asked that the integration be planned properly first so no time is
spent twice. The plan below is taken from research rather than invented, and every number is one a
source states:

- **Vendor Codec 2 at tag `1.2.0`, commit `06d4c11`.** Upstream says every mode that matters here is
  outside active maintenance, its only release is that tag, and its own `FetchContent` example pins
  `origin/main`, which is not reproducible.
- **Two modes, chosen by the airtime they cost.** Mode sizes come from `codec2_bits_per_frame` and
  `codec2_samples_per_frame`: 700C is 28 bits per 40 ms frame (700 bit/s, 87.5 B/s), 1200 is 48 (150 B/s),
  1300 is 52 (162.5 B/s), 1600 is 64 (200 B/s), 3200 is 64 per 20 ms (400 B/s). A 20-second note is
  therefore ~1,750 B in 700C (≈12 datagrams at 150 B), ~3,000 B in 1200 (≈20), ~3,250 B in 1300 (≈22).
  Ship **700C and 1300**: 700C is the only mode that fits a note in a dozen datagrams, and 1300 is the
  only mode wired for soft-decision decoding with a BER-driven soft mute, which is the feature a lossy
  mesh actually wants.
- **Pack frames bit-contiguously.** `codec2_bytes_per_frame` is `(bits + 7) / 8`, so 700C's 28 bits ride in
  4 bytes and 1300's 52 in 7 — four wasted bits either way, 12.5 % on the tightest mode. Upstream's own
  encoder packs bitwise MSB-first; the app must too.
- **Two shared libraries, not one.** A pristine `libcodec2.so` and our own thin `libcodec2bridge.so`.
  LGPL 2.1 §6(b) leans on the library being a distinct, individually replaceable object, and fusing it
  into one `.so` with our shim removes the strongest part of that argument.
- **Dart FFI over a plain C boundary, not JNI.** The boundary is a handful of functions, FFI is a direct
  call with no message queue and no platform-thread round trip, it works from a background isolate
  without a `RootIsolateToken`, and encode/decode are ideal `isLeaf` calls (pure C, no callbacks). The
  per-frame payload is 4–7 bytes in and 320 samples out, so the serialisation cost a channel avoids is
  not the deciding factor — the isolate and thread properties are.
- **minSdk stays 24.** Codec 2 needs API 23+ because Bionic below that lacks various `complex.h` maths
  the float path uses, and the app's floor is already 24.
- **16 KB on arrival, and the check that actually fails.** NDK r28+ aligns by default; the build passes
  `-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384` regardless. The trap is RELRO: a
  `PT_GNU_RELRO` whose `VirtAddr + MemSiz` is not a multiple of 16,384 is rejected even when every
  `PT_LOAD` aligns, so the verification checks both.
- **Capture through the `record` package at `pcm16bits`.** Codec 2 takes raw 16-bit mono PCM at 8 kHz, so
  any container encoder would force a decode before the encode. `RECORD_AUDIO` is the one new manifest
  permission, and the sample rate must be verified per device rather than assumed.
- **The licence work is a notice, the licence text, a source offer and a relink path** — which the
  two-library layout makes ordinary. `THIRD-PARTY-NOTICES.md` and `lib/licenses/asset_licenses.dart`
  both gain the entry, and the build keeps the shim MIT and the codec untouched.

**D11.11 The alert engine's whitelist is final (owner, 2026-11-09).** `set notify.<selector>` cannot be
offered because that grammar has no source in the firmware tree this app is built against, so "buzz only
for #emergency" is not expressible and the question stops being open. The typed whitelist is `get/set
buzzer` and `get/set vibration`, both through `0x42`, with the twelve refused commands still refused.
