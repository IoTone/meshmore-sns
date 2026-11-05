# Places on the map — feature specification

Written 2026-11-04. Scope: MeshMore SNS (phone companion), Android. Read with
`mesh-research/notes/topics/places-sos-prior-art.md`, `mesh-research/notes/topics/place-report-encoding.md`
(`:43-71`), `meshmore-scope-of-record.md` §7 and §11 (D8.2, D8.16), and `meshmore-sns-block-spec.md`
(the depth template).

## 1. The requirement in one sentence

A user drops a pin with a type, a short label, an optional photo and a short life, and every receiver
computes the same identity for it, so two reports of the same thing merge instead of piling up — while the
pin expires on its own without anyone deleting it.

## 2. The three conventions that already exist, and why we add a fourth

| Convention | Where | Carries | Cannot carry |
| --- | --- | --- | --- |
| `[WAY]<lat>,<lon> <label>` | `GeoUtils.h:102-105` | A waypoint | A TTL — appending one corrupts the label |
| `[LOC]<lat>,<lon>` | `GeoUtils.h:150-156` | A position only | Any label or life |
| `[SOS]<lat>,<lon> …` | `GeoUtils.h:165-172` | An alarm | Anything else; must start the message |
| `[PLACE]<lat>,<lon> <label> [<type>] [TTL:<dur>]` | **this spec** | Type, label, life | Nothing the others carry |

`[WAY]` and `[LOC]` stay readable to us and we stay readable to them — a `[PLACE]` message still resolves
its coordinates in any client that parses decimals. The suffix grammar is safe **only because the tag is
new**: no existing client parses `[PLACE]`, so a trailing `[TTL:6h]` cannot corrupt a label the way it would
inside `[WAY]`.

## 3. Wire grammar

```
[PLACE]<lat>,<lon> <label> [<type>] [TTL:<duration>]
```

Anchored, right to left:

1. **`[TTL:<duration>]` must be the last token**, exactly one, optional. Absent means 24 h.
2. **`[<type>]` is immediately before the TTL**, or last when there is no TTL. A bracketed word in that
   position is a type: if it is in the closed set of §4 it is used, and if it is not it renders as `other`
   while the token is kept in the row and shown in the detail sheet. A bracketed word anywhere else is part of
   the label — that is the rule that keeps a label like "the old [ford]" intact.
3. **`<label>`** is everything between the coordinate pair and the type token, trimmed. ≤60 characters.
   Must not be empty: a place with no words is a `[LOC]`.
4. **`<lat>,<lon>`** follows `GeoUtils.h:123-131`: decimal point mandatory, comma between, no spaces, ≤6
   decimal places, truncated not rounded.

Examples:

```
[PLACE]51.500741,-0.124596 Water at the ford [water] [TTL:2d]
[PLACE]51.500741,-0.124596 Bridge out, do not cross [hazard] [TTL:6h]
[PLACE]51.500741,-0.124596 Old [ford] marker [look] [TTL:12h]
```

Durations are one of `15m`, `30m`, `1h`, `3h`, `6h`, `12h`, `24h`, `2d`, `3d`, `7d`. Ten values, parsed by
exact string match. Anything else means the message is not a place — parse failure is silent to the
renderer and the message shows as ordinary text.

## 4. The closed type set

Nine values, lowercase ASCII, no spaces. The set is closed because the type drives the icon and the filter,
and an open set produces one icon per user.

| Token | Icon meaning | Default TTL |
| --- | --- | --- |
| `hazard` | Warning triangle | 6 h |
| `water` | Droplet | 2 d |
| `fuel` | Canister | 2 d |
| `med` | Cross | 12 h |
| `rally` | Flag | 12 h |
| `view` | Eye | 7 d |
| `camp` | Tent | 3 d |
| `look` | Pin | 1 h |
| `other` | Plain pin | 24 h |

- Default TTL applies only when the sender omits one. A receiver never changes a TTL it was given.
- A custom type is not expressible as a set member. A user who wants one puts it in the label; the icon stays
  `other`. That is the honest trade: an open type set costs every receiver an icon it cannot draw.
  That is the honest trade: an open type set costs every receiver an icon it cannot draw.
- Adding a tenth token later needs no version field: an old receiver renders it as `other` and keeps the token
  in the detail sheet, which degrades without failing. The set lives in one table in the app, not in the
  firmware.
- **Token length is a design constraint, not a style choice.** `[med]` costs 5 bytes and `[medical]` costs 9,
  out of a 160-byte channel text that also carries the coordinate pair and the label. The short forms are the
  ones that survive the budget.

## 5. The deterministic id

```
id = hex(sha256(pubkey ‖ latE6 ‖ lonE6 ‖ type))[0:8]
```

- **`pubkey`** is the reporter's 32-byte key. Where the report arrived as channel text there is no key — the
  sender's name is all the text carries — so the id uses the name's bytes and is marked `unkeyed`. An
  unkeyed id is still deterministic, but two reporters who share a name collide. Copy says "from a channel,
  identity is a name".
- **`latE6` / `lonE6`** are the truncated coordinate at six decimal places, as signed 32-bit integers. The
  name is the precision, not a habit: an earlier draft of this spec spelled the field `latE7` while its own
  text and the implementation used six places, and a second implementation reading the name literally would
  have derived a different id. They are the *truncated* values that travel, so every receiver computes from
  the same digits.
- **`type`** is the token's bytes. Two types at one coordinate are two places, which is correct: a hazard at
  a water point is not the water point.
- **No time.** Decided D8.2. A renewal keeps the id and changes the timestamp; a time bucket would make
  every renewal a new place and defeat merging. Reversal cost is medium because ids are persisted.
- **Collision handling.** Two different places with the same 8-hex id is 1 in 4 billion; when the app sees
  the same id with coordinates differing by more than the precision, it keeps both and suffixes the display
  name rather than merging. Merging wrong is worse than showing two.

## 6. Duplicate suppression and renewal

- Suppression is **per id**, newest timestamp winning. One row per reporter per location per type.
- A renewal is a **new report with the same id and a new timestamp** — not a mutation. The wire stays
  stateless and the seen table stays happy.
- A receiver that already has a live row for the id updates `lastSeen` and the timestamp, and does not
  create a second pin. It does **not** re-notify unless the user asked to be told about changes.
- **Salt every resend.** The seen table hashes type plus payload and drops byte-identical repeats, so a
  renewal must differ by at least one byte. The timestamp is inside the text, so a genuine renewal always
  differs; a *retry* of an identical message must not be sent at all.

## 7. Rate limits and TTL bounds

Decided D8.16: **6 reports per node per hour, burst 2 in 5 minutes.** Enforced at the send path, per
reporter key, not per channel. Exceeding it shows "you have sent 6 in the last hour" with the time the next
one is allowed — never a silent drop.

TTL bounds: minimum 15 m, maximum 7 d. A shorter TTL is raised to 15 m; a longer one is refused with a
reason. The sender's chosen TTL travels unchanged in the text; the clamp happens at the composer, so what
arrives is what was intended.

## 8. Data model

| Field | Type | Notes |
| --- | --- | --- |
| `id` | text(8) | Derived, stored so renewal finds the row |
| `unkeyed` | bool | True when the id used a name instead of a key |
| `type` | enum(9) | The closed set |
| `label` | text(60) | The words |
| `description` | text(160) | Optional longer text; channel text carries only the label |
| `lat`, `lon` | real | As received, truncated to 6 dp |
| `precision_m` | integer | Sender's stated precision, or the fix's accuracy |
| `reporter_key` | blob(32)? | Absent for channel text |
| `reporter_name` | text(32) | Always present |
| `provenance` | enum | `gps`, `phone`, `pinned`, `received`, `inferred` |
| `sent_at` | integer | Sender's clock; **clamped to now on receive** |
| `expires_at` | integer | `sent_at + ttl`, clamped to now + ttl when the clock was unset |
| `photo_ref` | object? | Content hash plus a transport hint; bytes ride the media path |
| `last_seen` | integer | Last report of this id received, not the sender's claim |
| `kept` | bool | Local pin; does not extend the wire TTL |

**`last_seen` is our clock, not the sender's.** A node whose clock is a day behind must never read
"1 d ago" as an accusation of staleness — the team app's backlog lists exactly this bug. The rule: display
time from the sender's timestamp, but validate it; a timestamp in the future or more than 7 d in the past
renders "time unknown" rather than a number.

## 9. Precision and grid snapping

**Precision is a user choice; grid snapping is the privacy default.** That is the scope of record's ruling and
it needs an exact rule or it is a slogan:

| Precision choice | What is stored and sent | What it protects |
| --- | --- | --- |
| Exact | The fix as received, truncated to 6 dp | Nothing; ~11 cm |
| Snapped 100 m | Rounded to 3 dp (~110 m) | Which building you are in |
| Snapped 1 km | Rounded to 2 dp (~1.1 km) | Which street you are on |

- The default for a place created at the user's own position is **snapped 100 m**, because "hazard here"
  rarely needs better than a hundred metres and a pin at your exact feet is a pin at your home.
- The default for a place dropped at a map point the user chose is **exact**, because the user aimed at it.
- Snapping happens **before** the id is computed, so the id and the transmitted digits agree. An unsnapped
  receiver would compute a different id for the same place, which is exactly the duplicate the id exists to
  prevent.
- The precision the sender chose travels in the binary form and is inferred from the decimal places in the
  text form: six places means exact, three means 100 m, two means 1 km. A receiver renders the accuracy circle
  at the sender's precision, never tighter.
- A receiver MUST NOT re-snap. Re-snapping changes the id and breaks merging.

## 10. Surfaces

| Surface | Behaviour |
| --- | --- |
| Map pin | Icon by type, **colour-coded until tapped**, then neutral — the team app's backlog finding |
| Pin detail | Who sent it, when, the label, the TTL, "expires in 4 h 12 m" |
| Expiry | Pin leaves the layer; the row moves to the local history list |
| History list | Every expired and live place this device saw, with its final state |
| Filter | By type and by "expires within"; a filter is per session |
| Search | Label and reporter name; **blocked keys never appear** |
| Photo | Shown only when the bytes are present; a reference without bytes shows "photo not fetched" |
| Ledger export | After-action record: what was reported, by whom, when, confirmed or not |
| Block interaction | A blocked key's places are hidden and discarded, and stored rows for that key are deleted |

The "colour-coded until tapped" rule matters: an unread place is a *report you have not seen*, and after
you tap it, it is knowledge you have. That distinction is cheap to build and impossible to retrofit.

## 11. Confirmations and refutations

A place is one person's claim. A confirmation is another person saying "still true", and a refutation saying "it is
gone". There is no prior art for this in the ecosystem — the nearest material is waypoint transport, which has no
tally at all — so this is a design, not an inheritance.

**Wire grammar.** Two reply tags, same shape as the SOS replies:

```
[CONFIRM:<id8>] <callsign>
[REFUTE:<id8>]  <callsign>
```

`<id8>` is the place's 8-hex id. The callsign is repeated so a listener who missed the original still reads
something. Both are ordinary channel text; neither is a new payload type.

**Attribution.** The same rule as the SOS ACK:

| Path | What we know | How it counts |
| --- | --- | --- |
| Direct message | The peer's key authenticated the packet | **Key-bound** — counts fully |
| Channel text | A display name in the decrypted text | **Claimed** — counted separately, shown as "claimed" |

A refutation from a key-bound source **hides the pin** on that device; a claimed refutation only adds weight
against it. A key-bound refutation cannot delete another reporter's place, because a place is a report and only its
reporter's expiry ends it.

**Rules.**

1. **One count per key per id.** A repeated confirmation from the same key updates its timestamp, not its count.
2. **A confirmation does not extend the TTL.** It is weight, not renewal. The scope of record is explicit that only a
   deliberate renewal changes a place's life; a confirmation that extended it would let a stranger keep a wrong pin
   alive.
3. **Display five, count the rest.** "5 confirmations" plus "+12 more" — a number that keeps growing is not more
   persuasive, and the screen stays readable.
4. **Never relay a confirmation.** A confirmation is cheap but not free; a node that relays confirmations multiplies
   channel load without adding information.
5. **A confirmation is not a moderation action.** Hiding by key-bound refutation is a local visibility rule, not a
   takedown; it does not travel to another device (D8.12).
6. **Rate limit shares the place budget.** A confirmation is a place-family message and counts against the 6-per-hour
   limit; otherwise the limit is trivially bypassed by confirming instead of reporting.

**What it makes possible:** "3 confirmations" as a social signal that costs almost nothing on the wire, and a map
that degrades gracefully — a pin refuted by two key-bound sources quietly leaves the layer while its history stays.

**What it does not do:** it does not reach consensus, does not resist a sybil (a name on a channel is not an
identity), and does not replace the TTL. Two strangers confirming a false hazard is indistinguishable from two
people confirming a real one.

## 12. What the UI says — and what it must not say

Required:

1. **"Expires in 4 h 12 m"** on the pin, always, because the TTL is the feature.
2. **"Reported by <name>, <time>"**, with the provenance: "from the sender's GPS", "from their phone",
   "placed by hand".
3. On a channel-sourced place: **"Identity is a name on a channel, not a key."**
4. Before sending a photo: **"The photo may not arrive. The text will."**

Must not say: "Verified", "Confirmed" unless a human confirmed it, "Official", or any word that implies a
map pin is authoritative. A place is one person's claim with a date.

## 13. Binary second, text first

The text convention ships first because it works on any channel through any number of hops on any client.
A binary form on the channel datagram path ships when `0x3E` exists, carrying type, precision and the photo
reference without spending characters. Rules:

- **The binary form never replaces the text announcement.** A binary-only place is invisible to every
  other client, which is the failure mode the text convention exists to avoid.
- **Same id derivation in both forms**, so a text place and its binary twin merge into one pin.
- **Never a new top-level payload type.** Channel datagram with a group-data type, or text.

## 14. What this feature does not do

- It does not build a curated POI database. Places expire because they are reports.
- It does not make a place outlive the reporter's knowledge. A "keep" pins the row on this device only.
- It does not guarantee the photo arrives. A photo is fetchable on demand and may never be fetched.
- It does not carry a custom type. An open set costs icons nobody can draw.
- It does not survive the channel's own key changing. A renewed key means a new channel identity and the
  old pins are stranded — they stay in history and stop receiving renewals.

## 15. Tests the spec requires

1. **Round trip.** Every one of the nine types encodes and parses, with and without a TTL.
2. **Anchoring.** `[PLACE]51.5,-0.12 Old [ford] marker [look] [TTL:12h]` parses type `look`, label
   "Old [ford] marker".
3. **Unknown bracket in the type position.** `[PLACE]51.5,-0.12 Meeting [shelter] [TTL:1h]` renders as type
   `other` with "shelter" retained and shown in the detail sheet.
4. **Id stability.** The same key, coordinates and type produce the same id across restarts, across the text
   and binary forms, and across a snap-then-send round trip.
5. **Id separation.** Changing only the type changes the id; changing only the timestamp does not; changing the
   precision from 6 dp to 3 dp changes it, and the sender computes the id from the same 3 dp it transmits.
6. **Renewal.** A renewal updates `last_seen` and the timestamp and does not create a second pin.
7. **Clock clamp.** A timestamp 30 d in the future is clamped to now and the row flags "time unknown".
8. **Rate limit.** The seventh report in an hour is refused with a time; the third in five minutes is
   refused.
9. **Expiry.** At `expires_at` the pin leaves the layer and appears in history with its final state.
10. **Block and confirmations.** A blocked key's places are absent from the map, the list and search, and its
    stored rows are deleted when the block is set. A blocked key's confirmation neither counts nor appears. A
    key-bound refutation hides the pin; a claimed one only adds weight; neither deletes the row.

## 16. Open, and honestly so

**Decided, from the evidence rather than preference.**

- **An unkeyed place IS shown by default**, labelled "identity is a name on a channel". The reasoning is the
  asymmetry of the two failures: showing a spoofed pin costs a wrong marker with a TTL and a visible reporter name,
  while hiding unkeyed pins costs a stranger's warning — and strangers warning each other is most of what a field
  mesh is for. Solo's `[WAY]` has no key at all and people rely on it in the field. Ranked below keyed places, with a
  per-channel "keyed only" filter offered. **The consequence that must be stated:** an unkeyed place cannot be blocked
  by key, because there is no key — a block filters keyed content only, and a name-only place is filtered only by the
  channel-level switch.

**Still open, honestly.**

- **The tenth type token.** The set is closed at nine. Whether a `shelter` or `crossing` token earns a place is a
  field question, not a design one. Adding one is a versioned change that degrades to `other`.
- **Whether a refutation should expire the place early.** It currently only hides it locally. A key-bound refutation
  from three distinct keys could reasonably shorten the TTL for everyone — but that is a consensus mechanism this
  design deliberately avoids, and it would let three colluding names clear a real hazard.
