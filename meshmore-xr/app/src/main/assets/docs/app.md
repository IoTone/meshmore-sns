# MeshmoreXR

An **offline-first companion** for MeshCore LoRa mesh radios, worn on
optical see-through glasses and paired over Bluetooth Low Energy. No
accounts, no servers, no internet dependency — everything you see is read
straight off the mesh through your connected radio.

> This page ships inside the app. The **Protocol** and **Firmware** docs
> beside it are snapshots of the upstream MeshCore documentation, bundled
> for offline reading.

## The paradigm: the room is the UI

There is no home screen. The mesh stands around you at its true bearing
and range — nearer nodes nearer, further nodes further, out to the
horizon ring. You turn your head to look at your network rather than
scrolling a list of it.

Everything else is **summoned**: a short row of pips low and to your
left, each opening one surface. Exactly one is open at a time.

## Getting started

1. **First light.** One glowing mote appears at arm's length with the
   word TOUCH THIS, and a trail of beads runs to it from your left hand.
   Reach out and touch it. That is the whole tutorial — it teaches that
   things in the air answer your hands, and it proves hand tracking works
   before anything else is on screen.
   *If your hands are not tracked, wait a moment: the mote will offer
   "or look at it and hold" and you can select by gaze instead.*
2. **Link a radio.** The LINK pip pairs a MeshCore companion radio over
   BLE. Your radio's PIN is random on every boot if it has a display.
3. **Look around.** Nodes appear as motes as their adverts arrive.

## The surfaces

- **HORIZON** — the mesh itself, always on. Range rings, callsigns, and
  a heading band. This is home; it is not a screen.
- **NODE FOCUS** — pinch a mote for one peer: distance, hops, signal,
  and a menu (favourite, message, telemetry, forget, claim).
- **SPEAK** — the crown. Dictate a message, watch the draft fill word by
  word, and send. Every direct message carries a real delivery state:
  SENDING, then delivered when the acknowledgement lands, or NO ANSWER.
- **CHANNELS** — bands rather than tabs. Type a `#tag` to join; the key
  is SHA-256 over the exact bytes, so one wrong character is a different
  channel with nobody in it.
- **MAP** — what the mesh knows about where it is. Mesh weather and
  Meshbook live here.
- **INBOX** and **LIST** — threads, and every node you have heard, with
  search, tags and favourites.
- **SETUP** — the console: radio configuration, permissions, language,
  diagnostics, theme.

## Mesh weather

Most radios ship with every telemetry class set to DENY, so asking the
mesh for sensor readings usually returns nothing. So the app reads the
weather people **say** on the public channel — rain, fog, storm, a 🌧
emoji — and groups it by where the sender's radio is, with how long ago
it was said. It costs no airtime and works with the radio off.

Terms are matched on word boundaries so "sun" does not fire on "Sunday",
negation is honoured ("no rain today" is not rain), and a qualitative
word like "hot" needs a second radio in the same area to agree before it
is reported.

## Meshbook

What kind of day this mesh had, computed from messages already on the
device: how busy, who carried it, what it was about, when the band is
awake, and how many of your own messages were delivered and answered.
No query, no airtime, no permission.

## What the app transmits, and when

Two different rules, on purpose:

- **You may message anyone.** Choosing a node and typing a message is
  the authorisation.
- **The app only transmits unattended to radios you have claimed.** A
  soak test or a path probe sends packets nobody asked for one at a
  time, so it only ever aims at hardware you have marked as yours with
  the MINE action on a node. Claiming needs the node's full key.

Position is **never** broadcast unless you turn sharing on. Using a
location fix to compute bearings is local and private; putting it in an
advert broadcasts it unencrypted to anyone in range. Those are separate
switches and one does not imply the other.

## Gestures

- **Pinch** — select what the pointer or your gaze is on.
- **B (flat hand)** — back, one level at a time. It closes what you most
  recently opened, and inside the settings tree it walks up one step
  rather than throwing you out.
- **R** — reset the floor height if the world has drifted.

Every gesture has a gaze-and-dwell equivalent, so nothing in the app
requires working hand tracking.

## Safety

Do not use while driving or operating machinery. The horizon is drawn
over the real world and can cover things you need to see. Range and
bearing are computed from adverts other radios chose to send and can be
wrong, absent, or stale — do not navigate by them.
