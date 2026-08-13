// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.Crown
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
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
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
import com.iotj.meshmore.xr.spatial.Theme
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
         * --ez find true : raise the FIND panel at launch, with the keyboard.
         *
         * The panel only opens from a pip, and the question that has to be
         * answered before anything else is whether the system IME comes up over
         * a spatial panel at all — which cannot be checked with a hand in front
         * of the glasses, because the emulator composites spatial content into
         * screencap and the glasses do not.
         */
        var showFind: Boolean = false
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
         * --ez planes true : report what surfaces the room offers, and shut up
         * otherwise. See [com.iotj.meshmore.xr.spatial.Planes] — this exists to
         * settle whether the runtime ever labels a plane TABLE, which decides
         * whether the tabletop can anchor semantically or has to pick the
         * largest horizontal surface itself.
         */
        var probePlanes: Boolean = false
        /**
         * --es switchto <key> : after the scene is up, change theme AS IF
         * PICKED, to exercise the runtime path rather than the launch one.
         */
        var switchTo: String? = null
        /**
         * --es telperm "battery,location,environment", each of deny|contacts|anyone.
         *
         * The rack is where this belongs (§9.5 lists it as a TUMBLER) and that
         * is still owed. Until then this makes the setting reachable rather
         * than merely implemented, because a permission you cannot change is
         * not a permission you control.
         */
        var telPerm: String? = null
        /** --ez console true : project the settings stack at launch. Inert. */
        var showConsole: Boolean = false
        /** --ez thread true : open the most recent conversation at launch. */
        var showThread: Boolean = false
        /** --ez handdebug true : log what the ASL classifier measures, ~1 Hz. */
        var handDebug: Boolean = false
        /** --ez typeprobe true : answer whether tier R can exist on this SDK. */
        var typeProbe: Boolean = false
        /**
         * --es theme "<key>" : build in one of the nine, ignoring what is stored.
         *
         * Nine skins is nine things to look at on a headset, and reaching each
         * one through the console costs a minute of somebody's time per check.
         * Keys are in [com.iotj.meshmore.xr.spatial.Theme.ALL]. Does not
         * persist — the wearer's own choice is still there next launch.
         */
        var themeKey: String? = null
        /**
         * --ez retintprobe true : cycle every theme, once a second, from boot.
         *
         * THIS EXISTS TO FALSIFY ONE CLAIM. The theme system rests on
         * `KhronosUnlitMaterial.setBaseColorFactor` re-colouring a material
         * that is already on screen — which is a documented setter, and which
         * this codebase had previously assumed was impossible after
         * `MeshEntity.setAlpha` turned out to be a no-op on the same path. One
         * wrong assumption of that shape already cost a fortnight of working
         * around it. A flag that repaints the whole scene nine times while
         * somebody watches settles it in nine seconds.
         */
        var retintProbe: Boolean = false
        /** --ez firstlight true : run S0 again on a device that has seen it. */
        var firstLight: Boolean = false
        /** --ez emberprobe true : fire embers all round the compass, on a timer. */
        var emberProbe: Boolean = false
        /**
         * --es bay "CHANNELS" : open one console bay at launch.
         *
         * The console is reached by a gesture, then a plate, then a pick. That
         * is correct for a wearer and expensive for a check — and a surface
         * that is only reachable by wearing the headset is a surface that gets
         * built unverified, which is how this app accumulated a backlog of them.
         * One of DEVICE, APP, PROFILE, CHANNELS, DIAG.
         */
        var openBay: String? = null
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
    private val link by lazy {
        MeshLink(this).also {
            it.restore()
            // WHAT THE WEARER DECIDED, not what the build shipped with. Off
            // unless somebody has been to the APP bay and said so twice; the
            // refusal path inside MeshLink is untouched and remains the only
            // gate. Loaded here so it is true before the first frame, rather
            // than only after the bay has been opened once.
            it.channelTxAuthorised = Settings.channelSend(this)
            Log.i(TAG, "[tx] channel send authorised = ${it.channelTxAuthorised}")
        }
    }

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
        showFind = intent?.getBooleanExtra("find", false) ?: false
        showMenu = intent?.getBooleanExtra("menu", false) ?: false
        showFocus = intent?.getBooleanExtra("focus", false) ?: false
        probePaths = intent?.getBooleanExtra("probe", false) ?: false
        probePlanes = intent?.getBooleanExtra("planes", false) ?: false
        switchTo = intent?.getStringExtra("switchto")
        telPerm = intent?.getStringExtra("telperm")
        showConsole = intent?.getBooleanExtra("console", false) ?: false
        themeKey = intent?.getStringExtra("theme")
        retintProbe = intent?.getBooleanExtra("retintprobe", false) ?: false
        firstLight = intent?.getBooleanExtra("firstlight", false) ?: false
        emberProbe = intent?.getBooleanExtra("emberprobe", false) ?: false
        openBay = intent?.getStringExtra("bay")?.uppercase()
        showThread = intent?.getBooleanExtra("thread", false) ?: false
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

/**
 * THE 2D PATH TAKES THE THEME TOO.
 *
 * These were six HALO FIELD constants, and everything they paint is what a
 * wearer sees FIRST: the boot wordmark, the unfold, the pre-spatial panel. So
 * picking TERMINAL VOID and relaunching gave a cyan boot screen that resolved
 * into a green world — the one moment in the app where the theme is doing all
 * the talking, and the only place it was ignored.
 *
 * Read once at class-init from the stored choice rather than plumbed through
 * the composables: the 2D path exists only until Full Space is granted, which
 * is before any surface that can change the theme is reachable, so it cannot go
 * stale within a launch. [Ink] owns everything after that.
 *
 * DIM has no palette role of its own — it is the text colour at low emphasis —
 * so it is derived rather than invented, which keeps it right in all nine.
 */
private var uiSkin: Theme.Skin = Theme.DEFAULT

private fun c(rgb: Int, alpha: Float = 1f) =
    Color(((alpha * 255).toInt() shl 24) or (rgb and 0xFFFFFF))

private val Ground get() = c(uiSkin.palette.ground)
private val Panel get() = c(uiSkin.palette.panel)
private val Accent get() = c(uiSkin.palette.accent)
private val TextC get() = c(uiSkin.palette.text)
private val Dim get() = c(uiSkin.palette.text, 0.55f)
private val Ok get() = c(uiSkin.palette.alt)

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
                // Same story as HAND_TRACKING: declared in the manifest, still
                // runtime-granted, and configure() throws for the whole call
                // without it. Spelled out because there is no SDK constant —
                // absent from android.Manifest$permission in every installed
                // platform including CANARY, though the device does report it.
                add("android.permission.SCENE_UNDERSTANDING_COARSE")
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

/** The head's yaw, in the convention Stage.Origin.place uses. */
/**
 * The CHANNELS bay's rows, from the two things that know: the radio's slots and
 * the wearer's voice preferences.
 *
 * SLOTS FIRST, THEN CHANNELS ONLY SEEN IN TRAFFIC. The radio enumerates its
 * slots at connect, which is the authoritative list and the one that includes
 * an empty band you have not heard from yet. But a channel can also arrive
 * purely as traffic — a message tagged `#3` from a radio whose enumeration we
 * missed, or that arrived before we connected — and dropping those would mean
 * the bay cannot turn off a channel that is, audibly, talking. So the traffic
 * is unioned in, after, and only where the slot list does not already have it.
 */
private fun channelRows(
    link: MeshLink,
    voice: VoicePrefs,
    pending: ChanAction? = null,
): List<com.iotj.meshmore.xr.spatial.Stack.Row> {
    val slots = link.channels()
    val known = slots.map { it.threadId }.toSet()
    val fromTraffic = link.threads()
        .filter { !it.direct && it.id !in known }
        .map { MeshLink.Chan(idx = -1, name = it.title, publicKey = false, threadId = it.id) }
    return (slots + fromTraffic).map { c ->
        com.iotj.meshmore.xr.spatial.Stack.Row(
            id = c.threadId,
            label = com.iotj.meshmore.xr.spatial.channelLabel(
                name = c.name,
                publicKey = c.publicKey,
                count = link.countFor(c.threadId),
                speaking = voice.isOn(c.threadId),
            ),
            lit = voice.isOn(c.threadId),
        )
    } + makeRows(link, pending)
}

/** A channel write the wearer has started but not yet confirmed. */
private sealed interface ChanAction {
    /** A rolled name, waiting for the second pinch that writes it. */
    data class New(val name: String) : ChanAction
    /** The public channel, waiting for the second pinch. */
    data object Public : ChanAction
}

private const val ROW_NEW = "+new"
private const val ROW_ROLL = "+roll"
private const val ROW_PUBLIC = "+public"

/**
 * The two things this bay can DO, under the list of what already exists.
 *
 * ARMED, THEN DONE — every write takes two pinches, and the first one commits
 * to nothing. A channel write is not undoable from here and gaze-dwell plus a
 * pinch is a low bar for an irreversible act; the second pinch is also what
 * gives the rolled name somewhere to appear before it becomes real, which is
 * the only chance the wearer gets to decide they would rather have a different
 * one.
 *
 * NO ACTIONS WHEN THERE IS NOWHERE TO PUT ONE. With four slots full the rows
 * are absent rather than present-and-failing: a button that always refuses is a
 * button that teaches people the app is broken. [MeshLink.writeChannel] still
 * refuses independently, because the slot table can fill between a draw and a
 * pinch.
 */
private fun makeRows(
    link: MeshLink,
    pending: ChanAction?,
): List<com.iotj.meshmore.xr.spatial.Stack.Row> {
    fun row(id: String, label: String, lit: Boolean = false) =
        com.iotj.meshmore.xr.spatial.Stack.Row(id = id, label = label, lit = lit)
    // NOT BEFORE THE RADIO HAS SPOKEN. With no link there is no slot table, so
    // every slot looks free and the bay would offer to make a channel it has
    // nowhere to put — and freeSlot()'s whole inference is that a slot missing
    // from the table is one the radio SAID was empty, which is only true after
    // the connect-time enumeration.
    if (link.status.value.state != SessionState.READY) return emptyList()
    if (link.freeSlot() == null) return emptyList()
    return when (pending) {
        // THE TAG IS SHOWN IN LOWERCASE, alone among the rows, and that is
        // deliberate rather than a missed uppercase(). The key is SHA-256 over
        // the tag's literal bytes, so "#pine-fox-47" and "#PINE-FOX-47" are two
        // different channels that look like one. What is on the glasses has to
        // be what the other person types, character for character, or the two
        // radios derive different keys and neither ever hears the other.
        is ChanAction.New -> listOf(
            row(ROW_NEW, "MAKE  ${Channels.tagFor(pending.name)}", lit = true),
            row(ROW_ROLL, "ROLL A DIFFERENT NAME"),
        )
        ChanAction.Public -> listOf(
            row(ROW_PUBLIC, "JOIN PUBLIC — PINCH AGAIN", lit = true),
        )
        null -> listOfNotNull(
            row(ROW_NEW, "+ NEW CHANNEL"),
            // Offered only when the radio is NOT already on the public band.
            // On a stock radio slot 0 is Public and this row would be an
            // invitation to spend a slot on a channel you are already in.
            if (link.channels().none { it.publicKey }) {
                row(ROW_PUBLIC, "+ JOIN PUBLIC CHANNEL")
            } else {
                null
            },
        )
    }
}

/**
 * S12's rows. Facts first, then the safety copy — and the safety copy is the
 * reason this surface exists.
 *
 * Every line is inside the Stack's shared row template, checked by RowsTest,
 * because a safety line clipped in half is worse than one that is absent: it
 * still looks like a complete sentence.
 */
private fun aboutRows(link: MeshLink): List<com.iotj.meshmore.xr.spatial.Stack.Row> {
    fun row(text: String) = com.iotj.meshmore.xr.spatial.Stack.Row(
        id = "about", label = text, lit = false,
    )
    val radio = link.status.value.deviceName?.uppercase() ?: "NO RADIO LINKED"
    return listOf(
        row("MESHMORE XR  ${BuildConfig.VERSION_NAME}"),
        row("RADIO  ${com.iotj.meshmore.xr.spatial.TypeTier.clip(radio, 22)}"),
        row("MESHCORE  ${MeshcoreConstants.FIRMWARE_PIN_TAG}"),
        // THE THREE THAT MATTER, in the order they matter. Driving first: it is
        // the only one where the consequence is not recoverable.
        row("DO NOT USE WHILE DRIVING"),
        row("WATCH THE ROOM, NOT THIS"),
        row("MIC ON ONLY WHEN YOU SPEAK"),
        // THE REGION DISCLAIMER LIVES HERE, and here is a surface a wearer can
        // actually reach — which is the whole argument for ABOUT existing. The
        // region list itself only has room for a 32-character footer, and "not
        // legal advice" without the part explaining that Japanese law is about
        // the HARDWARE would be the misleading half of a true statement.
    ) + Regions.DISCLAIMER.map { row(it) }
}

/**
 * The line under the CHANNELS bay, which is where the honesty about a derived
 * key goes.
 *
 * A hashtag channel is private the way an unlisted number is private: the key
 * is `SHA-256` of the tag, so anybody who guesses the two words and the number
 * is in, and nothing about a channel that says NEW and PRIVATE would tell you
 * that. It is worth a whole footer at the moment of writing and worth nothing
 * afterwards, so it only appears while the write is armed.
 */
private fun chanFooter(pending: ChanAction?): String = when (pending) {
    is ChanAction.New -> "A GUESSED TAG JOINS. SAY IT ONCE"
    ChanAction.Public -> "PUBLIC IS EVERYBODY. NO SECRETS"
    null -> "LIT = READ ALOUD    B TO CLOSE"
}

/**
 * The channel band's contents — the same source the CHANNELS bay uses, so a
 * channel cannot appear in one and not the other.
 */
private fun channelBands(
    link: MeshLink,
    voice: VoicePrefs,
): List<com.iotj.meshmore.xr.spatial.Bands.Band> =
    // WITHOUT THE ACTIONS. The bay's rows now end in things to DO, and a band
    // is a place traffic arrives — "+ NEW CHANNEL" hanging in the horizon over
    // the node lanes would be a control in the one part of the scene that has
    // none.
    channelRows(link, voice).filterNot { it.id.startsWith("+") }.map { r ->
        com.iotj.meshmore.xr.spatial.Bands.Band(
            id = r.id,
            // The bay's row is written for a 28-character plate; the band has
            // its own width and its own template, so it is re-clipped here
            // rather than shared. Same data, different budget.
            label = com.iotj.meshmore.xr.spatial.TypeTier.clip(r.label, 20),
            count = link.countFor(r.id),
            speaking = r.lit,
        )
    }

/**
 * S9's rows: every radio parameter, its live value, and what it will become.
 *
 * PRESET FIRST because it is the only control that changes everything at once,
 * and COMMIT/REVERT last because they are the ones you reach for when you have
 * finished. Six rows, so it pages at seven — which is why the Stack learned to.
 */
private fun radioRows(
    cfg: RadioConfig,
): List<com.iotj.meshmore.xr.spatial.Stack.Row> {
    val live = cfg.live
    val pend = cfg.pending
    fun row(id: String, name: String, l: String?, p: String?, lit: Boolean = false) =
        com.iotj.meshmore.xr.spatial.Stack.Row(
            id = id,
            label = com.iotj.meshmore.xr.spatial.radioRow(name, l ?: "—", p),
            lit = lit,
        )
    if (live == null) {
        return listOf(
            com.iotj.meshmore.xr.spatial.Stack.Row(
                "NONE", "RADIO NOT READ YET", false,
            ),
        )
    }
    fun f(v: Double) = if (v == Math.floor(v)) v.toLong().toString() else v.toString()
    return listOf(
        // REGION REPLACED PRESET, and it is the first row because it is the
        // only one most people should ever need.
        //
        // Stepping a preset one pick at a time was a control for someone who
        // already knows which of four tuples they want. The question an actual
        // wearer has is "I am in the US, make this radio correct" — the same
        // question Meshmore SNS answers with a grid of region chips and a
        // suggest-from-my-location button. The four parameter rows below stay
        // for the person who genuinely wants to hand-tune, but they are no
        // longer the only way in.
        //
        // The value says which region the LIVE radio matches, or CUSTOM. It
        // reads the live set rather than the pending one deliberately: this row
        // is where you find out what you are on, and a row that renamed itself
        // to your staged choice before you committed would answer the question
        // you are about to ask with the answer you were hoping for.
        com.iotj.meshmore.xr.spatial.Stack.Row(
            id = "REGION",
            label = com.iotj.meshmore.xr.spatial.radioRow(
                "REGION", Regions.labelFor(live), null,
            ),
            lit = Regions.match(live) != null,
        ),
        row("FREQ", "FREQ", "%.3f".format(live.freqMhz), pend?.let { "%.3f".format(it.freqMhz) }),
        row("BW", "BANDWIDTH", f(live.bandwidthKhz), pend?.let { f(it.bandwidthKhz) }),
        row("SF", "SPREADING", live.spreadingFactor.toString(), pend?.spreadingFactor?.toString()),
        row("CR", "CODING RATE", "4/${live.codingRate}", pend?.let { "4/${it.codingRate}" }),
        // LIT WHEN THERE IS SOMETHING TO COMMIT, so the one row that changes
        // the radio is also the one that says whether it has anything to do.
        row("COMMIT", "COMMIT", if (cfg.dirty()) "READY" else "NOTHING", null, cfg.dirty()),
        row("REVERT", "UNDO CHANGES", if (cfg.dirty()) "PENDING" else "CLEAN", null),
    )
}

/**
 * THE REGION LIST — every shipped operating point, with the one your position
 * suggests hoisted to the top.
 *
 * SNS puts this behind a "Suggest from my location" button that asks the phone
 * for a GPS fix and then opens a confirmation dialog. Here the suggestion is
 * just the first row, already resolved, because the position is already
 * resolved: [HereSource] has settled the radio-then-headset-then-stated
 * question long before this surface opens, and asking a wearer to press a
 * button to start a fifteen-second location request they then have to confirm
 * is three interactions to say something we could have simply shown.
 *
 * IT IS A ROW, NOT A DEFAULT. It sits with the others and has to be picked. A
 * bounding box near a border resolves to the neighbouring country — the boxes
 * are coarse on purpose — so the suggestion is a proposal from a machine that
 * knows roughly where you are, and the wearer is the one who knows which side
 * of the line they are standing on. It is lit, so it reads as an answer rather
 * than as a duplicate of the entry further down the list.
 *
 * There is no row when there is no fix and no row when the fix lands outside
 * every box. Both cases leave the full list, which is the right fallback and
 * needs no explanation.
 */
private fun regionRows(
    here: com.iotj.meshmore.xr.spatial.MeshNodes.Here,
    live: RadioConfig.Params?,
): List<com.iotj.meshmore.xr.spatial.Stack.Row> {
    val rows = mutableListOf<com.iotj.meshmore.xr.spatial.Stack.Row>()
    val suggested = Regions.suggest(here.lat, here.lon)
    if (suggested != null) {
        rows += com.iotj.meshmore.xr.spatial.Stack.Row(
            id = "R:" + suggested.id,
            label = com.iotj.meshmore.xr.spatial.radioRow(
                "HERE", suggested.label, null,
            ),
            lit = true,
        )
    }
    val on = Regions.match(live)?.id
    Regions.ALL.forEach { r ->
        rows += com.iotj.meshmore.xr.spatial.Stack.Row(
            id = "R:" + r.id,
            label = com.iotj.meshmore.xr.spatial.regionRow(r.label, r.freqMhz),
            // The region the radio is ALREADY on is lit, so the list answers
            // "where am I" as well as "where could I go" — and so picking the
            // one you are on is visibly a no-op rather than a silent one.
            lit = r.id == on,
        )
    }
    return rows
}

/**
 * What a radio row does when picked.
 *
 * COMMIT IS GUARDED and REVERT is not. Writing parameters to a radio can put it
 * on a frequency where nothing can reach it — including this app — and that is
 * not recoverable from inside the app. Discarding a staged edit costs nothing
 * and asking twice for it would only teach people to double-pick everything.
 */
private fun onRadioRow(
    id: String,
    cfg: RadioConfig,
    armed: androidx.compose.runtime.MutableState<Pair<String, Long>?>,
    nowMs: Long,
    say: (String) -> Unit,
) {
    when (id) {
        // NO PRESET CASE. Stepping through the preset table one pick at a time
        // was replaced by the REGION list, which is handled at the call site
        // because it opens a surface rather than staging a value — and which
        // carries transmit power, as stepping a Quint never could.
        "BW" -> cfg.stage { it.copy(bandwidthKhz = stepIn(BWS_UI, it.bandwidthKhz)) }
        "SF" -> cfg.stage { it.copy(spreadingFactor = stepInt(SFS_UI, it.spreadingFactor)) }
        "CR" -> cfg.stage { it.copy(codingRate = stepInt(CRS_UI, it.codingRate)) }
        // FREQ is not stepped from a row. A frequency is a continuous value
        // with legal bands around it, and cycling it one row-pick at a time
        // through a list somebody cannot see is how a radio ends up somewhere
        // it is not allowed to transmit. It moves with a PRESET, which is a
        // complete and legal parameter set, or it does not move here.
        "FREQ" -> say("FREQ FOLLOWS THE PRESET")
        "COMMIT" -> {
            if (!cfg.dirty()) { say("NOTHING TO COMMIT"); return }
            if (armed.value?.first != "COMMIT") {
                armed.value = "COMMIT" to nowMs
                say("PICK AGAIN TO WRITE")
                return
            }
            armed.value = null
            val p = cfg.commit()
            say(if (p != null) "WRITTEN — ${p.pretty().take(20)}" else "COMMIT FAILED")
        }
        "REVERT" -> {
            armed.value = null
            cfg.discard()
            say("CHANGES DISCARDED")
        }
    }
}

private val BWS_UI = listOf(7.8, 10.4, 15.6, 20.8, 31.25, 41.7, 62.5, 125.0, 250.0, 500.0)
private val SFS_UI = listOf(7, 8, 9, 10, 11, 12)
private val CRS_UI = listOf(5, 6, 7, 8)

private fun stepIn(xs: List<Double>, v: Double): Double {
    val i = xs.indexOfFirst { kotlin.math.abs(it - v) < 1e-6 }
    return if (i < 0) xs.first() else xs[(i + 1) % xs.size]
}

private fun stepInt(xs: List<Int>, v: Int): Int {
    val i = xs.indexOf(v)
    return if (i < 0) xs.first() else xs[(i + 1) % xs.size]
}

/** How often the wearer's position is re-read while the app is up. */
/**
 * How many orbs a TABLETOP draws, against [MeshNodes.MAX_MOTES]' two dozen.
 *
 * The table is 32.4 degrees across and cannot grow — see the frame's note. At
 * 24 that is 1.3 degrees a node, which is the pile that was reported twice; at
 * 12 it is 2.7, wider than the 2.0 degree floor a thing has to clear to be
 * reached for. The cap is the only lever the geometry leaves.
 */
private const val TABLETOP_MOTES = 12

private const val LOCATION_POLL_MS = 15_000L

/**
 * How far the wearer walks before an ACTIVE theme re-centres the scene on them.
 *
 * Three metres is a few paces — far enough that tracker wander at a bench never
 * reaches it, close enough that you are never outside your own ring. The rebuild
 * it triggers is rate-limited by the poll interval rather than by this, which is
 * what keeps it affordable at driving speed.
 */
private const val FOLLOW_RECENTRE_M = 3.0f

/**
 * How far the wearer must have moved before the map is rebuilt from the new
 * position. Under the nearest range band, and well above the few metres a
 * stationary GPS fix wanders, so sitting still never triggers it.
 */
private const val MOVED_ENOUGH_M = 25.0

/** How long a guarded row stays armed before it forgets it was asked. */
private const val ARM_MS = 6000L

/** Rows that a single pinch must not complete. */
private val GUARDED_ROWS = setOf("CHANSEND", "FORGET")

/**
 * The APP bay's rows.
 *
 * All five are REAL state that something in the app already reads. A settings
 * surface whose switches do nothing is worse than one that is missing: the
 * missing one is an obvious gap, and the fake one is a promise, so nobody finds
 * out until the thing they switched off happens anyway.
 *
 * The connection state is deliberately NOT here — console spec §10 says it is a
 * lamp rather than a row, and it goes in the title, because it is something you
 * read and not something you can change from a bay.
 */
private fun appRows(
    ctx: android.content.Context,
    link: MeshLink,
    armedId: String?,
): List<com.iotj.meshmore.xr.spatial.Stack.Row> {
    fun row(id: String, name: String, on: Boolean, onWord: String = "ON", offWord: String = "OFF") =
        com.iotj.meshmore.xr.spatial.Stack.Row(
            id = id,
            label = com.iotj.meshmore.xr.spatial.settingLabel(
                name, on, armed = armedId == id, onWord = onWord, offWord = offWord,
            ),
            // AN ARMED ROW DOES NOT LIGHT. Lighting it would show the state it
            // is about to have rather than the one it has, which is a switch
            // that lies for six seconds.
            lit = on && armedId != id,
        )
    return listOf(
        row("LOCATION", "HEADSET LOCATION", Settings.useDeviceLocation(ctx)),
        // Two location settings, and they are separate on purpose: using a fix
        // to compute bearings is local and private, putting it in an advert
        // broadcasts it unencrypted to anyone in range.
        row("SHARE", "SHARE MY LOCATION", Settings.shareLocation(ctx)),
        row("DIAG", "DIAGNOSTICS PANEL", Settings.diagnostics(ctx)),
        row("AUTOPEN", "SUGGEST A REPLY", Settings.autopen(ctx)),
        row("MOTION", "REDUCE MOTION", Settings.reduceMotion(ctx)),
        row("CHANSEND", "SEND ON CHANNELS", Settings.channelSend(ctx), "ALLOWED", "OFF"),
        com.iotj.meshmore.xr.spatial.Stack.Row(
            id = "FORGET",
            label = com.iotj.meshmore.xr.spatial.settingLabel(
                "ERASE ${link.msgs.value.size} MESSAGES",
                on = false, armed = armedId == "FORGET", offWord = "",
            ).trimEnd(),
            lit = false,
        ),
    )
}

private fun yawOf(h: androidx.xr.runtime.math.Pose): Float {
    val q = h.rotation
    val fx = 2f * (q.x * q.z + q.w * q.y)
    val fz = 1f - 2f * (q.x * q.x + q.y * q.y)
    return kotlin.math.atan2(-fx, fz)
}

/**
 * How long ago, in words a person uses.
 *
 * "1785739387" is a timestamp, "2 MIN AGO" is an answer. This app is a
 * companion and not a packet analyser, and the difference shows up in small
 * places like this one before it shows up anywhere else.
 */
private fun ago(sec: Long): String = when {
    sec < 0 -> "JUST NOW"
    sec < 60 -> "JUST NOW"
    sec < 3600 -> "${sec / 60} MIN AGO"
    sec < 86400 -> "${sec / 3600} HR AGO"
    else -> "${sec / 86400} DAY AGO"
}

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
    val tableRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.TableAnchor?>(null) }
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
    val inboxRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.Inbox?>(null) }
    val consoleRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.Console?>(null) }
    val themePickerRef =
        remember { mutableStateOf<com.iotj.meshmore.xr.spatial.ThemePicker?>(null) }
    val channelsRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.Stack?>(null) }
    val firstRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.FirstLight?>(null) }
    val emberRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.Ember?>(null) }
    val bandsRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.Bands?>(null) }
    val appRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.Stack?>(null) }
    /**
     * A guarded row that has been pressed ONCE, and when it expires.
     *
     * Two settings in the APP bay widen what the radio does or destroy
     * something that cannot be got back, and a single pinch is not enough
     * consent for either. Held here rather than in the stack because the stack
     * is deliberately ignorant of what a pick MEANS.
     */
    val armed = remember { mutableStateOf<Pair<String, Long>?>(null) }
    /**
     * The same idea for the CHANNELS bay, and separate from [armed] on purpose:
     * they are two surfaces, and a rolled channel name left armed while the
     * wearer goes to the APP bay must not be cancelled by — or worse, confused
     * with — a pick over there.
     */
    val chanArmed = remember { mutableStateOf<ChanAction?>(null) }
    val chanArmedAt = remember { mutableStateOf(0L) }
    /**
     * ABOUT borrows the APP bay's Stack rather than building a seventh surface.
     *
     * It is the same widget doing the same job — a column of lines you point
     * at — and the only difference is that none of these lines does anything.
     * This flag is what stops a pinch on "DO NOT USE WHILE DRIVING" being
     * routed into the APP bay's toggle table, which would silently flip a
     * setting whose row happened to share an index.
     */
    val aboutOpen = remember { mutableStateOf(false) }
    /** Which bay the shared APP stack is currently serving. */
    val bayMode = remember { mutableStateOf("APP") }
    /**
     * The last link step announced, so each one is said once and not per frame.
     *
     * Seeded with a sentinel no real step can equal, because the honest initial
     * value — null, meaning "no step, we are READY" — is also the value the
     * radio reaches on a fast link. The scene takes about fourteen seconds to
     * build and a bonded radio connects in two, so on every good launch the
     * first comparison was null == null and the wearer was told nothing at all,
     * including that the radio had linked.
     */
    val saidStep = remember { mutableStateOf<String?>("<not yet looked>") }
    val threadRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.Thread?>(null) }
    val cuffRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.Cuff?>(null) }
    val crownRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.Crown?>(null) }
    val reelRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.Reel?>(null) }
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
    /** Messages arrived and not yet looked at. Shown in the microhud band. */
    val unread = remember { mutableStateOf(0) }
    val helpRef = remember { mutableStateOf<HelpCard?>(null) }
    val cue = remember { Cue() }
    /**
     * WHICH OF THE NINE, read before anything is built.
     *
     * [Ink] can retint a scene that already exists, which is what makes the
     * picker a live preview — but the scene still has to be BUILT in the right
     * theme, or the first frame after launch is HALO FIELD flashing past on its
     * way to whatever the wearer actually chose. Read here, applied at
     * `Ink.begin` before the first surface exists.
     */
    val tagsRef = remember { NodeTags(ctx) }
    val themePrefs = remember { ThemePrefs(ctx) }
    val skin = remember {
        mutableStateOf(
            // The launch flag overrides for THIS RUN and is not written back.
            MainActivity.themeKey?.let { com.iotj.meshmore.xr.spatial.Theme.byKey(it) }
                ?: themePrefs.current(),
        ).also { uiSkin = it.value }
    }
    val speech = remember { Speech(ctx) }
    val dictation = remember { Dictation(ctx) }
    // ASKED AT THE MOMENT OF SPEAKING, never at startup. A microphone prompt on
    // first launch of a mesh radio reads as the app wanting to listen to the
    // room, and it would be the first thing anybody saw. The system dialog is
    // the sanctioned tier-P escape hatch, same as the BLE grant.
    val askMic = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        Log.i(TAG_UI, "[stt] mic granted=$granted")
        if (granted) dictation.start()
        else crownRef.value?.say("MIC NOT ALLOWED", android.os.SystemClock.uptimeMillis())
    }
    val voice = remember { VoicePrefs(ctx) }
    // TextToSpeech holds a system engine binding. Leaking one is not fatal but
    // it is the kind of thing a store review notices, and the fix is two lines.
    androidx.compose.runtime.DisposableEffect(Unit) {
        onDispose { speech.release(); dictation.release(); cue.release() }
    }
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

    // THE FLOOR FOLLOWS THE POSTURE, at runtime and not only at launch.
    //
    // Seeded with the LAUNCH posture, because the scene-setup path has already
    // built the floor for it — so this fires only on an actual change and a
    // FIELD launch does not pay for a second 34-bar build. Going to TABLETOP
    // clears the grid; coming back from it puts the room's ground back.
    val floorFor = remember { mutableStateOf(skin.value.key) }
    LaunchedEffect(skin.value.key, stageRef.value, originRef.value) {
        val st = stageRef.value ?: return@LaunchedEffect
        val o = originRef.value ?: return@LaunchedEffect
        if (floorFor.value == skin.value.key) return@LaunchedEffect
        floorFor.value = skin.value.key
        st.buildFloor(o, skin.value)
    }

    // Exercise the RUNTIME theme change, once the scene exists to change.
    LaunchedEffect(themePickerRef.value) {
        val key = MainActivity.switchTo ?: return@LaunchedEffect
        val want = com.iotj.meshmore.xr.spatial.Theme.ALL.firstOrNull { it.key == key }
            ?: return@LaunchedEffect
        val picker = themePickerRef.value ?: return@LaunchedEffect
        kotlinx.coroutines.delay(6_000)
        picker.fire(want)
    }

    // WHERE YOU ARE NOW, not where you launched.
    //
    // Every bearing and every range on this map is measured FROM the wearer, so
    // moving does not slide the map — it changes what the map SAYS. Walk ten
    // miles east and a node that was north-east of you is north-west; the marks
    // belong in different places, with different range bands, because the facts
    // they draw have changed.
    //
    // Nothing was recomputing them. The mesh effect keys on `here`, so it
    // reacts when the radio volunteers a new position — but the headset
    // fallback reads `getLastKnownLocation` once at launch and never again
    // (HereSource says so in as many words), and a radio that reports on
    // self-info only is little better. A map that silently keeps measuring from
    // this morning's position is worse than one that admits it does not know.
    //
    // THRESHOLD, NOT TIMER, for the rebuild. Re-placing 118 entities is a
    // visible cost and standing still must not pay it; 25 m is under the
    // nearest range band and far enough above GPS noise (a stationary fix
    // wanders several metres) that a chair by a window does not thrash it.
    LaunchedEffect(horizonRef.value) {
        if (horizonRef.value == null) return@LaunchedEffect
        var lastLat: Double? = null
        var lastLon: Double? = null
        while (true) {
            kotlinx.coroutines.delay(LOCATION_POLL_MS)

            // THE ACTIVE THEME TRAVELS WITH THE WEARER.
            //
            // HALO is the theme for movement — hiking, cycling, riding — and on
            // a walk the ring stayed pinned to wherever the app had launched,
            // so the wearer simply walked out of their own horizon and the mesh
            // sat behind them measuring from a place they had left.
            //
            // Re-centring is the SAME operation the H gesture performs: put the
            // origin where the wearer is and rebuild. It is not sliding the
            // mesh along beside them — every bearing and range is recomputed
            // from the new position, so a repeater on a hill stays on its hill
            // and simply reads from a different angle, which is what it should
            // do once you have walked a hundred metres toward it.
            //
            // TWO GATES, and they are for different failures. THREE METRES,
            // because a rebuild is visible and standing at a bench with the
            // tracker wandering must not trigger one. FIFTEEN SECONDS between
            // rebuilds, because in a car three metres passes in a fifth of a
            // second and distance alone would ask for a rebuild continuously —
            // the poll interval becomes the real cadence, which is what
            // "updates periodically" means at speed.
            val sk = skin.value
            if (sk.active) {
                val head = stageRef.value?.headNow()?.translation
                val o = originRef.value
                if (head != null && o != null) {
                    val dx = head.x - o.x
                    val dz = head.z - o.z
                    val moved = kotlin.math.sqrt(dx * dx + dz * dz)
                    if (moved >= FOLLOW_RECENTRE_M) {
                        originRef.value = o.copy(x = head.x, y = head.y, z = head.z)
                        hereEpoch.value += 1
                        Log.i(TAG_UI, "[here] active theme — scene follows, %.1f m".format(moved))
                    }
                }
            }

            val now = hereSource.resolve(link.here.value, MainActivity.homeOverride)
            val la = now.lat
            val lo = now.lon
            if (la == null || lo == null) continue
            val p0lat = lastLat
            val p0lon = lastLon
            if (p0lat == null || p0lon == null) {
                lastLat = la; lastLon = lo
                continue
            }
            val movedM = MeshNodes.haversineKm(p0lat, p0lon, la, lo) * 1000.0
            if (movedM < MOVED_ENOUGH_M) continue
            lastLat = la; lastLon = lo
            Log.i(TAG_UI, "[here] moved %.0f m — re-placing the map from here".format(movedM))
            hereEpoch.value += 1
        }
    }

    // THE FILTER, and whether its panel is up. Two states rather than one: a
    // query survives the panel being closed, so a wearer who narrows the ring to
    // three repeaters and puts the keyboard away is still looking at three
    // repeaters. Closing a search and silently restoring 350 nodes would undo
    // the thing they just did.
    val query = remember { mutableStateOf("") }
    val searchOpen = remember { mutableStateOf(MainActivity.showFind) }

    LaunchedEffect(signature, here, horizonRef.value, hereEpoch.value, query.value) {
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
        // THE WEARER'S OWN FAVOURITES, folded in before ranking rather than
        // taught to the ranker.
        //
        // MeshNodes.rank already puts favourites first and never clusters one
        // away — it just believed only the RADIO's flag. Marking the peer here
        // means an app-level favourite gets that behaviour for free and
        // MeshNodes stays ignorant of preferences, which is what keeps it pure
        // and testable.
        val marked = if (MainActivity.simulate) mesh else mesh.map { p ->
            if (p.favourite) p
            else if (tagsRef.isFavourite(p.fullKey ?: p.key)) p.copy(favourite = true)
            else p
        }
        // NARROWED BEFORE RANKED, never after. Ranking a filtered population is
        // the whole point: with four matches, all four are drawn, at their true
        // bearings, in the same ring as everything else. Filtering the RESULT
        // instead would leave the ranker's 24 arbitrary picks and hide most of
        // them, which is a way of showing less rather than of finding anything.
        val found = Search.apply(marked, query.value)
        if (found.size != marked.size) {
            Log.i(TAG_UI, "[find] '${query.value}' -> ${found.size} of ${marked.size}")
        }
        // HALF AS MANY ORBS ON A TABLETOP, because the table cannot grow.
        //
        // "Still too cramped" is an angular complaint, and the model is already
        // 32.4 degrees across against a 34 degree field — it fills the window,
        // and PostureTest keeps it there because a model you take in with your
        // neck is not a tabletop. Pushing it further out to make it physically
        // bigger leaves the angular density identical, which is the only thing
        // crowding is. Two dozen nodes across 32 degrees is 1.3 degrees each;
        // twelve is 2.7, which is the difference between a cloud and a set of
        // objects you can point at one at a time.
        //
        // What is lost is half the mesh, and that is what FIND is for: on a
        // tabletop the wearer names what they want to see rather than being
        // shown everything badly.
        val cap = if (skin.value.posture == com.iotj.meshmore.xr.spatial.Theme.Posture.TABLETOP) {
            TABLETOP_MOTES
        } else {
            MeshNodes.MAX_MOTES
        }
        val nodes = if (MainActivity.simulate) simulatedMesh() else
            MeshNodes.build(
                origin2, found, System.currentTimeMillis() / 1000, limit = cap, lens = lens,
            )
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
        // WHY EVERYTHING READS STALE, if it does. `ageOf` returns fully-stale
        // for any peer whose lastSeen is zero, so a radio that does not date
        // its contacts turns the whole mesh grey — and "stale" then means
        // "unknown", which is a different claim entirely and the one the wearer
        // is not being told.
        val undated = mesh.count { it.lastSeenEpochSec <= 0L }
        Log.i(TAG_UI, "[age] ${mesh.size} peers, $undated undated, " +
            "live=${nodes.count { it.age < 0.34f }} stale=${nodes.count { it.age >= 0.34f }}")
        // THE WHOLE MESH'S AGES, not just the two dozen that got drawn.
        //
        // "Everything says stale" has two completely different causes and the
        // drawn counts cannot tell them apart: either the threshold is wrong, or
        // the RANKER is picking old nodes — it sorts by distance before
        // recency, so 350 stored contacts compete for 24 slots and the near-but-
        // ancient ones win. The first is a constant; the second is a design
        // fault. This histogram is over every peer the radio holds, so the shape
        // of the mesh itself is visible and the answer stops being a guess.
        run {
            val nowS = System.currentTimeMillis() / 1000
            val buckets = intArrayOf(0, 0, 0, 0, 0)
            mesh.forEach {
                val d = if (it.lastSeenEpochSec <= 0L) Long.MAX_VALUE
                    else (nowS - it.lastSeenEpochSec).coerceAtLeast(0L)
                when {
                    d < 600 -> buckets[0]++
                    d < 3600 -> buckets[1]++
                    d < 21600 -> buckets[2]++
                    d < 86400 -> buckets[3]++
                    else -> buckets[4]++
                }
            }
            Log.i(TAG_UI, "[age] heard <10m ${buckets[0]}, <1h ${buckets[1]}, " +
                "<6h ${buckets[2]}, <24h ${buckets[3]}, older ${buckets[4]}")
        }
        // SAID OUT LOUD, ONCE, AT THE MOMENT THE RING COMES UP EMPTY.
        //
        // A radio with no GPS reports 0.0/0.0 forever and the app has nothing to
        // measure bearings from, so every located peer is unplaceable — 345 of
        // them, on the mesh this was found on. The status band carries the
        // standing fact; this is the sentence that arrives at the moment the
        // wearer is looking at an empty ring and wondering what broke.
        // 0/0 IS NOT A POSITION. It is what a GPS-less board reports forever,
        // and it is a real place in the Gulf of Guinea — counting those as
        // "waiting to be drawn" would promise the wearer 350 nodes that a fix
        // will never produce. Same test the link's own census uses.
        val unplaced = mesh.count {
            it.lat != null && it.lon != null &&
                (kotlin.math.abs(it.lat) > 1e-7 || kotlin.math.abs(it.lon) > 1e-7)
        }
        if (!origin2.known && unplaced > 0) {
            noticeRef.value?.say(
                if (Settings.useDeviceLocation(ctx)) {
                    "NO POSITION YET — $unplaced NODES WAITING"
                } else {
                    // Names the SHORTEST remedy, not the fault. The APP bay has
                    // the same switch two pinches deep; the HERE pip is one, is
                    // on the dock in every theme, and lights when it is on.
                    "NO POSITION — PINCH HERE ON THE DOCK"
                },
            )
            Log.w(TAG_UI, "[here] no fix — $unplaced located peer(s) cannot be drawn")
        }
        nodesRef.value = nodes
        h.build(nodes, o, st.floorHeight())
        // S5 — the channel band, above the node lanes. Rebuilt with the horizon
        // because it belongs to the same ring and shares its origin.
        bandsRef.value?.show(
            channelBands(link, voice),
            o,
        )
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

        // THE THEME, BEFORE THE FIRST SURFACE. Nine skins (brief §7); the table
        // is in Theme.kt and the stored choice in ThemePrefs. `Ink.begin` tells
        // the registry which palette everything about to be created belongs to,
        // which is what lets a later change re-colour it in place rather than
        // rebuild the scene.
        val palette = skin.value.palette
        com.iotj.meshmore.xr.spatial.Ink.begin(palette)
        com.iotj.meshmore.xr.spatial.Reveal.reduced = Settings.reduceMotion(ctx)
        cue.pack = Cue.packFor(skin.value.audio)
        Log.i(TAG_UI, "[theme] wearing ${skin.value.key} (${skin.value.name})")
        // Recentre on the body BEFORE building anything, or the whole
        // experience can end up behind the user.
        val stage = Stage(session, palette)
        // PERCEPTION IS ASKED FOR ONLY WHEN SOMETHING WANTS IT: the tabletop
        // posture, which needs a real table to stand on, or the probe. Seven of
        // the nine themes have no use for planes, and an unnecessary
        // runtime-permission prompt at launch is a cost paid by every wearer
        // for a feature two themes use.
        val wantPlanes = MainActivity.probePlanes ||
            skin.value.posture == com.iotj.meshmore.xr.spatial.Theme.Posture.TABLETOP
        val origin0 = stage.recentre(wantPlanes)
        Log.i(TAG_UI, "[boot] planes wanted=$wantPlanes granted=${stage.planesEnabled}")
        if (stage.planesEnabled && MainActivity.probePlanes) {
            launch { com.iotj.meshmore.xr.spatial.Planes.watch(session) }
        }
        // S6 — ask the room for a table to stand the model on. Only the
        // tabletop posture wants one, and only if perception was granted; the
        // body-relative placement carries on regardless and is what the wearer
        // sees until (and unless) a table is found.
        if (stage.planesEnabled &&
            skin.value.posture == com.iotj.meshmore.xr.spatial.Theme.Posture.TABLETOP
        ) {
            tableRef.value = com.iotj.meshmore.xr.spatial.TableAnchor(session, ctx).also {
                // REMEMBERED FIRST, SEARCHED SECOND. A wearer sets a desk up
                // once; if this room is one the runtime still recognises, the
                // model goes straight back onto the same surface and the
                // 20-second search never runs.
                if (!it.recall()) it.seek()
            }
        }
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

        val horizon = Horizon(session, palette, ctx, skin.value.symbol, skin.value.posture, skin.value.active)
        // Deliberately includes the shapes real MeshCore names take: emoji,
        // fullwidth Latin, accents, kana, and a name that is nothing BUT emoji.
        // If any of these can break the label path, better it breaks here.
        // Floor first: the room claims itself, then the mesh arrives on top.
        stage.buildFloor(origin, skin.value)
        // The boot surface goes up immediately -- the wait it covers starts
        // now, not when the first contact arrives.
        val boot = Boot(session, palette)
        boot.build(origin)
        // E0 WAKE — once, as the boot surface appears. The scene takes about
        // fourteen seconds to build on this hardware and until now the wearer
        // had a wordmark and silence for all of it.
        cue.wake()
        // ...AND THE THEME'S WELCOME, under it. The wordmark appearing is the
        // moment the wearer arrives, and it is followed by about fourteen
        // seconds of scene building with nothing to hear. A three-second tune
        // is a greeting; anything longer would be a loading screen with music,
        // which is a different and worse thing.
        // LOOPED, because it is covering a wait. The tune is three seconds and
        // the boot is about fourteen; one pass leaves eleven seconds of silence
        // in the middle of the wait it exists to fill. It stops looping when the
        // vessel starts filling — the point where the surface has something to
        // say for itself and the wearer is no longer waiting on nothing.
        cue.welcome(ctx, Cue.welcomeFor(skin.value.key), loop = true)
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
        // THE SKELETON IS DEBUG SCAFFOLDING AND NEEDS A WAY IN.
        //
        // Its dock pip was given to the inbox, on the argument that a wireframe
        // of your own fingers does not belong on a shipping dock — which stands,
        // but I said it was "behind --ez handdebug" without checking, and that
        // flag only ever gated LOGGING. So the surface was built on every launch
        // and reachable from nowhere: dead weight that still cost its entities.
        // The flag now does what it was claimed to do.
        if (MainActivity.handDebug) {
            hands.setVisible(true)
            Log.i(TAG_UI, "[hands] skeleton shown by --ez handdebug")
        }
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
        // HALO WEARS ITS DOCK. Four pips on the forearm instead of eight on the
        // ground — see Dock.tickWrist for why four: a wrist is 35 cm from the
        // eye and a pinch target needs ~5 degrees of separation, so a pip costs
        // 3.1 cm of arm and eight would want a quarter-metre of it.
        //
        // The four are the ones a moving wearer reaches for — which way am I
        // facing, did anyone call me, where am I — plus the door to everything
        // else. HELP, WIDE, LIST and LINK are one pinch away behind SETUP.
        val wristDock = skin.value.active
        // FOUR ON THE WRIST. It was four, I made it five to fit FIND, and the
        // glasses said no: "too much stuff on the wrist menu, it isn't stable,
        // hard to focus on anything since it's all too close together."
        //
        // So FIND stays and HERE goes, which is the right one to lose of the
        // five. HERE is a stored setting somebody turns on once and forgets —
        // it survives restarts, the status band now reports it standing, and
        // the APP bay still holds the switch. FIND is a thing you do repeatedly
        // while moving, which is the whole argument for anything being on a
        // wrist at all. A pip you use once should not hold a slot against a pip
        // you use all day.
        val WRIST_SET = setOf("COMPASS", "INBOX", "FIND", "SETUP")
        // A TABLETOP PUTS A MAP WHERE THE DOCK LIVES. See Dock.build's drop.
        val dockDrop =
            if (skin.value.posture == com.iotj.meshmore.xr.spatial.Theme.Posture.TABLETOP) {
                com.iotj.meshmore.xr.spatial.Dock.TABLETOP_DROP
            } else {
                com.iotj.meshmore.xr.spatial.Dock.DROP
            }
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
            // THE CONSOLE TAKES THE RADIO PIP'S SLOT, and the rack becomes a
            // bay inside it (console spec §7 D1). One guarded entrance to the
            // radio beats two — the original objection to the rack was that it
            // sat somewhere it would get changed by a hand reaching for
            // something else — and the dock does not grow a tenth pip.
            "SETUP" to {
                val c = consoleRef.value
                val at = dockRef.value?.pipAt("SETUP")
                if (c == null || at == null) {
                    cue.closed()
                } else if (c.open) {
                    c.hide(); dockRef.value?.setLit("SETUP", false); cue.closed()
                } else {
                    c.showAt(at)
                    dockRef.value?.setLit("SETUP", true)
                    cue.opened()
                }
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
            // THE INBOX TAKES THE HAND-SKELETON'S SLOT.
            //
            // HANDS draws a debug skeleton and belongs behind --ez handdebug,
            // not on the dock of an app someone installs: it is scaffolding
            // that earned its place while gestures were unreliable, and a row
            // of ten pips is already 52 degrees wide. What people said to you
            // outranks a wireframe of your own fingers.
            "INBOX" to {
                val b = inboxRef.value
                val h = stage.headNow()
                if (b == null || h == null) {
                    cue.closed()
                } else if (b.open) {
                    b.hide(); dockRef.value?.setLit("INBOX", false); cue.closed()
                } else {
                    val now = System.currentTimeMillis() / 1000
                    b.showAt(h.translation, yawOf(h), link.threads().map { t ->
                        val last = t.newest
                        com.iotj.meshmore.xr.spatial.Inbox.Entry(
                            id = t.id,
                            who = "%-14s %s".format(
                                com.iotj.meshmore.xr.spatial.TypeTier.clip(t.title, 14),
                                last?.let { ago(now - it.atEpochSec) } ?: "",
                            ),
                            // The last thing said, which is what a thread list
                            // is FOR — a row that only names the conversation
                            // makes you open every one to find the live one.
                            words = com.iotj.meshmore.xr.spatial.TypeTier.clip(
                                last?.text ?: "", 24,
                            ),
                            mine = t.direct,
                        )
                    })
                    dockRef.value?.setLit("INBOX", true)
                    unread.value = 0
                    cuffRef.value?.clearUnread()
                    cue.opened()
                }
            },
            // EVERY NODE, WITHOUT TURNING AROUND (§8.2).
            // FIND — the keyboard, and the only pip that changes what the RING
            // shows rather than raising a surface over it.
            //
            // Lit while a query is in force, not while the panel is up. The
            // panel is a keyboard you put away; the filter is a state the mesh
            // is in, and a wearer looking at nine motes needs to know whether
            // that is the mesh or their own last search. This is the same fault
            // the HERE pip had, caught before it shipped twice.
            "FIND" to {
                searchOpen.value = !searchOpen.value
                dockRef.value?.setLit("FIND", searchOpen.value || query.value.isNotEmpty())
                if (searchOpen.value) cue.opened() else cue.closed()
            },
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
                    MainActivity.northDeg = 0f   // north is now established
                    cue.opened()
                    Log.i(TAG_UI, "[heading] NORTH set from head yaw %.1f° — ring is now "
                        .format(Math.toDegrees(yaw.toDouble())) + "north-referenced")
                }
            },
        ).filter { !wristDock || it.first in WRIST_SET }.map { (n, f) -> n to { f(); Unit } }, dockDrop)
        // A short tick when a pip takes focus. On a display where you cannot
        // feel a control, sound is the only confirmation that the pointer has
        // arrived — and it arrives BEFORE the pinch, which is when it helps.
        // THE DWELL FALLBACK (§8.2). Armed only when no hand is tracked, so it
        // is an alternative to the pinch rather than a second way to fire the
        // same control by accident.
        val reel = com.iotj.meshmore.xr.spatial.Reel(session, palette, ctx)
        reel.build()
        reel.onDetent = { cue.tick() }
        reelRef.value = reel

        val cuff = com.iotj.meshmore.xr.spatial.Cuff(session, palette)
        cuff.build()
        cuffRef.value = cuff

        val crown = com.iotj.meshmore.xr.spatial.Crown(session, palette, ctx)
        crown.build()
        // Same tick the dock and menu use. On a display where you cannot feel a
        // control, sound is the only confirmation the pointer arrived — and it
        // arrives BEFORE the pinch, which is when it is worth having.
        crown.onFocus = { cue.recognised() }
        crownRef.value = crown

        val thread = com.iotj.meshmore.xr.spatial.Thread(session, palette, ctx)
        thread.build()
        threadRef.value = thread

        val console = com.iotj.meshmore.xr.spatial.Console(session, palette, ctx)
        console.build()
        console.onFocus = { cue.recognised() }
        consoleRef.value = console

        val picker = com.iotj.meshmore.xr.spatial.ThemePicker(session, palette, ctx)
        picker.build()
        picker.onFocus = { cue.recognised() }
        themePickerRef.value = picker

        val channels = com.iotj.meshmore.xr.spatial.Stack(session, palette, ctx, skin.value)
        channels.build()
        channels.onFocus = { cue.recognised() }
        channelsRef.value = channels

        val bands = com.iotj.meshmore.xr.spatial.Bands(session, palette, ctx)
        bands.build()
        bands.onFocus = { cue.recognised() }
        bandsRef.value = bands

        val ember = com.iotj.meshmore.xr.spatial.Ember(session, palette)
        ember.build()
        emberRef.value = ember

        val first = com.iotj.meshmore.xr.spatial.FirstLight(session, palette, ctx)
        first.build()
        // TOUCHED ONCE AND NEVER AGAIN. Recorded before the cue so a crash in
        // the sound path cannot make the wearer do onboarding twice.
        first.onTouched = {
            Settings.setFirstLightDone(ctx, true)
            first.hide()
            noticeRef.value?.say("HANDS ARE WORKING")
            cue.opened()
        }
        firstRef.value = first

        val appBay = com.iotj.meshmore.xr.spatial.Stack(session, palette, ctx, skin.value)
        appBay.build()
        appBay.onFocus = { cue.recognised() }
        appRef.value = appBay

        val inbox = com.iotj.meshmore.xr.spatial.Inbox(session, palette, ctx)
        inbox.build()
        inbox.onFocus = { cue.recognised() }
        inboxRef.value = inbox

        val roster = com.iotj.meshmore.xr.spatial.Roster(session, palette, ctx)
        roster.build()
        roster.onFocus = { cue.recognised() }
        rosterRef.value = roster

        val gaze = com.iotj.meshmore.xr.spatial.Gaze(session, palette)
        gaze.build()
        gaze.onFire = { cue.recognised() }
        gaze.setTargets(dock.gazeTargets())
        gazeRef.value = gaze

        // ARRIVAL IS AMBIENT. §S4: "Nothing appears in front of your face,
        // and nothing demands acknowledgement. The mesh is ambient; you look
        // when you choose to."
        //
        // This used to put the sender and the text on a NOTICE in the middle of
        // the view, with a comment arguing that one unsolicited interruption
        // earned its place. The brief had already decided otherwise, and it is
        // right: a mesh that interrupts you is a mesh you turn off. The four
        // channels it specifies are audio, the wrist CUFF, a MICROHUD unread
        // count and an EMBER at the viewport edge — none of them in the world
        // window, and the design survives losing any one.
        //
        // Audio and the unread count exist today. CUFF and EMBER are owed.
        // E7 — somebody new on the mesh. Rate-capped inside Cue: discovery is
        // delightful and is also the event most able to become a hailstorm.
        link.onNodeFound = { p ->
            cue.nodeFound()
            Log.i(TAG_UI, "[mesh] new peer '${p.name.ifBlank { p.key }}'")
        }
        link.onMessage = { m ->
            unread.value += 1
            // CHANNEL AND DM DIFFER BY FORM, not by colour (§S4): one arc
            // segment for channel traffic, the whole ring and a pulse for
            // something addressed to you personally.
            if (m.direct) cuffRef.value?.directArrived() else cuffRef.value?.channelArrived()
            // E10 / E11 — the arrival channel that was silent. Rate-capped
            // inside Cue (§2.1); the cuff and the ember are not, because a
            // light you can ignore is not the thing that becomes unwearable.
            cue.arrived(m.direct)
            // E16 CRITICAL — distress. The SAME reading that makes Autopen
            // refuse to draft a reply is the one that makes the app insist you
            // look: a classifier confident enough to decline to speak for you
            // is confident enough to get your attention. Exempt from the
            // density cap and never silent in any theme, per §2 and §4.4.
            if (Autopen.read(m.text) == Autopen.Intent.EMERGENCY) {
                cue.critical()
                noticeRef.value?.say(
                    "URGENT — ${com.iotj.meshmore.xr.spatial.TypeTier.clip(
                        m.fromName.ifBlank { m.channelName ?: "UNKNOWN" }, 16,
                    ).uppercase()}",
                )
                Log.w(TAG_UI, "[msg] reads as distress from '${m.fromName}'")
            }
            // EMBER — the fourth arrival channel. WHERE it came from, at the
            // edge of vision, gone in three seconds.
            //
            // The bearing is computed from the sender's own position against
            // ours, and only when BOTH are known. An unlocated sender gets no
            // ember rather than a plausible one: the mote would have to point
            // somewhere, the wearer would turn and look, and there is nothing
            // to check it against because it is gone before they get there.
            run {
                val me = link.here.value
                val mesh = link.mesh.value
                // TWO WAYS TO NAME A SENDER, because the protocol has two.
                //
                // A DIRECT message carries the sender's public key, which is an
                // identity. A CHANNEL message carries none — it is a broadcast
                // on a shared key — so the only thing available is the name the
                // text was prefixed with, which is a convention rather than a
                // protocol field.
                //
                // The name path is used, but only when it is UNAMBIGUOUS. Names
                // on a mesh are user-supplied and duplicated, and two nodes
                // called "shed" in different directions would give an ember
                // that points at one of them arbitrarily — which is the
                // invented bearing this whole surface refuses to draw. One
                // match or none.
                val peer = if (m.fromKey.isNotBlank()) {
                    mesh.firstOrNull { p ->
                        (p.fullKey ?: p.key).startsWith(m.fromKey, ignoreCase = true) ||
                            m.fromKey.startsWith(p.key, ignoreCase = true)
                    }
                } else {
                    m.fromName.takeIf { it.isNotBlank() }?.let { name ->
                        mesh.filter { it.name.equals(name, ignoreCase = true) }
                            .takeIf { it.size == 1 }?.first()
                    }
                }
                val b = if (me.known && peer?.lat != null && peer.lon != null) {
                    com.iotj.meshmore.xr.spatial.MeshNodes.bearingRad(
                        me.lat!!, me.lon!!, peer.lat!!, peer.lon!!,
                    ) - (originRef.value?.yawRad ?: 0f)
                } else {
                    null
                }
                emberRef.value?.arrived(b, m.direct, android.os.SystemClock.uptimeMillis())
            }
            // AND IT READS ITSELF, if this conversation was opted in. Only if:
            // an app that starts talking unprompted is startling in a way a
            // light is not, because you can look away from a light and you
            // cannot un-hear a voice in a room with other people in it.
            val tid = if (m.direct) m.fromKey else (m.channel ?: "#")
            if (voice.isOn(tid)) {
                val who = m.fromName.ifBlank { m.channelName ?: "someone" }
                speech.say("$who says: ${m.text}")
            }
        }

        // The dictation counter, straight from the recogniser's partial
        // results. Partials are too unreliable to send and exactly reliable
        // enough to count words with, which is all this uses them for.
        dictation.onUpdate = { d ->
            crownRef.value?.setDictation(d.text, d.words, d.listening, d.full)
        }
        // And when the wearer stops talking, the words become a DRAFT — never a
        // transmission. Speech recognition mishears; a radio that sends what it
        // thought it heard puts that mistake on somebody else's screen.
        dictation.onFinal = { text ->
            if (text.isNotBlank()) crownRef.value?.propose(text) else crownRef.value?.compose()
        }

        dock.onFocus = { cue.recognised() }
        // The menu gets the same tick the dock does. On a display where you
        // cannot feel a control, sound is the only confirmation the pointer
        // arrived — and it arrives BEFORE the pinch, which is when it helps.
        menuRef.value?.onFocus = { cue.recognised() }
        dockRef.value = dock
        // THE ONE PIP THAT REMEMBERS. Every other pip toggles a surface that is
        // closed at launch, so an unlit dock is the truth for all of them.
        // Headset GPS is a stored setting that survives the app, and its pip
        // came up dark on a build where it was already on — the state was
        // persisted correctly and looked exactly like off, which is the wrong
        // half to get right.
        dock.setLit("HERE", Settings.useDeviceLocation(ctx))
        if (MainActivity.showHelp) {
            help.setVisible(true)
            dock.setLit("HELP", true)
        }
        rack.onDismiss = {
            rack.setVisible(false)
            dock.setLit("SETUP", false)
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
        // How many slots the radio had confirmed last time the CHANNELS bay was
        // drawn. A write is confirmed asynchronously — the reply lands in
        // dumpChannel with nothing to redraw the bay — and comparing the count
        // is cheaper every frame than re-texting six panels on a timer.
        var chanCount = -1
        try {
            if (MainActivity.selfTest) launch { horizon.selfTest(origin) }
            if (MainActivity.showThread) launch {
                var waited = 0
                while (waited < 90_000) {
                    val t = link.threads().firstOrNull()
                    val h = stage.headNow()
                    if (t != null && h != null) {
                        val nowS = System.currentTimeMillis() / 1000
                        threadRef.value?.showAt(
                            h.translation, yawOf(h), t.id, t.title,
                            t.messages.map { m ->
                                com.iotj.meshmore.xr.spatial.Thread.Line(
                                    who = "%-14s %s".format(
                                        com.iotj.meshmore.xr.spatial.TypeTier.clip(
                                            m.fromName.ifBlank { t.title }, 14,
                                        ),
                                        ago(nowS - m.atEpochSec),
                                    ),
                                    words = com.iotj.meshmore.xr.spatial.TypeTier.clip(m.text, 24),
                                    mine = m.direct,
                                )
                            },
                        )
                        Log.i(TAG_UI, "[thread] opened by launch flag on " + t.title)
                        return@launch
                    }
                    kotlinx.coroutines.delay(1000); waited += 1000
                }
                // A QUIET MESH IS NOT A BROKEN SURFACE, and waiting for a
                // stranger to say something is a poor way to check geometry.
                // Labelled SAMPLE so it can never be mistaken for traffic —
                // the same bargain --ez sim already makes for the ring.
                stage.headNow()?.let { h ->
                    threadRef.value?.showAt(
                        h.translation, yawOf(h), "sample", "SAMPLE THREAD",
                        listOf(
                            "newest, nearest to you" to "JUST NOW",
                            "second message back" to "2 MIN AGO",
                            "third, further away" to "8 MIN AGO",
                            "fourth step into the past" to "20 MIN AGO",
                            "fifth, still readable" to "1 HR AGO",
                            "sixth and furthest" to "3 HR AGO",
                        ).map { (t, w) ->
                            com.iotj.meshmore.xr.spatial.Thread.Line(
                                who = "%-14s %s".format("SAMPLE", w),
                                words = t, mine = false,
                            )
                        },
                    )
                    Log.w(TAG_UI, "[thread] no traffic — showing SAMPLE for geometry")
                }
            }
            if (MainActivity.showConsole) launch {
                kotlinx.coroutines.delay(1500)
                dockRef.value?.pipAt("SETUP")?.let { at ->
                    consoleRef.value?.showAt(at)
                    dockRef.value?.setLit("SETUP", true)
                    Log.i(TAG_UI, "[console] opened by launch flag")
                }
            }
            // S0 · FIRST LIGHT. One mote, once per install. It teaches the
            // paradigm by doing it, and it is the fastest hand-tracking
            // diagnostic in the app: without it a dead tracker presents as five
            // different surfaces being broken.
            if (!Settings.firstLightDone(ctx) || MainActivity.firstLight) launch {
                kotlinx.coroutines.delay(2500)
                var waited = 0
                while (waited < 30_000) {
                    val h = stage.headNow()
                    if (h != null) {
                        firstRef.value?.showAt(
                            h.translation, yawOf(h), android.os.SystemClock.uptimeMillis(),
                        )
                        return@launch
                    }
                    kotlinx.coroutines.delay(500); waited += 500
                }
                Log.w(TAG_UI, "[first] never got a head pose — skipped")
            }
            // EMBERS ON DEMAND. Mesh traffic arrives when it arrives, and an
            // ember lasts three seconds — waiting for a real message to check
            // the placement means missing it. Walks the compass so both sides,
            // the front and the behind-you drop can be seen in one pass.
            if (MainActivity.emberProbe) launch {
                kotlinx.coroutines.delay(4000)
                var deg = 0
                while (deg < 360 * 2) {
                    emberRef.value?.arrived(
                        Math.toRadians(deg.toDouble()).toFloat(),
                        direct = (deg / 45) % 2 == 0,
                        nowMs = android.os.SystemClock.uptimeMillis(),
                    )
                    kotlinx.coroutines.delay(1200)
                    deg += 45
                }
                Log.i(TAG_UI, "[ember] probe done")
            }
            MainActivity.openBay?.let { bay ->
                launch {
                    // After the scene is up and the radio has enumerated its
                    // channels, or CHANNELS opens onto an empty list and the
                    // check says nothing.
                    kotlinx.coroutines.delay(9000)
                    consoleRef.value?.fire(bay)
                }
            }
            // THE ONE CLAIM THE THEME SYSTEM RESTS ON, put in front of an eye.
            // See MainActivity.retintProbe. Never persists: a probe that
            // changed the wearer's stored theme would be a probe with a side
            // effect, and this one is meant to leave no trace.
            if (MainActivity.retintProbe) launch {
                kotlinx.coroutines.delay(6000)
                val ink = com.iotj.meshmore.xr.spatial.Ink
                repeat(com.iotj.meshmore.xr.spatial.Theme.ALL.size * 2) { i ->
                    val s = com.iotj.meshmore.xr.spatial.Theme.ALL[
                        i % com.iotj.meshmore.xr.spatial.Theme.ALL.size,
                    ]
                    Log.i(TAG_UI, "[theme] PROBE -> ${s.key}, ${ink.size()} things registered")
                    ink.retint(s.palette)
                    noticeRef.value?.say(s.name)
                    kotlinx.coroutines.delay(2000)
                }
                ink.retint(skin.value.palette)
                Log.i(TAG_UI, "[theme] PROBE done, back to ${skin.value.key}")
            }
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
                    // THE CYLINDER IS FILLING — the wait is now showing its own
                    // progress and does not need covering. Stops the LOOP, not
                    // the sound: cutting a phrase mid-bar is more noticeable
                    // than the silence it was there to fill.
                    if (load.total > 0) cue.endWelcome()
                } else if (bootRef.value != null) {
                    Log.i(TAG_UI, "[boot] surface down after %.1fs (sync %s)"
                        .format(boot0Elapsed, if (load.done) "complete" else "TIMED OUT"))
                    // BELT AND BRACES. A radio that never reports a total never
                    // fills the cylinder, and the loop above would then have
                    // nothing to end it — the surface coming down is the last
                    // moment at which a boot tune is still a boot tune.
                    cue.endWelcome()
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
                    // The scale keeps up with the wearer; the mesh stays where
                    // the mesh actually is. HALO only.
                    horizonRef.value?.follow(it.translation)
                    dockRef.value?.tick(it.translation)
                    // WORN, FOR THE ACTIVE THEME. tick() still runs — it owns
                    // focus, caption and the fired queue — and this only
                    // re-places the pips onto the forearm afterwards, so the
                    // dock behaves identically whichever body it is on.
                    if (skin.value.active) {
                        dockRef.value?.tickWrist(handR?.state?.value?.handJoints)
                    }
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
                        (rosterRef.value?.gazeTargets() ?: emptyList()) +
                        (inboxRef.value?.gazeTargets() ?: emptyList()) +
                        (consoleRef.value?.gazeTargets() ?: emptyList()) +
                        (themePickerRef.value?.gazeTargets() ?: emptyList()) +
                        (firstRef.value?.gazeTargets() ?: emptyList()) +
                        (bandsRef.value?.gazeTargets() ?: emptyList()) +
                        (threadRef.value?.gazeTargets() ?: emptyList()) +
                        (crownRef.value?.gazeTargets() ?: emptyList()),
                )
                gazeRef.value?.tick(stage.headNow(), anyHand, nowMs)
                // THE CHAT HAND IS THE LEFT ONE by default (§5: one hand runs
                // the system, the other runs the conversation), so the cuff
                // rides the left wrist.
                cuffRef.value?.tick(handL?.state?.value?.handJoints, nowMs)
                // THE REEL RIDES THE SAME HAND AS THE CUFF — §5 puts the whole
                // conversation on one hand so an arriving message can never
                // disturb a control you are part-way through operating.
                run {
                    val cj = handL?.state?.value?.handJoints
                    val hp = stage.headNow()
                    val dot = handsRef.value?.palmDot(cj, hp, rightHand = false)
                    val r = reelRef.value
                    if (r != null) {
                        val nowS = System.currentTimeMillis() / 1000
                        r.setMessages(
                            link.msgs.value.take(12).map { m ->
                                com.iotj.meshmore.xr.spatial.Reel.Slot(
                                    who = com.iotj.meshmore.xr.spatial.TypeTier.clip(
                                        m.fromName.ifBlank {
                                            // A channel message with no sender
                                            // prefix is somebody the radio
                                            // cannot name, not the channel
                                            // talking to itself.
                                            if (m.direct) "?" else "SOMEONE"
                                        },
                                        // Eight, not more: the front-arc runs
                                        // are rasterised eight M's wide, and
                                        // wider labels are exactly what made
                                        // the first front arc a pile.
                                        8,
                                    ),
                                    // The raised card holds eight lines of
                                    // eighteen. Anything clipped here is
                                    // clipped BEFORE the card ever sees it, so
                                    // this number has to track the card's
                                    // capacity or the card silently shrinks.
                                    words = com.iotj.meshmore.xr.spatial.TypeTier.clip(m.text, 144),
                                    direct = m.direct,
                                    // The channel's NAME where the radio gave
                                    // us one, its slot index where it did not.
                                    // "#0" is the radio's filing system, not a
                                    // thing anybody calls a channel.
                                    origin = com.iotj.meshmore.xr.spatial.TypeTier.clip(
                                        m.channelName?.uppercase()
                                            ?: m.channel.orEmpty(), 10,
                                    ),
                                )
                            },
                        )
                        r.tick(cj, dot, hp?.translation, nowMs)

                        // THE CROWN LIVES AND DIES WITH THE CARD. Actions
                        // belong to the message being read, so there is no
                        // state to keep about whether they should be up: if
                        // there is a card, there is something to do about it.
                        val cw = crownRef.value
                        if (cw != null) {
                            if (r.open && r.cardAt != null) {
                                if (!cw.open) cw.show()
                            } else if (cw.open) {
                                cw.hide()
                            }
                            // The crown's VOICE label has to agree with the
                            // store for the CURRENT message, not the one the
                            // wearer last toggled — otherwise turning voice on
                            // for one conversation appears to have turned it on
                            // for every message you scroll past.
                            val sel = link.msgs.value.getOrNull(r.selectedIndex)
                            cw.voiceOn = voice.isOn(
                                sel?.let { if (it.direct) it.fromKey else (it.channel ?: "#") },
                            )
                            // Named, so the toggle says WHAT it is switching.
                            cw.voiceScope = sel?.let {
                                if (it.direct) it.fromName.ifBlank { "THIS SENDER" }
                                else (it.channelName ?: it.channel ?: "THIS CHANNEL")
                            }?.uppercase().orEmpty()
                            // AUTOPEN reads the message under the cursor, every
                            // frame the cursor moves. Set to null as readily as
                            // to a draft: a suggestion left over from the
                            // previous message is a reply to the wrong person,
                            // and it would look exactly as legitimate as a
                            // correct one.
                            //
                            // Cheap enough to do here rather than off-thread —
                            // it is a lowercase, a split and a few set lookups
                            // on at most 150 bytes. The spec's warning about
                            // hitching the frame was written for a model; when
                            // one arrives, this line becomes the place it is
                            // called FROM, not the place it runs.
                            cw.suggestion = sel?.text?.takeIf { Settings.autopen(ctx) }?.let { Autopen.suggest(it) }
                            cw.tick(
                                r.cardAt, hp?.translation,
                                hp?.let { yawOf(it) } ?: 0f, nowMs,
                            )
                            while (true) {
                                val act = cw.poll() ?: break
                                onCrown(
                                    act, link, r, cw, threadRef.value, speech,
                                    dictation, voice, cue, stage, nowMs,
                                    askMic = {
                                        askMic.launch(android.Manifest.permission.RECORD_AUDIO)
                                    },
                                )
                            }
                        }
                    }
                }
                // Show the dwelled pip's caption. Same focus state a pointer
                // produces, so the two input paths look identical as well as
                // firing identically.
                dockRef.value?.gazed = gazeRef.value?.onTarget
                consoleRef.value?.setGazed(gazeRef.value?.onTarget)
                themePickerRef.value?.setGazed(gazeRef.value?.onTarget)
                // Paging the corridor further back. One code path owns it: the
                // surface reports a pick, the host decides what a pick means.
                while (threadRef.value?.poll() != null) threadRef.value?.older()
                rosterRef.value?.tick(stage.headNow()?.translation)
                while (true) {
                    val pick = rosterRef.value?.poll() ?: break
                    rosterRef.value?.activate(pick)
                }
                // THE CHANNELS BAY. A pick is a TOGGLE, not a navigation: the
                // plate lights, the row re-labels, and the bay stays open,
                // because setting up which channels talk to you is several
                // decisions in a row and a surface that closes after each one
                // makes you walk back in five times.
                firstRef.value?.let { f ->
                    if (f.open) f.tick(stage.headNow()?.translation, nowMs)
                }
                stage.headNow()?.let { hp ->
                    emberRef.value?.tick(hp.translation, yawOf(hp), nowMs)
                    bandsRef.value?.tick(hp.translation)
                }
                // PICKING A BAND OPENS THAT CHANNEL'S THREAD. §S5 also asks
                // that it re-tint "the corresponding MOTEs" and there are
                // none — a channel message carries no sender key, so no node
                // is on a channel in any way the protocol exposes. Opening the
                // conversation is what somebody wanted anyway.
                while (true) {
                    val id = bandsRef.value?.poll() ?: break
                    val h = stage.headNow() ?: continue
                    val t = link.threads().firstOrNull { it.id == id } ?: run {
                        noticeRef.value?.say("NOTHING HEARD ON THAT CHANNEL YET")
                        cue.closed()
                        null
                    } ?: continue
                    val nowS = System.currentTimeMillis() / 1000
                    threadRef.value?.showAt(
                        h.translation, yawOf(h), t.id, t.title,
                        t.messages.map { m ->
                            com.iotj.meshmore.xr.spatial.Thread.Line(
                                who = "%-14s %s".format(
                                    com.iotj.meshmore.xr.spatial.TypeTier.clip(
                                        m.fromName.ifBlank { t.title }, 14,
                                    ),
                                    ago(nowS - m.atEpochSec),
                                ),
                                words = com.iotj.meshmore.xr.spatial.TypeTier.clip(m.text, 24),
                                mine = m.direct,
                            )
                        },
                    )
                    cue.opened()
                }
                // S2 · LINK — the handshake, out loud, as steps.
                //
                // Announced on CHANGE rather than drawn every frame: the notice
                // band is shared, and a readout that reasserts itself sixty
                // times a second would own it. Each step is said once, which is
                // also what makes the sequence legible — you see 1/4, 2/4, 3/4
                // go past, and where it stopped is where the fault is.
                run {
                    val step = link.linkStep()
                    if (step != saidStep.value) {
                        saidStep.value = step
                        if (step != null) {
                            noticeRef.value?.say(step)
                            // The ladder, as pitch. You stop hearing it climb
                            // and that is where the fault is.
                            Regex("STEP (\\d)/4").find(step)?.groupValues?.get(1)
                                ?.toIntOrNull()?.let { cue.linkStep(it) }
                            // A DROP GETS ITS OWN SOUND. The ladder is for
                            // arriving; losing the radio is the opposite motion
                            // and the one you need to hear while looking at a
                            // trail rather than at the band. Said once per
                            // outage — the string does not change while the
                            // retries run, so this cannot become a metronome.
                            if (link.status.value.droppedAtMs != null) cue.closed()
                            Log.i(TAG_UI, "[link] $step")
                        } else {
                            // Arrival is worth one line too; it is the only
                            // moment the wearer learns the radio is theirs.
                            val who = link.status.value.deviceName
                            noticeRef.value?.say(
                                if (who != null) "LINKED — ${who.uppercase()}" else "RADIO LINKED",
                            )
                            Log.i(TAG_UI, "[link] READY (${who ?: "unnamed"})")
                            cue.linked()
                        }
                    }
                }
                channelsRef.value?.tick(
                    stage.headNow()?.translation,
                    stage.headNow()?.let { yawOf(it) } ?: 0f,
                )
                // THE CHANNELS BAY. Its last rows MAKE channels rather than
                // toggling them, so they are handled before the voice toggle —
                // an action id that fell through to `voice.toggle` would set a
                // read-aloud preference on a thread that does not exist.
                while (true) {
                    val id = channelsRef.value?.poll() ?: break
                    val pending = chanArmed.value
                    val disarm = { chanArmed.value = null }
                    when {
                        id == ROW_ROLL -> {
                            // Re-roll in place. Costs nothing, commits nothing,
                            // and is the reason the name is shown before it is
                            // written rather than announced after.
                            chanArmed.value = ChanAction.New(Channels.roll())
                            chanArmedAt.value = nowMs
                            cue.tick()
                        }
                        id == ROW_NEW && pending is ChanAction.New -> {
                            val tag = Channels.tagFor(pending.name)
                            disarm()
                            when (val w = link.writeChannel(pending.name, Channels.pskFor(tag))) {
                                is MeshLink.Wrote.Ok -> {
                                    // THE TAG, NOT THE NAME. What the wearer has
                                    // to pass on is the exact string the other
                                    // person types; the channel's name is local
                                    // decoration on both radios.
                                    noticeRef.value?.say("MADE $tag — SAY IT TO SHARE")
                                    Log.i(TAG_UI, "[chan] made ${w.name} in slot ${w.idx}")
                                    cue.opened()
                                }
                                is MeshLink.Wrote.Refused -> {
                                    noticeRef.value?.say("NO — ${w.why}")
                                    cue.closed()
                                }
                            }
                        }
                        id == ROW_NEW -> {
                            chanArmed.value = ChanAction.New(Channels.roll())
                            chanArmedAt.value = nowMs
                            cue.recognised()
                        }
                        id == ROW_PUBLIC && pending == ChanAction.Public -> {
                            disarm()
                            when (val w = link.writeChannel(
                                Channels.PUBLIC_NAME, Channels.publicPsk(),
                            )) {
                                is MeshLink.Wrote.Ok ->
                                    noticeRef.value?.say("JOINED THE PUBLIC CHANNEL")
                                is MeshLink.Wrote.Refused ->
                                    noticeRef.value?.say("NO — ${w.why}")
                            }
                            cue.opened()
                        }
                        id == ROW_PUBLIC -> {
                            chanArmed.value = ChanAction.Public
                            chanArmedAt.value = nowMs
                            // THE WARNING BELONGS ON THE ARMING PINCH, where it
                            // is still a choice. Everyone on the mesh can read
                            // this band; that is the point of it and also the
                            // thing a wearer should be told before they join.
                            noticeRef.value?.say("PUBLIC IS READ BY EVERYONE")
                            cue.recognised()
                        }
                        else -> {
                            val now = voice.toggle(id)
                            noticeRef.value?.say(if (now) "READS ALOUD" else "SILENT")
                            if (now) cue.opened() else cue.closed()
                        }
                    }
                    channelsRef.value?.update(
                        channelRows(link, voice, chanArmed.value), chanFooter(chanArmed.value),
                    )
                }
                // The arming lapses on its own, like the APP bay's. A rolled
                // name left hanging in the air is a write the wearer walked away
                // from, and it must not still be one pinch from happening when
                // they come back to the bay for something else.
                chanArmed.value?.let {
                    if (nowMs - chanArmedAt.value > ARM_MS) {
                        chanArmed.value = null
                        channelsRef.value?.update(channelRows(link, voice, null), chanFooter(null))
                    }
                }
                // A WRITE THE RADIO HAS CONFIRMED arrives asynchronously, in
                // dumpChannel, with nothing to redraw the bay. Redrawn on the
                // COUNT CHANGING rather than on a timer: re-texting the rows
                // every frame churns a TextView per row, and doing it on a
                // second's tick would show a channel that already exists as
                // arriving up to a second late for no gain.
                val slotsNow = link.channels().size
                if (slotsNow != chanCount) {
                    chanCount = slotsNow
                    channelsRef.value?.update(
                        channelRows(link, voice, chanArmed.value), chanFooter(chanArmed.value),
                    )
                }
                // THE APP BAY. Two of its rows are GUARDED: the first pick
                // arms and re-labels, the second within ARM_MS commits. One
                // widens what the radio transmits and the other erases history
                // that cannot be got back, and a single pinch — which can land
                // slightly wrong — is not enough consent for either.
                appRef.value?.tick(
                    stage.headNow()?.translation,
                    stage.headNow()?.let { yawOf(it) } ?: 0f,
                )
                armed.value?.let { (_, at) ->
                    if (nowMs - at > ARM_MS) {
                        armed.value = null
                        appRef.value?.update(appRows(ctx, link, null), "LIT = ON    B TO CLOSE")
                    }
                }
                // Opening the region list, in one place. Two things reach it —
                // the REGION row and `--es bay REGION` — and a launch flag that
                // opened the surface by its own slightly different route would
                // be verifying its own route rather than the one a hand takes.
                val openRegions = {
                    bayMode.value = "REGION"
                    armed.value = null
                    aboutOpen.value = false
                    consoleRef.value?.hide()
                    appRef.value?.show(
                        regionRows(hereSource.here.value, link.radio.live),
                        title = "REGION — " + Regions.labelFor(link.radio.live),
                        footer = Regions.FOOTER,
                    )
                    dockRef.value?.setLit("SETUP", false)
                    cue.opened()
                }
                while (true) {
                    val id = appRef.value?.poll() ?: break
                    // ABOUT is read-only. Drain the pick and do nothing with it
                    // rather than let it fall through to the settings table.
                    if (aboutOpen.value) { cue.closed(); continue }
                    // THE RADIO BAY, on the same widget. Routed by mode rather
                    // than by id so a settings row and a radio row can never
                    // collide on a shared name.
                    // THE REGION LIST, checked before the radio bay because
                    // picking a region hands control straight back to it and a
                    // shared poll must not run both handlers on one pick.
                    if (bayMode.value == "REGION") {
                        val r = Regions.byId(id.removePrefix("R:"))
                        if (r != null) {
                            // STAGES, NEVER SENDS. Everything else on this
                            // surface is staged-then-committed and a region is
                            // the single most consequential thing here: the
                            // wrong one moves the radio to a band where nothing
                            // can reach it, including the app that moved it.
                            // SNS applies a region on tap because a phone can
                            // always be plugged into a laptop; a headset cannot.
                            link.radio.stage { r.params() }
                            r.note?.let { noticeRef.value?.say(it) }
                            bayMode.value = "RADIO"
                            appRef.value?.show(
                                radioRows(link.radio),
                                title = com.iotj.meshmore.xr.spatial.radioTitle(
                                    link.radio.live?.freqMhz, link.radio.live?.txDbm,
                                ),
                                footer = if (link.radio.dirty()) "PENDING — COMMIT TO APPLY"
                                else "PICK TO STEP    B TO CLOSE",
                            )
                        }
                        cue.recognised()
                        continue
                    }
                    if (bayMode.value == "RADIO") {
                        // The way IN to the region list. It is not an edit, so
                        // it does not go through onRadioRow — that function
                        // stages parameters, and this one opens a surface.
                        if (id == "REGION") { openRegions(); continue }
                        onRadioRow(id, link.radio, armed, nowMs) { note ->
                            noticeRef.value?.say(note)
                        }
                        appRef.value?.update(
                            radioRows(link.radio),
                            if (armed.value?.first == "COMMIT") "PICK AGAIN TO WRITE TO THE RADIO"
                            else if (link.radio.dirty()) "PENDING — COMMIT TO APPLY"
                            else "PICK TO STEP    B TO CLOSE",
                        )
                        cue.recognised()
                        continue
                    }
                    val guarded = id in GUARDED_ROWS
                    if (guarded && armed.value?.first != id) {
                        armed.value = id to nowMs
                        appRef.value?.update(
                            appRows(ctx, link, id),
                            when (id) {
                                "CHANSEND" -> "PICK AGAIN TO ALLOW CHANNEL SEND"
                                else -> "PICK AGAIN TO ERASE — CANNOT BE UNDONE"
                            },
                        )
                        cue.closed()
                        continue
                    }
                    armed.value = null
                    when (id) {
                        "LOCATION" -> Settings.setUseDeviceLocation(
                            ctx, !Settings.useDeviceLocation(ctx),
                        )
                        "SHARE" -> Settings.setShareLocation(ctx, !Settings.shareLocation(ctx))
                        "DIAG" -> Settings.setDiagnostics(ctx, !Settings.diagnostics(ctx))
                        "AUTOPEN" -> Settings.setAutopen(ctx, !Settings.autopen(ctx))
                        "MOTION" -> {
                            val on = !Settings.reduceMotion(ctx)
                            Settings.setReduceMotion(ctx, on)
                            // Read by every surface's reveal on the next frame;
                            // no rebuild, because a transition grammar is
                            // arithmetic rather than geometry.
                            com.iotj.meshmore.xr.spatial.Reveal.reduced = on
                        }
                        // THE ONE THAT WIDENS WHAT THE RADIO SAYS. MeshLink
                        // stays the single gate; this only sets the flag it
                        // reads, and the refusal path is untouched.
                        "CHANSEND" -> {
                            val on = !Settings.channelSend(ctx)
                            Settings.setChannelSend(ctx, on)
                            link.channelTxAuthorised = on
                            noticeRef.value?.say(
                                if (on) "CHANNEL SEND ALLOWED" else "CHANNEL SEND OFF",
                            )
                        }
                        "FORGET" -> {
                            val n = link.msgs.value.size
                            link.forgetMessages()
                            noticeRef.value?.say("$n MESSAGES ERASED")
                        }
                    }
                    appRef.value?.update(appRows(ctx, link, null), "LIT = ON    B TO CLOSE")
                    cue.recognised()
                }
                // THE THEME PICKER. A pick retints the whole scene in place —
                // including the picker's own readout, and including the HORIZON
                // behind it, which is the point (§S11: "you see your real mesh
                // restyled in place"). Persisted here rather than in the
                // surface, so one place in the app owns what choosing means.
                themePickerRef.value?.tick(stage.headNow()?.translation)
                while (true) {
                    val chosen = themePickerRef.value?.poll() ?: break
                    if (chosen == skin.value) {
                        // PICKING WHAT YOU ARE ALREADY WEARING IS THE WAY OUT.
                        // There is no separate CLOSE control: the tile you are
                        // standing in is the one under the cursor, so choosing
                        // it again is the gesture people try first and it costs
                        // no arc to support.
                        themePickerRef.value?.hide()
                        cue.closed()
                    } else {
                        skin.value = chosen
                        // ARRIVAL, NOT PREVIEW. The picker samples a pack's
                        // TONE as you scroll past each tile, which is what makes
                        // the choice audible; the welcome plays only on the one
                        // you land on. A tune firing on every tile you pass
                        // would be nine of them fighting over three seconds.
                        cue.welcome(ctx, Cue.welcomeFor(chosen.key))
                        // A TEST HOOK MUST NOT REWRITE A SETTING. `--es switchto`
                        // fires through this same queue on purpose — verifying
                        // the path a pinch takes is the whole point — but that
                        // made it persist too, and a debug launch left the
                        // wearer's stored theme changed. It did: an afternoon
                        // of `switchto` testing ended with the glasses booting
                        // into SEELE, whose black-on-additive substrate draws
                        // almost nothing, and the app read as frozen after the
                        // splash. Diagnosing a "stuck" app that was in fact
                        // working perfectly cost more than this line saves.
                        if (MainActivity.switchTo == null) themePrefs.set(chosen)
                        com.iotj.meshmore.xr.spatial.Ink.retint(chosen.palette)
                        // A THEME IS NOT A PALETTE, and until now choosing one
                        // acted as though it were. retint() repaints every
                        // material and moves nothing: pick BIOLUME here and you
                        // got its greens on the launch theme's discs, on the
                        // launch theme's floor, at the launch theme's distance.
                        // The structural half only ever applied at launch, via
                        // `--es theme`, which is not how anyone changes themes.
                        //
                        // So: hand the horizon the new symbol and posture, and
                        // bump the epoch the mesh effect already watches. That
                        // effect disposes and rebuilds the whole ring — which is
                        // what a symbol change requires anyway, since a mote's
                        // silhouette is baked into its mesh at build time.
                        horizonRef.value?.retheme(chosen.symbol, chosen.posture, chosen.active, chosen.palette)
                        hereEpoch.value += 1
                        // AND THE BAYS. A plate is GEOMETRY — a frame and a
                        // slab are different meshes — so the menus need a
                        // rebuild, not a repaint, and Ink cannot do it for
                        // them. Off the frame loop, because rebuilding two
                        // stacks means suspending on material creation and this
                        // is the frame the wearer is watching for a response.
                        launch {
                            channelsRef.value?.restyle(chosen)
                            appRef.value?.restyle(chosen)
                        }
                        themePickerRef.value?.commit(chosen)
                        themePickerRef.value?.setPreviewing(chosen)
                        noticeRef.value?.say(chosen.name)
                        // §S11: "hear the theme's audio pack fire on a sample
                        // event". The pack swaps with the palette and then
                        // announces itself, so a pick is seen AND heard — and
                        // the sample is a real app sound rather than a demo.
                        cue.pack = Cue.packFor(chosen.audio)
                        cue.sample()
                    }
                }
                // THE TABLE, IF ONE TURNS UP. Polled here rather than through a
                // state callback because the callback arrives off the main
                // thread and the scene may only be touched on it. One enum read
                // a frame is cheaper than making that safe.
                tableRef.value?.let { t ->
                    if (t.poll()) {
                        horizonRef.value?.tableAt = t.at
                        hereEpoch.value += 1
                    }
                }
                consoleRef.value?.tick(stage.headNow()?.translation)
                while (true) {
                    val bay = consoleRef.value?.poll() ?: break
                    when (bay) {
                        // The rack, unchanged and with its guards intact. The
                        // console changes how you REACH it, not how it works.
                        // S9 — RADIO CONFIG, as rows rather than as a rack.
                        //
                        // The rack is still built and still reachable with
                        // --ez radio true: it is a better OBJECT and a worse
                        // CONTROL, and there is no reason to delete a thing
                        // that photographs well. But the default path to
                        // changing a radio parameter is now a surface whose
                        // targets you can hit.
                        "DEVICE" -> {
                            consoleRef.value?.hide()
                            armed.value = null
                            aboutOpen.value = false
                            bayMode.value = "RADIO"
                            appRef.value?.show(
                                radioRows(link.radio),
                                title = com.iotj.meshmore.xr.spatial.radioTitle(
                                    link.radio.live?.freqMhz, link.radio.live?.txDbm,
                                ),
                                footer = if (link.radio.dirty()) "PENDING — COMMIT TO APPLY"
                                else "PICK TO STEP    B TO CLOSE",
                            )
                            dockRef.value?.setLit("SETUP", false)
                            cue.opened()
                        }
                        // Not a console tile — there is no REGION pip. It is
                        // here so `--es bay REGION` can reach the list the same
                        // way a hand does, since the surface it lives behind is
                        // two pinches deep and unverifiable from a shell.
                        "REGION" -> openRegions()
                        "DIAG" -> {
                            val on = !Settings.diagnostics(ctx)
                            Settings.setDiagnostics(ctx, on)
                            noticeRef.value?.say(
                                if (on) "DIAGNOSTICS ON" else "DIAGNOSTICS OFF",
                            )
                            cue.opened()
                        }
                        // S5 — CHANNELS. Which bands the radio carries, and
                        // which of them read themselves aloud. This is the only
                        // place the TTS toggle can be REACHED for a channel that
                        // has gone quiet, which is exactly when somebody wants
                        // to turn it off.
                        "CHANNELS" -> {
                            consoleRef.value?.hide()
                            // Opened UNARMED, always. A rolled name that
                            // survived a trip out of the bay would be sitting
                            // one pinch from a write next time it opened.
                            chanArmed.value = null
                            channelsRef.value?.show(
                                channelRows(link, voice, null),
                                title = "CHANNELS — PICK TO SPEAK",
                                footer = if (link.channels().isEmpty())
                                    "CONNECT A RADIO TO SEE ITS SLOTS"
                                else chanFooter(null),
                            )
                            dockRef.value?.setLit("SETUP", false)
                            cue.opened()
                        }
                        // APP — the settings that are about this app rather
                        // than about the radio. Console spec §10 wants the
                        // connection state as a LAMP rather than a row, so it
                        // lives in the title: it is something you read, not
                        // something you can change from here.
                        "APP" -> {
                            consoleRef.value?.hide()
                            armed.value = null
                            aboutOpen.value = false
                            bayMode.value = "APP"
                            appRef.value?.show(
                                appRows(ctx, link, armed.value?.first),
                                title = "APP — CONNECTION: " +
                                    link.status.value.state.name,
                                footer = "LIT = ON    B TO CLOSE",
                            )
                            dockRef.value?.setLit("SETUP", false)
                            cue.opened()
                        }
                        // S12 · ABOUT · TERMS · SAFETY. Read-only, and the
                        // safety copy is the reason it exists rather than the
                        // version number: "do not use while driving" has to BE
                        // somewhere a wearer can find, and a line in a store
                        // listing is not somewhere a wearer can find.
                        "ABOUT" -> {
                            consoleRef.value?.hide()
                            bayMode.value = "ABOUT"
                            appRef.value?.show(
                                aboutRows(link),
                                title = "ABOUT MESHMORE XR",
                                footer = "READ ONLY — B TO CLOSE",
                            )
                            aboutOpen.value = true
                            dockRef.value?.setLit("SETUP", false)
                            cue.opened()
                        }
                        // S11 — THEME & VOICE. The picker previews by retinting
                        // the real scene, so it opens in front of the wearer
                        // with the HORIZON still behind it: that IS the preview
                        // the brief asks for, and a swatch would be a worse one.
                        "PROFILE" -> {
                            val h = stage.headNow()
                            if (h == null) {
                                noticeRef.value?.say("NOT TRACKING YET")
                            } else {
                                consoleRef.value?.hide()
                                themePickerRef.value?.showAt(
                                    h.translation, yawOf(h), skin.value,
                                )
                                dockRef.value?.setLit("SETUP", false)
                                cue.opened()
                            }
                        }
                        // HONEST ABOUT WHAT IS NOT BUILT. A plate that opens
                        // nothing and says nothing reads as a fault; one that
                        // says so reads as a roadmap.
                        else -> {
                            noticeRef.value?.say("$bay — NOT BUILT YET")
                            cue.closed()
                        }
                    }
                }
                inboxRef.value?.tick(stage.headNow()?.translation)
                threadRef.value?.tick(stage.headNow()?.translation)
                while (true) {
                    val pick = inboxRef.value?.poll() ?: break
                    val id = inboxRef.value?.activate(pick) ?: continue
                    // OPENING A THREAD REPLACES THE LIST. One FOCUS at a time
                    // (§2.1 rule 3) — and a corridor of messages standing in
                    // front of the list it came from is two readable things
                    // competing for the same glance.
                    val h = stage.headNow() ?: continue
                    val t = link.threads().firstOrNull { it.id == id } ?: continue
                    val nowS = System.currentTimeMillis() / 1000
                    threadRef.value?.showAt(
                        h.translation, yawOf(h), t.id, t.title,
                        t.messages.map { m ->
                            com.iotj.meshmore.xr.spatial.Thread.Line(
                                who = "%-14s %s".format(
                                    com.iotj.meshmore.xr.spatial.TypeTier.clip(
                                        m.fromName.ifBlank { t.title }, 14,
                                    ),
                                    ago(nowS - m.atEpochSec),
                                ),
                                words = com.iotj.meshmore.xr.spatial.TypeTier.clip(m.text, 24),
                                mine = m.direct,
                            )
                        },
                    )
                    inboxRef.value?.hide()
                    cue.opened()
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
                    // THE PICKER FIRST, AND IT REVERTS. Everywhere else B just
                    // closes; here it also puts the theme back, because the
                    // picker previews by changing the whole world and a wearer
                    // who tried all nine has no other way to find the one they
                    // walked in with. Backing out of a preview must mean
                    // "nothing happened".
                    // THE HELP CARD IS FIRST, because it is IN FRONT. It is the
                    // one surface that covers the field rather than sitting in
                    // it, so whatever else is open is open BEHIND it — closing
                    // that instead would look like B doing nothing at all,
                    // twice, which is what it looked like. It was also the only
                    // surface never added to this chain: the card lists "B —
                    // BACK" among its own rows and did not answer to it.
                    // THE KEYBOARD, before anything else it might be sitting
                    // over. B puts the panel away and LEAVES THE QUERY: backing
                    // out of a keyboard is not a request to see all 350 nodes
                    // again, and a wearer who wanted that has CLEAR.
                    if (searchOpen.value) {
                        lastBackAt = nowMs
                        searchOpen.value = false
                        dockRef.value?.setLit("FIND", query.value.isNotEmpty())
                        cue.closed()
                        Log.i(TAG_UI, "[hand] $hand:B — find closed, query '${query.value}'")
                        return
                    }
                    helpRef.value?.let { h ->
                        if (h.visible) {
                            lastBackAt = nowMs
                            h.setVisible(false); cue.closed()
                            Log.i(TAG_UI, "[hand] $hand:B — help closed")
                            return
                        }
                    }
                    appRef.value?.let { a ->
                        if (a.open) {
                            lastBackAt = nowMs
                            armed.value = null
                            aboutOpen.value = false
                            a.hide(); cue.closed()
                            Log.i(TAG_UI, "[hand] $hand:B — app bay closed")
                            return
                        }
                    }
                    channelsRef.value?.let { c ->
                        if (c.open) {
                            lastBackAt = nowMs
                            c.hide(); cue.closed()
                            Log.i(TAG_UI, "[hand] $hand:B — channels closed")
                            return
                        }
                    }
                    // THE CONSOLE, AND THE TWO LISTS. Added because B did not
                    // close them and the footers had been promising it did.
                    //
                    // B unwound the bays but not the surface the bays open OUT
                    // of, so backing out of the settings fan fell through to
                    // popping a lens level instead — a gesture that answered a
                    // question about the horizon while a menu sat in front of
                    // the wearer. The roster and the inbox were missed the same
                    // way: every one of them is a thing you open and therefore
                    // a thing "back" has to close, or the gesture means
                    // something different depending on what is up, which is the
                    // one property a back gesture cannot have.
                    //
                    // Ordered inside-out, like the rest of this chain: a bay
                    // closes before the console it came from.
                    consoleRef.value?.let { c ->
                        if (c.open) {
                            lastBackAt = nowMs
                            c.hide(); cue.closed()
                            Log.i(TAG_UI, "[hand] $hand:B — console closed")
                            return
                        }
                    }
                    rosterRef.value?.let { r ->
                        if (r.open) {
                            lastBackAt = nowMs
                            r.hide(); cue.closed()
                            dockRef.value?.setLit("LIST", false)
                            Log.i(TAG_UI, "[hand] $hand:B — roster closed")
                            return
                        }
                    }
                    inboxRef.value?.let { i ->
                        if (i.open) {
                            lastBackAt = nowMs
                            i.hide(); cue.closed()
                            dockRef.value?.setLit("INBOX", false)
                            Log.i(TAG_UI, "[hand] $hand:B — inbox closed")
                            return
                        }
                    }
                    themePickerRef.value?.let { p ->
                        if (p.open) {
                            lastBackAt = nowMs
                            val was = p.previewing
                            p.cancel()
                            if (p.previewing != was) {
                                skin.value = p.previewing
                                themePrefs.set(p.previewing)
                                com.iotj.meshmore.xr.spatial.Ink.retint(p.previewing.palette)
                                cue.pack = Cue.packFor(p.previewing.audio)
                            }
                            cue.closed()
                            Log.i(TAG_UI, "[hand] $hand:B — theme picker closed")
                            return
                        }
                    }
                    threadRef.value?.let { t ->
                        if (t.open) {
                            lastBackAt = nowMs
                            t.hide(); cue.closed()
                            Log.i(TAG_UI, "[hand] $hand:B — thread closed")
                            return
                        }
                    }
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

                /**
                 * R — RESET THE VIEW: bring the ring to where you are standing now,
                 * WITHOUT touching which way north is.
                 *
                 * That second half is the whole point and the easy thing to get wrong.
                 * Stage.recentre() derives yaw from the current facing, so calling it
                 * here would silently redefine north as "whatever direction you were
                 * looking when you pressed reset" — undoing the NORTH correction and
                 * rotating every bearing in the app. A reset that breaks the compass is
                 * not a reset.
                 *
                 * So it moves the origin's POSITION and keeps its yaw. Walk to another
                 * room, press R, and the ring follows you with its bearings intact.
                 *
                 * If north was never established it says so rather than inventing one:
                 * this hardware publishes no magnetometer, so "orient to true north" is
                 * only meaningful once somebody has told it north once.
                 */
                val northKnown = MainActivity.northDeg != null
                fun resetView(hand: String) {
                    if (nowMs - lastBackAt < BACK_OUT_MS) return
                    lastBackAt = nowMs
                    val h = stage.headNow()
                    val o = originRef.value
                    if (h == null || o == null) {
                cue.closed()
                Log.w(TAG_UI, "[reset] no head pose")
                return
                    }
                    val t = h.translation
                    originRef.value = o.copy(x = t.x, y = t.y, z = t.z)
                    hereEpoch.value += 1
                    cue.opened()
                    noticeRef.value?.say(
                // NAMES WHAT MOVED. "VIEW RESET" reads as an undo — as though
                // something were being put back — when what happened is that
                // the scene picked itself up and re-centred on the wearer.
                if (northKnown) "SCENE MOVED HERE"
                else "SCENE MOVED HERE  NORTH NOT SET",
                    )
                    Log.i(TAG_UI, "[reset] $hand:R — origin moved to (%.2f, %.2f, %.2f), yaw kept %.1f°"
                .format(t.x, t.y, t.z, Math.toDegrees(o.yawRad.toDouble())))
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
                    // Presented, like B: a reset is not something to issue by
                    // resting a hand somewhere.
                    // H AND R BOTH RECENTRE, and that is a fix rather than a
                    // convenience.
                    //
                    // They are the SAME TWO FINGERS and differ only by the
                    // crossing — the classifier says so in as many words, and
                    // tests R first so a crossed hand is not swallowed by H. The
                    // consequence was silent: a wearer signing R whose crossing
                    // the tracker did not resolve got H, which was bound to
                    // nothing at all, so the gesture did nothing and looked like
                    // a feature that was never built. Reported as exactly that.
                    //
                    // Binding both to the same action makes the crossing stop
                    // mattering. It also gives the action the better letter: H
                    // for HERE, which is already this app's word for where the
                    // wearer is — the HERE pip, the HERE marker — and is a flat
                    // two-finger shape rather than a crossed one, which is the
                    // easier thing to do one-handed on a bike.
                    if ((gotR == com.iotj.meshmore.xr.spatial.HandSign.Letter.R ||
                            gotR == com.iotj.meshmore.xr.spatial.HandSign.Letter.H) &&
                        handsRef.value?.presented(j, it0) == true
                    ) {
                        resetView(if (gotR == com.iotj.meshmore.xr.spatial.HandSign.Letter.H) "R:H" else "R")
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
                    // Same on the left — see the note on the right hand.
                    if ((gotL == com.iotj.meshmore.xr.spatial.HandSign.Letter.R ||
                            gotL == com.iotj.meshmore.xr.spatial.HandSign.Letter.H) &&
                        handsRef.value?.presented(j, it0) == true
                    ) {
                        resetView(if (gotL == com.iotj.meshmore.xr.spatial.HandSign.Letter.H) "L:H" else "L")
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
                    // WHY THE RING IS EMPTY, in the one readout that is always
                    // in front of the wearer.
                    //
                    // "4/349" is a true statement that answers the wrong
                    // question. With no position fix there is nothing to
                    // measure a bearing FROM, so 345 perfectly good nodes have
                    // nowhere to be drawn — and the wearer sees an empty ring, a
                    // connected radio, and no way at all to connect the two.
                    // Reported as "I can't see anything (no nodes)" while the
                    // radio was healthy and hearing repeaters.
                    //
                    // The HERE marker has carried this remedy for a while, but
                    // it is a marker on the ground at the origin: it is not
                    // where you are looking when you wonder, and in a theme that
                    // draws little it may not be in the field at all. The status
                    // band is head-locked, which is exactly the property this
                    // needs.
                    val placed = hereSource.here.value.known
                    val count = if (placed) {
                        "%d/%d".format(nodesRef.value.size, mesh.size)
                    } else {
                        "NO FIX  %d UNPLACED".format(mesh.size)
                    }
                    hudRef.value?.setStatus(
                        "%s%s  %s%s%s".format(
                            // LINK / DISC / "LOST 4M" — after a drop the chip
                            // carries the age of the outage, because that is the
                            // age of everything else on the horizon too.
                            link.linkChip(),
                            batt, count,
                            positionMark(hereSource.source, Settings.shareLocation(ctx)),
                            // The unread count, in the band rather than the
                            // world window. Distinguished by FORM as well as
                            // number when the CUFF lands.
                            if (unread.value > 0) "  %d NEW".format(unread.value) else "",
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

    // THE ONE PANEL THIS APP ADMITS TO.
    //
    // Everything else here is geometry in the room, on principle — a panel is
    // what makes an XR app feel like a phone app that happens to be floating.
    // This is the exception and it earns it the same way the radio log does: a
    // text field is a text field. It needs the system IME, the IME needs a real
    // focusable view, and reinventing either in stroked geometry would produce
    // a worse keyboard than the platform's and no speech input at all.
    //
    // It sits BESIDE the forward arc rather than in it, so the ring it is
    // filtering stays visible while the query is typed. Watching the mesh narrow
    // as you type is the entire feedback loop; a panel that covered the horizon
    // would hide the result of its own filtering.
    if (searchOpen.value) {
        Subspace {
            SpatialPanel(
                SubspaceModifier.width(560.dp).height(190.dp)
                    .offset(x = 300.dp, y = (-120).dp, z = 260.dp)
                    .rotate(0f, -22f, 0f),
            ) {
                SearchSurface(
                    query = query.value,
                    onQuery = { query.value = Search.normalise(it) },
                    matched = nodesRef.value.size,
                    total = mesh.size,
                    onClose = { searchOpen.value = false },
                )
            }
        }
    }
}

/**
 * The field, the count, and a way out.
 *
 * DELIBERATELY PLAIN. This is the one surface in the app where the platform's
 * own conventions beat the theme's — a text field that does not look like a text
 * field does not get typed into, and the keyboard that appears over it is the
 * system's and will not match any of the nine palettes however hard this tries.
 *
 * The count under the field is the whole confirmation loop, and it must
 * distinguish "no matches" from "not searching": those look identical on a ring
 * that was already sparse, and they call for opposite next moves.
 */
@Composable
private fun SearchSurface(
    query: String,
    onQuery: (String) -> Unit,
    matched: Int,
    total: Int,
    onClose: () -> Unit,
) {
    val focus = remember { FocusRequester() }
    // THE KEYBOARD COMES UP WITH THE PANEL. A search you have to tap into
    // before you can type is a search with an extra step that exists only
    // because nobody asked for the focus.
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xE0121820))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("FIND", color = Color(0xFF66E8D0), fontSize = 15.sp)
        OutlinedTextField(
            value = query,
            onValueChange = onQuery,
            singleLine = true,
            placeholder = { Text("CALLSIGN OR KEY", color = Color(0xFF6E7C88)) },
            textStyle = LocalTextStyle.current.copy(color = Color(0xFFDDE7EF), fontSize = 22.sp),
            modifier = Modifier.fillMaxWidth().focusRequester(focus),
        )
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                Search.summary(matched, total, query),
                color = if (matched == 0 && Search.normalise(query).isNotEmpty()) {
                    Color(0xFFFF6B6B)
                } else {
                    Color(0xFFDDE7EF)
                },
                fontSize = 16.sp,
            )
            // CLEARING AND CLOSING ARE DIFFERENT ACTS, and both are needed: the
            // query outlives the panel on purpose, so without a CLEAR the only
            // way back to the whole mesh would be to reopen the panel and empty
            // the field by hand.
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                TextButton(onClick = { onQuery("") }) {
                    Text("CLEAR", color = Color(0xFF66E8D0), fontSize = 15.sp)
                }
                TextButton(onClick = onClose) {
                    Text("DONE", color = Color(0xFF66E8D0), fontSize = 15.sp)
                }
            }
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
/**
 * THE POSITION MARK, in the lower band — is this thing using my GPS, and is it
 * telling anybody.
 *
 * TWO SETTINGS, AND ONLY ONE OF THEM IS THE DOXXING ONE. Using a fix locally to
 * work out which way a node lies is arithmetic that never leaves the headset;
 * putting your coordinates into an advert is a broadcast, unencrypted, to
 * everyone in radio range. They were equally invisible, which meant the safe one
 * felt as risky as the dangerous one and got left off — and with it off the
 * whole horizon is empty. So the safe one gets a quiet standing mark and the
 * broadcast gets a louder one that names what it does.
 *
 * ARMED IS NOT THE SAME AS IN USE. With the radio's own fix good, the headset
 * setting is on and doing nothing, and a band that said GPS then would be
 * claiming the wearer's own GPS is running when it is not. The mark follows the
 * SOURCE actually in use, which is the only thing that is true.
 */
internal fun positionMark(
    source: String,
    sharing: Boolean,
): String {
    val using = when (source) {
        "headset" -> "  GPS"
        "radio" -> "  POS RADIO"
        "stated" -> "  POS SET"
        else -> ""
    }
    // Appended to whatever the source is, because sharing is a fact about the
    // air and not about where the number came from.
    return using + if (sharing && using.isNotEmpty()) " SHARED" else ""
}

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

/**
 * ACT ON THE MESSAGE ON THE CARD.
 *
 * Lives outside the scene composable because it is a decision table, and a
 * decision table buried in a tick loop is where behaviour goes to become
 * untraceable. Every branch ends with the wearer being TOLD something: on a
 * mesh radio there is no delivery receipt and no other way to find out whether
 * a reply left, and "did that send?" is not a question a companion app should
 * make anyone hold in their head.
 */
private fun onCrown(
    act: Crown.Act,
    link: MeshLink,
    reel: com.iotj.meshmore.xr.spatial.Reel,
    crown: Crown,
    thread: com.iotj.meshmore.xr.spatial.Thread?,
    speech: Speech,
    dictation: Dictation,
    voice: VoicePrefs,
    cue: Cue,
    stage: com.iotj.meshmore.xr.spatial.Stage,
    nowMs: Long,
    askMic: () -> Unit,
) {
    // The REAL message, not the reel's display copy: the copy is clipped for
    // the card and acting on a clipped message would be its own bug.
    val msg = link.msgs.value.getOrNull(reel.selectedIndex)
    val threadId = msg?.let { if (it.direct) it.fromKey else (it.channel ?: "#") }
    when (act) {
        Crown.Act.REPLY -> { crown.compose(); cue.opened() }
        Crown.Act.BACK -> { dictation.cancel(); crown.backToActions(); cue.closed() }
        Crown.Act.CANCEL -> {
            // Back to composing rather than out altogether: cancelling a draft
            // means "not those words", almost never "not at all".
            dictation.cancel(); crown.backToCompose(); cue.closed()
        }
        Crown.Act.DISMISS -> { dictation.cancel(); crown.hide(); cue.closed() }
        Crown.Act.VOICE -> {
            val now = voice.toggle(threadId)
            crown.voiceOn = now
            // NAMED. "VOICE ON FOR THIS" leaves the wearer to work out what
            // "this" was, which on a surface that scrolls between conversations
            // is exactly the thing they cannot be sure of.
            val what = crown.voiceScope.ifBlank { "THIS" }
            crown.say(if (now) "SPEAKING $what" else "SILENT: $what", nowMs)
            cue.recognised()
        }
        Crown.Act.ALOUD -> {
            if (msg == null) {
                crown.say("NOTHING TO READ", nowMs)
            } else {
                // WHO, then what. A disembodied sentence in your ear is a worse
                // experience than no audio at all.
                val who = msg.fromName.ifBlank { msg.channelName ?: "someone" }
                speech.say("$who says: ${msg.text}")
                crown.say("READING ALOUD", nowMs)
            }
            cue.recognised()
        }
        Crown.Act.SPEAK -> {
            when {
                dictation.listening -> dictation.stop()
                // The grant is requested HERE, the first time somebody asks to
                // talk, rather than at startup where it would look like the app
                // wanted to listen to the room.
                !dictation.hasPermission() -> { crown.say("ASKING FOR MIC", nowMs); askMic() }
                else -> {
                    dictation.start()
                    dictation.problem?.let { crown.say(it, nowMs) }
                }
            }
            cue.opened()
        }
        Crown.Act.THREAD -> {
            val h = stage.headNow()
            val t = link.threads().firstOrNull { th ->
                msg != null && th.messages.any { it.atEpochSec == msg.atEpochSec }
            }
            if (h == null || t == null) {
                crown.say("NO THREAD FOR THIS", nowMs)
                cue.closed()
            } else {
                val nowS = System.currentTimeMillis() / 1000
                thread?.showAt(
                    h.translation, yawOf(h), t.id, t.title,
                    t.messages.map { m ->
                        com.iotj.meshmore.xr.spatial.Thread.Line(
                            who = "%-14s %s".format(
                                com.iotj.meshmore.xr.spatial.TypeTier.clip(
                                    m.fromName.ifBlank { t.title }, 14,
                                ),
                                ago(nowS - m.atEpochSec),
                            ),
                            words = com.iotj.meshmore.xr.spatial.TypeTier.clip(m.text, 24),
                            mine = m.direct,
                        )
                    },
                )
                crown.hide()
                cue.opened()
            }
        }
        // A CANNED REPLY IS A DRAFT, NOT A TRANSMISSION. These used to send on
        // the spot, which is the accidental send this was built to prevent: a
        // pinch landing one slot wrong put words on a shared band with nothing
        // in between. Now they propose, and the confirm level sends.
        Crown.Act.SEND_1 -> { crown.propose("ROGER"); cue.opened() }
        Crown.Act.SEND_2 -> { crown.propose("ON MY WAY"); cue.opened() }
        Crown.Act.SEND_3 -> { crown.propose("STAND BY"); cue.opened() }
        // AUTOPEN. Routed through the SAME confirm level as every other draft
        // -- proposeGenerated differs only in that it remembers the words were
        // not the wearer's, so the confirm screen can say so. The row is only
        // offered when there is a suggestion at all, so a null here means the
        // pick raced a card change and doing nothing is right.
        Crown.Act.SEND_AUTO -> {
            val s = crown.suggestion
            if (s.isNullOrBlank()) { crown.say("NO SUGGESTION", nowMs); cue.closed() }
            else { crown.proposeGenerated(s); cue.opened() }
        }
        Crown.Act.CONFIRM -> {
            val text = crown.pending
            // SAY WHAT WE ARE ABOUT TO DO, ALWAYS. A reply that does not arrive
            // at the other end is the hardest thing in this app to diagnose
            // from the outside — the wearer sees a confirm screen and then
            // nothing, and the radio's own log is the only witness. One line
            // before the attempt turns "it didn't send" into a question with an
            // answer.
            Log.i(
                TAG_UI,
                "[crown] CONFIRM idx=${reel.selectedIndex} msg=" +
                    (msg?.let { "${it.fromName}/${if (it.direct) "DM" else it.channel}" }
                        ?: "NONE") +
                    " text='" + text.take(40) + "'",
            )
            if (msg == null || text.isBlank()) {
                Log.w(TAG_UI, "[crown] nothing to send: msg=${msg != null} blank=${text.isBlank()}")
                crown.say("NOTHING TO SEND", nowMs)
                cue.closed()
                return
            }
            when (val r = link.replyTo(msg, text)) {
                is MeshLink.Sent.Ok -> {
                    crown.say("SENT", nowMs); crown.backToActions(); cue.recognised()
                }
                is MeshLink.Sent.NotReady -> { crown.say("RADIO NOT READY", nowMs); cue.closed() }
                is MeshLink.Sent.Refused -> {
                    // The reason verbatim. "It did not send" and "it is not
                    // allowed to send" want different things from the reader,
                    // and only one of them is worth trying again.
                    crown.say(r.why, nowMs); cue.closed()
                }
            }
        }
    }
}
