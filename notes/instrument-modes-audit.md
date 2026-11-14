# Instrument modes — audit (tree, weather, and the other grid views)

Scope: `lib/screens/mesh_tree_view.dart`, `weather_view.dart`, `grid_screen.dart`,
`sns_cells_view.dart`, `elevation_profile_view.dart`, `lib/meshcore/mesh_graph.dart`,
`lib/meshcore/topology_hop.dart`, `lib/meshcore/mesh_radial_layout.dart`.

Everything below was read from the code and, where a claim is marked PROVEN, executed.
SUSPECTED means the code reads that way and I did not build a reproduction.

---

## 1. What each view claims, and what it does

| View | On-screen claim (`gridPurpose*`) | What it actually draws |
| --- | --- | --- |
| Radar (`radial`) | "How far each node is, and how long ago it was heard." | True: bearing+distance when both ends have a fix, else a signal-derived ring with a hashed placeholder angle, and the marker is hollow when the angle is not a direction (`gridMarkerSourceFor`, `grid_screen.dart:100-108`). |
| Mesh tree (`tree`) | "How nodes reach each other, from the routes they advertise." | True since the resolver keeps unresolved hops (`topology_hop.dart`). Depth is the learned route; a flood-routed peer gets a dashed edge; an advert-only peer floats on the `?` ring. **But the hop filter counted bytes, not hops** — fixed here, see §2. |
| Weather (`weather`) | "Temperature, humidity and pressure, from nodes that report them." | True, plus a second block mined from chat (`sns/weather_inference.dart`) which states its channel and its age. **The measured numbers ignored the reader's temperature scale** — fixed here, see §3. |
| Altitude (`elevation`) | "How high each node is, against landmarks." | True, and the file's own doc calls it "**Not** meant to be useful … meant to be *interesting*" (`elevation_profile_view.dart:18-21`). It is a landmark HUD; the on-screen line is honest about what it plots but not about the fact that most peers land in the `?` band until telemetry is polled. |
| Message heat (`snsCells`) | "Where messages came from, cooling over the last hour." | True for the current session: `MessageHeatTracker` with τ=15 min and a 1 h horizon (`message_heat.dart:71-80`), fed by `mc.messageHeatScores()`. Nothing is persisted, so a relaunch starts cold — see §4.5. |

The hop ladder (`mesh_tree_view.dart:37-45`) is `[0,1,2,3,4,5,10,allHops]` and a stop
below All means "peers whose route the radio has learned, at most N deep"; All (99) means
everything including unknown depths. That contract is stated in `mesh_graph.dart:112-135`
and is what the tests in `test/screens/mesh_tree_hop_ladder_test.dart` pin.

---

## 2. PROVEN BUG — the tree's hop filter counted path bytes as hops

`lib/meshcore/mesh_graph.dart:182` read

```dart
final int? hops = peer.outPathHashes?.length;
```

`outPathHashes` is the **raw path bytes**. `out_path_len` packs the hop count in its low
six bits and the hash width minus one in its top two (`packages/meshcore/lib/src/model/admin.dart:14-18`),
so the byte list is `hops × width` long. The controller already decodes both numbers and
`DiscoveredNode.hopCount` (`discovered_node.dart:124-125`) is the depth.

Consequence on a mesh that negotiated two- or three-byte hashes: a one-hop peer reports
two or three, so the stop called "≤1 hop" hid peers that were one hop away, "Direct"
excluded direct neighbours, and the stop the tree opens on (`defaultHops`) was picked from
a number two to three times too large.

Fixed to `peer.hopCount`. Counter-factual proved with the new test
`test/meshcore/mesh_graph_hop_count_test.dart`: against the old expression all three of its
cases fail —

```
Expected: true   Actual: <false>     (a one-hop peer included at ≤1)
Expected: true   Actual: <false>     (a two-hop peer included at ≤2)
Expected: <2>    Actual: <4>         (the depth the tree opens on)
```

and with the fix all three pass.

---

## 3. PROVEN BUG — the weather numbers ignored the reader's scale

`weather_view.dart` rendered temperatures three ways at once:

- `_SummaryCard.stat` — `'${c.toStringAsFixed(1)}°'` (`:260`): no unit at all, so `20.0°`
  could be either scale.
- `_ReadingTile` — `'${c.toStringAsFixed(1)}°'` (`:347`): the same.
- `_MicroclimateBubble` — `MmFormat.temperature(...)` (`:673`): correct.

So a reader who chose Fahrenheit saw °F in the microclimate block and an unlabelled
Celsius number in the summary directly below it. Both now go through
`MmFormat.temperature(c, prefs: context.formatPrefs)`, which is the app's one spelling for
it (`lib/util/mm_format.dart:128-136`).

Proved by `test/screens/weather_units_test.dart`, which emits a real 0x8B telemetry frame
(CayenneLPP 0x67, 20.0 °C) and asserts `20 °C` for a Celsius reader and `68 °F` — and the
absence of any `°C` or bare `20.0°` — for a Fahrenheit reader. Against the old rendering
both cases fail ("Found 0 widgets with text containing 20 °C" / "68 °F").

Also corrected two comments in `mesh_tree_view.dart` that still described the ladder as
"0..6, default 6".

---

## 4. NEEDS WORK — found, not fixed (outside this task's file scope)

### 4.1 The node sheet reports hops as bytes — user-visible, same root cause as §2

`lib/screens/node_detail_sheet.dart:449-459` renders the "hops" row from
`n.outPathHashes!.length`. On a two-byte-hash mesh a one-hop peer reads
"2 via repeater(s)". **Fix:** `n.hopCount`, exactly as `mesh_graph.dart` now does.
(S) — BUG.

Owned by another child in this fan-out (it is the verbosity/copy child's file), so it is
recorded here rather than edited.

### 4.2 The telemetry poller classifies hops by bytes too

`lib/meshcore/meshcore_controller.dart:4502` `_telemPollTierFor` does
`final int hopCount = hops.length;` and then tiers on it. A three-byte, two-hop peer reads
as six hops and returns `-1` (skipped) — so on a three-byte mesh most peers are never
polled at all, which is also why weather can look empty. **Fix:** `n.hopCount`. (S) — BUG.

`lib/meshcore/meshcore_controller.dart` is being edited by another child while this pass
runs, so this is recorded, not changed.

### 4.3 `MeshGraph.fromController` is O(n²) per rebuild

`topologyHopsFor` (`meshcore_controller.dart:1779-1815`) builds a `byPrefix` map over every
node **on each call**, and `fromController` calls it once per peer. `MeshTreeView.build`
(`mesh_tree_view.dart:370-374`) calls `fromController` on every rebuild, and this screen
rebuilds on every controller notification — every message, every telemetry poll, every
geofence sample. With 400 contacts that is ~160 000 map insertions per rebuild, several
times a second. SUSPECTED contributor to the owner's "periodically stops responding"
report, since the tree is on the same tab as the radar. **Fix (M):** build the prefix map
once per graph build — e.g. `topologyHopsForAll()` returning `Map<String, List<TopologyHop>>`
— or memoise the graph in the view on a signature over (node ids + each node's
`outPathHashes` identity + `maxHops`). Not fixed: the first needs a controller edit owned by
another child, the second risks a stale graph in ways that need a device to confirm.

### 4.4 The weather summary's count and its statistics have different bases

`weather_view.dart:110-117`: `temps` collects only readings that have a `temperatureC`, and
the summary is built whenever `readings` is non-empty, with `count: readings.length`. A node
reporting humidity but no temperature is counted in "N reporting" and absent from
min/avg/max, and nothing says so. (S) — BUG (honesty). **Fix:** count the temperature
reporters in the summary, or state both counts.

### 4.5 Message heat is session-only, and says otherwise

The header says "cooling over the last hour", but `MessageHeatTracker` holds cells in memory
(`message_heat.dart:82-83`); after a relaunch the map is empty despite a slogan that implies
an hour of history. (S) — UNFINISHED. Either persist the cell timestamps in the sealed store
(the app already persists positions, places and fences that way), or say "this session" in
the header.

### 4.6 The altitude view is a landmark HUD by design

Its own doc says it is not meant to be useful. Most peers land in the `?` band until each is
polled (`elevation_profile_view.dart:17-20`), and the on-screen line does not say that. (S) —
UNFINISHED/DECISION. Either keep it as the toy it is and say so on screen, or fold the
altitude row it duplicates into the node sheet.

### 4.7 Weather only reads the active channel

`_scanObservations` scans `mc.messagesFor(mc.activeChannel)` and the microclimates are
`mc.microclimatesFor(mc.activeChannel)`. A reader on channel 0 sees no weather from channel 2.
The strip does name the channel it read (`channelLabel: mc.activeChannelName`), which is the
honest minimum; whether the view should span channels is a product decision. (S) — DECISION.

---

## 5. What was verified

```
flutter analyze                      → No issues found!
flutter test test/meshcore/mesh_graph_hop_count_test.dart   → 3 passed
flutter test test/screens/weather_units_test.dart           → 2 passed
flutter test                         → see the commit message (full suite)
```

Counter-factuals were run by temporarily restoring the old expressions and re-running the
new tests; both fixes are load-bearing (outputs quoted in §2 and §3).
