> **Historical. This is a 2026-10-26 investigation, kept for its firmware evidence.**
> The record for radio settings is `meshmore-sns-radio-config.md`, and for the protocol `meshmore-sns-protocol-coverage.md`. See `docs/INDEX.md` for the role of every document.

# Private mesh, radio parameters, haptics storm, header structure, transport selector

Written 2026-10-26. Evidence only: every claim cites `path:line` or is marked
**[unverified]** (reasoned from general LoRa knowledge, not from a file or command
in this session). Firmware = `/home/ldeen/Documents/meshcore-fw-alerts`
(`companion-v1.17.1` @ `d929643`, read-only, nothing touched). App paths are
relative to `meshmore_sns_app/responsive_starter_app/`. LDMUX paths are relative to
`/home/ldeen/Documents/ldmux/`. No source file was edited; this is the only file written.

---

## 1. Private mesh on MeshCore: every mechanism the firmware has

### 1.1 Radio parameters (the only real airtime isolation)

`CMD_SET_RADIO_PARAMS` accepts `freq 150000..2500000 kHz`, `sf 5..12`, `cr 5..8`,
`bw 7000..500000 Hz` (`examples/companion_radio/MyMesh.cpp:1403-1404`). It writes
`_prefs`, calls `savePrefs()` and `radio_driver.setParams()` (`:1405-1412`). It is
**global and persistent**: one parameter set per radio, no per-channel or per-contact
radio config. Nothing in this handler touches the BLE link, so the BLE link survives;
the mesh-side effect is that the node immediately stops hearing everyone on the old
tuple (inference from `setParams`, not observed on hardware).

Repeat flag trap (new finding): the same command takes an optional `repeat` byte
(`:1396-1399`). Setting it is rejected unless the frequency is in
`repeat_freq_ranges`, which by default is exactly **433.000, 869.495 and 918.000 MHz**
(`:1006-1014`, `isValidClientRepeatFreq` `:1016-1022`, overridable only at compile time
by `ALLOWED_REPEAT_FREQ_RANGE`). The deployed 910.525 MHz is **not** allowed, so a
companion cannot be switched into repeater mode on the public frequency from the app
(`:1401-1402` returns `ERR_CODE_ILLEGAL_ARG`). The CLI path `set repeat on` on
repeater firmware has no such whitelist (`src/helpers/CommonCLI.cpp:532-534`).

What must match between two nodes: frequency, bandwidth, SF (demodulation). CR is in
the packet header so it need not match (LoRa PHY header; **[unverified in this repo]**,
stated in `meshmore-sns-radio-config.md` §2). Path hash mode does NOT need to match (corrected 2026-10-28):
it is the length a node stamps on packets it sends and forwarders follow each packet's own length
(`NodePrefs.h:40`, `Mesh.cpp:89`, `:347-349`; `CommonCLI.cpp:119` clamps 0..2, "mode 3 reserved").

Spacing between two private/public tuples **[unverified, general LoRa/SX126x knowledge,
not measured here]**: at 62.5 kHz BW, a 1 MHz or larger carrier offset is far outside
the receiver filter (practically orthogonal); a few channel widths (≥ 250-500 kHz)
is normally enough, and the 17 MHz gap 910.525 vs 927.875 is massively sufficient.
Different SF on the same frequency and BW is quasi-orthogonal (typically ~16-20 dB
co-channel rejection between SFs) but is not isolation under strong near-field TX.
**Recommendation: private network = different frequency, not just different SF.**

US-practical sub-band: any frequency 902-928 MHz at ≤ 62.5/125 kHz BW. Public presets
already occupy 910.525 (USA/Canada) and 927.875 (SoCal) (`/tmp/mc_api.json`, API
fetched 2026-10-25; table in `meshmore-sns-radio-config.md` §3). Avoid those and
918.000 (the one US frequency the firmware whitelists for companion repeat,
`MyMesh.cpp:1012`). A private 62.5 kHz pick such as 913.xxx-916.xxx is free of any
listed preset **[unverified: no local RF survey, no spectrum scan was done]**.

### 1.2 Region scoping / transport codes: a flood filter, not privacy

Mechanism, from code:

- A scoped flood is route type `TRANSPORT_FLOOD` with `transport_codes[0] =
  HMAC-SHA256(key, payload_type || payload)` truncated to **16 bits**
  (`src/helpers/TransportKeyStore.cpp:4-18`; `0000` and `FFFF` are reserved).
- Region key: `$name` = private (loaded from a keystore), `#name` or plain `name` =
  auto key `SHA256("#name")` (`src/helpers/RegionMap.cpp:173-188`,
  `TransportKeyStore.cpp:getAutoKeyFor`). The `#` key is **publicly derivable** from the
  name.
- Repeater receive: `TRANSPORT_FLOOD` → `region_map.findMatch(pkt, REGION_DENY_FLOOD)`;
  plain `FLOOD` → wildcard region unless the wildcard has `REGION_DENY_FLOOD`;
  anything else → NULL (`examples/simple_repeater/MyMesh.cpp:555-567`).
- Repeater forward: a **flood** with `recv_pkt_region == NULL` is **dropped**
  (`simple_repeater/MyMesh.cpp:440-443`, log "unknown transport code, or wildcard not
  allowed for FLOOD packet"). So a repeater that does not know region R will not relay
  R-scoped floods, and a repeater with `region denyf *` will not relay unscoped floods.
- Hop caps: `flood_max`, `flood_max_unscoped`, `flood_max_advert`
  (`src/helpers/RoutingPolicy.h:15-22`); defaults 64/64/8 on repeater
  (`simple_repeater/MyMesh.cpp:905-907`).
- **Direct traffic is not scoped at all.** A direct packet is forwarded when the
  node's hash is the next path element and `allowPacketForward` passes
  (`src/Mesh.cpp:78-109`); `simple_repeater`'s `allowPacketForward` only checks
  `disable_fwd`, flood limits, region (floods only) and loop detect
  (`simple_repeater/MyMesh.cpp:434-459`). No region, no ACL, no payload-type test on
  direct forwarding.
- Companion send side: `sendFloodScoped` wraps floods with the app-set key
  (`CMD_SET_FLOOD_SCOPE_KEY` `MyMesh.cpp:1936-1946`, 16-byte key) or the stored default
  scope (`CMD_SET_DEFAULT_FLOOD_SCOPE` code 63 `:1947-1963`, name[31] + key[16]).
  `codes[1] = 0` always (`:495`, "REVISIT"). Flooded `CMD_SEND_BINARY_REQ` goes through
  `sendRequest` → `sendFloodScoped(recipient, …)` (`src/helpers/BaseChatMesh.cpp:647,674`)
  so **Phase A discovery floods inherit the scope**.
- Companion repeat mode does **no** region filtering: `MyMesh::allowPacketForward`
  returns `_prefs.isRepeatEn()` (`MyMesh.cpp:485-487`).

Adversarial verdict, proven from code:

1. **Not confidential.** The code is an authenticator over the payload only to 16 bits.
   An attacker who has never seen the key still passes a repeater with probability
   1/65536 per attempt, so floods can be injected with ≈ 65k tries of airtime.
   It is a noise/ scope filter. Payload stays whatever the app made it
   (LDMUX's is ADR-0020 encrypted, so confidentiality is already handled above this).
2. **A `$private` region cannot work on this firmware.** `loadKeysFor` only reads a
   cache and ends in `// TODO: retrieve from difficult-to-copy keystore`;
   `saveKeysFor`, `removeKeys`, `clear` are TODO stubs returning `false`
   (`TransportKeyStore.cpp:46-86`). So repeaters can only match `#hashtag`/plain-name
   regions, whose key is `SHA256("#"+name)`. Workable trick: use a **long
   high-entropy region name** as the shared secret (name ≤ 30 chars,
   `RegionEntry.name[31]` `RegionMap.h:15-19`). That gives obscurity, not authentication
   (point 1).
3. **It does isolate flood load from public repeaters** (the useful property): public
   repeaters that do not know the region drop scoped floods (`:440-443`). It does
   **not** remove our own transmissions from the shared channel or stop public nodes
   hearing/colliding with them. Whether *all* deployed public repeaters run
   region-aware firmware is **not provable from this repo** (legacy firmware ignores
   transport codes: `Dispatcher.cpp:166` comment "legacy firmware").

### 1.3 Repeater operation

- `repeat` on dedicated repeater firmware: `set repeat on|off` toggles
  `disable_fwd` (`CommonCLI.cpp:532-534`, get at `:839-840`); `set freq` applies after
  reboot (`:713-717`); `set dutycycle 1-100` (`:450-464`); `set flood.max`,
  `set flood.max.unscoped`, `set flood.max.advert` (`:632-653`); `set path.hash.mode`
  `(0-2)` (`:678-682`); `set loop.detect` (`:700-710`); `set tx` (`:709-713`);
  advert intervals (`:486-501`).
- Minimal working private repeater network: **dedicated-firmware repeater node(s)**
  (`examples/simple_repeater`), each configured with the same freq/bw/sf/cr/path-hash
  mode as the endpoints, plus name, advert interval, and region list if scoping is
  used. A companion build repeater is a second-class option (frequency whitelist,
  no region filter, §1.1/1.2).
- Direct-routed `RAW_CUSTOM` does traverse repeaters: the relay code has no
  payload-type exclusion (`Mesh.cpp:78-109`). This contradicts the community report
  that repeaters drop `RAW_CUSTOM` (`meshmore-sns-architecture-audit.md` / issue 3110
  as recorded earlier): **per this tag's code, direct RAW_CUSTOM is relayed.** It is
  not verified on air. Endpoint receive of `RAW_CUSTOM` is `isRouteDirect()` only
  (`Mesh.cpp:292-297`).

### 1.4 Access control: none on the data path

`ClientACL` stores per-client permissions (`GUEST 0, READ_ONLY 1, READ_WRITE 2,
ADMIN 3`; `src/helpers/ClientACL.h:8-12`) and gates **management requests** to the
repeater (login `simple_repeater/MyMesh.cpp:92-126`, guest password `:104`,
status/telemetry `:216-248`, `setperm <pubkey> <perm>` `:1240`). It is **not
consulted by `allowPacketForward`** (`:434-459`) or by direct forwarding
(`Mesh.cpp:89`). A repeater **cannot be locked to specific public keys for
forwarding.** Privacy of the relayed traffic comes only from (a) different frequency,
(b) region obscurity, (c) end-to-end encryption by the application (ADR-0020).
`allow.read.only`, `guest.password` (`CommonCLI.cpp:482-507`) affect login only.

### 1.5 Path hash mode and the raw-data budget

`CMD_SET_PATH_HASH_MODE` is **61**, `[61][0][mode]`, mode 0..2
(`MyMesh.cpp:60,1466`), stored as `path_hash_mode`; floods are sent with
`path_hash_mode + 1` byte hashes (`MyMesh.cpp:491,497`). `path_len` has the mode in
its top 2 bits and the hop count in the low 6 (`Dispatcher.cpp:166`), path capacity 64
bytes (`src/MeshCore.h:22`). Packet limits: `MAX_PACKET_PAYLOAD 184`, `MAX_TRANS_UNIT
255` (`MeshCore.h:20,23`); companion frame `MAX_FRAME_SIZE 176`
(`src/helpers/BaseSerialInterface.h:5`). So the direct raw-data budget is
`174 - path_byte_len` where **path_byte_len = hops × (mode+1)**: 3 hops at mode 0 → 171,
at mode 2 → 165 bytes. The earlier design wrote `174 - path_len`; that is correct only
when read as bytes, which matters for modes 1-2 (record sizing must use bytes, not
hop count). More hops through private repeaters at mode 2 shrink the record faster:
**choose mode 0 (1-byte hashes) for a small private mesh** (collision risk rises with
node count; 256 hash values).

### 1.6 Other firmware features

- `CMD_SEND_RAW_PACKET` 65: `len >= 4`, injects any parsed packet with caller-chosen
  priority (`MyMesh.cpp:2003-2013`); input limited by `MAX_FRAME_SIZE 176` minus 2
  header bytes = 174 raw packet bytes incl. header+path_len+path, so payload ≤ 174 − 2 −
  path bytes. It bypasses `sendFloodScoped`, so **scope codes must be placed by the
  caller** in the injected packet.
- `PAYLOAD_TYPE_CONTROL` zero-hop discovery packets (`Mesh.cpp:70-76`): direct,
  `getPathHashCount() == 0` only, never forwarded.
- `sendZeroHop` (`Mesh.cpp:728`) never leaves one hop: the cheapest "private" mode,
  but then there are no repeaters.
- `MULTIPART` is ACK-only (recorded earlier). `TRACE` collects SNR per hop
  (`Mesh.cpp:42-69`): useful for the MeshMore path-quality UI, not for transport.
- `set tx` / `CMD_SET_RADIO_TX_POWER` (`MyMesh.cpp:1423-1425`, `-9..MAX_LORA_TX_POWER`):
  lowering TX power on a private pair reduces interference footprint on the shared
  band.
- `RESP_ALLOWED_REPEAT_FREQ` (`MyMesh.cpp:1995-2002`) lets the app read which repeat
  frequencies the build allows; MeshMore does not read it.

### 1.7 Viable architectures

| | (a) Private frequency + private repeaters | (b) Shared frequency + region scope | (c) Shared frequency + direct only |
|---|---|---|---|
| Isolates airtime | **Yes** (different carrier) | **No**: same channel; only stops public repeaters relaying our floods (`simple_repeater:440-443`) | **No** |
| Keeps public-mesh membership | **No** (one param set per radio, `MyMesh.cpp:1405-1412`) unless extra radios | Yes | Yes |
| Radios needed | endpoints (2) + repeaters (≥ 0). Pair with public membership: +2 | 2 endpoints (+ dedicated repeaters need region support) | 2 |
| Relays possible | Yes, dedicated repeater firmware, any freq | Dedicated repeaters only, with region set | Only via public repeaters relaying direct paths (no scoping, no ACL) |
| What breaks | leaves the live local mesh the phone radio is in; both ends must reprovision together; duty cycle is reachable via `CMD_SET_TUNING_PARAMS` (corrected 2026-10-28, see radio-config §4) | `$private` unsupported (§1.2); 16-bit code is a filter not auth; unknown legacy repeaters | uses other users' repeaters for traffic they cannot read (direct: they relay per path, `Mesh.cpp:89`) |
| Privacy | by obscurity of freq + ADR-0020 | obscurity of name + ADR-0020 | ADR-0020 only |

**Recommendation:** (c) now (no change), with (a) as the target when a dedicated pair
of private repeaters is wanted. (b) offers little: it saves public repeaters' airtime
but not the shared channel, and its privacy claim does not hold.

---

## 2. Does LDMUX need separate radio parameters?

- A radio has exactly one param set: `_prefs.{freq,bw,sf,cr}` (`MyMesh.cpp:1405-1409`).
  So the phone's radio cannot be on both the public tuple and a private tuple. To be in
  both, **two radios per endpoint** are needed (public radio + private radio); the
  gateway architecture (one single-central BLE link, `meshmore-sns-architecture.md`
  §1.1) means each extra radio needs its own BLE owner too, which MeshMore does not
  support (single device).
- Node counts for a pair (phone side + host side):

| Architecture | Radios | Notes |
|---|---|---|
| (c) direct on public tuple | 2 (existing) | phone radio and host radio remain public members |
| (a) private tuple, no repeaters | 2 | both reprovisioned; they **leave** the public mesh |
| (a) private tuple + public membership kept | 4 | 2 private + 2 public |
| (a) + N repeaters | 2 + N (dedicated repeater firmware) | N ≥ 1 per coverage gap |

- **Trigger to split params, as numbers** (derived from §3 of the radio doc;
  613 ms/packet at 910.525/62.5/SF7/CR5): split when, measured over a week of real use,
  - LDMUX-sourced airtime exceeds **36 s/hour** at the radio (≈ 59 records) on more
    than a few hours/week (i.e. you are actually pressing the voluntary 1% bound), or
  - p95 round-trip for a command exceeds **~10 s** on a 1-hop link, or
  - the public-mesh channel utilisation seen at HELTEC-BASE (`GET stats`
    `RESP_CODE_STATS` type radio, `MyMesh.cpp:~100`) is persistently > **10%** while LDMUX
    is running (guideline **[unverified]**), or
  - the user needs repeaters the public mesh does not provide.
  These numbers are proposals; MeshMore does not currently record LDMUX airtime
  (`GatewayCapability`/`STATUS` carries `txAirtimeTenthsThisHour` in the design only).
- Open question that changes everything (see Learnings): the radio plugged into the
  computer may be the **same** physical radio as `HELTEC-BASE`, i.e. there may be only
  one radio today.

---

## 3. Haptics storm on backfill

Call sites (all of them): `lib/cue/cue_service.dart:122` (`SystemSound.play`),
`:419-422` (`HapticFeedback.selection/light/medium/heavy`); everything else is routed
through `CueService.play` (`:443-448`) which does `unawaited(haptic.play(kind))` with
no gating, and `SystemHapticBackend.play` plays a 1-3 hit pattern with a 70 ms
`stepGap` (`:406-417`, `:400`).

Backfill path:

1. On link `ready`, `_drainStart(backlog: true)` (`lib/meshcore/meshcore_controller.dart:149-152`,
   comment "this one IS a backlog: it is history"). The drain loops
   `CMD_SYNC_NEXT_MESSAGE` one by one until `NoMoreMessages` (`:3200-3300`: `_drainStep`
   `:3229-3238`, `_maybeDrain` `:3253-3269`, cap 512).
2. Each synced text becomes a `ChatMessage`: channel `_ingestChat` `:1904-1919`,
   DM `_ingestDm` `:1866-1886`; both call `_addMessage` and then
   `_incomingCh.add(m)` / `_incomingDm.add(m)` (`:1919`, `:1886`).
3. `CueBridge` subscribes to both streams (`lib/cue/cue_bridge.dart:21-24`):

```dart
// cue_bridge.dart:108-110
void _onIncomingChannelMessage(ChatMessage m) {
  _cue.play(CueKind.messageIn);
```
```dart
// cue_bridge.dart:118-127
void _onIncomingDm(ChatMessage m) { ... _cue.playSignature(...)
```

**The wrong assumption:** these two handlers treat every stream event as a live
arrival. They never consult `_mc.isBacklogDrain`. The controller already exposes the
exact distinction (`meshcore_controller.dart:3203-3214`, "Replaying a backlog ... must not
be treated as fresh") and two consumers use it correctly (`lib/bot/bot_bridge.dart:51,65`).
The adverts path has its own guard (`cue_bridge.dart:96-97`, `if (_mc.isDraining)
return;`). Messages have **none**, and unlike adverts there is **no rate throttle**
(`_advertThrottle` `:56` exists only for adverts).

Consequences (same root cause):

- **Haptics**: one pattern per message, fired un-awaited so patterns overlap: N
  backlog messages → N concurrent 1-3-hit vibrations ("vibrating tons and tons").
- **Audio**: `CueService.play` also fires the sound per message
  (`cue_service.dart:443-448`) when audio is enabled.
- **TTS**: `speakForChannel` / `speakForPeer` run for every backlog message
  (`cue_bridge.dart:115,133`), i.e. the phone may read out the entire backlog.
- The recent-messages/dashboard/chat filling at once is **not** a cue bug: it is the
  UI reacting to `_messages` changes; `notifyListeners` is not coalesced per message in
  the paths read here. Not investigated further (read-only, no profiling). Observed
  screen fill is consistent with the storm but the rebuild count is **unmeasured**.
- No local-notification plugin is used for messages (`grep flutter_local_notifications`
  only matched `perms/permissions_service.dart`), so no notification storm.

Minimal correct fix (not implemented):

1. In `CueBridge`, in both handlers (`cue_bridge.dart:108` and `:118`): `if
   (_mc.isBacklogDrain) { _backlogMissed++; return; }` before any cue or TTS call.
2. In `_onChange` (`:58-89`, already called on every controller notify, and
   `_setDraining` notifies, `meshcore_controller.dart:3198-3201`): track
   `_wasBacklog`; on the falling edge play **one** summary cue (reuse `messageIn`,
   or `dmIn` if any DM) and reset the counter. `isBacklogDrain` is false by then so
   the edge needs `bool _wasBacklog` stored in the bridge.
3. Optionally add a live-burst throttle for `messageIn` mirroring `_advertThrottle`
   (a second, independent defect: a busy channel still buzzes per message).
4. Edge to document, not fix: a live message arriving during a backlog drain is
   silenced by the same flag (no way to tell them apart; `_drainStart` returns early
   if already draining, `:3217`).

Tests that should exist (`test/cue/cue_bridge_test.dart` is the home; fakes exist
there; `test/bot/bot_bridge_test.dart:156,191` already shows how to drive
`isBacklogDrain`):
- backlog channel messages produce zero `play` calls and zero TTS calls;
- backlog DMs produce zero `playSignature`/`play` calls;
- exactly one summary cue at the end of a backlog drain with ≥ 1 messages, none with 0;
- a live message after the drain ends plays normally;
- N rapid live messages produce ≤ 1 cue per throttle window (if the throttle is added).

Edit sites: `lib/cue/cue_bridge.dart` lines 58-89 (`_onChange`, add edge), 108-116
and 118-134 (guards), 53-56 (new `_lastMessageCue` throttle field). No controller
change needed.

---

## 4. Header/title structure

Current structure, exact:

- Top label: `lib/shell/home_shell.dart:159-160`, `appBar: AppBar(title:
  Text(current.title(l)), actions: const [RadioLinkIndicator()], bottom: _ViewStrip(...))`.
  `current.title(l)` is from `MmView.title` (`:39-46`: `tabDashboard`, `tabChat`,
  `tabNodes`, `tabGrid`?, `tabMap`, `tabSettings`, strings `lib/l10n/app_en.arb:7-12`).
- Tab buttons: `_ViewStrip` (`home_shell.dart:200-330`), icon-only cells
  (`:271-330`; label is semantic/tooltip only).
- Body: `PageView` with six children (`:177-199`): `DashboardHost`, `ChatScreen`,
  `NodesScreen`, `GridScreen`, `MapScreen`, `_SettingsView`.
- The tab label also appears: tooltip/semantics of the strip (`:271,275`), tests
  (`test/shell/home_shell_test.dart:101,133,136,143,158,193,271,279,301,307` all
  `find.widgetWithText(AppBar, '<tab name>')` and will need rewriting), and pushed
  sub-pages use their own AppBar titles (Docs, About, Device configuration), which
  are a different route and can stay.
- Existing "second header box" per tab (what the user calls the lower box):

| Tab | Has its own top box? | Where |
|---|---|---|
| Dashboard | No. Big `PEERS IN RANGE` numeral in a `ListView` (padding 20) | `lib/screens/dashboard_screen.dart:49-83`; also per-skin dashboards carry their own `MESHMORE`/`MESHMORE // NERV` banners (`dashboards/nerv_dashboard.dart:43`, `drpop_dashboard.dart:61`, `aghud_dashboard.dart:209`, `hyperlocal_dashboard.dart:529`, `recon_dashboard.dart:108`): **these will double up** with an always-"MeshMore" AppBar |
| Chat | A 48 dp channel-chip strip, no title | `lib/screens/chat_screen.dart:215-262` (comment `R91`) |
| Nodes | A filter/advertise row | `lib/screens/nodes_screen.dart:~413-460` (Padding+Row, count chip) |
| Grid | Its own toolbar Row with the view picker, shows current view name | `lib/screens/grid_screen.dart:~625-680` (R88/R104) |
| Map | None; floating overlay buttons only | `lib/screens/map_screen.dart:43-83` |
| Settings | None; list with group labels | `home_shell.dart:384-420` |

Smallest consistent structure: one shared widget, e.g. `MmPageHeader(title, {actions,
subtitle})`, fixed `minHeight` ≈ 48 dp, placed as the first child in each tab body
(`dashboard_screen.dart:~66`, `chat_screen.dart:~215` above the chip strip,
`nodes_screen.dart:~413`, `grid_screen.dart:~625` merging the title with the picker,
`map_screen.dart:~47` as a `Positioned` overlay or a compact bar, `home_shell.dart:~384`
for settings). AppBar title becomes a constant (`Text('MeshMore')`, new l10n key or
brand literal; `l10n/app_ja.arb` must mirror). The icon-only strip may then drop its
reliance on the AppBar for orientation.

Other defects found (read-only, from code and the 2026-10-25 screenshots):

1. **"MESHMORE / S…" truncation is not the AppBar**: it is the boot overlay header,
   `lib/shell/boot_overlay.dart:195-230`: two `Flexible(Text(..., ellipsis))` at
   `fontSize 11, letterSpacing 4`; on the test phone (`font_scale 1.3`, 1080 px at 400
   dpi) the subtitle truncates ("MESHMORE / S…"). Fix by letting the pair wrap or
   dropping letterSpacing at large font scale.
2. The boot overlay ("OFFLINE — Settings → Diagnostics & connect", "SKIP") appears
   whenever the radio link is down; the shell cannot be used until skipped (observed
   screenshot `/tmp/mm1.png`, not verified in code beyond `BootOverlay` wrapping the
   scaffold, `home_shell.dart:158`).
3. `home_shell.dart:159` AppBar actions contain only the `RadioLinkIndicator`; the
   `LINKED · NO ALERTS` status slab on the dashboard (`dashboard_screen.dart:~95`)
   repeats the link state: duplicate status, inconsistent with other tabs.
4. Map has no header at all, so with an always-MeshMore AppBar there would be no tab
   name anywhere on Map unless one is added.
5. Back affordance: `PopScope` returns non-dashboard tabs to Dashboard
   (`home_shell.dart:147-155`); pushed pages show a back arrow
   (screenshot "Device configuration"). Consistent and intentional (R11).
6. All dashboards are per-skin ornament; any shared header must be skin-aware
   (`context.skin`), as `MmScaffold` already is (`lib/ui/mm_scaffold.dart:14-55`).

---

## 5. Transport selection across mobile and desktop

What exists today (no transport concept):

- Mobile config is `host`, `token`, panel side, font, compact, device id/label,
  pair name (`packages/mobile/composeApp/src/commonMain/kotlin/dev/ldmux/mobile/Config.kt:12-50`).
  `isPaired` requires a tailnet or loopback `ws://` host (`:60-75`). Settings dialog
  (`SettingsDialog.kt:22-50`): panel, font, compact, pairing only. No transport row.
- Daemon: remote listener bound from env `LDMUX_REMOTE_HOST` / `LDMUX_REMOTE_PORT`
  (`crates/daemon/src/bin/ldmuxd.rs:14-15,73-88`), optional `~/.config/ldmux/env`
  (`docs/STATE.md:~52`). Port: code default **7623**, deployed **7625**
  (`docs/REMOTE.md:37`, `ADR-0016:13`); docs are consistent about this, not a bug.
- Runtime control: newline-JSON RPC over the local control socket
  (`crates/daemon/src/control_socket.rs:131-135`), plus `ldmux code` for pairing.
- The protocol deliberately has **no** profile field: `caps.capabilities` only carries
  `scrollback`; the mesh profile is **implied by the gateway**, not negotiated
  (`docs/MESH-TRANSPORT.md:149-155,215-216`).

Recommendation (extends, does not invent):

1. **Do not add a profile field to `hello`/`caps`** (stays consistent with
   MESH-TRANSPORT.md:149-155). The path *is* the profile: a session that arrives via
   the MeshCore gateway is a `mesh` session.
2. **Mobile owns the route choice per endpoint**: add `route: tailnet | mesh` to
   `LdmuxConfig` (Config.kt) and a row in `SettingsDialog`. `tailnet` uses the existing
   `ws://` path; `mesh` talks to MeshMore's loopback gateway (L2, design in
   `meshmore-sns-architecture.md` §5.5). iOS: row hidden/disabled (tailnet only,
   architecture §1.6/O1).
3. **Daemon owns availability**: a boolean + peer binding for the mesh listener in
   `~/.config/ldmux/env` (new key) and live toggle through a new control-socket RPC
   (`mesh.status`, `mesh.enable`), surfaced in `ldmux status`. The desktop therefore
   knows (a) whether a mesh endpoint is enabled and (b) per live session which route it
   arrived by.
4. **Disagreement handling**: if the phone selects `mesh` while the daemon mesh
   listener is disabled, the L2 `BIND` fails (`BIND_ERR`, `meshcore_gateway`
   `constants.dart`) or the session times out; surface "host not listening on mesh"
   rather than silent retries. If the phone selects `tailnet` while only mesh is up,
   the WebSocket connect fails. Both are visible failures, not negotiated fallbacks.
5. **What is not possible**: the phone cannot use BLE to the radio from LDMUX itself
   (single-central link, `meshmore-sns-architecture.md` §1.1); LDMUX on iOS cannot use
   MeshCore at all; one radio carries one param set so a "protocol toggle" cannot
   switch the radio between public and private tuples without leaving the other.

---

## 6. Open questions not resolvable from evidence

1. **Is the Heltec on the computer's USB the same radio as `HELTEC-BASE` that the phone
   uses?** Evidence for "same": the serial port streamed `BLE: writeBytes/readBytes`
   debug lines (`/tmp/mc_listen.py` output) while MeshMore showed OFFLINE and the app,
   once launched, linked to `HELTEC-BASE`; the BLE-only build has no companion USB
   interface (`variants/heltec_v4/platformio.ini` `:182-190`). Not proven; compare the
   pubkey `615f431f51c96375…` with the radio's own screen.
2. Do all deployed public repeaters in the user's area drop unknown-scope floods
   (region-aware firmware)? Unknowable offline.
3. Does a real repeater relay direct `RAW_CUSTOM` on the air (code says yes,
   issue 3110 says no for some builds)? Needs a two-hop hardware test.
4. Real spectrum occupancy around 913-916 MHz at the user's location (no RF survey).
5. Whether the `STATS_TYPE_RADIO` response exposes airtime/utilisation counters (not
   read in this pass); needed for the numeric split trigger.

## 6. Verification of the load-bearing claims (main assistant, 2026-10-24)

Spot-checked in the firmware because the recommendation rests on them.

### 6.1 Private repeaters on the US band ARE possible — the whitelist is a companion-build default

`examples/companion_radio/MyMesh.cpp:1005-1021` defines the repeat-mode
frequency gate:

```cpp
static FreqRange repeat_freq_ranges[] = {
  #ifdef ALLOWED_REPEAT_FREQ_RANGE
  ALLOWED_REPEAT_FREQ_RANGE
  #else
  { 433000, 433000 }, { 869495, 869495 }, { 918000, 918000 }
  #endif
};
```

Two things follow, and the second matters more than the first:

- `ALLOWED_REPEAT_FREQ_RANGE` **is never defined anywhere in the repo**
  (`grep` over `*.ini`, `*.h`, `*.cpp` finds only the `#ifdef` and its use),
  so a stock companion build is restricted to those three frequencies. That
  means a companion node at 910.525 cannot be told to repeat.
- That gate lives **only in the companion firmware**. The dedicated
  `examples/simple_repeater/` build has no frequency gate at all: its
  `allowPacketForward` (`MyMesh.cpp:434-459`) checks `disable_fwd`, flood
  hop limits, unknown transport codes and loop detection — nothing about
  frequency.

**So a private repeater at 910.525 MHz is a supported configuration.** It
needs a radio flashed with the `simple_repeater` firmware, not a companion
build with repeat mode switched on. This is the correct answer to "can we
have private repeaters", and it was almost lost behind the companion's
build-time default.

### 6.2 Private (`$`) region keys are still non-functional

`RegionMap.cpp:175` recognises `src.name[0] == '$'` as a private region, but
`TransportKeyStore::saveKeysFor` (`:70-77`) is:

```cpp
  // TODO: update hardware keystore
  return false;  // failed
```

So only publicly derivable `#name` regions work, keyed
`SHA256("#name")` (`TransportKeyStore.cpp:44-49`). A private region name is
obscurity, not a secret: anyone who guesses the name derives the same key.

### 6.3 A repeater relays our direct raw custom, and it relays everyone's traffic

`simple_repeater::allowPacketForward` has **no payload-type test**, so a
repeater does forward direct `RAW_CUSTOM` packets. That contradicts the
community report that repeaters drop them, and it means the two-phase
carriage survives a multi-hop private link.

The same function has **no per-key access control** — `ClientACL` gates
management logins only (`src/helpers/ClientACL.h`). Therefore a repeater on
a shared frequency relays every node it hears, not just our two. A genuinely
private repeater network is only private if it is on its own frequency,
because "relay only my traffic" is not expressible in this firmware.
