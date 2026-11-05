# MeshMore — feature plan, two lists, 2026-11-04

Companion to `meshmore-feature-audit.md`. Every item below is a **feature family or capability**, not a task.
Evidence and file:line for each status is in the audit; this document is the decision surface.

> **Superseded in part, 2026-11-04.** The owner answered the scope questions. `meshmore-scope-of-record.md`
is now authoritative for what is in and out; this document remains the analysis trail behind those decisions.
Where the two disagree, the scope of record wins. The lists below still carry the full candidate pool and the
reasoning, including items the owner has since excluded.

Vocabulary:
- **List A — CORE.** Must exist for MeshMore to be the product it claims to be. Includes *amendments* to
  features that ship but are wrong, fragile or dishonest.
- **List B — ADDITIVE.** Could or should be built on top. Tagged `NOW` (needed to make A work),
  `PLAN` (already designed, just not built), `COOL` (worth doing, needs a decision), `LATER`
  (real but not yet), `EXPERIMENT` (measure before committing).
- **List C — NOT TO DO.** Traps, dead ends and things the ecosystem has already proven cost more than they
  return. This is the list the user's "things not to do" asks for.
- **`[Dn]`** marks an open decision; the register is in §5.

---

## List A — CORE (must exist, including fixes to what already ships)

### A1. Messaging that behaves like a messenger
- **A1.1 Inbound notification** — OS-level notification with per-channel and per-peer routing, tap-through to
  the thread, and a silent/visual-only mode. Currently absent entirely: no notifications library is linked, so a
  message that arrives while backgrounded is invisible. This is the single largest product gap.
- **A1.2 Durable, searchable history** — replace the 250-message `SharedPreferences` cap with a real store:
  per-peer threads, full-text search, retention policy, export. Amendment, not addition: the current cap is a
  silent data-loss boundary.
- **A1.3 Honest delivery state across relaunch** — a send that was delivered must never read *failed*. Persist
  in-flight sends with their correlation, reconcile on reconnect, and label the genuinely unknown as unknown.
- **A1.4 Command correlation** — every `OK`/`ERR` attributed to the command that caused it, not to "whatever is
  pending". The host twin already does this; the app does not. Prerequisite for A1.3 and for any bulk transfer.
- **A1.5 Composer byte budget** — live remaining-bytes against the active ceiling, warning before a message
  becomes an over-long frame. Amendment to text chat, which currently has no guard at all.
- **A1.6 Message-level actions and threads** — reply/quote with the quoted excerpt carried in the frame, forward,
  copy-with-metadata, multi-select delete, and a per-peer thread view distinct from the channel stream.
- **A1.7 Notification and delivery semantics per channel** — audio, haptic, OS notification and TTS independently
  per channel; the current build only has the TTS mute.
- **A1.8 Send-side airtime courtesy** — outbound text counted against the duty policy already implemented for the
  gateway, surfaced when a channel is hot. Amendment: the policy exists and only the gateway obeys it.

### A2. Identity, trust and onboarding
- **A2.1 First-run that ends in a working radio** — permission gate, radio choice, region choice, name, and a
  first successful send, as one flow. Currently the intro gate and device config are separate worlds.
- **A2.2 Contact identity that cannot be silently swapped** — the returning-contact key-change path exists; it
  needs to be a visible, blocking, explained event with a per-contact trust state (verified / changed / unknown),
  not a quiet reconciliation.
- **A2.3 Channel-key hygiene the user can act on** — key strength hints exist; the product needs a stated model:
  what "public" means, what a leaked channel key costs, and how to rotate without losing the channel.
- **A2.4 Own-key handling** — export/import of the radio's private key is codec-only today. Decide whether the app
  ever touches key material [D7].

### A3. Device and radio control that cannot strand you
- **A3.1 Two-phase commit for every stranding setting** — frequency, bandwidth, SF, CR, TX power, path-hash mode.
  Confirm on the radio, keep a last-known-good, and offer a one-tap revert sweep. Amendment: current behaviour is
  fire-and-forget and the ecosystem documents this as the failure that loses nodes.
- **A3.2 Make "Pinned" advert location mean something** — either the firmware gains the value or the UI stops
  offering it. Amendment to a stub that currently lies.
- **A3.3 Region presets that match reality** — the full live preset set, the Japan LBT caveat stated in the UI,
  and the "every node must match" warning at the point of change. Amendment: 14 presets are missing and the
  legality text is buried.
- **A3.4 Radio health the user can read** — duty cycle, airtime used, queue depth, retry count, RSSI/SNR trend,
  last-heard-per-neighbour. The numbers exist in fragments; there is no one place that answers "is my radio OK".
- **A3.5 Firmware/board awareness** — detect board and firmware, gate features by what the radio actually
  supports, and say "your firmware cannot do this" instead of failing. Prerequisite for A3.6 and for honest UI.
- **A3.6 Firmware update from the app** — out of scope unless [D12] says otherwise; the ecosystem's mature answer
  is a dedicated quiet frequency, signed blocks and a 3-minute safety check.

### A4. Location and presence
- **A4.1 Location provenance everywhere** — every position shown carries device / phone / pinned / inferred and
  its age. Partially present; needs to be uniform across grid, map, node sheet and weather.
- **A4.2 Beacon policy the user controls** — interval, movement threshold, quiet hours, "only on a private
  channel". Amendment: auto-publish exists with two constants and no user surface.
- **A4.3 Offline maps that actually work offline** — publish or import region files and switch on the shipped
  archive path; today the only offline vector route is disabled by a constant.
- **A4.4 Distance and bearing to a node** — the primitives exist (grid positioning, FNV-1a offset angle); there
  is no compass/range cue in the field.

### A5. Diagnostics a normal person can use
- **A5.1 A "why is this not working" panel** — link quality, last error, firmware mismatch, duty exhaustion,
  permission denial, each with the next action. Today diagnostics is a developer surface.
- **A5.2 Support bundle** — one tap produces a redacted log + config + frame trace for a bug report. The fixture
  export exists in the dev panel; the product has no path to it.
- **A5.3 Repeater/room visibility without administration** — show what the mesh is doing (who repeats, what
  paths are used) without granting destructive access [D10].

### A6. Data safety and privacy defaults
- **A6.1 Encrypted local storage** — history and channel keys are plaintext today. Amendment: this is a default,
  not an option.
- **A6.2 Redaction and export controls** — what leaves the device in a support bundle, a GPX file or an export.
- **A6.3 A stated privacy posture in-product** — no backend is the architecture's decision; the product must say
  so where the user can see it, and say what the radio broadcasts about them.

### A7. Platform parity or an honest platform claim
- **A7.1 Decide and declare** — Android-first with iOS as a later port, or both. Everything else follows [D3].
- **A7.2 If iOS is in**: background BLE via state restoration, no bond list, motion permission for
  shake-to-derive, gateway handoff substituted by something that works on iOS.
- **A7.3 Accessibility and localisation stay requirements** — they are already treated as such and are the
  cheapest differentiator in the ecosystem.

### A8. Legal, release and support surface
- **A8.1 Terms and Conditions** — R10 is not built and the placeholder was deliberately removed.
- **A8.2 Legality statement per region** — the app cannot certify compliance and must not imply it; the Japan LBT
  gap is the worked example.
- **A8.3 A demo mode with no radio** — needed for store review and for anyone evaluating the app [D11].

### A9. Protocol foundations
- **A9.1 A conformance suite for emitted frames** — golden vectors for every frame the app sends, plus the four
  ceilings and `path_len` unpacking. There is no such gate today and the failures it would catch are silent.
- **A9.2 One shared protocol core, or an explicit three-implementation policy** — Dart, Java and Kotlin all carry
  frame logic [D15].
- **A9.3 Licence discipline** — MIT project; adopt formats, never copy GPL reference code or vector files without
  permission. No document records this yet.

---

## List B — ADDITIVE (could / should be built on top)

### B1. Media — the largest single family
- **B1.0 The prerequisite, not a feature:** `0x3E CMD_SEND_CHANNEL_DATA` encoder + an inbound `ChannelDataFrame`
  dispatch branch. `NOW`. One encoder and one `else if` is the entire distance to every media format in the field;
  the receive half is already decoded and tested. Nothing in B1 can start without it.
- **B1.1 Channel images** — adopt an existing registered type rather than inventing an eighth format [D2].
  `PLAN` once B1.0 exists. Cost is mostly UI, plus a codec choice and a licence check.
- **B1.2 Image transport robustness** — salt every resend (the seen-table drops identical repeats), countdown
  markers so the receiver knows when the answer ends, and a completion receipt. `NOW` with B1.1; these are the
  three failure modes the ecosystem has already documented.
- **B1.3 Voice / PTT** — one format for live and stored voice, FEC above ~4 packets. `COOL`, gated on [D2] and on
  a radio-profile decision: voice changes bandwidth and airtime arithmetic and may not be lawful in every region.
- **B1.4 File transfer and bulk** — the honest framing is "an hour and say so": dedicated quiet frequency,
  signed blocks, resumable, stoppable. `LATER`; the mature design exists in wadamesh's LoRa OTA.
- **B1.5 Media off by default on Public** — enforced at the send path, not the UI. `NOW` with any B1 item.

### B2. Interoperability — pick deliberately, not all
- **B2.1 Gateway as a product surface** — the LDMUX tunnel already exists; what is missing is a supported client
  story, a stable contract version and a second signed app to prove the Binder handoff. `PLAN`.
- **B2.2 USB-serial host as a product** — the twin exists and is unpublished; it is currently a developer tool
  [D5]. `PLAN`.
- **B2.3 TCP/WiFi companion transport** — `TcpMeshcoreTransport` beside BLE; the seam is ready. Needed for any
  WiFi-capable node and for the host. `NOW` if iOS background or WiFi nodes matter.
- **B2.4 TAK / CoT bridge** — the largest external audience in the ecosystem; a bridge, not a core feature. `COOL`.
- **B2.5 MQTT bridge** — online, opt-in, explicitly at odds with offline-first. `LATER`, and only as a separate
  component.
- **B2.6 Meshtastic coexistence** — protocol-level bridge; real demand, real complexity. `LATER`.
- **B2.7 KISS modem / TCP companion emulation** — cheap credibility with the ham-adjacent audience. `COOL`.
- **B2.8 Public map/telemetry upload** — the ecosystem's live-map pattern. Privacy-loaded; only with [D7]
  answered and off by default. `LATER`.

### B3. Network operations
- **B3.1 Repeater and room-server administration** — login, status, neighbours, owner info are codec-only today;
  destructive actions deliberately unexposed. Depth is [D10]. `PLAN`.
- **B3.2 Path management the user understands** — reset path, per-contact path-hash width, flood-vs-routed
  policy, and an explanation of why a message took three hops. `PLAN`.
- **B3.3 Congestion controls** — advert rate limiting and a flood allowlist are implemented in forks and absent
  here. Careful: a client cannot fix a mesh's congestion. `EXPERIMENT`.
- **B3.4 Mesh health over time** — coverage survey exists as a view; trend, per-node history and "this hole has
  been here for a week" are not. `PLAN`.

### B4. Teams and coordination
- **B4.1 Team/group identity** — the ecosystem has TEAM wire types and team routes; MeshMore has none. `COOL`.
- **B4.2 Roles and capability gating in-app** — there is no role model at all today; "permissions" means OS
  permissions plus per-contact telemetry flags. Needed before any multi-user feature [D6]. `PLAN`.
- **B4.3 Shared configuration bundles** — one person configures twenty radios; QR/OTP out-of-band already exists
  as a mechanism. `COOL`.
- **B4.4 Check-in, SOS and status** — the field-utility core of every comparable product. `COOL`.

### B5. Field utility
- **B5.1 Trail recording and GPX export** — R37, designed in `geofence-tracking.md`, unbuilt. `PLAN`.
- **B5.2 Geofence and arrival alerts** — same doc, P1–P4. `PLAN`.
- **B5.3 Waypoints and shared markers** — present in the XR client's specs, absent in the app. `COOL`.
- **B5.4 Compass, proximity cue, "point me at that node"** — needs A4.4. `COOL`.

### B6. Automation and bots
- **B6.1 The responder bot** — designed and shipped as a deterministic rulepack; the product question is whether
  it is a user feature or a test fixture. `PLAN`.
- **B6.2 Rules and triggers** — "if this node is heard, do that". `COOL`.
- **B6.3 A scripting surface** — only with hard sandbox limits; the ecosystem's Lua host is the reference and the
  warning. `LATER`.

### B7. AI (F3, explicitly undefined)
- **B7.1 Summarise a channel day / draft a reply / label inferred content** — `COOL`, but only on-device or
  explicitly opt-in, never silent. The privacy posture must be written before any design [D8].
- **B7.2 AI-assisted place inference and message triage** — the existing heuristics are the honest baseline.
- **B7.3 Do not build an AI that transmits.** Any model output that reaches the radio costs other people airtime.

### B8. Platform expansion
- **B8.1 The XR client** — 39k Kotlin lines already exist and are invisible to every plan document [D4].
- **B8.2 Desktop** — the host twin suggests a Linux story; a desktop GUI is a different product. `LATER`.
- **B8.3 Watch / minimal companion** — notification-first surface; depends on A1.1. `LATER`.

### B9. Research and experiments
- **B9.1 lobospeak** — closed-network robot control plane over binary req/resp; fully designed, unimplemented,
  and its carriage assumption contradicts the architecture doc's own analysis of what a channel costs. `EXPERIMENT`
  and it needs a carriage decision first.
- **B9.2 Second PHY (FLRC)** — the only step change in the ecosystem: ~2,000× on bulk versus 3–10× from
  compression. `EXPERIMENT`.
- **B9.3 Swarm repair** — request missing fragments from any holder; the fan-out cost is unmeasured. `EXPERIMENT`.
- **B9.4 Measured reliability in-product** — the programme already produced a real SNR curve; nothing in the app
  uses measured numbers instead of airtime arithmetic.

---

## List C — NOT TO DO

- **Do not become a seventh image format.** Six exist, zero interoperate. Adopt a registered type or join one.
- **Do not put a cloud in the middle.** No backend is an architectural decision; the gateway is loopback-only by
  design. An account system would undo the product's only structural advantage.
- **Do not require the radio to be online for the app to be useful.** Every offline path is a feature.
- **Do not add a feature that costs other people airtime without an explicit, enforced opt-in.** Photos and voice
  on Public are the worked example; enforce at the send path, not the UI.
- **Do not invent a private chunking scheme while upstream's multipart is an ACK-only stub that might generalise.**
  Build against the type that exists; revisit if upstream ships.
- **Do not bind the app to a firmware fork.** 52 custom firmwares exist; an app bound to one inherits its lifespan.
  Target the companion protocol. Corollary: do not depend on a CLI verb that only one fork has.
- **Do not add destructive remote administration without a two-phase confirm and a stated blast radius.**
- **Do not ship an AI feature that is silent, cloud-dependent by default, or that transmits.**
- **Do not treat the spec as the product map, or "Future" as a state.** Both are wrong in both directions.
- **Do not quote "R1–R108" as a requirement count.** R38–R51 do not exist; the namespace is broken.
- **Do not copy GPL reference code or test-vector files into an MIT project.** Formats yes, files no.
- **Do not build a fourth protocol implementation by accident.** Three already exist; decide deliberately.
- **Do not add a skin per feature.** Seven skins already cost real money; consolidate before adding an eighth.
- **Do not chase full protocol coverage in the UI.** 21 opcodes are refused by policy and that is correct; expose
  the ones a user needs, and say why the rest are absent.
- **Do not add a feature whose flash/RAM budget was not checked on the smallest supported board.**
- **Do not promise a route the radio cannot prove** — the host already learned this; the app should not relearn it.

---

## §5 Open decisions — what each one changes

| # | Decision | What it changes |
| --- | --- | --- |
| D1 | **What MeshMore is for**: personal messenger / field-ops tool / platform other apps use | Ordering of A1 vs A5 vs B2; whether the gateway is core or a side door |
| D2 | **Media scope**: none / images / images+voice / +files, and which wire type | Whether B1 exists at all; radio profile; legality |
| D3 | **Platform**: Android-only / +iOS / +XR / +desktop | A7; ~30 % of total effort; background architecture |
| D4 | **The XR client**: first-class, experimental, or frozen | Whether 39k Kotlin lines are in the roadmap or in maintenance |
| D5 | **Host gateway**: product or developer tool | Packaging, support, release cadence |
| D6 | **Multi-user**: single-user or teams/roles | B4; needs an in-app role model that does not exist |
| D7 | **Privacy posture**: confirm no cloud/no accounts; is crash reporting acceptable; does the app ever touch key material | A6, A2.4, B2.8 |
| D8 | **AI**: in or out; on-device only? | B7 |
| D9 | **lobospeak**: active track or parked | B9.1; and its carriage contradiction needs resolving first |
| D10 | **Repeater admin depth**: read-only / config / destructive | B3.1; blast-radius design |
| D11 | **Release channel**: store or sideload | A8.3 demo mode, A8.1 terms, review-safe scope |
| D12 | **Firmware baseline**: which boards/versions must work; may older ones be dropped | A3.5; the whole gating layer |
| D13 | **History**: is searchable archive a requirement | A1.2; storage architecture |
| D14 | **Design scope**: keep seven skins or consolidate | Frees real effort for A1/B1 |
| D15 | **Shared protocol core**: one implementation or three | A9.2; every future protocol change |
| D16 | **Interop**: which of TAK / MQTT / Meshtastic / KISS-TCP is actually wanted | B2.4–B2.7 |
| D17 | **Location**: is tracking/geofencing in scope, or is location presence-only | B5.1–B5.2 |
| D18 | **Notification depth**: local only, or push through a relay | A1.1 architecture; a relay breaks "no backend" |

---

## §6 Dependency order (technical; mine to decide unless you object)

1. **A1.1 notifications + A1.4 correlation + A1.2 history** — in that order. Notifications need a reliable inbound
   path; correlation is what makes delivery state honest; history needs a store that survives relaunch.
2. **B1.0 the `0x3E` encoder + inbound dispatch** — before any media UI, voice, or MediaMesh control work.
3. **A3.5 firmware/board awareness** — before A3.1 rollback and before any gated feature, because both need to
   know what the radio can do.
4. **A3.1 two-phase commit** — after A3.5, because a revert sweep needs the capability layer to know what changed.
5. **B2.3 TCP transport** — only if D3 puts iOS background or WiFi nodes in scope; otherwise later.
6. **A9.1 conformance suite** — start now in parallel; it is the cheapest insurance against silent regressions and
   it will catch the four ceilings and `path_len` bugs that no current test covers.
7. **A6.1 encrypted storage** — before any history growth, so the migration happens once.

---

## §7 Scope decisions recorded in round 1 (2026-11-04)

- **Product identity:** personal messenger **and** field-and-operations tool, **primarily field operations**.
  The "platform other apps use" framing is not the primary identity — so the gateway is an integration, not a
  product surface.
- **Media:** images **and** voice/PTT requested. Voice investigated in depth; verdict below.
- **Platform:** **Android-first, iOS later.** Keep iOS compiling with best-practice compatibility; do not invest
  in iOS testing now. Declare the platform honestly in-product.
- **Interoperability:** TAK/CoT and MQTT wanted, subject to a practical-value audit. Connected-apps gateway to be
  audited critically for keep/fix/drop.

### Voice — the evidence verdict

**Ship recorded voice messages; defer live PTT.** Reasoning, all from `meshmore-research` notes and the app:

- Live PTT needs **250 kHz**; **19 of 26 live presets are 62.5 kHz**, which is the US/Canada main mesh. At
  62.5 kHz one voice packet is ~0.61 s of air for ~1.04 s of speech — ~60 % channel duty single-hop, and it
  collapses with one repeater.
- PTT needs third-party fork firmware (`radio2`), which is exactly the fork-binding List C warns against.
- **It is unlawful in the EU at every bandwidth** — duty cycle binds, not bandwidth; 250 kHz is 15.4 % against
  a 1 % budget, and no EU sub-band is 500 kHz wide.
- **No measured multi-hop voice success rate exists.** The only published figure is 197/200 on a MediaMesh
  scan-timing bench, explicitly "a timing policy, not a claim of zero packet loss".
- **FEC cannot protect live audio** — parity ships after the clip. Our own measured curve has ~20 % loss at
  −6 dB, so a 20-packet block fails below about −5 dB.
- **No direct-message binary carrier exists**: DM voice must ride `0x19 CMD_SEND_RAW_DATA`, which refuses to
  flood, so "voice note to a contact" silently degrades to direct-range-only until a route is known.
- **Voice messages are cheaper in airtime than the cheapest image** — ~55 % of one Standard 2.75 KB photo for
  the same duration of content. Order voice before images on cost grounds.
- The companion radio has **no audio hardware**, so "voice costs radio flash" is a category error; the real
  cost is an Android microphone permission and a capture plugin, neither of which exists (`pubspec.yaml` has
  only `flutter_tts` and `audioplayers`).

Narrowest viable configuration: recorded clips ≤20 s, ≤20 packets, VE3 format on `0x5643`, one channel,
**off by default on Public and `#public`**, FEC on the stored copy only, salted fetch requests, marked packets
so the receiver knows when the answer ends. PTT only behind a capability gate (`get radio2` = `rxtx`, preset
≥250 kHz) and refused outright in EU presets.

### Interop — the evidence verdicts

- **Connected apps / LDMUX gateway — keep, but as an internal integration.** The client is real (a live LDMUX
  repo with a deployed daemon and a device-verified Android client), the security model is honest, and the
  costs are already sunk. What it needs is finishing and freezing: published L2 v1 with vectors, a
  release-signed Binder handoff test, a UI statement that it serves only while MeshMore runs, a watchdog exit
  and a bounded queue. It shares one radio and one outstanding request with chat — at the 1 % governor that
  is ~58 records/hour, ~10 command operations once replies are counted.
- **MQTT — reject in the app; host-side only.** A bridge that only works when the phone is online and awake is
  down most of the time; the host twin already runs headless with a systemd unit. If it exists, the host
  publishes, off by default.
- **TAK/CoT — bridge from the host only, if a TAK user asks.** UV-CORE already owns the ATAK-plugin niche
  (position sharing, slotted pings, net slots, GeoChat, CoT). What MeshMore can uniquely add is publishing
  its own users' positions and messages to a TAK server — a CoT publisher beside the host gateway. Two
  techniques worth copying regardless: slotted reply timing keyed by callsign hash, and a stale window scaled
  to the advertised beacon interval.
- **Refused for this phase:** KISS modem, Meshtastic bridge, public map upload.

## §8 Maps, social places and directions — additions to the lists

Full design in `meshmore-maps-and-directions.md`. Headlines:

- **The first blocker is that nothing can be created on the map.** No tap handler, no long-press handler on
  the basemap anywhere. Every social-map feature starts there.
- **A pin can already be shared as text and already parses inbound at 0.95 confidence** — the text convention
  is a formatting decision, not a protocol one.
- **No `Place` object exists.** Favourites are pubkeys, not places; the only persisted place-like thing is a
  coverage cell.
- **No routing at all**, and the external launch opens a *pin*, not *directions*.
- **Engine verdict:** none of BRouter/Valhalla/GraphHopper/OSRM/MapLibre is copyleft, so all are linkable by
  an MIT app; the binding licence problem is the ODbL *data*. BRouter (MIT, pure Java, on-device by design,
  tiny shared segments, documented voice hints) is the Android-first choice; Valhalla (MIT, published AAR +
  XCFramework, one tile set for all modes) is the cross-platform choice. Against a 500 MB shared budget,
  per-profile storage multiplication rules out GraphHopper and OSRM.
- **The artifact problem is the same one region files already have:** machinery can exist with nothing
  published. Fetch from public sources, ship one region, or self-host — decide before promising offline
  turn-by-turn.

## §9 What I will do without asking

- Repair the requirement set: define or retire R38–R51, disambiguate the duplicate R51, move the eight shipped
  items out of "Future", and add the eight missing documents to the spec's document map.
- Produce the single feature matrix: every requirement → shipped / partial / unbuilt / dropped, with code evidence.
- Fix the three stale docstrings and the four self-contradictions named in the audit.
- Record the licence constraint (MIT vs GPL reference code) as a decision of record.
- Add the "no media requirement" finding as an explicit scope decision rather than an omission.
