# SOS and check-in — feature specification

Written 2026-11-04. Scope: MeshMore SNS (phone companion), Android. Read with
`mesh-research/notes/topics/places-sos-prior-art.md` (the prior art and the engine constants),
`meshmore-scope-of-record.md` §7 and §11 (D8.4, D8.5), and `meshmore-sns-block-spec.md` (the depth
template this document follows).

## 1. The requirement in one sentence

A person in trouble can raise an alarm that keeps repeating for an hour without drowning the mesh, and
can stop it deliberately — and a responder's acknowledgement stops it only when that acknowledgement is
cryptographically attributable.

## 2. What the prior art actually does, and what it gets wrong

The working pattern is in `uncovered/MeshCore-Solo`, `examples/companion_radio/ui-core/SosEngine.h:27-32`:

```cpp
MAX_SENDS       = 12
RETRY_MS        = 10000UL
LAST_MAX_SECS   = 3600
BEACON_MS       = 5 * 60000UL
```

So: **twelve sends, ten seconds apart, then a five-minute beacon for up to an hour, bounded by the age of
the last fix.** That is the design that reached users, and its two merits are real — the send count is
bounded, and the beacon outlives the sends so a responder arriving late still finds the alarm.

Three things it gets wrong for our product:

1. **Ten seconds is too fast for a shared channel.** Twelve sends 10 s apart is 2 minutes of repeated
   channel traffic on a mesh that carries other people's messages. The measured primary profile in the
   radio2 corpus loses packets under load already; a 2-minute burst is the load. We keep the bound and
   stretch the interval.
2. **It cannot stop on an ACK, because a channel carries no key.** The prior art matches the ACK by
   display name. A name is not an identity. Our decision D8.4 requires the ACK to come from the
   responder's key, which means the alarm must reach that responder as a direct message to be stoppable.
3. **`LAST_MAX_SECS` is a fix-age limit that suppresses the whole alarm.** A device whose last GPS fix is 70
   minutes old sends nothing at all. Refusing the *stale position* is correct — a search team sent to a
   three-hour-old coordinate is worse than one sent to no coordinate. Refusing the *alarm* is not. So we keep
   the age limit on the position and drop only the position: the alarm goes out, without coordinates, saying
   "no recent fix". This is the reconciliation with the existing normative requirement APP-H2, which forbids
   sending a stale fix as an SOS position; the alarm itself is never suppressed by fix age.

## 3. The two features are not the same feature

| | SOS | Check-in |
| --- | --- | --- |
| Trigger | User action, deliberate | User action or schedule |
| Repetition | 12 sends + 10 beacons | One send |
| Termination | Explicit cancel, or an authenticated ACK | A deadline the app watches locally |
| Wire tag | `[SOS:<id6>]` | `[CHK:<id6>]` |
| Radio feature required | None | None |

Check-in is deliberately one bounded send. It carries a deadline as text and the app marks it overdue
locally. No radio-side timer exists and none is invented — the device cannot know when its own message
arrived, and a firmware timer would be a new protocol feature we do not control.

## 4. The emergency channel, and what it costs in privacy

The fork already has an emergency-channel convention, and it decides where an SOS should go by default:

- The channel's key is **`SHA-256("#emergency")[0:16]`**, so it is derivable from the name and public by
  construction. keymind hardcodes those exact bytes (`MyMesh.cpp:387-390`), and wadamesh-tak derives the same bytes
  from the name (`resolveAliasKey`, `MediaMeshCore.h:880`). The app already computes them:
  `channelPskFromHashtag` (`packages/meshcore/lib/src/crypto/channel_crypto.dart:68`) hashes the tag with its
  leading `#`, so typing `#emergency` in the existing "Key derived from the tag" source produces the same secret.
- A channel whose companion alias hashtag tail is `emergency` is treated as an emergency channel
  (`isEmergencyNoticeChannelName`), and joining one seeds a notice: "#EMERGENCY: This is an emergency channel. Do not
  use for testing or small talk.", sent with `notify=false`.
- A received **zero-path flood** on that channel is **held and re-sent** after 120 s plus up to 15 s jitter, tracked
  in a 63-entry key table (`:350-354`, `:2253-2285`, `:12098-12102`).

Three consequences bind this spec:

1. **Default destination is `#emergency` when the radio has it.** Reach is the whole point of an alarm. Two forks
   reach the same key, so the channel is a convention rather than one fork's choice. The user may choose a private
   channel or direct messages instead. The app **does not create the channel silently**: it offers a one-tap add
   whose copy names the public key and the channel-slot cost.
2. **The copy must say the key is public.** "Anyone who knows the channel name can compute its key and read this."
   That is not a flaw in an emergency broadcast — it is the design — but no surface may call the channel private or
   encrypted.
3. **The radio itself repeats once, without the app.** If the phone dies after the first send, the held flood goes
   out about two minutes later. So "the alarm lives only in the app" is false on the emergency channel; the honest
   claim is "one repeat survives app death, the rest do not".

## 5. Wire grammar

Both are ordinary channel text or direct messages. **No new payload type.** Both start the message, as
`[SOS]` already must in `GeoUtils.h:165-172`.

```
[SOS:<id6>] <lat>,<lon> <callsign> <free text>
[SOS:<id6>] NOFIX <callsign> <free text>
[ACK:<id6>] <callsign> on my way
[CHK:<id6>] <lat>,<lon> <callsign> until <ISO-ish local time>
[CHK:<id6>] NOFIX <callsign> until <ISO-ish local time>
[SAFE:<id6>] <callsign>
```

The `NOFIX` form is used when the last fix is older than one hour. It is a literal uppercase token in the
position slot, so a receiver parses the message the same way and knows not to draw a pin. An alarm without a
position is still an alarm; an alarm with a three-hour-old position sends help to the wrong place.

- `<id6>` is six lowercase hex characters, from `sha256(request_nonce ‖ pubkey)[0..2]`. It is **not**
  time-derived and **not** secret; it exists so an ACK can name one request among several.
- `<lat>,<lon>` follows the existing `GeoUtils.h:123-131` convention: decimal point required, comma
  between, no spaces. Six decimal places at most, truncated not rounded, so the sender's own precision is
  visible.
- `<callsign>` is the device name, ≤32 bytes, and is repeated in the ACK so a listener who missed the
  original still reads something meaningful.
- Free text is ≤96 bytes. The whole message must fit the channel text ceiling of **160 bytes including the
  `sender: ` prefix**, which the composer counts as D8.3 decided.
- An SOS never carries a photo. The message must survive a 160-byte text path; a photo would make it a
  media message and change its delivery guarantees.

**Reject and warn, never truncate.** The firmware truncates over-length channel text silently. The app
counts the bytes and refuses to send an SOS that would lose its tail, because a truncated SOS loses the
callsign or the coordinate.

## 6. Data model

One row per request, keyed by `<id6>` plus the local key that raised it.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | text(6) | The wire id |
| `nonce` | blob(16) | Kept so the id can be recomputed and so a duplicate raise is detected |
| `kind` | enum | `sos`, `checkin` |
| `state` | enum | See §7 |
| `raised_at` | integer | Sender's clock at raise, milliseconds |
| `lat`, `lon`, `precision_m` | real, real, integer | Precision from the fix, not assumed |
| `fix_age_s` | integer | Age of the fix at each send; travels as text |
| `callsign` | text(32) | Copied into every send |
| `text` | text(96) | The user's words |
| `targets` | list | Channel id, plus up to 4 contact keys for the DM copies |
| `sends` | list | `(at, frame, radio, result)` per attempt, capped at 12 |
| `beacons` | list | `(at, result)`, capped at 10 |
| `ack` | object? | `{key, name, at, claimed_only}` — `claimed_only` true when it came over a channel |
| `cancelled` | object? | `{at, reason}` |

Nothing in this row is deleted when the alarm ends. An SOS history is evidence, and the block spec's rule
applies here too: a hidden row is counted, not vanished.

## 7. The schedule, exactly

Twelve sends and ten beacons, computed from `raised_at`:

| Event | Times from raise |
| --- | --- |
| Sends 1–12 | `t = 0, 60, 120, …, 660 s` |
| Beacons 1–10 | `t = 720, 1020, 1320, …, 3420 s` |
| Hard stop | `t = 3600 s` |

That is 22 packets over 57 minutes and it ends inside the hour. **This is the exact reading of D8.4, whose
original parenthetical did not add up** — "12 at 60 s (12 minutes)" plus "a beacon every 5 minutes for 60
minutes" would end at 72 minutes. The prior art's engine has `MAX_SENDS = 12` as a total, so the count is fixed
at 12 sends and the beacons start after the last send so the two never coincide. D8.4 was amended to this
arithmetic on 2026-11-04.

- Each send is a fresh frame with a **salted** payload, because the seen table hashes type plus payload and
  drops identical repeats.
- A fix older than one hour is not sent as a position (APP-H2): the send uses the `NOFIX` form instead. The
  schedule does not change — 12 sends and 10 beacons go out either way.
- Jitter each send by ±3 s so twelve devices raising alarms together do not collide in lockstep.
- An authenticated ACK stops sends and beacons at once. A channel ACK does not.
- "I'm safe" sends one `[SAFE:<id6>]` and stops.
- Battery: the beacon is 10 packets in an hour. If the device reports <5 % battery the app sends the
  remaining beacons and says so in the copy before the user raises the alarm.

**What the radio does without the app.** On the emergency channel, each zero-path flood is held and re-sent once
after 120 s + up to 15 s jitter. So an SOS on `#emergency` gets **one firmware-side repeat** per packet regardless of
app state, plus the app's 22-packet schedule while the app lives. The two do not double up in a damaging way — the
firmware repeat is one delayed copy of a packet the app already sent — but they do mean a listener may see a packet
twice, which is why every payload carries a timestamp and the id.

**Airtime budget.** An SOS frame is 130–150 bytes of channel text: the tag, the 6-hex id, the coordinate
pair, the callsign and up to 96 bytes of words. At SF7 / 125 kHz with the default coding rate that is roughly
0.35–0.45 s of airtime per packet. Twenty-two packets is **8–10 seconds of airtime spread over 57 minutes**,
about 0.25 % of a 1 % duty cycle — cheap enough that the bound exists to protect the channel from *many*
simultaneous alarms, not from one. Twenty devices raising at once would be 160–200 s in one minute, which is
why the ±3 s jitter matters more than the interval. The app refuses a 23rd packet and logs that it did.

## 8. State machine

```
idle --raise--> arming --confirm--> active --ack(key)--> acknowledged --(user dismiss)--> closed
                        |              |  --cancel-----> cancelled ----------------------> closed
                        |              |  --t=3600s----> expired ------------------------> closed
                        +--abort-----> idle
```

- `arming` exists because raising an alarm is destructive to the channel. It is a 3-second hold with the
  destination and the fix shown, not a dialog to read.
- `acknowledged` does not mean rescued. The copy says "X has seen this", never "help is coming".
- `expired` means the schedule ended, not that the situation did. The row stays openable and the user can
  re-raise, which creates a **new** id and a new nonce — never a resume, because a resume would replay a
  payload the seen table already has.
- One active alarm per device. A second raise while active is refused with the active one brought to front.

## 9. ACK attribution — the honest rule

| Path | What we know | Does it stop the alarm |
| --- | --- | --- |
| Direct message | The peer's public key authenticated the packet | **Yes** |
| Channel text | A display name in the decrypted text prefix | **No** |

- A channel `[ACK:<id6>]` is shown as **"claimed by <name>"** and the alarm keeps going. The app may offer
  "stop anyway" as a deliberate user action, never automatically.
- A direct `[ACK:<id6>]` from a key in `targets` stops the alarm. A direct ACK from a key outside `targets`
  is shown and counted but does not stop it — otherwise any contact could silence an alarm by guessing six
  hex characters. Six hex is 24 bits, which is guessable, so the key check is the load-bearing part.
- Every ACK is deduplicated per key per id. A repeated ACK from the same key is one row.

## 10. What the UI says — and what it must not say

Required, in this order, on the alarm screen:

1. **"This repeats for up to one hour."** Before the hold completes.
2. **Where it goes**: "Channel *name*" and "3 contacts" as separate lines, because they differ in what
   they guarantee.
3. **"Nobody is notified unless they are in radio range."** No promise of delivery. The mesh has no
   acknowledgement for channel text at all.
4. On the acknowledged state: **"<name> has seen this"**, plus the path — "direct" or "claimed on channel".
5. On expiry: **"The alarm has stopped repeating. It is not resolved."**

Must not say: "Help is on the way", "Sent", "Delivered", "Emergency services notified", or any spinner
that implies a network wait. A tick means *the radio accepted the frame*, nothing more.

## 11. Interaction with blocking

- A blocked key's SOS is **hidden like any other content**, per the block spec's ten-row matrix. The block
  filter runs before the SOS handler, so a blocked key cannot raise a visible alarm on this device.
- Blocking a key does **not** stop the radio's own alert engine. If the device's notification rules fire
  for that key, the buzz still happens; the app can only hide what it renders. Copy says so.
- A blocked key's ACK cannot stop the user's own alarm — correct, and also the reason the alarm's copy
  never claims "everyone has seen this".

## 12. What this feature does not do

- It does not contact emergency services. There is no gateway in this release and no address to send to.
- It does not guarantee delivery, ordering, or arrival within any time.
- It does not stop the device's firmware from sending its own configured alerts.
- It does not survive the phone being destroyed. On the **emergency channel only**, the radio holds and re-sends one
  copy about two minutes after the last one the app sent, so one repeat outlives the app; the 22-packet schedule does
  not. On any other channel nothing survives the app.
- It does not make its **own** radio buzz. The device-side alert engine is receive-side only. What the app can do is
  set the rules that make a **responder's** radio buzz without their phone (D8.24) — and a channel rule fires on every
  message on that channel, so "buzz only for SOS" is not expressible.
- It does not encrypt anything the radio does not already encrypt. On a channel, the channel key is the
  only protection.

## 13. Tests the spec requires

1. **Schedule.** Fake clock: 12 sends at 0–660 s, 10 beacons at 720–3420 s, nothing after 3600 s.
2. **Salt.** Two sends in one alarm never produce identical payload bytes.
3. **Attribution.** A channel `[ACK:<id6>]` leaves the state `active`; a direct ACK from a target key moves
   it to `acknowledged`; a direct ACK from a non-target key does not.
4. **Id collision.** Two raises in one minute produce different ids; a resume attempt creates a new id.
5. **Byte ceiling.** An SOS whose encoded text exceeds 160 bytes is refused at the composer with a count,
   and nothing is sent.
6. **Stale fix.** A fix older than an hour sends the `NOFIX` form; no coordinate appears in the text; the
   schedule still runs 12 sends and 10 beacons; and no pin is drawn for that request on a receiver.
7. **Cancel.** "I'm safe" sends one `[SAFE:<id6>]` and stops both loops; no further frames appear.
8. **Block.** A blocked key's `[SOS:<id6>]` is not rendered, not stored and increments the hidden count.
9. **Check-in.** One send only; the app marks it overdue at the deadline and notifies locally.
10. **Process death and the firmware repeat.** Killing the app mid-alarm leaves a row in `active`; on relaunch the
    app either resumes the remaining schedule with fresh sends or tells the user the alarm stopped — never silently
    neither. On `#emergency`, a zero-path flood is held and re-sent once after 120 s + jitter by the radio; the app's
    copy states that one repeat outlives the app.

## 14. Open, and honestly so

- **Whether a channel ACK should ever stop the alarm.** Decided no in D8.4; a user who wants it gets the explicit
  "stop anyway" action. Reversible cheaply if field feedback disagrees.
- **Whether to expose the alert engine's `remote` field.** Decided no by default (D8.24). It lets a contact change the
  radio's alerts over a DM with the `!notify ` prefix, which is a real convenience for a team and a real attack
  surface for everyone else. Reversible per-radio, not per-alarm.
- **Whether the app should create the `#emergency` channel itself** when the radio has none. Decided in D8.23: it
  offers a one-tap add and never creates silently, because the key is derivable from the name so creation leaks
  nothing, but it consumes a radio channel slot and puts a public channel in the user's list unasked. Reversible if
  field feedback says the extra tap costs more than the surprise does.
