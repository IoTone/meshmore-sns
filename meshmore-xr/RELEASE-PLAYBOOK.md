# MeshmoreXR — RELEASE PLAYBOOK

**Target: Google Play open beta (open testing track).**
Written 2026-08-25, updated 2026-08-28 against **0.4.1 build 3** (versionCode 4103). Companion to `RELEASE-SIGNING.md`
(the key) and `MeshmoreXR-FSD-STATUS.md` (what is built).

Run this top to bottom. Each step says what "done" looks like, so a step can be
checked rather than believed.

---

## 1. The short version

| # | Step | Owner | State |
|---|---|---|---|
| 1 | ~~Transmit allow-list~~ | — | **done** (build 143) |
| 2 | Decide Play App Signing | **Operator** | **OWED — before first upload** |
| 3 | ~~Decide EN-only or EN+JA at beta~~ | Operator | **RESOLVED — ship JA** (§2.3) |
| 4 | `targetSdk` → 36 | Dev | **done**, smoke-tested |
| 5 | Version 0.4.1 b3 (versionCode **4103**), AAB built, signature verified | Dev | **done — the upload artefact.** 4102 was rejected and is burned (§5.4) |
| 5b | Unit tests green | Dev | **done** — 700 pass; the 108-string review applied at last (§4b) |
| 5c | Permission + declaration audit | Dev | **done** — §4c; two inherited permissions removed |
| 5d | Reviewed against the XR release reference | Dev | **done** — §8b; ARCore type declared, feature graphic flattened |
| 6 | ~~Host the privacy policy at a public URL~~ | Operator | **DONE 08-28** — https://meshmore-xr-www.pages.dev/privacy/ |
| 7 | Store listing + data safety, rating, XR targeting | Operator | **done** — EN and JA at parity, limits checked (§5.1); JA copy needs the reviewer |
| 8 | Store assets | Dev | **done** — icon, feature graphic, 8 screenshots (rebuilt from the worn captures) |
| 9 | Promo video → **YouTube**, paste into **both** 2D video fields | **Operator** | **OWED — cut 2 is rendered and waiting; Play takes a URL, not a file.** The third field, *Spatial XR video*, stays empty — §6c |
| 10 | Internal track → install on Aura → open testing | Both | ready when 2/3/6/9 land |

**Two things are owed and both are yours: the YouTube upload and the Play App
Signing decision.** Everything the repo can answer for itself is answered. Everything the repo can
answer for itself is answered.

One thing is owed by nobody here: Play's **Spatial XR video** slot wants 360°,
180° or stereo 3D, and `androidx.xr.scenecore` does not hand an app its eye
buffers. We cannot fill it, we should not fake it, and §6c says who to ask.

## 2. The decisions only you can make

### 2.1 The transmit allow-list — RESOLVED

**Done on 2026-08-25, build 143.** `ALLOWED_SUFFIXES` is removed.

The operator's recollection of why it existed was exact: it was there to stop an
assistant with a live radio and a 350-node contact store transmitting at
strangers. That protection is kept — the rule simply stopped asking *which peer
is this* and started asking **who is doing the asking**:

- **A person may message anyone.** Choosing a node and typing a message is the
  authorisation; the crown's arm/confirm step is the guard.
- **The app may only transmit unattended to claimed nodes.** Soak and the path
  probe pass `automated = true` and are refused for anything not pinned.

Claiming is the `MINE` spoke on the node menu. It is reversible, transmits
nothing, and needs a full 32-byte key. The operator's own radios were already
pinned by the previous code and remain claimed.

### 2.2 Play App Signing — irreversible

At first upload Play asks whether Google holds the app signing key.

- **Opt in** (recommended): your `keys/meshmore-release.jks` becomes the *upload*
  key. Google re-signs with a key you never hold. If you lose the upload key you
  request a reset and keep the listing. Play requires this for new apps in most
  flows anyway.
- **Opt out**: your key is the app signing key forever. Lose it and the listing
  cannot be updated — a new package name and a new listing is the only way back.

Either way the build command and `RELEASE-SIGNING.md` are unchanged. **This
cannot be undone after the first upload**, so decide before step 9, not during.

### 2.3 Japanese at beta, or after

The reviewer's pass has not come back, and **nine** strings were added after
they got the form — five for WX and Meshbook, four for claiming a node.
**RESOLVED 2026-08-28: ship Japanese.** Not because the copy is now beyond
question, but because waiting had no finish line and it took asking the reviewer
to see it.

The reviewer's answer to the terminology questions was that they cannot be
answered by a native speaker at all. The vocabulary — advert, flood, hop, mesh,
repeater — is invented for LoRa and for XR, has no everyday Japanese use, and so
is unknown to Japanese readers technical and non-technical alike. Settling it
properly would take the makers of the core technology publishing Japanese
terminology, and LoRa adoption in Japan is too low for that to exist yet.

**A blocker with no achievable completion condition is not a blocker, it is an
excuse.** Holding Japanese back until the terminology is authoritative means
holding it back indefinitely, in a market where shipping the app is itself part
of how the vocabulary would come to exist.

What actually remains, and travels with the release rather than gating it:

- **214 of 339 strings have never been read** (§4b). Real, and worth continuing.
- **Consistency, not idiom, is the standard now.** `docs/l10n-glossary-ja.md`
  restates the review question as: does one concept read the same on every
  screen, and can a reader connect it to the English they will meet in MeshCore's
  own documentation? Both are answerable without an authority.
- **One open decision: transliterate or translate the protocol terms.** ADVERT is
  currently `通知` in settings and `アドバート` in the notice band — the same
  action under two names. The glossary argues for transliteration, since a
  Japanese operator meets these words only in English and a translated form cuts
  them off from the only documentation there is. Not applied: those are the
  reviewer's words and this is the operator's call.

**The premise of this decision was wrong until 08-28.** It said nine strings had
been added since the reviewer got the form. Nothing had — the review is newer
than every feature commit (§4b). What is actually true is harder: **214 of 339
strings have never been reviewed at all**, and the 108 that were reviewed had
never been applied to the resource file until yesterday.

**Two further things changed its shape on 08-27, both in §5.1.** First, the
Japanese *listing* was found to be abridged rather than translated — it was
missing the see-through section entirely — and is now at parity, which adds a
second block of unreviewed Japanese prose to the same decision. Send the
reviewer the store copy along with the nine strings; it is one errand, not two.
Second, adding the locale costs **three text fields and no artwork**, because
icon, feature graphic, screenshots and video all fall back to `en-US`. So the
case against Japanese at beta is review quality alone. Effort was never the
reason, and should not be allowed to masquerade as one.

---

## 3. The keystore — what exists, what is left

**You already have a release key.** Created 2026-08-14, and the release build
has been verified running on the Aura. Do not generate another one.

```
Alias      meshmore
Type       PKCS12, RSA-4096, 10,000 days
Store      keys/meshmore-release.jks            (gitignored)
Wiring     app/keystore.properties              (gitignored)
SHA-256    E4:5F:5A:34:2F:A5:B2:69:7E:D4:03:7F:24:7D:23:45:
           D0:D7:48:27:06:CB:1B:40:01:25:A9:71:DE:4F:49:E5
```

Verify it right now, before anything else:

```bash
cd meshmore-xr
KT="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"

# 1. the store opens with the stored password, and holds the alias
"$KT" -list -v -keystore keys/meshmore-release.jks \
  -storepass "$(grep '^storePassword=' app/keystore.properties | cut -d= -f2-)" \
  | grep -E "Alias name|Valid from|SHA256"

# 2. nothing secret was EVER committed — stronger than `git status`, which
#    only proves nothing is staged right now. Must print nothing at all.
git log --all --pretty=format: --name-only --diff-filter=A \
  | sort -u | grep -iE "keystore|\.jks$|^keys/" 
git status --short | grep -cE "keys/|keystore.properties"
```

**Done looks like:** alias `meshmore`, the SHA-256 above, and a `0`.

### What is actually left on signing

1. **Back it up off this laptop.** Losing the key before Play App Signing is
   adopted loses the listing. Two copies, neither on this machine: the `.jks` in
   an encrypted vault, the password in a password manager.
   `keys/keystore.properties.backup` exists so the two travel together.
2. ~~Add v3 signing~~ — **done 2026-08-27.** The build signed with v2 alone,
   which cannot ever be rotated; v3 carries the proof-of-rotation record, so the
   option of replacing this key without starting a new listing now exists. v1
   stays off — it is JAR signing for API < 24 and `minSdk` here is 34. Verified:
   `Verified using v3 scheme: true`, certificate digest unchanged.
3. **Build a bundle rather than an APK** (Play requires AAB):

```bash
./gradlew :app:bundleRelease
# → app/build/outputs/bundle/release/app-release.aab
```

4. **Verify what you are about to upload.** An AAB is not verified with
   `apksigner`; extract the APKs Play would generate:

```bash
# apksigner works on APKs, so check the release APK's certificate:
./gradlew :app:assembleRelease
"$ANDROID_HOME"/build-tools/37.0.0/apksigner verify --print-certs \
  app/build/outputs/apk/release/app-release.apk
# → the SHA-256 must match the fingerprint above. Two traps are documented in
#   RELEASE-SIGNING.md; read them before concluding the build is broken.
```

---

## 4. Build and pre-flight

```bash
cd meshmore-xr
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"

./gradlew :app:testDebugUnitTest        # 700 tests, 0 failures
./gradlew :app:bundleRelease
```

**The submission artefact is kept out of `build/`.** `app/build/outputs/` is
overwritten by the next build, so a verified release is copied to `dist/` with
its version in the filename and a checksum beside it:

```
meshmore-xr/dist/meshmore-xr-0.4.1-4103.aab     18.41 MB  ← upload this
meshmore-xr/dist/meshmore-xr-0.4.1-4103.apk     45.68 MB  ← sideload this
meshmore-xr/dist/meshmore-xr-0.4.1-4103.sha256
meshmore-xr/dist/REJECTED-4102-do-not-upload.aab          ← kept as a record only
```

`dist/` is gitignored — the bytes are reproducible from the tagged source, and
an 18 MB `.aab` in git history is 18 MB every future clone pays for. The
checksum is what lets you prove months later that the file in Play is the file
you built.

**Done:** the tree is at `0.4.1`, `verBuild` 3, `versionCode` **4103**,
`targetSdk` 36. `bundleRelease` needs `-x lintVitalAnalyzeRelease -x lintVitalRelease` on
this machine — the Gradle daemon crashes in lint's release analysis, a
known-local failure that does not affect the artifact.

Pre-flight checks that have each caught something real:

```bash
# no English literal left where a Japanese wearer would see it
./gradlew :app:testDebugUnitTest --tests '*StringsParityTest*'

# no method near the JIT ceiling (largest of ours today: 7,548 of ~10,000)
dexdump -d classes*.dex | grep "insns size"

# the release build actually runs on the glasses, not just builds
bin/install.sh && adb logcat -d | grep -E "FATAL|AndroidRuntime"
```

---

## 4b. The Japanese review was never applied — now it is

`./gradlew :app:testReleaseUnitTest` → **700 tests, 0 failures.**

The width gates went red, and chasing them uncovered something much larger than
a layout problem.

### What was actually wrong

Commit `c8aea4e` — *"JA REVIEW: 121 strings back from the native speaker"* —
says 108 rewritten and 13 approved were **applied to values-ja**. They were not.
`docs/l10n-review-ja.csv` held every reviewed string; `values-ja/strings.xml`
still held the unidiomatic first pass for all 108. The CSV and the resource file
had diverged completely, and the only reason it surfaced is that six of the
reviewer's rewrites were *shorter* than the stale text, so the stale text
overflowed and the width tests failed.

The six over-budget strings the commit message warns about were the reviewer's
**first** pass. Their corrected copy in the CSV is inside budget on every one.

Applied 2026-08-28: **108 written, 13 already matching, 0 missing keys.** Tests
green afterwards, which is the check that matters — the resource file and the
review record now agree.

**What was shipping in the meantime was worse than awkward, it was wrong:**

| Key | English | Was shipping | Reviewer |
|---|---|---|---|
| `cm_bearing` | BEARING | `影響` — *influence* | `方位` |
| `rr_flood_sub` | ALL REPEATERS | `全ての通信` — *all communications* | `全中継局` |
| `pk_field` | FIELD | `フィールド` — the loanword | `空間` |
| `p_stale` | STALE | `未効力` — *not in force* | `古い` |
| `n_hands_busy` | HANDS ARE WORKING | `手は作動中` | `手を認識中` |

`cm_bearing` is a compass label reading "influence". The systematic one runs
through a dozen keys: `無線` (radio, the phenomenon) where the reviewer wants
`無線機` (radio, the device).

### The claim this corrects

§2.3 has said through several revisions that **nine strings were added after the
reviewer got the form**. That is false, and the dates say so: the review came
back `2026-08-27 16:40`, which is **newer than every feature commit** — WX and
Meshbook are 08-22, the claim and launch work 08-23. Nothing has been added
since. Diffing the string tables against `c8aea4e` returns **zero added keys**.

### A mistake worth recording

When the gates first went red I shortened eight Japanese strings myself to make
them fit. Five of those keys already had reviewed, in-budget copy sitting in
`docs/l10n-review-ja.csv` — I overwrote a native speaker's words with my own and
reported the build green. All eight have been reverted to the reviewer's text.

**The lesson is cheap and general: when a localized string fails a gate, look for
an existing review record before writing new text.** The CSV is the source of
truth for Japanese; `values-ja/strings.xml` is a build artifact of it. Treating
them the other way round is what produced both this and the original divergence.

### Where the Japanese actually stands

| | Count |
|---|---|
| Strings in `values-ja` | 369 |
| Rows in the review record | 339 |
| — rewritten by the reviewer, now applied | 108 |
| — approved as-is | 13 |
| — **never reviewed, still first-pass** | **214** |
| — held at the door, see below | 4 |

**214 of 339 have never been read by a native speaker.** That, not a nine-string
delta, is the real scope of the Japanese decision in §2.3, and `cm_bearing`
suggests what is likely still in there.

### Four still held

- `ago_day` / `ago_hr` / `ago_min` — came back as `%1$d１日前`, a full-width `1`
  after the format arg, which renders as "3 1日前". An IME artifact. The existing
  `%1$d日前` is correct and was kept.
- `al_lookalike` — **no such key exists in `values/strings.xml`.** Either an
  English string that needs adding first or a rename; not something to guess at.
  Worth asking the reviewer which they meant.

---

## 4c. Permissions and declarations — audited 2026-08-27

Audited against the **merged** manifest, not the source one, because three of
the findings were permissions no source file of ours mentions.

```bash
aapt2 dump badging app/build/outputs/apk/release/app-release.apk \
  | grep -E "uses-feature|uses-implied-feature|uses-permission"
```

### What we declare, and why each one is there

| Permission | Why | Prompt? |
|---|---|---|
| `OPENXR_SYSTEM` | ask the broker which OpenXR runtime is live; without it there is no XR session at all | no, `normal` |
| `HAND_TRACKING` | hands; a denial degrades to gaze+dwell | yes |
| `SCENE_UNDERSTANDING_COARSE` | find a real table for TABLETOP. Coarse, not fine | yes |
| `BLUETOOTH_SCAN` *(neverForLocation)* | find the companion radio | yes |
| `BLUETOOTH_CONNECT` | talk to it | yes |
| `RECORD_AUDIO` | dictation, asked at the moment of speaking | yes |
| `ACCESS_FINE/COARSE_LOCATION` | bearings, computed on device | yes |
| `VIBRATE` | the haptic language | no, `normal` |
| `BLUETOOTH` / `BLUETOOTH_ADMIN` *(maxSdkVersion 30)* | from `libmeshcore-android` and Nordic BLE; legacy pre-31 path | no |

Every permission the code requests at runtime is declared, and every declared
permission is requested by something — checked both directions.

### What is absent, and why that is the interesting half

- **No `<service>` of any kind.** No foreground service, no background service,
  no `FOREGROUND_SERVICE*` permission, and therefore **no Play foreground-service
  type declaration to fill in.** The app does nothing when it is not in front of
  you, which is a design property and not an oversight.
- **No `ACCESS_BACKGROUND_LOCATION`.** Location is read while the app is open.
  This is what keeps us out of Play's background-location declaration form and
  its review.
- **No `INTERNET`.** The listing says "No accounts. No servers. No internet."
  and the manifest is the proof — an app without `INTERNET` cannot open a socket
  no matter what its code says. This is the strongest evidence we have for the
  central claim, and it is worth not losing.
- No `POST_NOTIFICATIONS`, `WAKE_LOCK`, `QUERY_ALL_PACKAGES`, `RECEIVE_BOOT_
  COMPLETED`, `SCHEDULE_EXACT_ALARM`, storage or media permissions — none of
  which need a Play declaration form, because none of them are there.

### Three things this audit changed

**1. `WAKE_LOCK` and `ACCESS_NETWORK_STATE` were in the shipped manifest, and are
now removed.** Neither is in any source or build file of ours. Both arrive
through `androidx.xr.scenecore` → `androidx.media3:media3-exoplayer:1.10.0`, a
spatial media player this app never touches — audio here is platform `AudioTrack`
and `MediaPlayer`, and no SceneCore audio API is called anywhere. They matter
because **Play shows them to the shopper**: an app whose listing promises no
internet was asking to view network connections and to keep the device awake, and
a reviewer reading that list is entitled to ask why. Removed with
`tools:node="remove"`; verified gone from the badging dump.

*If a future version does use SceneCore's media player, delete those two removal
lines first.* ExoPlayer takes the wake lock only when `setWakeMode` is called and
reads network state only when streaming, so nothing we do today needs either.

**2. `<queries>` for the speech recogniser was missing.** From targetSdk 30 the
package-manager query behind `SpeechRecognizer.isRecognitionAvailable()` is
filtered, so an app without the declaration can be told no recogniser exists and
report NO SPEECH ENGINE on a device that has one. **Measured on the Aura: it
already worked without it** — the voice probe ran a dictation and the recogniser
timed out on a silent room rather than failing to start. So this fixes nothing
today. It is here because "works on the one device we own" is precisely how the
`xr.immersive` feature nearly shipped a store-only failure, and the next Android
XR device may ship its recogniser in a package we cannot see.

**3. `registerReceiver` now states its export intent.** Since targetSdk 34 a
dynamically registered receiver must declare whether other apps can reach it.
Receivers listening only to protected system broadcasts are exempt and both
Bluetooth pairing actions are protected, which is why this never threw. It is
spelled out anyway because of *which* path it is on: it runs **only when the
radio is not already bonded**, so it is the path every new tester walks and the
one our own testing never reaches — ours has been bonded since August. A silent
`SecurityException` there looks exactly like "pairing is broken" to the one
person who cannot tell us why.

### Required features — the device-catalogue check

```
uses-feature: android.software.xr.api.spatial      ← intended
uses-feature: android.hardware.bluetooth           ← intended, implied by the
                                                      pre-31 BLUETOOTH perms
uses-feature: android.hardware.faketouch           ← "default feature for all
                                                      apps"; universal, harmless
```

Three lines, not two. `faketouch` is aapt2's default for every app ever built
and filters nothing — **do not try to remove it.** Everything else is correctly
`uses-feature-not-required`: `bluetooth_le`, `location`, `location.gps`,
`microphone`, `xr.input.hand_tracking`.

---

## 5. Play Console

**Register the app.** Package `com.iotj.meshmore.xr`, category Communication.
All listing copy, and prepared answers for the data-safety and content-rating
forms, are in **`store/LISTING.md`** — every field is inside Play's character
limit, checked by `store/check_listing.py` (which counts CHARACTERS, because a
Japanese description well under 4000 characters is far over 4000 bytes).

### 5.1 The store listing, field by field

**Yes, the default listing is written.** `store/LISTING.md` is paste-ready and
every field is inside Play's limit:

| Field | Limit | en-US | ja-JP |
|---|---|---|---|
| App name | 30 | `Meshmore XR` — 11 | same, deliberately |
| Short description | 80 | 74 | 43 |
| Full description | 4000 | 2462 | 1228 |

`store/check_listing.py` counts **characters, not bytes** — that is the whole
reason it exists. A Japanese description comfortably under 4000 characters is
far over 4000 bytes, and a byte-based check rejects copy Play would accept. Run
it after any edit:

```bash
python3 store/check_listing.py     # → "all fields within limits", exit 0
```

**Default language is `en-US`.** Play falls back to it for any field a
translation leaves empty, which means adding Japanese costs three text fields
and no new artwork: one icon, one feature graphic, one screenshot set and one
video serve every locale. Two of the eight screenshots are already Japanese UI,
so the shared set reads honestly in both stores.

**The Japanese was abridged, and is not any more.** As first written it was a
condensed paraphrase: one whole section — *built for optical see-through* — was
absent, and five claims were flattened to a clause each, including the delivery
one (DELIVERED vs NO ANSWER), the channel-key one, and both the mesh-weather and
Meshbook explanations. That is the section that tells a reader *why* the app
looks the way it does, so a Japanese shopper was being handed a description of a
3D app with no reason offered for any of its choices. Corrected 2026-08-27; the
section-by-section parity table is in `store/LISTING.md`.

⚠️ **The corrected Japanese has not been native-reviewed.** It is new prose
written on 08-27 and goes to the reviewer with the nine-string delta — see §2.3.
If Japanese is held for the first promotion, this is not blocking.

The listing copy is also the place where three claims must not drift from the
build, because a reviewer will check them:

- *"No accounts. No servers. No internet."* — must stay true while S10 UPLINK is
  unbuilt. If an online tier ever ships, this paragraph changes first.
- *"Nine visual themes"* — count them before submitting, not after.
- *"every gesture has a gaze-and-dwell equivalent"* — this is an accessibility
  claim and it is the kind Play will act on if a tester disproves it.

### 5.3 Videos for the Console forms — and App access

**No permission we declare requires a demonstration video.** Play asks for one
only on a short list of sensitive declarations, and the badging dump holds none
of them — checked, not assumed:

```bash
aapt2 dump badging app-release.apk | grep -oE "name='[^']*'" \
  | grep -iE "BACKGROUND_LOCATION|MANAGE_EXTERNAL_STORAGE|READ_SMS|READ_CALL_LOG|QUERY_ALL_PACKAGES|BIND_ACCESSIBILITY|READ_MEDIA"
# → no matches
```

`ACCESS_FINE_LOCATION` is the one that looks like it should. It does not: the
video requirement attaches to **background** location, and we hold only the
foreground permission and declare no service (§4c). Microphone likewise needs no
video — the requirement there is a prominent in-app disclosure, and asking for
the mic at the moment the wearer chooses to speak *is* that disclosure.

So: **nothing owed for permissions.** But there is a video-shaped obligation of a
different kind, and it is easy to miss because it is not on the permissions page.

#### App access — the reviewer has no LoRa radio

Play's **App access** section exists for functionality a reviewer cannot reach.
Ours is not login-gated — there are no accounts — it is **hardware-gated**, which
the form does not have a checkbox for.

What a reviewer actually gets with no MeshCore radio in the room, traced through
the code rather than guessed:

| Reachable | Not reachable |
|---|---|
| First light — the mote, the reach trail | The horizon with nodes on it |
| The dock, and every surface it opens | Messaging, delivery state, channels |
| `NO RADIO / IS IT ON AND NEARBY? / A PHONE MAY BE HOLDING IT` | Mesh weather, Meshbook *(both need stored traffic)* |
| The built-in docs, all three sections, fully offline | Node focus, telemetry, claiming |
| Themes, language, settings | |

That is a coherent app rather than a blank room — the `NO RADIO` advice card
names the likely cause and offers a retry. But **every feature the listing
describes is on the right-hand side of that table**, and a reviewer who cannot
see any of them is a reviewer who may conclude the app does not work.

Three ways to answer it, in increasing order of how well they work:

1. **App access instructions**, naming the hardware requirement in plain words.
   Cheap, honest, and leaves the reviewer unable to verify anything.
2. **Point them at the promo video** (§6b). It is already cut, it is entirely
   real device footage, and it shows every feature in the order the listing
   claims them. This costs nothing extra and is the practical answer for beta.
3. **Make simulation reachable from the UI.** The app already has a full
   simulated mesh behind `--ez sim true` — it is how most of the screenshots and
   half the promo were shot. Today it is an intent extra, which means adb, which
   means a reviewer can never reach it. A labelled `DEMO MESH` row in SETUP would
   let anyone see the app work with no radio at all.

**Option 3 is the real fix and it is not free.** It needs a settings row and a
new string in *both* locales — and the Japanese side is already blocked behind a
reviewer (§2.3, §4b), so doing it now adds to that queue rather than draining it.
For an open beta, 1 + 2 is the proportionate answer. Revisit 3 before any wider
release, because it also fixes the first thing a curious tester without hardware
hits.

### 5.2 Asset requirements — phone listing and Android XR listing

**The Console has two screenshot uploads, not one.** The default store listing
takes the phone/tablet set; an **Android XR** section further down the same page
takes its own. Both were checked on 2026-08-27 and **our set failed the aspect
rule** — see below.

| Asset | Requirement | Source | Ours |
|---|---|---|---|
| App icon | 512×512, 32-bit PNG, ≤1 MB | Play docs — **verify in Console** | `icon-512.png`, 512×512, 0.04 MB ✅ |
| Feature graphic | 1024×500, PNG or JPEG, ≤15 MB | Play docs — **verify in Console** | `feature-graphic-1024x500.png`, 0.29 MB ✅ |
| Phone screenshots | 2–8, PNG/JPEG, ≤8 MB each, **16:9 or 9:16**, each side 320–3840 px | Play docs — **verify in Console** | 8 × 1920×1080, ≤1.8 MB ✅ |
| **Android XR screenshots** | **4–8, PNG or JPEG, ≤15 MB each, 16:9 or 9:16, each side 720–7,680 px** | **the deck, verbatim from the Console** | same 8 files ✅ |

Only the XR row is quoted from the Console itself — the deck's slide 11 shows
that field's help text in full. The other three rows are Play's published
requirements and are written here to be checked against the Console on the day,
**not** to be trusted over it. Numbers in a runbook age; the upload form does not.

**One set serves both uploads.** Every constraint that differs between the two
is looser on the XR side (4–8 vs 2–8, 15 MB vs 8 MB, 720 px vs 320 px floor), so
anything that passes the phone rules passes XR. 1920×1080 was chosen because it
also clears the 1,080 px floor that Play's newer phone guidance states, so the
same eight files satisfy the strictest reading of either.

#### The aspect rule, and why the set was rebuilt

The captures are **1920×1200 — 16:10**, because that is the Aura's display. The
Console asks for **16:9 or 9:16**. That is not a range with 16:10 inside it; it
reads as two permitted values, and a set that is neither is a set that may be
rejected at upload with everything else already filled in.

So the eight are now **1920×1080**, cropped from the natives, and the natives are
kept in `store/screenshots/native/` so a re-crop never needs a re-shoot.

**The crop offset is chosen per image, not applied uniformly.** A centre crop
took 60 rows off each end and clipped content on five of the eight — the hero
lost "40 NODES NOT SHOWN / NEAR 33KM", the channels shot lost its `CHANNEL 3`
header, and the Japanese shot lost the bottom of the gesture list, which is the
entire reason that shot exists. Offsets as built:

| Shot | Crop from | Because |
|---|---|---|
| 01 the mesh in your room | top, 70 | keeps `40 NODES NOT SHOWN` and `NEAR 33KM` on the bottom edge |
| 02 one node | bottom, 120 | the card sits high; the lower grid is empty floor |
| 03 channels | bottom, 120 | keeps `CHANNEL 3 / Ping / 3 DAY AGO` |
| 04 linked | centre, 60 | the banner is mid-frame |
| 05 callsigns *(emulator)* | bottom, 120 | keeps the callsign column, drops the LINK band |
| 06 every node heard | bottom, 120 | the list runs downward from the top |
| 07 Japanese | **top, 120** | the gesture list is the content; the heading band is not |
| 08 settings Japanese *(emulator)* | bottom, 120 | keeps the header and every settings row |

Re-verify after any re-crop:

```bash
cd store/screenshots
for f in 0*.png; do
  ffprobe -v error -show_entries stream=width,height -of csv=p=0:s=x "$f"
done          # → every line must read 1920x1080
```

#### Counts

Play's minimum to publish is 2 phone screenshots; the **XR field asks for at
least 4**. We supply 8 to both, which is the maximum either accepts, so there is
no room to add one later without dropping one — decide the order deliberately.
The first two are what a browsing shopper sees before scrolling: `01` is the
mesh standing in a real room and `02` is one node with its range and path.

### The assets, and where they are

| Asset | Play requires | State |
|---|---|---|
| App icon | 512×512 PNG | ✅ `store/icon-512.png` — rendered from the launcher vector, so it matches the icon on the device exactly |
| Feature graphic | 1024×500 PNG | ✅ `store/feature-graphic-1024x500.png` |
| Screenshots — phone | 2–8 | ✅ `store/screenshots/*.png`, 8 × **1920×1080 (16:9)** — §5.2 |
| Screenshots — **Android XR** | **4–8**, its own upload | ✅ the same 8 files; one set clears both (§5.2) |
| XR-specific non-spatial video | a **YouTube URL** | ✅ cut — `store/cut/meshmore-xr-promo-v2.mp4`, 43.7s (§6b). ⛔ still needs uploading; Play takes a URL, not a file |
| Generic promo video | the same **YouTube URL** | ✅ same cut, pasted into both fields (§6c) |
| **Spatial XR video** | 360°, 180° or 3D YouTube URL | ⛔ **not producible with this stack** — §6c. Leave empty; do not fake it |
| Privacy policy | a public **URL** | ✅ **https://meshmore-xr-www.pages.dev/privacy/** — Cloudflare Pages, EN and JA. Japanese: `/ja/privacy/` |

The screenshots are pulled from your own captures rather than staged, so what
the listing shows is what the app does.

### 5.4 The upload Play rejected, and what it settled

**versionCode 4102 was rejected.** The Console returned:

> APKs and bundles must not require following features:
> `android.software.xr.api.spatial`

The manifest had `required="true"` on purpose — the app is entirely spatial, and
requiring the feature was how it was kept off phones where there is nothing to
draw and nothing to touch. **Play does not accept that.** Distribution to XR is
the Console's form-factor setting to make, not the manifest's, and a required
spatial feature is read as an error rather than as targeting.

Changed to `required="false"` in build **4103**. Required features are now
`android.hardware.bluetooth` and `android.hardware.faketouch` only.

**This overrules a deviation recorded in §8b.** The XR release reference said
`required="true"` was correct "for a dedicated XR track". It is not, and the
guide's own rule decides it: *where console behaviour and documentation
disagree, believe the thing that rejects your upload.*

**The consequence is real and is now shipped.** With the feature optional, the
app is installable on a phone. The fail-safe that already existed for a headset
without hand tracking is what catches it — no spatial runtime means
`isSpatialUiEnabled=false` and a flat window rather than a crash. Degraded, not
broken. **Exclude phones in the Console's device catalogue**, which is where that
decision belongs.

**4102 is burned.** Play will not accept that code again under any content. The
rejected bundle is kept as `dist/REJECTED-4102-do-not-upload.aab` so it cannot be
picked up by mistake, and its `.apk` was deleted.

⚠️ **If 4103 is also rejected, do not re-upload it after fixing** — bump to 4104.
Every attempt costs a code.

### Device targeting — the check that decides whether anyone sees the listing

The manifest is now explicit about this, and it was not before. `aapt2 dump
badging` on the release APK reports every required feature Play will filter on:

```bash
aapt2 dump badging app/build/outputs/apk/release/app-release.apk | grep uses-feature
```

**Exactly two may be required:**

```
uses-feature: name='android.software.xr.api.spatial'    ← the point: XR only
uses-feature: name='android.hardware.bluetooth'         ← a client for a BT radio
```

Anything else appearing without `-not-required` is narrowing your catalogue by
accident. Three were, until 2026-08-27: `RECORD_AUDIO` implied a **microphone**
and the two location permissions implied **location hardware**, and an implied
feature is a REQUIRED one. A permission the app asks for politely had turned
into a hardware demand. All three are now declared `required="false"`.

**Data safety.** The honest answer is short and unusual: the app collects
nothing and transmits nothing to us. Location is used on-device for bearings and
broadcast over LoRa only when the wearer turns that on. Microphone is dictation,
on-device, never recorded by us.

**Beta specifics.** Start on the **internal** track and install from Play onto
the Aura before promoting. That is the one thing internal testing proves which a
sideload cannot: that Play's device targeting accepts the XR feature
declarations above.

## 6. The video, and how to capture true spatial

See §7 for the shot list. The tooling question first, because it has one
surprising answer.

### 6.1 What works, measured

**`adb emu screenrecord` on the XR emulator captures spatial content.** This was
tested on 2026-08-25: 12 seconds produced a 12 MB VP9 file, **1920×1200 at
24 fps with an audio track**, showing the horizon, the motes, the range rings
and the microhud composited over the emulator's virtual living room.

```bash
S=~/Desktop/meshmore-cuts
mkdir -p "$S"

adb emu screenrecord start "$S/cut-01.webm"
#   ... drive the scene ...
adb emu screenrecord stop

# frames, duration, size:
ffprobe -v error -show_entries stream=width,height,r_frame_rate \
        -show_entries format=duration "$S/cut-01.webm"
```

**What does not work: `adb shell screencap` on the Aura.** It returns the 2D
window and never the spatial layer — this is why every device-side check in this
project reads the log instead of looking at a picture. Do not plan any marketing
capture around it.

**Untested, worth ten minutes when the glasses are next up:** `adb shell
screenrecord` (present at `/system/bin/screenrecord`) may behave differently from
`screencap` on this platform, and the XREAL/Android XR system shell may offer its
own capture. Test both before assuming the emulator is the only source:

```bash
adb shell screenrecord --time-limit 10 /sdcard/aura-test.mp4
adb pull /sdcard/aura-test.mp4 && open aura-test.mp4
# blank or 2D-only → emulator it is.
```

### 6.2 Why the emulator is the right primary source anyway

It renders the same scene, at a clean 1920×1200, over a furnished virtual room —
which reads to a viewer exactly like passthrough AR. No camera, no moiré, no
autoexposure hunting the bright glyphs, and it is repeatable, which matters
because you will re-shoot.

**Parallax is what sells depth on a flat screen.** A still frame of an optical
see-through UI looks like a HUD overlay; the same frame moving with head motion
reads as objects standing in a room. So every cut must contain **head movement**,
and the movement should be slow, continuous, and roughly lateral — that is the
motion that produces parallax between the near dock, the mid-range motes and the
far horizon ring.

Drive it repeatably with the emulator's macro system rather than by hand:

```bash
adb emu automation record  ~/Desktop/orbit.macro    # move the view in the UI
adb emu automation stop-record

adb emu screenrecord start "$S/cut-01.webm"
adb emu automation play ~/Desktop/orbit.macro       # identical move, every take
adb emu screenrecord stop
```

One macro per camera move, reused across every theme — nine themes shot on the
same move cut together beautifully and cost one recording each.

### 6.3 The honest shot, for one cut only

The emulator cannot show what **additive optical see-through** actually looks
like: black is absence, the room shows through everything, and bright glyphs
float in real space. If you want one shot that is true to the product rather than
true to the render, film **through the eyepiece** — a phone or mirrorless camera
held to the lens, manual exposure locked, in a dim room. It will look worse and
be more convincing. Use it once, near the end, as the "this is really what you
see" beat. Do not open with it.

### 6.4 Delivery format

Play's promo video is a **YouTube link**, so cut and upload as ordinary video —
the store does not host the file.

```bash
# 16:10 → 1080p16:9 without distorting: crop the height, do not squash
ffmpeg -i cut-01.webm -vf "crop=1920:1080:0:60" -c:v libx264 -crf 18 \
       -preset slow -c:a aac -b:a 192k cut-01.mp4

# join the cuts
printf "file '%s'\n" cut-*.mp4 > list.txt
ffmpeg -f concat -safe 0 -i list.txt -c copy meshmore-xr-beta.mp4
```

Crop offset 60 keeps the horizon band centred; check one frame before batching.
**Keep the captured audio** — the cues are generated by `Synth` and are the
app's actual voice, which is a better soundtrack than a stock bed and needs no
licence.

---

## 6b. The cut that exists

Two cuts exist. **Ship cut 2.**

### Cut 2 — `store/cut/build2.sh` — the worn-glasses cut  ← the one to upload

```
store/cut/meshmore-xr-promo-v2.mp4   43.7s · 1920×1200 · h264 + aac 48 kHz · 48 MB
store/cut/promo-v2-preview.mp4       1280-wide review copy, 6.7 MB
```

Cut from the three captures made on the glasses on 2026-08-27, which are better
than the emulator material in the one way that decides a store listing: **the
room is in the frame.** The mesh stands on a real dining table with real
callsigns on it, which is the product. The emulator captures show the same
geometry against black, where a shopper cannot tell the app is see-through at
all.

Two acts, one theme each. The flip back to green for the Japanese beat is
deliberate and does the "nine themes" claim without a theme-carousel beat.

| # | Beat | From | Length |
|---|---|---|---|
| 1 | The room, with a grid laid on it | B 0.10–1.35 | 1.3s |
| 2 | **The mesh standing on the table**, callsigns and range | A 14.0–20.5 | 6.5s |
| 3 | `LINKED — MESHCORE-B722FE05` | C 0.60–4.00 | 3.4s |
| 4 | One node: 2.6KM NW 314, PATH UNKNOWN STALE, actions | C 18.8–21.0 @0.7× | 3.1s |
| 5 | A real conversation, READ ALOUD / VOICE: ON | C 25.0–31.0 | 6.0s |
| 6 | Channels, and the weather people mention on them | C 45.2–48.6 | 3.4s |
| 7 | Every node heard, including 180KM STALE | C 57.0–62.0 | 5.0s |
| 8 | The dock: pips lighting under a pointing hand | C 86.2–90.2 | 4.0s |
| 9 | GESTURES, spelled out | C 91.4–93.65 @0.65× + 1.0s freeze | 4.5s |
| 10 | The whole app in Japanese | A 5.50–9.50 | 4.0s |
| 11 | End card | the feature graphic | 2.5s |

Sources are `A = 162720`, `B = 162851`, `C = 163020` in `~/Desktop/meshmore`.
`CAPS=<dir> ./build2.sh` points the script somewhere else.

**Beats 4 and 9 are retimed, and that is not a stylistic choice.** Both are text
the viewer has to read, and both are on screen for barely two seconds in the
source. Beat 4 slows to 0.7× — the shot is near-static, so it does not read as
slow motion. Beat 9 is worse: the GESTURES panel is only legible from 91.6 to
93.7 and the head is turning through it the whole time, so the panel is sliding
out of frame exactly as it becomes readable. It runs at 0.65× and then **freezes
on the last frame for a second**, which is the only way that panel is readable
at all, and is why beat 9 is the one cut that stops moving.

**The promo is silent until the end card.** The glasses capture has two data
streams where the emulator had AAC, so there is no audio to use. Silence for the
body and the end card's own sting is the honest version; a music bed would be
the one thing in this listing that did not come off the device. If you want one,
add it in YouTube's editor rather than re-rendering, so the master stays what
the glasses recorded.

### Cut 1 — `store/cut/build.sh` — the emulator cut, superseded

```
store/cut/meshmore-xr-promo.mp4    50.5s · 1920×1200
```

Kept, not deleted. It is the only cut that has audio throughout and its shot
list is a different nine beats, so it is the fallback if a worn-glasses beat
turns out to be unusable. Its two standing weaknesses: the source splash carries
`V0.3.0-DEBUG.142`, and the Japanese crown holds for only about two seconds.

**Native 1920×1200 is kept in both, rather than cropped to 16:9.** Cropping 120
rows either clips the callsigns along the top or the status band along the
bottom, and both are the content. YouTube letterboxes the difference.

## 6c. Spatial video — the two XR fields, and the one we cannot fill

Source: *"[Ext May 2025] Android PlayXR Spatial Video and other Store Listings"*,
Google, 6 May 2025 — the deck in `~/Downloads`. Reviewed 2026-08-27. **It changes
the video plan, because Play has more than one video field for an XR listing and
we had been planning for one.**

### There are three video slots, not one

| Slot | Format | Where it plays | Us |
|---|---|---|---|
| **Spatial XR video** — *"highly recommended"* | 360°, 180°, **or rectangular 3D** | Moohan | ⛔ **cannot produce** — see below |
| **XR-specific non-spatial video** | ordinary 2D | Moohan **and** phone/tablet | ✅ **cut 2 goes here** |
| Generic video (the existing field) | ordinary 2D | phone/tablet, and Moohan only if the XR-specific slot is empty | ✅ cut 2 again |

All three are optional. Put cut 2 in **both** fields we can fill: the XR-specific
slot is what a Moohan browser sees, and the generic slot is what everyone else
sees. Leaving the generic one empty costs the phone/tablet listing its video for
no gain.

### Why we cannot make a spatial one, stated plainly

A spatial video must be 360°, 180°, or stereo 3D. All three need frames this app
cannot produce:

- Our captures are **monoscopic 1920×1200**, one flat rectangle off the glasses.
  There is no stereo pair in them and none can be recovered — synthesising a
  second eye would be inventing depth that was never measured, in a listing whose
  whole argument is that it shows measured things.
- The deck's 360° route is **Unity Recorder**, which works because a Unity app
  owns its camera and can be asked to render a sphere. We are on
  `androidx.xr.scenecore` + `androidx.xr.compose`; the compositor owns the eye
  buffers and the beta API does not hand them out. This is not "work we have not
  done" — the capture path is not ours to write.

So the spatial slot stays empty for beta. **Do not fake it.** A stretched or
duplicated-eye SBS upload is the kind of thing that reads as spatial in the
Console and as broken in the headset.

If the homepage placement is later worth chasing, the question to ask Google
directly — the deck names **yinkatp@google.com** — is whether Android XR exposes
an eye-buffer or 360 capture path for SceneCore apps, or intends to. That is the
single blocker, and it is theirs, not ours.

### What the deck's best practices say about cut 2

Checked against the cut as rendered, not against intent:

| Guidance | Cut 2 | |
|---|---|---|
| ≥80% from the user's perspective, headlocked | **100%** — every frame is first-person off the worn glasses | ✅ |
| Core in-app content inside the first 10 seconds | The mesh is on screen at **1.3s** and holds to 7.8s | ✅ |
| Limit title screens, logos, cutscenes | One 2.5s end card, at the end — 5.7% of the runtime | ✅ |
| Public or unlisted | operator's call at upload | — |
| **Ads turned off** | operator's call at upload | — |
| **Not age-restricted** | operator's call at upload | — |

Cut 2 was built before this deck was read, and it happens to satisfy the three
guidelines that are about content. That is not luck so much as the same reason
the screenshots were rebuilt: shooting the real thing from the wearer's head is
what both were asking for.

⚠️ **YouTube Shorts are not accepted.** Cut 2 is 43.7s, which is inside the
Shorts window, and YouTube classifies by aspect ratio as well as length. At
1920×1200 landscape it will not be treated as a Short — but if this cut is ever
re-rendered square or vertical for another channel, that upload cannot be the
one pasted into Play.

### The stale part of the deck

The timeline slide is from May 2025 and is fully elapsed: it points at "late May
2025" for Console access and "August 22, 2025" for submission, and it is now
August 2026. Treat the dates as history and the field definitions as current,
but **expect the Console to have moved** — the deck's screenshot shows the fields
under *Grow users → Store presence → Store listings*, and that is where to look
first, not where to insist they are.

## 7. Shot list

Ten cuts, 6–12 seconds each, ~75 seconds assembled. Ordered so the first eight
seconds answer "what is this" — most viewers see no more.

| # | Cut | What it shows | Move | Setup |
|---|---|---|---|---|
| 1 | **The mesh is around you** | Horizon ring with 30+ motes, range rings, callsigns | Slow lateral pan, 180° | `--ez sim true` |
| 2 | **Reach and touch** | First light: mote, reach trail, hand closing on it | Static, hand enters frame | `--ez firstlight true` |
| 3 | **One peer** | Node focus: callsign, distance, hops, SNR | Push in, then hold | Pick a mote |
| 4 | **Speak a message** | Crown opens, dictation draft fills word by word | Slight drift | `--ez dm true` |
| 5 | **It actually arrived** | SENDING → delivered on the thread line | Static | Live radio |
| 6 | **Bands, not tabs** | Channels surface, a tag typed, the slot written | Small orbit | `--ez sim true` |
| 7 | **The day this mesh had** | Meshbook: sparkline, topics, top voices | Slow rise | `--es bay MESHBOOK` |
| 8 | **Weather nobody measured** | WX rows mined from public chat, glyph + how long ago | Static | `--es bay WX` |
| 9 | **Nine worlds** | Theme cycle — one cut per theme, same move, hard cuts on the beat | Same macro ×9 | `--ez sweep true` |
| 10 | **Through the glass** | Filmed through the eyepiece in a dim room | Handheld, gentle | Real Aura |

Three rules for the edit:

- **No cut without motion.** A static frame of this app looks like a 2D overlay.
- **Cut on the audio.** The motifs are short and percussive; a hard cut on a
  DELIVERED or OPENED cue does the work a music edit usually does.
- **Show the room.** Frames where the virtual furniture is visible behind the
  glyphs are the ones that read as spatial. A cut filled edge to edge with UI
  reads as a screenshot.

Store listing also needs **screenshots** — pull them from the same recordings
rather than shooting separately:

```bash
ffmpeg -i cut-01.webm -ss 4 -frames:v 1 -q:v 2 shot-01.png
```

---

## 8. Submission day, in order

Everything above is preparation. This is the sequence on the day, and each step
says how you know it worked.

1. **Upload `store/cut/meshmore-xr-promo-v2.mp4` to YouTube**, unlisted is
   fine. Play's promo video field takes a URL — the store never hosts the file,
   and one listing takes one video, so this is the single cut (§6b). Title it
   `Meshmore XR — the LoRa mesh, standing around you`; leave the description
   plain and do not put a call to action in the first line, because Play renders
   the video with its own overlay.
   *Done when:* the URL plays in a private window, and Play accepts it — it
   rejects age-restricted, private, and ad-enabled videos, so turn monetisation
   off on that upload. **Not a Short** — see §6c.
2. ~~Host the privacy policy.~~ **Done 2026-08-28.** Paste
   `https://meshmore-xr-www.pages.dev/privacy/` into the Privacy policy field.
   The Japanese listing, if added, takes `/ja/privacy/` in its own field.
   *Verified:* both return 200, and the site no longer references the
   not-yet-live `meshmorexr.iotj.cc` — see `DEPLOY.md` §2 in
   **IoTone/meshmore-xr-www**, which is now its own repository, for why
   that mattered.
3. **Create the app in Play Console.** Name `Meshmore XR`, category
   Communication, **default language `en-US`** — Play uses it as the fallback
   for every other locale, so this is the one language field worth getting right
   the first time.
4. **Fill the default store listing** from `store/LISTING.md` §"App name",
   "Short description", "Full description", then attach the icon, feature
   graphic and the eight screenshots. **Scroll down to the separate *Android XR*
   section and upload the same eight there too** — it is its own field and an
   empty one is an XR listing with no screenshots (§5.2). Paste the YouTube URL
   from step 1 into **both** the *XR-specific non-spatial video* and the
   *generic video* fields; leave *Spatial XR video* empty (§6c).
   *Done when:* the XR section shows `8 / 8` and no upload was rejected. A
   rejection here is almost certainly the aspect rule — §5.2.
   *Done when:* Play's own character counters agree with
   `python3 store/check_listing.py`. If they disagree, Play is counting a
   trailing newline you pasted — not a copy problem.
5. **Add `ja-JP` only if §2.3 says yes.** Three fields, paste from the Japanese
   blocks in `store/LISTING.md`; leave every graphic empty and it inherits the
   default. Do not add the locale with English text in it as a placeholder — a
   listing that claims Japanese and delivers English is worse than no listing.
6. **Decide Play App Signing at the first upload** — §2.2. It cannot be undone.
7. **Upload `app-release.aab`** to the **internal** track.
   *Done when:* the release shows a device catalogue that is XR devices rather
   than "0 devices". If it says zero, the cause is a required feature — go back
   to §5 and dump the badging.
8. **Install from Play onto the Aura** and run for an hour.
   *Done when:* `adb logcat -d | grep -cE "FATAL|AndroidRuntime"` is 0.
9. **Complete data safety, content rating and target audience** from the
   prepared answers in `store/LISTING.md`.
9b. **Fill App access** (§5.3). No permission of ours needs a demonstration
   video, but the reviewer has no LoRa radio and therefore cannot reach any
   feature the listing describes. State the hardware requirement and give the
   promo URL from step 1 as the demonstration.
10. **Promote to open testing.**

---

## 8b. Reviewed against "Shipping Android XR"

The operator's Play Console release reference, dated 2026-08-28, read in full and
checked claim by claim against our actual artifacts rather than against the
source tree. Three things it caught, three it confirmed we had already done, and
two places we deviate on purpose.

### It caught three, all now fixed

**1. The ARCore dependency type was missing — the highest-risk item on this
page.** The guide says an app pulling in ARCore must declare whether AR is
required or optional, and calls omitting it a hard upload rejection rather than a
warning. We had no such declaration, and we *are* pulling ARCore in: the badging
dump on the previous release APK carried `com.google.ar.core.min_apk_version =
253130000` and a `com.google.ar.core.InstallActivity`, both merged from
`androidx.xr.arcore`, with no `com.google.ar.core` meta-data anywhere.

Now declared as **`optional`**, verified present in the rebuilt APK. Optional
rather than required because on Android XR the arcore artifact talks to the
platform's XR runtime rather than to the Play Services for AR APK, so demanding
that APK would narrow the device catalogue on top of the spatial feature we
already require.

*This is the one item I could not verify myself.* Whether Play actually rejects
the upload is the guide's claim, not something measurable from here. The fix is
one line and costs nothing, so it is applied regardless of whether the claim is
strictly true.

**2. The feature graphic had an alpha channel.** The guide is specific that the
feature graphic must be opaque and that a channel must be flattened *"even one
where every pixel is already opaque"*. Ours was exactly that case — PNG colour
type 6 (RGBA), and a scan of the alpha plane returned min 255 across all 512,000
pixels. Fully opaque, and still carrying the channel Play objects to. Flattened
to colour type 2; every store asset is now RGB with no alpha.

**3. `debugSymbolLevel` was unset.** Set to `SYMBOL_TABLE`. It collects nothing
today — we ship no native code of our own, and the `.so` files in the bundle
arrive prebuilt and stripped inside Google's AARs — but it means symbols travel
with the first build that *does* contain native code, rather than being
remembered after the first unreadable crash.

### It confirmed three we already had

- **arm64-v8a only.** `abiFilters` was already set; the AAB carries exactly one
  `lib/` directory.
- **Secrets absent from the whole history.** The guide is right that
  `git status` is the weaker check — it only proves nothing is staged *now*. Ran
  `git log --all --diff-filter=A --name-only`: no keystore, `.jks`, or
  `keystore.properties` path was ever added on any branch. **This replaces the
  status check in §3.**
- **One eye, not two.** The guide warns that a 3840×1200 grab is both eyes and
  must be cropped rather than squashed. Ours are 1920×1200 — a single eye
  already.

### Two deliberate deviations

**We crop to 16:9; the guide says letterbox.** Its reasoning is against
*stretching*, which we agree with — a squashed screenshot looks careless. But
letterboxing 16:10 into 16:9 means scaling 1920×1200 down to 1728×1080 and
padding, which costs real resolution and adds bars. Cropping keeps pixels 1:1,
and §5.2 chose the offset per image and verified by eye that nothing important
was lost. Cropping is a third option the guide does not consider, and for stills
it is the better one.

**We require `android.software.xr.api.spatial`; the guide leans to
`required="false"`.** No conflict — the guide says `true` is correct for an
XR-only track, which is exactly what this is. The consequence it names is the
intent: no phone will ever see the listing, because there is nothing on a phone
for this app to do.

### What does not apply

Sections 02 (foreground services) and the exact-alarm guidance are moot: we
declare no service and no alarm permission at all (§4c). The declaration-video
checklist item is likewise satisfied by having none to upload (§5.3).

### One thing it says that our footage does not do

> *"Record against a dark surface. Light UI over a white wall in passthrough
> washes out badly enough to be unreadable."*

Our captures are a bright white-walled room in daylight, and it shows: shots 05
and 06 are the two washed out by windows, and it is why beat 9 of the promo needed
a freeze to be readable at all. The guide is right and our footage is at the edge
of legible in places. Not worth re-shooting for beta — the content reads — but
**if any asset is ever re-shot, shoot it against a dark wall in the evening.**

It also suggests burning in section labels for silent video, and notes the
workaround when `ffmpeg` lacks `drawtext`: render PNG labels and composite with
`overlay`. This build of `ffmpeg` does lack `drawtext` — confirmed while cutting
the promo — so that is the route if labels get added later.

### One number to re-check, not to trust

The guide gives **15 MB** for phone screenshots; §5.2 recorded **8 MB** from
Play's published docs. They disagree. Ours are all ≤1.8 MB so nothing turns on
it, but the guide's own rule applies — believe the upload panel, not either
document.

### And one operational warning worth internalising

**A rejected upload burns its `versionCode` permanently.** Proven on 4102 (§5.4). We are at 4103. Do not
plan a numbering scheme that assumes a failed attempt is free; expect to
increment on every try.

---

## 9. What I would not ship without

1. ⚠️ **A wear pass on the artefact being uploaded.** The operator reports
   wearing "the release" and finding it fine, but the Aura's puck
   (`Android XR Puck`, checked 08-28) still holds **0.3.0-debug.142, versionCode
   3142, last updated 08-24**. Whatever was worn, it was not 0.4.1 on this
   device. Build 4102 additionally carries changes made *after* any 0.4.1 was
   flashed: the 108 reviewed Japanese strings, three manifest declarations, and
   the ARCore dependency type. **Confirm which device and which build, or wear
   4102 before promoting past internal test.**
2. A **crash-free hour** on the Aura with the log clean of `FATAL`.
3. **Play App Signing decided** before the first upload, not during it.
4. The **Japanese decision** made deliberately rather than by default — nine
   strings have been added since the reviewer got the form.
5. ~~A green test run.~~ **Done** — 700 pass (§4b). What remains from it is
   larger than the tests were: **214 of 339 Japanese strings have never been
   read by a native speaker**, and one of the 108 that had been ("BEARING" as
   `影響`, *influence*) shows what that can look like.
