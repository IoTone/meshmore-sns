# Telemetry and coverage — feature specification

Written 2026-11-04. Scope: MeshMore SNS (phone companion), Android. Read with
`mesh-research/notes/topics/companion-behaviour.md` §5 (§4 for the request shape, §6 for what is worth
showing), `coverage-and-simulation-tools.md` §1 (the working ping mechanism), and
`meshmore-scope-of-record.md` §11 (D8.17). Two features that share one privacy decision and must be read
together, because both put positions on a screen.

## 1. The two requirements in one sentence each

**Telemetry:** the app reads the radio's own health numbers and renders them as sentences a person can act
on, not as a hex dump. **Coverage:** the app measures where the mesh hears you by pinging and counting real
replies, and draws only the links that were actually observed.

## 2. Telemetry — request and push

The companion request is undocumented in the firmware's own telemetry document and exists only in code:

| Request | Bytes | Answers |
| --- | --- | --- |
| Self | `[39][0][0][0]` — exactly four, last three ignored | An unsolicited push `0x8B` + reserved + 6-byte key prefix + LPP payload |
| Peer | `[39][tag u32][pubkey 32]` | The same push shape, through the **single** pending-request slot |

**The request-slot limit is the design constraint, and it is narrower than "one request".** The mechanism is one
**live** request plus eight remembered `(peer, tag)` guards (`CompanionDelayedReplies.h:16-18`, kinds `Login`,
`Status`, `Telemetry`, `Discovery`, `Binary`), and `Trace` has its own guard path that does **not** take the live
slot. So:

- **Self telemetry never contends.** `CMD_SEND_TELEMETRY_REQ` with `len == 4` is answered synchronously in the
  command handler (`MyMesh.cpp:7572-7590`); only a **peer** request calls `beginPendingRequest`.
- A **peer** request takes the one live slot. The app coalesces: two peers asked in one second become one in flight
  and one queued.
- A duplicate `Login` to the same peer is refused by the firmware while one is held, so the app must not retry a login
  blindly.
- A request with no answer within 10 s (`DELIVERY_GRACE_MS`) is reported "no answer" and the slot released. It is not
  retried automatically — a retry would take the only slot again.

The push arrives without correlation to the request. So the app correlates by the 6-byte key prefix in the
payload and by request order: one outstanding request means the next push is its answer. That is the only
correlation available and the copy must not imply more.

## 3. The decoding table

LPP units, and the one field that is routinely misread:

| Field | Encoding | Render |
| --- | --- | --- |
| Temperature | whole °C, −50…+77 | `23 °C` |
| Battery | hundredths of a volt, 1.88–4.40 V | `3.87 V` |
| External I²C voltage | 15-bit code at 0.02 V | `4.12 V` |
| **Noise floor** | **code table, not dBm** | see below |
| Last RSSI | signed dBm | `−97 dBm` |
| Last SNR | signed dB, quarter steps | `+7.25 dB` |
| TX airtime | 32-bit seconds | `12 m 04 s` |
| RX airtime | 32-bit seconds | `1 h 03 m` |
| Queue depth | count | `3 waiting` |

**Noise floor is a code table and must never be plotted as a number.** `0` → −120 dBm, `1` → −119,
`2` → −118, `3…29` in 2 dB steps to −64, `30` = MAX (above −64), `31` = Missing. Plotting the raw code as
dBm is off by 120 dB. The renderer maps the code to its dBm or to the words "at the floor" / "above −64" /
"unknown"; the raw code appears only in the diagnostics export.

## 4. What the telemetry screen shows, and the order

1. **A sentence first.** "Good, because 6 neighbours heard in the last 10 minutes." A percentage alone is
   not actionable; the sentence names the evidence.
2. **Four fault conditions as words**, not a bitmask: each named, each with what it means for the user.
3. **Duty cycle**, TX and RX airtime as a fraction of the hour, because that is the legality story made
   concrete.
4. **Battery and temperature** as numbers with a trend arrow over the last hour, not a single reading.
5. **Noise floor and last RSSI/SNR** last, because they matter only when something is wrong.
6. **Raw LPP and the request hex** behind a "show the bytes" affordance, for bug reports.

Values older than 10 minutes render greyed with "as of 14:02". A stale number shown as live is a lie.

## 5. Telemetry privacy

Positions are sensitive and the radio's own status contains none — but the *coverage* data does, and the two
are shown on the same screen. Rules:

- Telemetry contains no position. It is radio health only.
- The coverage layer is **off by default**, opt-in per session, and says what it records before it starts.
- Nothing telemetry-related leaves the device. There is no analytics, no cloud, no MQTT. The wardrive prior
  art's MQTT observer path is deliberately **not** implemented: it publishes positions to a third-party
  broker, which contradicts the app's privacy position. Out-of-band observers are excluded, not deferred.
- A diagnostics export the user triggers is the only way any of it leaves the device, and it is explicit.

## 6. Coverage — the ping

No new protocol. The mechanism is published prior art and reuses existing commands:

1. A **zero-hop advertisement** so neighbours update their tables.
2. `CMD_SEND_CONTROL_DATA (55)` with subtype **`DISCOVER_REQ` (0x8)** carrying an **8-character ping id**.
3. A response is **any** correlated frame: `0x84` ACK or `0x8E` control data carrying `DISCOVER_RESP`, matched
   on the 8-character id.
4. Each response records: responder key, RSSI, SNR, hops, the sample's position and time.

**Correlation is the known bug in the prior art** — the wardrive corpus records a response-correlation defect.
Our rule: a response counts only when its 8-character id matches exactly and its arrival is within the
session window. A response with no matching id is counted as "unmatched" and shown separately, because an
unmatched response is evidence of *something* even when it cannot be attributed.

## 7. Pacing

Decided D8.17: **1 ping per 30 seconds, and 1 per area per hour, jittered.**

- The 30-second floor is a hard rate limit at the send path.
- The area limit uses **geohash precision 6** (~1.2 km × 610 m) — one ping per cell per hour. Standing still
  costs one ping an hour, which is the point.
- Jitter the interval by ±20 % so several phones in one place do not ping in lockstep.
- No firmware-side reply cap was found in the companion or repeater code read, so the app paces itself and
  the copy says the app is doing the pacing — it cannot promise other clients will.
- A manual "ping now" overrides the area limit once, and only once, per hour. It does not override the
  30-second floor.

## 8. The coverage cell model

Aggregation follows the prior art's published algorithm, which is the closest thing to a validated model:

| Dimension | Rule |
| --- | --- |
| Cell | geohash precision 6, ~1.2 km × 610 m |
| Time weight | <1 day 1.0, week 0.8, month 0.5, older 0.2 |
| Contradiction | if newer samples show the opposite, older samples drop to 0.1 |
| Edges | **observed only** — a link is drawn only when a response came back |
| Sample trigger | every 5 m of movement, not on a timer |

- "Opposite" means a success where the cell previously only failed, or a failure where it previously only
  succeeded. The demotion is to 0.1, not to zero: an old observation is weak evidence, not no evidence.
- The cell's score is the time-weighted mean of its samples, and the UI shows the sample count beside it.
  "80 %" from two samples is not the same claim as "80 %" from forty.
- **Storage**: SQLite, columns position, timestamp, 8-char geohash, rssi, snr, ping success, indexed on
  geohash and timestamp. The same shape as the prior art, because it is the shape that supports the query
  "what happened in this cell this week".

## 9. Observed-only edges, stated as a hard rule

The prior art's change log records the bug we must not repeat: "Edges no longer connect to nearest repeater;
only show actual response paths." So:

- An edge exists **only** between a sample's position and a responder that actually answered.
- The app **never** infers a link from proximity, from an advert heard, or from a repeater's existence.
- No line is drawn to "the nearest repeater" under any circumstance. A map that guesses at links is worse
  than a map with no links, because the guess is indistinguishable from a measurement.
- An edge is drawn once per observed pair per session, and its thickness is the count of successful
  responses — not a modelled signal strength.

## 10. What the coverage screen says, and what it must not say

Required:

1. Before starting: **"This records where you are and who answered. It stays on this device."**
2. During: the current cell's count, and the time until the next allowed ping.
3. After: **"3 of 7 pings answered"**, never "coverage 43 %" — the denominator is what was tried, not what
   exists.
4. On an unmatched response: **"One reply could not be identified."**
5. On a blocked key: counted, not drawn. "2 hidden" beside the totals.

Must not say: "Coverage map", "Signal strength map", "Range 4 km", "Dead zone", or any word implying the
coloured area is where the mesh reaches. It is where *this device's pings were answered*. A hole in the map
is a hole in the sample, not a hole in the mesh.

**Block interaction**, per the scope of record's decision: a blocked node's responses are **counted as
reception evidence** but excluded from coverage *results* and never drawn. "3 hidden" is shown so the map
does not silently understate the mesh.

## 11. What these features do not do

- Telemetry does not query the mesh. It asks the connected radio about itself.
- Coverage does not measure range. It records which pings were answered, where, and when.
- Coverage does not publish anything. The MQTT observer path is excluded on privacy grounds, not deferred.
- Neither stores a position without the user having opted into the coverage session.
- Neither claims a link exists because two nodes are near each other.

## 12. Tests the spec requires

1. **Self request bytes.** The request is exactly `[39][0][0][0]`; a five-byte request is refused.
2. **Noise code.** Code 0 renders "−120 dBm"; 2 renders "−118"; 30 renders "above −64"; 31 renders "unknown";
   and the raw code appears only in the export.
3. **Single slot.** A second telemetry request while one is outstanding is queued, not sent; the UI shows
   "waiting for the radio" when the slot is held by a login.
4. **Timeout.** A request unanswered after 10 s reports "no answer", releases the slot, and is not retried.
5. **Stale value.** A 15-minute-old reading renders greyed with its time and is not presented as live.
6. **Ping shape.** A ping emits a zero-hop advert then `DISCOVER_REQ 0x8` with an 8-character id.
7. **Correlation.** A `0x84` and a `0x8E` carrying the matching id both count; a mismatched id counts as
   unmatched; neither is attributed to a responder it did not come from.
8. **Pacing.** The 31st second's ping is allowed; the 29th is refused; a second ping in one geohash-6 cell
   within an hour is refused; the manual override works once per hour.
9. **No inferred edges.** A responder heard by advert but never replying produces no edge; a nearby
   repeater produces no edge.
10. **Block.** A blocked key's responses are counted, excluded from results and absent from the map; the
    hidden count is visible.

## 13. Open, and honestly so

**Decided from the mechanism (D8.26).** Request ordering is the app's job because the firmware has no priority:
background telemetry polling yields silently and does not queue; a user-initiated request waits with a visible
"waiting for the radio"; a user-initiated login may abandon a *background* request via `abandonRequest()` but never a
user-initiated one. No silent pre-emption — a request the user asked for must never vanish without a trace.

- **Whether the coverage layer should persist across sessions at all.** The prior art stores in SQLite and
  maps over weeks. Persisting positions on a device is a privacy commitment that has to be stated in the
  data-safety declaration, and "off by default, session only" is cheaper to defend than "stored for a
  month". Decided session-only for this phase; the schema supports persistence when the privacy wording
  exists.
- **The wardrive app's own source is a second repository and was never read**, so its geohash weighting and
  its MQTT auth are inherited as *published description*, not as verified code. The numbers in §8 are its
  description, not our measurement. Reversal cost: low, because the model is a default and the schema is
  additive.
