# Bottom-edge audit — MeshMore SNS

**Verdict: the bottom edge is not handled. The app is edge-to-edge, nothing in `lib/` ever reads the device's bottom inset, and on the handset the last row of the Settings list, the last card of the Nodes list, the grid's transport bar and the map's attribution are all clipped by, or sitting inside, the system navigation area.**

---

## The measurement this rests on

Not inferred — read off the handset (`ZD222W34LJ`) while the app was running:

| Fact | Value | Source |
|---|---|---|
| Navigation mode | `2` = **gesture** | `adb shell settings get secure navigation_mode` |
| Navigation bar frame | `[0,2340][1080,2400]` → **60 px = 24 dp** | `dumpsys window displays`, `InsetsSource type=navigationBars` |
| App window frame | `[0,0][1080,2400]` → **full screen, edge-to-edge** | `dumpsys window windows`, `Window{a1a689 … MainActivity}` |
| Cutout mode | `layoutInDisplayCutoutMode=always` | same |
| `targetSdkVersion` | **36** | `android/app/build.gradle:76` |
| Density | 2.5 (400 dpi) | `wm density` |

Two consequences:

1. **The app draws behind the system bars.** `MediaQuery.padding.bottom` is **24 dp** on this phone and **48 dp** on a three-button phone. Both are real, and the app must handle both.
2. **`Scaffold` does not do it for you here.** In the Flutter SDK, `scaffold.dart:3023-3032` passes `removeBottomPadding: widget.bottomNavigationBar != null || widget.persistentFooterButtons != null`. This app has **neither anywhere** (`grep -rn "bottomNavigationBar\|persistentFooterButtons\|bottomSheet:" lib/` → no hits), so the body keeps `padding.bottom` and nothing applies it. The framework *does* handle the FAB (`floating_action_button_location.dart:565-570`, via `minViewPadding.bottom`) and SnackBars (`scaffold.dart:1230-1240`), and the keyboard (`removeBottomInset: _resizeToAvoidBottomInset`). It does **not** handle body content, scroll views, `Positioned` children, or sheet content.

**`grep -rn "padding\.bottom\|viewPadding\|paddingOf(" lib/ --include=*.dart` returns zero hits.** The app has never read the bottom inset. The only bottom-inset handling in the whole codebase is 27 `SafeArea` widgets, and 22 of those are inside bottom sheets.

### Photographed on the device

| Screen | What the screenshot shows |
|---|---|
| Settings (scrolled to end) | The last row, **About**, is cut off at the screen edge; its bottom border is not drawn and the gesture handle is painted over the card. |
| Nodes (scrolled) | The last card, **RevPeater**, is cut off; the handle is painted over it. |
| Grid → Radar | The transport bar (`⏸ 15s ▾ Auto ▾`) is the last row; its 48 dp tap targets extend into the 24 dp gesture zone. |
| Map | The attribution **"USGS The National Map"** and the compass legend **"The arrow is this phone's compass…"** are clipped mid-line by the screen edge, with the handle over the legend. |
| Dashboard (hyperlocal) | The status rail's text clears the handle by luck: its bottom padding is `sectionGap` = 24 dp, exactly the gesture inset — and **half** the 48 dp three-button inset. |

---

## Ranked findings

Severity: **breaks** = content is unreachable or clipped today; **wrong** = it is inside the system area and will be clipped on the other navigation mode; **risky** = a literal stands in for the inset and will drift.

| # | Sev | Where | `file:line` | Mechanism found | What goes wrong |
|---|---|---|---|---|---|
| 1 | **breaks** | `MmScaffold` — the shared screen wrapper, **41 call sites** | `lib/ui/mm_scaffold.dart:13-62` (body at `:28-30`, `Stack` at `:42-57`) | **NONE.** Paints a ground, a transparent `Material` and skin chrome; no `SafeArea`, no inset read. | Every screen built on it ends at the physical bottom. On gesture nav the last 24 dp is under the handle; on three-button nav the last 48 dp is under the bar. This is the single cause of findings 5, 6 and most of 10. |
| 2 | **breaks** | Map — attribution + compass legend | `lib/screens/street_map_view.dart:1661-1664` — `Positioned(left: 0, right: 0, bottom: 0, child: Column(...))` | **NONE.** `bottom: 0` is the physical bottom. | The OSM/USGS attribution — a licence obligation — and the compass legend are clipped and under the handle. Photographed. |
| 3 | **breaks** | Grid — transport bar | `lib/screens/grid_screen.dart:1137` (`if (_hasTransport) _transportBar(...)` as the last child of a `Column`); bar built at `:450-460` with `Padding(fromLTRB(4, 0, 8, 0))` | **NONE.** Zero bottom padding. | Play/pause, the interval picker and the range chip sit in the gesture zone; their 48 dp targets overlap the system swipe area. Photographed. |
| 4 | **breaks** | Dashboard — status rail (hyperlocal) | `lib/screens/dashboards/hyperlocal_dashboard.dart:197` (last child of the `Column`); padding at `:745-747` = `sectionGap` | **A literal that happens to equal the gesture inset.** `sectionGap` = `step(8)` = **24 dp** (`lib/theme/mm_skin.dart:138`). | Clears the 24 dp handle by exactly zero margin; on three-button nav (48 dp) the rail's text is **under the bar**. |
| 5 | **wrong** | Settings hub list | `lib/shell/home_shell.dart:577-580` — `padding: cardRows ? const EdgeInsets.fromLTRB(12, 8, 12, 12) : EdgeInsets.zero` | **A literal 12 dp.** | 12 dp of padding against a 24 dp inset: the last row is 12 dp inside the handle. Photographed clipped. |
| 6 | **wrong** | Nodes list | `lib/screens/nodes_screen.dart:495-498` — same `fromLTRB(12, 8, 12, 12)` / `EdgeInsets.zero` | **A literal 12 dp.** | Same as 5. Photographed clipped. |
| 7 | **wrong** | Dashboards — the four `ListView` skins | `aghud_dashboard.dart:78-79`, `drpop_dashboard.dart:55-56`, `nerv_dashboard.dart:36-37`, `studio_dashboard.dart:57-58` | **`sectionGap` = 24 dp** bottom padding. | Same arithmetic as 4: flush on gesture nav, 24 dp short on three-button nav. |
| 8 | **wrong** | Meshbook sheet | `lib/screens/chat_screen.dart:352-360` — `showModalBottomSheet(isScrollControlled: true)` → `SizedBox(height: MediaQuery.sizeOf(ctx).height * 0.7)` | **NONE.** No `SafeArea`, no `MmSheetBody`. The inner `MeshbookView` list has `fromLTRB(14, 14, 14, 24)` (`meshbook_view.dart:48`). | The sheet is 70 % of the screen and anchored to the bottom; its last row is 24 dp from the physical bottom, i.e. flush on gesture nav and 24 dp under the bar on three-button nav. |
| 9 | **wrong** | Device-config region picker | `lib/screens/device_config_screen.dart:295-303` — `DraggableScrollableSheet` → `ListView(padding: fromLTRB(16, 12, 16, 24))` | **NONE.** No `SafeArea`. | Same as 8. |
| 10 | **wrong** | Place-create sheet | `lib/places/place_create_sheet.dart:134-140` — `bottom: MediaQuery.viewInsetsOf(context).bottom + skin.space.step(5)` | **Keyboard only.** `viewInsets` is the keyboard; `padding` is the system bar. | With the keyboard closed the sheet's last row is `step(5)` = 12 dp from the physical bottom — inside the handle. This is the one sheet that *looks* like it handles insets and does not. |
| 11 | **risky** | Boot overlay | `lib/shell/boot_overlay.dart:318-321` (`bottom: 96`), `:335-337` (`bottom: 16`) | **Literals.** | The Skip button is 16 dp from the physical bottom — inside the handle on gesture nav, well inside the bar on three-button nav. |
| 12 | **risky** | Floating overlays with literal bottom offsets | `mesh_tree_view.dart:513-516` (`bottom: 12`), `sns_cells_view.dart:293-295` and `:319-321` (`bottom: 12`), `elevation_profile_view.dart:341-344` (`bottom: 8`), `chat_screen.dart:1061-1063` (`bottom: 12`, the jump-to-newest pill), `street_map_view.dart:1774-1776` (`bottom: 92`, the density chip) | **Literals.** | Each is 8-12 dp inside the gesture zone. The map's density chip at `bottom: 92` is the only one with real clearance, and it is clearance from a number, not from the inset. |
| 13 | **risky** | The map is outside the shared wrapper | `lib/screens/map_screen.dart:52-61` — `Column` → `Expanded` → `StreetMapView`, **no `MmScaffold`** | **NONE.** | A fix in `MmScaffold` does not reach the map; it needs its own (finding 2). |
| 14 | **risky** | The only code that reads `systemGestureInsets` is dead | `lib/ui/mm_edge_swipe.dart:39-130`; `_band` uses `insets.top`/`insets.bottom` at `:94-95`, and `build` reads `systemGestureInsets` at `:120-121` | **Correct thinking, zero call sites.** `grep -rn "MmEdgeSwipe(" lib/` finds only its own constructor. | The horizontal gesture insets are handled in a widget nothing mounts. The shell's `PageView` drag (`home_shell.dart:360-372`) therefore starts inside the system Back zone. |

### Handled — checked, not findings

| Where | `file:line` | Why it is fine |
|---|---|---|
| Chat composer | `lib/screens/chat_screen.dart:1077` | `SafeArea(top: false)` around the composer row. |
| DM composer | `lib/screens/dm_screen.dart:471` | Same, and the comment says so. |
| `MmSheetBody` | `lib/ui/mm_components.dart:958-975` | `Padding(viewInsets.bottom)` + `SafeArea(top: false)` + a height taken from the free space. |
| `showMmPicker` | `lib/ui/mm_components.dart:832-846` | `SafeArea(top: false)` + `ListView(padding: only(bottom: 12))`. |
| FAB | `lib/screens/networks_screen.dart:72` | Framework: `floating_action_button_location.dart:565-570` uses `minViewPadding.bottom`. |
| SnackBars (107 call sites) | — | Framework: `scaffold.dart:1230-1240`; `fixed` applies a `SafeArea`, `floating` uses `minViewPadding.bottom`. |
| First-run intro | `lib/screens/first_run_intro_screen.dart:86` | `body: SafeArea(...)`. |
| Branded splash | `lib/splash/branded_splash_screen.dart:54` | `body: SafeArea(...)`. |
| Boot failure | `lib/app/boot_guard.dart` | `Scaffold` with a centred column; nothing is bottom-anchored. |

---

## What one shared fix would repair

**Insertion point A — `lib/ui/mm_scaffold.dart:28-30`.** Apply the inset and then *consume* it, so a nested `SafeArea` cannot double-count:

```dart
final double bottom = MediaQuery.paddingOf(context).bottom;
final Widget body = Padding(
  padding: EdgeInsets.only(bottom: bottom),
  child: MediaQuery.removePadding(
    context: context,
    removeBottom: true,
    child: padding == null ? child : Padding(padding: padding!, child: child),
  ),
);
```

The `ColoredBox` stays outside the padding, so the skin's ground still fills the whole screen. `removePadding` is what makes this safe: the chat and DM composers already wrap themselves in `SafeArea(top: false)`, and after this they see `padding.bottom == 0` and add nothing.

**Repairs: 41 call sites, 36 screens** — every screen in the app except the map, the first-run intro, the splash and the boot-failure screen (the last three already `SafeArea`). That is findings **1, 4, 5, 6, 7** and most of **12** in one edit.

**Insertion point B — `lib/screens/street_map_view.dart:1661-1664`.** `bottom: 0` → `bottom: MediaQuery.paddingOf(context).bottom`. Repairs finding **2** (and the map's density chip at `:1776` should become `bottom: 92 + inset`).

**Insertion point C — the two unguarded sheets.** `chat_screen.dart:356` and `device_config_screen.dart:297`: wrap the body in `SafeArea(top: false)` (or `MmSheetBody`, which also handles the keyboard). Repairs findings **8, 9**.

**Insertion point D — `lib/places/place_create_sheet.dart:139`.** `viewInsets.bottom` → `viewInsets.bottom + padding.bottom` (or `max` of the two, since the keyboard already covers the bar). Repairs finding **10**.

**Insertion point E — `lib/shell/boot_overlay.dart:321, 337`.** `bottom: 96 + inset`, `bottom: 16 + inset`. Repairs finding **11**.

Total: **5 insertion points, ~46 call sites, 14 findings.**

---

## What cannot be fixed by one shared fix

1. **The map** (`map_screen.dart:52-61`) — it is the one screen that does not use `MmScaffold`, because its content is full-bleed and it wants no ground colour. It needs insertion point B.
2. **The two unguarded sheets** — a sheet is not inside `MmScaffold`; `showModalBottomSheet` preserves `padding.bottom` in the sheet's `MediaQuery` (`bottom_sheet.dart:1167-1169`: `useSafeArea: false` → `MediaQuery.removePadding(removeTop: true)`), so the sheet body must apply it itself.
3. **The floating overlays with literal offsets** (finding 12) — each is a `Positioned` inside a `Stack` that is not a `Scaffold` body, so no wrapper sees them. They need the literal replaced by `literal + inset`, one at a time. They are cosmetic (a pill, a legend, a chip) rather than unreachable, which is why they rank below the lists.
4. **The horizontal gesture insets** (finding 14) — `systemGestureInsets` is a different inset from `padding.bottom`, and the only code that reads it is unmounted. Fixing it means either mounting `MmEdgeSwipe` or reading `systemGestureInsets` in the shell's `PageView` drag. That is a gesture decision, not a padding one.
5. **The `sectionGap` coincidence** (findings 4, 7) — `sectionGap` is a *rhythm* token (24 dp, the gap between groups). It is not an inset and must not become one: if it were raised to 48 dp to clear a three-button bar, every dashboard would gain 24 dp of dead space on every gesture phone. The inset has to be added *on top of* the rhythm, which is exactly what insertion point A does.

---

## The guard that is missing

**Nothing in the suite would notice a control sliding under the handle.** Every `MediaQueryData(...)` in `test/` sets only `textScaler` — `grep -rn "MediaQueryData(" test/` returns 20 hits, none with `padding` or `viewPadding`. `test/screens/a11y_floors_test.dart:148-149` pumps `MediaQueryData(textScaler: TextScaler.linear(2.0))` and nothing else. `test/ui/mm_sheet_body_test.dart:31-40` sets `viewInsets` (the keyboard) and deliberately no `padding`, with a comment explaining that a `Scaffold` would consume it — correct for that test, and it is the only test that thinks about insets at all.

**The smallest test that would catch it** — one file, `test/ui/bottom_inset_test.dart`, three cases:

1. **The shared wrapper.** Pump `MmScaffold(child: SizedBox.expand())` inside `MediaQuery(data: MediaQueryData(padding: EdgeInsets.only(bottom: 48)))` with no `Scaffold`, and assert the child's `Rect.bottom <= 800 - 48`. This is the regression test for insertion point A, and it fails today.
2. **No double-count.** Pump `MmScaffold(child: SafeArea(top: false, child: SizedBox(key: k, height: 40)))` with the same 48 dp padding and assert the child's bottom is `800 - 48`, not `800 - 96`. This is the test that keeps the chat composer from gaining 24 dp of dead space.
3. **The map's bottom column.** Pump `StreetMapView` (or the attribution column alone) with a 48 dp bottom padding and assert the attribution's `Rect.bottom <= 800 - 48`.

A fourth, cheap and worth having: a **source guard** in the style of `test/ui/tap_affordance_guard_test.dart` — assert that no file under `lib/screens/` contains `Positioned(` with a literal `bottom:` and no `paddingOf`/`SafeArea` in the same widget. That is the only way to stop finding 12 from coming back one overlay at a time.

---

## Could not determine

- **Whether the three-button bar is 48 dp on this device.** The phone is in gesture mode (`navigation_mode = 2`), so the 48 dp figure is the Android platform default for a three-button bar, not a measurement from this handset. The arithmetic in findings 4, 5, 6, 7, 8, 9, 10 assumes it; if a given OEM ships a 44 dp or 56 dp bar the numbers move, and the *conclusion* (a 12-24 dp literal cannot cover a 48 dp bar) does not.
- **Whether any screen is reached only through a route that supplies its own `Scaffold` with a bottom bar.** I checked `grep -rn "bottomNavigationBar\|persistentFooterButtons\|bottomSheet:" lib/` and found none, but I did not trace all 29 routes in `lib/app/router.dart` to confirm each destination's `Scaffold` shape.
- **The `PageView`'s own bottom behaviour.** `home_shell.dart:360-372` builds a `PageView` of screens; I confirmed each child screen carries its own `MmScaffold`, but I did not verify whether `PageView` clips a child that overflows its viewport, which would change whether a fix at insertion point A is visible or merely correct.
- **The `_ViewStrip`'s top clearance.** It is `AppBar.bottom` (`home_shell.dart:340`) with `preferredSize` 56 dp (`:404`), and `AppBar` handles the top inset, so I did not treat it as a bottom finding — but I did not measure the strip's tap targets against the status bar on the device.
