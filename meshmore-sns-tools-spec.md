# Meshmore SNS — Tools (R60): UI spec

Issue: [IoTone/meshmore-sns#7](https://github.com/IoTone/meshmore-sns/issues/7)
— "built-in tester tools … under Settings → Tools".

This is the active side of mesh testing. R59 (the bot) is the passive
side: a client that answers. Tools is the client that asks, measures and
writes the result down. The two are designed to pair: a soak run from
here against an R59 echo bot on another radio yields a transcript that
shows drops, duplicates and reordering in one read.

## What the reference apps do, and what we take from them

| Reference | Tool | Take it? |
|---|---|---|
| MeshCore app (Liam Cottle), meshcore-cli | **Trace path** — pick repeaters, "add return path", per-hop SNR | **Yes — T3** |
| MeshCore app 1.34+, meshcore-cli `nd` | **Discover nearby** repeaters, SNR both ways | **Yes — T4** |
| meshcore-cli `rs`, repeater Status screen | **Status request** to a repeater/sensor | **Yes — inside T2 Ping** |
| Signal-tester apps, MeshCore `GET_STATS` | **Noise floor**, airtime, packet counters | **Yes — T1** |
| Meshtastic Range Test | Sequenced beacons, receiver logs SNR/RSSI/position → CSV | **Yes — T6** |
| meshcore-bot `test`/`ping`/`multitest` on `#test` | Bot answers on a channel | Already **R59** |
| *(nobody)* | **Soak** — sequenced sends, counted round-trips, exportable report | **Yes — T5** (new) |
| MeshCore RX Log, meshcore-cli `disc_path`, repeater login / neighbours | | Spec'd as **phase 2**, below |

Meshtastic's Traceroute and Neighbor Info have no MeshCore equivalent
beyond trace + discover; Store & Forward, Detection Sensor and
Paxcounter are not test tools and are out of scope.

## Rules every tool obeys

1. **Airtime is somebody else's too.** Every repeating tool has a
   floor on its interval and a cap on its count, both shown, never
   silently enforced. Defaults are polite (Meshtastic recommends
   15–30 s for range test; we default to 30 s).
2. **Never on Public.** Tools that send text (Soak, Range test) refuse
   any scope whose key is the public PSK — the same structural refusal
   R59 uses, not a hidden control.
3. **One remote request in flight.** The firmware keeps one pending
   request (status / telemetry / path / login) and each new one clears
   the last. So:
   - tools run one at a time (a second tool shows "another tool is
     running" and offers Stop);
   - while a tool runs, the app's own background telemetry poller is
     held, and resumes when the tool stops.
4. **Timeouts come from the radio.** `RESP_CODE_SENT` carries the
   radio's estimated timeout; a tool waits that long ×1.5 (clamped
   5–60 s) before calling an attempt lost.
5. **Offline-first.** Every tool screen renders disconnected, explains
   that it needs the radio, and its Start is disabled — same pattern as
   the rest of the app (R21).
6. **Evidence, not vibes.** Every tool that produces a series has a
   copy-to-clipboard export (JSON or CSV) carrying enough to reproduce
   the run: target, parameters, timestamps, firmware version.
7. **Firmware may not have it.** `GET_STATS` and discover are newer
   firmware. `ERR_CODE_UNSUPPORTED_CMD` is shown as "your radio's
   firmware doesn't support this" — never as a generic failure.
8. **R13 parity.** Results are text + icon; colour is never the only
   carrier (lost = ✕ + "lost", not just red).

## Information architecture

Settings hub gains a sixth row, after Diagnostics:

```
Settings
  Device configuration
  App settings
  Profile & personalization
  Channels
  Diagnostics & connect
  Tools                       ← new: "Ping, trace, soak, range test"
```

`/settings/tools` is a hub list; each tool is its own pushed route:

| Route | Tool | Needs |
|---|---|---|
| `/settings/tools/stats` | T1 Radio stats | radio |
| `/settings/tools/ping` | T2 Ping | radio + a contact |
| `/settings/tools/trace` | T3 Trace path | radio + a path |
| `/settings/tools/discover` | T4 Discover nearby | radio |
| `/settings/tools/soak` | T5 Soak test | radio + private channel or DM |
| `/settings/tools/range` | T6 Range test | radio + private channel |

Hub row: icon · name · one-line purpose · trailing "RUNNING" pill when
that tool is active. A disconnected banner tops the hub when offline.

Every tool screen has the same skeleton (skinned via `MmScaffold`):

```
┌──────────────────────────────────────────┐
│ ← Ping                                   │
├──────────────────────────────────────────┤
│ TARGET   [ Hilltop RPT ▾ ]               │  ← setup (locked while running)
│ COUNT    [ 5 ]   INTERVAL [ 10 s ▾ ]     │
│ method: status request (repeater)        │
├──────────────────────────────────────────┤
│ [ ▶ START ]                [ COPY ]      │  ← one primary action
├──────────────────────────────────────────┤
│ 3/5 · lost 1 (33 %)                      │  ← summary line, live
│ rtt min 812 · avg 1 140 · max 1 603 ms   │
├──────────────────────────────────────────┤
│ #1  ✓  812 ms                            │  ← per-attempt log, newest last
│ #2  ✕  lost (timeout 9.0 s)              │
│ #3  ✓  1 603 ms                          │
└──────────────────────────────────────────┘
```

## T1 — Radio stats

What the radio itself has seen. One-shot fetch, plus an "auto" toggle
that refreshes every 5 s while the screen is open.

- **Wire:** `CMD_GET_STATS (0x38)` with sub-type 0 (core), 1 (radio),
  2 (packets) → `RESP_CODE_STATS (0x18)`.
- **Shows:**
  - RADIO — noise floor (dBm), last RSSI, last SNR, TX airtime, RX
    airtime, and **duty cycle** = airtime ÷ uptime (%).
  - PACKETS — received / sent, each split flood vs direct; receive
    errors where the firmware reports them.
  - CORE — uptime, queue length, error flags (hex), battery mV.
- Deltas since the previous refresh are shown beside the counters
  (`+12`), so "is anything happening" reads at a glance.
- Unsupported firmware → the rule-7 message, with the firmware version.

## T2 — Ping

Round-trip to one node, N times, with loss and RTT.

- **Target picker:** synced contacts (only contacts can be addressed),
  repeaters first, then by last heard. Shows type + hops.
- **Method** follows the target's type and is displayed, not chosen:
  - repeater / room / sensor → **status request**
    (`CMD_SEND_STATUS_REQ 0x1B` → `PUSH 0x87`, matched on pubkey
    prefix). The last reply's repeater stats (battery, uptime, noise
    floor, its last RSSI/SNR) show under the log.
  - chat node → **telemetry request** (`CMD_SEND_TELEMETRY_REQ 0x27`
    → `PUSH 0x8B`). Silent for the peer; it only answers if it shares
    base telemetry with us, which the screen says up front.
- **Parameters:** count 1–20 (default 5); interval 5 s – 2 min
  (default 10 s; never shorter than the radio's timeout estimate).
- **RTT** is app-timed from the `RESP_CODE_SENT` to the reply.
- **Summary:** sent, replied, lost %, RTT min / avg / max.
- **Export:** JSON.

## T3 — Trace path

Per-hop SNR along a repeater chain, there and back.

- **Wire:** `CMD_SEND_TRACE_PATH (0x24)` `[tag u32][auth u32][flags]
  [hashes…]` → `PUSH_CODE_TRACE_DATA (0x89)`, matched on our random
  tag. Each repeater appends the SNR it heard the packet at; the final
  byte is the SNR our own radio heard the last hop at.
- **Path source** (segmented control):
  - **To a node** — pick a contact with a known route. For a
    repeater/room it is the route plus the node's own hash; for any
    other contact the repeater chain toward it. **Round trip** (on by
    default) appends the reverse so the trace comes back to us: route
    `a b` → `a b a`.
  - **Manual** — type hashes (`a1,7f,a1`); validated as hex bytes.
- Contacts without a known route (flood or advert-only) are listed
  disabled with "no route — send it a message first".
- **Result:** a vertical hop ladder, one row per hop: hash, resolved
  repeater name when we know it, SNR into that hop, and a bar. The
  weakest hop is called out in text ("weakest: 7f Hilltop, −9.5 dB").
- **Repeat:** run again; the last 10 results stay listed for
  comparison during the session.
- **Reset route** button for the chosen contact
  (`CMD_RESET_PATH 0x0D`) — the classic hop-test move: drop to flood,
  let the mesh find a path, trace again.

## T4 — Discover nearby

Which repeaters can hear us right now, and how well — both ways.

- **Wire:** `CMD_SEND_CONTROL_DATA (0x37)` with `DISCOVER_REQ (0x80)`,
  filter = repeaters, our random tag; zero-hop only. Replies arrive
  over a few seconds as `PUSH_CODE_CONTROL_DATA (0x8E)`, each carrying
  the repeater's pubkey (or 8-byte prefix), the SNR **it** heard us at,
  and the SNR/RSSI **we** heard it at.
- **UI:** "Listening… 12 s" countdown, then a list sorted by weaker of
  the two SNRs: name (resolved from contacts/adverts, else key
  prefix), ↑ SNR them-hearing-us, ↓ SNR / RSSI us-hearing-them.
- Asymmetry over 6 dB is called out — a classic sign of a deaf or loud
  node.

## T5 — Soak test

Many sequenced messages to one conversation, counted.

- **Scope:** a DM peer, or a private channel. Public is refused
  (rule 2).
- **Message:** `echo soak <run> <seq>/<count>` — `<run>` is a 4-hex run
  id, so concurrent or earlier runs never cross-match. The leading
  `echo` makes an R59 bot with the default pack answer
  `#<N> soak <run> <seq>/<count>`.
- **Parameters:** count 1–500 (default 50); interval DM ≥ 5 s, channel
  ≥ 15 s (default 30 s).
- **Measures:**
  - DM: per message sent → delivered (recipient ACK) or failed; RTT
    send→ACK.
  - Channel: per message sent (radio confirmed); flood has no receipt.
  - Both: **echoes** — replies carrying our run id, matched by seq:
    echoed, missing, duplicated, out of order; echo RTT.
- **Live summary:** sent · delivered · failed · echoed · dup · reordered,
  plus elapsed / remaining time.
- **Export:** JSON report: run id, scope, parameters, firmware version,
  start/stop, every message's seq, sent-at, outcome, rtt, echo-at.
- Messages are ordinary messages — they appear in the conversation's
  history, which is the point (the transcript is evidence).

## T6 — Range test

Meshtastic-style: one radio beacons, another walks and logs.

- **Scope:** a private channel (Public refused). Both ends use the
  same channel.
- **Sender:** every interval (≥ 15 s, default 30 s; stops after count
  or 8 h, whichever first) sends `RT <seq> <lat>,<lon>` with our best
  location (device first, phone fallback — R22), or `RT <seq>` without
  one.
- **Receiver:** logs every `RT` heard on that channel: seq, time,
  SNR, hop count (flood/path), sender position, our position, distance
  when both are known. Missing seqs are counted as lost.
- **UI:** mode toggle Sender / Receiver; live counters; table, newest
  first; best SNR and farthest distance called out.
- **Export:** CSV (`seq,time,snr_db,path_len,sender_lat,sender_lon,
  rx_lat,rx_lon,distance_m`) to the clipboard.

## Phase 2 (spec'd, not built)

- **RX log** — parsed `PUSH_CODE_LOG_RX_DATA` stream: payload type,
  route, path, SNR/RSSI, with channel names decoded where we hold the
  key. (Diagnostics' raw frame log covers the need meanwhile.)
- **Path discovery** — `CMD_SEND_PATH_DISCOVERY_REQ (0x34)` →
  `PUSH 0x8D`, showing outbound and return routes; not stored on the
  contact.
- **Repeater sessions** — login (`0x1A` → `0x85/0x86`), the full status
  page, neighbours (`BINARY_REQ` type 0x06) and owner info.
- **Trace history** — chart per path across sessions.

## Implementation notes

- New codec: `getStats`, `sendStatusReq`, `sendTracePath`,
  `resetPath`, `sendDiscoverReq`; inbound `StatsFrame`,
  `StatusResponseFrame`, `TraceDataFrame`, `ControlDataFrame`;
  `AckFrame` gains the firmware's round-trip ms.
- `MeshcoreController` gains only seams: the inbound frame stream, a
  tool request send that keeps the chat SENT/ACK correlation aligned,
  and a hold on the background telemetry poller.
- `ToolsController` (Provider, app-scoped so a soak survives leaving
  its screen) owns "one tool at a time". Each tool is a ChangeNotifier
  over the controller and an injectable clock, tested against the fake
  transport without a radio (`test/tools/tools_test.dart`).
- Status: built (R60 / U17); **not yet run against real radios.**
- Strings in EN + JA in lock-step.
