# MeshmoreXR — THE LATTICE

**The mesh's topology as a spatial force-directed graph. Spec only; nothing built.**
Written 2026-08-03. Mirrors Meshmore SNS's `MeshTreeView` (R50). Extends
`MeshmoreXR-design-brief.md` §5 as a new surface; does **not** replace S1
HORIZON or the ROSTER — see §11 for why all three exist.

---

## 1. A different question

HORIZON answers **where**: every mote sits at its true bearing and range. That
is the app's thesis and it is right. But it cannot answer the question an
operator asks the moment the mesh stops working:

> *Everything routes through one repeater. Which one?*

Bearing cannot show that. Two nodes 3° apart on the ring may be six hops apart
in the network, and the repeater the whole neighbourhood depends on looks
exactly like any other mote. Topology is not a restyling of the horizon; it is
information the horizon structurally cannot carry.

SNS reached the same conclusion and its `MeshTreeView` says so in one line
worth stealing verbatim:

> *Compared to the globe view this is topology, not geography — peers without
> GPS still get a place (their connectivity does the work). Compared to the
> radial view this is connectivity, not recency — every edge in the picture is
> a confirmed route.*

**Peers without GPS get a place.** On the ring, a node with no position is
parked in an "unlocated" arc and says nothing. In the lattice it sits wherever
its connections put it, which for a repeater with no GPS is often dead centre.
That is a real gain, not a nicer picture.

---

## 2. Parity: mirror SNS, do not reinvent it

The phone app has solved the hard half. `mesh_graph.dart` and
`util/force_layout.dart` already define the model, and it should be ported
rather than re-derived:

| SNS concept | Meaning | XR treatment |
|---|---|---|
| Root `self` | Our own radio, pinned | The one node anchored, at the user |
| Resolved chain `self → r0 → r1 → peer` | A confirmed route | Solid spurs |
| Flood-routed peer | Reachable, route not pinned | **Dashed** spur from self |
| Unresolved chain, not flood | Known to exist, position in the tree unknown | **Floater** — no edge at all |
| Direct neighbour (empty chain) | One hop | Solid spur from self |
| Edge dedup | Many peers share a first hop | One spur per pair |
| `maxHops` | Depth filter | The one control this surface needs (§8) |

The XR side owes only the plumbing and the rendering. `MeshLink.onContact`
already reads `c.outPathLen()` and **throws `c.outPath()` away**; carrying it
through `MeshNodes.Peer` is the whole data change.

---

## 3. The data, honestly — and why the graph will look sparse

Three things about MeshCore routing decide what this surface can be, and all
three are already known:

**Path entries are ONE BYTE.** A stored route is a sequence of first-bytes of
repeater public keys. SNS resolves them by building a first-byte → node map and
**tracking collisions as `ambiguous`** rather than picking a winner. The XR side
must do the same, and must *show* ambiguity rather than resolve it silently —
this project's rule against inventing a peer's position applies exactly as much
to inventing an edge.

**Most contacts are flood-routed.** SNS's own comment, from the field:

> *in practice almost every MeshCore contact is flood-routed, so a lower
> default shows only the handful of direct/repeater peers (the "3 nodes"
> surprise). Start wide; the user dials down to declutter.*

This is the single most important line in this document. **Do not expect a
beautiful dense graph.** On a 350-contact mesh the honest picture is a small
solid core of direct peers and repeaters, a large fan of dashed flood edges,
and a cloud of floaters. A design that only looks good on a dense graph is a
design that will look broken on every real mesh.

**Advert-only peers have no path at all.** They are floaters by definition, and
there will be many.

### 3.1 What this surface must never do

- **Never draw an edge it did not resolve.** No inferring links from shared
  bearing, from range, or from hop count. An unresolved peer floats.
- **Never silently pick one side of an ambiguous hash.** Either draw the edge as
  ambiguous, or do not draw it.
- **Never let the layout imply distance.** Spring length is a rendering
  artefact. Two nodes close together in the lattice are not near each other,
  and the surface must not read as a map — which is the strongest argument for
  it looking nothing like HORIZON (§5).

---

## 4. Where it lives

A **summoned FOCUS surface**, like the roster: it is what you are doing while
it is up, so it may use the protected centre (§2.1 rule 2 reserves that against
anything *persistent*).

| Property | Value | Why |
|---|---|---|
| Distance | 1.6 m | Past arm's reach, inside comfortable convergence |
| Extent | ~40° × 30° | Fills the working field without exceeding it |
| Anchoring | World-anchored at summon, billboarded | Nothing may move the user (§8.2) |
| Ring while open | Recessed, as the menu and FOCUS already do | One FOCUS at a time |

**It is a SLAB, not a globe.** A 3D force layout looks better in a screenshot
and is worse to read: depth ambiguity means two nodes that overlap may be
adjacent or may be metres apart, and the only way to resolve it is to move your
head, which is exactly the "reachable without turning" problem §8.2 exists to
avoid. Lay it out in 2D on a plane facing the viewer, and spend the third
dimension on *one* thing: **hop depth**, pushing each ring of the tree slightly
further away. That gives parallax that means something instead of parallax that
must be untangled.

---

## 5. It must not look like the horizon

The lattice and the ring will be on screen minutes apart, both showing motes
and both drawn in the theme's ink. If they look alike, users will read lattice
adjacency as geography, which is the one misreading that makes this surface
harmful rather than merely useless.

So they are deliberately different registers:

- **HORIZON** — motes on a ground plane, range bands, a horizon line. Spatial.
- **LATTICE** — a flat sheet of nodes and edges, no ground, no bands, no
  compass. Everything about it says *diagram*.

Node marks reuse the type shapes already established (repeater = dish, chat =
mote) so identity carries across, but nothing else does.

---

## 6. The force layout in XR

Ported from `util/force_layout.dart`, with three XR-specific constraints:

**IT MUST SETTLE, AND THEN STOP.** A graph that jiggles forever is motion in the
periphery of a see-through display, which §8.2 treats as a nausea risk and
which is also just noise. Run the simulation to convergence — or to a hard tick
cap — then freeze. SNS already has a `frozen` flag for exactly this; XR should
default to freezing on settle rather than offering it as an option.

**REDUCE-MOTION IS A REAL STATE (§9.1).** Under `a11y.reduceMotion` the
simulation runs to completion *invisibly* and the settled graph fades in. The
layout is the information; watching it converge is not.

**IT MUST BE DETERMINISTIC.** Same mesh, same picture, every time. A layout
seeded from a random number is a layout the user cannot learn, and re-opening
the surface to find the network rearranged destroys the one thing a topology
view is for — recognising the shape you saw yesterday. Seed positions from a
hash of the node key, not from a random source.

---

## 7. Drawing it in additive light

- **Edges are spurs**, the primitive `Prims.spur` already provides — never GL
  lines, whose width is ignored on most platforms and which vanish in bright
  passthrough. This is already written down in `Prims`.
- **Flood edges are dashed**, matching SNS. The dashing is not decoration: a
  solid edge is a confirmed route and a dashed one is "reachable, route not
  pinned", and those are different claims.
- **Ambiguous edges** need a third treatment — proposed: dashed *and* dimmer,
  with the ambiguity stated when the edge is focused. Open decision D2.
- **Floaters** sit outside the connected body, unattached, and must look
  deliberate rather than dropped. A faint boundary they live outside of.
- **Self is pinned and unmistakable** — it is the only node whose position is a
  fact rather than a relaxation result.

---

## 8. Interaction

| Action | Pinch | Dwell |
|---|---|---|
| Focus a node | Point at it | Gaze 900 ms |
| Open it | Pinch | Dwell fires |
| Hop depth | The one control: a RAIL, 0–6 | Same, as a dwell target |
| Dismiss | The LIST/LATTICE pip again, or B | Dwell the pip |

Selecting a node opens the **same S3 FOCUS** the ring and roster open — card
and spur, at the node's true bearing. That is what keeps three access paths
from becoming three different apps: they differ in how you *find* a node and
agree completely on what one *is*.

**Labels on focus only.** At 1.6 m the §4.1 floor is 0.0335 m cap, so a
14-character callsign is 15.7° wide — about two and a half of them fit across
the whole surface. Labelling forty nodes at a legal size is not possible, and
labelling them illegally is what §4.1 exists to prevent. Identity at rest comes
from the type mark and from position in the tree; the word arrives on focus.
This is the same rule the dock settled on (`Marks`, 2026-08-02).

---

## 9. Scale and cost

`MAX_MOTES = 24` on the ring, and the reasons were angular crowding and label
budget. Neither applies the same way here — a diagram may be denser than a
horizon — but two hard limits do:

- **PanelEntity count.** Tier R labels are real Android Views with their own
  surfaces. This surface must borrow from `LabelPool`, not create panels per
  node; that pool exists because churning six of them put the device into
  thermal throttle.
- **Edge count.** Every spur is a mesh. Dedup is mandatory (SNS already does
  it), and the hop-depth control is the real budget lever: depth 0–1 is tens of
  edges, depth 6 on a 350-node mesh is not a diagram anyone can read anyway.

**Proposed budget: 60 nodes and 80 edges visible.** Beyond that the hop filter
tightens automatically and the surface SAYS it did — a silent truncation reads
as "this is the whole network", which is a lie about the one thing this
surface exists to tell the truth about.

---

## 10. Legibility budget

At the 1.6 m working distance, §4.1's 1.2° floor is **0.0335 m cap**.

| Element | Cap | Angle | |
|---|---|---|---|
| Focused node label | 0.038 m | 1.36° | one at a time |
| Hop-depth readout | 0.036 m | 1.29° | |
| Node mark | — | ≥1.5° | a mote, not an icon; the 3.0° icon floor does not apply |
| Edge section radius | 0.006 m | — | under ~1 cm a tube disappears in bright passthrough |

---

## 11. Why all three surfaces exist

This is the question the next reader will ask, so it is answered here.

| Surface | Question | Access path |
|---|---|---|
| **HORIZON** | Where are they? | Bearing — spatial, requires turning |
| **LATTICE** | How is this network held together? | Topology — spatial, does not require turning |
| **ROSTER** | What is out there? | Ordered rows — no aiming at all |

The lattice does **not** discharge §8.2. It is still spatial navigation: you
find a node by looking at it. The roster stays, because "no information by
position alone" means there has to be one route that needs no aim, and a
force-directed graph you hunt through is not it. Anyone tempted to delete the
roster once the lattice looks good should read §8.2 again.

---

## 12. Open decisions

- **D1 — Its own pip, or a mode of the roster?** The dock is nine pips and 47°
  wide, and this would make ten. The console spec's STACK was proposed partly
  to stop this; a LATTICE/ROSTER pair sharing one entry is the cheaper answer.
  **Recommendation: share the LIST pip, with the two as modes**, since they
  answer adjacent questions about the same set.
- **D2 — How to draw an ambiguous hop.** Dashed-and-dim is proposed; it may not
  be distinguishable from flood at 1.6 m. Needs a build-and-look.
- **D3 — Freeze on settle, or keep simulating as the mesh changes?** A mesh
  that gains a contact every few seconds would re-converge constantly. Proposed:
  freeze on settle, re-run only on an explicit refresh or on a topology change
  (not on every advert).
- **D4 — Does self sit at the centre or at the edge?** Centre is conventional
  and symmetrical; edge (a left-anchored tree) reads the direction of routing
  more clearly. SNS uses a tree; this may want to differ.

---

## 13. Sequencing

1. **Plumb `outPath`** through `MeshNodes.Peer`. One field, and it is the whole
   data dependency. Do this first and log what comes back — specifically what
   fraction of a real 350-contact mesh has a resolvable chain, because §3 says
   that number decides whether the rest is worth building.
2. **Port the graph model** from `mesh_graph.dart`, with tests. It is pure, so
   it can be argued without a device — the same property that made `MeshNodes`
   and `HandSign` fixable.
3. **Port the force layout**, deterministic and freezing on settle.
4. **Render**, at the budget in §9.
5. **Wire selection to S3 FOCUS**, which already exists.

Step 1 is small and answers the question the whole surface rests on. It should
happen before anything else here is designed further.
