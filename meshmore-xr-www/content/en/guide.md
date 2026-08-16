---
title: "Using Meshmore XR"
description: "The complete guide: setup, the horizon, gestures, messages, channels, themes, and settings."
url: /guide/
---

Meshmore XR is a spatial client for a [MeshCore](https://meshcore.co.uk) LoRa
mesh. This page is the whole manual. If you are choosing hardware first, see
our [device guide](https://offlinesns.pages.dev/en/tboc/devices/#/) on the
Offline SNS site; if you want the same mesh on a phone, that is
[Meshmore SNS](https://offlinesns.pages.dev/en/tboc/meshmore-sns/#/).

## 1 · What you need

- **Android XR glasses.** Built and tested on the XREAL Aura.
- **A MeshCore companion radio** flashed with the `companion_radio_ble`
  firmware, powered on, within Bluetooth range. Any board from the
  [device guide](https://offlinesns.pages.dev/en/tboc/devices/#/) works.
- Nothing else — no account, no app server, no internet.

## 2 · First launch

1. Grant **Bluetooth** when asked — it is how the app reaches your radio, and
   nothing starts without it.
2. The app scans, prefers a radio it has **bonded** with before (otherwise the
   strongest signal), and walks a four-step ladder it shows and sounds out:
   `LOOKING FOR A RADIO → CONNECTING → HANDSHAKING → READING RADIO`. Where the
   ladder stops is where the problem is.
3. Your radio may show a **pairing PIN** on its screen the first time.
4. The boot scene plays your theme's welcome tune while the contact list
   loads into the vessel under the wordmark. The build version is printed
   right there — if you ever wonder what you're running, look at the splash.

**Region check.** As soon as the app knows both where you are and what your
radio is set to, it compares them. If they disagree — a US preset standing in
Japan — it says so and opens the region list. Pick a preset that is legal
where you are; every node you talk to must share it. *Presets are community
settings, not legal advice; in Japan the hardware itself must carry 技適.*

## 3 · The Horizon

The ring around you is your mesh. Every node your radio can hear stands at
its **true compass bearing**, range mapped logarithmically from arm's length
to the 50 km rim.

- **Shape is type**: a plain mote is a node, concentric rings a repeater, a
  wide coarse ring a **cluster** — a group too dense to draw separately,
  labelled like `+19 NW 12KM`.
- **Brightness is age.** Fresh nodes glow; a node fades over six hours of
  silence. The ring prefers **live** nodes: recently-heard peers outrank
  near-but-silent ones, and your favourites always make the cut.
- **Pinch a cluster** for its menu: MAGNIFY opens a lens over that wedge
  (B backs out one level), BEARING and NEAREST tell you what's inside.
- A **pulse** rippling from a node means a real packet just arrived.

**No nodes visible?** The band will say why: `NO FIX` means there is nothing
to measure bearings from — your radio has no GPS and headset location is off.
One pinch on the HERE control fixes it. Positions never leave the device
unless you separately enable sharing.

## 4 · The dock and gestures

The **dock** is a pad of controls to your lower left — two columns, read
down the near column first: compass and link bands, setup, help, here, wide,
inbox, roster, north, find. Point and pinch; if your hands are busy or
untracked, **look at a control and hold** — gaze-dwell fires it.

Hand signs (shown on the HELP card with drawings):

| Sign | Hand | Does |
|---|---|---|
| **A** | right | compass band on/off |
| **A** | left | link band on/off |
| **B** | either | back out one level — closes the top surface, help card first |
| **H** or **R** | either | move the scene to where you stand; in the tabletop it also re-finds the table |
| palm up | left | raises the message **reel** |
| thumb slide on index | left | scrubs the reel, either direction |

Hold a sign still for half a second, palm away from your face. Every
recognition clicks in the puck; a refusal is a double-click that feels wrong
on purpose.

## 5 · Nodes have verbs

Pinch any node: its **FOCUS card** opens (name, range, compass, hops,
live/stale, telemetry if known) with a four-way menu beside it —

- **FAVOURITE** — star it. Starred nodes float to the front of the ring and
  the top of search, forever.
- **MESSAGE** — opens your conversation. Sending is deliberately locked to
  your **own registered hardware**; other people's nodes answer
  `NOT YOUR NODE — SEND LOCKED`.
- **TELEMETRY** — one polite request for that node's battery/environment
  readings. Manual and single, never automatic: it spends the *other* node's
  battery.
- **CLOSE.**

## 6 · Find anyone

The **FIND** control opens a search panel with the system keyboard already
up. Type any part of a name or key — `NO MATCH IN 350` means it truly is not
there. Chips narrow further: **★ FAVOURITES** and one chip per tag you've
created. Terms combine by narrowing. Each result row carries a star toggle
and **+TAG** — tag the nodes from that trip `hike` and they are one chip away
forever. The query outlives the panel: B puts the keyboard away and keeps the
filter (the FIND control stays lit); CLEAR restores the whole mesh.

## 7 · Messages

- **Inbox** lists conversations, newest activity first; pick one to open its
  thread corridor. `OLDER` pages back.
- The **reel** (palm up, left hand) is triage: scrub the last dozen messages
  on your wrist without opening anything.
- The **crown** around a reel card offers REPLY (three canned phrases),
  SPEAK (dictation — mic listens only while you dictate), READ ALOUD, THREAD,
  and SEND/CANCEL confirmation. Nothing transmits without your confirm.
- Per-channel **read-aloud**: SETUP → CHANNELS, pick a channel — it speaks
  new arrivals. A DM arrives as a thud-beat-thud in the hand; channel traffic
  never buzzes.
- **Suggested replies** (off by default in APP settings) are drafted on
  device from a fixed phrase list — no model, no network.

## 8 · Channels

SETUP → CHANNELS shows your radio's slots (PUBLIC marked — everyone in range
reads it) and any channel heard in traffic.

- **+ NEW CHANNEL** rolls a speakable name like `PINE-FOX-47`. Re-roll free;
  pinch again to write it. Share it by *saying it* — the other person types
  `#pine-fox-47` (exactly as shown, lowercase) into Meshmore SNS and derives
  the same key. *A guessed tag joins: private like an unlisted number, not
  like a safe.* Strong keys stay on the
  [phone app](https://offlinesns.pages.dev/en/tboc/meshmore-sns/#/), which
  has a screen others can scan.
- **+ JOIN PUBLIC** joins the well-known channel, with a warning that it is
  everyone.
- Occupied slots are never overwritten from the glasses.
- **Sending on channels is off** until you enable it in APP settings —
  asked twice, because a channel message goes to strangers.

## 9 · Themes

The palette control opens the picker — nine themes, each with its own
structure, sounds, and (growing) welcome tune. Pick the tile you're in to
close; B reverts a preview. Three postures matter:

- **Field** (most themes): the room-scale ring.
- **Active — HALO**: built for hiking or riding. The scene re-centres as you
  move, the dock rides your **right wrist** (four controls), and the horizon
  keeps up with you. Not while driving.
- **Tabletop — BIOLUME**: the mesh as a half-metre diorama. With scene
  understanding granted it finds a real table, sits on it, and remembers
  that desk. Names live on leader lines beside the map; hover an orb for its
  callsign. If the model is ever somewhere wrong, **H** puts it back in front
  of you and re-finds the table.

## 10 · Settings that matter

SETUP opens the console: DEVICE (radio parameters — staged, and only written
when you COMMIT), APP, PROFILE (themes), CHANNELS, DIAG, ABOUT.

In **APP**: headset location (off by default), **share my location** (off by
default — broadcasts your position unencrypted to the mesh; separate switch
on purpose), suggested replies, reduce motion, channel send, **WHO MAY ASK
ABOUT ME** — three telemetry classes (battery / location / environment), each
DENY, CONTACTS, or ANYONE — and message erase (asked twice, no undo).

The **status band** (left-hand A) reads like an instrument:
`LINK 3.9V 24/350 GPS` — link state, radio battery, drawn/held nodes, and
your position source. After a drop it counts: `LOST 4M` is how old everything
you're looking at is. The app reconnects by itself; walk back into range and
the mesh returns.

## More

- [Devices that run this mesh](https://offlinesns.pages.dev/en/tboc/devices/#/)
- [Meshmore SNS — the phone app](https://offlinesns.pages.dev/en/tboc/meshmore-sns/#/)
- [The Offline SNS project](https://offlinesns.pages.dev/#/)
- [Privacy](/privacy/) · [Support](/support/)
