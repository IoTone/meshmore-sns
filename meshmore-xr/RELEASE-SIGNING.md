# MeshmoreXR — Release Signing

**The keystore and its passwords are NOT in this repository** and must never
be. They live in `keys/` (gitignored, along with `app/keystore.properties`).
This file documents how the key was made and how to use, back up, and — if it
comes to it — replace it.

## What exists

| Artifact | Where | In git? |
|---|---|---|
| Release keystore | `keys/meshmore-release.jks` | **No** (gitignored) |
| Passwords + wiring | `app/keystore.properties` | **No** (gitignored) |
| A copy of the properties | `keys/keystore.properties.backup` | **No** |
| This procedure | `RELEASE-SIGNING.md` | Yes |

Key facts (safe to publish — the fingerprint identifies the app, it does not
unlock anything):

- **Alias:** `meshmore`
- **Type:** PKCS12, RSA-4096, validity 10,000 days (created 2026-08-14)
- **DN:** `CN=Meshmore XR, O=IoTone Inc., L=Portland, ST=Oregon, C=US`
- **SHA-256 fingerprint:**
  `E4:5F:5A:34:2F:A5:B2:69:7E:D4:03:7F:24:7D:23:45:D0:D7:48:27:06:CB:1B:40:01:25:A9:71:DE:4F:49:E5`

## How it was generated

```bash
# From meshmore-xr/. keytool is the Android Studio JBR's.
KT="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"
STORE_PW=$(openssl rand -base64 18 | tr -d '=+/')   # generated, never typed

"$KT" -genkeypair -v \
  -keystore keys/meshmore-release.jks \
  -alias meshmore -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$STORE_PW" \
  -dname "CN=Meshmore XR, O=IoTone Inc., L=Portland, ST=Oregon, C=US"
```

⚠️ **PKCS12 has ONE password.** Modern `keytool` produces PKCS12 stores, which
do not support a per-key password — a `-keypass` different from `-storepass`
is silently ignored at creation and then fails at signing time with the
deeply unhelpful `Given final block not properly padded`. We hit exactly this.
In `keystore.properties`, `keyPassword` must equal `storePassword`.

`app/keystore.properties` (the build reads it; absent = unsigned release,
which is what every machine that is not the release machine should produce):

```properties
storeFile=/absolute/path/to/meshmore-xr/keys/meshmore-release.jks
storePassword=<the one password>
keyAlias=meshmore
keyPassword=<the same password>
```

## Signing and verifying

```bash
./gradlew :app:assembleRelease
# → app/build/outputs/apk/release/app-release.apk (signed; "UNSIGNED" warning absent)

apksigner verify --print-certs app/build/outputs/apk/release/app-release.apk
# → V2 Signer certificate SHA-256 must match the fingerprint above
```

For Google Play, build the bundle instead: `./gradlew :app:bundleRelease` →
`app-release.aab`, same signing config. If Play App Signing is adopted, THIS
key becomes the upload key and Google holds the app signing key — decide that
at first upload, it cannot be undone.

## Back it up, now

**Losing this key means losing the ability to update the app** under the same
identity — for sideload users that is a reinstall-from-scratch; under Play
without Play App Signing it is a new listing. Copy `keys/` to at least two
places that are not this laptop (password manager for the properties, an
encrypted drive or vault for the `.jks`). The `keys/keystore.properties.backup`
exists so the `.jks` and its password travel together.

## If the key is ever compromised

There is no revocation for Android signing keys. Rotate: generate a new key by
this procedure, ship the next release signed with it as a NEW applicationId or
via Play's key-upgrade flow (Play App Signing only), and publish the new
fingerprint. This is painful by design — which is the argument for the backup
paragraph above.

## The release build, verified end to end (2026-08-21, build 112)

Verified for the first time on this date. It works, and both artefacts build:

| Artefact | Size | Signature |
|---|---|---|
| `app/build/outputs/apk/release/app-release.apk` | 47 MB | v2 scheme, `CN=Meshmore XR` |
| `app/build/outputs/bundle/release/app-release.aab` | 18 MB | jar verified |

```bash
./gradlew :app:assembleRelease :app:bundleRelease
$ANDROID_HOME/build-tools/*/apksigner verify --print-certs \
    app/build/outputs/apk/release/app-release.apk
```

`isMinifyEnabled = false` on release, so there is no R8 pass and no shrinker
configuration to get wrong — the usual way an XR release differs from its
debug build does not apply here. The release APK was installed on the XR
emulator and reached a full spatial scene: `requestFullSpace -> Success`,
`isSpatialUiEnabled=true`, and the reel, crown, console, theme picker and
stack all built. No exceptions. The version stamp reads `0.3.0` with no
`-debug` suffix, which is how to tell at a glance which build is on a device.

### Install with `bin/install.sh`, not with `adb install`

    bin/install.sh release v1l264b1186364

It grants every runtime permission the manifest asks for, reading the list out
of the manifest rather than repeating it, and refuses to finish quietly if hand
tracking did not take. Use it. The hand-written alternative was got wrong on
2026-08-21 and cost most of the app for an evening — see below.

### Three things that will look like a broken release and are not

Both cost an hour on 2026-08-21, and neither has anything to do with the APK.

1. **Another XR app holding Full Space.** Only one app can be in full space at
   a time. With `com.iotj.diana.xr` resumed as `full-space-managed`, MeshmoreXR
   starts, logs `isSpatialUiEnabled=false`, builds no surfaces and sits there
   looking exactly like a release-only failure. `adb shell dumpsys activity
   activities | grep topResumedActivity` names the culprit; force-stop it.
2. **Uninstalling revokes the runtime permissions.** Testing a release build
   means `adb uninstall` first (debug and release are signed differently), and
   the reinstalled app comes up with no BLE, microphone or location grant. The
   permission dialog takes focus and the app is behind it. Grant them from the
   shell before launching, or answer the dialog.

3. **An uninstall revokes HAND_TRACKING, and nothing obvious says so.** This
   is the expensive one. Installing release over debug means uninstalling, and
   the app then comes up looking entirely healthy — it draws, it connects to
   the radio, it syncs 350 contacts — while seeing nothing of your hands. The
   only evidence is one line:

       [stage] hand tracking refused (SecurityException) — gestures off

   With hands gone, gestures, ASL and every pinch go with them, and the dock
   becomes unreachable rather than absent. Reported as "hand tracking and ASL
   are now broken, the dock menu is gone too", which is exactly what it looks
   like from inside the glasses. `bin/install.sh` exists so it cannot recur.

   A second, unrelated-looking symptom lands at the same moment: the wipe also
   resets the THEME to HALO FIELD, and HALO is the one theme with
   `active = true`, which switches the dock to its four-pip WRIST form down by
   your hand. A wearer who had RECON sees a different, smaller dock somewhere
   else and reasonably reports the dock as missing. Nothing is wrong; re-pick
   the theme.

### Still owed before a store submission

- **v3 signing is off.** The APK verifies under v2 only, which Play accepts at
  minSdk 34, but v3 is what allows the signing key to be ROTATED later. Worth
  turning on deliberately rather than discovering the limitation the day a key
  needs replacing — it changes the signed artefact, so it is a decision rather
  than a tidy-up.
- The release build has not been run on the Aura. Doing so means uninstalling
  the debug build, which erases the wearer's theme, favourites, tags and home
  radio, so it should be done when losing those is acceptable.

