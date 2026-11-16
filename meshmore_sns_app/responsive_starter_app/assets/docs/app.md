# Meshmore SNS

An **offline-first companion app** for MeshCore LoRa mesh radios, paired
over Bluetooth Low Energy. No accounts, no servers, nothing collected.
Everything you see is read off the mesh through the radio in your pocket.

> This page ships inside the app. The **Protocol** and **Firmware** docs
> next to it are snapshots of the upstream MeshCore documentation, cached
> for offline reading and refreshed from GitHub when you are online.

This page is the app's own reference. Each section says what a feature is
for, what it does, and what it cannot do.

## Contents

- Finding and pairing a radio
- The six views, and moving between them
- Channels
- Direct messages, reactions, pictures, voice notes
- Nodes, the tree and routes
- The map
- Places
- Geofences
- The hyperlocal grid
- Tools
- Safety: check-in and the alarm
- Notifications and the background link
- Sound, haptics and speech
- Themes, type and reading comfort
- Settings, storage and what is kept where
- What this app cannot do, and why

## Finding and pairing a radio

The app talks to a **MeshCore companion radio**. The radio is the one with
the antenna and the licence-free band. The phone has no radio of its own,
so with no paired radio the app can show only what it already stored.

- **Pair** scans for MeshCore radios over Bluetooth, lists them, and
  connects to the one you pick. Pairing is remembered, so a radio you have
  used comes back on its own.
- **Reconnect** happens automatically after a drop, with a growing wait
  between attempts and a visible count. The retry action appears while the
  app is retrying, not only after it has given up, so a link that is
  taking a while always has something to press.
- **A lost notification during the handshake** does not cost the link: the
  app asks again once before it treats the handshake as failed.
- **More than one paired radio** is a list, not a hidden last-used. The
  connect screen lists every radio this phone has paired and switches to the
  one you pick. A switch is refused while a message is still waiting for an
  answer, because that answer belongs to the radio it was sent on, and the
  app says so rather than losing the reply.
- **The radio's own limits** are read from it rather than assumed. How many
  contacts it can hold, how many channel slots it has, which bands it will
  repeat on, its firmware version and build date, its battery, and whether
  it is the radio from before or a replacement are all readout lines on
  Device configuration.
- **A radio can be restarted from Diagnostics.** It asks first and says
  what the restart costs: the link drops for a few seconds and anything
  queued on the radio is lost.

The app refuses a Bluetooth link whose negotiated packet size is below what
the protocol needs, and says the number. The same radio negotiates the same
value every time, so that refusal is not retried.

## The six views, and moving between them

**Dashboard, Chat, Nodes, Hyperlocal grid, Map, Settings.** Two ways across:
swipe the body sideways, or tap the strip under the app bar. The strip is
labelled, 48 dp per cell, and always one tap away for anyone who cannot
swipe. A surface that needs the sideways drag takes it while you are using
it, so the strip is how you leave the map.

The app bar carries one title, and it names what is on screen.

Every view is portrait. A tablet or a landscape mount shows the same single
column, by decision, because every layout is drawn for a handset at arm's
length.

**The dashboard** shows nodes heard, the radio and location readouts, the
radio's own battery estimate, and recent activity. The radio's name is a
readout: tapping it opens Device configuration. The dashboard has one
layout per theme, and several state plainly when the link is down.

## Channels

A channel is a name and a key. Everyone holding the key reads the channel,
and the radio repeats what it hears without knowing who is speaking.

- **The Public slot** is the one every radio hears. The app never uses it
  for anything that has to be addressed to somebody.
- **A hashtag channel** derives its key from the name, so two people who
  type the same tag land on the same key without exchanging anything. The
  key is therefore public by construction, and the app says so.
- **A named channel** takes a key you supply, or one generated for you, and
  can be shared as a QR code.
- **Slot count follows the radio.** A radio with forty slots shows forty.
  A slot the radio has already named is never hidden by a smaller count.
- **Channel names stop at 32 bytes**, because the radio's own name field
  truncates there. While the key is derived from the name, a longer name
  would give two people identical-looking channels with different keys.
- **Per-channel notification bundle**: sound, vibration, notification and
  speech, each on its own switch, plus a mentions-only mode and an optional
  match on the last characters of your key. The public slot gets one master
  switch in App settings, and an alarm is never silenced by it.

A channel message carries your display name as text and no key. Any holder
of the channel key can type any name, and the app is honest about that
wherever attribution matters, in places and in alarms.

## Direct messages, reactions, pictures, voice notes

A direct message is addressed to one key, so it is authenticated by that
key in a way a channel line can never be.

- **Delivery state** is per message and it is one of five: sending, sent,
  delivered, unknown, failed. `unknown` is a real answer, not a failure: the
  radio accepted the text and the app heard no confirmation, which happens
  when the firmware is configured to send none, and when a message was in
  flight while the process died. Unknown rows can be retried.
- **One unsettled message per contact.** The firmware keeps eight pending
  acknowledgements in a circular table, so a ninth in flight evicts the
  oldest and that message can no longer be matched to its answer. The
  composer refuses a second send to the same contact while one is open and
  says why.
- **Reactions** are written in the format the other MeshCore clients
  already understand, and both formats found in the wild are read. A reader
  whose client does not understand reactions sees a short line with an
  emoji and a code, which is what a stock client shows anyway.
- **Pictures** are sent as chunks on a channel, reassembled by everyone
  listening, and shown in the thread as a row that opens at full size. The
  picture is kept as the received bytes rather than as pixels. A picture
  carries no acknowledgement, so the app calls the send accepted, not
  delivered, and says so before you send it.
- **Voice notes** record up to 20 seconds, are paced out like a picture,
  and state their cost in datagrams and seconds before they go. A note that
  the receiver's build cannot decode is refused with a named reason rather
  than played as noise.
- **Drafts** are kept per conversation and per radio, survive a failed
  send, and are never carried to a different radio.
- **Search** covers stored history only, ranks a whole word above a word
  found inside another, counts blocked hits instead of showing them, and
  says how far back the store reaches.
- **Forwarding** puts the text in another conversation's draft rather than
  sending it, because a forward that sends itself cannot be recalled on a
  shared mesh.
- **Blocking a key** stops this device showing, searching, announcing or
  speaking that key's messages, and it stops this device sending to that key:
  the composer refuses and names the block, and a retry of a message addressed
  to a key blocked since is refused too. An alarm is never refused. It does not
  stop the radio receiving or relaying the packet, and it does not remove the
  contact. A channel line carries a name and no key, so a channel sender is
  filtered only when the name is unique in your contact list.

## Nodes, the tree and routes

**Nodes** lists every contact the radio's own table holds, with message
counts, tags and favourites.

The node sheet carries identity, signal, the route to that node, and its
telemetry. A route is direct, N hops through named repeaters, flooded, or
not known yet, and the app never guesses which. Two actions ask the mesh
rather than waiting for an advert:

- **Find the route** floods one request and shows both directions, because
  an asymmetric link is the interesting answer.
- **Share this contact** copies the radio's own advert packet as a link
  that any MeshCore client can import.

A repeater or room node also offers a **session**: the password is sent once
and never stored, the permission the radio grants is reported rather than
interpreted, and signing out says so.

**The mesh tree** draws who is reachable through whom. Depth comes from the
route the radio advertises, so a peer whose route the radio never learned
is drawn on its own ring rather than at an invented depth.

## The map

The map is one themed vector basemap plus whatever you turn on.

- **The camera** follows one order: the phone's own position, then the
  radio's reported position, then the view you last left, then the whole
  world. A downloaded region is deliberately not part of that order: a region
  says which map this device holds, not where you are.
- **Position arriving late does not move the map** under your finger. The
  locate control re-centres and, when there is no position at all, asks for
  one.
- **With no position** the map still draws, and one row says which
  situation it is, with the action that helps: not allowed, blocked, off on
  the phone, or none yet.
- **Layers** are one sheet: map tiles or the bundled basemap, places,
  fences, the movement trail, the coverage quilt, and any imported GeoJSON
  event layers. The map's display choices survive a restart.
- **Offline packs** are pre-cut region archives. A download is resumable,
  verified by size and checksum, refused before it starts when the phone
  cannot hold it, and held back on a metered link unless you turn that rule
  off. The app installs prepared archives and never cuts one itself.
- **OpenStreetMap's own servers do not allow bulk downloads.** If you point
  the app at OSM, you are caching what you look at, one square at a time.
- **Every source is named on the map.** Nothing is drawn from a source the
  attribution line does not carry.

## Places

A place is a coordinate, a type, a label and a time to live, sent as a
short line of text on a channel so that any MeshCore client can read it
with no app at all.

- **Report a place** from the map: long-press, or the labelled control on
  the map's bottom chrome. Nine types, a label, and a lifetime chosen from
  the ten stops the format allows.
- **A report has a destination.** The create sheet names the channel the
  report will go to, defaulting to the one you last chose and then to the
  channel you are reading, and the place's own sheet says which channel it
  went to. A report never goes silently to whatever happens to be active.
- **Import a shared place.** A place shared out of the app is a link and a
  line of text. Pasting either into Import reads it back, checks the
  coordinate range and the id, and opens the create sheet prefilled. Text it
  cannot read is refused with the reason rather than imported as nonsense.
- **Six reports an hour**, shared with confirmations, so a place report is
  not a way to flood a channel.
- **Confirm and refute.** A reply on the channel is recorded as *claimed*,
  because a channel line carries a name. A key-addressed reply is recorded
  as *key-bound*. The app offers the key-bound pair only when the place
  arrived with a key.
- **Expiry is final.** A place's lifetime stops counting when its time to
  live runs out, and time is the only thing that ends it. A photo attached
  to a place never extends it.
- **A block** drops that reporter's stored places as well as hiding them.
- **The ledger** exports one row per place with its final state,
  confirmations, refutations and whether it was hidden.

## Geofences

A fence is a circle or a polygon you draw. The app compares your own
position against it and tells you when you cross.

- **Sampling is one second**, not per frame. A fence is crossed by walking,
  and a sample per inbound packet would re-run a distance calculation for
  every message on a busy channel.
- **Hysteresis** keeps a position sitting on the boundary from flapping
  inside and outside. A crossing counts once per stay.
- **Enter and leave sound different**, in every theme, so the pair is
  learned once. A crossing vibrates, and it never sounds like the alarm.
- **A drawn fence can be reshaped.** Edit a polygon and choose Reshape on the
  map: its corners load into the same drawing flow you drew them with, and
  saving replaces the shape while keeping the fence's name and its crossing
  log. A circle is resized from its own sheet.
- **A crossing is a notification as well as a cue**, on its own OS channel, so
  fences can be silenced without silencing messages. It names the fence and
  says which direction you crossed. It is posted when a position fix arrives,
  which is the only moment a crossing can be noticed.
- **The inside state is remembered**, so launching the app already inside a
  fence does not announce an entry that did not happen.
- **A fence needs a position to fire.** Positions arrive when the radio
  reports one or the phone provides one. A fence is not a tracker, and it
  cannot cross itself while nothing is moving.

## The hyperlocal grid

Five views of the mesh from where you stand, chosen from one list.

- **Radar**: nodes by distance and bearing, with range rings. Auto range
  frames the group rather than the outlier. A node with no reported
  position is drawn hollow, and the legend says its angle is not a
  direction.
- **Weather**: readings your own radio and other contacts report, plus a
  microclimate rollup mined from what people type on the selected channel.
  Environment readings appear only if the radio's firmware build puts a
  sensor in its telemetry path. Many stock builds report battery and
  position and nothing else, and the view says so rather than showing a
  zero.
- **Mesh tree**: who is reachable through whom, by the routes the radio
  advertises.
- **Message heat**: how traffic is distributed over the mesh, one flat
  colour per occupied cell.
- **Altitude**: an exploratory profile that places peers by reported
  altitude against a set of real-world reference heights. It is meant to be
  interesting, not authoritative, and it says so.

The grid's own preferences, including the chosen view and range, survive a
restart.

## Tools

One tool runs at a time, because each of them needs the radio to itself.
Every tool states what it is about to do before it does it, and every
failure is a sentence rather than the word "failed".

- **Radio stats**: noise floor, airtime, and the radio's own counters.
- **Ping**: asks one node for its readings. A node that does not share
  telemetry answers nothing, and that is a permission, not a range problem.
- **Trace**: per-hop round trip through the repeaters a route names.
- **Discover**: finds nearby repeaters and what they answer.
- **Soak**: sends a run of messages and measures duplicates, reordering and
  loss off the frames rather than off the history.
- **Range test**: walks a link to its limit, in both directions if you want
  them.

The tools that send text refuse the Public slot structurally, because a
tool's traffic is not for everyone on the mesh.

**Every finished run is kept.** Tools → History lists the runs newest first,
each with a one-line summary and the table it produced, which can be copied
out. The history holds the newest 40 runs and at most 96 KB of tables, and it
says so on screen. A run whose table was dropped to stay inside that budget
keeps its summary and says the table went. A run that never started leaves no
row, and clearing the history deletes the runs and nothing else.

## Safety: check-in and the alarm

**Check-in** sends one short message that says you are fine, to the channel
you choose. It is a row under Safety in Settings, not a button in the app
bar, because it is an action rather than a view.

**The alarm** repeats until it is cancelled, with the interval and the
message the schedule states. It picks the radio's `#emergency` channel as
its destination when that channel exists, and the active channel
otherwise, and it never creates a channel silently. The channel's key is
derivable from its name and therefore public, which the app states.

Acknowledgements are kept apart by the path they arrived on: a channel
acknowledgement is a name in decrypted text, a direct-message
acknowledgement is authenticated by the sender's key, and the screen shows
which is which. The alarm keeps running with the screen off, because the
background link keeps the process alive.

## Notifications and the background link

Each class of notification is its own OS channel, so a message and an alarm
can be silenced separately:

- **Channel message**
- **Direct message**
- **Emergency alert**
- **Fence crossings**

A notification is posted once per message, names the channel or the peer,
and never carries the text of an alarm, because a lock screen is not where
a position should be published. Tapping one opens the thread it came from,
including after a cold start. A thread you are already reading is not
announced.

**The background link** is a foreground service that keeps the process
alive so the app keeps draining the radio. App settings states which of the
three states it is in: off, failed, or running.

**Battery optimisation** is the other half of that, and the app can now see
it. When Android is still allowed to optimise this app, App settings says so
and offers the one-tap request to exempt it. A phone that stops a background
app after a while is the commonest reason messages stop arriving with the
screen off, and this row is how you tell that apart from a link that failed.

## Sound, haptics and speech

Every one of the eleven themes ships its own synthesised pack, one cue per
event: message arrival, direct message, link up, link down, alert, scan
start, task done, task failed, and the fence pair. Nothing is borrowed
between themes.

- **Alerts are audible by default** and there is one master switch.
- **The cue volume slider names the stream it uses**, because a phone's
  media volume and its notification volume are separate and only one of
  them is the one you hear.
- **Reduced motion** stops the app's own animation without removing
  information.
- **Speech** reads inbound messages aloud, with its own per-channel mute
  and voice. It is off by default.

## Themes, type and reading comfort

Eleven presets, each a complete look: ground, ink, accent, a mono face, a
corner rule and its own audio pack. Every preset is held to the same
measured floors, so no preset is the pretty one that is hard to read.

- **Text and body copy clear 4.5:1** on every ground they are drawn on, and
  disabled controls stay above 3:1.
- **Every route survives 320 dp width at 200 percent text.** That is a
  test, not an intention.
- **Units, clock and temperature** follow your choice rather than the
  phone's locale.
- **The first run** asks for the permissions the app needs and for the
  three choices that change every screen after it: units, a 24-hour clock,
  and whether pictures are drawn in colour. It can be replayed from About
  without losing those choices.

## Settings, storage and what is kept where

Settings is a hub of rows grouped by what they configure: Safety, the
radio, location, the app, the link, and the build.

**What is stored, and where:**

- Message history keeps 250 rows per conversation and says how many it
  dropped.
- Places keep 500 rows and evict the expired ones first.
- The movement trail keeps 2000 points or seven days, whichever binds
  first.
- Pictures and voice notes are held as unfinished and finished transfers,
  bounded, and cleared by the storage delete.
- Fences, drafts, the block list and places are sealed with a key the
  phone's keystore holds and does not export.
- Coverage cells are kept so the quilt survives a restart.
- The radio's own contact table, channels and settings are read from the
  radio, so they are not this app's to lose.

**Storage** shows each of those with the number it can prove, and hides a
store it cannot measure rather than showing a zero that would read as
"empty". **One action deletes everything**, lists exactly what goes and
what survives, and requires the word DELETE to be typed.

**Export** writes a passphrase-protected file, and **restore** reads one
back. A file opened into the app from another app is staged and restored
the same way.

**Nothing is uploaded.** The app has no backend and no account. Two
requests do leave the phone and neither carries your identity: a map tile
request, which tells that server roughly where you are looking, and a
refresh of these documentation snapshots. Both are off until you use them.

## What this app cannot do, and why

- **It cannot hear the mesh without the radio.** The phone has no LoRa
  radio, and the app does not pretend the last known state is live.
- **It cannot make a channel private.** A channel key is held by everyone
  on the channel, and a channel message carries a name rather than a key.
- **It cannot stop a blocked peer reaching the radio.** A block is this
  device's filter.
- **It cannot recover what the radio discarded.** An offline queue, an
  over-the-air update, or a table overflow drops frames the app never saw.
- **It cannot show environment readings a firmware does not send.**
- **It cannot deliver a picture or a voice note with an acknowledgement,**
  because the transport has none for a chunked payload.
- **It cannot promise a notification after a reboot on its own.** Starting
  the background link at boot is a decision with a platform risk attached,
  and the app does not take it for you.

---

_Meshmore SNS, IoTone, Inc. Licensed MIT. Built with Flutter._
