# Meshmore SNS — project status

_Snapshot as of 2026-11-08. App `1.0.197+13`, branch `feat/app-completion`.
Change records below are newest first from R122; older entries are kept in
the order they were written._

**What is proven and what is not.** Measured on this tree, 2026-11-07: `flutter test` **2114 passed** in 3 m 08 s;
`flutter analyze` reports **no issues** (the two `unawaited_return_in_try_block` warnings in `lib/maps/maps_controller.dart`
were fixed on 2026-11-05, so any warning now is a regression);
the protocol package `dart test` 368 passed with 1 skipped; the pure-Java port at the repository root, `cd libmeshcore && ./gradlew test --offline
--rerun-tasks`, 143 tests with 0 failures. Both release paths build: `flutter build appbundle --release` produced a 77.0 MB bundle and
`flutter build apk --release --target-platform android-arm64` a 32.2 MB APK, each signed with a throwaway key that
was deleted afterwards (`meshmore-publishing.md` lists what the publisher must supply instead). The debug arm64 APK
(105 MB) is installed on the motorola edge 2024 over wireless adb.

**Device-verified on that phone, 2026-11-07** (screenshots and accessibility dumps, not test output): a group boundary
is one rule and one only, in both the dark and the paper ground, with no filled header between them (measured: the same
five rules at the same five y positions in both grounds); selecting Studio Light keeps the Studio dashboard instead of
swapping in the SEELE monolith.

**Device-verified on that phone, 2026-11-07 (later)**: the contact table now
survives a restart — the dashboard reads "193 known · contacts 193/350" straight
after launch instead of an empty list while the radio reports its own count — and
the Ping target sheet lists all 193, filters by name, and a row other than the
first is selectable. A ping to **HELTEC-BASE** (a chat node, 0 hops) runs: the
screen states "Asks for readings. The other radio answers only if it shares them
with you", sends, and reports `1 sent · 0 replied · 1 lost`. That loss is the
peer's telemetry permission, not the app: a chat node is pinged with a telemetry
request, and a node that does not share readings answers nothing. A repeater
target would use the status request instead.

**Device-verified on that phone, 2026-11-05**: the app bar
carries one title and the dashboard's is the app's own name; the tab strip's cell is labelled "Hyperlocal grid"; each
group boundary draws one rule, not two; the status slab names the radio instead of repeating the chip's "linked"; the
radio's stored contact table fills the node list on connect and kept growing live (184 → 193 of 350); a channel text
was sent on air and acknowledged by the radio (the row's tick); the vector basemap draws on the paper skin and
re-paints into the dark palette on a preset switch, which is the defect the owner described; the Tools list carries
the check-in row and the alarm screen no longer does; the contact picker lists HELTEC-BASE with "direct (0 hops)"; and
the Japanese locale renders. The clock rule and the coalesced feed were verified the same way on the previous build.

**Owed on the phone**: the ping round trip, the alarm's hold-to-raise and cancel, a media send and receive, the
notification tap-through, a radio-settings save and revert, and the Doze/foreground-service run — scripted taps kept
losing focus to another app mid-sequence, so this is deferred rather than half-done. The 16 KB page check fails on
`libavif_native.so` only (`tool/check_16k.sh`); the two published deadlines differ, so the Play Console notice
decides, and that is not needed until David uploads.

An offline-first Flutter companion app for MeshCore LoRa mesh radios
over BLE. Mesh-first, no backend, no account, no server.

## Architecture

- **`MeshcoreController`** (`lib/meshcore/`) — the Provider-exposed
  facade over the BLE link + MeshCore companion protocol. Owns nodes,
  chat/DM, channels, telemetry, battery, location, delivery tracking.
  Transport is injectable, so the whole controller is `flutter test`-
  covered with a fake (1680 app-wide tests, measured 2026-11-05).
- **`packages/meshcore`** — pure-Dart protocol codec (frames/opcodes,
  CayenneLPP, channel/identity crypto, the binary/raw carriers). No Flutter deps.
- **`lib/meshcore/mesh_sender.dart`** — the app's own raw send path: one opaque
  record to a contact as `0x19`, with the radio's OK/ERR as the outcome.
- **`lib/meshcore/airtime.dart`** + `airtime_meter.dart` — the two airtime policies and the LoRa time-on-air
  estimator. Every send is charged through one path; a send over the window is refused by the app's own meter
  (`AirtimeRefused`), an urgent send bypasses the refusal but is still charged.
- UI: `provider` + `go_router`; token-based themes; ARB + `gen-l10n`
  localization (EN + JA, in lock-step).

## Feature inventory

**Connection & shell**
- BLE scan / pair / connect, auto-reconnect (backoff), background
  keep-alive (Android FGS), reconnect on resume.
- Dashboard (R8): peers-in-range, radio/location readouts, battery
  readout (taps → Battery screen), recent activity, and the device name
  as a **readout that opens Device configuration** (R100). Rename with
  re-advertise + SelfInfo refresh (R52) lives there.

**Chat (R6/R20)**
- Channel + DM chat; per-message **delivery status** (sending → sent →
  delivered / failed), handling the firmware's ACK-before-SENT ordering.
- Channel sender attribution via the "name: " text prefix.
- Channels: name + PSK, **#hashtag-derived** public channels (SHA256),
  hex PSK, shake-to-derive; QR share.

**Nodes / fabric**
- Nodes list with DM counts, tags (R28), favorites, and a per-row
  **temperature chip** when telemetry is present. The proximity badge
  lives in the node sheet, not the row (R108).
- Node detail sheet: identity, signal, hops (Direct / N-via / **Flood**
  / unknown), per-node telemetry (altitude + **temp/humidity/pressure**),
  on-tap telemetry query (contacts only).

**Navigation (R64/R85/R95/R109)**
- Six views (`dashboard, chat, nodes, grid, map, settings`; R85). Two ways
  across: a horizontal swipe on the body pages one view (R109), and the
  **view strip** — tap jumps in one frame with one cue, vertical drag steps
  one view (R95). A surface that needs the drag takes it: the **Map** while
  it is current, and the grid while a pan/zoom view is in pan mode. Strip is
  56 dp tall, 48 dp cells with 22 px icon-only glyphs, 3 px selected rule,
  and the app bar ends in a rule: 2 px `fg`@22 % on the dark skins, and on paper a
  1 px `line` at 3.6:1, because the dark skin's faint rule was 1.35:1 there.
- **Hyperlocal grid (R118).** The tab is called **Hyperlocal grid** again
  (`gridTitle`, EN/JA), not "Survey". Its views are one flat picker list —
  Radar, Coverage, Weather, Mesh tree, Message heat, Altitude — with no "More views…"
  second level and no hand-off row to the Map tab: this tab is a destination,
  not a router. The globe is out of the product.
- **One header (R118).** The app bar names what is on screen: the app's own
  name on the dashboard, the view's name everywhere else (`home_shell.dart`).
  The second title block that used to sit under the strip is gone — 56 dp of
  the same information, twice. `MmPageHeader` is deleted; its left-padding
  token went with it.
- **The paper ground audited (R118).** Studio Light was the first preset to be
  measured rather than eyeballed: `fgDisabled` went from 2.1:1 to 3.2–4.6:1 on
  the layers it is drawn on, the dark skins' 1.9:1 gauge amber became a `warn`
  role at 5.7:1, twenty subtitle sites moved from ink-at-60 % (3.9:1) to the
  secondary tier, every 35–50 % border became the border tier (3.5:1), the
  collapsible header's beige band became an opening rule (a band on paper is a
  box), and a `Card`'s shadow became a border. Two screens could not be
  completed at the floor and now scroll: the first-run intro (2120 px of
  overflow above the only button) and the device sheet (the radio list was
  under the glass). Tests: `test/theme/section_header_test.dart`,
  `studio_light_test.dart`, `test/ui/disabled_affordance_test.dart`,
  `mm_value_fields_test.dart`.
- **Storage, in the app (R118).** Settings → App settings → Storage states what
  the app holds with the numbers each store can prove: map data against its
  budget with cached tiles split from downloaded regions, a sweep that clears only
  the rebuildable tiles, and the sealed history's record size published by
  `ChatStore.bytes`. A store that cannot measure itself is absent rather than
  guessed at.
- **Broadcast reach (R118).** D8.1's flood scope is now read on connect
  (`CMD_GET_DEFAULT_FLOOD_SCOPE`, decoded from the reply the frame codec used to
  drop) and the photo composer states which scope a send inherits — a named
  region, no scope set, or not yet reported — plus that a photo carries no
  acknowledgement.
- **The floor test was measuring one skin (R118).** The per-preset pass skipped
  tapping the Dashboard, so after the first preset it measured whichever view the
  previous iteration left on screen. With every view actually shown, three Dr Pop
  overflows appeared at 320 dp / 200 % and are fixed: the brand tag ran 229 px
  past the edge, the channel name 94 px, and the block grid's fixed 116 dp height
  clipped its own label and numeral by 52. A second test renders four deep routes
  in every preset at the floor, which is what surfaced it.
- **Tool pickers filter (R118).** Ping, trace, soak and the range test all opened
  one undifferentiated scroll of every synced contact — 190 rows on the bench
  radio. The filter matches a name anywhere and a key from its start, and the
  rule is a pure function with its own test. Found while driving the phone: the
  sheet's list had been shrink-wrapped inside a min-height column, so its lower
  rows drew outside the sheet's box and stopped accepting taps.
- **One bubble rule, one composer (R118).** The message bubble carried a fill
  and a hairline around one edge; it now carries one of the two, and the Dr Pop
  Mondrian rule is the one deliberate exception, written where it is drawn. Both
  composers used Material's bare `OutlineInputBorder` — the last control that
  ignored the skin's corner and hairline — and now share one decoration. The
  send control says whether it can act.
- Device configuration (5 groups) and Profile & personalization (4
  groups) fold with `MmCollapsibleSection`, open by default.

**What this branch added (R109–R113 and the completion waves)**

- **Notifications.** Three OS channels (channel message, direct message, SOS) at
  high importance with no full-screen intent, a per-channel bundle with
  audio/haptic/OS/TTS and a mentions-only mode, one post per message id, the
  open thread suppressed by a focus record the shell publishes, tap-through to
  the thread including after a cold start, and an SOS body that carries no
  coordinates. `lib/notifications/`, `test/notifications/**`,
  `test/shell/home_shell_test.dart`.
- **Composer.** The byte counter delegates to the encoder, so the number and
  the refusal agree (160 UTF-8 bytes including the `sender: ` prefix), and
  per-channel and per-thread drafts are sealed, debounced, restored after a
  failed send and keyed by radio. `lib/chat/composer_budget.dart`,
  `lib/chat/draft_store.dart`.
- **History.** Search over stored history with blocked hits counted and
  ranked word matches, per-channel unread badges, a thread that says how many
  rows the 250-row cap dropped, and a per-thread `MMEX` export that leaves
  through the share channel. `lib/screens/chat_search_screen.dart`,
  `lib/chat/unread_counts.dart`, `lib/meshcore/history_export.dart`,
  `lib/util/share.dart`.
- **Block list.** Full 32-byte keys, app-side only, read by the timeline, the
  roster, places, search, unread counts, speech and notifications, with a list
  screen at `/settings/blocks` and copy that says the radio still carries the
  packet. `lib/meshcore/block_store.dart`, `block_filter.dart`.
- **At rest.** History, drafts, places, the block list and the retention tally
  live in one sealed file whose AES-256-GCM key the Android Keystore generates
  and does not export. The plaintext was migrated once with a serialised
  read-back. Auto Backup and device transfer exclude everything, and exports
  are passphrase files that fail closed. `lib/meshcore/secure/`, `SecureStore.kt`.
- **Places.** The text convention with a trailing TTL, a nine-token type set, a
  deterministic id over six-decimal coordinates, a layer with clustering and a
  countdown, long-press create with the 6-per-hour budget, confirm and refute
  as claimed, the directions ladder, echoes in the thread, a ledger export and
  a photo path whose photo never extends the TTL. `lib/places/`,
  `test/places/**`.
- **Media.** One AV1-class format behind a codec seam with a 320x240 floor, a
  12-byte chunk header with its own CRC and a resend salt, reassembly with a
  missing-chunk request, erasure FEC at 10 % for images and 15 % for voice,
  350 ms pacing with table-full as backpressure, a Public-channel gate on the
  only send path, a cost line before the send, and an inbound consumer that
  decodes what arrives. `lib/media/`, `test/media/**`.
- **Field operations.** Our own position trail with age and count bounds, GPX
  and an operational bundle, both of which leave through the share channel,
  geofences with a ±5 % margin shown on the map, an inter-node relationship
  line, and SOS plus check-in as engines with surfaces and exact timings.
  `lib/field/`, `lib/geofence/`, `lib/telemetry/coverage_*`, `lib/sos/`.
- **Pairing and the radio.** In-app pairing with five named failure paths, the
  four stranding parameters as one transaction with a single-use revert, a
  capability model learned from replies, a health readout that names each
  frame, and an MTU refusal at 179 with the negotiated number in the copy.
  `lib/screens/pair_radio_screen.dart`, `lib/meshcore/radio_config_transaction.dart`,
  `lib/ui/radio_health_block.dart`.
- **Accessibility and l10n.** A 320 dp by 200 % floor over every primary screen
  and the three new routes, semantics on the shell strip and the icon-only
  controls, and a lockstep test that fails when an ARB key or a getter is
  missing on one side. `test/screens/a11y_floors_test.dart`,
  `test/l10n/lockstep_test.dart`.
- **Skin sweep.** The six shell views are built once per preset, so a view that
  breaks under one skin fails a test rather than a user. Seven cases, measured
  8 s for the file, which is the only test here that mounts the whole app seven
  times. `test/theme/skin_sweep_test.dart`.

**Studio skin (R63)**
- Seventh preset `studio` ("Studio Dark — clean · square"): grey layer
  stack + 1px hairline + square controls + one light-grey accent (R68;
  blue in R63-R65). `MmTokens`
  gained derived `raised/selected/hairline/onAccent/fgDisabled`; `MmShape`
  gained `hairlineWidth`/`squareControls`; the six older skins are
  unchanged by construction (`test/theme/mm_layers_test.dart`).
- `MmCollapsibleSection` groups Location settings (Auto-publish / Beacon
  / Manual). Collapse state is **persisted** per stable group id (R65:
  `MmCollapseController`, `mm.collapse.v1`, default open, loaded before
  `runApp`).
- R65: Studio hairline/line `#4A4A4A`, accent `#70A5DA`, alert `#E8887E`
  so the rule and the coloured text are legible on all four layers (the
  old hairline was 1.06:1 on `selected`). Pinned per layer in
  `test/theme/mm_layers_test.dart`.
- R66: Studio cards get a 1px hairline edge and the app bar (with the
  view strip) ends in a 1px hairline; both null for the six older
  presets. **Unverified on a device** (theme-level tests only).
- R66: a collapsible group with no `MmCollapseController` provider still
  works per session but logs a one-time `debugPrint` on its first toggle.
- R68: Studio is **monochrome**: accent `#D0D0D0` (saturation 0), alert
  `#D6A7A1`, ok `#A9C4A7` (both <= 0.30 saturation), new `onAlert` token
  (dark on the alert fill). The R63/R65 blue is gone. Pinned in
  `test/theme/mm_layers_test.dart`. **Unverified on a device.**
- R68: fixed the shell being mounted twice at launch (BootOverlay swapped
  Stack for a bare child on dismissal); `test/shell/boot_overlay_test.dart`.
- R68: Personalization is uniformly collapsible (4 groups; TYPE and
  Audio alerts fold too).
- R68: Device configuration groups region presets under Americas /
  Europe / Asia-Pacific headings (was one wall of 15 chips).
- R68: the boot overlay is grey under Studio (still NERV for the rest).
- R68: the app-bar link chip is localised (was hard-coded English).
- R68: Studio has its own dashboard (`StudioDashboard`): quiet status row
  (text + dot shape, no colour fill), collapsible Radio / Location /
  Recent. Type rule: words sans, machine data mono (`MmType.sansLabels`).
  The old SEELE "double CONNECT" was one TextButton drawn in the accent on
  the error fill (1.5:1) beside a second OFFLINE in the app bar.
  **Unverified on a device.**
- Audio aliases the Hyperlocal pack; **unverified on a device**.

- R69: the Map tab with no fix shows a world view (20N 0E, zoom 2) plus a
  quiet "no fix" row instead of a blank screen; the grid's street-map mode
  keeps its empty state. **Unverified on a device.**

- R69: the named raw-English strings (Device configuration channel row and
  live-params line, location source label, battery "CHG", Elevation chip,
  Nodes clear-search tooltip, Diagnostics connection block) now follow the
  locale. **Unverified on a device.**

- R69: the 28-36dp icon buttons the R68 pass listed (chat/DM message
  actions, dashboard refresh, equal-grid and fabric-survey controls, dense
  audio toggle + NERV bluetooth sibling) are 48x48. **Unverified on a
  device**: the equal-grid bar is wider now (about 280dp), fabric-survey's
  column is 240dp tall.

- R74: prose that older skins set in mono is sans under Studio (`MmType.wordsMono`): docs hub, grid HUD heading, readout labels, status pill, voice/battery sentences, boot overlay. `PEERS IN RANGE / 0 known` counts `mc.nodes` (contacts + adverts); channel chatter makes no node, so the label stands (a 'heard on channel' line is proposed, not done).
- R84: **the basemap picker works in Studio.** It was a dead control (it changed a raster source the vector layer ignored). It now offers the skin's vector basemap plus the raster sources; a raster pick draws that source dimmed, the credit and zoom ceiling follow what is drawn. **Not device-verified yet.**
- R85: **six views.** Docs and About are no longer tabs: Settings > Information (`/settings/about`) holds the brand/version block and licences. New EN/JA strings, `DocsHubScreen` is now a routed sub-page. **Not device-verified yet.**
- R86: **Docs is a Settings row beside Information** (`/settings/docs`, was `/settings/about/docs`), listed immediately before Information. The top view strip fills the full width in equal cells (scrolls only below 288dp). **Not device-verified yet.**
- R87: **clean-up pass.** `MmScaffold` gains an ink surface (tap ripples on Device/Channels/Personalization rows); `about.dart`, `boilerplate_main.dart` and 24 unread ARB keys deleted; Docs hub on the skin ground; tooltips on two icon-only buttons; three strings localised. Known, not fixed: 320dp at 2.0x text overflows the Dashboard status row (~7 px) and the New-region source dropdown (~57 px). **Not device-verified yet.**
- R113: **a channel tag has one canonical form.** `canonicalHashtag` trims and prefixes, so `emergency` and `#emergency` derive one key — the firmware's own definition (first 16 bytes of `sha256("#test")`, `docs/companion_protocol.md`). The weak-tag warning reads the same canonical string, and a tag typed without `#` saves `#name` to the slot. Case is not normalised. A slot written before this change keeps the key it was given (the tag was never stored, so it cannot be re-derived); it is not the public `#name` channel.
- R112: **the datagram's profile byte is read out.** `RxVia` on `ChannelDataFrame`; Diagnostics states the channel, which radio carried it, and the application data type. "Unreported" is the normal reading on a single-profile radio. No application consumer for the datagram yet (that is the `0x3E` work).
- R111: **the link says what it negotiated; a link that cannot carry a frame is refused.** MTU read before subscribe, refused below 179 with a typed failure naming the number and no reconnect spent on it; Diagnostics prints the MTU, the refusal in EN/JA, and counters for truncated and trailing-bytes frames — the `DecodeFailure` path nothing consumed.
- R110: **the inter-app gateway is gone; the raw send stays.** Decided 2026-11-05 (`meshmore-scope-of-record.md` §12, D10.1): the one application that used the handoff now owns the radio link itself from its own copy of the Android transport, so nothing on this phone needed the server. Removed: `lib/meshcore/gateway/` (the loopback L2 server, the Binder handoff, the pairing-token store), `lib/screens/connected_apps_screen.dart` with its route and Settings row, the `GATEWAY_HANDOFF` signature permission and its exported service in the manifest, the method channel and `GatewayHandoff.kt`, `flutter_secure_storage`, the 20 EN/JA `connectedApps*` strings and their generated accessors, and the two packages `meshcore_gateway` and `meshcore_host`. Kept and moved: `MeshSenderAdapter` became `lib/meshcore/mesh_sender.dart` with `bindPeer`/`isContact`/the status view dropped (the destination is a per-send `Contact`, since the caller is now the app itself) and `airtime_prefs` now reads `AirtimePolicy` from `lib/meshcore/airtime.dart` instead of the deleted package. Not kept: the airtime governor, because it metered a client's records and there is no client; the estimator and policy are the parts a future meter is built from. Tests: `test/meshcore/mesh_sender_test.dart` (12) and `test/meshcore/airtime_test.dart` (4) replace the four deleted gateway test files. `flutter analyze` clean apart from the two known `maps_controller` warnings; full suite 1046 -> 1016 tests, 83 s.
- R109: **the swipe between views is the shell's again, gated per pan surface.** `origin/dev` (the app owner's own branch) shipped the opposite of R95's second half in `10a8c14` + `c81b051`: a left/right swipe changes screens, maps change by the picker, and a pan/zoom view carries a **Swipe ⇄ Pan** toggle. Ported onto this tree with R95's first half intact (tap jumps, one cue; vertical strip drag steps a view). Paging is locked while the drag belongs to a surface: the Map while it is the current view, and the grid while a pan/zoom view is in pan mode (`lib/shell/horizontal_drag_claim.dart`, named holders, published outside the build pass). Pan mode is off on every visit; the toggle is on the five views that pan (globe, street map, fabric, tree, SNS cells); the equal grid is pinned to us and is not one of them; in swipe mode the view is held still with a hint. The Map's R67 edge bands stay and change exactly one view. EN/JA: `gridSwipeModeTooltip`, `gridPanModeTooltip`, `gridSwipeHint`, `gridPanHint`. One measured trap recorded in the tests: a claim held on mount is wrong, because the shell builds the neighbour page before it is shown, which locked the shell while another view was on screen.
- R108: **node row right column.** Age and badge were centred against the 48 dp star button; both are start-aligned now, star is compact, and the FAR/IN RANGE badge is removed from the list (it contradicted the age and the distance, which already says it).
- R107: **prose pass 2.** Node sheet: telemetry-share help 139 -> 68, add-contact done 141 -> 76, remove-contact question 112 -> 87, empty link list 93 -> 66. Identity dialogs deliberately untouched.
- R106: **three more sheets unified.** Location interval, location movement and device GPS interval now use `showMmPicker` (they were the last sheets with no drag handle).
- R105: **prose pass 1.** Ten explanation strings shortened (node, channels, location, contacts), JA in lock-step. Longest cut 191 -> 67 chars. Region legal text and identity dialogs left intact.
- R104: **grid pickers are sheets.** New `showMmPicker<T>` (48 dp rows, ticked current value, group headers) replaces the view, interval and range `PopupMenuButton`s. Adds `context.skinRead` for event handlers.
- R103: **band picker folds.** Applied-band banner above the section, chip list collapsed by default, family headings quiet labels.
- R102: **device pass.** Chat time gutter scales with text (was wrapping "16:0" / "7"); node row is `type · distance` + mono signal, no bare hex or coordinates; `MmListRow.alignTop`.
- R101: **page vs panel.** Audit result: no routed screen lacked a back
  control (every route pushes an `AppBar`); the only exit-less surface was
  the node sheet (R96). Rule recorded: a panel is for a choice that ends
  where it started, a page is a place you return to with its own state.
  Same task was solved three ways (sheet, popup menu, inline dropdown);
  the three grid menus became sheets in R104.
- R100: **settings in Settings.** Dashboard device name is a readout that opens Device configuration (rename stays there); `showDashboardRenameDialog` + its string deleted; Studio's region row gets a chevron.
- R99: **actions look pressable.** New `MmAction` (tonal fill + hairline, skin shape, 44 dp) replaces bare TextButtons for Connect/Retry, Details, Load from device, Set name, Set advert location.
- R98: **square = 1 px corner.** `kSquareRadius` backs mmRadius, squareBorder, squareField, cards, FAB and the chat pill's square branch. Sharp non-square presets keep 0; the >=6 px guard still runs.
- R97: **link green everywhere.** New `MmTokens.link` (#3DDC84) for the app-bar chip, dashboard status slab, Studio dot and AG-HUD/NERV/Hyperlocal pills. `DashboardModel.linked` separates "link up" from "not alert".
- R96: **node sheet exit.** Close button in the header (EN/JA). A sheet opened from a DM no longer offers Message (it stacked duplicate DM routes).
- R95: **one navigation model.** Strip taps jump (no 250 ms scroll across the views in between, one nav cue instead of one per page crossed). Body swipe paging removed in every skin; `swipeNavigation` and the grid pan flag deleted. Vertical drag on the strip steps one view. Strip 56 dp tall with a 3 px selected rule; every preset's app bar ends in a 2 px `fg`@22% rule. **Half of this is superseded by R109.** The tap behaviour (jump, one cue) and the vertical strip drag stay; body paging is back, gated per pan surface. R95's own claim that paging is gone in every skin is history now, kept because it explains why the flag was deleted once.
- R94: **Settings hub labels fixed.** R92 picked the group label by list index (0/4/8) while the separators sit at 0/3/7/10, so the phone showed RADIO / ABOUT / ABOUT / ABOUT. The label now lives on its own group row; a test builds every row and asserts each label once, in order. Found on the phone while recording the radio model.
- R92: **Settings grouping + text cuts.** Hub grouped RADIO / APP / CONNECTION / ABOUT. Three dead chevron rows removed from App settings (Connection, Notifications, Data/About). Region disclaimer 620 → one line + Details dialog; telemetry help 470 → one sentence; nodes empty state 4 paragraphs → one; docs subtitle 150 → one line. Two jargon subtitles rewritten.
- R91: **crowded headers.** Chat is one 48 dp strip (chips + "+ Manage channels" + speech toggle); the "CHANNEL · NAME" caption and collapse chevron are gone. Nodes filters move into one sheet behind a counted Filters button (search stays). Grid transport bar is a Wrap with an icon+stop range control (no 320dp overflow). Dashboard Connect/Retry gets its own row instead of squatting in the status slab.
- R90: **basemap + event maps.** OSM vector is the basemap on every skin (raster OSM dropped from the picker, kept as the cell/fabric fallback). The map's layers button no longer removes the basemap; it opens event-layer visibility. Layers get per-layer colours, a 24 dp point hit box, and a "not loaded" mark. Basemap choice persists. Self-test reach check fixed for MVT.
- R89: **grid chrome.** Header is one control (current view, icon + long name + chevron) with the menu grouped PEERS / SURVEY / REPORTS. Play/pause + interval and the range scale moved to a bottom bar, shown only in the seven views with a time-ordered snapshot. Legend button only where a legend exists. `_live` starts true so the transport no longer says "paused" while the view is live. Footer and four strings deleted; counts line is `gridStatusCounts`, shown in every view.
- R88: **first device pass against a live radio.** motorola edge 2024 + `MeshCore-HELTEC-BASE` (fw `v1.17.1-d929643`): LINKED, self info, radio params, battery, device location, 2 nodes, docs FIRMWARE card matched to the firmware, logcat free of Flutter assertions at 387/320/256dp and 2.0x. Fixed: the About page printed "Terms & Conditions — wired in U5." (placeholder, U5 unbuilt) — line and `aboutTerms` removed from both ARBs, test guards it. Corrected from R87: the status-row squeeze is the DISCONNECTED state only (CONNECT button); LINKED wraps cleanly.
- R83: **region files deferred; the live map made responsive.** The archive machinery stays (reader, resume, hash, read-in-place) but its Settings entry is hidden behind `kRegionFilesEnabled = false` until a region file exists to publish. Map: one in-flight request per tile (dedupe), a 24-tile warm ring prefetched 500 ms after the camera settles and only while the gate is idle, 24 MB parsed-tile memory cache, and Studio zoom capped at z17 (Shortbread stops at z14). **Not device-verified yet.**
- R82: **the Studio basemap is OSM's own vector service** (`vector.openstreetmap.org/shortbread_v1`, Shortbread v1, live since 2025-07-22, policy-permitted for interactive apps), so no third-party tile company sits in the middle. `kOsmVector` replaces `kOpenFreeMapVector`, and `assets/maps/studio_dark.json` is rewritten for Shortbread: 28 layers, 14.9 KB (was 47 / 36 KB), every `source-layer` asserted against the published schema. Region archives must now carry Shortbread too (`kArchiveRequiredLayers = {water_polygons, streets}`). Tile life is floored at seven days (`MapSource.minCacheAge`) because the service advertises five minutes while its policy requires a week. Rendering, store, cache, ETag, budget, expiry, backoff and gate untouched. **Also fixed:** Android Auto Backup would have uploaded region archives (25 MB quota) - both backup rule files now exclude `maps/`, guarded by a test. iOS `isExcludedFromBackup` not done. **Not device-verified yet.**
- R81: **map subsystem pass** (not device-verified). OpenFreeMap is view-only (its terms cap offline use at 3,000 tiles / 50 MB; USGS Topo and Imagery are the only pack sources). Fetch backoff is per source after three failures, jittered, instead of one global 30 s freeze. New `TileFetchGate` (4 concurrent, newest first, stale dropped), 404 = empty tile, second library tile cache capped, Studio underlay = style background. PMTiles v3 reader written in-house (the `pmtiles` pub package is BSD-2; unused `vector_map_tiles_pmtiles` removed). **Region files**: one resumable verified PMTiles download per region, read by seek, Settings > Maps > Region files. Style retuned to the Studio tokens (labels >= 4.5:1, blue water, green parks). **Correction:** `vector_map_tiles` and `vector_tile_renderer` are BSD-3-Clause (R80 called them MIT), as is `flutter_map`. **Open, owner:** Protomaps schema vs OpenMapTiles (see maps spec "R81 decisions"), where region files are hosted. See `meshmore-sns-maps-spec.md`.
- R80: **the Studio map is rendered from vector tiles**, not recoloured raster: `vector_map_tiles` + a bundled Apache-2.0 OpenFreeMap dark style, tiles served through the existing offline tile store (`.pbf`, same cache/packs/ETag/budget, 2062 tiles cached on the device pass), labels drawn by Flutter text (no glyph server), attribution now names OpenFreeMap and OpenMapTiles. No `flutter_map` upgrade needed (8.0.0 wants `^7.0.2`). Raster remains as the fallback. **Device-verified 2026-10-20:** renders, tiles fill in, zero fetch failures. Style is untouched OpenFreeMap dark, so it is near-greyscale and low-contrast; a palette pass to the Studio tokens is the next step, as is sprite icons.
- FIX: **two fetch defects that had hidden each other.** `httpMapFetcher` swallowed every exception (`catch (_)`), so a real failure looked like a missing tile. Adding a debug log exposed the cause: `HttpHeaders.value()` throws when a response repeats a header, and OpenFreeMap sends two `cache-control` headers, so every vector tile died in the header read. Now `headerValue()` joins list-valued headers and takes the first of single-valued ones. Tests: `test/maps/duplicate_headers_test.dart` (real loopback server).
- R79: **the map is dimmed, not recoloured.** `out = 0.70 * in` (a pure RGB scale) replaces R70-R73's luminance invert + 0.15 desaturation, which flipped hue (OSM water read orange) and, because the filter was applied to every basemap, destroyed the USGS **aerial-imagery** source. Hue now survives (land 169, sea 119/148/156, label 36, 6.7:1). `darkBasemap`/`mmDarkTile*` renamed `dimmedBasemap`/`mmDimTile*`. **Unverified on a device.**
- R78: **Studio has no swipe navigation** (`MmShape.swipeNavigation`, false for Studio only): the `PageView` is `NeverScrollableScrollPhysics` and the Map tab's R67 edge bands are not wired. The 48dp strip is the only view switcher; the six older presets still swipe. **Unverified on a device.** **Superseded by R95**, which removes body paging in every skin.
- R127 (2026-11-08): **every preset now carries the degraded banner, and four dashboard layouts got their first behavioural test.** The banner was built inside the SEELE monolith, so a storage-full warning showed on one of the seven presets and none of the others; the observation moved to `DashboardHost`, above the layout, because the facts do not change with the preset. `test/screens/dashboard_layouts_test.dart` renders all seven layouts over one controller and records what each actually says: the peers-count idiom (a bare numeral, Recon's `seen/known`, the radar's `NODES n` rail cell), whether a recent-activity feed exists at all (drPop and Recon carry none, now recorded rather than assumed), the LOCATION tile (SEELE and Studio only), and three link states across every layout (live says LINKED, a drop says RECONNECTING, a transport that cannot be acquired says LINK LOST, and no layout keeps claiming LINKED). The fixture also had to pin a distinction the app makes and a test can easily miss: a contact with an old advert is known but not in range. One guard was wrong and is fixed with it: `ui/mm_collapsible.dart` counted live section ids in a `Set`, so a layout swapping under the same id read as a duplicate — the incoming section mounts before the outgoing one disposes. It is a count per id, checked at the end of the frame.
- R126 (2026-11-08): **the storage block states every store, and deleting everything says what happened.** It had named the map budget and the sealed history's size; places, the movement trail and the media journal were counted only inside their own stores. All three are in the block now, with their real bounds (rows of 500, 2000 points or seven days, unfinished transfers), and a store outside the tree is absent rather than shown as a zero. **One destructive action** clears the sealed history, places, the trail, the media inbox and cached map tiles behind a dialog that lists exactly what goes and what survives and requires the word DELETE typed; packs that can be re-fetched are kept, and the snackbar says which. Each clear runs under a bounded wait and the result is always reported — a confirm that then says nothing was the bug the first test caught, and it was real: `places.clear()` hung under the host's missing Keystore and left the whole chain suspended. The history goes through the new `MeshcoreController.clearAllHistory()`, which empties the in-memory rows and the dropped tally as well as the sealed record, and `ChatStore.clear()` zeroes its published byte count; without either, the app would delete and then repaint the history from memory. Tests: `test/ui/storage_use_block_test.dart` (the counts, the absent-store case, the typed-word gate, cancel deleting nothing, and confirm repainting the counts in place).
- R125 (2026-11-08): **the Java port now decodes every opcode the Dart reference does.** 24 of 45 cases were implemented, so 21 inbound opcodes arrived as `UnsupportedFrame` — well-formed and named, never misread, but invisible to a Java consumer. The port has all 45 now (20 new frame records, 13 model records, `ByteCursor.i16`/`skipRemaining`, `MeshcoreResponse` 24 → 45 codes with none duplicated), and `everyOpcodeTheDartReferenceDecodesIsModelledHere` fails if the Dart side grows again without the port. Java suite 164 tests, 0 failures, 1 pre-existing skip; `javadoc` clean under the build's doc gate. **Not proven, and named in the register:** no Java consumer exercises the new frames yet, and the 21 vectors are hand-built from the Dart suite's cases rather than replayed from the shared golden files, so they are not yet cross-implementation fixtures.
- R124 (2026-11-08): **one lost app-start frame no longer costs the whole handshake.** The owner reported the symptom eight times between 2026-11-01 and 2026-11-06: returning to the home view showed "hand shaking for like a long time", and pressing refresh made it work. The cause was real: the handshake sent APP_START **once** and waited 8 s for the SELF_INFO that answers it, so a single lost notification failed the whole handshake, tore the link down and started the reconnect ladder. It now re-sends APP_START once at half the window (a duplicate app-start is harmless — the firmware answers), and the counters `handshakeAttempts`/`handshakeTimeouts` are shown in Diagnostics when non-zero. Two hazards the same report exposed are closed with it: transport close and open are bounded (5 s and 30 s) with a typed `LinkAcquireTimeout`, because an unbounded `close()` inside `connect()` could wedge `_connecting` forever with the UI still reading "handshaking" (both states render the same boot string, so a retry ladder reads as one stuck handshake); and the first retry after a handshake timeout is immediate, while the ladder's 6 s floor still applies from the second attempt so an absent radio is not rescanned inside Android's five-scans-per-30 s throttle. Worst case for one lost frame: **about 4.0 s to ready**, was about 14 s and a new link. Still owed, and recorded rather than fixed: a radio that is genuinely gone takes about 3 min 18 s to reach `gaveUp`, and the boot overlay renders `reconnecting` with the handshaking string, so that wait still reads as handshaking. Tests: `packages/meshcore/test/meshcore_connection_test.dart` (4), `test/meshcore/link_recovery_test.dart` (3), `test/screens/diagnostics_screen_test.dart` (2 new), each proved by mutating the fix and watching it fail.
- R123 (2026-11-08): **the image encoder now spends CPU to buy airtime, and the setting is measured rather than argued.** The default was `speed: 9` on libavif's 0–10 effort scale, chosen to save encoding time on a phone — the resource this app has most of. The one it has least of is channel time: one datagram every 350 ms at 150 payload bytes, so a full-budget 4 KB photo is 27 datagrams and about nine seconds of airtime against a 36-second hourly budget. Measured with the bundled libavif/libaom on a 320×240 gradient photo at quantiser 18: speed 9 gives 1390 B in 7 ms, speed 6 gives 887 B in 22 ms, **speed 5 gives 784 B in 90 ms**, speed 4 gives 796 B in 131 ms, and speed 0 gives 749 B in 818 ms. The knee is 5: 44 % smaller than what shipped, and the last 35 bytes to the maximum effort cost nine times the CPU and a frozen frame on a phone, because the encode is synchronous. `speed: 0` was tried first and rejected on that evidence. The numbers are content-dependent, so M1's device run is still the gate, and if a phone's encode at 5 exceeds about a second the answer is to move the encode off the frame thread rather than to lower the effort again. Test: `test/media/media_codec_settings_test.dart` also pins the 350 ms pacing, 150-byte payload and 27-datagram arithmetic, so changing any of them forces the reasoning to be re-read.
- R122 (2026-11-08): **a throw inside one tracker no longer costs the rest of the frame, and three notifiers stop notifying after they are gone.** One inbound frame ran 23 tracker and ingest steps in a single closure with no try around any of them, so a throw in one aborted the rest for that frame (a message recorded but never heat-mapped, a delivery state half-updated, the notify skipped) and the only trace was an uncaught async error. The steps now run through `lib/util/frame_trackers.dart`, each in its own try, failures go to `AppErrors.record(where: 'frame')`, the frame counts once in `MeshcoreController.framesDropped`, and Diagnostics says so when the count is above zero. Every production tracker is defensive today, so the isolation is proved with throwing callbacks and the wiring with a hostile-input test; planting a failing tracker in shipped code to raise the count was refused. Second: `lib/util/safe_notifier.dart` is one `SafeNotifier` mixin, applied to `PlaceStore`, `GeofenceController` and `ToolsController`, which could each notify from an awaited write that outlived its owner. `SoakTool` already inherited the guard from `MeshTool`, so a test pins that rather than adding a second guard. Four hand-written copies remain in `MeshcoreController`, `MapsController`, `MeshTool` and `SosController`; correct, and recorded as duplication. Tests: `test/util/frame_trackers_test.dart`, `test/meshcore/inbound_guard_test.dart`, `test/util/safe_notifier_test.dart`. Whole suite 2137 passed.
- R121 (2026-11-08): **the repository's CI has never run, because the workflow sat where GitHub does not look.** `meshmore_sns_app/.github/workflows/ci.yml` was tracked and the repository has no `.github` at its root, so no push ever started a run, and its `working-directory` values (`packages/meshcore`, `responsive_starter_app`) were relative to the wrong place anyway. It is at the root now, with the three gates it claimed (codec analyze+test, app analyze+test) plus the Java port's `./gradlew test --rerun-tasks`, pins that match the tree (Flutter 3.47.4, Dart 3.13.3, JDK 17 from `libmeshcore/build.gradle.kts`), and branch triggers that cannot be disabled by a rename. `--offline` is deliberately absent in the Java job: a fresh runner has no Gradle cache, so offline resolution would fail for a reason that is not the code. No `dart format` gate yet: the tree is not format-clean, and a gate that is red on its first push teaches people to ignore it. `test/repo_layout_test.dart` holds the arrangement in place — the workflow at the root, no workflow left under `meshmore_sns_app/`, and every `working-directory` naming a directory that holds a `pubspec.yaml` or a `gradlew` — and both guards were proved to fail when broken.
- R120 (2026-11-08): **the second radio profile is reported, and the app says what it would cost.** `0x1B` and `0x84` carry a byte naming the profile that heard the frame (`0xA0` primary, `0xA1` second), and the app decoded it and used it only to label one Diagnostics line. Device configuration's DEVICE block now has a line for it ("second profile: heard 5 min ago"), and once a frame has been heard, a note under the block states the measured cost: a second profile takes 96–99 % of the radio's transmit time. **No switch, and that is a decision (D8.27):** the companion codec has no command that sets or reads a second profile's parameters, so the staged-commit-and-revert surface the residue row asked for could neither be staged nor undone. Silence says "nothing heard this session" rather than "one profile", because a quiet second profile is indistinguishable from none, and the line repaints because every inbound frame notifies. The duration uses the shared relative-time strings, so a Japanese build reads "5 分前" instead of a localized template wrapped around an English "5 min". The DEVICE read-only block had no test at all and now has three cases (both states, and Japanese). Tests: `test/meshcore/radio_profile_test.dart`, `test/screens/device_config_readout_test.dart`.
- R119 (2026-11-07, twelfth part): **message concurrency, to the published rule.** The firmware keeps eight pending ACKs in one circular table, so a ninth in-flight message evicts the oldest entry and that message can no longer be attributed; the documented client rule is one message in flight **per contact**. The DM composer now refuses a second send while one to that contact is unsettled and says why, and the controller keeps a ceiling of **four** unsettled outgoing messages overall — half the firmware's table, leaving room for what the radio is doing itself — as the backstop for callers that are not a composer (the soak tool measures several messages to one node, which is legitimate). Both rules read the rows the app already tracks, so `unknown` counts as unsettled until its own grace timer resolves it. Test: `test/meshcore/contact_policy_test.dart`. **Also settled by the same evidence:** the "one live request" half of D8.26 was already true — `ToolsController` holds the radio for one tool at a time, which is stricter than per-peer — and the firmware's `ERR_CODE_TABLE_FULL`/`BAD_STATE` refusals were already mapped to causes. What was not built is the eight remembered guards, and nothing now needs them.
- R119 (2026-11-07, eleventh part): **D8.7's carry-over was never needed, and its copy was wrong.** The decision assumed tags, favourites, blocks and peer profiles were keyed to the radio and had to be copied to a replacement's records. They are keyed by the **node**, so a new radio inherits them by construction and the copy would have duplicated them; what is per-radio is the radio's own table, channels and settings (fetched from it) and drafts (per-radio on purpose). The Diagnostics line said "Its history is not carried over", which reads as lost messages and is false: the history is one sealed store for the app. It now says what actually happens — history, tags, favourites and blocks stay, the table, channels and settings are the radio's — in both languages. The register row is corrected with the reason rather than quietly flipped to BUILT.
- R119 (2026-11-07, tenth part): **confirming a place to the sender, not to a name.** Every place reply went out as channel text, so the tally could only record it as *claimed*: a channel message carries a name and any channel-key holder can type any name. `PlaceComposer.replyKeyed` sends the same `[CONFIRM:<id8>]` / `[REFUTE:<id8>]` grammar as a **direct message** to the reporter's own key, which the tally records as *keyBound*. The place sheet offers the pair only when the place carried a key and there is a radio — no silent fallback to a channel reply — and it shares the place budget, so it is not a way around the rate limit. Tests: `test/places/place_composer_test.dart` (addressed to the key, parsed back as key-bound, nothing sent to the channel, no key means no action, and the budget still holds).
- R119 (2026-11-07, ninth part): **forwarding a message.** The residue row said reply, copy and delete existed and no composer path took a message into another thread. Forward is now a row in the message actions sheet: it asks which conversation (the same picker the tools use), **appends** the text to that thread's draft so half-typed words are not thrown away, opens the thread, and says it went there. It is a draft and not a send on purpose — the text lands in a composer the user can edit or cancel, which is also what makes it safe on a shared mesh. Two smaller things came with it: the actions sheet's six rows grew the trailing chevron every other row in the app has (the affordance guard's baseline for that file dropped 5 → 0, which is the direction the ratchet allows), and the picker's own doc now says it is a shared conversation picker rather than a Soak/Range one. Tests: `test/chat/draft_store_test.dart` (a forward appends rather than replaces).
- R119 (2026-11-07, audit 2): **three sweeps that found nothing to fix, and here is the evidence so it is not repeated.** (1) *Swallowed failures:* 62 `catch` blocks in `lib/` whose next lines do nothing visible — read one by one, every one carries a comment saying why silence is right (an asset that may be missing, a preference write that must not stop an alarm, a corrupt blob that starts fresh, a host without the platform plugin). None hides a user action. (2) *Rebuild blindness*, the class that made the Ping target look dead: 11 `context.read` values inside `build` methods — nine are tool pages, whose `ToolPage` body builder re-reads the tool on every notification, and two are a row builder under a parent that `watch`es and a one-shot `FutureBuilder`. (3) *Hygiene:* no `TODO`/`FIXME`/`HACK` anywhere in `lib/`, seven `debugPrint`s all guarded, and every file under `lib/screens` now referenced from a test.
- R119 (2026-11-07, eighth part): **a repeater session.** `CMD_SEND_LOGIN` (0x1A) and `CMD_LOGOUT` (0x1D) were the last D8.15 item still unsent. A repeater or room node's sheet now carries a session block: the password is sent once and never stored, the reply's permission byte is reported rather than interpreted, and signing out says so. The verdict is matched by the node's prefix, so it cannot be credited to another repeater. A password longer than the firmware's 15-byte cut is refused by the codec rather than silently truncated into a different secret. **`CMD_HAS_CONNECTION` (0x1C) is deliberately not wired:** its answer is a bare OK/ERR, which the app cannot attribute without guessing, and it already has two exact ways to ask about reach (the advert route and an active path discovery). **A command console is not built:** the codec has no `CMD_RUN_CLI_COMMAND` builder, so the session is the session and not half a console. Tests: `test/meshcore/contact_policy_test.dart` (grant, refusal, and the over-long password).
- R119 (2026-11-07, audit): **the two shipped widgets with no test.** A sweep of every file under `lib/screens` against the test tree found three without a reference: the About page, and the delivery-status glyph (the third was `dashboard_model.dart`, a model rather than a screen). Both now have one. The About page's test checks the version, both brand lines, that the licence page opens, and that replaying the intro is offered only after it has been seen. The glyph's test pins the property that matters: five states, five distinct glyphs, five distinct labels, and the tooltip is the same string the actions sheet writes, because both come from `deliveryLabel`. It also asserts the Japanese label is not still English. Same sweep found **zero** TODO/FIXME/HACK comments in `lib/` and seven `debugPrint`s, all guarded by `kDebugMode` or in the error recorder.
- R119 (2026-11-07, seventh part): **the pairing PIN.** `CMD_SET_DEVICE_PIN` (0x25) was scheduled by D8.15 and never built, so the radio's own gate on a new Bluetooth pairing could only be changed on the radio's screen while the app already displayed the current value. Settings → App settings gains a **Radio access** group: the current PIN, a six-digit field, and a remove action behind a confirmation that says what removing it means. 0 clears it. The readout is re-read from `DEVICE_INFO` after a write, because the radio clamps and may refuse. That leaves the repeater session screen as the only D8.15 item still unscheduled. Test: `test/meshcore/contact_policy_test.dart`.
- R119 (2026-11-07, sixth part): **the radio can be restarted from the app.** `CMD_REBOOT` (0x13) was scheduled by D8.15 with a confirmation and never built, so a radio that had stopped answering its own screens could only be power-cycled by hand. It is a Diagnostics developer action: it asks first, the dialog says the link drops for a few seconds and anything queued on the radio is lost, and the snack after it says the command takes no reply — the reconnect is what proves it.
- R119 (2026-11-07, fifth part): **a contact as a link.** `CMD_EXPORT_CONTACT` (0x11) and `CMD_IMPORT_CONTACT` (0x12) were built and never sent, so a contact could only be shared by this app's own backup file. The radio's export is its own advert packet, and `meshcore://<hex>` carries exactly that, so a link made here imports into any MeshCore client: the node sheet copies one ("Share this contact"), and the radio-contacts screen takes one back ("Import a link") and lets the radio validate the packet, which is the only party that can. One export is in flight at a time, because the reply carries no key. Tests: `test/meshcore/contact_policy_test.dart` (the link is the packet, both spellings parse, a bad link is refused, and an import reads the table back).
- R119 (2026-11-07, fourth part): **four decoded frames that nothing handled.** A sweep of every `MeshcoreInbound` subclass against its callers (43 types, 10 unreferenced) found four that carried real information and were dropped: `PUSH_CODE_ONE_KEY_DM_REJECTED` (0x91) — the radio refused a stranger's message, so the sender never appears and the reader cannot tell an attempt from silence; now a RECENT-feed line with the key prefix. `RESP_CODE_DISABLED` (0x0F) — the command exists and is switched off on this radio, which used to look like no answer at all and cost a 15 s timeout on whatever was pending; it now claims the head at once with its own cause and copy. `RESP_CODE_TUNING_PARAMS` (0x17) — the radio's own duty-cycle limit (`1/(1+af)`), shown in Device configuration beside the app's meter, which until now had nothing to be read against. `RESP_CODE_TUNING_PARAMS` is read once per connection; the remaining six unreferenced frames are the refused ones (key export, signing) plus a CLI reply and raw-data push that belong to surfaces the app does not have. Tests: `test/meshcore/contact_policy_test.dart`.
- R119 (2026-11-07, third part): **the bands the radio will relay in.** `CMD_GET_ALLOWED_REPEAT_FREQ` (0x1A) was built and never sent, so a radio that hears a channel and refuses to repeat it was indistinguishable from a range problem. It is read once per connection and shown as one line among the radio's other own limits in Device configuration ("repeat: 902–928 MHz", or "none reported"). Test: `test/meshcore/contact_policy_test.dart` decodes two ranges.
- R119 (2026-11-07, second part): **route discovery, actively.** `PUSH_CODE_PATH_DISCOVERY_RESPONSE` (0x8D) was decoded and handled nowhere, so the app could show the route an advert happened to take but could not ask the mesh for one. The node sheet now offers "Find the route" (`CMD_SEND_PATH_DISCOVERY_REQ` 0x34): it floods a request, matches the answer by the node's prefix (only one in flight, because the reply names the prefix but not the request), and shows both directions, since an asymmetric link is the interesting answer. Costs airtime, so it is a tap. Tests: `test/meshcore/contact_policy_test.dart` (the reply, and a reply for another node being ignored).
- R119 (2026-11-07): **the protocol has no message id, and the queue re-sends.** A received message is identified only by its sender's prefix, the sender's timestamp and its text, and the radio re-delivers anything it never saw acknowledged. `_ingestDm`/`_ingestChat` appended it again, so a replayed DM or channel line appeared twice with nothing to tell a duplicate from a repeat. Both now keep a bounded memory of the last 64 ingested keys and drop the repeat (`test/meshcore/inbound_dedupe_test.dart`). The soak tool counts echoes off the **frames**, not off the history, so its duplicate and reorder measurements still see what the radio delivered — otherwise the dedupe would have made it report zero duplicates by construction. Also: an add (`CMD_ADD_UPDATE_CONTACT`) now takes the answer the radio gives it, so `ERR_CODE_TABLE_FULL` sets the same `contactsFull` state as the 0x90 push instead of the add reporting success while the contact was refused.
- R77: collapse groups draw header, content, then one closing rule (the rule used to sit between a header and its own content). Studio tints the header row with `raised` (`MmShape.tintedHeaders`). **Superseded by R116.**
- R116 (device-verified 2026-11-07): **one boundary, one mark.** The header fill is gone and so is the closing rule, on every preset: a group is a label under one rule in the border tier. R77's tint plus close rule drew a group boundary twice on the dark grounds (the previous group's rule sat directly above the next group's fill) and made a folded group a box bounded above and below; R115 had removed the fill on paper only. `MmShape.tintedHeaders` is deleted. Studio Light also stopped borrowing the SEELE dashboard: `DashboardHost` sent `studioLight` to the fallback arm, so switching from Studio Dark to Studio Light replaced the layout (colour-inverting slab, 88 sp numeral) instead of repainting it; both Studio presets now use `StudioDashboard`. Tests: `test/theme/section_header_test.dart`, `test/ui/mm_collapsible_test.dart`, `test/screens/dashboard_host_test.dart`. Measured on the handset: five rules on the dashboard in both grounds, one per boundary, identical y positions.
- R76: **every channel send was marked failed.** The firmware answers a channel text with `OK`, the app waited for `SENT`, so the 15 s watchdog failed 4 of 4 sends (also on pristine `origin/dev`). Pending sends now record the reply they expect and match by kind, oldest first. ERR fails the send at once with the device reason. Failed rows offer Retry. The chat row glyph repaints (selector deep-compared identical objects: `deliveryRevision`). **Unverified on a device.** Known limit: OK/ERR carry no tag, and commands that are not registered (setAdvertName, tools' OK commands) can still have their OK credited to a pending channel send.
- R75 (device pass): the RECENT rows of both dashboards used a fixed-width stamp column (70dp Studio / 64dp SEELE) narrower than their own 12pt `HH:MM:SS` mono stamp, so the stamp ran into the event text with no headroom for text scaling. Now `Text(stamp)` + 10dp gap + `Expanded`, which mono keeps aligned without a width.
- R75 (device pass): the splash subtitle was a hardcoded Japanese literal (`branded_splash_screen.dart:75`) while `appSubtitle` already had an English value, so an en-US device showed Japanese. Now `l.appSubtitle`, which resolves because the splash is the `home:` of a `MaterialApp` that installs the locale delegates.
- R73: Studio's dark basemap retuned (`0.8*inv+48`: land 61, sea 90, labels 220, 8.0:1) after R70's was too dark. **Needs a device look.**
- R72: Studio chat/DM rows follow words-sans / data-mono (`StudioMessageRow`):
  sender above body, timestamp + SNR/flood mono, `«`/`»` dropped for an accent
  rule on outgoing rows. Other presets unchanged. **Unverified on a device.**
- R71: Studio is uniformly square: Material buttons, FAB, menus and text
  fields (theme) plus 49 screen-drawn radii via `mmRadius` and the chat
  jump pill. Older presets unchanged. Guard: `test/ui/square_controls_guard_test.dart`.
  **Unverified on a device.**

**Known issues from the R68 critical pass (not fixed; read from code and phone screenshots)**
- Still English in the Japanese locale (after R69): the Diagnostics SEND /
  M6 interop / fixture-export / bot-soak panels (developer tooling, left
  in English on purpose). Other screens were not swept literal by literal;
  a grep for `Text('Latin...')` finds only brand marks, "BLE", hint URLs
  and the unused `about.dart`.
- R70 (device findings): edge swipe from the physical edge was Android
  system Back (bands now sit inside `systemGestureInsets`, not
  device-verified); the OSM credit line was covered by the no-fix banner
  (fixed); the map control column is 48dp and the band inset is derived;
  Studio draws the basemap dark (`MmShape.darkBasemap`).
- The six older dashboards still show two status displays (the dashboard's
  own slab and the app-bar chip) for one link state.
- `JetBrains Mono` is still hard-coded in about 85 places (ratcheted per
  file by `test/ui/type_rule_guard_test.dart`). R74 fixed the prose ones
  reachable under Studio. Left in mono on purpose (data, or HUD
  decoration of the older presets): dashboard_screen (older dashboards,
  Studio has its own), hex / PSK / JSON in channels and diagnostics,
  elevation and weather figures, mesh-tree and globe node labels,
  meshbook counts. Left although mixed: the DM header "Peer: <key>"
  (`dm_screen.dart`), node-detail "old key" line, the device-config block
  `mfr: / max contacts:` and the equal-grid "[ MESHMORE :: HYPERLOCAL ]"
  banner. **Unverified on a device.**
- Studio still uses the accent decoratively in places (about 35
  `color.accent`, 121 `cs.primary` uses); with the grey accent that is
  now a style question only, not a colour or contrast one.
- No serif face is bundled (only Saira and JetBrains Mono). Not added:
  a new font is a new asset with licence and size cost, and a serif at
  11-13 sp on a dark UI reads worse than the platform sans.

**Privacy (R62)**
- The periodic 60 s position-bearing self-advert is **opt-in** (App
  settings → Auto-publish location → *Periodic position beacon*, default
  off). With it off the SelfInfo poll sends `appStart` only — nothing over
  the air.

**Hyperlocal grid (R18/R25/R27) — 10 view modes**
- Its own primary tab, right after Nodes (issue #4). Disconnected, it
  shows the radar with no nodes and "Not Connected to Mesh". The chosen
  view is remembered for the session; every launch opens on the radar.
  A sideways swipe changes view, and a pan/zoom view that is in pan mode
  keeps every drag until you switch it back (R109); the view strip always
  switches too.
- **Map tab (R61)** — the street map viewer as its own page right after
  the grid, in every skin; the middle pans and zooms, and a 24 dp edge
  band on each side (R67) steps one view by an inward fling, because a pan
  surface is the one place a horizontal gesture cannot be free. A corner
  button opens Settings → Offline maps. Six views in all (R85).
- **Radial "radar"** — range rings (Room…Wide…**City…Region**, Region
  auto-frames the known extent), signal/bearing placement, compass rose
  + heading needle, **north-up/heading-up toggle**, prominent top
  **heading HUD**.
- **Weather (WX)** — environment telemetry at a glance: summary band
  (nodes reporting + min/avg/max temperature on a cold→hot ramp) + a
  warmest-first list of reporting nodes with temp/humidity/pressure +
  freshness; tap → node detail.
- **sns-cells** social heat map — time-decayed message density with
  **last-hour counts** on each square; **place echoes** (R54 inferred-
  place ◇ markers with last-hour ×count, edge-pinned when off-frame,
  + a dismissible "Places" list); a **scale stop** chip (Metro ~20 km /
  Region ~300 km / Mesh fit-all) so distant nodes (Seattle, Vancouver
  BC) can be framed instead of edge-pinned.
- Hyperlocal grid views, all at one level: radar, coverage survey (OSM
  tiles), street map, mesh tree (force-directed, hop slider, Flood as
  first-class), SNS cells, elevation profile. The globe was removed from the
  product on 2026-11-05.

**Telemetry & sensors**
- Self + peer telemetry via `CMD_SEND_TELEMETRY_REQ` / `0x8B`.
- Decodes GPS (alt) + **environment (temperature/humidity/pressure)**;
  surfaced in node detail, Nodes rows, the Fuji-san self chip, and the
  Weather view.
- **Background telemetry poller** (opt-in, App settings → "Gather node
  telemetry", default on): politely cycles synced contacts (one req per
  ~10 s, hop/distance-tiered, 3 attempts/contact, 15-min refresh, then
  quiet). Off = no telemetry traffic from us.
- Self-telemetry zero-prefix replies normalized to our own key; a
  `[telem]` diag log dumps received LPP types.
- Fuji-san polls **self** telemetry on load / on UPDATE (+ a phone-GPS
  one-shot so altitude resolves even when the device omits GPS alt).
- **Telemetry sharing** is a permission (Off/Contacts/Anyone per
  base/loc/env); the radio firmware answers other nodes' scans itself
  (`onContactRequest`, contact-only, base is the master gate). For
  "Contacts" mode, the Node detail sheet grants **per-contact telemetry
  permissions** (writes `contact.flags` via ADD_UPDATE_CONTACT) — the
  only lever the app has on the responder side.

**Tools (R60) — Settings → Tools (issue #7)**
- Radio stats, Ping, Trace path, Discover nearby, Soak test, Range
  test; spec in `meshmore-sns-tools-spec.md`.
- One tool holds the radio at a time and the background telemetry
  poller is held meanwhile (the firmware keeps one pending request).
  Tool requests don't disturb chat SENT/ACK correlation.
- Soak pairs with the R59 echo bot; Soak and Range refuse Public.
  Ping/Soak export JSON, Range exports CSV.
- **Unverified on hardware.** Frame layouts are from current MeshCore
  firmware source (newer than the codec pin); GET_STATS and discover
  need recent firmware and say so when missing.

**Offline maps (R61) — Settings → Offline maps (issue #5)**
- Disk tile cache behind every map view (street map, equal grid, fabric
  survey); region packs; GeoJSON event-map overlays; one storage
  budget; per-pack/layer expiry; setup online-only; downloads park
  while offline and resume on their own. Spec in
  `meshmore-sns-maps-spec.md`.
- **OSM and OpenTopoMap are view-cache only**: their tile policies
  forbid prefetch/offline. Packs come from USGS (US only) or a custom
  tile server the user marks as allowing offline download. Offline OSM
  in bulk is phase 2 (vector extracts).
- Street map's street/topo toggle is now a basemap picker; attribution
  shown on the map.
- **Self-test** (Offline maps → check icon): 11 end-to-end checks
  against the real servers, in a sandbox. All pass on the SH-53D
  (2026-10-15). Headless runner: `tool/maps_selftest_device.dart`.
  Not yet exercised by hand: map pan performance from disk, multi-MB
  packs, behaviour across days.

**Battery (R16)**
- Voltage → SoC via per-device OCV curve; observed-drain regression +
  rated-capacity cross-check; time-to-empty + confidence; persisted
  voltage history; dedicated Battery screen + dashboard summary.

**Docs (R53) — Settings row (R85/R86)**
- Offline reader for three sections: **Protocol** (MeshCore companion
  radio protocol), **Firmware** (MeshCore README, matched to the
  connected device's fw version), and **App** (self-authored).
- Offline-first snapshots baked in (`assets/docs/`), refreshed
  opportunistically from GitHub (`meshcore-dev/MeshCore`) and cached
  (SharedPreferences); App section never hits the network.
- Futuristic monospace rendering (tracked-caps headings + accent
  rules); markdown parsed with the `markdown` package, rendered to
  widgets in-app (images → alt text). Fetch seam is injectable/tested.

**Skin system (R55) — design-system foundation**
- A **skin is a bundle**, not just a palette: `MmSkin` = colour
  (`MmTokens`) + `MmType` + `MmShape` (sharp/rounded/**chamfer**) +
  `MmOrnament` (scanlines, corner brackets, hazard-stripe headers),
  resolved per preset via `mmSkinFor` and read through **`context.skin`**
  (high-contrast forces SEELE).
- **Bundled OSS type spine** (the brief's faces): **Saira** (Eurostile-
  class display) + **JetBrains Mono** (telemetry, **slashed-zero** via
  `FontFeature`) — variable fonts (~670 KB), OFL, attributed in About.
  Applied **app-wide**: `buildMmTheme` puts the skin's display face on
  the global `textTheme` (every screen, not just migrated components),
  and all telemetry/mono text uses JetBrains Mono.
- **Branded component library** (`lib/ui/`): `MmPanel`, `MmSectionHeader`,
  `MmReadout`, `MmStatusPill`, `MmListRow`, `MmScaffold` +
  `SkinChromePainter` (CRT scanlines + L brackets, suppressed under
  reduce-motion). `context.skin` falls back to SEELE when no
  `ThemeController` is above it, so migrating a screen never forces its
  test harness to wire one.
- **Two migration mechanisms, both proven:**
  1. **Per-skin layout fork** (for screens whose *metaphor* differs):
     the Dashboard is hosted by `DashboardHost`, which dispatches the
     **NERV Terminal** telemetry-grid vs the **SEELE monolith** from one
     `DashboardModel` (slot data).
  2. **Component-driven reskin** (one screen, all skins, no fork): the
     **Nodes** + **Chat** views are wrapped in `MmScaffold` and use the
     components (`MmListRow` cards; Chat's terminal-log mono rows) —
     chamfered + scanline under NERV, flat/clean under SEELE; same code,
     reskinned by bundle.
  Switch live in Personalization.
- **Visualisation painters follow the skin.** Audit finding: the 9 viz
  painters were **already theme-driven** — they read `ColorScheme`
  (which *is* the skin's tokens via `buildMmTheme`), with **zero**
  hardcoded brand-colour literals. Only residuals fixed: the sns-cells
  painter's heat/◇ literals → `VizPalette.of(skin)` (hot→alert,
  cool→fg, self/inferred→accent, grid→line), and two legend swatches →
  theme. Intentionally left theme-independent: the weather temperature
  ramp (a physical cold→hot scale) and the white map-marker outlines
  (cartographic contrast on full-colour OSM tiles).
- **NERV audio identity** (R12): the shared cue motifs read generic, so
  NERV got a bespoke **"Mission Control"** set — crisp upper-register
  messageIn blip, Geiger-counter **discovery ticks**, a descending
  **sawtooth klaxon** (alert ×2 / link-lost), ascending square link-up.
  Two new synth modes (`sweep`, `ticks`) in `brand/_audio_pack.py`
  (pure-stdlib). **Bug fixed:** `CueKind.discovery` had no trigger —
  now `CueBridge` fires it when a newly-heard node appears (suppressed
  during the post-connect sync flood), so the most distinctive NERV cue
  actually plays. (Verified the WAVs ship + audioplayers plays them, not
  the system-sound fallback.)
- _Migrated onto the components: Dashboard (fork), Nodes, Chat, **DM**,
  **Settings hub**, **About** (component-driven). Viz painters
  skin-following; fonts app-wide; NERV audio. Next: settings sub-screens
  + Docs/Battery, then concepts B/C/E/F bundles._

**Platform / settings / a11y**
- About → **Open-source licenses & attributions** (`showLicensePage`):
  bundled-asset licenses registered with `LicenseRegistry` — MeshCore
  docs (MIT), GeoNames cities (CC-BY 4.0), Natural Earth (public
  domain), OpenStreetMap (ODbL) — alongside all package licenses.
- Region presets (R39, baked-in), location settings, diagnostics +
  raw-frame log, personalization (themes, font scale, reduce-motion,
  high-contrast), voice/TTS (R5), per-theme audio cues (R12).

## Known constraints & caveats

- Most recent UI/paint changes are **verified by `flutter analyze` +
  the test suite, not a device render** — eyeball on hardware.
- **Environment telemetry is NOT available on the test device's current
  firmware (confirmed 2026-06-03 on hardware).** The T1000-E's BME280
  needs the MeshCore *sensor firmware* build; standard companion firmware
  sends only battery/GPS. Two independent signals confirmed this:
  1. Self-telemetry replies carry an **empty** CayenneLPP payload
     (`[telem] … types=` blank — no `0x67`/`0x68`/`0x73`).
  2. Writing a non-zero **Environment** value in device config
     (`SET_OTHER_PARAMS`) does not stick — the device **clamps the env
     bits back to 0** and echoes a `SelfInfo` with env=0. A firmware
     with the sensor in its telemetry path would accept the class.
  The app's encode (byte position, no clobber of base/loc) and decode
  (env at SelfInfo byte 46) were both verified correct — this is purely
  a device-side limitation, not an app bug. Resolution is to flash a
  MeshCore sensor firmware build; **no app change can surface data the
  radio never emits.** (BME280 also reads a few °C warm — sits by the
  electronics.) Further firmware investigation is the user's to pursue.
- Peer telemetry is **contact-only** (firmware drops requests for
  advert-only nodes); the background poller respects that.
- **The whole temperature chain (poller → decode → Weather view) is
  unverified on hardware** — it only shows data if a node's firmware
  actually transmits environment telemetry. Confirm via the WX view /
  `[telem]` logs before relying on it.
- The PUSH_CODE_ACK (0x82) wire format isn't in firmware docs we hold;
  decoded as the documented u32 tag, degrades to "sent" if a device
  differs.

## In progress / next

- **Telemetry & weather thrust:** Phase 1 (background poller) ✅ and
  Phase 2 (Weather view) ✅ shipped. **Phase 3 (per-node temperature
  trends / history + sparkline) is shelved** — the test device's
  firmware emits no environment telemetry (see constraints above), so
  there is no source to build history on. The decode/poller/WX chain is
  complete and will light up automatically if a sensor-firmware node
  joins the fabric. Re-open Phase 3 only once a node is confirmed
  transmitting `0x67`-class telemetry.
- **Settings toggle contrast** ✅ (v1.0.125+1) — `segmentedButtonTheme`
  + `chipTheme` give selected controls a solid-accent fill app-wide.

## Backlog (flagged, not started)

- **Block a key** _(specified 2026-11-04, not started)._ Spec: `../meshmore-sns-block-spec.md`.
  No firmware has a per-sender block or mute, so this is an app-side store keyed by the full
  32-byte public key, filtered on ten surfaces and on contact-list replay. Also needs the
  `0x91 PUSH_CODE_ONE_KEY_DM_REJECTED` decoder (keymind-only frame, 1 + 32 bytes) and an optional
  "also remove the contact" action. Copy must name what a block cannot stop.
- **Real per-feature app docs ("online-help-md")** _(noted, not started)._
  The Docs → App section currently points at `assets/docs/app.md`, a
  single **summary** doc. Replace it with proper per-feature help —
  a new `online-help-md` doc set **with screenshots** — documenting each
  feature, not one overview page. Leave `app.md` in place for now; build
  the real docs as a follow-up. Docs is a Settings row (R86), not a tab.


- **R54 — place names in messages** — changed from plotting to offering.
  The grid layer that drew these mentions as ghost markers was deleted with
  the rest of the hyperlocal views, which left the per-channel switch
  controlling nothing and its copy describing a screen that no longer exists.
  A message that names a place now gets one line under the row: the
  gazetteer's name, **Report place** (opens the place sheet at the user's own
  position, label prefilled) and **Dismiss** (remembered per text, bounded to
  200 entries, stored as hashes). No coordinates are derived from the words.
  `PlaceInferenceEngine.placeNames` is the name-only path; `infer` remains for
  placing a weather observation. `InferredPlaceStore` and the arrival-time
  marker pass are deleted with the layer that read them.


- **lobospeak** — closed-network robot control plane over MeshCore
  binary req/resp (design doc exists in `meshmore-sns/`). The big one.
- **F2** — map alternatives. **F3** — AI integrations. (Both flagged
  only; need specifics before design.)
- `responsive-iot-2026` generic starter branch — complete & local-only;
  not pushed to origin.
