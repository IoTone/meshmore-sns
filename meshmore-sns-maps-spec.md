# Meshmore SNS — Offline maps (R61): spec

Issue: [IoTone/meshmore-sns#5](https://github.com/IoTone/meshmore-sns/issues/5)
— "a way to download and cache maps": OpenStreetMap, USGS, event maps;
choose regions; a storage budget; no licensed maps; setup online only;
opportunistic downloads; updates and deletion; expiry.

A mesh radio is most useful where the network isn't. Every map view that
shows tiles (street map, equal grid, fabric survey) has fetched them live
until now, so the maps were blank in exactly the places the app is for.
R61 closes R25's deferred "offline-first" decision.

## The constraint that shapes everything: tile policies

| Source | Licence | Bulk / offline download | R61 treatment |
|---|---|---|---|
| **OpenStreetMap** (`tile.openstreetmap.org`) | ODbL data, attribution required | **Forbidden.** The tile policy says "offline use is not permitted", and that apps must not "bulk download tiles or offer prefetch features", including any "download for offline" button or background job | **View cache only**: tiles you have looked at are kept, honouring `Cache-Control`/`Expires`/`ETag`, with a 7-day floor when the server says nothing. Never prefetched. Stable User-Agent `MeshmoreSNS/<version> (+repo URL)` |
| **OpenTopoMap** | CC-BY-SA | Free to embed "provided the server is not overly burdened, e.g. by mass downloads"; it runs on one small vServer | **View cache only** |
| **USGS The National Map** (USGSTopo, USGSImageryTopo) | US-government public domain | No prohibition found; public-domain data | **Region packs allowed**, inside US coverage only (CONUS, Alaska, Hawaii, PR/USVI). Paced at about 6 tiles/s, one download at a time |
| **Custom tile server** (user-entered `https://…/{z}/{x}/{y}…`) | Whatever its owner says | The user ticks "this server allows offline download", for their own server or one whose terms permit it | View cache, plus packs when ticked |
| **Event maps** (GeoJSON by URL) | The publisher's terms | The user fetches one file | Downloaded once, drawn as an overlay. **The app ships no event data and no event URLs.** The add dialog says that the publisher's terms apply |

So the honest answer to "download OpenStreetMap regions" is: **not from
openstreetmap.org.** You can do it today by pointing a custom source at a
server that permits offline use (self-hosted, or a provider whose terms
allow it). OSM data you can legally take offline in bulk comes as **vector
extracts** (for example Protomaps PMTiles builds), which needs a vector
renderer. That is phase 2, below.

"No licensed maps" holds: nothing keyed or commercial is built in.

### Event maps: the Burning Man example

Burning Man publishes its city plan as GeoJSON (street lines and outlines,
plazas, CPNs, toilets, the trash fence) at innovate.burningman.org and in
`burningmantech/innovate-GIS-data`. Its terms: no commercial use, the app
must be free, a prominent "not affiliated, endorsed, or verified by Burning
Man Project" disclaimer, camp locations are embargoed until the Sunday
before the event, and "Burning Man" may not appear in an app's name. R61
works with such data because the user brings the URL. We do not bundle
the data or preset the URL. If we ever add a preset, it must carry the
disclaimer.

## Model

- **Tile store**: one file per tile under
  `<app-support>/maps/tiles/<source>/<z>/<x>/<y>`, with one JSON index of
  bytes, fetched-at, expires-at, last-used, ETag, and the set of packs
  that hold the tile.
  - A tile with **no pack** is a *view* tile, the only kind evicted
    automatically.
  - A tile in several packs is stored once. Deleting one pack never
    breaks another.
- **Region pack**: a source, a box (centre ± radius), a zoom range, and a
  "delete after" period.
  - Tiles are fetched lowest zoom first, so a half-done pack is already
    useful zoomed out.
  - States: downloading, updating, waiting for network, stopped (over
    budget), paused, complete.
  - At most 50,000 tiles per pack. The top zoom is capped at the
    source's native maximum.
- **Event layer**: name, https URL, size, feature count, delete-after,
  and visible.
  - GeoJSON Point/MultiPoint, (Multi)LineString, (Multi)Polygon (outer
    rings only) and GeometryCollection are drawn.
  - At most 10 MB per layer.
- **Custom source**: name, https template containing `{z}`, `{x}` and
  `{y}` (`{s}` optional), attribution, and the allows-offline flag.

## Rules

1. **Server rules are not preferences.** A view-only source shows no
   download control at all. The source list says why, e.g. "Viewed tiles
   only: the server forbids bulk download".
2. **Setup is online-only.** Creating a pack fetches its first tile not
   already held, and if that fails nothing is created ("Can't reach the
   server. Set up maps while online."). Adding a layer is its download.
3. **Opportunistic downloads.**
   - A failed fetch parks the pack as *waiting for network*, and backoff
     runs from 30 s, doubling to 15 min.
   - The pack wakes on the backoff timer, or as soon as any map fetch
     succeeds (for example, the user panning a map).
   - Packs survive restarts and resume on launch.
   - No Wi-Fi-only switch yet; that needs a connectivity plugin. Noted
     as phase 2.
4. **The budget is one number** (100 MB – 5 GB, default 500 MB), shared by
   packs, layers and the view cache.
   - Packs and layers are *pinned*. The view cache gets what they leave,
     evicted least-recently-used first.
   - Creating a pack refuses if its estimate won't fit beside the pinned
     bytes.
   - A pack that grows past the budget (because the server's tiles are
     heavier than planned) stops as "over budget". The check uses the
     larger of the plan and the observed tile size. Raising the budget
     resumes it.
5. **Updates are conditional.** "Update" re-asks the server about every
   tile with `If-None-Match`/`If-Modified-Since`: a 304 is cheap, and gaps
   are filled. Pack tiles are never re-fetched merely because someone
   looked at them. Stale *view* tiles are revalidated when online, and
   shown as they are when offline.
6. **Expiry deletes.** Packs and layers have "delete after" settings of
   never, 7, 30, 90 or 365 days, counted from the last finished download
   or update. View tiles unused past "keep viewed" (7–365 days, default
   30) are dropped. The sweep runs at launch and hourly.
7. **Attribution is always on the map** for the visible basemap.
8. **Every refusal is a sentence** (house rule from R60): no name,
   offline, view-only source, outside coverage, too many tiles, over
   budget, not https, not GeoJSON, over 10 MB.

## UI

**Map tab** (the viewer): the street map is a primary swipe page, right
after the Hyperlocal grid, in every skin. It is the same `StreetMapView`
that the grid offers as a view mode, promoted so it is one swipe away
rather than three picks deep. It is the *viewer*; pack and source
management stay in Settings → Offline maps, one tap from a corner button
on the map. Because a pan/zoom map owns horizontal drags, the shell's
swipe is locked on this tab, the same rule the grid applies to its
panning views. Unlike the grid, the Map tab keeps a way out by gesture:
a 24dp band at each screen edge (R67, `MmEdgeSwipe`) is hit-tested
before the map, so an inward fling there goes to the previous (left) or
next (right) view and the map never sees those touches; the middle
pans and zooms. Back and the view strip also leave. With no position yet
(R69) the Map tab is still a map: a **world view** (centre 20N 0E, zoom 2,
a deliberate non-guess at the user's region) with a quiet, non-modal,
non-dismissable hairline row at the bottom: "No position fix yet. This is
a world view, not centred on you." The re-centre button is disabled and
self/range markers are omitted until a fix arrives, at which point the
map recentres on self at zoom 14.
(R70) The OSM credit line sits in the same bottom column as that row so it
is never covered; the five map controls are 48dp and the right edge band
starts below the column (derived from it). The edge bands start just
inside the Android system-gesture zone (`systemGestureInsets`): a swipe
from the very edge is the OS's Back. Under the Studio skin the basemap is
**rendered from a vector style** (R80), not shown as pictures and not
filtered: `assets/maps/studio_dark.json` (Apache-2.0, derived from
OpenFreeMap's `dark` style, OpenMapTiles schema over OSM data, trimmed to
one vector source and with `glyphs`/`sprite` removed) is drawn by
`vector_map_tiles` onto Flutter's canvas, so land, water, roads and parks
carry their own colour and the result is sharp at every zoom instead of
an upscaled PNG. Tiles come from `kOpenFreeMapVector` through
`MmVectorTileProvider`, which calls the same `MapsController.loadTile`
bytes path the raster layer used, so the R61 view cache, packs, ETag
revalidation, budget and expiry all still apply. Labels need no glyph
server: the renderer draws `text-font` with Flutter's text engine. The
credit line follows what is drawn (`kOpenFreeMapVector.attribution`:
OpenFreeMap, OpenMapTiles, OpenStreetMap).

The dimmed raster path remains as the fallback for a skin that has not
opted in, and for a build where the style asset fails to load (R79:
`out = 0.70 * in`, a pure RGB scale, so hue survives - land 169, sea
119/148/156, label 36, 6.7:1). R70-R73's luminance invert plus 0.15
desaturation is gone: it flipped hue (OSM water read orange) and, being
per-tile and global, destroyed the USGS aerial-imagery source, which has
no luminance structure to invert. The grid's street-map mode keeps its
"awaiting fix" text (`StreetMapView.browseWithoutFix`, default off; only
`MapScreen` opts in).

**Settings → Offline maps** (new hub row, after Tools):

- **Storage**: "X of Y used" bar, then the breakdown (regions · event
  maps · viewed tiles), Budget, Keep viewed, and Clear viewed tiles.
- **Region downloads**: one row per pack.
  - Row text: name; source and zoom; state, tiles done/total, size, and
    "N not on server"; then "Deletes in N d" or "Kept until deleted";
    plus a progress bar while incomplete.
  - Menu: Pause/Resume, Update, Delete after…, Delete (confirmed).
  - Button: **Download a region**.
- **Event maps**: one row per layer, with a visibility switch, host,
  feature count and size, and expiry.
  - Menu: Download again, Delete after…, Delete.
  - Button: **Add event map** (name, URL, delete-after, and the
    publisher-terms note).
- **Map sources**: each source, with whether it can be downloaded.
  Custom sources can be deleted, which deletes their packs. Button:
  **Add tile server**.

**Download a region** has these fields: name, source (only sources that
allow packs), centre (my location, or typed lat, lon), radius (1–50 km),
zoom from / to, and delete after. A live line shows "N tiles · about X",
and a refusal sentence appears whenever the plan would be refused. The
Download button stays off until the plan is acceptable, and an empty
name just keeps it off without a scolding.

**Street map** (grid tab): the street/topo toggle becomes a **basemap
picker** listing every source (built-in and custom). Visible event layers
draw over the basemap and under the nodes. An attribution line sits
bottom-left. Equal-grid and fabric survey use the cached OSM layer.

## Self-test (validation)

**Offline maps → Self-test** (the app-bar check icon) validates the
whole path on the phone, against the real servers and the phone's own
storage. It runs in a sandbox: a `maps-selftest` folder beside the real
maps folder, and its own settings key. The sandbox is deleted
afterwards, so the user's packs and budget are never touched. A run
takes about 40 s and about 0.9 MB of data. **Copy report** gives
plain text for an issue comment.

| Check | Passes when |
|---|---|
| Map servers reachable | OSM and USGS Topo return an image at z12 (OpenTopoMap and USGS Imagery are reported, not required); latency and max-age shown |
| Viewed tiles are kept | Two loads of one tile cause one fetch |
| Stale tiles re-checked politely | 8 days later (clock skew), a conditional request is sent; 304 or re-send reported |
| Region download | A USGS pack of about 1 km, z12–14, completes; tiles held = total − missing; rate shown |
| Region update | Every tile is re-asked; the 304 vs re-sent counts are shown |
| Event map | A public GeoJSON (BRC street centrelines) parses to features |
| Offline behaviour | With the network cut, a cached tile shows, an unseen tile is blank, and a new pack and a new layer are refused as offline |
| Pause and resume | The network is cut mid-pack; the pack parks, then finishes **by itself** when the backoff timer fires (about 30 s) |
| Refusals | A huge area gives too-many-tiles, a 100 MB budget gives over-budget, OSM is view-only, Tokyo is outside coverage |
| Delete-after expiry | 8 days later, packs and the layer are gone and the bytes are freed |
| Storage matches the books | Tile bytes on disk equal the index's count |

The test point is the user's own location when USGS covers it, or else
Black Rock City.

For developers, `tool/maps_selftest_device.dart` is the same self-test
as a headless APK entrypoint. It writes the report to logcat between
`MAPS-SELFTEST BEGIN/END` markers; the usage is in the file header.
First device run (SH-53D, 2026-10-15): **all 11 pass**, 38 s.

## Phase 2 (not built)

- **Vector OSM offline**: built in R81 (region files, below). Still open:
  a hosted list of regions, range reads of a remote archive for online
  use, and the Protomaps schema.
- **Wi-Fi-only / charging-only** download conditions (connectivity
  plugin).
- **Pick the area on a map** (drag a box) instead of centre + radius.
- **Event layer styling** by property (street names on lines, POI icons)
  and a Burning Man preset with the required disclaimer.
- **Auto-update** packs every N days.
- **Bundled starter basemap**: a world overview at z0–5 from public-domain
  data, so a fresh install has something under the pins.

## R81: region files (PMTiles) and the map network path

### Why one file per region
A `MapPack` fetches a box tile by tile. That is the wrong primitive for
vector OSM: OpenFreeMap's terms allow an app's offline download only if it
is "at most 3,000 tiles or 50 MB, made with at most 4 parallel requests,
sent with a unique User-Agent" (openfreemap.org/tos, checked 2026-10-20),
and OSM's own tile servers forbid bulk download. Tile counts for a modest
region (computed with the app's tile maths, exact):

| Region (bbox) | z0-12 | z0-14 | z14 only |
|---|---|---|---|
| Front Range, 38.2,-105.4 to 40.8,-104.5 | 657 | 8,883 | 6,510 |
| Cascadia, 42.0,-125.0 to 50.0,-117.0 | 16,423 | 257,090 | 192,355 |

Front Range at z14 is three times the cap, Cascadia is 86 times it (and
over `MapsController.maxPackTiles`, 50,000). So a region must come as a
file from a host that permits it. Size in bytes is an **estimate from
published ranges, not measured here**: Colorado at z0-14 is 50-150 MB, so
a Front Range corridor is roughly 30-80 MB; Cascadia 150-450 MB at z14
and about 50 MB at z12. The app's planning figure of 12 kB a tile would
say 107 MB and 3.1 GB, which shows how much dedupe and empty ocean tiles
matter; that figure has never been measured against real tiles.

### Model
`MapArchive` (`lib/maps/map_archive.dart`): id, name, https url, optional
declared size and SHA-256, keep-for days, state (downloading, waiting for
network, over budget, paused, complete, failed) and, once accepted, the
file's zoom range and extent from its header. Files live in
`<maps root>/archives/<id>.pmtiles` (`.part` while downloading). They count
in `usedBytes`/`pinnedBytes`, so the view-tile cache gives way to them.

### Download, resume, accept
Streamed to disk, never buffered. Resume sends `Range: bytes=N-` with
`If-Range: <etag>`: a 206 whose `Content-Range` starts at N continues; a
200 restarts at zero (range ignored, or the file was replaced, so a file is
never stitched from two versions); a 416 whose total equals N means the
part is already the file. A lost connection parks the archive as waiting
and the existing retry and wake-on-success machinery resumes it, as does
an app restart. A file is only used after: size (declared, else the
server's), SHA-256 when given, `PmTilesArchive.open`, tile type MVT, and
the layers `water` and `transportation` (OpenMapTiles). Anything else is
deleted and the row says why. The budget stops the download at the real
byte that would break it; raising the budget and resuming finishes it.

### Reading
For the vector basemap, a tile inside a complete archive's extent and zoom
range is read by seek with no network; an empty cell inside it is final;
outside every archive the view cache and network answer. A damaged file
falls through to the network instead of blanking the map.

### How the owner makes a region file
The accepted schema is OpenMapTiles (the bundled style and OpenFreeMap use
it), so the file must carry that schema. Planetiler (Apache-2.0) builds it
by default from an OSM extract, for example
`java -jar planetiler.jar --download --area=colorado --maxzoom=14
--output=colorado.pmtiles`, then `sha256sum` it and host it on any static
HTTPS host that serves byte ranges. **Unverified**: this recipe was not run
here (it needs a multi-GB download and Java). `pmtiles extract` on a
Protomaps build is simpler but yields the Protomaps schema (`earth`,
`roads`, ...), which the app refuses on arrival.

### R81 decisions (why Protomaps was not adopted)
- Protomaps public builds are dated (`maps.protomaps.com/builds`), kept
  for about a week, and their docs say "hotlinking to these downloads are
  discouraged ... copy the tileset to your own Cloud Storage"
  (docs.protomaps.com/basemaps/downloads). They are an input to extract
  from, not a runtime URL.
- The only stable public vector endpoint is OpenFreeMap (OpenMapTiles).
  Keeping one schema end to end means one style, and an archive is a
  drop-in for the same tiles. Switching schema means a second style plus
  schema detection, or dropping online vector. That is the owner's call.
- The data is ODbL: a produced work (tiles) may be distributed with
  attribution (docs.protomaps.com: "Open Database License Produced Work,
  OpenStreetMap attribution required"), so self-hosting a region file is
  permitted. Attribution on the map names OpenStreetMap.

### Network path (R81)
Viewing fetches go through `TileFetchGate` (4 concurrent, newest first,
queue 32, oldest dropped). Backoff is per source after three consecutive
failures. A server "no such tile" is remembered for the run. The vector
layer's own tile file cache is capped to 1 MB / 1 h because `TileStore` is
the cache of record. The library cannot cancel a provider call and has no
prefetch ring, so neither is implemented.
