# Missing work — the register

Everything in this app that is **not properly implemented**, in one place, with the
evidence for each row and a size. Sibling of `STATUS.md` (what was done) and of
`meshmore-feature-register.md` (what was decided).

Rules for this file:

- **Every row has evidence** — a `file:line`, a command that was run, or a named
  register row. A row without evidence does not belong here.
- **BUG** means the code does something wrong. **UNFINISHED** means the code does what
  it says and the feature is not complete. **DECIDED** means it was deliberately not
  built; it is listed so nobody re-litigates it by accident.
- Sizes are the work, not the importance: **S** is an afternoon, **M** is a day or two,
  **L** is a wave with its own tests.
- Five audits were running in parallel when this was written (verbosity, messaging,
  instruments, media, map). Their findings are **not** folded in here yet; this is the
  standing list, and it should be merged with theirs rather than replaced.

---

## 0. Merged audit findings (2026-11-14)

The three audits that finished (`notes/instrument-modes-audit.md`,
`notes/media-audit.md`, and the messaging pass folded into the commits) are merged here.
What they found and what happened to it:

| finding | evidence | resolution |
|---|---|---|
| **The tree collapses to a circle when most peers are one hop or unresolved.** Not a layout bug: the view is force-directed, and depth comes from the route the radio advertises, so a mesh where every route is unlearned is a ring — which is what the owner saw. | `lib/screens/mesh_tree_view.dart:20-29`; `lib/meshcore/mesh_radial_layout.dart:8-30` | **Partly fixed.** Since `topology_hop.dart` keeps a hop that names nothing, a route through an unknown repeater now draws at its real depth. A peer whose route the radio never learned (flood or advert-only) still floats on the `?` ring, because no layout can invent a depth. |
| **The hop filter counted path bytes, not hops** — a three-byte, two-hop peer read as six and was skipped by the poller, which is also why weather could look empty. | `lib/meshcore/mesh_graph.dart` (fixed) | **Fixed**, with three cases in `test/meshcore/mesh_graph_hop_count_test.dart`. |
| **`MeshGraph.fromController` is O(n²) per rebuild** — the prefix map is rebuilt per peer, and the tree rebuilds on every controller notification. With 400 contacts that is ~160 000 map insertions several times a second. | `lib/meshcore/meshcore_controller.dart:1779-1815`; `lib/screens/mesh_tree_view.dart:370-374` | **Open.** Plausible contributor to "periodically stops responding". Fix is memoising the graph on a signature; not done because it needs a device to confirm freshness. |
| **The weather summary counts a different set than it averages** — a node with humidity and no temperature is counted in "N reporting" and absent from min/avg/max. | `lib/screens/weather_view.dart:110-117` | **Open** (S, honesty). |
| **A received photo was reassembled and dropped** — nothing claimed an image. | `lib/media/media_inbox.dart` completed payloads, no consumer | **Fixed**: `lib/media/photo_inbox.dart` + `received_photos_sheet.dart`. |
| **A DM refused by the airtime meter said only "send failed".** | `lib/meshcore/meshcore_controller.dart` | **Fixed**: names the budget as the cause. |
| **A write that threw was marked "not sent".** The bytes may have reached the radio's buffer. | same | **Fixed**: uncertain, not failed. |
| **Inbound rows were stamped with arrival time**, so a radio's queued backlog drained looking like it arrived in one second. | same | **Fixed**, with a window that only trusts a believable sender clock. |
| **`send` and `scanStart` were in all eleven packs and played by nothing.** | `rg -n "CueKind.send" lib/` was empty | **Fixed**, with `test/cue/cue_coverage_test.dart` failing if a cue ever becomes unreachable again. |
| **The periodic "crashes" are ANRs, not crashes.** `dumpsys dropbox` holds three `data_app_anr` entries for this package and six `data_app_crash` entries belonging to `io.ldmux.mobile`. Two traces: the main thread executing Dart for five seconds, and a broadcast to `RadioLeaseReceiver` overrunning its window. | device `dumpsys dropbox`, 2026-11-13 | **Instrumented and partly fixed**: `AppErrors` now persists to prefs and is shown in the developer console; the GeoJSON parse and the city gazetteer moved off the UI isolate; the receiver answers on a four-second timeout. The remaining attribution needs the new error rows read after the next freeze. |

Also outstanding from this stretch, and honest to record: the **verbosity, map and Bluetooth
audit children were killed by their own time limit** before writing their notes. Their code
changes are committed (copy shortened, basemap fallback, lifecycle test) but their reasoning
is not, so those three audits owe a write-up rather than being considered complete.


---

## 1. Ranked table

| id | area | what is missing | evidence | size | type |
|----|------|-----------------|----------|------|------|
| R-01 | radio | **The CLI surface covers two commands.** `runRadioCli` is wired for buzzer and vibration only, because the whitelist is those two; a repeater's own console (the `0x42` path the codec can build) is not reachable. | `lib/meshcore/meshcore_controller.dart:5562`; whitelist `meshmore_sns_app/packages/meshcore/lib/src/codec/cli_command.dart:49,64`; callers `lib/screens/diagnostics_screen.dart:100,104,121` | M | UNFINISHED |
| R-02 | radio | **Multi-radio switch surface.** One session exists; there is no picker, and no rule for an in-flight send at switch time. | `meshmore-feature-register.md:334` | M | UNFINISHED |
| R-03 | radio | **Firmware OTA install.** The page reads the gate and shows versions; no transfer starts, because an install drains the radio's offline queue and nothing can re-sync it. | `lib/screens/firmware_screen.dart`; `meshmore-feature-register.md:48` | L | DECIDED |
| R-04 | radio | **Resume after a phone restart.** `autoRunOnBoot` is false and no boot receiver is registered, so nothing arrives until the app is opened. | `meshmore-feature-register.md:211` | M | DECIDED |
| R-05 | radio | **Background location publication.** Auto-publish uses the phone fix only while the app is open; the service is `connectedDevice`, not `location`. | `meshmore-feature-register.md:210` | M | DECIDED |
| U-01 | UI | **Landscape and tablet.** Every view is portrait-locked, so a tablet, an unfolded foldable or a landscape mount gets a narrow column. | `lib/main.dart:123`; `meshmore-feature-register.md:209` | L | DECIDED |
| U-02 | UI | **`MmEdgeSwipe` is mounted nowhere.** It was written for the map, whose pan/zoom locks the shell pager, so the map has no swipe exit at all. | `lib/ui/mm_edge_swipe.dart:47`; `rg -n "MmEdgeSwipe" lib/` finds only the file | S | UNFINISHED |
| U-04 | UI | **A drawn fence cannot be reshaped.** Rename only; the sheet says so on screen. | `lib/l10n/app_en.arb:3475` (`geofencePolygonNote`) | M | UNFINISHED |
| U-05 | UI | **A place cannot be imported.** Sharing writes a human link; nothing parses it back. | `lib/places/place_ui.dart:86` (`placeShareText`), used at `place_detail_sheet.dart:342`; no parser | S | UNFINISHED |
| T-01 | tools | **The tools keep no history.** Six tools, no store: a range test's rows live in memory and leave as a CSV the reader must paste somewhere. | `lib/tools/` has no `Prefs`/`Store` reference (`rg -n "Prefs\|Store" lib/tools/` is empty); `lib/tools/range_test_tool.dart:195` is the only export | M | UNFINISHED |
| A-01 | a11y | **Angular floors are unasserted.** The 320 dp / 200 % floors are tested; the Latin 1.2°, kana 1.5°, kanji 1.8° distance thresholds are not. | `meshmore-feature-register.md:214` | S | UNFINISHED |
| A-02 | a11y | **Icon-only controls inside screens are not all labelled.** The shell's strip cells are; the screens' own are the W9 tail. | `meshmore-feature-register.md:214` | M | UNFINISHED |
| G-01 | guards | **36 files still carry a bare-`TextButton` baseline** — each is a control that has not moved to `MmAction`/`MmPickerTile`. | `test/ui/tap_affordance_guard_test.dart:31-…` (36 non-zero entries) | M | UNFINISHED |
| G-02 | guards | **23 files carry an off-ladder spacing baseline.** | `test/ui/mm_spacing_test.dart:104-130` | M | UNFINISHED |
| B-01 | build | **No release APK can be built from this checkout.** `android/key.properties` is absent, and the Gradle config refuses to sign a release with the debug key. `flutter build apk --profile` works and is what the handset runs. | `android/app/build.gradle` (the signing gate); `flutter build apk --release` → "Release signing needs android/key.properties" | S | DECIDED |
| G-03 | guards | **19 files carry a literal-size/colour/radius baseline.** | `test/theme/mm_ratchet_test.dart:57-93` | M | UNFINISHED |
| E-01 | instruments | **The elevation profile is exploratory by its own doc comment** — peers are placed by reported altitude, and phone-GPS altitude is a last-resort fallback. | `lib/screens/elevation_profile_view.dart:18` | S | UNFINISHED |
| M-01 | media | **Media is app-to-app only.** The ecosystem has no interoperable image standard, so a chunked picture is understood by this app and no other client. | `meshmore-feature-register.md` R167 row | L | DECIDED |
| P-01 | protocol | **Three encoders are unexercised** by any test (`getAllowedRepeatFreq`, `getDefaultFloodScope`, `removeContact`) — though the register also claims the first is wired, so this row needs re-measuring before it is trusted. | `meshmore-feature-register.md:51` vs `:93` | S | SUSPECTED |

---

## 2. By area

### Messaging

No gap found by inspection that is not already covered by a test; the parallel
messaging audit is the authority on this area and its findings should replace this
paragraph. What is known from the code:

- Channel and DM rows are capped at 250 per channel (`lib/meshcore/chat_store.dart:45`),
  oldest dropped first, and the drop is counted and shown.
- The store is sealed and debounced at 400 ms (`meshcore_controller.dart:517`), so a
  burst collapses into one write.

### Media

- **M-01** above: no interop with other clients, by decision.
- The public channel hides the microphone and the photo control, with one line saying
  where they live (`meshmore-feature-register.md` R167).

### Map

- The overlay count is still higher than it needs to be (pins, rings, cells, trail,
  fences, event layers) — `meshmore-feature-register.md` R167's closing note.
- The parallel map audit is the authority on tiles, camera, overlays and cost.

### Instruments

- **E-01** elevation profile.
- Tree mode's hop filter and weather mode's staleness are being audited in parallel;
  their findings belong here.

### Settings and IA

- No open item found by inspection beyond the guard baselines (G-01…G-03), which are
  the mechanical tail of the same work.

### Themes and sound

- Closed this pass: eleven presets, eleven synthesised packs, 209 files, no borrowing
  (`lib/theme/mm_tokens.dart` `audioPackKey`, `brand/_audio_pack.py`).

### Accessibility

- **A-01**, **A-02**.

### Data and storage

- Every store states its own size and there is one delete that names what goes and what
  survives (`meshmore-feature-register.md:330`). No open item found.

### Radio protocol

- **R-01** … **R-05**, **P-01**.

### Tests and guards

- **G-01**, **G-02**, **G-03**: the three ratchets are honest about what is left, and
  their non-zero baselines are the list of un-migrated UI.

---

## 3. Known good — proved, with the test that proves it

| what | test |
|------|------|
| Every preset has its own sound pack, 19 cues each | `test/theme/theme_integration_test.dart`, `test/cue/asset_audio_pack_test.dart` |
| Every preset's body text is ≥ 4.5:1 on its ground | `test/theme/theme_integration_test.dart` |
| Every route survives 320 dp at 200 % text | `test/screens/a11y_floors_test.dart` |
| The bottom edge is handled on every screen | `test/ui/bottom_inset_test.dart`, `test/ui/mm_scroll_edge_test.dart` |
| The hex field is anchored to the ground and drawn at its own scale | `test/maps/hex_field_test.dart` |
| A polygon fence contains what it should, including a horseshoe notch | `test/geofence/geofence_polygon_test.dart` |
| A fence crossing is heard, once per stay, and survives a restart | `test/geofence/geofence_controller_test.dart` |
| The map's own display choices survive a relaunch | `test/maps/map_overlay_prefs_test.dart`, `test/screens/map_overlay_persistence_test.dart` |
| The camera ladder prefers a fresh view over a stale fix | `test/maps/map_view_state_test.dart`, `test/screens/map_view_restore_test.dart` |
| A channel is created with a name-derived key, never the public key by default | `test/screens/channel_create_sheet_test.dart` |
| The app's own errors survive the process and are readable | `test/app/app_errors_persistence_test.dart`, `test/screens/diagnostics_errors_section_test.dart` |
| A GeoJSON layer is parsed off the UI isolate | `test/maps/maps_test.dart` (behaviour), `lib/maps/maps_controller.dart:1456` (the `Isolate.run`) |
| The launch screen is one design in every theme | `test/shell/launch_surface_test.dart` |
| The mesh tree keeps the depth the radio reported | `test/meshcore/mesh_radial_layout_test.dart` (the layout and the hop rings), `test/meshcore/meshcore_controller_test.dart` (`topologyHopsFor`: an unresolved hop keeps its place, the width is the radio's) |
| Units, clock and temperature follow the reader's choice | `test/util/mm_format_test.dart` |

---

## 8. Hardware state (2026-11-14)

Both radios were plugged in and identified, and nothing was flashed.

| unit | enumerated as | current firmware | asked for |
|---|---|---|---|
| Heltec WiFi LoRa 32 V4 (ESP32-S3, 16 MB flash) | `303a:1001` Espressif USB JTAG/serial, `/dev/ttyACM0`, serial `F8:5B:1B:BE:C5:3C` | MeshCore 1.17.1 **repeater**, node name `HELTEC-REP` | reflash as **`h0`** |
| Seeed Wio Tracker L1 Pro (nRF52840) | `2886:1667` Seeed Wio Tracker L1, `/dev/ttyACM1`, serial `6A6D57BFADA2FDA2` | MeshCore 1.17.1 **companion**, node name `WIO` | reflash as **`m0`** |

Evidence: `lsusb`, `udevadm info`, and `~/Documents/lora/INVENTORY.md` (which also records
the flash history and the Meshtastic environment names for both boards).

**Not done, and why:** the request named them "h1, and m0 (m0 for the wio, h0 for the
heltec)", which is two different names for the Heltec; and a reflash rewrites what every
other radio on the mesh sees, so the name and the role have to be confirmed first rather
than guessed. Flashing also needs a decision this register cannot make: whether the Wio
stays a companion (the app talks to it) and the Heltec stays a repeater, or both become
companions for testing.

---

## 9. Notifications with the app closed — audit (2026-11-14)

The question: do notifications arrive when the app is closed or sitting in the background
behind the persistent notification? What the code says, and what is left to prove on a
device.

**What exists (proven by reading):**

| piece | where | state |
|---|---|---|
| `POST_NOTIFICATIONS` permission | `AndroidManifest.xml:52`; requested once at notifier init `local_notifier.dart:211` | present; a denial is non-fatal and Settings says what will not appear |
| Notification channels | `local_notifier.dart:195-207`, importance high, one per class | present; a deleted or quieted channel is reported as `NotifierHealth.missingChannel` / `quiet` and shown as a row in App settings |
| Foreground service | `AndroidManifest.xml:128-130`, type `connectedDevice` | declared; started when the link reaches ready and the setting is on (`meshcore_controller.dart:204`) |
| Keep-alive state in the UI | `app_settings_screen.dart:206-220` | three states shown: off / failed / on |
| Where delivery happens | `NotificationService` posts from the **main isolate**; the service handler is deliberately empty (`background_keepalive.dart:56-64`) | by design: the service keeps the *process* alive so the main isolate keeps draining the radio |

**The three ways "no notifications" happens, and whether each is a defect:**

1. **After a phone reboot, nothing runs until the app is opened.** `autoRunOnBoot: false`
   (`background_keepalive.dart:75`). This is a recorded decision, not an oversight — register
   row R-04. Changing it means starting a foreground service from `BOOT_COMPLETED`, which
   Android 15+ restricts per service type; it is a decision with a platform risk attached.
2. **The OEM kills the service anyway.** Motorola/Android 16 battery management can stop a
   foreground service that is not on the battery-optimisation exemption list. **Not
   proven either way on this handset** — it needs the app running with the screen off for an
   hour and a message sent to it. The app cannot currently *show* the exemption state, which
   is the one piece of this that would be worth adding: `PowerManager.isIgnoringBattery
   Optimizations` is one platform call and would turn "I get no notifications" into a row
   saying why.
3. **The process is swept away (task removed).** No `android:stopWithTask` override, so the
   default applies; whether `flutter_foreground_task` stops the service on task removal
   depends on its own `onTaskRemoved`. **Unverified**, and the same device test would settle
   it.

**The device test that settles 2 and 3** (one sitting): turn the screen off, leave the app in
the background, send a channel message from another node after five minutes and after thirty,
and record whether a notification appears and whether `dumpsys activity services` still lists
`com.pravera.flutter_foreground_task.service.ForegroundService`. If the service is gone, the
exemption row is the fix; if it is running and the message is not delivered, the fault is in
the drain, not the service.
