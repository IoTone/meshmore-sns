# Android XR Glasses — Developer Starter Guide (LLM-ready)

A bootstrap guide for standing up a **new Android XR app** for optical
see-through glasses (Xreal Aura class), targeting Jetpack XR + Jetpack Compose,
with an **optional native OpenXR/Vulkan** layer for heavy rendering. Written to
be pasted into an LLM coding session as ground truth. Versions are what
RobotARme ships and has verified on device/emulator as of 2026-07; treat them as
a known-good baseline, and re-check the Jetpack XR release notes (it's a
fast-moving Developer Preview).

**Two apps feed this guide, and they do not share a display technology.**
RobotARme is **video passthrough** (a camera feed behind your UI). MeshmoreXR
(Xreal Aura, 2026-08) is **additive optical see-through** — light is *added* to
the room and nothing can be made darker. Several rules invert between the two,
and items below are marked `[VIDEO]` or `[ADDITIVE]` where they do. If you are
on optical glasses, read §4a before you draw anything.

> Convention in this guide: `✅` = do this, `⚠️` = known trap, `🔎` = verify against
> current SDK because it changes.

---

## 0. Mental model

Three layers, use only what you need:

1. **Jetpack Compose spatial UI** (`androidx.xr.compose`) — `Subspace`,
   `SpatialPanel`, `Orbiter`. Your 2D screens, floating in space. Start here.
2. **SceneCore** (`androidx.xr.scenecore`) — imperative 3D: load glTF models,
   place `PanelEntity`/`GltfModelEntity`, set poses/scales. Use when Compose
   spatial isn't enough (3D content, hand-anchored elements).
3. **ARCore for Jetpack XR** (`androidx.xr.arcore`) — perception: head pose
   (`ArDevice`), hands (`Hand`), planes, depth. Use for anything that reacts to
   the room or the user's body.
4. **Native OpenXR + Vulkan** (optional, NDK) — only for rendering you can't do
   in the managed layer (e.g. hundreds of thousands of gaussian splats). Heavy;
   skip unless you need it.

---

## 1. Toolchain (get this exactly right — most first-day pain is here)

| Component | Value | Notes |
|---|---|---|
| JDK | **17–21** | ⚠️ Gradle/AGP for XR **reject Java >21** with a cryptic error that's just the bare version string (e.g. `25.0.2`). Android Studio's bundled JBR can silently jump to Java 25 on update. Pin a 17–21 JDK. |
| `compileSdk` | **36** | Required by `androidx.xr.compose` alpha AAR metadata. |
| `minSdk` | **34** | Android XR baseline. |
| `targetSdk` | 35 | |
| NDK (native only) | **28.x** (`28.0.13004108`) | Pin it so CLI and Studio agree. |
| CMake (native only) | 3.22.1 | |
| Emulator image | **Google XR / Aura, API 34** | For compile + flow. ⚠️ hand simulation ≠ real hardware. |

⚠️ **The JDK trap, concretely.** If `./gradlew` dies printing only a version
number, your `JAVA_HOME` is >21. Probe candidates and pick one in range:

```bash
java_major() { "$1/bin/java" -version 2>&1 | sed -nE 's/.*version "([0-9]+).*/\1/p' | head -1; }
for c in "$JAVA_HOME" "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
         "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home" \
         "/opt/homebrew/opt/openjdk@17/..."; do
  m=$(java_major "$c"); [ -n "$m" ] && [ "$m" -ge 17 ] && [ "$m" -le 21 ] && { export JAVA_HOME="$c"; break; }
done
```

✅ **Wrap build/install/test in a `bin/` script** that pins `JAVA_HOME`,
`ANDROID_HOME`, and forwards the server URL. It keeps everyone (and every LLM
session) on the same invocation and out of the JDK trap. Example targets:
`assembleDebug`, `installDebug` + `adb shell monkey … LAUNCHER`,
`testDebugUnitTest`, `connectedDebugAndroidTest`.

---

## 2. Gradle wiring

`app/build.gradle.kts` essentials:

```kotlin
android {
    namespace = "com.example.xrapp"
    compileSdk = 36
    defaultConfig {
        minSdk = 34; targetSdk = 35
        // Independent versioning; the app also shows the server version at runtime.
        versionCode = 1; versionName = "0.1.0"
        // Native only:
        ndk { abiFilters += "arm64-v8a" }   // headsets are arm64
        externalNativeBuild { cmake { arguments += "-DANDROID_STL=c++_shared" } }
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true; prefab = true } // prefab: native only
    ndkVersion = "28.0.13004108"                                        // native only
    externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } } // native only
    // Bake a server URL into BuildConfig (see §7).
}

dependencies {
    // Compose + lifecycle (standard)
    implementation(platform("androidx.compose:compose-bom:<current>"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:<current>")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:<current>")

    // Jetpack XR (Developer Preview — 🔎 pin exact versions from the release notes)
    implementation("androidx.xr.compose:compose:1.0.0-alphaNN")
    implementation("androidx.xr.scenecore:scenecore:1.0.0-alphaNN")
    implementation("androidx.xr.arcore:arcore:1.0.0-alphaNN")

    // Native OpenXR loader (native only) — ships a prefab CMake package
    implementation("org.khronos.openxr:openxr_loader_for_android:<current>")
}
```

⚠️ **Keep the Gradle wrapper (`gradlew`, `gradle/wrapper/*`) tracked in VCS** so
builds are reproducible across machines and CI.

🔎 The Jetpack XR artifacts are alpha and move fast; the composable/entity APIs
change between alphas. **Verify signatures against the AAR you actually depend
on** (e.g. `javap` the classes.jar) rather than trusting older examples.

`AndroidManifest.xml` — declare XR use and permissions you need:

```xml
<uses-feature android:name="android.software.xr.immersive" android:required="true"/>
<uses-permission android:name="android.permission.HAND_TRACKING"/>
<!-- scene understanding / depth / camera as needed -->
```

---

## 3. Compose spatial UI (start here)

```kotlin
setContent {
  Subspace {
    SpatialPanel(SubspaceModifier.width(1024.dp).height(640.dp).movable().resizable()) {
      // Ordinary Compose content renders on a panel floating in space.
      AppScreens()
    }
  }
}
```

- `Subspace {}` is the spatial container; `SpatialPanel` hosts normal Compose.
- `.movable().resizable()` let the user reposition/scale — ⚠️ this puts a **scale
  in the panel's parent transform**, which matters if you later mix in SceneCore
  world poses (see §5).
- Use `Orbiter` for chrome (nav, close) that should hug the panel edge.
- Gate 3D affordances on capability:
  `LocalSpatialCapabilities.current.isSpatialUiEnabled` /
  `isContent3dEnabled` before assuming you're in a spatial context (you may be in
  a 2D home-space window).

---

## 4. SceneCore: the Session, panels, and 3D models

```kotlin
// Session.create is idempotent PER ACTIVITY (cached). xr.compose's SpatialPanel
// host uses the SAME instance. Never cache a Session past the Activity — it dies
// on recreate().
val session = (Session.create(activity) as? SessionCreateSuccess)?.session ?: return

// A 2D panel entity in world space, sized in METERS:
val panel = PanelEntity.create(session, androidView, FloatSize2d(0.30f, 0.083f),
    "hud", Pose(Vector3(0f, 0f, -0.8f), Quaternion.Identity), session.scene.activitySpace)
panel.setPose(worldPose, Space.REAL_WORLD)   // ⚠️ see §5 on space choice

// A glTF model (suspend load, then place):
val model = GltfModel.create(session, file.toPath())          // also Uri / ByteArray
val entity = GltfModelEntity.create(session, model)           // + optional pose/parent
val bbox = entity.getGltfModelBoundingBox()                   // meters, model space
entity.setScale((0.8f / bbox.maxExtent).coerceIn(0.02f, 1f))  // e.g. dollhouse-scale a room
// Gate on capability first:
if (SpatialCapability.SPATIAL_3D_CONTENT !in session.scene.spatialCapabilities) { /* 2D fallback */ }
```

Lifecycle: `GltfModel`/entities are `AutoCloseable`. Dispose in order
(`entity.dispose()` → `model.close()`), guard against use-after-dispose
(`isDisposed` / `DisposedException`), and tie disposal to the composable
(`DisposableEffect { onDispose { … } }`).

---

## 4a. SceneCore rendering realities `[ADDITIVE]`

Everything here was proved on device (Xreal Aura, `scenecore:1.0.0-beta01`,
2026-08) after being guessed wrong first. These are not style opinions; they are
properties of the material path.

### ⚠️ `MeshEntity.setAlpha()` is a NO-OP on the Khronos-unlit path

It compiles, it runs, it returns, and nothing changes. **Brightness has to be
baked into the material at creation.** The practical consequences:

- You cannot fade anything. Not in, not out, not to indicate state.
- A "lit / focused" state must be its **own entity with its own material**,
  toggled with `setEnabled`. Build both at startup and swap them.
- The only things you can actually animate are **geometry, scale, pose and
  enablement**. Design every affordance out of those four.

✅ Scale survives being seen at the edge of vision, which is where a
wrist- or hand-mounted element usually is. Prefer a size pulse to a glow.

### ⚠️ One material per entity — sharing aborts the renderer NATIVELY

Reusing a `KhronosUnlitMaterial` across two entities kills the process from
native code, with no Kotlin stack trace:

```
OwnedPtr of type imp::Material ... released with N outstanding borrowed objects
```

✅ Build a fresh material per entity, even when the colour is identical. It cost
four separate crashes (Horizon, HereMark, Hud, Boot) before the pattern was
recognised.

### ⚠️ Black is TRANSPARENT, and a transparent quad still OCCLUDES

On additive optics, RGB(0,0,0) emits nothing, so it *is* the passthrough. But a
`PanelEntity` **writes depth across its entire quad**, including the parts that
emit nothing — so a panel behind an icon punches a hole in everything drawn
behind it. The symptom is a "dark rectangle" that no amount of colour tuning
fixes.

✅ Use an alpha-**mask** material (`AlphaMode.MASK` + an alpha cutoff) so
sub-cutoff fragments are *discarded* rather than drawn transparent. Discarded
fragments write no depth.

⚠️ **This inverts RobotARme's advice** (UX doc §4/§5: "give small UI a dark halo
/ backing"). On video passthrough a dark backing raises contrast. On additive
optics it is a hole. Know which display you are on.

### ⚠️ `PanelEntity.size` and `sizeInPixels` overwrite each other

Each setter recomputes the other from the current pixel density. Whichever you
assign **last** wins, and the other silently changes. Setting a metre size after
a pixel size gave 350×55-pixel panels rendered as unreadable slivers.

✅ The order that works: assign `sizeInPixels`, read back `size` to learn the
actual metres-per-pixel, then reach your target world size with `setScale()`.

```kotlin
val panel = PanelEntity.create(session, view, FloatSize2d(wPx * NOMINAL_MPP, hPx * NOMINAL_MPP), …)
panel.sizeInPixels = IntSize2d(wPx, hPx)
val mpp = (panel.size.height / hPx).takeIf { it > 0f } ?: NOMINAL_MPP
panel.setScale((capHeightM / capPx) / mpp)
```

### ✅ Build all geometry at startup, hidden; never in an input callback

`Prims.material()`-style creation is a **suspend** call and an
`InteractableComponent` callback is **not** a coroutine. Beyond the typing
problem, building meshes mid-gesture hitches the frame at exactly the moment the
user is watching for a response. Opening a menu should be a **pose and an
enable**, nothing more.

### ✅ When you cannot see it, outline it

Three wrong theories in a row (foreshortening, pitch sign, panel density) were
killed in one run by drawing the panel's actual bounds as a debug rectangle
behind it and logging `DRAW bounds=350x55`. On a device strapped to your face,
**a debug widget that draws what the code believes is worth more than reasoning
about what it should be doing.** Put one behind a launch flag early.

---

## 5. Coordinate spaces (a top source of "it's behind me / wrong size")

- Panel sizes (`FloatSize2d`) are in **meters**.
- When you set a pose derived from a **world source** (head or hand pose from
  ARCore), use **`Space.REAL_WORLD`**, not `Space.ACTIVITY`. `activitySpace`
  carries the movable/resizable panel scale (field: ~1.75×) that corrupts a
  world-derived pose.
- To place UI relative to the **head**: pose = `deviceState.devicePose.compose(offset)`
  in REAL_WORLD, offset rotation `Identity` (inherits head facing → screen-facing).
- To place UI on the **hand but facing the user**: position from the hand joint,
  **orientation from the head** — never compose with the hand's rotation (it goes
  edge-on and foreshortens). Offset along the hand→head vector, not a local axis.
  (Exception worth knowing: an element whose *whole point* is being legible from
  any wrist angle — a ring encircling the wrist — should deliberately follow the
  forearm instead. Billboarding it turns it back into a badge that can be faced
  away from.)

### Perception space ≠ activity space

ARCore hand/head poses arrive in **perception** space and must be converted
before you can place anything next to them:

```kotlin
val ps = session.scene.perceptionSpace
val worldPos = ps.getScenePoseFromPerceptionPose(joints[HandJointType.WRIST]!!)
    .poseInActivitySpace.translation
```

⚠️ Forgetting this does not throw — it puts your element somewhere plausible and
wrong, which is much harder to spot.

### ⚠️ `Quaternion.fromLookTowards(forward, up)` — pin the convention in a test

The KDoc says "forward and upward" and never says **which local axis each
becomes**. Measured on `androidx.xr.runtime` (2026-08):

| local axis | lands on |
|---|---|
| `+Z` | `forward` |
| `+Y` | `up` |
| `+X` | `up × forward` |

For a rotationally symmetric shape (a torus, a disc) the second argument does
not matter and you will never notice. For anything with a **long axis** — an
ellipse, a bar, a label row — getting it wrong rotates the shape a quarter turn
and the bug looks like bad geometry rather than a bad rotation.

✅ `Quaternion` is pure math in a plain `.kt`, so it is **JVM-testable with no
device**. Assert where the basis vectors land; if a library update changes the
convention you find out in CI rather than on somebody's hand.

---



---

## 6. ARCore for Jetpack XR: head + hands

⚠️ **All acquisition is blocking IPC — do it off the main thread**, or you ANR.

```kotlin
// Enable perception ONCE. Config REPLACES the whole set — pass the SUPERSET you need.
session.configure(Config(handTracking = HandTrackingMode.BOTH,
                         deviceTracking = DeviceTrackingMode.SPATIAL))

// Head pose (StateFlow) — read .value anywhere, or collect:
val dev = ArDevice.getInstance(session)           // ⚠️ THROWS if device tracking disabled
val headPose = dev.state.value.devicePose         // world/REAL_WORLD space

// Hands:
val hand = Hand.right(session)
hand.state.collect { st ->
  if (st.trackingState == TrackingState.TRACKING) {
    val anchor = st.handJoints[HandJointType.MIDDLE_METACARPAL]  // a Pose
    // position from anchor, orientation from head (see §5)
  }
}
```

Rules that prevent the classic bugs:
- Acquire on `Dispatchers.Default`; configure **at most once**; bound retries and
  park a fallback after N misses instead of hammering.
- Hand tracking needs the **`HAND_TRACKING` permission granted** — denied = "no
  hands", not an error. Request before the flow; **fail safe** (screen still
  works via panel buttons).
- `Config` is replace-not-merge: if two features configure separately, the second
  turns off the first's tracking. Centralize on one superset config.
- ⚠️ `HAND_TRACKING` is declared in the manifest **and** is a runtime permission;
  declaring it only earns the right to ask. Without the grant,
  `session.configure()` throws for the **whole call** — so requesting an optional
  gesture feature can take *device tracking* down with it. Configure defensively.

### The full joint set is richer than the examples suggest

Each finger exposes `_METACARPAL`, `_PROXIMAL`, `_INTERMEDIATE`, `_DISTAL`,
`_TIP`. Most sample code uses only proximal and tip, which is why so much
gesture code silently assumes straight fingers.

✅ **Measure against the bone polyline, not the chord.** A thumb sliding along a
curled index sits well off the straight line from knuckle to fingertip; a chord
measurement reads "not touching" while the fingers are plainly in contact.
Segment-wise nearest-point over `PROXIMAL → INTERMEDIATE → DISTAL → TIP` costs
nothing and is correct at any curl.

✅ **Express thresholds as fractions of the user's own anatomy**, never in
millimetres. Hands differ in size by far more than a gesture's tolerance. "Within
45% of *this* finger's length" holds across users; "within 25 mm" fails for
roughly half of them, and fails *silently*.

✅ **Clamp the projection parameter to [0,1] BEFORE taking the perpendicular.**
Otherwise a thumb held out past the fingertip measures its distance from an
infinite line and an open hand reads as contact.

✅ Degrade, don't drop: take intermediate joints with `listOfNotNull(...)` so a
partial tracking frame falls back to the chord instead of losing the gesture.

### Hardware capability is not uniform — check, don't assume

On Xreal Aura (2026-08) `adb shell dumpsys sensorservice` reports **no
magnetometer, no accelerometer and no eye tracking** exposed to apps
(`sensors: 0:, 32:FHS Dynamic Sensor Manager`). Anything needing true north or
gaze must be user-supplied or head-derived. Verify per device before designing
around a sensor.

---

## 7. Emulator & device workflow

- **Emulator** (Google XR API 34): great for compile, screen flow, and logic.
  ⚠️ Its simulated hands don't match real tracking — don't tune hand placement
  against it.
- **Server connectivity:** the emulator reaches your host at `10.0.2.2`. A real
  headset over USB uses `adb reverse`:
  ```bash
  adb reverse tcp:8000 tcp:8000        # headset's 127.0.0.1:8000 → your host
  ```
  Bake the server URL into `BuildConfig` (default `http://10.0.2.2:8000` for the
  emulator; pass `-PappServer=http://127.0.0.1:8000` for device builds) and add a
  debug `network-security-config` permitting cleartext to `127.0.0.1`/`localhost`.
- **Logcat is your primary debugger** on a device you're wearing. Tag everything
  consistently and log every state transition (see §9).

### ⚠️ Silence is usually the headset being off your face

An XR scene does not build until the device is **worn and tracking**. An app that
runs (`pidof` returns), does not crash, and logs *nothing at all* under its own
tag is almost always sitting on a desk. Three separate "the scene is broken"
investigations turned out to be this.

✅ Log the moment tracking settles (`pose settled`) so its **absence** is itself
a diagnosis. Do not begin debugging rendering until you have seen that line.

### ⚠️ `adb` traps that eat an afternoon

- **`adb shell` reads stdin**, so inside `for s in $(adb devices)` … `adb shell`
  swallows the rest of the loop's input and only the first device is ever
  probed. Redirect: `adb shell … </dev/null`.
- A dev machine typically has a **phone and the XR puck** attached; every bare
  `adb` call then fails with `more than one device/emulator`. Detect the XR one
  by feature and pin `ANDROID_SERIAL`:
  ```bash
  adb -s "$s" shell pm list features </dev/null | grep -q xr.api.spatial
  ```
- ⚠️ In a `set -u` wrapper script, **initialise the serial variable before the
  detection loop**. If no device matches, the later reference is an
  unbound-variable error and "the glasses are unplugged" presents as "the build
  tool is broken".

### `Method exceeds compiler instruction limit` in logcat

Large Compose lambdas (a spatial scene body easily exceeds 20k instructions)
log this per invocation. It is an **ART JIT notice, not an error** — the method
still runs, interpreted. Worth splitting the lambda for frame time, but it is
not the bug you are hunting.

---

## 8. Native OpenXR + Vulkan (only if you must)

Skip unless the managed layer can't render your content. If you do:

- Depend on the OpenXR loader AAR and consume its **prefab** CMake package
  (`OpenXR::openxr_loader`); it dispatches to the platform `libopenxr.google.so`.
- Standard OpenXR loop: create instance → system → Vulkan device (matching the XR
  graphics requirements) → session → swapchains → the **session state machine**
  (`READY → xrBeginSession`, `STOPPING → xrEndSession`, `EXITING → finish`).
- ⚠️ **Exit cleanly or crash the OS compositor.** On voluntary BACK, call
  `xrRequestExitSession()` and keep pumping events so the session drains
  `RUNNING → STOPPING → EXITING` before you finish the activity and destroy
  Vulkan objects. Never tear down while RUNNING (the compositor still holds your
  swapchains). Add a timeout so a stuck runtime can't hang you.
- ⚠️ **native_app_glue contract:** to leave voluntarily call
  `ANativeActivity_finish()` and keep pumping the looper until `APP_CMD_DESTROY`;
  returning from `android_main` early deadlocks onDestroy.
- **Foveation** (`XR_FB_foveation_vulkan` + `VK_EXT_fragment_density_map`): big
  fragment-throughput win, but with `fragmentDensityMapNonSubsampledImages` OFF,
  **every** attachment in the foveated render pass must be subsampled
  (`VK_IMAGE_CREATE_SUBSAMPLED_BIT_EXT`). Swapchain color images get it via the
  swapchain foveation flag; **your own depth/aux images must set it too** or the
  GPU page-faults mid-render.
- Gate every native GPU feature behind a **runtime flag defaulting OFF** (a flags
  file + a `debug.<app>.<feature>` system property for bisecting) so the stable
  path always ships and you enable one feature at a time on hardware.
- Prefer **data-only** optimizations first (e.g. importance-ordered LOD where any
  prefix of the buffer is a valid lower-detail model) — perf with no GPU-crash
  surface.

---

## 9. Debuggability & testing

- **Lifecycle logging.** One tag, `[feature] STATE` at every branch — especially
  the silent early-returns (permission denied, muted, fetch failed, capability
  missing). On glasses you can't attach a visual debugger to your face; the log
  must answer "did it even fire, and where did it stop?"
- **JVM unit tests** for pure logic. Set `unitTests.isReturnDefaultValues = true`
  so `android.util.Log`/audio stubs no-op instead of throwing `"Stub!"`.
  Synthesis, parsing, and math test cleanly headless.
- ✅ **If a test cannot construct your class, the arithmetic is in the wrong
  place.** A gesture test that needs a `Session` just to call a distance
  calculation is telling you the calculation is not spatial code. Lift pure
  geometry to file scope (or an object) and the test becomes trivial. Every
  on-glasses attempt at a threshold costs minutes; every JVM run costs
  milliseconds.
- ✅ **Keep pure classes pure.** Adding one `android.util.Log` call inside an
  otherwise-pure gesture classifier broke five tests at once. Log at the caller.
- ⚠️ **Write the test that proves your diagnosis, and believe it when it
  fails.** A test written to show "the old chord method fails where the new bone
  method passes" *failed* — the old method still passed at the loosened
  tolerance. The fix was real but the story about *why* was wrong, and only the
  test knew. Assert what the arithmetic supports, not what you hoped it did.
- **Instrumented tests** (`connectedDebugAndroidTest`) are the only tier that
  validates real DP **runtime contracts** (not just signatures) — run the
  critical ones on the emulator/device.
- **i18n:** bundle your string catalogs as APK assets for an offline baseline so
  the UI never shows raw keys when the server is unreachable; overlay the
  server's catalog on load. Add every new user-facing string in all locales in
  the same change.

---

## 10. First-week checklist

- [ ] JDK pinned to 17–21; `bin/` build wrapper in place
- [ ] `compileSdk 36 / minSdk 34`; XR deps pinned to exact alpha versions
- [ ] Manifest declares `xr.immersive` + the permissions you request at runtime
- [ ] A `Subspace { SpatialPanel { … } }` renders your first screen
- [ ] `Session.create(activity)` resolved once; capability-gated before 3D
- [ ] ARCore acquisition off-main-thread; one superset `Config`; fail-safe paths
- [ ] World-derived poses in `REAL_WORLD`; hand UI oriented to the head
- [ ] `adb reverse` + baked server URL working from a real headset
- [ ] Consistent lifecycle logging on one tag
- [ ] (native) clean `xrRequestExitSession` drain; GPU features flag-gated OFF
- [ ] Validate hand-relative placement on **real hardware**, not the emulator
- [ ] `[ADDITIVE]` One material per entity; no `setAlpha`; lit states are a second entity
- [ ] `[ADDITIVE]` Alpha-MASK materials so invisible fragments don't write depth
- [ ] `PanelEntity`: set `sizeInPixels`, then reach world size with `setScale`
- [ ] All geometry built at startup, hidden — never inside an input callback
- [ ] `fromLookTowards` axis convention pinned by a JVM test
- [ ] Perception poses converted via `getScenePoseFromPerceptionPose(...).poseInActivitySpace`
- [ ] Gesture thresholds expressed as fractions of the user's own bone lengths
- [ ] Pure geometry at file scope so it tests without a `Session`
- [ ] A `pose settled` log line, so its absence diagnoses "headset on the desk"

---

### See also
- `AndroidXR_Glasses_UX_Best_Practices.md` — the UX side of these lessons.
- `UX-XR-best-practices.md` — the WebXR/three.js stack, plus TUI and web.

### Field sources
- **RobotARme** (2026-07) — video passthrough, Compose spatial + native
  OpenXR/Vulkan. Toolchain, native exit, foveation, ANR/threading.
- **MeshmoreXR** (2026-08) — Xreal Aura, additive optical see-through,
  SceneCore + ARCore hands. §4a rendering realities, the coordinate-space and
  hand-tracking findings, and the testing discipline in §9.
