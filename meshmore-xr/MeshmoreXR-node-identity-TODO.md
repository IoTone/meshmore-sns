# MeshmoreXR — NODE IDENTITY & TELEMETRY PERMISSIONS: two follow-ups

**Status: FLAGGED, NOT BUILT. 10 August 2026.** Both deferred deliberately.
Recorded here rather than remembered, and with what already exists checked
rather than assumed — because in both cases a useful part is already in the
codebase and the gap is smaller and more specific than it sounds.

---

## 1. Telemetry permissions — ours and theirs

### What exists

`spatial/TelemetryPerms.kt` is done and is the hard part. MeshCore packs three
permissions into one byte — bits 0–1 base/battery, 2–3 location, 4–5
environment — each at one of three levels (`DENY`, `ALLOW_FLAGS`, `ALLOW_ALL`).
The packing is pure and unit-tested, which matters because a mis-shifted field
does not fail, it **grants a permission nobody intended to grant**.

`MeshLink.setTelemetryPermissions` / `telemetryPermissions()` read and write it
on the radio. The only way to change it today is the launch flag
`--es telperm "battery,location,environment"`.

### What is missing, precisely

**A control.** The brief's §9.5 lists this as a rack TUMBLER and it was never
built, so a permission that is implemented and honoured cannot be changed by a
wearer. That is the whole of the "ours" side.

**And "theirs", which is not the same axis and is not started at all.** The
byte above governs *who may ask this radio what it knows*. It says nothing
about the reciprocal question — what THIS app may ask of other people's nodes,
and whether it should. Those are separate decisions with separate consequences:

- **Ours** is a privacy decision. `location` is where the operator is standing,
  which is why the file already refuses to collapse the three classes into one
  switch: "the one people would get wrong is the one that matters."
- **Theirs** is a courtesy-and-airtime decision. Querying telemetry costs the
  other node's battery and occupies a shared band, and doing it automatically
  across a 50-peer mesh is the kind of thing that gets an app talked about.

The `elevation` / `fuji` view in SNS is the concrete case: its own header says
most peers plot in the "?" band "until each one's telemetry has been queried".
Making that view useful means querying other people's radios, which is exactly
the decision this flag is about.

### Questions before it can be designed

1. Does a wearer set the three "ours" classes independently in the UI, or is
   the rack TUMBLER's shape (§9.5) already the answer?
2. Is "theirs" a per-node choice, a global one, or a rate? A global "never ask"
   is honest; a global "always ask" is antisocial on a busy mesh.
3. Does the reciprocity matter — should the app decline to *ask* for a class it
   refuses to *answer*? There is a strong argument that it should, and it is
   the kind of rule that is much easier to adopt before there are users.

---

## 2. Favourites, tags, and search

### What exists

**Favourites are already half-built, and from the right source.** MeshCore has a
`FLAG_FAVOURITE` bit per contact; `MeshLink` reads it, `MeshNodes.Peer.favourite`
carries it, and `MeshNodes.rank` already treats it as load-bearing — a
favourite is **never clustered away**, which is the single most valuable thing
the flag can do on a crowded horizon.

So the model, the plumbing and the layout consequence are done. What is missing
is that **the wearer cannot set it.** It is read-only from whatever the phone
app or the radio decided.

### What is missing

- **Marking a favourite from XR.** The obvious home is the CROWN, which is
  already the per-node/per-message action surface, or NODE FOCUS (§S3).
- **Tags.** Nothing exists. Not in MeshCore either — the protocol has a
  favourite bit and a name, and no tag field. **Tags would therefore be local
  to this app**, which is a real design decision and not an implementation
  detail: they will not sync to the phone app, will not survive a reinstall
  unless persisted here, and will not be visible to anybody else on the mesh.
- **Search over name, id and tags.** Also nothing. And search is the item that
  needs the most thought in XR, because a search box is a keyboard, and this
  app has spent its whole life avoiding one.

### The hard part, stated now

**Search in XR is not a text field.** Dictation exists (`Dictation.kt`) and is
the obvious input, but it is built for composing a message and is gated behind
a deliberate mic prompt. The alternatives worth weighing before anyone builds
a search box in the air:

- **Filter, not search.** Tags are a closed set the wearer created, so picking
  from them is a Stack of six rows, which is a solved surface. That covers
  "show me my repeaters" without any text entry at all.
- **Speak a name.** Good for "where is astor", which is the other real query.
- **The horizon already IS the answer to most spatial questions.** "Which nodes
  are near me" is not a search, it is a glance. Be careful not to port a
  phone's search box to solve a problem the room already solves.

A reasonable first cut is therefore: favourite from the crown, tags as a small
closed set, filter the horizon by tag from a Stack, and NO free-text search
until something demands it.

### Questions before it can be designed

1. Are tags per-node only, or do channels and threads get them too?
2. What happens to a tag when a node is renamed or its key rotates? Tags keyed
   by name detach silently; keyed by key they survive but stop matching what
   the wearer sees. (`VoicePrefs` already met this and chose the key —
   worth reusing that reasoning.)
3. Does a tag change what the HORIZON draws, or only what a list shows? If it
   changes the horizon it is a filter with real consequences for §4 symbology
   and the clustering budget, and that is a bigger piece of work.
