# MeshMore SNS — toolchain and verification commands

The one page a child reads before it runs anything. Every number here was measured on this machine; when a number
moves, the line moves with it and the old value goes into the commit message, not into a second table.

Measured 2026-11-05 at `c7ea6ca` (branch `feat/app-completion`), phone `ZD222W34LJ` attached.

---

## 1. Environment

```bash
export PATH="/nix/store/x8cc2489gk0lhbgm5q3y7pxfb7v9r706-flutter-wrapped-3.47.4-sdk-links/bin:$PATH"
export JAVA_HOME=/home/ldeen/.local/jdk/jdk-21.0.12+8
export ANDROID_HOME=$HOME/Android/Sdk
export ANDROID_USER_HOME=/home/ldeen/.config/.android   # build only
```

| Tool | Value | Verified by |
| --- | --- | --- |
| Flutter | 3.47.4 stable, Dart 3.13.3, DevTools 2.60.0 | `flutter --version` |
| `dart` | 3.13.3, beside `flutter` on the exported PATH | `dart --version` |
| JDK | Temurin 21.0.12+8 at `/home/ldeen/.local/jdk/jdk-21.0.12+8` | `java -version` |
| adb | 1.0.41 / 34.0.5-debian at `/usr/bin/adb` | `adb version` |
| Gradle / AGP / Kotlin | 8.14.3 / 8.11.1 / 2.2.20 | `android/gradle/wrapper/gradle-wrapper.properties:6`, `android/settings.gradle:26-27` |
| Application id | `com.iotone.meshmore_sns_app` | `android/app/build.gradle.kts` |
| App version | `1.0.197+13` | `pubspec.yaml:19` |

**Only the `-sdk-links` wrapper works.** The plain nix wrapper writes into its own read-only store path and dies with
`flutter failed to create a directory at .../bin/cache/artifacts`. There is no `flutter` on the default PATH, so every
command needs the export above; a bare `flutter` is a mistake, not a missing install.

**`JAVA_HOME` is mandatory** for anything Gradle touches (the app build and `libmeshcore`). Without it Gradle picks a
JDK the pins do not accept.

Flutter prints one advisory on every build: Kotlin 2.2.20 support "will soon be dropped … at least 2.3.20". It is a
warning, the build is green, and the bump belongs to the store-readiness wave, not to a feature commit.

---

## 2. Tests, and what they cost

Run from `meshmore_sns_app/responsive_starter_app/` unless stated.

| Scope | Command | Measured |
| --- | --- | --- |
| One file | `flutter test test/meshcore/ble_adopt_bond_test.dart` | **4.9 s**, 10 tests |
| One subtree | `flutter test test/theme` | **7.5 s**, 36 tests |
| Full app suite | `flutter test` | **71.6 s**, **1016 tests**, all passed |
| Protocol package | `cd ../packages/meshcore && dart test` | **2.7 s**, 312 passed, 1 skipped |
| Java port | `cd ../../../libmeshcore && ./gradlew test --offline` | **4.7 s**, 143 tests, 0 failures |

- **A test file that takes more than ~5 s is a defect to report, not to live with.** `test/shell/home_shell_test.dart`
  is the known offender (~12–14 s: it builds six skins' worth of shells). Fixing it is a named task, not a side effect.
- Run targeted files while iterating and the full suite once, at the end of a task. Two full suites at once on this box
  thrash each other and both look slow.
- The Java port's test task is incremental: the first run after a clean checkout is much slower than 4.7 s (it compiles
  the module and resolves plugins). `--offline` works because the cache is warm; drop it only if a dependency changed.
- `flutter analyze` must stay at **two** warnings, both pre-existing: `lib/maps/maps_controller.dart:1008` and `:1013`
  (`unawaited_return_in_try_block`). Anything else that appears is yours. Analyzer run: 3–5 s.

---

## 3. Build, install, run, and see

```bash
cd meshmore_sns_app/responsive_starter_app
flutter build apk --debug                       # 13.7 s warm; minutes cold
adb -s ZD222W34LJ install -r build/app/outputs/flutter-apk/app-debug.apk
for p in android.permission.BLUETOOTH_SCAN android.permission.BLUETOOTH_CONNECT \
         android.permission.ACCESS_FINE_LOCATION android.permission.ACCESS_COARSE_LOCATION \
         android.permission.POST_NOTIFICATIONS; do
  adb -s ZD222W34LJ shell pm grant com.iotone.meshmore_sns_app $p
done
adb -s ZD222W34LJ shell am start -n com.iotone.meshmore_sns_app/.MainActivity
```

Evidence channels:

```bash
adb -s ZD222W34LJ logcat -c                                   # before you act
PID=$(adb -s ZD222W34LJ shell pidof com.iotone.meshmore_sns_app | tr -d '\r')
adb -s ZD222W34LJ logcat -d --pid=$PID \
  | grep -E 'flutter :|\[meshcore|\[telem|\[place|BluetoothGatt'
adb -s ZD222W34LJ exec-out screencap -p > /tmp/shot.png
adb -s ZD222W34LJ shell uiautomator dump /sdcard/ui.xml && adb -s ZD222W34LJ pull /sdcard/ui.xml /tmp/
adb -s ZD222W34LJ shell run-as com.iotone.meshmore_sns_app cat shared_prefs/FlutterSharedPreferences.xml
adb -s ZD222W34LJ shell dumpsys bluetooth_manager | sed -n '/Bonded devices:/,/^$/p'
adb -s ZD222W34LJ shell dumpsys activity services com.iotone.meshmore_sns_app
```

What the log tags mean: `flutter :` is anything the app prints, `[meshcore...]` the protocol client, `[telem`/`[place`
the telemetry and places paths, `BluetoothGatt` the platform link. A silent log with no `[meshcore` line after a
connect attempt is a finding, not a passing test.

**The screen must be awake and unlocked, and it is not always.** `adb shell input keyevent 26` turns the display on,
but this phone has a secure PIN keyguard: while it is up, `mCurrentFocus` is `NotificationShade`, the app's activity
sits at `mLastPausedActivity` with `visibleRequested=false`, and `uiautomator dump` returns the keyguard, not the app.
No adb command dismisses a secure keyguard. So a UI capture needs the PIN entered by hand; ask for it in one batched
request rather than trying three more gestures. The process, the Dart VM and the radio link keep running behind the
keyguard, so logcat evidence is still valid while the screen is locked.

---

## 4. Bench radios

Two MeshCore companions are bonded to this phone: `MeshCore-HELTEC-BASE` and `MeshCore-WIOld`. The bench repo is
`/home/ldeen/Documents/lora/` (flash and inventory), the serial node is `/dev/ttyACM0`. **Software must work with any
radio**: nothing in the app may assume a particular device name, firmware build or profile count.

---

## 5. What a child must not do

- Do not edit `lib/gen/**` by hand. Change `lib/l10n/app_en.arb` and `app_ja.arb` in lockstep and run
  `flutter gen-l10n`; the generated files are reproducible byte-for-byte from the ARBs.
- Do not use the plain nix wrapper, and do not rely on a bare `flutter` being on PATH.
- Do not commit a red tree, and do not run the full suite twice in parallel on this machine.
- Do not run a second writer in a checkout another child is editing. Use a `git worktree` (`git worktree add -b <name>
  /home/ldeen/Documents/meshmore-sns-<name> HEAD`) and commit there.
- Do not push. Nothing leaves this machine without an explicit instruction.
