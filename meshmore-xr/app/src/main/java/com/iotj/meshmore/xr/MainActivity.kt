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
import androidx.xr.scenecore.scene
import androidx.xr.compose.platform.requestHomeSpace
import androidx.xr.compose.spatial.Subspace
import androidx.xr.compose.subspace.SpatialPanel
import androidx.xr.compose.subspace.layout.SubspaceModifier
import androidx.xr.compose.subspace.layout.height
import androidx.xr.compose.subspace.layout.width
import com.iotj.meshmore.xr.spatial.Horizon
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
    }

    // One link per activity. Checkpoint 3 lives here.
    private val link by lazy { MeshLink(this) }

    override fun onDestroy() {
        link.close()
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i(TAG, "[boot] onCreate — ${Build.MANUFACTURER} ${Build.MODEL} api=${Build.VERSION.SDK_INT}")

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
    LaunchedEffect(Unit) {
        if (linkTried) return@LaunchedEffect
        linkTried = true
        if (link.hasBlePermissions()) {
            Log.i(TAG_UI, "[link] auto-connect at startup")
            if (pinOverride != null) link.connect(pin = pinOverride) else link.connect()
        } else {
            Log.i(TAG_UI, "[link] no BLE permission at startup — waiting for user")
        }
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
        HorizonScene()
        if (debug) {
            Subspace {
                SpatialPanel(SubspaceModifier.width(560.dp).height(420.dp)) {
                    DiagnosticSurface { StatusScreen(facts, link, spatial = true) }
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
@Composable
private fun HorizonScene() {
    val session = LocalSession.current ?: return

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
        val origin = stage.recentre()

        val horizon = Horizon(session, palette)
        // Deliberately includes the shapes real MeshCore names take: emoji,
        // fullwidth Latin, accents, kana, and a name that is nothing BUT emoji.
        // If any of these can break the label path, better it breaks here.
        val names = listOf(
            "kanako.1", "davi1 \uD83D\uDE80", "relay-nw", "t1000-e", "gate-cam",
            "\uD83D\uDC22 turtle relay", "\uFF2F\uFF2B\uFF41\uFF59", "shed",
            "\u00D6konomy", "\u3042\u304D\u306F\u3070\u3089", "\uD83C\uDF0A\uD83C\uDF0A",
        )
        val nodes = names.mapIndexed { i, nm ->
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
        Log.i(TAG_UI, "[horizon] building ${nodes.size} nodes")
        // Floor first: the room claims itself, then the mesh arrives on top.
        stage.buildFloor(origin)
        horizon.build(nodes, origin, stage.floorHeight())

        // Frame loop: pulses decay, and a packet lands every so often so the
        // mesh visibly breathes. ~30 Hz is plenty for this motion.
        var since = 0f
        var fall = 0f
        try {
            if (MainActivity.selfTest) launch { horizon.selfTest(origin) }
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
                stage.headNow()?.let { horizon.faceViewer(it.translation) }
                horizon.drainSelections(origin)
                horizon.tick(0.033f)
                since += 0.033f
                if (since > 1.4f) {
                    since = 0f
                    val n = nodes.filter { it.located }.random(Random)
                    horizon.pulse(n.bearingRad, n.dist, origin)
                }
            }
        } finally {
            horizon.clear()
            stage.clearFloor()
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
