# MeshmoreXR — RELEASE PLAYBOOK

**Target: Google Play open beta (open testing track).**
Written 2026-08-25, updated 2026-08-27 against **0.4.0** (versionCode 4000). Companion to `RELEASE-SIGNING.md`
(the key) and `MeshmoreXR-FSD-STATUS.md` (what is built).

Run this top to bottom. Each step says what "done" looks like, so a step can be
checked rather than believed.

---

## 1. The short version

| # | Step | Owner | State |
|---|---|---|---|
| 1 | ~~Transmit allow-list~~ | — | **done** (build 143) |
| 2 | Decide Play App Signing | **Operator** | **OWED — before first upload** |
| 3 | Decide EN-only or EN+JA at beta | **Operator** | **OWED** |
| 4 | `targetSdk` → 36 | Dev | **done**, smoke-tested |
| 5 | Version 0.4.0, AAB, signature verified | Dev | **done** |
| 6 | Host the privacy policy at a public URL | **Operator** | **OWED — blocks submission** |
| 7 | Play Console: data safety, rating, XR targeting | Operator | copy prepared, see `store/LISTING.md` |
| 8 | Store assets | Dev | **done** — icon, feature graphic, 8 screenshots |
| 9 | Promo video → **YouTube**, paste the link | **Operator** | **OWED — Play takes a URL, not a file** |
| 10 | Internal track → install on Aura → open testing | Both | ready when 2/3/6/9 land |

**Four things are owed and three of them are yours.** Everything the repo can
answer for itself is answered.

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
Shipping unreviewed Japanese to an open track is shipping text no native speaker
has read. Either hold JA for the first promotion, or send the reviewer the
nine-string delta now and wait.

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

# 2. nothing secret is tracked — must print 0
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

**Done:** the tree is at `0.4.0`, `verBuild` 0, `versionCode` 4000, `targetSdk`
36. `bundleRelease` needs `-x lintVitalAnalyzeRelease -x lintVitalRelease` on
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

## 5. Play Console

**Register the app.** Package `com.iotj.meshmore.xr`, category Communication.
All listing copy, and prepared answers for the data-safety and content-rating
forms, are in **`store/LISTING.md`** — every field is inside Play's character
limit, checked by `store/check_listing.py` (which counts CHARACTERS, because a
Japanese description well under 4000 characters is far over 4000 bytes).

### The assets, and where they are

| Asset | Play requires | State |
|---|---|---|
| App icon | 512×512 PNG | ✅ `store/icon-512.png` — rendered from the launcher vector, so it matches the icon on the device exactly |
| Feature graphic | 1024×500 PNG | ✅ `store/feature-graphic-1024x500.png` |
| Screenshots | ≥2, we supply 8 | ✅ `store/screenshots/*.png`, 1920×1200 native, both themes, English and Japanese |
| Promo video | a **YouTube URL** | ✅ cut — `store/cut/meshmore-xr-promo.mp4`, 50s. ⛔ still needs uploading; Play takes a URL, not a file |
| Privacy policy | a public **URL** | ⛔ `PRIVACY.md` has the text; it needs hosting |

The screenshots are pulled from your own captures rather than staged, so what
the listing shows is what the app does.

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

`store/cut/build.sh` is the edit, as a re-runnable script — nine segments named
in the source, hard cuts, one loudness pass over the finished audio because the
captures were made on different days and step in level when joined. Change a
timestamp in the script and re-run it; nothing is destructive and the sources
are untouched.

```
store/cut/meshmore-xr-promo.mp4    50s · 1920×1200 · h264 + aac 48 kHz
```

| # | Beat | From |
|---|---|---|
| 1 | The mesh around you | demo3 8–15 |
| 2 | Linked to a radio | demo1 9–12 |
| 3 | Horizon, callsigns, range | demo 42–48 |
| 4 | One node, its actions | demo 56–62 |
| 5 | A real conversation | demo 78–86 |
| 6 | Summon a surface | demo2 6–12 |
| 7 | The whole app in Japanese | demo3 43.5–49.5 |
| 8 | Settings | demo3 64–70 |
| 9 | End card | the feature graphic |

**It opens on the mesh, not on the splash.** The boot wordmark was the obvious
first beat and it is the wrong one twice over: a splash does not answer "what is
this" in the eight seconds most viewers give it, and this build's splash carries
`V0.3.0-DEBUG.142` under the wordmark until it fades at about 3.5 s. The
branding moved to an end card built from the feature graphic, which carries the
wordmark with no build number attached to it.

**Native 1920×1200 is kept rather than cropped to 16:9.** Cropping 120 rows
either clips the callsigns along the top or the status band along the bottom,
and both are the content. YouTube letterboxes the difference.

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

1. **Upload the videos to YouTube**, unlisted is fine. Play's promo video field
   takes a URL — the store never hosts the file. One video per listing, so cut
   the four captures into one piece, or pick the strongest.
   *Done when:* you have a URL that plays.
2. **Host the privacy policy.** Any stable public URL serving `PRIVACY.md`.
   *Done when:* the URL loads in a private window.
3. **Create the app in Play Console.** Name `Meshmore XR`, category
   Communication, and paste from `store/LISTING.md`.
4. **Decide Play App Signing at the first upload** — §2.2. It cannot be undone.
5. **Upload `app-release.aab`** to the **internal** track.
   *Done when:* the release shows a device catalogue that is XR devices rather
   than "0 devices". If it says zero, the cause is a required feature — go back
   to §5 and dump the badging.
6. **Install from Play onto the Aura** and run for an hour.
   *Done when:* `adb logcat -d | grep -cE "FATAL|AndroidRuntime"` is 0.
7. **Complete data safety, content rating and target audience** from the
   prepared answers in `store/LISTING.md`.
8. **Promote to open testing.**

---

## 9. What I would not ship without

1. One full pass **wearing** the 0.4.0 build, doing what a tester would do.
   Every glass check on the punch list is still unworn, and this build carries
   changes nobody has worn at all: the reach trail, the bay back-stack, menu
   exclusivity, MAP, the docs panel, and the claim action.
2. A **crash-free hour** on the Aura with the log clean of `FATAL`.
3. **Play App Signing decided** before the first upload, not during it.
4. The **Japanese decision** made deliberately rather than by default — nine
   strings have been added since the reviewer got the form.
