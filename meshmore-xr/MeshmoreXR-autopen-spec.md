# AUTOPEN — a suggested reply, before launch

**Status: NOT BUILT. Owed before launch.** Requested 2026-08-04.

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

- [ ] A fourth COMPOSE slot, present only when a suggestion exists
- [ ] Visibly marked as generated, at COMPOSE **and** at CONFIRM
- [ ] Never reaches `replyTo` without a wearer confirming
- [ ] Clipped to `Dictation.MAX_WORDS`
- [ ] Off the render thread; failure degrades to absence
- [ ] A setting to turn it off entirely
