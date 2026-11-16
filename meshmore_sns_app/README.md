# Meshmore SNS — app

Offline-first Flutter client for MeshCore LoRa mesh radios over BLE.
Mesh-first, no backend. Localized EN + JA.

This directory is tracked in the parent repository, not a submodule.

## Where the documentation lives

| Document | What it holds |
|---|---|
| [`../README.md`](../README.md) | Project overview, doc map, repository layout |
| [`../meshmore-sns-spec.md`](../meshmore-sns-spec.md) | Requirements R1–R117 and their change record. R118 onward live in [`STATUS.md`](STATUS.md), which is the current change log |
| [`../meshmore-sns-UX-spec.md`](../meshmore-sns-UX-spec.md) | U0–U15 implementation plan and the six original skins (historical plan; the app now ships eleven presets) |
| [`../meshmore-sns-maps-spec.md`](../meshmore-sns-maps-spec.md) | Basemaps and offline region files (R61, R93) |
| [`../meshmore-sns-tools-spec.md`](../meshmore-sns-tools-spec.md) | Tools surface (R60) |
| [`../meshmore-sns-radio-alerts.md`](../meshmore-sns-radio-alerts.md) | Radio chime in firmware, per-board matrix, silence patch |
| [`../meshmore-sns-architecture.md`](../meshmore-sns-architecture.md) | The design of record, including the responsibility matrix (§13) |
| [`../meshmore-sns-architecture-audit.md`](../meshmore-sns-architecture-audit.md) | The audit trail, append-only |
| [`STATUS.md`](STATUS.md) | What is built, what is open, and the one dated test count every other document defers to |
| [`responsive_starter_app/assets/docs/`](responsive_starter_app/assets/docs/) | In-app offline docs: Protocol, Firmware, App and Devices |

## Layout

```
meshmore_sns_app/
├── STATUS.md                  ← status and change log
├── packages/meshcore/         ← pure-Dart protocol codec (no Flutter deps)
└── responsive_starter_app/    ← the Flutter app
    ├── lib/
    │   ├── meshcore/          ← controller facade over BLE + protocol
    │   ├── screens/           ← routed pages and the shell tabs
    │   ├── shell/             ← HomeShell, view strip, boot overlay
    │   ├── theme/             ← eleven presets (NERV, AG-HUD, Hyperlocal, SEELE, DR Pop, Recon, Studio, Studio Light)
    │   ├── maps/              ← tiles, style, offline packs, region files
    │   ├── ui/                ← shared components (MmListRow, MmAction, showMmPicker…)
    │   └── l10n/              ← ARB files (app_en.arb, app_ja.arb)
    ├── test/                  ← widget and unit tests, with the count in STATUS.md
    └── android/, ios/         ← platform shells
```

## Build and test

```sh
cd responsive_starter_app

flutter pub get
flutter analyze                 # must report no issues at all
flutter test                    # the whole suite, about three minutes
flutter build apk --debug       # Android debug APK

# Toolchain floor with Flutter 3.47.4, enforced by dev.flutter.flutter-gradle-plugin:
# Gradle 8.14+, AGP 8.11.1+, Kotlin 2.2.20+. Older pins are refused outright, not
# warned about, so the build stops before any APK is produced.
flutter run -d <device>         # install on a device
```

- Android APK output: `build/app/outputs/flutter-apk/app-debug.apk`.
- iOS builds need a Mac with Xcode and CocoaPods.

## Conventions

- **Strings**: every user-facing string goes through ARB, EN and JA updated in
  lock-step, then `flutter gen-l10n`. No revision tags or placeholder text in
  shipped strings.
- **Themes**: behaviour is generalized through `MmTokens` / `MmType` / `MmShape`,
  not forked per theme. Read tokens through `context.skin` in build and
  `context.skinRead` in event handlers.
- **Navigation**: six views, paged by a horizontal swipe on the body. The view
  strip is always there as well (tap jumps in one frame, vertical drag steps one
  view), and a surface that needs the drag takes it: the Map while it is current,
  and the grid while a pan/zoom view is in pan mode.
- **Surfaces**: `showMmPicker` for pick-one-of-N, a bottom sheet for a choice
  that ends where it started, a routed page for a destination with its own
  state.
- **Radii**: `mmRadius(context, n)` and `kSquareRadius` (1 px, not 0).
