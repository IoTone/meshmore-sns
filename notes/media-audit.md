# Media audit — photo and voice, both directions

Scope read: `lib/media/**` (16 files, 3 400 lines), `lib/voice/**` (11 files, 2 500 lines),
the media paths in `lib/screens/chat_screen.dart`, `lib/screens/dm_screen.dart`, and
`lib/places/place_photo.dart`.

Verdict: **the send path is careful and honest; the receive path for photos did not exist.**
A picture sent on a channel was reassembled by the app's `MediaInbox` and then dropped on
the floor — no row, no error, no trace. Voice had a home (`VoiceInbox`); photos had none.
That is fixed here. Two further gaps are documented and not fixed, because they need files
outside this task's scope.

---

## 1. Photo send — PROVEN working

| Step | Where | Evidence |
| --- | --- | --- |
| Channel gate before any encode | `media_transfer.dart:prepare` | `MediaSendPolicy.channelRefusalFor` runs first, so a Public channel answers instantly instead of after a native encode |
| Public is identified by the **secret**, not the name | `media_send_policy.dart:isPublicChannel` | compares the 16 bytes against `kPublicChannelPsk` |
| Size ceiling before the radio is asked | `media_transfer.dart:_planFor` | empty payload → `payloadUnusable`; `chunkCount > MediaReassembler.maxChunks` → `payloadUnusable` |
| Three sizes, each with a byte budget and a pixel floor | `media_transfer.dart:MediaSendSize` | preview 600 B/160×120, standard 1600 B/256×192, full 4096 B/320×240 |
| Cost stated before sending | `media_composer.dart:_planBlock` | chunk count and projected airtime, plus `mediaOverBudget` when the encoder could not reach the budget |
| Pacing, salting, capacity handling | `media_sender.dart` | 350 ms pacing, `TABLE_FULL` requeues without spending an attempt, every resend rewrites the attempt nibble so the radio's seen-table does not drop it |
| Honest receipt | `media_composer.dart:_receiptBlock` | "accepted, not delivered" — there is no ACK for group data |
| Stalled vs failed are different sentences | `media_composer.dart` | `MediaUploadStalled` names airtime or table-full; `MediaUploadFailed` names lost chunks |
| Closing the sheet stops the transfer | `media_composer.dart:dispose` | `_upload?.cancel()` |

## 2. Photo receive — WAS BROKEN, now fixed

**The defect.** `MediaInbox` reassembles a payload and hands it to whoever claimed it
(`media_inbox.dart:_handOff`). In `main.dart:178` the inbox is built with **no
`onCompleted`**, and the only subscriber to `completed` was `VoiceInbox`, which returns
early for anything that is not `MediaKind.voice` (`voice_inbox.dart:_onPayload`). So an
image payload completed, was handed to nobody, and `download.forget()` dropped the bytes.
The sender's receipt said "accepted"; the receiver saw nothing at all.

**The fix.** `lib/media/photo_inbox.dart` — `PhotoInbox`, the same shape as `VoiceInbox`
and for the same reason: a bounded list of the newest 8 pictures per channel, kept for the
life of the process, decoded only when shown. `lib/media/received_photos_sheet.dart` shows
them, decoding each with the app's codec and giving a payload this build cannot read its
own row rather than taking the sheet down. `chat_screen.dart` owns one `PhotoInbox` built
from the app-scoped `MediaInbox`, and shows a counted control beside the mic and the attach
button **only when this channel has a picture** — a fourth icon on every channel would be a
promise that something is there.

Proven by `test/media/photo_inbox_test.dart` (9 cases): newest first, voice ignored,
per-channel counts, bounded at capacity, a replayed payload not filed twice, empty payload
ignored, `clear`, a listener notified, and a payload arriving after dispose not filed.

**Still missing (NEEDS WORK, below):** a picture that loses a chunk is invisible. The
reassembler knows what is missing and can build a request datagram
(`media_transfer.dart:requestBytesFor`), but no surface for a channel photo shows progress
or offers the ask. Only the place-photo path has that, and that path is unreachable.

## 3. Voice — PROVEN working, both directions

- Ceiling: `kVoiceMaxDuration` 20 s, enforced by a timer started at capture
  (`voice_capture.dart:185`), and `stoppedAtCeiling` tells the surface the microphone
  stopped rather than the user.
- Send: `prepareVoice` runs the channel rules before packing, and an empty take becomes
  `payloadUnusable` rather than a codec exception reaching a surface
  (`media_transfer.dart:prepareVoice`).
- Receive: `VoiceInbox` keeps the newest 12 notes per channel, refuses a payload whose
  header it cannot read at arrival (so no row fails when pressed), and the sheet decodes
  from the bytes that arrived (`voice_notes_sheet.dart:_toggle`).
- Playback of a note that arrived in several chunks: the payload is reassembled before it
  is handed on, so the sheet always decodes a whole note. PROVEN by construction; the
  chunk-level reassembly is covered by `test/media/` and `test/voice/`.

## 4. Channel vs DM — the rule holds on channels, and DMs cannot send media at all

- Public refusal is enforced twice: the buttons are hidden (`chat_screen.dart:_mediaAllowed`,
  which also requires a ready radio) and the send path refuses independently
  (`MediaSendPolicy`), so a future surface cannot bypass it by forgetting a checkbox.
- The refusal is explained: `chatMediaPrivateOnly` is shown above the composer on a channel
  where media is not offered (`chat_screen.dart:1078`).
- **NEEDS WORK:** `lib/screens/dm_screen.dart` has no media composer at all — no photo, no
  voice (grep for `MediaComposer|VoiceComposer|attach|mic` returns nothing). The policy says
  media belongs on DMs and private channels; only channels can send it. The DM screen is
  being edited by another task, so this is documented rather than changed.

## 5. "Says sent but nothing was sent" — none found on the send path

Every path that could drop a chunk is named and surfaced: `refused` spends an attempt and
eventually reports lost chunks; `tableFull` and `budgetRefused` requeue without spending
one and stop after six consecutive answers with a sentence naming which capacity refused
it; a thrown radio call requeues and rethrows after three in a row. The receipt never claims
delivery.

The one place the app *did* say nothing was the receive side, which is §2.

---

## NEEDS WORK

| # | What | Evidence | Size | Kind |
| --- | --- | --- | --- | --- |
| M1 | A channel photo that loses a chunk is invisible: no progress row, no "ask for the missing packets" control. The machinery exists (`MediaDownload.requestBytesFor`, `MediaReceiveView`) but nothing mounts it for a channel payload. | `media_transfer.dart:474`, `media_receive_view.dart` (used only by `place_detail_sheet.dart:451`) | M | UNFINISHED |
| M2 | DMs cannot send or receive media. The composer is only in the chat tab. | `dm_screen.dart` has no `MediaComposer`/`VoiceComposer` | M | UNFINISHED |
| M3 | The place-photo fetch is dead code: `placePhotoFetchFrom` has no callers and `onFetchPhoto` is never passed, so the "fetch this place's photo" section renders a promise with no button. | `place_photo.dart:113` (no callers), `place_detail_sheet.dart:39,145` | S | BUG |
| M4 | An inbound transfer has no age limit. It is dropped only when a seventeenth transfer evicts it, so a payload that will never complete holds its chunks until then. | `media_reassembly.dart:98,166` (eviction by last activity, no `firstSeenAt` expiry) | S | UNFINISHED |
| M5 | Received photos are not persisted. A picture is as durable as the process, which the sheet says; the alternative is an image per message in the sealed store. | `photo_inbox.dart` (by design), `received_photos_sheet.dart:mediaReceivedKept` | — | BY DESIGN |
| M6 | `VoiceInbox.dispose` is not idempotent, so a second dispose asserts in debug. `PhotoInbox` guards it; the voice one does not. | `voice_inbox.dart:155` | S | BUG |

## Known good, with the test that proves it

- Photo send pacing, salting and capacity handling — `test/media/media_sender_test.dart`.
- Chunk encode/parse and refusals — `test/media/media_chunk_test.dart`.
- Reassembly, duplicates, eviction — `test/media/media_reassembly_test.dart`.
- Public-channel refusal — `test/media/media_send_policy_test.dart`.
- Voice payload round trip and refusals — `test/voice/voice_payload_test.dart`.
- Photo receive (new) — `test/media/photo_inbox_test.dart`.
