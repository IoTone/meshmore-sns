// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.xr.compose.platform.LocalSession
import androidx.xr.compose.platform.LocalSpatialCapabilities
import androidx.xr.compose.platform.requestFullSpace
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import com.iotj.meshmore.xr.spatial.Prims
import com.iotj.meshmore.xr.spatial.Rack
import androidx.xr.scenecore.scene
import androidx.xr.compose.platform.requestHomeSpace
import androidx.xr.compose.spatial.Subspace
import androidx.xr.compose.subspace.SpatialPanel
import androidx.xr.compose.subspace.layout.SubspaceModifier
import androidx.xr.compose.subspace.layout.height
import androidx.xr.compose.subspace.layout.offset
import androidx.xr.compose.subspace.layout.rotate
import androidx.xr.compose.subspace.layout.width
import com.iotj.meshmore.xr.spatial.Boot
import com.iotj.meshmore.xr.spatial.Dock
import com.iotj.meshmore.xr.spatial.Glyphs
import com.iotj.meshmore.xr.spatial.Hands
import com.iotj.meshmore.xr.spatial.HelpCard
import com.iotj.meshmore.xr.spatial.HereMark
import com.iotj.meshmore.xr.spatial.Horizon
import com.iotj.meshmore.xr.spatial.Lens
import com.iotj.meshmore.xr.spatial.RadialMenu
import com.iotj.meshmore.xr.spatial.Hud
import com.iotj.meshmore.xr.spatial.MeshNodes
import com.iotj.meshmore.xr.spatial.Notice
import com.iotj.meshmore.xr.spatial.Stage
import com.iotj.meshmore.xr.spatial.Unfold
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.scale
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.shape.GenericShape
import io.iotone.meshcore.android.SessionState
import io.iotone.meshcore.MeshcoreBle
import io.iotone.meshcore.MeshcoreConstants
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.random.Random

/**
 * P0 checkpoints 1 + 2.
 *
 * 1. toolchain: builds with compileSdk 36 + Jetpack XR, installs, launches, and
 *    the composite build to libmeshcore links AT RUNTIME (constants read below).
 * 2. spatial: `Subspace { SpatialPanel { } }` renders once the app holds spatial
 *    UI capability.
 *
 * TWO THINGS THE DEVICE TAUGHT US, both of which change how this is written:
 *
 *  - The Aura reports `xr.api.spatial = YES` but `xr.immersive = no`. Gating on
 *    the immersive feature (as the starter guide suggests) would have rejected
 *    the APK at install. Capability gating keys off LocalSpatialCapabilities.
 *
 *  - An XR app starts in HOME SPACE, i.e. an ordinary 2D window, where
 *    isSpatialUiEnabled is false. Full Space has to be *requested*, and
 *    requestFullSpace() is a suspend function. So spatial UI is a state the app
 *    transitions into, never something to assume at startup.
 */
class MainActivity : ComponentActivity() {

    companion object {
        const val TAG = "MeshmoreXR"
        /** Set by the launch intent; read by HorizonScene. */
        var selfTest: Boolean = false
        /** --ez sim true : draw the fake ring instead of the radio's mesh. */
        var simulate: Boolean = false
        /** --ez radio true : bring the RADIO rack up alongside the horizon. */
        var showRadio: Boolean = false
        /**
         * --ez help true : bring the GESTURE CARD up at launch.
         *
         * Unlike the radio rack, which stays closed on principle because a
         * launch flag onto live controls is the same hazard as leaving them
         * standing, this card is inert: it says what the hands can do and
         * touches nothing. Being able to open it without a hand in front of the
         * glasses is the only way to check it renders.
         */
        var showHelp: Boolean = false
        /**
         * --ez menu true : open the cluster menu on the first cluster found.
         *
         * The menu only appears by pinching a cluster mote, so nothing about it
         * can be checked without a hand in front of the glasses — which is how
         * it shipped with no focus state at all and nobody noticed.
         */
        var showMenu: Boolean = false
        /** --ez focus true : open S3 NODE FOCUS on the first node that arrives. */
        var showFocus: Boolean = false
        /**
         * --ez probe true : message the operator's OWN nodes, once, to make
         * the mesh learn a route to them.
         *
         * Off by default and deliberately a launch flag rather than anything
         * automatic: this transmits. The targets are allow-listed in MeshLink
         * and the flag cannot widen them.
         */
        var probePaths: Boolean = false
        /**
         * --es telperm "battery,location,environment", each of deny|contacts|anyone.
         *
         * The rack is where this belongs (§9.5 lists it as a TUMBLER) and that
         * is still owed. Until then this makes the setting reachable rather
         * than merely implemented, because a permission you cannot change is
         * not a permission you control.
         */
        var telPerm: String? = null
        /** --ez handdebug true : log what the ASL classifier measures, ~1 Hz. */
        var handDebug: Boolean = false
        /** --ez typeprobe true : answer whether tier R can exist on this SDK. */
        var typeProbe: Boolean = false
        /**
         * --es north "<deg>" : the TRUE heading you are facing at launch.
         *
         * The Aura publishes no magnetometer and no accelerometer to apps — the
         * IMU belongs to the XR runtime — so the device cannot find north by
         * itself, and every node's bearing comes from lat/lon and is therefore
         * measured from true north. Telling the app which way you were pointing
         * is the only offline way to reconcile the two.
         *
         * Face north and pass 0; face east and pass 90. Null means the ring
         * stays relative to the launch facing, which is what it has always done.
         */
        var northDeg: Float? = null
        /** --es home "lat,lon" : our position when the radio has no GPS. */
        var homeOverride: MeshNodes.Here? = null
        /**
         * Activity starts within this PROCESS. Survives recreation, dies with
         * the process, so it separates "the Activity came back" from "the whole
         * app was killed and relaunched".
         */
        var starts: Int = 0
    }

    // One link per activity. Checkpoint 3 lives here.
    private val link by lazy { MeshLink(this) }

    override fun onStop() {
        super.onStop()
        Log.i(TAG, "[boot] onStop — finishing=$isFinishing changing=$isChangingConfigurations")
    }

    override fun onDestroy() {
        link.close()
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // WHICH KIND OF START THIS IS.
        //
        // Everything the session holds — the lens stack, which surfaces are
        // open, where the origin was taken — lives in Compose `remember`, so an
        // Activity recreation silently resets all of it and the user is
        // returned to an unmagnified ring at the home orientation with no event
        // to explain it. That is indistinguishable, from the outside, from a
        // gesture having fired. This line tells the two apart after the fact.
        starts += 1
        Log.i(TAG, "[boot] onCreate — ${Build.MANUFACTURER} ${Build.MODEL} " +
            "api=${Build.VERSION.SDK_INT} start=#$starts " +
            (if (savedInstanceState != null) "RESTORED (activity recreated)"
             else if (starts > 1) "fresh activity, SAME process"
             else "fresh process"))

        val facts = collectFacts()
        facts.forEach { (k, v) -> Log.i(TAG, "[boot] $k = $v") }

        // The radio's PIN is random per boot (MyMesh.cpp:932), so allow it to be
        // supplied at launch:  adb shell am start -n .../.MainActivity --es pin 123456
        val pin = intent?.getStringExtra("pin")
        Log.i(TAG, "[boot] pin override = ${pin ?: "<none, using built-in>"}")
        val debug = intent?.getBooleanExtra("debug", false) ?: false
        Log.i(TAG, "[boot] debug surface = $debug")
        selfTest = intent?.getBooleanExtra("selftest", false) ?: false
        Log.i(TAG, "[boot] selftest = $selfTest")
        typeProbe = intent?.getBooleanExtra("typeprobe", false) ?: false
        showRadio = intent?.getBooleanExtra("radio", false) ?: false
        handDebug = intent?.getBooleanExtra("handdebug", false) ?: false
        showHelp = intent?.getBooleanExtra("help", false) ?: false
        showMenu = intent?.getBooleanExtra("menu", false) ?: false
        showFocus = intent?.getBooleanExtra("focus", false) ?: false
        probePaths = intent?.getBooleanExtra("probe", false) ?: false
        telPerm = intent?.getStringExtra("telperm")
        northDeg = intent?.getStringExtra("north")?.toFloatOrNull()
        Log.i(TAG, "[boot] north at launch = " +
            (northDeg?.let { "%.0f° true".format(it) } ?: "<unknown, ring is relative>"))
        // Draw every tier R panel's own boundary. See TextRun.outline.
        com.iotj.meshmore.xr.spatial.TextRun.outline =
            intent?.getBooleanExtra("outline", false) ?: false
        Log.i(TAG, "[boot] radio rack = $showRadio")
        simulate = intent?.getBooleanExtra("sim", false) ?: false
        Log.i(TAG, "[boot] simulate = $simulate")
        homeOverride = intent?.getStringExtra("home")?.split(",")?.let { parts ->
            val la = parts.getOrNull(0)?.trim()?.toDoubleOrNull()
            val lo = parts.getOrNull(1)?.trim()?.toDoubleOrNull()
            if (la != null && lo != null) MeshNodes.Here(la, lo) else null
        }
        Log.i(TAG, "[boot] home override = ${homeOverride ?: "<none, using radio GPS>"}")
        // Until the spatial settings surface exists, the toggle is reachable
        // from the launch intent:  --ez devloc true
        if (intent?.hasExtra("devloc") == true) {
            Settings.setUseDeviceLocation(this, intent.getBooleanExtra("devloc", false))
        }
        Log.i(TAG, "[boot] device-location fallback = ${Settings.useDeviceLocation(this)}")
        // A flood advert reaches the whole mesh through every repeater that
        // hears it. That is someone else's airtime, so it is opt-in per launch:
        //   --ez flood true
        if (intent?.hasExtra("diag") == true) {
            Settings.setDiagnostics(this, intent.getBooleanExtra("diag", true))
        }
        Log.i(TAG, "[boot] diagnostics panel = ${Settings.diagnostics(this)}")
        link.floodOnConnect = intent?.getBooleanExtra("flood", false) == true
        Log.i(TAG, "[boot] connect advert = ${if (link.floodOnConnect) "FLOOD" else "zero-hop"}")
        setContent { MaterialTheme { Root(facts, link, pin, debug) } }
        Log.i(TAG, "[boot] setContent done")
    }

    private fun collectFacts(): List<Pair<String, String>> {
        val xrFeatures = listOf(
            "android.software.xr.immersive",
            "android.software.xr.api.spatial",
            "android.software.xr.api.openxr",
            "android.hardware.xr.input.hand_tracking",
        ).map { it to packageManager.hasSystemFeature(it) }

        return buildList {
            add("app" to "${BuildConfig.APPLICATION_ID} ${BuildConfig.VERSION_NAME}")
            add("device" to "${Build.MANUFACTURER} ${Build.MODEL} (${Build.DEVICE})")
            add("android" to "${Build.VERSION.RELEASE} / API ${Build.VERSION.SDK_INT}")
            xrFeatures.forEach { (name, present) ->
                add(name.removePrefix("android.") to if (present) "YES" else "no")
            }
            // proof the composite build links at runtime, not just at compile time
            add("libmeshcore pin" to MeshcoreConstants.FIRMWARE_PIN_TAG)
            add("libmeshcore commit" to MeshcoreConstants.FIRMWARE_PIN_COMMIT.take(12))
            add("meshcore BLE svc" to MeshcoreBle.SERVICE_UUID.take(13) + "…")
        }
    }
}

// HALO FIELD — the chosen default theme (design brief §7.11).
private val Ground = Color(0xFF070B10)
private val Panel = Color(0xFF101722)
private val Accent = Color(0xFF35E0F0)
private val TextC = Color(0xFFDDE7EF)
private val Dim = Color(0xFF6C8296)
private val Ok = Color(0xFF7CFF6B)

@Composable
private fun Root(facts: List<Pair<String, String>>, link: MeshLink, pinOverride: String?, debug: Boolean) {
    val caps = LocalSpatialCapabilities.current
    val spatial = caps.isSpatialUiEnabled
    val activity = LocalContext.current as? ComponentActivity

    // Every transition logged: on a device you are wearing, logcat is the only
    // debugger, and the silent early-return is what you need to see.
    LaunchedEffect(spatial) {
        Log.i(TAG_UI, "[spatial] isSpatialUiEnabled=$spatial isContent3d=${caps.isContent3dEnabled}")
    }

    // MeshmoreXR is a spatial app, so it asks for Full Space itself rather than
    // waiting for a tap -- an XR app always starts in Home Space (a 2D window).
    // Requested ONCE: the request is a suspend call that can be refused, and
    // retrying on every recomposition would hammer it.
    var requested by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        val a = activity ?: return@LaunchedEffect
        if (requested || spatial) return@LaunchedEffect
        requested = true
        val res = a.requestFullSpace()
        Log.i(TAG_UI, "[spatial] auto requestFullSpace -> $res")
    }

    // "Always-on mesh" (design brief section 3) means the radio links itself;
    // the user should never have to ask for the mesh. Attempted ONCE -- a retry
    // loop on a failed scan would burn the radio and the battery. Reconnect
    // with backoff is a later concern (S2 LINK).
    var linkTried by remember { mutableStateOf(false) }

    fun dial() {
        if (linkTried) return
        linkTried = true
        Log.i(TAG_UI, "[link] auto-connect at startup")
        if (pinOverride != null) link.connect(pin = pinOverride) else link.connect()
    }

    // THE REASON THE LINK NEVER CONNECTED. The app logged "no BLE permission --
    // waiting for user" and then waited forever, because nothing ever asked.
    // BLUETOOTH_SCAN and BLUETOOTH_CONNECT are runtime permissions on API 31+,
    // and the grant dialog is the system's own. That makes it the sanctioned
    // tier-P escape hatch (typography plan §2): a system surface we do not own,
    // shown once, rather than a panel of ours.
    val askBle = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { granted ->
        val ok = granted.values.all { it }
        Log.i(TAG_UI, "[link] BLE permission granted=$ok $granted")
        if (ok) dial() else Log.w(TAG_UI, "[link] BLE denied — mesh will stay empty")
    }

    LaunchedEffect(Unit) {
        if (link.hasBlePermissions()) dial()
        else askBle.launch(
            buildList {
                add(android.Manifest.permission.BLUETOOTH_SCAN)
                add(android.Manifest.permission.BLUETOOTH_CONNECT)
                // Asked for in the same prompt ONLY when the user already
                // enabled the fallback. Requesting location from someone who
                // never turned it on is exactly the kind of thing that makes
                // people deny the whole dialog.
                if (Settings.useDeviceLocation(activity ?: return@buildList)) {
                    add(android.Manifest.permission.ACCESS_FINE_LOCATION)
                }
                // HAND_TRACKING is declared in the manifest and is still a
                // RUNTIME permission — declaring it only earns the right to
                // ask. Without the grant, session.configure() throws for the
                // whole call, which is how requesting an optional gesture
                // feature managed to take device tracking down with it.
                add("android.permission.HAND_TRACKING")
            }.toTypedArray()
        )
    }

    if (spatial) {
        // P1 — the HORIZON is REAL GEOMETRY in the room, not a panel. The panel
        // below is a development readout only, deliberately small and pushed
        // aside; it is not the experience.
        // NO PANEL. The spatial experience is geometry only -- floor, mesh,
        // callsigns. The diagnostic readout is a DEBUG SURFACE and is opt-in:
        //     adb shell am start -n .../.MainActivity --ez debug true
        // Launching into a panel is what makes an XR app feel like a phone app
        // that happens to be floating.
        HorizonScene(link)
        // TIER R, THE ONLY REMAINING PATH — a transparent panel carrying one run.
        //
        // The texture route is closed (TypeProbe): Texture.create resolves
        // against the AssetManager, so a string composed at runtime can never
        // become a sampled texture on this SDK. Compose can still rasterise it,
        // and the question this answers is whether the panel it arrives on
        // behaves like ink in the room or like a pane of glass.
        //
        // Three things to look for in the capture, in order of severity:
        //   1. does it OCCLUDE the horizon behind it (mainPanelEntity does)
        //   2. is there a visible RECTANGLE on an additive display
        //   3. do the kanji and the emoji render at all
        if (MainActivity.typeProbe) {
            Subspace {
                SpatialPanel(
                    SubspaceModifier.width(420.dp).height(150.dp)
                        .offset(x = (-260).dp, y = 150.dp, z = 300.dp)
                ) {
                    Column(
                        Modifier.fillMaxSize().background(Color.Transparent),
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text("\u4e2d\u7d99\u5c40 ABC", color = Color(0xFF66E8D0), fontSize = 34.sp)
                        Text("ESTACADA \u306e\u5fdc\u7b54\u306a\u3057", color = Color(0xFFDDE7EF), fontSize = 22.sp)
                    }
                }
            }
        }
        if (debug) {
            Subspace {
                SpatialPanel(SubspaceModifier.width(560.dp).height(420.dp)) {
                    DiagnosticSurface { StatusScreen(facts, link, spatial = true) }
                }
            }
        }
        // RADIO TRAFFIC — a conventional scrolling panel, off to the right.
        //
        // Everything else in this app refuses to be a panel on principle. This
        // one is a panel ON PURPOSE: it is an instrument for finding out why
        // the mesh is not doing what you expect, and a scrolling transcript of
        // decoded frames is genuinely the right shape for that. Making it
        // spatial would make it worse.
        //
        // Pushed to the right and turned away from the forward arc so it never
        // sits in front of the horizon. Default ON while the advert path is
        // still in question; `--ez diag false` turns it off.
        if (Settings.diagnostics(LocalContext.current)) {
            Subspace {
                SpatialPanel(
                    SubspaceModifier
                        .width(520.dp).height(760.dp)
                        .offset(x = 620.dp, z = (-140).dp)
                        .rotate(androidx.xr.runtime.math.Vector3(0f, 1f, 0f), -34f)
                ) {
                    RadioLogPanel(link)
                }
            }
        }
    } else {
        // Home Space is a 2D window we are only ever passing through: the app
        // requests Full Space immediately. Showing the full readout here is what
        // made the launch look like a mobile app, so this is a holding state.
        HoldingScreen()
    }
}

private const val TAG_UI = "MeshmoreXR"

/**
 * How long after a 'B' back-out a second one is ignored, whichever hand sends
 * it. Long enough to cover both hands settling into a flat rest at slightly
 * different moments, short enough that deliberately stepping out two levels
 * still feels immediate.
 */
private const val BACK_OUT_MS = 600L

/**
 * How far from a cluster's stated bearing a node counts as belonging to it.
 * The cluster's own bearing is the MEAN of its members, so the grab has to be
 * wide enough to reach the ones at the edges — CLUSTER_RAD is the bucket width
 * they were grouped into, and a little over that covers the spread.
 */
private val CLUSTER_GRAB = MeshNodes.CLUSTER_RAD * 0.75f

/**
 * How wide to grab, at magnification [depth].
 *
 * The grab is in TRUE bearing, and each level of magnification means the
 * cluster you just pinched covers a proportionally narrower slice of the real
 * world. Using one width at every depth would, on the second level, scoop up
 * the entire wedge again — you would magnify and get exactly what you were
 * already looking at, which reads as the button not working.
 */
private fun grabFor(depth: Int): Float =
    CLUSTER_GRAB / Math.pow(6.0, depth.toDouble()).toFloat()

/** Minimum time the boot surface stays up, so a fast sync is not a flicker. */
private const val MIN_BOOT_S = 4.5f

/**
 * Hard ceiling on the loading surface. A live 280-contact sync takes ~16 s, so
 * this is generous -- it exists to guarantee the experience starts, not to cut
 * a healthy load short.
 */
private const val MAX_BOOT_S = 28f

/**
 * The only rectangle in the app, and it does not arrive like one: a targeting
 * reticle punches in, tears, then unfolds vertically from a slit with the
 * content fading up inside it. Diagnostics earn a panel; nothing else does.
 */
/** Passing through home space. Deliberately almost nothing. */
@Composable
private fun HoldingScreen() {
    Box(Modifier.fillMaxSize().background(Ground)) {
        Text(
            "MESHMORE XR",
            color = Accent, fontSize = 22.sp,
            fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.align(Alignment.Center),
        )
    }
}

@Composable
private fun DiagnosticSurface(content: @Composable () -> Unit) {
    val t = Unfold.rememberClock(durationMs = 1100)
    Unfold.Frame(t = t, accent = Accent, alt = Ok) { contentAlpha, foldOpen ->
        Box(
            Modifier
                .fillMaxSize()
                .clipToBounds()
                // scale on Y only: the content unfolds with the frame rather
                // than sliding in behind it
                .scale(scaleX = 1f, scaleY = foldOpen.coerceAtLeast(0.001f))
                .alpha(contentAlpha)
        ) { content() }
    }
}

/**
 * P1 — builds the HORIZON as MeshEntities in world space and drives its pulses.
 *
 * Bearings are simulated for now: the radio only reports a peer's position when
 * that peer advertised one (ADV_LATLON), and on a bench neither of ours does.
 * Faking a bearing for an unlocated node is explicitly forbidden by the brief,
 * so those park in the unlocated arc instead. Real bearings arrive with S3.
 */
/**
 * The fake ring. No longer the default -- it exists so the rendering, the
 * label pipeline and the interaction can be exercised with no radio present,
 * which is most of the time. The names deliberately include the shapes real
 * MeshCore names take: emoji, fullwidth Latin, accents, kana, and a name that
 * is nothing but emoji.
 */
private fun simulatedMesh(): List<Horizon.Node> {
    val names = listOf(
        "kanako.1", "davi1 \uD83D\uDE80", "relay-nw", "t1000-e", "gate-cam",
        "\uD83D\uDC22 turtle relay", "\uFF2F\uFF2B\uFF41\uFF59", "shed",
        "\u00D6konomy", "\u3042\u304D\u306F\u3070\u3089", "\uD83C\uDF0A\uD83C\uDF0A",
    )
    return names.mapIndexed { i, nm ->
        Horizon.Node(
            name = nm,
            bearingRad = (i.toFloat() / names.size * 2f * PI.toFloat()) + (i % 3) * 0.22f,
            elev = kotlin.math.sin(i * 2.1f) * 0.34f,
            dist = 0.28f + ((i * 37) % 100) / 140f,
            age = ((i * 53) % 100) / 100f,
            located = !nm.startsWith("shed"),
            hops = 1 + (i % 3),
        )
    }
}

@Composable
private fun HorizonScene(link: MeshLink) {
    val session = LocalSession.current ?: return
    val ctx = LocalContext.current
    val hereSource = remember { HereSource(ctx) }

    // LIVE MESH. The horizon is whatever the radio can actually see; the
    // simulated ring is now opt-in (--ez sim true) and exists only so the
    // rendering can be exercised with no hardware present.
    val mesh by link.mesh.collectAsState()
    val here by link.here.collectAsState()
    val load by link.load.collectAsState()
    val status by link.status.collectAsState()

    // Rebuild on MEMBERSHIP change, not on every frame the radio speaks. An
    // advert arrives with a fresh timestamp several times a minute per node,
    // and rebuilding the horizon on each one would dispose and re-create every
    // entity -- destroying hover state and the user's open selections while
    // they are looking at them.
    val signature = remember(mesh) { mesh.joinToString(",") { "${it.key}:${it.lat != null}" } }

    val horizonRef = remember { mutableStateOf<Horizon?>(null) }
    val stageRef = remember { mutableStateOf<Stage?>(null) }
    val originRef = remember { mutableStateOf<Stage.Origin?>(null) }
    val nodesRef = remember { mutableStateOf<List<Horizon.Node>>(emptyList()) }
    val bootRef = remember { mutableStateOf<Boot?>(null) }
    val hudRef = remember { mutableStateOf<Hud?>(null) }
    val hereMarkRef = remember { mutableStateOf<HereMark?>(null) }
    val rackRef = remember { mutableStateOf<Rack?>(null) }
    val dockRef = remember { mutableStateOf<Dock?>(null) }
    val handsRef = remember { mutableStateOf<Hands?>(null) }
    val menuRef = remember { mutableStateOf<RadialMenu?>(null) }
    val focusRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.Focus?>(null) }
    val gazeRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.Gaze?>(null) }
    val rosterRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.Roster?>(null) }
    val noticeRef = remember { mutableStateOf<Notice?>(null) }
    // The wedge currently magnified, or null for the true 1:1 ring. Bumping
    // hereEpoch is what makes the mesh effect re-run and re-place everything.
    /**
     * The magnification STACK, outermost first. Empty is the true 1:1 ring.
     *
     * A stack rather than a single lens because the user asked the right
     * question: magnifying 106 nodes across the ring still cannot label all of
     * them — four lanes hold about 120 evenly spread, and they are never evenly
     * spread — so the magnified view has clusters of its own, and those want
     * going into too. Depth has to be a first-class thing rather than a case.
     *
     * Every lens is defined over TRUE bearings and composed by unmapping first,
     * so the third level is the same arithmetic as the first.
     */
    val lensStack = remember { mutableStateListOf<Lens>() }
    val helpRef = remember { mutableStateOf<HelpCard?>(null) }
    val cue = remember { Cue() }
    // Bumped by the HERE marker so the mesh rebuild below re-runs on a toggle.
    val hereEpoch = remember { mutableStateOf(0) }

    // The mesh, rebuilt whenever membership changes.
    // TELEMETRY PERMISSIONS, if the launch asked to change them. Not in the
    // scene effect for the same reason the probe is not: it is a radio setting
    // and has nothing to do with a head pose.
    LaunchedEffect(link, MainActivity.telPerm) {
        val spec = MainActivity.telPerm ?: return@LaunchedEffect
        while (link.status.value.selfInfo == null) kotlinx.coroutines.delay(500)
        val want = spec.split(",").map { it.trim().lowercase() }
        fun lvl(s: String?) = when (s) {
            "anyone", "all" -> com.iotj.meshmore.xr.spatial.TelemetryPerms.ALLOW_ALL
            "contacts", "flags" -> com.iotj.meshmore.xr.spatial.TelemetryPerms.ALLOW_FLAGS
            else -> com.iotj.meshmore.xr.spatial.TelemetryPerms.DENY
        }
        val p = com.iotj.meshmore.xr.spatial.TelemetryPerms.Perms(
            base = lvl(want.getOrNull(0)),
            location = lvl(want.getOrNull(1)),
            environment = lvl(want.getOrNull(2)),
        )
        Log.i(TAG_UI, "[telemetry] was ${link.telemetryPermissions()}, setting $p")
        link.setTelemetryPermissions(p)
    }

    // THE PATH PROBE, deliberately NOT inside the scene effect.
    //
    // Sending is a radio action and has nothing to do with the head. The scene
    // effect blocks on Stage.recentre() until a head pose settles, so putting
    // it there meant the probe never ran while the glasses sat on a desk —
    // which is precisely when it is convenient to run one.
    LaunchedEffect(link, MainActivity.probePaths) {
        if (!MainActivity.probePaths) return@LaunchedEffect
        // Wait for the first contact sync so the allow-listed keys are known.
        while (!link.load.value.done) kotlinx.coroutines.delay(500)
        link.probePaths()
        // Then long enough for a reply to come back and teach the radio a
        // route, and re-sync so the new path is visible to the census.
        kotlinx.coroutines.delay(60_000)
        link.refreshContacts()
    }

    LaunchedEffect(signature, here, horizonRef.value, hereEpoch.value) {
        // DEBOUNCE. A contact sync delivers the whole list one frame at a time
        // -- 58 contacts arrived as 58 separate membership changes, and without
        // this the scene is disposed and rebuilt 58 times in 1.5 s. LaunchedEffect
        // cancels on key change, so a delay here means only the last one runs.
        kotlinx.coroutines.delay(700)
        val h = horizonRef.value ?: return@LaunchedEffect
        val st = stageRef.value ?: return@LaunchedEffect
        val o = originRef.value ?: return@LaunchedEffect
        // WHERE WE ARE. The companion radio reports its own position, but a
        // board with no GPS reports 0/0 -- and without an origin no bearing can
        // be computed, so every peer parks in the unlocated arc however good
        // its own position is. `--es home "lat,lon"` lets the operator state
        // where they are. That is not a fabricated bearing: the brief forbids
        // inventing a peer's position, not being told our own.
        val origin2 = hereSource.resolve(here, MainActivity.homeOverride)
        val lens = lensStack.lastOrNull()
        // Tell the mesh where we are, using the SAME fix the horizon is drawn
        // from, so what we broadcast and what we draw cannot disagree.
        if (Settings.shareLocation(ctx)) link.publishPosition(origin2)
        val nodes = if (MainActivity.simulate) simulatedMesh() else
            MeshNodes.build(origin2, mesh, System.currentTimeMillis() / 1000, lens = lens)
        // Count what was DRAWN, not what the cap would have dropped. The old
        // form was peers.size - MAX_MOTES, which stopped being true the moment
        // placement became fit-driven: a saturated bearing labels five nodes,
        // not twenty-four, and reporting the cap hid that entirely.
        val clusters = nodes.filter { it.cluster > 0 }
        Log.i(TAG_UI, "[horizon] building ${nodes.size} motes " +
            "(${if (MainActivity.simulate) "SIMULATED" else "live"}, " +
            "fix=${origin2.known} via ${hereSource.source}, " +
            "labelled=${nodes.count { it.cluster == 0 }}" +
            (if (clusters.isEmpty()) "" else
                ", ${clusters.size} cluster(s) holding ${clusters.sumOf { it.cluster }}") +
            ", of ${mesh.size} peers" +
            (lens?.let { ", MAGNIFIED $it" } ?: "") + ")")
        nodesRef.value = nodes
        h.build(nodes, o, st.floorHeight())
        // WHERE AM I, on the one surface that is always there.
        dockRef.value?.let { d ->
            // Pinned only while magnified: at 1:1 there is nothing to say and
            // an always-on caption is one more thing between the user and the
            // room.
            d.setCaption("WIDE", if (lens == null) null else "OUT x${lensStack.size}")
            d.setLit("WIDE", lens != null)
        }
    }

    LaunchedEffect(session) {
        // THE PANEL YOU CANNOT SEE IN CODE. Entering Full Space does not remove
        // the Activity's own window -- it becomes `mainPanelEntity` and keeps
        // rendering, so the app appears as a big opaque rectangle floating in
        // the room even when setContent() draws nothing but a wordmark. It also
        // occludes everything behind it, which hides the geometry we came here
        // to show. Disabling it is what actually makes the app spatial.
        runCatching { session.scene.mainPanelEntity.setEnabled(false) }
            .onFailure { Log.w(TAG_UI, "[spatial] main panel still visible: $it") }

        val palette = Horizon.Palette(
            accent = 0x35E0F0, alt = 0x7CFF6B, warn = 0xFFB020, text = 0xDDE7EF,
        )
        // Recentre on the body BEFORE building anything, or the whole
        // experience can end up behind the user.
        val stage = Stage(session, palette)
        val origin0 = stage.recentre()
        // WHICH WAY IS NORTH. Every node's bearing comes from real lat/lon, so
        // it is measured from TRUE north — while place() measures from the
        // launch facing. They agree only if the wearer happened to start facing
        // north, and otherwise the whole ring is rotated by the difference.
        //
        // Measured now, APPLIED only when Heading.TRUST says the convention has
        // been checked against a real compass. Android's azimuth is written for
        // a phone's frame and this is a headset; a confidently wrong north
        // looks authoritative, which is worse than an honestly relative one.
        val fix = com.iotj.meshmore.xr.spatial.Heading.read(
            ctx,
            MainActivity.homeOverride?.lat, MainActivity.homeOverride?.lon, null,
        )
        val told = MainActivity.northDeg
        val origin = when {
            // What the wearer says, first. A person with a compass is a better
            // heading source than a headset with no magnetometer.
            told != null -> {
                Log.i(TAG_UI, "[heading] ring is NORTH-REFERENCED from --es north $told")
                origin0.copy(
                    yawRad = origin0.yawRad - Math.toRadians(told.toDouble()).toFloat(),
                )
            }
            fix != null && com.iotj.meshmore.xr.spatial.Heading.TRUST -> {
                Log.i(TAG_UI, "[heading] ring is NORTH-REFERENCED from the sensor")
                origin0.copy(yawRad = origin0.yawRad - fix.trueRad)
            }
            else -> {
                Log.w(TAG_UI, "[heading] ring is RELATIVE to launch facing — " +
                    "'N' means 'the way you were pointing', not north")
                origin0
            }
        }

        val horizon = Horizon(session, palette, ctx)
        // Deliberately includes the shapes real MeshCore names take: emoji,
        // fullwidth Latin, accents, kana, and a name that is nothing BUT emoji.
        // If any of these can break the label path, better it breaks here.
        // Floor first: the room claims itself, then the mesh arrives on top.
        stage.buildFloor(origin)
        // The boot surface goes up immediately -- the wait it covers starts
        // now, not when the first contact arrives.
        val boot = Boot(session, palette)
        boot.build(origin)
        bootRef.value = boot
        val hud = Hud(session, palette)
        hud.build()
        hudRef.value = hud
        // THE RADIO RACK, built but NOT SHOWN. Settings are summoned from the
        // dock; leaving a live radio configuration standing in the room is how
        // it gets changed by someone reaching for something else.
        val rack = Rack(session, palette, ctx, link.radio)
        rack.onCommit = { link.commitRadio() }
        rack.onRevert = { link.revertRadio() }
        rack.build(origin)
        rack.setVisible(false)
        rackRef.value = rack

        // HANDS. The Aura reports hand tracking and nothing else, so a shape the
        // hand makes is the only command that costs neither world space nor a
        // glance — which is what "turn the HUD off" needs, since you want it
        // mid-stride without looking at anything.
        val handR = runCatching { androidx.xr.arcore.Hand.right(session) }.getOrNull()
        val handL = runCatching { androidx.xr.arcore.Hand.left(session) }.getOrNull()
        val gateR = com.iotj.meshmore.xr.spatial.HandSign.Gate()
        val gateL = com.iotj.meshmore.xr.spatial.HandSign.Gate()
        // EITHER HAND BACKS OUT, but only one level per press.
        //
        // 'B' is a flat hand, and a flat hand is what BOTH hands are doing when
        // you rest them. The two gates are independent, so with the command
        // bound on each hand a two-handed rest fires it twice in the same frame
        // and drops two levels at once — the exact failure the right-hand-only
        // version was written to avoid, doubled. One shared debounce is what
        // makes the symmetry safe.
        var lastBackAt = 0L
        var lastShapeR = ""
        var lastShapeL = ""
        Log.i(TAG_UI, "[hand] tracking right=${handR != null} left=${handL != null}")

        val menu = RadialMenu(session, palette)
        menu.build(listOf(
            RadialMenu.Item("magnify", "MAGNIFY"),
            RadialMenu.Item("bearing", "BEARING"),
            RadialMenu.Item("nearest", "NEAREST"),
            RadialMenu.Item("dismiss", "CLOSE"),
        ))
        menuRef.value = menu
        val focus = com.iotj.meshmore.xr.spatial.Focus(session, palette, ctx)
        focus.build()
        focusRef.value = focus

        val notice = Notice(session, palette, ctx)
        notice.build()
        noticeRef.value = notice

        val hands = Hands(session, palette, ctx)
        hands.build()
        handsRef.value = hands
        val help = HelpCard(session, palette, ctx)
        help.build(origin)
        helpRef.value = help

        // Roster picks, queued: Focus.showFor builds the spur and therefore
        // suspends, and a dock action is not a coroutine. Same shape as the
        // node-pinch queue below.
        val rosterWant = java.util.concurrent.ConcurrentLinkedQueue<
            com.iotj.meshmore.xr.spatial.Horizon.Node>()
        val dock = Dock(session, palette, ctx)
        // EVERY SURFACE HAS A PINCHABLE WAY IN, gesture or no gesture.
        //
        // The ASL toggles are the fast path -- no glance, no target, usable
        // mid-stride -- but a gesture that fails is indistinguishable from a
        // feature that does not exist, and hand tracking can be PAUSED for
        // reasons the user cannot see (hands out of the camera's view being the
        // common one). A surface reachable ONLY by gesture is a surface that is
        // sometimes unreachable.
        dock.build(origin, listOf(
            "COMPASS" to {
                hudRef.value?.let { h ->
                    h.setUpper(!h.upperOn); dockRef.value?.setLit("COMPASS", h.upperOn)
                }
            },
            "LINK" to {
                hudRef.value?.let { h ->
                    h.setLower(!h.lowerOn); dockRef.value?.setLit("LINK", h.lowerOn)
                }
            },
            "RADIO" to {
                val next = !(rackRef.value?.visible ?: false)
                rackRef.value?.setVisible(next)
                dockRef.value?.setLit("RADIO", next)
                if (next) cue.opened() else cue.closed()
            },
            "HELP" to {
                val next = !(helpRef.value?.visible ?: false)
                helpRef.value?.setVisible(next)
                dockRef.value?.setLit("HELP", next)
                if (next) cue.opened() else cue.closed()
            },
            "HERE" to {
                val on = !Settings.useDeviceLocation(ctx)
                Settings.setUseDeviceLocation(ctx, on)
                dockRef.value?.setLit("HERE", on)
                hereEpoch.value += 1
                if (on) cue.opened() else cue.closed()
                Log.i(TAG_UI, "[here] headset GPS -> ${if (on) "ON" else "OFF"}")
            },
            "WIDE" to {
                // Back out one level. The pip is also the ANCHOR: its caption
                // says which region you are inside, so the one always-present
                // surface answers "where am I" without the ring having to.
                if (lensStack.isNotEmpty()) {
                    lensStack.removeAt(lensStack.lastIndex)
                    hereEpoch.value += 1
                    menuRef.value?.hide()
                    cue.closed()
                    // NAMED, because "the view demagnified" has three possible
                    // causes — this pip, the B gesture, and the Activity being
                    // recreated under us — and they are indistinguishable from
                    // the outside. A pop with no line before it was not a pop.
                    Log.i(TAG_UI, "[lens] popped by WIDE pip, depth ${lensStack.size}")
                } else {
                    cue.closed()
                }
            },
            "HANDS" to {
                val next = !(handsRef.value?.visible ?: false)
                handsRef.value?.setVisible(next)
                dockRef.value?.setLit("HANDS", next)
                if (next) cue.opened() else cue.closed()
            },
            // EVERY NODE, WITHOUT TURNING AROUND (§8.2).
            "LIST" to {
                val r = rosterRef.value
                val h = stage.headNow()
                if (r == null || h == null) {
                    cue.closed()
                } else if (r.open) {
                    r.hide(); dockRef.value?.setLit("LIST", false); cue.closed()
                } else {
                    val o2 = hereSource.resolve(link.here.value, MainActivity.homeOverride)
                    val now = System.currentTimeMillis() / 1000
                    // BY RANGE. The one ordering that is a fact about the mesh
                    // rather than a claim about importance.
                    val entries = link.mesh.value.mapNotNull { p ->
                        if (!o2.known || p.lat == null || p.lon == null) null
                        else p to MeshNodes.haversineKm(o2.lat!!, o2.lon!!, p.lat, p.lon)
                    }.sortedBy { it.second }.map { (p, km) ->
                        val n = MeshNodes.nodeFor(o2, p, now)
                        com.iotj.meshmore.xr.spatial.Roster.Entry(
                            "%-14s %5s %s".format(
                                com.iotj.meshmore.xr.spatial.TypeTier.clip(n.name, 14),
                                MeshNodes.km(n.dist.toDouble()),
                                MeshNodes.compass(n.bearingRad),
                            ),
                        ) {
                            rosterWant.add(n)
                        }
                    }
                    val q = h.rotation
                    val fx = 2f * (q.x * q.z + q.w * q.y)
                    val fz = 1f - 2f * (q.x * q.x + q.y * q.y)
                    r.showAt(h.translation, kotlin.math.atan2(-fx, fz), entries)
                    dockRef.value?.setLit("LIST", true)
                    cue.opened()
                }
            },
            // FACE NORTH, THEN PRESS THIS.
            //
            // The glasses publish no magnetometer — two sensors reach apps and
            // neither is an IMU — so the device cannot find north, while every
            // node's bearing is computed from lat/lon and is therefore measured
            // FROM north. Without this the whole ring is rotated by however far
            // off north you happened to be at launch, which is what a real
            // compass held up to the display showed on 2026-08-02.
            //
            // PER SESSION, and that is not laziness. The correction is a yaw in
            // the runtime's activity space, and that space is re-established on
            // every launch — a number stored from one session means nothing in
            // the next. Persisting it would be storing a fiction.
            "NORTH" to {
                val h = stage.headNow()
                if (h == null) {
                    cue.closed()
                    Log.w(TAG_UI, "[heading] NORTH pressed with no head pose")
                } else {
                    // The same derivation Stage.recentre uses, and it must stay
                    // the same: place() maps bearing 0 to (sin a, -cos a), so
                    // the yaw that puts north under your nose is atan2(-fx, fz).
                    // The X sign vanishes at identity, which is how a mirrored
                    // scene survives every test done facing the tracking origin.
                    val q = h.rotation
                    val fx = 2f * (q.x * q.z + q.w * q.y)
                    val fz = 1f - 2f * (q.x * q.x + q.y * q.y)
                    val yaw = kotlin.math.atan2(-fx, fz)
                    originRef.value = originRef.value?.copy(yawRad = yaw)
                    hereEpoch.value += 1
                    cue.opened()
                    Log.i(TAG_UI, "[heading] NORTH set from head yaw %.1f° — ring is now "
                        .format(Math.toDegrees(yaw.toDouble())) + "north-referenced")
                }
            },
        ))
        // A short tick when a pip takes focus. On a display where you cannot
        // feel a control, sound is the only confirmation that the pointer has
        // arrived — and it arrives BEFORE the pinch, which is when it helps.
        // THE DWELL FALLBACK (§8.2). Armed only when no hand is tracked, so it
        // is an alternative to the pinch rather than a second way to fire the
        // same control by accident.
        val roster = com.iotj.meshmore.xr.spatial.Roster(session, palette, ctx)
        roster.build()
        roster.onFocus = { cue.recognised() }
        rosterRef.value = roster

        val gaze = com.iotj.meshmore.xr.spatial.Gaze(session, palette)
        gaze.build()
        gaze.onFire = { cue.recognised() }
        gaze.setTargets(dock.gazeTargets())
        gazeRef.value = gaze

        dock.onFocus = { cue.recognised() }
        // The menu gets the same tick the dock does. On a display where you
        // cannot feel a control, sound is the only confirmation the pointer
        // arrived — and it arrives BEFORE the pinch, which is when it helps.
        menuRef.value?.onFocus = { cue.recognised() }
        dockRef.value = dock
        if (MainActivity.showHelp) {
            help.setVisible(true)
            dock.setLit("HELP", true)
        }
        rack.onDismiss = {
            rack.setVisible(false)
            dock.setLit("RADIO", false)
        }
        // DEFAULT CLOSED, no exception. A launch flag that opens a live radio
        // panel is the same hazard as leaving it standing, just triggered by a
        // command line instead of a stray hand. The dock is the way in.
        // HERE used to be its own ring, low and forward — which is exactly
        // where the dock now sits. Two settings surfaces in the same place, one
        // of them a lone unlabelled ring, is what the extra rings in the view
        // were. It is a dock pip now; the dock is the settings surface.
        stageRef.value = stage
        originRef.value = origin
        horizonRef.value = horizon
        // A cluster is the one mote whose selection cannot mean "open this
        // node", because there is no node behind it.
        // A NODE PINCH OPENS FOCUS. Queued rather than handled here: showFor
        // builds the spur, which suspends, and this is an input callback.
        val focusWant = java.util.concurrent.ConcurrentLinkedQueue<Pair<
            com.iotj.meshmore.xr.spatial.Horizon.Node, androidx.xr.runtime.math.Vector3>>()
        horizon.onNode = { node, at -> focusWant.add(node to at) }

        horizon.onCluster = { node, at ->
            menuRef.value?.let { m ->
                if (m.open) m.hide() else m.showAt(at, node)
            }
            cue.opened()
        }

        // Frame loop: pulses decay, and a packet lands every so often so the
        // mesh visibly breathes. ~30 Hz is plenty for this motion.
        var since = 0f
        var fall = 0f
        var lastAdverts = -1
        var boot0Elapsed = 0f
        var statusTick = 0f
        try {
            if (MainActivity.selfTest) launch { horizon.selfTest(origin) }
            if (MainActivity.showFocus) launch {
                var waited = 0
                while (waited < 60_000) {
                    val n = horizon.firstNode()
                    val h = stage.headNow()?.translation
                    if (n != null && h != null) {
                        focusRef.value?.showFor(n.first, n.second, h)
                        Log.i(TAG_UI, "[focus] opened by launch flag on ${n.first.name}")
                        return@launch
                    }
                    kotlinx.coroutines.delay(1000); waited += 1000
                }
                Log.w(TAG_UI, "[focus] --ez focus: no node appeared in 60 s")
            }
            if (MainActivity.showMenu) launch {
                // POLLED, not delayed. The mesh arrives over BLE and the ring
                // does not cluster until it has; a fixed wait picked before that
                // just reports "no cluster" and looks like a broken flag.
                var waited = 0
                while (waited < 60_000) {
                    horizon.firstCluster()?.let { (n, p) ->
                        menuRef.value?.showAt(p, n)
                        Log.i(TAG_UI, "[menu] opened by launch flag on ${n.name}")
                        return@launch
                    }
                    kotlinx.coroutines.delay(1000); waited += 1000
                }
                Log.w(TAG_UI, "[menu] --ez menu: no cluster appeared in 60 s")
            }
            if (MainActivity.typeProbe) launch { com.iotj.meshmore.xr.spatial.TypeProbe.run(session, ctx) }
            var panelWarned = false
            while (true) {
                delay(33)
                // RE-ASSERT EVERY FRAME. Disabling the main panel once is not
                // enough: the Compose XR layer re-enables it behind our back on
                // later layout passes, and it comes back as a large translucent
                // quad that writes depth -- so it does not just look wrong, it
                // OCCLUDES the geometry behind it and the scene reads as empty.
                val mp = session.scene.mainPanelEntity
                if (mp.isEnabled()) {
                    if (!panelWarned) {
                        Log.i(TAG_UI, "[spatial] main panel came back — re-disabling")
                        panelWarned = true
                    }
                    mp.setEnabled(false)
                }
                // Tron floor falls into place over ~1.6s, outward from the user.
                if (fall < 1f) {
                    fall = (fall + 0.033f / 1.6f).coerceAtMost(1f)
                    stage.tickFloor(fall)
                }
                // Billboard the callsigns at the LIVE head, not the launch
                // pose -- the labels have to keep facing the user as they walk.
                // BOOT SURFACE. Held for a minimum dwell even if the sync is
                // instant: a wordmark that appears and vanishes inside a second
                // reads as a glitch, not as a launch.
                // TIME-BOX THE WAIT. Teardown used to depend solely on the
                // contact sync completing -- and on a reconnect to an already
                // bonded radio the sync sometimes never starts at all. The app
                // was then stuck on the loading surface forever while happily
                // hearing live adverts behind it: connected, working, and
                // apparently frozen. Whatever has arrived by MAX_BOOT_S is what
                // we show; an incomplete horizon beats a permanent splash.
                val loading = boot0Elapsed < MAX_BOOT_S &&
                    (!load.done || boot0Elapsed < MIN_BOOT_S)
                boot0Elapsed += 0.033f
                if (loading) {
                    bootRef.value?.tick(0.033f, load.fraction, load.total > 0)
                } else if (bootRef.value != null) {
                    Log.i(TAG_UI, "[boot] surface down after %.1fs (sync %s)"
                        .format(boot0Elapsed, if (load.done) "complete" else "TIMED OUT"))
                    bootRef.value?.clear()
                    bootRef.value = null
                }
                stage.headNow()?.let {
                    horizon.faceViewer(it.translation)
                    // Callsigns give way to the microhud bands where they cross.
                    // ONE FOCUS AT A TIME (§2.1 rule 3). Set before veil, which
                    // is what actually writes the alphas.
                    // Either FOCUS surface quiets the ring's names — §2.1 rule
                    // 3 is about how many things can hold the text layer, not
                    // about which one happens to be up.
                    horizon.setRecessed(
                        menuRef.value?.open == true || focusRef.value?.open == true,
                    )
                    horizon.veil(it)
                    rackRef.value?.tick(it.translation)
                    dockRef.value?.tick(it.translation)
                    menuRef.value?.tick(it.translation)
                    focusRef.value?.tick(it.translation)
                    noticeRef.value?.tick(it)
                    helpRef.value?.tick(it.translation)
                    launch { handsRef.value?.tick(handR, handL, it) }
                    // The microhud is head-locked, so it is re-placed from the
                    // live pose every frame rather than anchored once.
                    hudRef.value?.tick(it)
                }
                // ASL QUICK ACTIONS. Right 'A' raises the compass band, left
                // 'A' raises the link band. Per-hand rather than one gesture
                // cycling both: two surfaces answering different questions
                // should be two commands, and a cycle makes you pass through a
                // state you did not want on the way to the one you did.
                val nowMs = android.os.SystemClock.uptimeMillis()
                // THE DWELL FALLBACK. Hands present means the pinch path is
                // live, so dwell stands down — it is an alternative, not a
                // second way to fire the same control without noticing.
                val anyHand = listOf(handR, handL).any { h ->
                    h?.state?.value?.handJoints?.isNotEmpty() == true
                }
                // Targets are refreshed each frame because the roster's rows
                // come and go. Fourteen cones is nothing next to the ring.
                gazeRef.value?.setTargets(
                    (dockRef.value?.gazeTargets() ?: emptyList()) +
                        (rosterRef.value?.gazeTargets() ?: emptyList()),
                )
                gazeRef.value?.tick(stage.headNow(), anyHand, nowMs)
                // Show the dwelled pip's caption. Same focus state a pointer
                // produces, so the two input paths look identical as well as
                // firing identically.
                dockRef.value?.gazed = gazeRef.value?.onTarget
                rosterRef.value?.tick(stage.headNow()?.translation)
                while (true) {
                    val pick = rosterRef.value?.poll() ?: break
                    rosterRef.value?.activate(pick)
                }
                val it0 = stage.headNow()
                // Hands that are operating a control are not signing. Feeding
                // the gate NONE rather than skipping it also resets any partial
                // dwell, so a fist held through a selection cannot complete a
                // letter on the other side of it.
                val reaching = com.iotj.meshmore.xr.spatial.Reach.busy()
                // Calibration trace, ~1 Hz, only while a hand is actually
                // tracked. The classifier's thresholds were set from synthesised
                // joints; this is what a real hand measures.
                if (MainActivity.handDebug && statusTick == 0f) {
                    handR?.state?.value?.let { st ->
                        Log.i(TAG_UI, "[hand] R ${st.trackingState} " +
                            com.iotj.meshmore.xr.spatial.HandSign.describe(st.handJoints))
                    }
                    handL?.state?.value?.let { st ->
                        Log.i(TAG_UI, "[hand] L ${st.trackingState} " +
                            com.iotj.meshmore.xr.spatial.HandSign.describe(st.handJoints))
                    }
                }
                // ONE LEVEL, not all the way out. Getting three levels deep and
                // being thrown to the top loses the path you took to find
                // something; "back" and "home" are different commands, and B is
                // back. Only listened to while magnified, because a flat hand is
                // a common resting shape and making it mean something at all
                // times would be a command you issue by relaxing.
                fun backOut(hand: String) {
                    if (nowMs - lastBackAt < BACK_OUT_MS) return
                    // FOCUS FIRST. B is "back", and the most recent thing you
                    // opened is what back should undo — unwinding a lens level
                    // while a card is still up would answer a question nobody
                    // asked.
                    focusRef.value?.let { f ->
                        if (f.open) {
                            lastBackAt = nowMs
                            f.hide(); cue.closed()
                            Log.i(TAG_UI, "[hand] $hand:B — focus closed")
                            return
                        }
                    }
                    if (lensStack.isEmpty()) return
                    lastBackAt = nowMs
                    cue.recognised()
                    lensStack.removeAt(lensStack.lastIndex)
                    hereEpoch.value += 1
                    menuRef.value?.hide()
                    Log.i(TAG_UI, "[lens] popped by $hand:B gesture, depth ${lensStack.size}")
                }

                handR?.state?.value?.handJoints?.let { j ->
                    // ORIENTATION COUNTS. A fist held palm-first is the back of
                    // an 'A', not an 'A' — and accepting both doubles the number
                    // of accidental hand positions that fire a command.
                    val away = handsRef.value?.palmAway(j, it0, rightHand = true)
                    val seenR = if (reaching) com.iotj.meshmore.xr.spatial.HandSign.Letter.NONE
                                else com.iotj.meshmore.xr.spatial.HandSign.classify(j, away)
                    val gotR = gateR.update(seenR, nowMs)
                    // WHAT THE CLASSIFIER SAW, so the B threshold is set from a
                    // real hand rather than from hand proportions. Throttled,
                    // and only while a hand is actually tracked.
                    // ON CHANGE ONLY. At 500 ms this was four lines a second
                    // and it evicted the app's own startup log from a buffer the
                    // platform's sensor HAL already floods — which cost a whole
                    // debugging cycle chasing a feature that had in fact built.
                    val shapeR = "%s %.2f".format(
                        seenR, com.iotj.meshmore.xr.spatial.HandSign.spread(j))
                    if (shapeR != lastShapeR) {
                        lastShapeR = shapeR
                        Log.i(TAG_UI, "[hands] R seen=$shapeR " +
                            "(B limit ${com.iotj.meshmore.xr.spatial.HandSign.B_SPREAD})")
                    }
                    // B RETURNS A MAGNIFIED RING TO TRUE BEARING, and is only
                    // listened to while magnified. A flat hand is a common
                    // resting shape; making it mean something at all times
                    // would be a command you issue by relaxing.
                    // PRESENTED, not merely present. See Hands.presented — a
                    // hand that has been put down must not issue commands, and
                    // this does not depend on the spread threshold being right.
                    if (gotR == com.iotj.meshmore.xr.spatial.HandSign.Letter.B &&
                        handsRef.value?.presented(j, it0) == true
                    ) {
                        backOut("R")
                    }
                    if (gotR == com.iotj.meshmore.xr.spatial.HandSign.Letter.A) {
                        // BEFORE the action. Hearing this means the classifier
                        // saw the letter; the only remaining question is whether
                        // what it triggered did anything. Silence means the
                        // problem is upstream of our logic entirely.
                        cue.recognised()
                        hudRef.value?.let { h ->
                            h.setUpper(!h.upperOn)
                            // The dock lamp is the app's statement about what is
                            // open; a gesture that changes the state without
                            // updating it makes the dock lie.
                            dockRef.value?.setLit("COMPASS", h.upperOn)
                            Log.i(TAG_UI, "[hand] R:A — compass ${if (h.upperOn) "ON" else "OFF"}")
                        }
                    }
                }
                handL?.state?.value?.handJoints?.let { j ->
                    val away = handsRef.value?.palmAway(j, it0, rightHand = false)
                    val seenL = if (reaching) com.iotj.meshmore.xr.spatial.HandSign.Letter.NONE
                                else com.iotj.meshmore.xr.spatial.HandSign.classify(j, away)
                    val gotL = gateL.update(seenL, nowMs)
                    val shapeL = "%s %.2f".format(
                        seenL, com.iotj.meshmore.xr.spatial.HandSign.spread(j))
                    if (shapeL != lastShapeL) {
                        lastShapeL = shapeL
                        Log.i(TAG_UI, "[hands] L seen=$shapeL " +
                            "(B limit ${com.iotj.meshmore.xr.spatial.HandSign.B_SPREAD})")
                    }
                    if (gotL == com.iotj.meshmore.xr.spatial.HandSign.Letter.B &&
                        handsRef.value?.presented(j, it0) == true
                    ) {
                        backOut("L")
                    }
                    if (gotL == com.iotj.meshmore.xr.spatial.HandSign.Letter.A) {
                        cue.recognised()
                        hudRef.value?.let { h ->
                            h.setLower(!h.lowerOn)
                            dockRef.value?.setLit("LINK", h.lowerOn)
                            Log.i(TAG_UI, "[hand] L:A — link band ${if (h.lowerOn) "ON" else "OFF"}")
                        }
                    }
                }

                horizon.drainSelections(origin)

                // ONE FOCUS AT A TIME: a second node replaces the first, and
                // the same node again closes it, so a pinch is always its own
                // undo and there is no way to be left with a card you cannot
                // dismiss.
                // A ROSTER PICK OPENS THE SAME FOCUS a pinch on the mote would
                // have, at the node's TRUE bearing — which is the point of the
                // list: the node may be behind you, or clustered away, or both.
                while (true) {
                    val n = rosterWant.poll() ?: break
                    val f = focusRef.value ?: break
                    val head = stage.headNow()?.translation ?: break
                    f.showFor(
                        n,
                        origin.place(
                            n.bearingRad,
                            com.iotj.meshmore.xr.spatial.Horizon.R * n.dist,
                            com.iotj.meshmore.xr.spatial.Horizon.EYE_DROP,
                        ),
                        head,
                    )
                    rosterRef.value?.hide()
                    dockRef.value?.setLit("LIST", false)
                    cue.opened()
                }
                while (true) {
                    val (n, p) = focusWant.poll() ?: break
                    val f = focusRef.value ?: break
                    val head = stage.headNow()?.translation ?: break
                    if (f.open && f.subject == n.name) {
                        f.hide(); cue.closed()
                    } else {
                        f.showFor(n, p, head); cue.opened()
                    }
                }

                // THE MENU'S ANSWER, drained on the frame loop like every other
                // input — nothing rebuilds the horizon from a pinch callback.
                menuRef.value?.poll()?.let { choice ->
                    val node = menuRef.value?.subject as? Horizon.Node
                    when (choice) {
                        "magnify" -> {
                            val o2 = hereSource.resolve(link.here.value, MainActivity.homeOverride)
                            // The cluster's bearing is a DISPLAYED one. Unmap it
                            // back through every active lens to get the true
                            // bearing, or the new wedge is built over
                            // already-magnified angles and magnifies the
                            // magnification.
                            val trueB = node?.let { n ->
                                lensStack.foldRight(n.bearingRad) { l, b -> l.unmap(b) }
                            }
                            val bearings = link.mesh.value.mapNotNull { p ->
                                if (!o2.known || p.lat == null || p.lon == null) null
                                else MeshNodes.bearingRad(o2.lat!!, o2.lon!!, p.lat, p.lon)
                            }.filter { b ->
                                trueB != null &&
                                    MeshNodes.angularGap(b, trueB) < grabFor(lensStack.size)
                            }
                            val l = Lens.over(bearings)
                            if (l == null || bearings.size < 2) {
                                Log.i(TAG_UI, "[menu] nothing left to magnify there")
                                cue.closed()
                            } else {
                                lensStack.add(l)
                                hereEpoch.value += 1
                                Log.i(TAG_UI, "[menu] magnify $l over ${bearings.size}, " +
                                    "depth ${lensStack.size}")
                                cue.opened()
                            }
                        }
                        "bearing" -> node?.let { n ->
                            val o2 = hereSource.resolve(link.here.value, MainActivity.homeOverride)
                            val trueB = lensStack.foldRight(n.bearingRad) { l, b -> l.unmap(b) }
                            // The TRUE bearing, because a displayed one is only
                            // meaningful inside a magnification the user may
                            // already have forgotten they are in.
                            noticeRef.value?.say(
                                "%s TRUE %03d  %s".format(
                                    n.name,
                                    Math.round(Math.toDegrees(trueB.toDouble())).toInt()
                                        .let { ((it % 360) + 360) % 360 },
                                    MeshNodes.km(n.dist.toDouble()),
                                ),
                            )
                            cue.opened()
                        }
                        "nearest" -> node?.let { n ->
                            val o2 = hereSource.resolve(link.here.value, MainActivity.homeOverride)
                            val trueB = lensStack.foldRight(n.bearingRad) { l, b -> l.unmap(b) }
                            // The nearest few BY NAME, without changing the
                            // view. Most of the time "what is in there" is the
                            // whole question and magnifying is more than was
                            // asked for.
                            val near = link.mesh.value.mapNotNull { p ->
                                if (!o2.known || p.lat == null || p.lon == null) null
                                else {
                                    val b = MeshNodes.bearingRad(o2.lat!!, o2.lon!!, p.lat, p.lon)
                                    if (MeshNodes.angularGap(b, trueB) >= grabFor(lensStack.size)) null
                                    else p to MeshNodes.haversineKm(
                                        o2.lat!!, o2.lon!!, p.lat, p.lon)
                                }
                            }.sortedBy { it.second }.take(3)
                            noticeRef.value?.say(
                                if (near.isEmpty()) "NOTHING RESOLVABLE THERE"
                                else near.joinToString("   ") {
                                    "%s %.1fKM".format(it.first.name.take(14), it.second)
                                },
                            )
                            // AND OPEN THE NEAREST ONE, because a name you
                            // cannot reach is a dead end.
                            //
                            // MAX_MOTES is 24. Magnifying into a count spreads
                            // its members across the ring but does not reduce
                            // how many there are, so layout() clusters them
                            // again and most of the nodes NEAREST just named
                            // still have no mote of their own — there is
                            // nothing on the ring to go and pinch. Reported
                            // 2026-08-03 as "nearest reports a node I cannot
                            // find".
                            //
                            // FOCUS does not need a mote. The card answers who,
                            // and the spur answers where, from the node's TRUE
                            // bearing — which is the one thing a magnification
                            // does not change.
                            near.firstOrNull()?.let { (p, _) ->
                                val f = focusRef.value
                                val head = stage.headNow()?.translation
                                if (f != null && head != null) {
                                    val fn = MeshNodes.nodeFor(
                                        o2, p, System.currentTimeMillis() / 1000,
                                    )
                                    f.showFor(
                                        fn,
                                        origin.place(
                                            fn.bearingRad,
                                            com.iotj.meshmore.xr.spatial.Horizon.R * fn.dist,
                                            com.iotj.meshmore.xr.spatial.Horizon.EYE_DROP,
                                        ),
                                        head,
                                    )
                                }
                            }
                            cue.opened()
                        }
                        "dismiss" -> cue.closed()
                    }
                    menuRef.value?.hide()
                }


                // Link readout, refreshed about once a second. The strings are
                // short on purpose: the microhud answers "is the radio there
                // and how much of the mesh do I hold", not everything about it.
                statusTick += 0.033f
                if (statusTick > 1f) {
                    statusTick = 0f
                    // The rack is built at launch, BEFORE the radio has said
                    // what it is running -- so its segment displays showed the
                    // dark-8 ghost forever. Refreshed on the same ~1 Hz tick as
                    // the link readout, which is also when a commit or revert
                    // would have changed what LIVE means.
                    rackRef.value?.refresh()
                    val st = link.status.value
                    // THREE STATES, NOT TWO. Silence used to cover both "the
                    // radio never answered the battery query" and "it answered
                    // 0 mV", which are different facts: the first is a link we
                    // should look at, the second is a mains-powered node working
                    // perfectly. 0 mV now draws the external-power bolt.
                    val mv = load.batteryMv
                    val batt = when {
                        mv == null -> ""
                        mv <= 0 -> " ${Glyphs.BOLT}"
                        else -> " %.1fV".format(mv / 1000f)
                    }
                    hudRef.value?.setStatus(
                        "%s%s  %d/%d".format(
                            if (st.state == SessionState.READY) "LINK" else st.state.name.take(4),
                            batt, nodesRef.value.size, mesh.size,
                        )
                    )
                }
                horizon.tick(0.033f)
                // PULSE ON A REAL PACKET. The brief defines a pulse as a packet
                // event, and until now it fired on a 1.4 s timer over invented
                // nodes -- a screensaver pretending to be telemetry. It now
                // tracks the advert counter, so a ring on the horizon means the
                // radio genuinely heard something, and a quiet mesh looks quiet.
                val adverts = link.status.value.adverts
                if (adverts != lastAdverts) {
                    lastAdverts = adverts
                    val live = nodesRef.value.filter { it.located }
                    if (live.isNotEmpty()) {
                        val n = live.random(Random)
                        horizon.pulse(n.bearingRad, n.dist, origin)
                    }
                }
                since += 0.033f
                if (MainActivity.simulate && since > 1.4f) {
                    since = 0f
                    nodesRef.value.filter { it.located }.takeIf { it.isNotEmpty() }?.let {
                        val n = it.random(Random)
                        horizon.pulse(n.bearingRad, n.dist, origin)
                    }
                }
            }
        } finally {
            horizon.clear()
            hudRef.value?.clear()
            stage.clearFloor()
        }
    }
}

/**
 * What the HERE marker says. It reports the source that is actually IN USE, not
 * the setting -- those differ whenever the radio has its own fix, because the
 * headset is a fallback and never an override. Saying "HEADSET" while the
 * bearings came from the radio would be a plain lie about where the horizon is
 * measured from.
 *
 * The no-fix case names the remedy rather than the fault. "NONE" alone tells
 * someone staring at an empty ring nothing they can act on.
 */
private fun hereCaption(
    ctx: android.content.Context,
    src: HereSource,
    resolved: MeshNodes.Here,
): String = when {
    !resolved.known && !Settings.useDeviceLocation(ctx) -> "HERE  NO FIX - PINCH FOR HEADSET GPS"
    !resolved.known -> "HERE  NO FIX"
    // The armed-but-unused note only earns its place when the fallback is NOT
    // the source. "HEADSET (HEADSET ON)" says one thing twice.
    src.source == "headset" -> "HERE  HEADSET GPS"
    else -> "HERE  ${src.source.uppercase()}" +
        if (Settings.useDeviceLocation(ctx)) "  - HEADSET ARMED" else ""
}

/**
 * The radio transcript. Deliberately an ordinary widget: header, scrolling
 * list, two buttons.
 *
 * AUTOSCROLL FOLLOWS THE TAIL, AND STOPS WHEN YOU SCROLL. A log that yanks
 * itself back to the bottom while you are reading three lines up is unusable
 * for the one thing it is for, which is reading what already happened.
 */
@Composable
private fun RadioLogPanel(link: MeshLink) {
    val lines by link.diag.collectAsState()
    val st by link.status.collectAsState()
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    var follow by remember { mutableStateOf(true) }
    val scope = rememberCoroutineScope()

    // "Are we at the bottom" has to be recomputed from the list, not
    // remembered from the last scroll: new lines move the bottom.
    LaunchedEffect(lines.size, follow) {
        if (follow && lines.isNotEmpty()) listState.scrollToItem(lines.size - 1)
    }

    Column(
        Modifier.fillMaxSize().background(Color(0xF00A0E12)).padding(12.dp),
    ) {
        Text(
            "RADIO TRAFFIC",
            color = Color(0xFF66E8D0), fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold, fontSize = 15.sp,
        )
        Text(
            "${st.state}   adverts ${st.adverts}   contacts ${st.contacts}   ${lines.size} lines",
            color = Color(0xFF7A8C96), fontFamily = FontFamily.Monospace, fontSize = 11.sp,
            modifier = Modifier.padding(bottom = 6.dp),
        )
        androidx.compose.foundation.lazy.LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxWidth().weight(1f),
        ) {
            items(lines.size) { i ->
                val l = lines[i]
                Text(
                    l,
                    // Colour by KIND, read off the tag the writer already
                    // emitted -- nothing here re-parses the frame.
                    color = when {
                        l.contains("ERROR") || l.contains("DECODE!") -> Color(0xFFFF7A6B)
                        l.contains(">>ADVERT") -> Color(0xFFFFD166)
                        l.contains("OK ") -> Color(0xFF8CE99A)
                        l.contains("ADVERT") -> Color(0xFF66E8D0)
                        else -> Color(0xFFAFC0CA)
                    },
                    fontFamily = FontFamily.Monospace, fontSize = 11.sp,
                )
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(top = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Target("ADVERT", Color(0xFFFFD166)) { link.announce(false) }
            Target("FLOOD", Color(0xFFFF7A6B)) { link.announce(true) }
            Target(if (follow) "FOLLOWING" else "PAUSED", Color(0xFF66E8D0)) {
                follow = !follow
                if (follow && lines.isNotEmpty()) {
                    scope.launch { listState.scrollToItem(lines.size - 1) }
                }
            }
            Target("CLEAR", Color(0xFF7A8C96)) { link.clearDiag() }
        }
    }
}

@Composable
private fun StatusScreen(facts: List<Pair<String, String>>, link: MeshLink, spatial: Boolean) {
    val mesh by link.status.collectAsState()
    // BLUETOOTH_SCAN/CONNECT are runtime permissions on API 31+. A denial must
    // leave the app usable (Tier 0), never error out -- design brief section 3.
    val perms = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { granted ->
        Log.i(TAG_UI, "[perm] BLE granted=$granted")
        if (granted.values.all { it }) link.connect()
    }
    val activity = LocalContext.current as? ComponentActivity
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(if (spatial) Panel else Ground)
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            "MESHMORE XR",
            color = Accent, fontSize = 26.sp,
            fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace,
        )
        Text(
            if (spatial) "P0 · checkpoint 2 — SPATIAL PANEL" else "P0 · checkpoint 1 — home space (2D)",
            color = if (spatial) Ok else Dim,
            fontSize = 13.sp, fontFamily = FontFamily.Monospace,
            modifier = Modifier.padding(bottom = 12.dp),
        )

        facts.forEach { (k, v) -> FactRow(k, v) }

        FactRow("spatial UI", if (spatial) "YES" else "no (home space)")

        Text(
            "MESH LINK",
            color = Accent, fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace,
            modifier = Modifier.padding(top = 16.dp, bottom = 4.dp),
        )
        FactRow("state", mesh.state.name + if (mesh.scanning) " (scanning)" else "")
        mesh.deviceName?.let { FactRow("radio", it) }
        mesh.error?.let { FactRow("error", it) }
        mesh.selfInfo?.let { si ->
            FactRow("node", si.name())
            FactRow("radio cfg", "%.3f MHz  SF%d  BW%.0f  CR%d".format(
                si.frequencyMhz(), si.spreadingFactor(), si.bandwidthKhz(), si.codingRate()))
            FactRow("tx power", "${si.txPowerDbm()} dBm (max ${si.maxTxPowerDbm()})")
            FactRow("handshake", "YES")
        }
        FactRow("adverts/contacts/msgs", "${mesh.adverts} / ${mesh.contacts} / ${mesh.messages}")

        Row(
            modifier = Modifier.padding(top = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Target(
                label = if (spatial) "TO HOME SPACE" else "REQUEST FULL SPACE",
                tint = Accent,
                enabled = !busy && activity != null,
                onClick = {
                    val a = activity ?: return@Target
                    busy = true
                    scope.launch {
                        // Suspend, and it can be refused -- hence the result log.
                        val res = if (spatial) a.requestHomeSpace() else a.requestFullSpace()
                        Log.i(TAG_UI, "[spatial] request ${if (spatial) "HOME" else "FULL"} -> $res")
                        busy = false
                    }
                },
            )

            Target(
                label = "LINK RADIO",
                tint = Ok,
                enabled = mesh.state == SessionState.DISCONNECTED && !mesh.scanning,
                onClick = {
                    if (link.hasBlePermissions()) link.connect()
                    else perms.launch(arrayOf(
                        android.Manifest.permission.BLUETOOTH_SCAN,
                        android.Manifest.permission.BLUETOOTH_CONNECT,
                    ))
                },
            )
        }
    }
}

/**
 * A control, not a Button. Material's pill is a fingertip-on-glass affordance;
 * this is a bracketed target that ignites on focus -- the flat cousin of the
 * PEBBLE, for the one surface that is allowed to be flat.
 */
@Composable
private fun Target(label: String, tint: Color, enabled: Boolean = true, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val hot by interaction.collectIsHoveredAsState()
    val c = if (enabled) tint else Dim
    val brackets = GenericShape { size, _ ->
        val a = size.minDimension * 0.34f
        moveTo(0f, a); lineTo(0f, 0f); lineTo(a, 0f)
        moveTo(size.width - a, 0f); lineTo(size.width, 0f); lineTo(size.width, a)
        moveTo(size.width, size.height - a); lineTo(size.width, size.height); lineTo(size.width - a, size.height)
        moveTo(a, size.height); lineTo(0f, size.height); lineTo(0f, size.height - a)
        close()
    }
    Box(
        Modifier
            .border(if (hot) 1.6.dp else 1.dp, c.copy(alpha = if (hot) 1f else 0.55f), brackets)
            .clickable(enabled = enabled, interactionSource = interaction, indication = null) { onClick() }
            .padding(horizontal = 16.dp, vertical = 9.dp)
    ) {
        Text(
            label, color = c, fontSize = 12.sp,
            fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun FactRow(key: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(key, color = Dim, fontSize = 13.sp, fontFamily = FontFamily.Monospace)
        Text(
            value,
            color = if (value == "YES") Ok else TextC,
            fontSize = 13.sp, fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Medium,
        )
    }
}
