# AUTOPEN — a suggested reply, before launch

**Status: BUILT 2026-08-08**, as `meshmore-xr/app/src/main/java/com/iotj/meshmore/xr/Autopen.kt`.
Requested 2026-08-04.

> **What shipped is not a model.** It is intent recognition plus a table of
> drafts — see the file's own header, which says so first. Every constraint
> below is honoured, and the "Definition of done" at the foot is complete except
> for the settings toggle. The seam is `suggest(String): String?`, so a real
> model can replace it without any caller changing.
>
> The reason it is not a model is in the file too, and it is not only schedule:
> what a model would buy is the CONTENT of the answer — "20 minutes" rather than
> "on my way" — which requires knowing where the wearer is going and when they
> will arrive. The app does not know that. So this drafts the FORM and leaves
> the wearer the fact.

## What it is

A small on-device model reads the message you are looking at, and the CROWN
offers a fourth reply next to `ROGER` / `ON MY WAY` / `STAND BY` — one written
for *this* message rather than for messages in general.

The three canned replies cover most mesh traffic precisely because most mesh
traffic is acknowledgement. What they cannot do is answer a question. "What's
your ETA?" gets `STAND BY`, which is not an answer, and the wearer either
dictates or lets it go. Autopen is for that gap.

## Where it plugs in

The path is already built and this is the reason to write the note now rather
than the design later:

- `Crown.Level.COMPOSE` already holds a variable list of proposals. A fourth
  entry is a list entry.
- `Crown.propose(text)` already routes any string to the confirm level.
- `MeshLink.replyTo` is already the single gated exit.

So autopen produces a **string** and hands it to `propose()`. It touches
nothing else. Anything that needs to change the sending path is out of scope
and probably wrong.

## The constraints that are not negotiable

**IT PROPOSES, IT NEVER SENDS.** The confirm level exists because speech
recognition mishears; a generated reply is the same risk with better grammar.
A model that can transmit is a model that can transmit something you would not
have said, to a stranger, over a shared band, with your callsign on it. The
generated text must arrive at `CONFIRM` like every other draft, and the wearer
must read it before it leaves.

**IT MUST BE MARKED AS GENERATED, in the draft and not only in the menu.** By
the time the words are on the confirm screen they look exactly like words the
wearer chose. That is the moment the label matters.

**ON DEVICE, OR NOT AT ALL.** A mesh radio is for where there is no other
network — that is the entire proposition — so a reply generator that needs a
server is one that fails in the only conditions the product exists for. It also
means every message would be shipped to a third party, which is not a thing to
do quietly with other people's conversations.

**THE WORD CEILING STILL APPLIES.** `Dictation.MAX_WORDS` (20) is derived from
the MeshCore frame size, not from taste. Generated text is subject to the same
arithmetic and should be clipped by the same rule.

**SENTIMENT IS THE INPUT, NOT THE OUTPUT.** The request was a reply based on
the sentiment of the incoming message. Worth being careful here: a cheerful
reply to a message the model *scored* as cheerful is a machine agreeing with
its own guess. The useful version reads intent — is this a question, a summons,
a status report, an emergency — and drafts accordingly. An emergency wrongly
answered with a breezy acknowledgement is the failure case that matters, and it
is the one a pure-sentiment model is most likely to produce.

## Sizing

Whatever ships has to fit in an APK next to a renderer and run on the glasses'
compute without touching frame time. A generation that hitches the scene is
worse than no generation: the reel is hand-anchored, and §5 is explicit that
flicker on a hand-anchored element is the most nauseating failure available
here. Generate off the render thread, show a placeholder in the slot while it
works, and let it fail silently into "no suggestion" rather than blocking the
crown.

## Definition of done

- [x] A fourth COMPOSE slot, present only when a suggestion exists
- [x] Visibly marked as generated, at COMPOSE **and** at CONFIRM
- [x] Never reaches `replyTo` without a wearer confirming
- [x] Clipped to `Dictation.MAX_WORDS`
- [x] Failure degrades to absence. *Not* off the render thread — it is a
      lowercase, a split and a few set lookups on at most 150 bytes, so moving
      it off-thread would cost more than it saves. That line is where a model
      would be called FROM, and a model would need the thread.
- [x] A setting to turn it off entirely — APP bay, `SUGGEST A REPLY`. Opt-OUT.

## What testing changed, which is worth keeping

Four false positives, none of them found by thinking about it:

- "all good **here**" read as a summons — `here` and `over` are ordinary words.
- "…**when** you get a chance tomorrow" read as a question about time.
- "**come** to the gate **when** you can" answered with an ETA, because the time
  words were tested before the summons.
- "you **need** to start with the protocol" answered with ON MY WAY — found only
  by replaying a captured evening of real Portland-mesh traffic, which is now a
  verbatim test case. `need` carries advice as often as it carries a summons.

A mesh channel is mostly chatter between strangers, so the default has to be
SILENCE. The real-traffic test asserts that a whole evening of it produces no
suggestions at all.
