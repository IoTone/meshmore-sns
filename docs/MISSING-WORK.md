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
- The audits of 2026-11-14 (instruments, media, airtime, bottom edge, messaging) are folded
  into §0. A later audit that is not merged here is named in its own row rather than left
  implied.

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

## 1. Ranked table (rewritten 2026-11-15)

Every row that was open on 2026-11-14 has been re-measured against the tree. The
rows below are what is still open, and the closures are recorded in §12 with
their evidence so a row that says "built" can be checked rather than trusted.

| id | area | what is missing | evidence | size | type |
|----|------|-----------------|----------|------|------|
| N-01 | notifications | **Task removal is the one delivery case left.** Closed-app delivery is measured: a real channel message notified at 22 minutes of a screen-off background on 2026-11-16, and the foreground service was still listed at the 30-minute mark. What is not measured is the app swiped out of the recents list, because that needs its own sitting. | `docs/MISSING-WORK.md` §9, the 2026-11-16 run | S | UNFINISHED |
| N-02 | notifications | **Measured: the app runs optimised on this handset.** `dumpsys deviceidle whitelist` has no entry for the package, and the App settings row says so. Whether that stops delivery is answered by N-01's run (it did not, at 22 minutes), so the row is informational until an OEM does stop it. | `docs/MISSING-WORK.md` §9; `lib/perms/battery_exemption.dart` | S | CLOSED (measured) |
| R-06 | radio | **A radio rename does not survive a power cycle** on the paired Wio (1.17.1). The write lands and reads back in the same session, then the name reverts. This is the firmware's own prefs write, not the app's encode. | `docs/MISSING-WORK.md` §10; firmware `examples/companion_radio/MyMesh.cpp:1219-1225` | — | DECIDED (firmware) |
| R-07 | radio | **Firmware OTA install.** The page reads the gate and shows versions; no transfer starts, because an install drains the radio's offline queue and nothing can re-sync it. | `lib/screens/firmware_screen.dart`; register row | L | DECIDED |
| R-08 | radio | **Resume after a phone restart.** `autoRunOnBoot` is false and no boot receiver is registered, so nothing arrives until the app is opened. Android 15+ restricts starting a foreground service from `BOOT_COMPLETED`. | `background_keepalive.dart:75` | M | DECIDED |
| R-09 | radio | **Background location publication.** Auto-publish uses the phone fix only while the app is open; the service is `connectedDevice`, not `location`. | register row 210 | M | DECIDED |
| M-01 | media | **Media is app-to-app only.** The ecosystem has no interoperable image standard, so a chunked picture is understood by this app and no other client. | register R167 row | L | DECIDED |
| M-02 | media | **AEIC: the installer is built, the port is not.** Five files, MIT, published at `huggingface.co/zjs81/aeic-se-onnx` (three ONNX graphs, the decoder's 832 MB `.onnx.data`, the 305 MB of entropy models and the rANS CDF table; 957 MiB total). `lib/media/aeic_installer.dart` downloads them resumably, verifies each against its published SHA-256, attempts one repair per bad file and deletes them on request; `Settings → Chat & media` shows the state, the percentage and the licence. What remains is the codec itself: about 4000 lines of ONNX session management, a rANS coder with these CDF tables, a worker isolate and a memory-pressure policy, plus a `flutter_onnxruntime` (or ORT-via-FFI) dependency. The decode peak is 2.16 GiB and this handset had 2.4 GB free, so the policy is part of the work rather than an optimisation. `kAeicEncodeAvailable` is false until then, and the settings row says "not in this build yet" instead of offering the mode. | register "Media: what the other clients do, and the AEIC decision"; `lib/media/aeic_installer.dart`, `lib/media/media_mode.dart`, `test/media/aeic_installer_test.dart` | XL | DECIDED, INSTALLER DONE |
| B-01 | build | **No release APK can be built from this checkout.** `android/key.properties` is absent and the Gradle config refuses to sign a release with the debug key. `flutter build apk --profile` works and is what the handset runs. | `android/app/build.gradle` (the signing gate) | S | DECIDED |
| U-01 | UI | **Landscape and tablet.** Every view is portrait-locked, so a tablet, an unfolded foldable or a landscape mount gets a narrow column. | `lib/main.dart`; register row 209 | L | DECIDED |

Closed on 2026-11-15, with the evidence in §12: U-02, U-04, U-05, T-01, A-01,
A-02, E-01, P-01, the weather summary count, the block-at-send defect, the
multi-radio switch surface, the fence OS notification, the battery-exemption
row, the place destination channel and the `MeshGraph` rebuild cost.

## 2. By area (rewritten 2026-11-15)

### Messaging

- **Fixed 2026-11-15: a blocked key could still be messaged.** `BlockStore` was read
  by every display surface and by nothing on the way out, so the thread a block was
  meant to close could be replied to. The send path now asks
  (`MeshcoreController.isPeerBlocked`), refuses a direct message to a blocked key
  before a row is written, refuses a *retry* of a row addressed to a key blocked
  since, and lets the SOS path through with the same precedence an SOS already has
  over a muted channel. The composer states the rule and the copy says what a block
  cannot stop: the MeshCore radio still relays the packet.
  Test: `test/meshcore/block_send_test.dart`.

### Media

- **M-01** and **M-02** above. Nothing else open.

### Map

- No open item. The overlay count is the register's closing note, not a defect.

### Instruments

- No open item. The weather band now counts the nodes its own three figures come
  from (`WeatherTemperatureSummary`), and the altitude chart states where each
  height came from instead of calling itself exploratory.

### Settings and IA

- No open item.

### Themes and sound

- No open item.

### Accessibility

- **A-01 is not a phone-app rule and is closed as such.** The Latin 1.2°, kana 1.5°
  and kanji 1.8° floors are visual-angle thresholds, and a visual angle needs a
  stated viewing distance. They belong to the XR work (`meshmore-xr/`,
  `MeshmoreXR-i18n-ja.md`), which is out of scope for this repository. The phone app
  has no such rule to assert, and inventing a distance to make it assertable would
  be a number nobody measured.
- **A-02 is closed.** Every `IconButton` in `lib/` carries a tooltip and every
  icon-only `InkWell`/`GestureDetector` in `lib/screens/` carries a label or a
  `Semantics` node (measured 2026-11-15 over the whole tree, zero hits).

### Data and storage

- No open item.

### Radio protocol

- No open item besides R-06 to R-09, which are decided.

### Tests and guards

- The three ratchets are the mechanical tail and are being worked down rather than
  added to; their non-zero baselines are the list of un-migrated UI.

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

**Code defects found on 2026-11-14 and fixed** (`6feb9a69`): the keep-alive was started once
per ready edge with no retry, so one refusal left the session unprotected
(`meshcore_controller.dart:465` is the watchdog now); the catch-up digest reused one id with
`onlyAlertOnce`, so every burst after the first was silent (`local_notifier.dart:293` clears
it); a reconnect was treated as a backlog even when the link had only blinked
(`notification_service.dart:304`); and the open-thread suppression read a cached foreground
flag that a missed lifecycle event could leave true (`notification_focus.dart`). What is left
here is the platform question, not the app's.

**Run on 2026-11-15, and what it settled.** The phone was attached and the app
linked to the radio. `dumpsys activity services` showed
`com.pravera.flutter_foreground_task.service.ForegroundService` with
`isForeground=true` and the `mm_keepalive` notification, so **question 1 is
answered: the service does start on a fresh link.** The app was then sent to the
background and the screen turned off at 07:26:55 UTC. Eight minutes later the
notification list held the same 19 entries it held before, with no new message
notification. That is not yet a result: whether any channel traffic arrived in
those eight minutes is unproven, because the device locked and the check needs
the owner's PIN to read the thread. The test therefore stops at the lock screen
and the remaining steps are the owner's.

**The device test that settles 2 and 3** (one sitting): turn the screen off, leave the app in
the background, send a channel message from another node after five minutes and after thirty,
and record whether a notification appears and whether `dumpsys activity services` still lists
`com.pravera.flutter_foreground_task.service.ForegroundService`. If the service is gone, the
exemption row is the fix; if it is running and the message is not delivered, the fault is in
the drain, not the service.

**Run on 2026-11-16, and what it settled.** Baseline at 13:43:06 UTC on build 1.0.198, linked to
the Wio on 1.17.1: one notification (`mm_keepalive`, id 4403), `ForegroundService isForeground=true`
in `dumpsys activity services`, and `GeolocatorLocationService` beside it. The phone was sent
home and the screen turned off at 13:43:14, and the screen was off for the whole window
(`mWakefulness=Dozing` before and after each check; it woke once at 13:54 and was put back).

- `dumpsys deviceidle whitelist` has **no entry** for `com.iotone.meshmore_sns_app`: this
  handset runs the app optimised, which is the precondition for an OEM stopping the foreground
  service. The App settings row reports exactly that state, so N-02's cause is now named on
  the handset rather than inferred.
- At 22 minutes (14:05:57) a **real channel message arrived and notified**: a group summary on
  `mm_messages_channel` reading `1 message · RichardWB5YOE: @[Half Live] ack, 5 hops to SE
  Aurora`, plus its own message record (`id=584208371`, `category=msg`, `AUTO_CANCEL`), with
  the keepalive still in place and the service still listed.
- At the 30-minute mark (14:13:51) the picture was unchanged: `ForegroundService` still listed,
  the keepalive and both `mm_messages_channel` records still there, `mWakefulness=Dozing`
  throughout. The service and the drain therefore survive a full half hour of a screen-off
  background, so the platform did not stop it and question 2 is answered for this handset in
  this configuration. Question 3 (task removal) is unchanged: it needs the app swiped out of
  the recents list, which is a separate sitting.
- Not exercised: the 5-minute mark with an inbound message, because no traffic arrived in the
  first five minutes. The 22-minute delivery covers the same path at a longer interval.

---

## 10. What the 2026-11-14 device session did, and what it could not finish

The phone was attached (`ZD222W34LJ`), one radio at a time was enumerable, and the app was walked on the handset
rather than reasoned about.

| Step | Result |
| --- | --- |
| Rename the connected radio to `m0` | Done in Device configuration, read back as `m0` on a fresh screen entry. **It reverted to `WIOld` after the radio power-cycled**, which matches the firmware's own path: the write lands in `_prefs.node_name` and calls `savePrefs()` (`examples/companion_radio/MyMesh.cpp:1219-1225`), and it reads back correctly in the same session. Whether the Wio's NVS write failed or the firmware's prefs write does not cover the name is not settled |
| Flash the Heltec as a BLE companion | Done: `heltec_v4_companion_radio_ble` from `~/Documents/meshcore-fw-alerts` (upstream `meshcore-dev/MeshCore`, detached at `685a869`), build 39 s, upload 33 s, and the host BLE scan sees `MeshCore-HELTEC-BASE` advertising at `F8:5B:1B:BE:C5:3D`. The node name survived from the earlier flash and is still one field from `h0` |
| Notification with the app closed, 5 and 30 minutes | **Not run.** The steps stayed in §9. Two facts were established on the way: `Stay connected in background` is on, and at 10:46 the app was running with no `ForegroundService` record in `dumpsys activity services`, so the test's first question is whether the service starts on a fresh link |
| Sound | Investigated as a defect report ("the themes have no sound") and it was the files, not the wiring: 30-150 ms cues peaking at -10 to -15 dBFS, inaudible at a media volume of 3/15. Regenerated to a perception floor per cue and a -1.5 dBFS peak, played as sonification without audio focus, at a new persisted `cueVolume`. Recorded in the register §11 |
| Device configuration UX | Rebuilt on `MmAction.primary` and `MmActionRow`, one family and one placement, with the advert policy staged and sent with the coordinates. Recorded in the register §11 |

---

## 11. The second 2026-11-14 pass

Four reports, four defects, each traced to a line before anything was changed.

| Report | What was wrong | Where it is fixed |
| --- | --- | --- |
| "The themes have no sound" | The files, not the wiring: 30-150 ms cues peaking at -10 to -15 dBFS, inaudible at a media volume of 3/15 | `brand/_audio_pack.py` floors and peak target, all 209 files regenerated, `test/cue/cue_pack_loudness_test.dart` |
| "Set name and Set advert location are weirdly placed" | Four button families and three placements in one scroll view, two enabled policies, two commit models in one section | `MmAction.primary` and `MmActionRow`, `test/screens/device_config_actions_test.dart`, `test/ui/action_family_guard_test.dart` |
| "The wave is like one FPS" | The heat view repainted once a second, and its CRT sweep and toast fades were advanced in one-second steps | `lib/screens/sns_cells_view.dart` frame clock with the heat maps cached at one hertz |
| "I never get notifications" | The keep-alive started once with no retry, the digest silenced every burst after the first, a flap counted as a backlog, and the open-thread check read a stale flag | `meshcore_controller.dart:465`, `local_notifier.dart:293`, `notification_service.dart:304`, `notification_focus.dart` |

Also in this pass: the map's basemap folded into the Layers sheet, the compass line moved under
the header and gated to the views that draw a bearing, pause stopping the sweep, the
quarter-turn click using `lightImpact`, the grid remembering its view and legend across a
restart, a geofence's inside state persisted so a launch inside a fence does not fire an entry,
and confirmations on fence delete and log clear.

Still open, with what would close each:

| Item | What closes it |
| --- | --- |
| The 5 and 30 minute screen-off notification test | The device steps in §9. The app-side defects are fixed, so this now measures the platform |
| Rename the Heltec to `h0` | One field in Device configuration with the app pointed at that radio |
| Duty-cycle cutoff toggle and the time left in the hour | A switch and a line over `MeshcoreController.airtimeRemaining` (`meshcore_controller.dart:1323`) |
| Geofence cue and OS notification | `CueKind.geofenceEnter`/`geofenceExit` with their assets, and a notification class for a crossing (`meshmore-sns-geofence-tracking.md:110-116`) |
| A place's destination channel | A channel field on `Place` and a line in the create sheet naming the slot the report will use |
| Radio rename across a power cycle | A firmware answer: whether the Wio's NVS write or the firmware's prefs write drops the name |
| A blocked peer can still be messaged | `BlockStore` is read by the UI only (`lib/chat/block_actions.dart:28`, `chat_actions.dart:176`), never by the send path in `meshcore_controller.dart`. The decision the execution plan calls "block vs queue at send time" is still open, so the composer neither refuses nor warns |

---

## 12. The 2026-11-15 pass — what closed, and how to check it

Every row below was open in §1 on 2026-11-14. Each one names the code and the test
that now holds it, so "built" is checkable rather than asserted.

| Row | What closed it | Evidence |
|---|---|---|
| **Blocked peer could still be messaged** | The send path asks the block store. A direct message to a blocked key is refused before a row is written, a retry of a row addressed to a key blocked since is refused, and the SOS path keeps its precedence. The composer states the rule and the copy says the radio still relays. | `lib/meshcore/meshcore_controller.dart` (`isPeerBlocked`), `lib/screens/dm_screen.dart`; `test/meshcore/block_send_test.dart` |
| **Multi-radio switch surface** (register D8.9) | `switchRadio` plus a "Paired radios" list on the connect screen, which the link chip already routes to. A switch is refused while a send is unanswered, because an answer belongs to the link it arrived on. A phone with one radio shows no picker. | `lib/meshcore/radio_switch.dart`, `lib/screens/connect_screen.dart`; `test/meshcore/radio_switch_test.dart`, `test/screens/connect_screen_radio_switch_test.dart` |
| **`MeshGraph.fromController` was O(n²) per rebuild** | The repeater prefix map is cached per route width and invalidated by a revision bumped at every `_nodes` mutation, and the graph is memoised on a signature covering exactly what the build reads (`lastHeardUnix` deliberately excluded, entries sorted so recency cannot reorder it). | `lib/meshcore/mesh_graph.dart`, `meshcore_controller.dart`; `test/meshcore/mesh_graph_memo_test.dart` |
| **P-01, three unexercised encoders** | `getAllowedRepeatFreq`, `getDefaultFloodScope` and `removeContact` are asserted against the firmware's own request bytes, and the gap list is empty. The register's two contradicting rows resolve in favour of the code: the encoders exist and are now exercised. | `packages/meshcore/test/network_shaping_test.dart` |
| **Weather summary counted a different set than it averaged** | `WeatherTemperatureSummary` is the one set: the count is the nodes the three figures come from, and a node reporting humidity or pressure only is named on the line below instead of being folded into the count. | `lib/screens/weather_view.dart`; `test/screens/weather_summary_count_test.dart` |
| **E-01, the elevation profile was "exploratory by its own doc comment"** | The doc comment now states what the chart does and where each height comes from, and the chart says it on screen: each height is that node's own telemetry, ours is the phone's GPS. The header stopped reading "MESHMORE :: FUJIさん" in the English bundle. | `lib/screens/elevation_profile_view.dart`; `test/screens/grid_view_controls_test.dart` |
| **U-02, `MmEdgeSwipe` mounted nowhere** | Closed by deletion, not by mounting. The owner's ruling of 2026-11-11 is that a drag starting near an edge is a pan, so the bands are gone; the widget, its test and its spacing baseline entry went with them. | `git show fcd7377a` (the ruling); `lib/shell/home_shell.dart` |
| **U-04, a drawn fence could not be reshaped** | The fence sheet offers "Reshape on the map" for a polygon, which hands the reader to the map with the corners loaded and draggable. Saving replaces the corners and keeps the id, the name and the crossing log. | `lib/geofence/geofence_controller.dart` (`updatePolygon`), `lib/screens/street_map_view.dart` (`_beginReshape`); `test/geofence/geofence_controller_test.dart`, `test/geofence/geofence_create_sheet_test.dart` |
| **U-05, a place could not be imported** | The reverse of `placeShareText` parses a shared place, validates the coordinate range and the id, and opens the create sheet prefilled, refusing with a named reason rather than importing nonsense. | `lib/places/place_import.dart`, `place_import_sheet.dart`; `test/places/place_import_test.dart` |
| **Place destination channel** | A place report has a destination: a channel picker on the create sheet defaulting to the remembered slot and then the active one, the choice persisted, the send going to that slot, and the sheet saying which channel it went to. | `lib/places/place_channel_pref.dart`, `place_create_sheet.dart`, `place_sender.dart`; `test/places/place_channel_test.dart` |
| **T-01, the tools kept no history** | A finished run is kept with its one-line summary and its own CSV, in the sealed store, bounded to 40 runs and 96 KB of tables, with both bounds stated on screen and a dropped table named on its row. | `lib/tools/tool_history.dart`, `lib/screens/tools/tool_history_screen.dart`; `test/tools/tool_history_test.dart`, `test/tools/tools_test.dart` |
| **Geofence OS notification** | A crossing posts its own notification class on its own OS channel, titled by direction and naming the fence, deduped per fence, and kept out of the message group so the "N messages" summary never counts one. The body says a crossing is only noticed when a position fix arrives. | `lib/notifications/message_notification.dart`, `notification_service.dart`, `lib/main.dart`; `test/notifications/geofence_notification_test.dart` |
| **The app could not show why a backgrounded link stops** | App settings reads `PowerManager.isIgnoringBatteryOptimizations` through the plugin the keep-alive already depends on, and offers the one-tap request when the app is still optimised. | `lib/perms/battery_exemption.dart`, `lib/screens/app_settings_screen.dart`; `test/screens/app_settings_battery_exemption_test.dart` |
| **A-01, angular floors** | Closed as not applicable: a visual-angle floor needs a stated viewing distance, and the rule belongs to the XR work, which is out of scope for this repository. | `meshmore-xr/MeshmoreXR-i18n-ja.md`; §2 above |
| **A-02, icon-only controls inside screens** | Closed by measurement: every `IconButton` in `lib/` carries a tooltip and every icon-only `InkWell`/`GestureDetector` in `lib/screens/` carries a label or a `Semantics` node. | measured 2026-11-15 over the whole tree, zero hits |
| **R-01, the CLI surface covers two commands** | Closed as decided, not built: the typed whitelist is final (D11.11) and the twelve refused commands stay refused. The row was stale against that decision. | `packages/meshcore/lib/src/codec/cli_command.dart`; register D11.11 |

### The review pass, 2026-11-15

An independent review of the wave's 29 commits found six defects and one nit.
All seven are fixed, each with the test that holds it:

| Finding | Fix |
|---|---|
| The reshape sheet asked for a name and threw it away: it opened as a new fence with an empty field, and `updatePolygon` never read the label | The sheet opens with `editing: true` and the fence's own name, and `updatePolygon` takes an optional label. An untouched field keeps the old name (`test/geofence/geofence_controller_test.dart`) |
| A reshape of a fence deleted while its corners were open reported success and played the success cue | `updatePolygon` returns false when the fence is gone, the cue is played only on true, and the map says the fence is gone (`geofenceReshapeGone`) |
| One `_nodes` write skipped the revision bump, so the prefix cache could keep a partial map after the persisted table loaded | `_nodesChanged()` is called there, as the invariant at `meshcore_controller.dart:1934` says it must be |
| `ToolHistoryStore.record` had no in-flight-load guard, so two records before the load finished could each assign `_runs` and drop one | One shared load future (`_loading`), so a record awaits the same read |
| The tree's memo was a static keyed on `identityHashCode` and never cleared, so a dead controller's graph was retained | `MeshGraph.clearCache()` is called from `MeshcoreController.dispose` |
| `PlaceCreateSheet.initialChannelIdx` was dead, and the fallback was not validated against the radio's slots | The message-suggestion line passes it, the caller's slot wins over the remembered one, and every candidate is checked against `mc.channels` |
| The two scan helpers do not handle raw or triple-quoted strings, or `//` inside a row's arguments | Documented as known limits in both files: the failure direction is over-counting, which fails loudly |

### The invisible-state sweep, 2026-11-15

A scan for public getters that nothing in `lib/` or `test/` reads found eleven.
Six were leftovers and are deleted (`airtimeRemaining`, a duplicate of
`airtimeLeft`; `rightControlsBottom`, which existed for the edge bands that were
removed; `persistQueued`, `pendingCount`, `maxBlobBytes`, `addressedTiles`).
Three were state the app kept and no screen showed, which is the same defect as
a received picture nothing claimed, and they are now facts on the Diagnostics
page: commands that timed out, reactions that named a message the window no
longer holds, and the frames the telemetry poller sent. The fourth of that kind
was `MediaFetchService.foreignPictures`, the count of pictures that arrived in
AEIC, and it is now a line in the received-pictures sheet.

### The 2026-11-16 second pass

| What was wrong | What it is now | Where |
|---|---|---|
| The review found Discover and Trace could transmit past the hour's airtime ceiling | `sendAwaitingReply` sends `gated: true`, and a frame that spends no airtime is never refused (a spent budget used to refuse local config writes too) | `lib/tools/mesh_tool.dart`, `meshcore_controller.dart`; `test/meshcore/airtime_send_test.dart`, `airtime_accounting_test.dart` |
| A bot bound to a channel could answer its own replies: the own-key guard cannot fire on a channel (no key on a channel row) and the `[bot]` marker was tested against `Name: [bot] …` | The sender name is compared to our own advertised name, and the loop marker is read from the body after the prefix | `lib/bot/bot_controller.dart`, `bot_bridge.dart`; `test/bot/bot_controller_test.dart` |
| The heat view's recorded backdrop was keyed without the text scale or the label colour, so an accessibility change never reached it | The signature covers `textScale`, `label` and the micro type role | `lib/screens/sns_cells_view.dart` |
| A friendly ack could borrow another channel's RSSI and route | The RF-log capture carries the packet's channel hash and is matched on it, oldest first | `meshcore_controller.dart`; `test/meshcore/friendly_ack_send_test.dart` |
| `CMD_SET_ADVERT_LATLON` was charged as airtime although it only writes a preference | Removed from `isOverTheAir` | `meshcore_controller.dart`; `airtime_accounting_test.dart` |
| A stored movement threshold the current build does not offer (1 m) re-advertised every metre | Validated on load, falling back to interval-only | `lib/meshcore/auto_publish_controller.dart` |
| The map warmed two zoom levels it might never need, ahead of the tiles on screen | Warm-up is the current zoom only; the parents/children fetchers are gone | `lib/screens/street_map_view.dart`, `lib/maps/maps_controller.dart` |
| Hexagons were drawn over ground whose tiles had not arrived | A cell is drawn only where its own tile has been drawn, and the field's box is the viewport (or the nodes' box when none is on screen). No margin | same files; `test/maps/hex_field_test.dart` |
| A node could be counted in a hexagon it was not drawn inside: the assignment rounded each axis independently | The cell is the one with the nearest centre (nine candidates), which is the lattice's own Voronoi rule | `lib/maps/hex_field.dart`; `test/maps/hex_field_test.dart` — *every node lands inside the hexagon it was counted in* |
| SEELE's radar sweep was invisible: its accent is cream, so the 180° hue turn returned cream, and reduce-motion removed the hand entirely | A low-saturation skin takes its alert colour at full saturation, and the hand stays on the dial at a fixed angle when motion is reduced | `lib/theme/viz_palette.dart`, `lib/screens/grid_screen.dart` |
| Reduced motion was only the app's own switch: the platform's "Remove animations" did nothing, ripples and page transitions still animated, the boot dial still spun, the chat still glided and the heat wave still travelled | The platform's flags are mirrored into `ThemeController`, the theme drops ink and page transitions, and every self-driven animation asks one helper | `lib/main.dart`, `lib/theme/theme_controller.dart`, `lib/theme/mm_skin.dart` (`reduceMotionNow`), chat, boot overlay, heat view |
| Vector roads were the brightest thing on the map in every skin | The road ramp starts at the quiet rule colour and reaches a third of the way to the muted text colour at its loudest | `lib/maps/vector_basemap.dart` |
| Check-in was reachable from both Tools and Settings -> Safety | One entry point: Safety | `lib/screens/tools/tools_hub_screen.dart`; `test/screens/tools_screens_test.dart` |
| The channel editor was a tall `AlertDialog` with its actions in the system button slot | A scroll-controlled sheet with a drag handle and one `MmActionRow`, like every other editor | `lib/screens/channels_screen.dart` |
| Channel keys could be derived by shaking the phone | Removed. The generate button uses `Random.secure()`, which is the platform CSPRNG; the accelerometer path and its widget are deleted | `lib/screens/channels_screen.dart`; `lib/cryptokit/dice_roll_entropy.dart` deleted |
| A network could not be edited, could only use a preset's bandwidth/SF/CR, and two could share a name | The editor carries bandwidth, spreading factor, coding rate and transmit power (every value a preset already holds), edits in place keeping members, refuses a duplicate name, and refuses a "private" frequency that overlaps a public preset | `lib/screens/networks_screen.dart`, `lib/meshcore/mesh_network.dart`, `network_detail_screen.dart` |
| 56 English UI strings ran past five words in chrome (buttons, menu rows, subtitles, snackbars) | Trimmed to the fact, with the Japanese following | `lib/l10n/app_en.arb`, `app_ja.arb` |

Measured on the handset, 2026-11-16: a geofence created from the Geofences screen records
"Entered Fence 1/2" in the crossings log and posts its own OS notification; the SEELE dashboard
leads with the numeral and the status slab beneath it, as the original monolith did.

### Still open after this pass

| Item | What closes it |
|---|---|
| Delivery after a **task removal** (swipe out of recents) | Swipe the app out and repeat §9's steps. Closed-app delivery itself is measured (§9, 2026-11-16) |
| AEIC (M-02) | A port of about 4000 lines plus a ~1 GB model bundle. It is the one large piece of work left, and it is a wave of its own rather than a row |
| A release APK | `android/key.properties` with a real keystore |
| Landscape and tablet | A layout wave, decided against for now |
| The radio rename surviving a power cycle | A firmware answer, not an app change |

## 13. The 2026-11-16 pass

Four defects, each one reported from the handset rather than found by a scan, plus the
notification sitting that §9 left open. Every fix names the test that now holds it.

| What the owner saw | What it was | Where it is fixed |
|---|---|---|
| Reacting to the same message with the same emoji sent another line | A reaction is a text line on the air, so a second tap was a second send and every other client counted the reactor once per tap. `reactTo` had no memory of what this app had already sent, and the folded reaction map cannot say who is who, because a channel reaction carries a name and a DM reaction carries nothing | `ChatMessage.ownReactions`, persisted as `or`, checked before any send; the picker marks an emoji this message already has from us. `test/meshcore/chat_reaction_test.dart` — *the same emoji on the same message sends once*, *what this app reacted with is remembered across a restart* |
| The hexagons moved a hair after swiping up to the app switcher and coming back | The cell size came from ground metres under the camera, so metres-per-degree-longitude, a cosine of the box centre's latitude, was part of the lattice frame. Any change to the box rescaled that frame and slid every cell: measured at 1.4769e-4 of longitude, about 13 m, for a hundred-thousandth of a degree of change | The lattice is laid out in Web Mercator metres (`mercatorX/Y/Lon/Lat`, `groundPerProjectionMetre`) and a cell is sized from the zoom alone (`hexRadiusForZoomLevel`). A cell is now a regular hexagon on screen at every latitude. `test/maps/hex_field_test.dart` — *a resize cannot move the lattice* (identical centres and corners, bit for bit), *a hexagon is regular on the screen, at any latitude* (0, 39, 47.61, 60, −33) |
| The message bubbles in the heat view left and arrived at a few frames a second, and the field never moved | The ticker returned for every frame inside the same second, so a toast rising and fading over 3.5 s advanced in one-second steps. There was no motion left to smooth after the CRT sweep was removed, so nothing showed it | The ticker repaints every frame. The backdrop — ground, lattice, heat fills, counts — is recorded into a `ui.Picture` once per signature and drawn as one call, the geometry is computed once per paint for both passes, and the lattice is one path rather than a draw per cell. `test/screens/heat_wave_test.dart` |
| The heat view's hexagons were wider than they were tall | A pointy-top hexagon is `√3/2` as wide as it is tall, and both the column pitch and the hexagon's own half-width used the cell size, so each one sat in a square box: fifteen percent too wide, and row neighbours overlapped | `hexW = hexH · √3/2`, with the row pitch at `3/4` of the height. Same file |

**The wave.** The field carries a band of green light crossing it top to bottom on an 8 s loop:
`heatWaveY(nowMs, height, hexH)` is the whole of the motion, one path is built over the rows the
band crosses, and a vertical gradient with `BlendMode.plus` fades its own edges. On the handset,
two screenshots 0.4 s apart differ across a band of rows, which is what a frame-rate clock looks
like; before the fix both frames were identical.

**Also closed in this pass.** A poll landing in the middle of a contact sync split the feed's one
line into two counts that did not match the CONTACTS row, because the run was only merged while
the contact frame was the *last* event. The run is now found anywhere in the feed within a minute
(`test/meshcore/recent_feed_coalesce_test.dart` — *a poll landing mid-sync does not split the one
line*). The menu copy trim from the previous sitting is committed with it: menus name what they
open, and the sentences that explained the design moved off the firmware page.

Test count on 2026-11-16: 3168 passing, `flutter analyze` clean.
