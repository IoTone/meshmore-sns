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
