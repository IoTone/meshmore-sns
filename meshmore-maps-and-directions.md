# MeshMore — maps, social places and directions, 2026-11-04

Scope: the map subsystem as built, the "social map" (shared pins, places, meeting points), and
turn-by-turn directions to a shared pin using OpenStreetMap-derived routing rather than Google.
Companion to `meshmore-feature-audit.md` and `meshmore-feature-plan.md`.

Licence figures below come from a web research pass on 2026-11-04 and are **untraced beyond the
summary**; the GPL/AGPL question is settled (none of the candidates is copyleft), the MapLibre iOS
routing-provider question is **not** settled.

---

## §1 The map stack as built

- **Four tile sources** (`maps/map_source.dart:110-190`): OSM Shortbread **vector** at
  `vector.openstreetmap.org/shortbread_v1/{z}/{x}/{y}.mvt`, `maxNativeZoom` 14, 40 KB planning figure
  (84 KB measured on a dense z13 Denver tile), `minCacheAge` 7 days, packs **not** allowed; OpenTopoMap
  raster (view-cache only by its policy); USGS topo and USGS imagery (ArcGIS REST, packs allowed,
  **CONUS+AK+HI+PR only**); OSM standard raster retained as fallback only.
- **The vector basemap is the default on every skin** since R90, and it is a *style* (28 layers, 14.9 KB,
  `assets/maps/studio_dark.json`) drawn against Shortbread v1 — **not** bundled tiles. Offline needs
  region files or nothing.
- **Hand-rolled HTTP + cache**, no package: `If-None-Match`/`If-Modified-Since`, `Cache-Control` over
  `Expires`, duplicate-value headers joined per RFC 9110 (one tile server's doubled `cache-control`
  header killed every vector tile), in-flight de-dup keyed by tile (`maps/map_fetch.dart:40-69`,
  `maps_controller.dart:385-398`).
- **Fetch gate**: 4 concurrent, newest-first, stale dropped (`maps/fetch_gate.dart:17-53`); a source
  backs off after 3 consecutive view failures (`maps_controller.dart:100`); absent tiles remembered for
  the run, cap 2048 (`:95`).
- **Storage**: one file per tile plus one JSON index that is the truth for accounting
  (`maps/tile_store.dart:53-72`). Budget **100 MB–5 GB, default 500 MB**, decimal MB. Packs and layers
  pinned; view cache takes what they leave, LRU. Region packs cap at **50,000 tiles**; event layers at
  **10 MB**.
- **Rendering**: `vector_map_tiles` + `vector_tile_renderer` on Flutter's own canvas, no platform view.
  Labels through Flutter's text engine — no glyph server, no sprite. Unloaded tiles read as the style's
  background so a gap looks like "land, not yet drawn" (`maps/vector_basemap.dart:5-50`).
- **Projections**: Web Mercator for raster and vector street map; hand-rolled orthographic sphere for
  the globe (`screens/globe_view.dart:936`); equal-grid deliberately **not** Mercator so density
  comparison is honest (`screens/equal_grid_view.dart:30-32`).
- **No clustering anywhere.** The globe collapses peers into ~10° geohash bubbles; the street map
  overplots; event points cap at 2,000 drawn.
- **Gestures**: drag, pinch, wheel, double-tap; **rotation deliberately disabled**
  (`street_map_view.dart:310-316`); edge-swipe band to leave the tab because R95 made the shell
  `PageView` unscrollable.
- **Performance guards**: warm ring — after 500 ms settle expand by one tile, cap 24, prefetch only when
  the gate is idle; parsed-tile memory cache 24 MB; honest z17 ceiling because Shortbread stops at z14.

---

## §2 What the map can show, and what it cannot do

**Shows:** node markers with role glyph and known/favourite state; self marker with heading; self and
per-peer reach circles; coverage polygons; chatter-heat cells; event-layer geometry; globe arcs;
mesh-tree topology; inferred-place markers; own trail.

**Interactivity:** only peer/node markers are tappable (opens `NodeDetailSheet`). Event-layer points
carry a tooltip and nothing else. Inferred places are tappable only in a bottom-sheet list, not on the
canvas. **Nothing is draggable. Nothing can be created.** There is **no tap-on-map and no long-press
handler** on the basemap at all — the only `onLongPress` in any map view is the equal-grid's zoom reset
(`equal_grid_view.dart:408`).

That single absence is the first blocker for every feature in this document.

---

## §3 Sharing primitives — what exists

**Outbound:** coordinates as plain text at 5 dp in the node sheet, dashboard, Studio dashboard, recon
dashboard and the range-test `RT <seq> <lat>,<lon>` strings. "Show on map" launches **Apple Maps on
iOS/macOS and Google Maps elsewhere with a 6 dp pin and no directions**
(`screens/node_detail_sheet.dart:677-693`). Clipboard copy exists for pubkey and message text only.

**Inbound — and this is the important finding:** `PlaceInferenceEngine` already parses decimal lat/lon
out of message text at **confidence 0.95** and Maidenhead grid locators at 0.90, plus gazetteer names and
"X to Y" pairs (`sns/place_inference.dart:314-345`). So **a pin can be shared to another MeshMore user
today, as text, with zero protocol work.** It plots as an inferred marker and cannot be acted on,
because there is no pin object — `InferredMarker` is a heuristic with a dismiss action.

**Missing to share a pin properly:** a canonical text convention with a tap target; a map interaction to
*create* a point; a saved-place object (favourites are pubkeys, not places); and a structured type, which
needs the `0x3E` channel-datagram encoder that does not exist.

---

## §4 The social map — a design that fits what already ships

The app already has most of a social map without calling it one: chatter heat per cell, inferred places
from message text, a gazetteer, Meshbook volume/reply-rate/top-voices per hour, and a coverage store that
persists across sessions. What it lacks is **objects a user can create, name, share and act on.**

Proposed model, in dependency order:

1. **`Place`** — the object that does not exist today. Fields: id (deterministic from coordinates so the
   same place merges), lat/lon, precision (the grid snap the user chose), name, type, provenance
   (device / phone / pinned / inferred / received), created-by (pubkey or "me"), created-at, expiry,
   confidence, notes, and an optional photo/voice reference once media exists. Persisted locally,
   revisitable, searchable by name, exportable.
2. **Place types with meaning** — hazard, water, fuel, medical, rally/meeting, viewpoint, camp, "look
   here", custom. A type is what makes a pin actionable: "water, 400 m, reported 2 h ago by K7ABC" is a
   field tool; "pin" is not.
3. **Create** — tap/long-press the basemap to drop a pin, or "pin my position". No map creation gesture
   exists, so this is a real UI feature, not a wiring change.
4. **Share as text first** — a canonical convention that survives any client, any channel, any number of
   hops, and is already parsed inbound at 0.95. Cheapest possible path, and it works on the mesh today.
   The convention must carry type, name, precision, expiry and reporter, not only coordinates.
5. **Act on a received pin** — tap a coordinate in chat or on the map, open the place, then "show on map",
   "directions", "save", "reply with my ETA".
6. **Structured type second** — once `0x3E` exists, a channel datagram carrying the same fields in binary,
   with the text convention as the fallback announcement. Same pattern the ecosystem already uses:
   announce in text, carry in binary, correlate by session id.
7. **Meeting point** — a place with attendees and an ETA, arrival detection by geofence, and "who's
   coming" evidence. This is the first genuinely social object and it depends on the geofence design
   that is written but unbuilt.
8. **Place corrections** — a user must be able to confirm, correct or refute an inferred place. Today the
   only action is dismiss. A social map without correction accumulates lies.

**What not to build:** implicit position broadcasting. A pin must be a deliberate act, or the social map
becomes the privacy failure the ecosystem documents at length.

---

## §5 Directions — the options, with the licence verdict

The requirement is "a user shares a pin; another user gets driving or walking instructions to it".
Four architectures, cheapest first.

### Option 1 — handoff to an external app (zero build, needs network)

Today's launch opens a pin in Apple/Google Maps. Extending it to a *directions* URI (`geo:lat,lon?q=`,
`maps://?daddr=`, or an OsmAnd/Organic Maps intent) is a few lines and needs no data. It works with the
user's own offline maps. **Limitation:** the instructions live in another app, so MeshMore cannot show
progress, arrival or ETA, and cannot work without that app installed. It is also the only option that
works everywhere on day one.

### Option 2 — on-device routing engine plus a per-region graph (offline-correct)

The engine comparison, from the 2026-11-04 research pass. **None of these is GPL or AGPL**, so an MIT
Flutter app can link any of them; the obligations are notice-retention only. The hard licence problem is
the **data**: OSM-derived routing graphs are an ODbL Derivative Database — attribution and share-alike on
the database, not on the app.

| Engine | Licence | On-device | Android fit | iOS fit | Storage shape | Turn-by-turn |
| --- | --- | --- | --- | --- | --- | --- |
| **BRouter** | MIT | designed for it | pure Java, simplest | none official | **shared segment files; near-zero per-profile multiplier**; 5°×5° rd5 tiles, per-country download | **yes — voice hints are a documented feature** |
| **Valhalla** | MIT | yes, published AAR + XCFramework (`io.github.rallista:valhalla-mobile` 0.6.1) | JNI, heavier | Objective-C++/Swift, real | one tile set amortises **all modes**; community country packs exist | yes (narrative construction) |
| **GraphHopper** | Apache-2.0 core | yes | Java on ART, easy | J2ObjC translation, heavy | one graph **per profile**: ~12 GB Europe base, ~27 GB with 5 profiles, ~14 GB per LM profile | engine only; navigation is a **paid** SDK |
| **OSRM** | BSD-2 | legally yes, practically no | needs nodejs-mobile or hand-written JNI | same | multi-GB memory-mapped `.osrm` files, per-profile datasets | text instructions only |
| **MapLibre Native + Navigation** | BSD-2 | yes | AAR, actively released (`org.maplibre.gl:android-sdk` 2026.10.19) | Swift package | tile store + external routing service | yes, but **routing provider lineage is an unresolved licence question** |

**The decisive structural difference:** BRouter and Valhalla amortise profiles; GraphHopper and OSRM
multiply storage per profile. Against a **500 MB shared budget**, per-profile multiplication is
disqualifying for a multi-modal product (car + walk + cycle).

**BRouter is the best fit for an Android-first product:** MIT, pure Java (no FFI bridge), the only engine
architected for the device from the outset, small per-region segments, and documented voice hints which
map directly onto the TTS the app already ships. Its weakness is iOS, which is exactly the platform that
is deferred.

**Valhalla is the best fit if iOS and desktop matter soon:** a maintained mobile distribution on both
platforms and one tile set for all modes. Its weakness is build weight and the JNI/ObjC layer.

**Recommended:** an abstraction layer (`RoutingProvider`) with **BRouter on Android first**, Valhalla as
the second implementation when iOS lands. Never OSRM on-device; never MapLibre Navigation until its
routing-provider question is answered.

### Option 3 — online routing service (breaks offline-first)

GraphHopper's hosted API, OpenRouteService, or a self-hosted Valhalla. Only acceptable as an optional
enhancement, explicitly online, never the default. Rejected as the primary path.

### Option 4 — no directions, bearing and range only

Honest fallback: "target 1.2 km at 214°" plus the existing external handoff. Costs almost nothing,
works offline, and is genuinely useful in the field where a road route may be wrong anyway. This is the
correct floor and should ship regardless of which option is chosen.

### The artifact problem — the real blocker

Same shape as the region-file deferral already in the repo (`maps/map_archive.dart:19`,
`kRegionFilesEnabled = false`): **the machinery can exist but nothing is published.** Routing packs are
bigger than tile packs and more regionalised. Three viable answers, in cost order:

- **Fetch per region on demand** from a public source (BRouter publishes rd5 tiles at
  `brouter.de/brouter/segments4/`; Valhalla has community country packs). Needs a stable URL, a checksum
  and a size estimate before the download starts.
- **Ship one small region** with the app for the launch market only, and say so.
- **Self-host** a pack per region — the only option that guarantees availability, and it makes MeshMore a
  distributor with the support burden that implies.

Whichever is chosen, the honest UI sentence is "directions work offline in [region]; elsewhere they need
a connection or another app".

---

## §6 Constraints this design inherits

- **Storage is shared with tiles.** 500 MB default covers a small country's tiles plus its routing pack
  and not much else. The budget must be re-cut per feature, not per screen.
- **The basemap is network-only outside the US.** Only two built-in sources allow packs and both are
  US-only; outside CONUS/AK/HI/PR the offline story is empty today and every map feature inherits that.
- **No creation gesture exists.** Every social-map feature starts with one.
- **Place inference already works inbound**, so the text side is a formatting decision, not a parsing one.
- **ODbL is a data obligation**, not a code obligation; attribution must be visible on the map and in any
  export.
- **Android-first** means BRouter now and Valhalla later, or Valhalla now to avoid the swap.
- **The app has no background location of its own** beyond the foreground service; a directions session
  that must survive a locked screen needs a second architecture decision.

---

## §7 Decisions this document needs

| # | Decision | Options | What changes |
| --- | --- | --- | --- |
| M1 | **Pin sharing mechanism** | text convention first; structured `0x3E` type first; text now + structured later | zero protocol work vs richer payloads; airtime |
| M2 | **Social model** | private pin; broadcast to a channel; shared object with attendees and ETA | message vs feature; needs geofence design |
| M3 | **Directions depth** | external handoff only; on-device engine; both (handoff now, engine later) | storage budget, engine choice, iOS path |
| M4 | **Routing engine** | BRouter (MIT, Java, Android); Valhalla (MIT, mobile AAR/XCFramework); both behind an abstraction | iOS readiness vs build weight |
| M5 | **Who publishes the routing/tile packs** | fetch from public sources; ship one region; self-host | support burden, offline coverage |
| M6 | **Map creation UX** | long-press to drop; a "+pin" mode; a place search from the gazetteer | first blocker for every social feature |
| M7 | **Correction model** | confirm/refute only; full edit; voting | data quality vs complexity |
| M8 | **Place-to-place navigation** | "directions from me"; "directions from a chosen start"; multi-stop | field utility vs scope |
