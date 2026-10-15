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

- **Vector OSM offline**: PMTiles regional extracts and a vector renderer.
  This is the route to policy-clean offline OSM.
- **Wi-Fi-only / charging-only** download conditions (connectivity
  plugin).
- **Pick the area on a map** (drag a box) instead of centre + radius.
- **Event layer styling** by property (street names on lines, POI icons)
  and a Burning Man preset with the required disclaimer.
- **Auto-update** packs every N days.
- **Bundled starter basemap**: a world overview at z0–5 from public-domain
  data, so a fresh install has something under the pins.
