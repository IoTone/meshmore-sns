# Blocking a key — feature specification

Written 2026-11-04. Scope: MeshMore SNS (phone companion). Read with
`mesh-research/notes/topics/blocking-and-ignore.md` (the firmware evidence) and
`meshmore-master-plan.md` §9.8 (the decision and its limits). Every firmware claim here has a `file:line`
locator in the note; nothing here is inferred from a README.

---

## 1. The requirement in one sentence

A user can stop seeing content from a public key on every surface of the app, and the app tells the truth about
the three things it cannot stop: the radio receiving the packet, the radio relaying it for other people, and the
radio's own buzzer.

## 2. Why it is app-side

No firmware read has a per-sender block, mute, ignore or denylist. The nearest verb is output-scoped —
`setNotificationOutputMute(mesh::notify::Output, bool)` takes `Sound` or `Vibration`, never a key
(`meshcore-keymind/examples/companion_radio/MyMesh.h:334`). Contact removal genuinely stops **direct** messages,
because decryption needs the contact (`src/helpers/BaseChatMesh.cpp:334-352`) and the ACK is generated only after
decryption and contact match (`:395-401`) — but the next advert re-adds the key (`:249-329`), and **channel
messages have no sender gate at all** (`:602-618`).

So the block is a store in the app. The only radio-side help in the ecosystem is the keymind fork's `dm.one_key`
consent gate (`NodePrefs.h:121`, default off), which refuses unknown senders and holds up to 15 of their DMs.

## 3. The three actions

| Action | Where it happens | What it stops | What it cannot stop |
| --- | --- | --- | --- |
| **Block** (a keyed store) | App | Every surface the app renders: channel timeline, DM list, threads, search, map places, app notifications, unread counts | The radio receiving, relaying or storing the packet |
| **Remove contact** (optional, offered in the same flow) | Radio, `CMD_REMOVE_CONTACT` `0x0F` | Direct messages, ACKs and offline-queue storage for that key — until its next advert | Channel messages; re-add at the next advert |
| **Consent gate** (where the fork has it) | Radio, `dm.one_key` | DMs from keys that are not contacts, with a signed refusal marker back to the sender | Anything for keys already in the contact table |

The UI presents these as one flow with two switches, not as three concepts. "Block" alone is the app-side store.
"Also remove the contact" is a checkbox on by default, with its expiry explained.

## 4. Data model

```
BlockedKey {
  pubKey: 32 bytes          // authority. Never a name, never a prefix.
  name:   string?           // snapshot for display only, may be stale or wrong
  since:  int64             // epoch ms, local clock
  reason: enum { user, report, imported }
  notifySuppressed: bool    // default true
}
```

- Stored in the encrypted store that N3 creates, keyed by hex of the full public key. A block set before N3 lands
  goes in the same store the contacts use, not in `SharedPreferences`.
- **Never key on a display name.** A name match *pins* the key once; a key-suffix match with no name match is
  refused and logged. Four hex characters are not an identity — the XR client's rule, learned from an incident
  where a stranger named `7182` with key suffix `d563` was treated as the operator's own hardware across 350
  contacts.
- The store is bounded (default 500 keys) and the bound is visible. A block list that silently drops entries is
  worse than no block list.

## 5. Surfaces the filter must cover

Filtering only the timeline is the failure mode. Every row is a test.

| Surface | Behaviour | Notes |
| --- | --- | --- |
| Channel timeline | Messages from a blocked key are **not rendered and not stored** | New arrivals are discarded on sight; existing rows for that key are deleted when the block is set. The radio still holds its own copy |
| Unread counts and badges | Blocked messages do not count | Otherwise the badge is a lie |
| DM list and thread | Thread deleted; the header shows "Blocked" and an unblock action | Unblocking does not restore what was discarded — say so at the moment of blocking |
| App notifications | No notification is raised for a blocked key | The app cannot stop the radio's buzzer; it can stop its own |
| Search | Blocked key's messages and name do not appear | Search over history is the most common leak |
| Map places | Places whose `createdByKey` is blocked are hidden **and deleted** | Including cached place photos and echoes; the sender can re-report and it is discarded again |
| Node roster, horizon, topology | Hidden from lists and diagrams | With a count, not silently absent (§7) |
| Telemetry polling | Stop querying the key's telemetry | A request to a blocked key is a relationship |
| Coverage ping results | Excluded from the *result* table; its replies still count as reception evidence | Otherwise the coverage figure is wrong |
| Contact-list replay | Filter applied on replay as well as on arrival | A reconnect replays the whole list; arrival-only filtering leaks here |

## 6. State machine

```
visible ──block──▶ blocked ──unblock──▶ visible
                      │
                      ├── key removed from contacts?  (optional, default yes)
                      ├── advert arrives from key?    → stay blocked; hidden immediately, contact removed
                      │                                 again at most once per hour
                      ├── queued message from key?    → sync it, then drop it
                      └── already-stored message?     → deleted when the block is set
```

**Three actions, one state.** The app cannot stop the radio admitting a key at its next advert — auto-add is type-
and hop-scoped only (`BaseChatMesh.cpp:249-329`). So the state is enforced twice: the display filter is immediate and
always on, and the contact removal is rate-limited hygiene that stops the contact table filling with keys the user
blocked. "Logged once" means one diagnostic line per key per removal, not one per advert. The trigger already exists in the protocol — the radio pushes `0x8A PUSH_CODE_NEW_ADVERT` with the
full contact record when an unknown key is admitted, and `0x80 PUSH_CODE_ADVERT` with just the 32-byte key when a
known contact advertises (`examples/companion_radio/MyMesh.cpp:957-965`, `:372`, `:382`). The app only has to
compare those keys against the store. Two flash writes per advert is the cost (`MyMesh.cpp:7169`, `:7192-7202`), so the removal is
rate-limited, with the remainder handled by the app-side filter. A block that
writes flash on every advert is a wear bug.

## 7. What the UI says — and what it must not say

Required copy at the moment of blocking:

> **Blocked.** Messages and places from this key are deleted from this app and will not appear again. This cannot
> be undone — unblocking will not bring them back. Your radio still receives and relays its messages, and the
> radio's own buzzer may still sound. Blocking is local to this device and does not tell anyone else.
> [Also remove the contact] [Report]

Forbidden claims, each of which is false somewhere:

- "You will no longer receive messages from this person" — false for channel messages.
- "This person cannot contact you" — false; they can, and the radio will accept the packet.
- "Blocked users cannot see your location" — false; broadcasts are broadcast.
- "No ACK" — true only while the contact stays removed, and only for DMs.
- Presenting blocking as moderation — it is a one-way, per-device filter. Reporting is the moderation path.

**Discarding has to consume the queue.** A frame leaves the radio's offline queue only when the app asks for it with
`CMD_SYNC_NEXT_MESSAGE` (`0x0A`) and accepts the whole frame (`MyMesh.cpp:728-749`). "Discard on sight" therefore
means: sync it, then throw the bytes away — never stop syncing. A client that merely ignored the key would leave the
frame queued and leak a 177-byte slot per message until the queue starved the user's own traffic. The same trap
applies to an OTA session, which drains the queue down to `OTA_RETAINED_OFFLINE_FRAMES` and notifies per consumed
frame (`MyMesh.cpp:607-611`).

**Counts instead of silence.** Hidden nodes are counted, not vanished: "3 hidden" beside the roster and on the map
legend. A map that silently omits nodes lies about mesh size and about coverage. Exclude blocked keys from the
*coverage result* while still counting their replies as evidence that the transmission was heard — two different
questions: "who is here" and "did my packet get out".

## 8. The report action is separate, and needs its own design

Reporting asks someone else to act; blocking acts locally. The same long-press offers both. A report carries: the
message id, the sender key, the channel, the timestamp and the text — nothing else. There is no server in this
product, so "report" means *export a report bundle the user sends to a destination they choose* (support address,
community moderator, or their own archive). Say so in the sheet: "This opens a share sheet with the message
attached. MeshMore does not send it anywhere."

Acceptance: a report bundle can be produced offline, contains no keys the user did not already have, and states
that no network request was made.

## 9. Owner decisions — all four closed 2026-11-04

1. **Hide or quarantine? — DECIDED 2026-11-04: hide and discard.** Messages from a blocked key are not rendered and
   not stored; rows already on the device for that key are deleted when the block is set. Unblocking does not
   restore them, and the copy says so. The radio's own copy is untouched — only the app's store is cleaned.
2. **Do blocked nodes vanish or count? — DECIDED 2026-11-04: count.** "3 hidden" beside the roster and on the map
   legend. Excluded from coverage results; still counted as reception evidence.
3. **Is "Ask me first" the default for strangers' DMs? — DECIDED D8.11: expose it where the fork supports it, consent
   stays the default.** The firmware default is already consent-required (`one_key_dm_enabled = 0`), so the switch
   offers "Allow anyone" as the opt-out. The copy states what a refused stranger sees: a signed marker, not a silent
   drop.
4. **Does a block set on the phone apply on the glasses? — DECIDED D8.12: no.** No radio-side record exists to share,
   so a block is per-device. The spec says so rather than implying sync.

## 10. Tests the spec requires

1. Blocking a key deletes its channel messages from the store, the timeline **and** the unread count.
2. A blocked key's message arriving while the app is closed produces **no** app notification.
3. A blocked key's place does not render, and its telemetry is not requested.
4. A blocked key still appears in the "hidden" count, and its coverage replies still count as reception evidence.
5. A contact-list replay after a reconnect does not resurrect a blocked key's messages.
6. Removing a blocked key's contact, then receiving its advert, does not re-add it more than once per hour and logs
   the refusal.
7. Unblocking restores nothing that was discarded, and the UI said so before the block was set.
8. A block keyed by name only is refused: the store rejects a key that is not 32 bytes.
9. The block sheet's copy passes a review that greps for the five forbidden claims.
10. Blocking does not change the wire: no frame is emitted by blocking a key.

## 11. What this feature does not do

- It does not moderate content. Play's UGC policy asks for reporting and blocking; this is the blocking half, and
  reporting is a separate action (§8).
- It does not notify the blocked person. There is no radio-side marker for "you are blocked" except the keymind
  consent gate's refusal, which is a different event (consent, not block).
- It does not survive a reinstall unless the encrypted store is exported and restored.
- It does not prevent the device's own buzzer. Only `dm.one_key` (fork-only) or the global quiet settings do that.
- It does not delete the radio's copy of anything. The radio's message store and its contact table are the radio's;
  the app deletes only its own rows.
