# MeshmoreXR — THE MAP VIEWS: a design brief that does not exist yet

**Status: FLAGGED, NOT WRITTEN. Deferred deliberately, 9 August 2026.**

Nothing here is a design. It is an accurate inventory of the ten views SNS
already ships, so that when §S6 TERRAIN is built it is not built for one view
and then bent around nine more.

---

## The ten, resolved against the SNS source

They are the `_GridViewMode` enum in
`meshmore_sns_app/responsive_starter_app/lib/screens/grid_screen.dart`, and
every one has an implementation. Short names as spoken, mapped to what they
actually are:

| Spoken | Enum | Source | What it is, from its own header |
|---|---|---|---|
| **radar** | `radial` | `grid_screen.dart` | R18/U9 — the hyperlocal radial range-ring view. The default, and the one MeshmoreXR's HORIZON already is. |
| **globe** | `globe` | `globe_view.dart` | R27 — macro globe. Mesh fabric on a 3D earth from Natural Earth 110m land polygons. Pure Flutter, no WebView. |
| **cells** | `equalGrid` | `equal_grid_view.dart` | R25 — rectangular canvas of equal-sized cells centred on us; each located peer placed in its cell. **See the conflict below.** |
| **roads** | `streetMap` | `street_map_view.dart` | R25+2 — a standard interactive street map, full-colour OSM tiles. |
| **mesh** | `fabric` | `fabric_survey_view.dart` | F8 — mesh COVERAGE as a quilt of shaded cells over a basemap. **Multi-session aggregation**: every cell where activity was ever observed. |
| **fuji** | `elevation` | `elevation_profile_view.dart` | R45 — altitude profile. A NERV-style targeting HUD with real-world references at true height and our node pinned at its reported altitude. Its own header says it is meant to be *interesting* rather than useful. |
| **tree** | `tree` | `mesh_tree_view.dart` | R50 — directed topology tree, force-directed. Data is `Contact.outPath`; shared repeaters become hubs. |
| **sns** | `snsCells` | `sns_cells_view.dart` | R51 — social-activity heat map. Same cell idea as the grid, but plots CHATTER not presence; cells cool over an hour. |
| **wx** | `weather` | `weather_view.dart` | Mesh weather — environment telemetry across the fabric: reporting-node count, min/avg/max temperature, nodes sorted warmest-first. |
| **mbk** | `meshbook` | `meshbook_view.dart` | Meshbook — rolling last-24h social shape of the current channel: volume, reply rate, top voices, topics, hourly histogram. |

**Correction to the previous version of this file:** it recorded five of these
as undefined and said they had to come from elsewhere. They were all in this
repository. Scanned rather than asked.

---

## What the inventory changes

**Four of the ten are not maps.** `tree` is a topology graph, `wx` is a
telemetry table, `mbk` is a statistics readout, and `fuji` is an altitude
chart. They live in the map picker in SNS because that is where the space was,
not because they are geographic — and in XR, three of them have a more natural
home: topology on the HORIZON, telemetry on a FOCUS panel, Meshbook as its own
surface. **Porting the picker would carry a phone-shaped filing decision into a
room-shaped app.**

**Three ARE the same map with different data on it.** `cells`, `mesh` and `sns`
all shade geographic cells — presence now, coverage ever, chatter lately. On a
floor-scale terrain those are obviously three LAYERS, not three views, and §2.1
rule 2 (more room means a bigger world window, not more UI) argues hard for
collapsing them.

**`radar` is already built.** It is the HORIZON. That is worth saying plainly
because it means the suite is 1 of 10 only if you count the way SNS counts.

---

## The conflict, now precisely identified

§S6.0 already ruled on `cells`:

> *"R25's equal-grid map does not port, and should not. Equal-area cells exist
> because a phone screen is small and you need comparability between buckets. At
> floor scale you have a real map and real space, so the abstraction has nothing
> to buy. Port the purpose, not the workaround."*

That is exactly `equal_grid_view.dart`. So the brief has already declined one
of the ten — and note there are **two** cell views (`equalGrid` and `snsCells`)
which the short names `cells` and `sns` do not distinguish. Whatever the brief
concludes, it has to say which of those two survives and in what form.

---

## Still open, and genuinely open

1. **Which of these are views, which are layers, and which are not maps at
   all.** The inventory above is the argument; the decision is not made.
2. **`roads` has no offline story.** §S6.0 settled that OSM tiles cannot be
   prefetched under the usage policy, and PMTiles is the answer for the base
   map. `street_map_view.dart` uses live OSM tiles today.
3. **`wx` needs live data** on a device whose proposition is working where
   there is no network — but unlike `roads` it may be fine, because its source
   is *the mesh itself* (environment telemetry from peers), not the internet.
   Worth confirming: that would make it the only "live" view that works offline.
