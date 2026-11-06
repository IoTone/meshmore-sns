# Publishing Meshmore SNS

The Android build is the only shipping target. iOS is deferred, and the desktop
runners were removed with the bridge-era code.

Everything below was verified on 2026-11-05 against commit `ede4a9c5`'s tree. A
step is marked **verified** when it was run, and **yours** when it needs the
publisher's key or console.

## 1. Signing (yours)

The release variant refuses to build without a key, on purpose: signing a
release with the public debug key produces an artifact Play rejects on its first
check, so the build stops instead.

1. Create the upload key once and keep two backups off this machine:

   `keytool -genkeypair -v -keystore upload.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload`

2. Copy `meshmore_sns_app/responsive_starter_app/android/key.properties.example`
   to `android/key.properties` beside it and fill in `storeFile`
   (relative to `android/app/`, so `../upload.jks`), `storePassword`,
   `keyAlias`, `keyPassword`. Both the file and `*.jks` are git-ignored.

3. If this app has ever been uploaded, the new build's `versionCode` must be
   higher than the last upload. The code's own record is `version: 1.0.197+13`
   in `pubspec.yaml`, but a build on the test phone carried `2013`, so **check
   the console's last version code before the first upload** and raise the
   number (`flutter build appbundle --build-number <n+1>`) rather than assuming
   13 is free.

## 2. Build (verified)

- `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab`, 77.0 MB.
- `flutter build apk --release --target-platform android-arm64` → 32.2 MB.
- Both were built with a throwaway 2048-bit RSA key to prove the path, and the
  throwaway keystore and `key.properties` were then deleted. Do not reuse them.
- `minify` and `shrinkResources` are deliberately off: the plugins that matter
  register through reflection and INI, and a release came out 32 MB without
  them, so the risk of stripping a registrant buys nothing.

## 3. Store requirements

- **Target API 36**: set as a literal in `android/app/build.gradle` (`targetSdkVersion 36`).
  Mandatory for new apps and updates since 31 August 2026.
- **minSdk 24**: set as a literal beside it.
- **16 KB page sizes**: `tool/check_16k.sh` passes for every shipped library
  except `lib/arm64-v8a/libavif_native.so`, whose load segments are 4 KB
  aligned (`1000`) and whose `GNU_RELRO` range ends past the next load segment.
  The deadline is stated two ways upstream: the May 2025 announcement said
  1 November 2025, and the current page-size guide says 1 February 2027, both
  for apps targeting Android 15+ on 64-bit devices. **Read the app's own Play
  Console notice** — that is the binding signal for this listing. Fixes, in
  order of cost: an `avif_native` rebuild with `-Wl,-z,max-page-size=16384`
  (the package ships `native/CMakeLists.txt` and `tool/native/build_unix.sh`),
  a newer vendor artifact, or dropping media.
- **Permissions**: `INTERNET` (map tiles and archives), Bluetooth scan/connect,
  location (phone-GPS fallback and BLE scan results on API ≤ 30), foreground
  service `connectedDevice`, post-notifications, wake lock. Location hardware
  is declared **optional** so GPS-less tablets are not filtered out of the
  listing.
- **Data safety**: the app sends to the radio, fetches map tiles from the
  configured source, and opens the user's own links. There is no analytics and
  no crash reporter. Position, messages, media and diagnostics stay on the
  device; the history is sealed with an Android Keystore key, and places,
  trail, coverage and geofences are plaintext at rest, which the privacy text
  says in those words.
- **Privacy statement, terms gate, licences page and export compliance** are all
  in-app (`/settings/terms`, `/settings/about`), and the licences page lists
  bundled assets as well as packages.

## 4. Before the first upload

- Run `flutter test` once (1 987 tests at `ede4a9c5`'s tree, about 3 minutes).
- Run `flutter analyze`: expected output is the two known warnings in
  `lib/maps/maps_controller.dart:1202,1207`.
- Install the release APK on a phone and pair a radio: the fast path
  (`adb install`) is not available over the air in release mode, so use the
  debug APK for on-air work and the release APK for a startup/logcat pass.
- Confirm the launcher name and the per-app language list show English and
  Japanese (`res/values/strings.xml`, `res/values-ja/strings.xml`,
  `res/xml/locales_config.xml`).
