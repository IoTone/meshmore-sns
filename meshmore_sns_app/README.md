# Meshmore SNS — app

Offline-first Flutter client for MeshCore LoRa mesh radios over BLE.
Mesh-first, no backend. Localized EN + JA.

This directory is tracked in the parent repository, not a submodule.

## Where the documentation lives

| Document | What it holds |
|---|---|
| [`../README.md`](../README.md) | Project overview, doc map, repository layout |
| [`../meshmore-sns-spec.md`](../meshmore-sns-spec.md) | Requirements (R1–R24) and the change record (R29–R108) |
| [`../meshmore-sns-UX-spec.md`](../meshmore-sns-UX-spec.md) | U0–U15 implementation plan and the six skins (historical plan, see its header) |
| [`../meshmore-sns-maps-spec.md`](../meshmore-sns-maps-spec.md) | Basemaps and offline region files (R61, R93) |
| [`../meshmore-sns-tools-spec.md`](../meshmore-sns-tools-spec.md) | Tools surface (R60) |
| [`../meshmore-sns-radio-alerts.md`](../meshmore-sns-radio-alerts.md) | Radio chime in firmware, per-board matrix, silence patch |
| [`../meshmore-sns-architecture.md`](../meshmore-sns-architecture.md) | The design of record, including the responsibility matrix (§13) |
| [`../meshmore-sns-architecture-audit.md`](../meshmore-sns-architecture-audit.md) | The audit trail, append-only |
| [`STATUS.md`](STATUS.md) | What is built, what is open, test counts |
| [`responsive_starter_app/assets/docs/`](responsive_starter_app/assets/docs/) | In-app offline docs (Protocol, Firmware, App) |

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
    │   ├── theme/             ← skins (NERV, AG-HUD, Hyperlocal, SEELE, DR Pop, Recon, Studio)
    │   ├── maps/              ← tiles, style, offline packs, region files
    │   ├── ui/                ← shared components (MmListRow, MmAction, showMmPicker…)
    │   └── l10n/              ← ARB files (app_en.arb, app_ja.arb)
    ├── test/                  ← 1016 widget/unit tests
    └── android/, ios/         ← platform shells
```

## Build and test

```sh
cd responsive_starter_app

flutter pub get
flutter analyze                 # clean: no errors, no warnings
flutter test                    # 1016 tests, ~83 s
flutter build apk --debug       # Android debug APK

# Toolchain floor with Flutter 3.47.4, enforced by dev.flutter.flutter-gradle-plugin:
# Gradle 8.14+, AGP 8.11.1+, Kotlin 2.2.20+. Older pins are refused outright, not
# warned about, so the build stops before any APK is produced.
flutter run -d <device>         # install on a device
```

- Known analyzer warnings: `lib/maps/maps_controller.dart` (two
  `unawaited_return_in_try_block`).
- Android APK output: `build/app/outputs/flutter-apk/app-debug.apk`.
- iOS builds need a Mac with Xcode and CocoaPods.

## Conventions

- **Strings**: every user-facing string goes through ARB, EN and JA updated in
  lock-step, then `flutter gen-l10n`. No revision tags or placeholder text in
  shipped strings.
- **Themes**: behaviour is generalized through `MmTokens` / `MmType` / `MmShape`,
  not forked per theme. Read tokens through `context.skin` in build and
  `context.skinRead` in event handlers.
- **Navigation**: six views in one `PageView` with `NeverScrollableScrollPhysics`.
  The view strip is the only switcher (tap jumps, vertical drag steps one).
  Panning surfaces keep their edge bands.
- **Surfaces**: `showMmPicker` for pick-one-of-N, a bottom sheet for a choice
  that ends where it started, a routed page for a destination with its own
  state.
- **Radii**: `mmRadius(context, n)` and `kSquareRadius` (1 px, not 0).
