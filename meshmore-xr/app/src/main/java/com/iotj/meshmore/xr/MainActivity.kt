// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.Crown
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import kotlinx.coroutines.sync.withLock
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.text.input.ImeAction
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
         * `--ez dm true` : address the first node on the ring, as though its
         * MESSAGE verb had been pinched. The compose crown is otherwise
         * reachable only through a hand, which no emulator has.
         */
        var dmProbe: Boolean = false

        /**
         * `--es gc dry` : say what a sweep would take, touching nothing.
         * `--es gc go`  : take it.
         *
         * The sweep lives on a settings row, which means it can only be run by
         * a hand — and the first time it was run in anger the operator could
         * not tell whether it had worked, the log had rotated out of a 4 MiB
         * ring buffer, and the radio still held 349 contacts. A destructive
         * operation with no way to rehearse it and no durable account of what
         * it did is not finished. DRY IS THE DEFAULT for anything but the
         * literal string "go".
         */
        var gcProbe: String? = null

        /**
         * `--ez neighbours true` : who is actually one hop away.
         *
         * "We should have four devices in range at zero hops" is a claim about
         * RF adjacency, and the app has never been able to answer it: the ring
         * draws everything the radio holds, and an advert heard once an hour
         * looks identical whether it arrived directly or was relayed across the
         * county. MeshCore stores a PATH LENGTH per contact — one hop means a
         * direct neighbour — and that is the number this prints.
         */
        var neighbourProbe: Boolean = false

        /**
         * `--es soak d563` : send a message to the operator's own node on a
         * timer and account for every one of them, for `--es soakmin` minutes
         * at `--es soakint` seconds apart.
         *
         * ONLY EVER TO A NODE THE ALLOW-LIST ADMITS — MeshLink refuses anything
         * else, and this passes the suffix through rather than a key so it
         * cannot be pointed at a stranger by a typo. Airtime is shared: one a
         * minute for an hour is sixty transmissions, which is a test; one a
         * second would be an attack on everybody else's mesh.
         */
        var soakTo: String? = null
        var soakMinutes: Int = 60
        var soakEverySec: Int = 60
        /**
         * --es query "rep" : start with the filter already applied.
         *
         * The panel needs a keyboard and a hand, so the FILTER — which is the
         * part with the arithmetic in it — could only ever be exercised by
         * somebody wearing the glasses. This sets the same state a typed query
         * would, which makes the narrowing measurable from a script: the
         * horizon logs how many of how many survived.
         */
        var queryOverride: String? = null
        var farOverride: Double? = null
        var staleOverride: Int? = null
        /**
         * --es board "M5 C6L" : claim the attached radio is a board we believe
         * has no GNSS, without owning one.
         *
         * The hint this drives is the answer to "why is nothing on the ring",
         * and the only honest way to see it is with a radio that really cannot
         * report a position. Testing it by carrying the right board to the
         * right place is not a test, it is a coincidence.
         */
        var boardOverride: String? = null
        /**
         * --ez menu true : open the cluster menu on the first cluster found.
         *
         * The menu only appears by pinching a cluster mote, so nothing about it
         * can be checked without a hand in front of the glasses — which is how
         * it shipped with no focus state at all and nobody noticed.
         */
        var showMenu: Boolean = false
        /**
         * `--ez crown true` opens the crown's ACTIONS screen on a node,
         * preferring a starred one.
         *
         * The screen only ever opened under a hand before, so the rows it
         * chooses — which is where SOAK and RESEND compete for the last slot —
         * could not be read anywhere but on worn glass. The row budget is
         * exactly the thing that failed silently, so it needed a way to be
         * looked at.
         */
        var crownProbe: Boolean = false

        /**
         * `--ei soak N` runs N soaks back to back at a starred node and prints
         * the ledger after each.
         *
         * A one-in-ten loss cannot be seen in ten messages: the run that shows
         * 10/10 and the run that shows 8/10 are the same mesh. The rate needs
         * a few hundred packets, which is an hour of somebody pinching a menu
         * — so it is a flag, and the glasses can be left on a table doing it.
         */
        var soakRuns: Int = 0

        /**
         * `--es prefix <BLE name>` restricts the connect to one radio.
         *
         * Only for asking a specific device a question — see where it is read.
         * Left null in normal use, where the scanner's own ranking is right.
         */
        var namePrefix: String? = null

        /**
         * `--ez adopt true` alongside `--es prefix` means THIS ONE IS MINE.
         *
         * A prefixed connect deliberately does not adopt: reaching one radio
         * to ask it a question is not choosing it, and that rule is what keeps
         * an inbox read from silently rehoming the app. But a fresh install
         * has no memory at all, and if the operator owns two bonded radios the
         * first connect is decided by which happens to be louder — a coin toss
         * that then persists, because the first completed session is what
         * writes the memory.
         *
         * So there is a way to say it outright, used once, on a new install.
         */
        var adopt: Boolean = false

        /**
         * `--ez wxsweep true` runs one telemetry sweep and reports.
         *
         * The sweep is a pinch on a row, and a row cannot be pinched from a
         * cable. What it measures — how many of a real mesh's radios answer a
         * telemetry request at all — cannot be measured on the emulator
         * either, because a simulated peer has no radio to answer with. So it
         * needs a flag, and the answer needs the glasses on a live mesh.
         */
        var wxSweep: Boolean = false

        /**
         * `--es jointag "#soaktest" [--es channame soak]` writes a channel
         * whose KEY comes from a tag and whose NAME is whatever you say.
         *
         * The bay can only make a channel this app rolled itself, where the
         * tag is the name with a marker in front — which cannot express the
         * two things an operator actually needs: a channel called one thing
         * and keyed on another, and joining a channel somebody else made. The
         * derivation is the same either way, so this flag is the same write
         * with the two strings separated.
         */
        var joinTag: String? = null
        var joinName: String? = null

        /** `--ei chanslot N` writes to that slot even if it is occupied. */
        var chanSlot: Int = -1

        /** `--ez chanpublic true` writes the well-known public key. For repairs. */
        var chanPublic: Boolean = false

        /** `--ei chanclear N` empties a slot, to find out if the radio allows it. */
        var chanClear: Int = -1
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
        var probeEarth: Boolean = false
        /** vps | inertial | spatial — which geospatial mode the probe asks for. */
        var earthMode: String? = null
        /**
         * --es switchto <key> : after the scene is up, change theme AS IF
         * PICKED, to exercise the runtime path rather than the launch one.
         */
        var switchTo: String? = null
        /**
         * --ez sweep true : commit every theme in sequence through the REAL
         * picker path, four seconds apart.
         *
         * The regression this exists to catch was found by eye: a surface
         * built once at launch surviving into the next theme's world. One run
         * exercises all nine transitions; anything that lingers, crashes, or
         * over-runs a template says so in the log.
         */
        var sweep: Boolean = false
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
        // L10n.wrap so the link's own strings (the connect ladder) follow the
        // locale; `lazy` means this runs after onCreate has read --es lang.
        MeshLink(L10n.wrap(this)).also {
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
        // FIRST, before anything lazily touches a context: `--es lang ja`
        // forces the locale for a device test without changing the glasses'
        // system language. The link and every surface build from L10n.wrap.
        L10n.override = intent?.getStringExtra("lang")?.takeIf { it.isNotBlank() }
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
        // WHICH RADIO, WHEN THERE ARE THREE IN THE ROOM.
        //
        // The scanner ranks bonded first and strongest second, which is right
        // for a wearer putting the glasses on. It is wrong for the one job
        // that needs a specific radio: asking the RECEIVING end whether the
        // messages arrived. The soak sends from whichever radio the glasses
        // are bonded to; the only device that knows whether the mesh delivered
        // them is the one they were addressed to, and the only way to ask it
        // is to connect to it. `--es prefix MeshCore-D38F07AED563` does that.
        val prefix = intent?.getStringExtra("prefix")
        namePrefix = prefix?.takeIf { it.isNotBlank() }
        adopt = intent?.getBooleanExtra("adopt", false) ?: false
        wxSweep = intent?.getBooleanExtra("wxsweep", false) ?: false
        joinTag = intent?.getStringExtra("jointag")?.takeIf { it.isNotBlank() }
        joinName = intent?.getStringExtra("channame")?.takeIf { it.isNotBlank() }
        chanSlot = intent?.getIntExtra("chanslot", -1) ?: -1
        chanPublic = intent?.getBooleanExtra("chanpublic", false) ?: false
        chanClear = intent?.getIntExtra("chanclear", -1) ?: -1
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
        dmProbe = intent?.getBooleanExtra("dm", false) ?: false
        gcProbe = intent?.getStringExtra("gc")
        neighbourProbe = intent?.getBooleanExtra("neighbours", false) ?: false
        soakTo = intent?.getStringExtra("soak")
        soakMinutes = intent?.getStringExtra("soakmin")?.toIntOrNull() ?: 60
        soakEverySec = intent?.getStringExtra("soakint")?.toIntOrNull() ?: 60
        Log.i(TAG, "[boot] soak = ${soakTo ?: "off"} " +
            "(${soakMinutes}min every ${soakEverySec}s)")
        queryOverride = intent?.getStringExtra("query")?.takeIf { it.isNotBlank() }
        // `--es far 100` / `--es stale 24` : open FIND with the sweep filters
        // already set. The chips are a hand's work and no emulator has one.
        farOverride = intent?.getStringExtra("far")?.toDoubleOrNull()
        staleOverride = intent?.getStringExtra("stale")?.toIntOrNull()
        boardOverride = intent?.getStringExtra("board")?.takeIf { it.isNotBlank() }
        showMenu = intent?.getBooleanExtra("menu", false) ?: false
        crownProbe = intent?.getBooleanExtra("crown", false) ?: false
        soakRuns = intent?.getIntExtra("soak", 0) ?: 0
        showFocus = intent?.getBooleanExtra("focus", false) ?: false
        probePaths = intent?.getBooleanExtra("probe", false) ?: false
        probePlanes = intent?.getBooleanExtra("planes", false) ?: false
        // --ez earth true : ask the planet which way north is, and say what it
        // answers. Off by default because earth-relative tracking wants a
        // location grant and a network.
        earthMode = intent?.getStringExtra("earth")?.lowercase()
        probeEarth = earthMode != null
        switchTo = intent?.getStringExtra("switchto")
        sweep = intent?.getBooleanExtra("sweep", false) ?: false
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
        // `--es home none` : simulate, and stand nowhere. See below.
        val homeRaw = intent?.getStringExtra("home")
        homeOverride = homeRaw?.split(",")?.let { parts ->
            val la = parts.getOrNull(0)?.trim()?.toDoubleOrNull()
            val lo = parts.getOrNull(1)?.trim()?.toDoubleOrNull()
            if (la != null && lo != null) MeshNodes.Here(la, lo) else null
        }
        // A SIMULATION NEEDS SOMEWHERE TO STAND. Without a fix there is nothing
        // to measure a bearing from and all 350 fake peers are unplaceable —
        // which is a real failure mode, carefully signalled elsewhere, and not
        // the one anybody runs a simulation to look at.
        // EXCEPT WHEN THAT IS THE POINT. `--es home none` asks for the failure
        // itself: a mesh with no origin, which is what a wearer holding a
        // board with no GNSS actually has. It is the only way to see the card
        // and the hint that names their board without owning one.
        if (simulate && homeOverride == null && !homeRaw.equals("none", ignoreCase = true)) {
            homeOverride = MeshNodes.Here(SIM_HOME.lat, SIM_HOME.lon)
            Log.i(TAG, "[boot] simulated mesh — standing at $homeOverride")
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
        // `--ez alerts true` — the same door the DIAG panel has, for the same
        // reason: a panel that is off by default needs a way on that does not
        // require finding a settings row while wearing a headset.
        if (intent?.hasExtra("alerts") == true) {
            Settings.setAlerts(this, intent.getBooleanExtra("alerts", true))
        }
        Log.i(TAG, "[boot] alerts panel = ${Settings.alerts(this)}")
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
        // A SIMULATION DOES NOT SHARE A TABLE WITH A RADIO. Both write into the
        // same keyed peer map, so on the operator's own glasses a simulated run
        // would be 350 fabricated peers plus 350 real ones — a fine stress test
        // and a useless measurement, because no count afterwards belongs to
        // either mesh. The whole value of a seeded dataset is that the numbers
        // are the same every time.
        if (MainActivity.simulate) {
            Log.i(TAG_UI, "[link] SIMULATING — radio not dialled")
            return
        }
        Log.i(TAG_UI, "[link] auto-connect at startup")
        val want = MainActivity.namePrefix
        when {
            want != null -> {
                Log.i(
                    TAG_UI,
                    "[link] auto-connect restricted to '$want'" +
                        if (MainActivity.adopt) " — ADOPTING it as home" else "",
                )
                if (MainActivity.adopt) Settings.setHomeRadio(link.context, want)
                link.connect(namePrefix = want, pin = pinOverride)
            }
            pinOverride != null -> link.connect(pin = pinOverride)
            else -> link.connect()
        }
    }

    // THE FAKE MESH, LOADED ONCE, AT THE SOURCE.
    //
    // --ez sim true used to fabricate eleven already-placed motes, which
    // exercised the renderer and skipped every stage anybody has asked a
    // question about since: ranking, clustering, filtering, favourites, the
    // tabletop cap. This puts 350 peers into the same table an advert fills, so
    // all of it runs, on a machine with no radio.
    LaunchedEffect(MainActivity.simulate) {
        if (!MainActivity.simulate) return@LaunchedEffect
        val at = MainActivity.homeOverride ?: SIM_HOME
        link.loadSimulated(
            FakeMesh.peers(at.lat ?: 0.0, at.lon ?: 0.0, System.currentTimeMillis() / 1000),
        )
        // A SIMULATED RADIO HAS PARAMETERS TOO. Without them the rack shows
        // ghosts and the region-compliance check can never run on a bench —
        // and that check is exactly the kind of thing that should be provable
        // without flying somewhere. US/CA is the seed, so `--es home` with
        // European or Japanese coordinates exercises the mismatch.
        Regions.ALL.firstOrNull { it.id == "us_canada" }?.let { link.radio.observe(it.params()) }
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
        // THE ALERTS PANEL. Everything the app has to say that does not stop it
        // working: a full contact store, a region mismatch, a sweep's result.
        // Off by default and opened from SETUP > APP, because an alert that
        // interrupts is an alarm, and almost none of these are alarms.
        //
        // On the LEFT, mirroring the radio log on the right, so neither ever
        // sits in front of the horizon.
        if (Settings.alerts(LocalContext.current)) {
            Subspace {
                SpatialPanel(
                    SubspaceModifier
                        .width(520.dp).height(560.dp)
                        .offset(x = (-620).dp, z = (-140).dp)
                        .rotate(androidx.xr.runtime.math.Vector3(0f, 1f, 0f), 34f),
                ) {
                    AlertsPanel()
                }
            }
        }
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
    ctx: android.content.Context,
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
                unnamedWord = ctx.getString(R.string.w_unnamed),
                publicMark = ctx.getString(R.string.w_public),
            ),
            lit = voice.isOn(c.threadId),
        )
    } + makeRows(ctx, link, pending) + deleteRows(ctx, link, pending)
}

/**
 * A DELETE ROW PER CHANNEL WORTH DELETING.
 *
 * MeshCore's companion protocol has no CLEAR_CHANNEL opcode and the phone app
 * concluded there was no delete — it overwrites a slot with the Public name and
 * key instead, leaving a slot that works and lies about what it is. Measured on
 * the operator's radio 2026-08-22: writing an EMPTY name with an all-zero key
 * makes the firmware report `<empty slot>`, and it stays empty across a
 * reconnect. So this app deletes properly. See MeshLink.clearChannel.
 *
 * NOT OFFERED FOR THE PUBLIC BAND. Deleting Public takes the wearer off the
 * channel everybody else is on, and unlike a private key it can be restored
 * from a constant — so the row would be an invitation to break something for no
 * reason. Nor for a channel known only from traffic: there is no slot to clear.
 */
private fun deleteRows(
    ctx: android.content.Context,
    link: MeshLink,
    pending: ChanAction?,
): List<com.iotj.meshmore.xr.spatial.Stack.Row> {
    if (pending != null) return emptyList()
    if (link.status.value.state != SessionState.READY) return emptyList()
    return link.channels()
        .filter { !it.publicKey && it.idx >= 0 }
        .map { c ->
            com.iotj.meshmore.xr.spatial.Stack.Row(
                id = ROW_DEL + c.idx,
                label = ctx.getString(
                    R.string.c_delete,
                    com.iotj.meshmore.xr.spatial.TypeTier.clip(c.name.uppercase(), 12),
                ),
                lit = false,
            )
        }
}

/** A channel write the wearer has started but not yet confirmed. */
private sealed interface ChanAction {
    /** A rolled name, waiting for the second pinch that writes it. */
    data class New(val name: String) : ChanAction
    /** The public channel, waiting for the second pinch. */
    data object Public : ChanAction

    /**
     * A tag somebody else gave us, heard and waiting to be confirmed.
     *
     * THE LITERAL STRING IS CARRIED, not the words that were said. The key is
     * SHA-256 over these exact bytes, so what the wearer confirms has to be
     * what gets hashed — including its case, which dictation decides and this
     * app must not quietly change.
     */
    data class Join(val tag: String) : ChanAction

    /**
     * A channel about to be deleted, waiting for the second pinch.
     *
     * Carries the SLOT as well as the name, because the name is decoration and
     * the slot is what gets written. Two channels may share a name; only one
     * occupies slot 2.
     */
    data class Delete(val idx: Int, val name: String) : ChanAction
}

private const val ROW_NEW = "+new"
private const val ROW_ROLL = "+roll"
private const val ROW_PUBLIC = "+public"
private const val ROW_SAYTAG = "+saytag"
private const val ROW_JOINTAG = "+jointag"
private const val ROW_TYPETAG = "+typetag"
private const val ROW_DEL = "+del:"

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
    ctx: android.content.Context,
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
            row(ROW_NEW, ctx.getString(R.string.c_make, Channels.tagFor(pending.name)), lit = true),
            row(ROW_ROLL, ctx.getString(R.string.c_reroll)),
        )
        ChanAction.Public -> listOf(
            row(ROW_PUBLIC, ctx.getString(R.string.c_join_arm), lit = true),
        )
        // THE TAG IS SHOWN EXACTLY AS IT WILL BE HASHED, for the same reason
        // the rolled tag is shown in lowercase: "#Soak" and "#soak" are two
        // channels that look like one, and this is the wearer's only chance to
        // see that dictation heard a capital.
        is ChanAction.Join -> listOf(
            row(ROW_JOINTAG, ctx.getString(R.string.c_join_tag_arm, pending.tag), lit = true),
            row(ROW_SAYTAG, ctx.getString(R.string.c_say_again)),
        )
        is ChanAction.Delete -> listOf(
            row(ROW_DEL + pending.idx, ctx.getString(R.string.c_delete_arm), lit = true),
        )
        null -> listOfNotNull(
            row(ROW_NEW, ctx.getString(R.string.c_new)),
            // JOINING IS THE OTHER HALF OF MAKING, and the half this app did
            // not have. A rolled channel has exactly one member until somebody
            // else can type its tag; a wearer who is TOLD a tag had no way to
            // use it at all.
            row(ROW_SAYTAG, ctx.getString(R.string.c_join_tag)),
            // TYPING IS THE ONE THAT WORKS. Dictation is kept because it is
            // faster when it lands, but the log of four failed attempts at
            // "#soaktest" is why this row exists — see TagPad.
            row(ROW_TYPETAG, ctx.getString(R.string.c_type_tag)),
            // Offered only when the radio is NOT already on the public band.
            // On a stock radio slot 0 is Public and this row would be an
            // invitation to spend a slot on a channel you are already in.
            if (link.channels().none { it.publicKey }) {
                row(ROW_PUBLIC, ctx.getString(R.string.c_join_public))
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
/**
 * S · DELIVERY — what became of the messages this app sent.
 *
 * The numbers come from [TxLog], which keeps one record per send; this only
 * puts them on rows and lets the row builder measure them against the plate,
 * because the log format they are also printed in is thirty-five columns wide
 * and would be clipped exactly where the figures are.
 *
 * Read-only apart from CLEAR. A wearer cannot repair a mesh from a settings
 * bay, but they can find out whether the thing they just sent arrived, and
 * whether that is normal — which is the question this surface exists for.
 */
/**
 * A delivery row's name, in the wearer's language.
 *
 * [TxLog] deliberately knows no words — it is pure so it can be measured on a
 * desktop JVM — so the joining happens here, where a Context exists and where
 * the parity test can see every string it uses.
 */
private fun txName(ctx: android.content.Context, n: TxLog.Name): String = when (n) {
    TxLog.Name.Sent -> ctx.getString(R.string.tx_sent)
    TxLog.Name.Refused -> ctx.getString(R.string.tx_refused)
    TxLog.Name.Acked -> ctx.getString(R.string.tx_acked)
    TxLog.Name.InFlight -> ctx.getString(R.string.tx_inflight)
    TxLog.Name.RoundTrip -> ctx.getString(R.string.tx_rtt)
    TxLog.Name.Slowest -> ctx.getString(R.string.tx_worst)
    TxLog.Name.Direct -> ctx.getString(R.string.tx_direct)
    TxLog.Name.Flood -> ctx.getString(R.string.tx_flood)
    is TxLog.Name.Hops -> ctx.getString(R.string.tx_hops, n.n)
    is TxLog.Name.Size -> ctx.getString(R.string.tx_size, n.lo, n.hi)
    is TxLog.Name.Over -> ctx.getString(R.string.tx_size_over, n.lo)
}

private fun txRows(
    ctx: android.content.Context,
    link: MeshLink,
): List<com.iotj.meshmore.xr.spatial.Stack.Row> {
    val pairs = TxLog.rows(link.txAttempts())
    if (pairs.isEmpty()) {
        return listOf(
            com.iotj.meshmore.xr.spatial.Stack.Row(
                id = "tx", label = ctx.getString(R.string.tx_none), lit = false,
            ),
        )
    }
    return pairs.map { r ->
        com.iotj.meshmore.xr.spatial.Stack.Row(
            id = "tx",
            label = com.iotj.meshmore.xr.spatial.radioRow(
                txName(ctx, r.name),
                // The two timings are bare numbers so the unit can be a
                // resource; everything else already carries its own.
                if (r.name == TxLog.Name.RoundTrip || r.name == TxLog.Name.Slowest) {
                    ctx.getString(R.string.tx_ms, r.value.toLongOrNull() ?: 0L)
                } else {
                    r.value
                },
                null,
            ),
            lit = false,
        )
    } + com.iotj.meshmore.xr.spatial.Stack.Row(
        id = "TXCLEAR", label = ctx.getString(R.string.r_txclear), lit = false,
    )
}

private fun aboutRows(ctx: android.content.Context, link: MeshLink): List<com.iotj.meshmore.xr.spatial.Stack.Row> {
    fun row(text: String) = com.iotj.meshmore.xr.spatial.Stack.Row(
        id = "about", label = text, lit = false,
    )
    val radio = link.status.value.deviceName?.uppercase()
        ?: ctx.getString(R.string.ab_no_radio)
    // NAME AND VALUE, THROUGH THE BUILDER THAT MEASURES. These were three
    // hand-spaced strings, and in Japanese two of them were a cell over the
    // plate and lost their last character to the clamp:
    //
    //   MESHMORE XR  0.3.0-debug.70   ->   MESHMORE XR  0.3.0-debug.…
    //
    // Which is the build number — the one thing on this surface a person is
    // reading it to find out. The Japanese plate is 26 cells against the
    // Latin 28, so a row that exactly fits in English is over by one there.
    //
    // The labels give way rather than the values: this bay's title already
    // says MESHMORE XR, so the row does not need to, and `radioRow` clips
    // whatever is left over against the locale's own template instead of a
    // constant somebody has to remember to update.
    return listOf(
        row(com.iotj.meshmore.xr.spatial.radioRow(
            ctx.getString(R.string.ab_version), BuildConfig.VERSION_NAME, null,
        )),
        row(com.iotj.meshmore.xr.spatial.radioRow(
            ctx.getString(R.string.ab_radio), radio, null,
        )),
        row(com.iotj.meshmore.xr.spatial.radioRow(
            ctx.getString(R.string.ab_firmware), MeshcoreConstants.FIRMWARE_PIN_TAG, null,
        )),
        // THE THREE THAT MATTER, in the order they matter. Driving first: it is
        // the only one where the consequence is not recoverable.
        row(ctx.getString(R.string.s_driving)),
        row(ctx.getString(R.string.s_room)),
        row(ctx.getString(R.string.s_mic)),
        // THE REGION DISCLAIMER LIVES HERE, and here is a surface a wearer can
        // actually reach — which is the whole argument for ABOUT existing. The
        // region list itself only has room for a 32-character footer, and "not
        // legal advice" without the part explaining that Japanese law is about
        // the HARDWARE would be the misleading half of a true statement.
    ) + ctx.resources.getStringArray(R.array.region_disclaimer).map { row(it) }
}

/**
 * WHO MAY ASK THIS RADIO WHAT IT KNOWS — three rows, three levels each.
 *
 * `TelemetryPerms` has been complete and unit-tested since it was written, and
 * `MeshLink` has read and written the byte all along. The only way to change it
 * was a launch flag, which means a privacy setting the app implements and
 * honours could not be changed by the person it is about.
 *
 * THREE ROWS AND NOT ONE SWITCH, which is the file's own argument and worth
 * repeating where the control is: battery level is a curiosity, environment is
 * a weather station, and LOCATION is where the wearer is standing. Collapsing
 * them into "share telemetry" would hide the one that matters behind the two
 * that do not.
 *
 * Each row CYCLES rather than toggling, because the middle level is the useful
 * default and a two-state control cannot reach it: DENY, then CONTACTS (only
 * people already in the radio's contact list, per-contact flags), then ANYONE.
 */
/**
 * THE LANGUAGES, AS A LIST YOU CHOOSE FROM.
 *
 * This began as a toggle, which was wrong twice over: a wearer cannot see what
 * they are toggling BETWEEN — with two languages a switch is guessable, with
 * three it is a lottery — and a language change rebuilds the whole scene, which
 * is far too abrupt to hang off a control that can be brushed by accident.
 *
 * SYSTEM DEFAULT is a first-class choice and not an absence. It is what an
 * unmodified install is in, it is what a Japanese wearer's headset already
 * gives them, and without it a tester who switched to English for an afternoon
 * has no way back to "whatever the device says" — only to a language they have
 * now pinned by hand.
 *
 * Endonyms, deliberately: 日本語 says what it is to the person who needs it,
 * where "JAPANESE" is only useful to somebody who already reads English.
 */
private fun langRows(
    ctx: android.content.Context,
): List<com.iotj.meshmore.xr.spatial.Stack.Row> {
    val current = runCatching {
        ctx.getSystemService(android.app.LocaleManager::class.java)
            ?.applicationLocales?.takeIf { !it.isEmpty }?.get(0)?.language
    }.getOrNull()
    fun row(id: String, label: String, on: Boolean) =
        com.iotj.meshmore.xr.spatial.Stack.Row(id = id, label = label, lit = on)
    return listOf(
        row("LANG_sys", ctx.getString(R.string.lang_system), current == null),
        row("LANG_en", "ENGLISH", current == "en"),
        row("LANG_ja", "日本語", current == "ja"),
    )
}

/**
 * A name, a gutter, and a value, with the gutter measured in CELLS.
 *
 * `String.format("%-12s")` pads to a count of code units, which is the width of
 * the string only while the string is Latin. Kanji are two cells each, so a
 * padded Japanese column lands wherever the character count happens to put it.
 */
private fun padCells(name: String, value: String, column: Int): String {
    val used = com.iotj.meshmore.xr.spatial.TypeTier.displayCells(name)
    return name + " ".repeat((column - used).coerceAtLeast(1)) + value
}

/**
 * WHO SAID IT AND WHEN, on one line, in every list that shows messages.
 *
 * The column is shared by the inbox, the thread, the palm reel and the crown,
 * and it was `"%-14s %s"` in all six places — six copies of a number and six
 * copies of the same wrong ruler. A sender's name is the one string in this
 * app that is arbitrary user text in an arbitrary script, so it is exactly
 * where code-unit padding goes wrong, and it goes wrong in the ENGLISH build
 * too: a node called 中継局 is three units and six cells, and the timestamp
 * beside it landed eight cells left of where every other row put it.
 */
private fun whoLine(name: String, rest: String) = padCells(name, rest, column = WHO_COLUMN)

/** One past the 14-cell name budget every caller clips to. */
private const val WHO_COLUMN = 15

/**
 * S · MESH WEATHER — what other people's radios say the world is like.
 *
 * THE POINT OF THIS SURFACE IS THAT IT EXISTS. The app has been able to ask a
 * peer for telemetry, decode the answer and store it for weeks; nothing has
 * ever displayed a byte of it. A wearer who used the node menu's TELEM action
 * heard "asked NAME" and then, whatever came back, saw nothing at all. That is
 * the whole of why telemetry felt impossible to get — not airtime, not policy,
 * an absent readout.
 *
 * Sorted warmest first, which is what SNS does and is right for the same
 * reason: a list of temperatures has no natural order, and the extremes are
 * the only rows anybody looks for.
 */
private fun wxRows(
    ctx: android.content.Context,
    link: MeshLink,
    plan: TelemetryAsk.Plan?,
    nowEpochSec: Long,
): List<com.iotj.meshmore.xr.spatial.Stack.Row> {
    fun plain(text: String) =
        com.iotj.meshmore.xr.spatial.Stack.Row(id = "wx", label = text, lit = false)

    val readings = link.mesh.value
        .mapNotNull { p -> p.telemetry?.let { p to it } }
        .sortedByDescending { it.second.tempC ?: -1000.0 }

    val rows = mutableListOf<com.iotj.meshmore.xr.spatial.Stack.Row>()

    // THE ASK IS THE FIRST ROW AND IT SAYS WHAT IT WILL COST. Same rule the
    // contact sweep follows: a control that reaches other people's hardware
    // names the number of them before it does it.
    val n = plan?.askCount ?: 0
    rows += com.iotj.meshmore.xr.spatial.Stack.Row(
        id = if (n > 0) "WXASK" else "wx",
        label = if (n > 0) ctx.getString(R.string.r_wxask, n)
                else ctx.getString(R.string.r_wxnone),
        lit = n > 0,
    )

    val temps = readings.mapNotNull { it.second.tempC }
    if (temps.isNotEmpty()) {
        rows += plain(
            com.iotj.meshmore.xr.spatial.radioRow(
                ctx.getString(R.string.wx_summary, temps.size),
                "%.0f / %.0f / %.0f°".format(temps.min(), temps.average(), temps.max()),
                null,
            ),
        )
    }

    if (readings.isEmpty()) {
        rows += plain(ctx.getString(R.string.wx_empty))
        // AND WHY. "No readings" with three hundred contacts in the store is
        // the sentence that made this feel broken; this says where they went.
        //
        // Built from resources rather than from Plan.census(), which is
        // English for the log. A wearer reads this one.
        plan?.let { pl ->
            rows += plain(ctx.getString(R.string.wx_all, pl.considered))
            pl.skipped.forEach { (why, n) ->
                if (n <= 0) return@forEach
                rows += plain(
                    when (why) {
                        TelemetryAsk.Skip.NO_FULL_KEY -> ctx.getString(R.string.wx_no_key, n)
                        TelemetryAsk.Skip.TOO_FAR_IN_HOPS ->
                            ctx.getString(R.string.wx_hops, n, TelemetryAsk.MAX_HOPS)
                        TelemetryAsk.Skip.TOO_FAR_IN_KM ->
                            ctx.getString(R.string.wx_km, n, TelemetryAsk.MAX_KM.toInt())
                        TelemetryAsk.Skip.UNROUTED_AND_STALE ->
                            ctx.getString(R.string.wx_unrouted, n)
                        TelemetryAsk.Skip.OVER_FLOOD_BUDGET ->
                            ctx.getString(R.string.wx_floodcap, n)
                        TelemetryAsk.Skip.ALREADY_FRESH -> ctx.getString(R.string.wx_fresh, n)
                        TelemetryAsk.Skip.COOLING_DOWN -> ctx.getString(R.string.wx_cool, n)
                        TelemetryAsk.Skip.OVER_BUDGET -> ctx.getString(R.string.wx_budget, n)
                    },
                )
            }
            rows += plain(ctx.getString(R.string.wx_to_ask, pl.askCount))
        }
        return rows
    }

    readings.forEach { (p, t) ->
        val age = (nowEpochSec - t.atEpochSec).coerceAtLeast(0)
        val ageWord = if (age < 3600) ctx.getString(R.string.ago_min_short, age / 60)
                      else ctx.getString(R.string.ago_hr_short, age / 3600)
        rows += plain(
            com.iotj.meshmore.xr.spatial.radioRow(
                com.iotj.meshmore.xr.spatial.TypeTier.clip(p.name.uppercase(), 12),
                "$t  $ageWord",
                null,
            ),
        )
    }
    return rows
}

/**
 * The radio link's state in the wearer's language.
 *
 * Every other surface that reports the link already says it in words — the
 * notice band has link_scan, link_handshake and the rest. Only the APP bay's
 * title took the shortcut of printing the enum, and it was the one place the
 * Japanese build showed an English identifier.
 */
private fun linkWord(ctx: android.content.Context, link: MeshLink): String =
    ctx.getString(
        when (link.status.value.state) {
            SessionState.READY -> R.string.ls_ready
            SessionState.HANDSHAKING -> R.string.ls_shake
            SessionState.CONNECTING -> R.string.ls_shake
            else -> if (link.status.value.scanning) R.string.ls_scan else R.string.ls_off
        },
    )

private fun telemetryRows(
    ctx: android.content.Context,
    link: MeshLink,
): List<com.iotj.meshmore.xr.spatial.Stack.Row> {
    val p = link.telemetryPermissions()
    return com.iotj.meshmore.xr.spatial.TelemetryPerms.CLASSES.mapIndexed { i, cls ->
        val level = p.level(i)
        com.iotj.meshmore.xr.spatial.Stack.Row(
            id = "TELEM$i",
            // PADDED IN CELLS. "%-12s" counts code units, so 電池 — two units
            // and four cells — was padded as though it were ten cells narrower
            // than it draws, putting the value two cells past the column the
            // English rows use. It reads straight today only because all three
            // Japanese names happen to be two kanji; the first three-kanji one
            // would have stepped out of the column with nothing to explain it.
            label = padCells(
                column = 13,
                name = ctx.getString(
                    when (i) {
                        0 -> R.string.telem_battery
                        1 -> R.string.telem_location
                        else -> R.string.telem_environment
                    },
                ),
                value = ctx.getString(
                    when (level) {
                        com.iotj.meshmore.xr.spatial.TelemetryPerms.DENY -> R.string.telem_deny
                        com.iotj.meshmore.xr.spatial.TelemetryPerms.ALLOW_FLAGS -> R.string.telem_contacts
                        else -> R.string.telem_anyone
                    },
                ),
            ),
            // Lit means "somebody other than me can have this", which is the
            // state worth seeing at a glance rather than the state that is safe.
            lit = level != com.iotj.meshmore.xr.spatial.TelemetryPerms.DENY,
        )
    }
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
private fun chanFooter(ctx: android.content.Context, pending: ChanAction?): String = when (pending) {
    is ChanAction.New -> ctx.getString(R.string.f_chan_new)
    ChanAction.Public -> ctx.getString(R.string.f_chan_public)
    // A DIFFERENT WARNING FROM THE OTHER TWO. Rolling a name is told that the
    // key is only as good as the words; joining somebody else's is told to
    // check the characters, because the failure here is not weakness, it is
    // landing on a channel nobody else is on and having nothing say so.
    is ChanAction.Join -> ctx.getString(R.string.f_chan_join)
    is ChanAction.Delete -> ctx.getString(R.string.f_chan_del)
    null -> ctx.getString(R.string.f_chan)
}

/**
 * The channel band's contents — the same source the CHANNELS bay uses, so a
 * channel cannot appear in one and not the other.
 */
private fun channelBands(
    ctx: android.content.Context,
    link: MeshLink,
    voice: VoicePrefs,
): List<com.iotj.meshmore.xr.spatial.Bands.Band> =
    // WITHOUT THE ACTIONS. The bay's rows now end in things to DO, and a band
    // is a place traffic arrives — "+ NEW CHANNEL" hanging in the horizon over
    // the node lanes would be a control in the one part of the scene that has
    // none.
    channelRows(ctx, link, voice).filterNot { it.id.startsWith("+") }.map { r ->
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
/** How far out the radio's clock is, said the way a person would say it. */
private fun clockWord(ctx: android.content.Context, skew: Long): String {
    val a = kotlin.math.abs(skew)
    if (a < 120) return ctx.getString(R.string.rr_clock_ok)
    val amount = when {
        a >= 86400 -> "%.1fD".format(a / 86400.0)
        a >= 3600 -> "%.1fH".format(a / 3600.0)
        else -> "%dM".format(a / 60)
    }
    return ctx.getString(
        if (skew < 0) R.string.rr_clock_off else R.string.rr_clock_ahead, amount,
    )
}

private fun radioRows(
    ctx: android.content.Context,
    cfg: RadioConfig,
    /** Radio clock minus headset clock, for the row that reports it. */
    skewSec: Long = 0L,
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
                "NONE", ctx.getString(R.string.rr_unread), false,
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
        row(
            "COMMIT", ctx.getString(R.string.rr_commit),
            ctx.getString(if (cfg.dirty()) R.string.rr_commit_ready else R.string.rr_commit_none),
            null, cfg.dirty(),
        ),
        row(
            "REVERT", ctx.getString(R.string.rr_revert),
            ctx.getString(if (cfg.dirty()) R.string.rr_revert_pending else R.string.rr_revert_clean),
            null,
        ),
        // SAY YOU ARE HERE. Both of these existed only as buttons on the 2D
        // debug panel and a launch flag — which is to say they existed for
        // anyone holding a laptop, and for nobody wearing the glasses.
        //
        // A ZERO-HOP advert is heard by direct neighbours and stops there; it
        // costs one transmission and is the right way to say "I am in this
        // room" to a node you are standing next to. A FLOOD advert is repeated
        // by every repeater that hears it, across the whole mesh — that is
        // other people's airtime, and on a 350-node mesh it is a lot of it, so
        // it is armed like the destructive controls are.
        row(
            "ADVERT", ctx.getString(R.string.rr_advert),
            ctx.getString(R.string.rr_advert_sub), null,
        ),
        row(
            "FLOOD", ctx.getString(R.string.rr_flood),
            ctx.getString(R.string.rr_flood_sub), null,
        ),
        // The radio's own store, from the surface that is about the radio.
        row(
            "RESCAN", ctx.getString(R.string.rr_rescan),
            ctx.getString(R.string.rr_rescan_sub), null,
        ),
        // THE RADIO'S OWN CLOCK, and how far out it is.
        //
        // Every contact in the store carries a last-heard stamp written by
        // this clock, and the ring ages the whole mesh against the headset's.
        // The bench radio was found 16.8 DAYS behind — it believed it was the
        // third of August on the twentieth — which nothing could have noticed
        // because nothing had ever asked. Lit when it is worth acting on.
        row(
            "CLOCK", ctx.getString(R.string.rr_clock), clockWord(ctx, skewSec),
            null, kotlin.math.abs(skewSec) >= 120,
        ),
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
    ctx: android.content.Context,
    here: com.iotj.meshmore.xr.spatial.MeshNodes.Here,
    live: RadioConfig.Params?,
): List<com.iotj.meshmore.xr.spatial.Stack.Row> {
    val rows = mutableListOf<com.iotj.meshmore.xr.spatial.Stack.Row>()
    val suggested = Regions.suggest(here.lat, here.lon)
    if (suggested != null) {
        rows += com.iotj.meshmore.xr.spatial.Stack.Row(
            id = "R:" + suggested.id,
            label = com.iotj.meshmore.xr.spatial.radioRow(
                ctx.getString(R.string.d_here), suggested.label, null,
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
/**
 * The DEVICE bay's three ACTIONS, as opposed to its parameters.
 *
 * Kept out of [onRadioRow] on purpose: that function stages values to be
 * committed later, and these three do something the moment they are picked.
 * Mixing "type a number, commit it in a minute" with "transmit now" in one
 * table is how a wearer ends up flooding a mesh they meant to tune.
 */
private fun onRadioAction(
    ctx: android.content.Context,
    id: String,
    link: MeshLink,
    armed: androidx.compose.runtime.MutableState<Pair<String, Long>?>,
    nowMs: Long,
    say: (String) -> Unit,
): Boolean = when (id) {
    "ADVERT" -> {
        link.announce(false)
        say(ctx.getString(R.string.n_advert_sent))
        true
    }
    "FLOOD" -> {
        if (armed.value?.first != "FLOOD") {
            armed.value = "FLOOD" to nowMs
            say(ctx.getString(R.string.n_flood_arm))
        } else {
            armed.value = null
            link.announce(true)
            say(ctx.getString(R.string.n_flood_sent))
        }
        true
    }
    "RESCAN" -> {
        link.connect()
        say(ctx.getString(R.string.n_rescan))
        true
    }
    // ARMED, because it writes to hardware the operator owns and the app does
    // not. A clock is right until somebody decides it is not.
    "CLOCK" -> {
        if (armed.value?.first != "CLOCK") {
            armed.value = "CLOCK" to nowMs
            say(ctx.getString(R.string.n_clock_arm))
        } else {
            armed.value = null
            if (link.syncClock()) say(ctx.getString(R.string.n_clock_set))
            else say(ctx.getString(R.string.n_radio_not_ready))
        }
        true
    }
    else -> false
}

private fun onRadioRow(
    ctx: android.content.Context,
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
        "FREQ" -> say(ctx.getString(R.string.n_freq_preset))
        "COMMIT" -> {
            if (!cfg.dirty()) { say(ctx.getString(R.string.n_nothing_commit)); return }
            if (armed.value?.first != "COMMIT") {
                armed.value = "COMMIT" to nowMs
                say(ctx.getString(R.string.n_commit_arm))
                return
            }
            armed.value = null
            val p = cfg.commit()
            say(if (p != null) ctx.getString(R.string.n_written, p.pretty().take(20)) else ctx.getString(R.string.n_commit_failed))
        }
        "REVERT" -> {
            armed.value = null
            cfg.discard()
            say(ctx.getString(R.string.n_discarded))
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
 * Where a simulated mesh is centred when no `--es home` was given.
 *
 * Portland, because that is the mesh this app is developed against and a fake
 * dataset should sit where the real one does — a simulation an ocean away from
 * the operator's own contacts is one whose distances mean nothing to whoever is
 * looking at it.
 *
 * IT ALSO SUPPLIES THE FIX. Without a position there is nothing to measure a
 * bearing from and every simulated peer would be unplaceable, which is a real
 * failure mode (see the status band's NO FIX) but not the one a simulation is
 * for. `--ez sim true --es home "lat,lon"` moves both the origin and the peers.
 */
private val SIM_HOME = MeshNodes.Here(45.5152, -122.6784)

/**
 * How many orbs a TABLETOP draws, against [MeshNodes.MAX_MOTES]' two dozen.
 *
 * The table is 32.4 degrees across and cannot grow — see the frame's note. At
 * 24 that is 1.3 degrees a node, which is the pile that was reported twice; at
 * 12 it is 2.7, wider than the 2.0 degree floor a thing has to clear to be
 * reached for. The cap is the only lever the geometry leaves.
 */
private const val TABLETOP_MOTES = 12

/**
 * How far above its mote a node's action menu opens. High enough that the ring
 * of verbs clears the FOCUS card that opens at the same moment, low enough
 * that both read as one answer to one pinch.
 */
private const val NODE_MENU_LIFT = 0.06f

/**
 * THE APP'S ONE COMPOSE FACE — M PLUS 1 Code, the same asset TextRun bakes
 * into every spatial panel (typography plan §3: body/CJK in one face, and
 * "never mix faces inside a run"). meshMono(LocalContext.current) was the stand-in, and
 * a different monospace on the flat panels than in the room made the two feel
 * like different products. Cached: Compose calls this per composition and
 * createFromAsset is a disk read.
 */
private var meshMonoCache: FontFamily? = null
private fun meshMono(ctx: android.content.Context): FontFamily =
    meshMonoCache ?: FontFamily(
        runCatching {
            android.graphics.Typeface.createFromAsset(
                ctx.assets, "fonts/MPLUS1Code-Regular.ttf",
            )
        }.getOrDefault(android.graphics.Typeface.MONOSPACE),
    ).also { meshMonoCache = it }

/**
 * How far beside its mote the menu stands. Wider than the menu's own
 * distance-scaled spread (0.163 at 2.5 m) plus a label, so no spoke reaches
 * back over the FOCUS card it opened next to.
 */
private const val NODE_MENU_SIDE = 0.55f

/** The no-radio card's own patience: three quiet rescans, half a minute apart. */
/**
 * How long the notice stands before the scene is rebuilt in the new language.
 * Long enough to read one short sentence; short enough that nobody wonders
 * whether the pinch registered.
 */
/**
 * The distance past which a contact is a candidate for collection.
 *
 * 100 km is not a guess about radio range — LoRa does far more than that from
 * a hilltop — it is a guess about USEFULNESS: a node that far away is not one
 * you are about to walk over to, and if it adverts again it comes straight
 * back. The number is deliberately generous, because the cost of collecting
 * too little is another sweep and the cost of collecting too much is a contact
 * the operator wanted.
 */
/**
 * How long a soak waits after its last packet before it calls a message lost.
 *
 * The radio publishes its own estimate — 2.2 s on a known route, 8 s flooded —
 * and nothing measured on this mesh has come back past 2.4 s. Twenty seconds
 * is therefore not a guess, it is a wide margin around the worst thing ever
 * observed, chosen so that an unanswered message means the mesh dropped it and
 * not that the report was written too early.
 */
private const val SOAK_SETTLE_MS = 20_000L

/**
 * THE SOAK ITSELF, IN ONE PLACE.
 *
 * Ten full-length packets six seconds apart at one node, then a wait long
 * enough that silence means the mesh dropped something rather than that the
 * report was written early. Extracted from the crown's action because a
 * measurement you can only start by pinching a menu is a measurement you
 * cannot repeat, and repeating it is the entire point — the loss being chased
 * is roughly one in ten, which no single run can resolve.
 *
 * Returns the finished ledger so a caller can report it however it likes.
 */
private suspend fun runSoakAt(
    ctx: android.content.Context,
    link: MeshLink,
    peerKey: String,
    onChannel: Boolean = false,
    say: (String) -> Unit = {},
): List<TxLog.Attempt> {
    val fmt = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US)
    val before = link.delivery.value
    // THE RUN MEASURES ITSELF. The ledger is a rolling window over everything
    // the app has ever sent, and a soak whose report includes this morning's
    // messages is not a measurement of anything.
    link.clearTxLog()
    var accepted = 0
    // COUNTED, NOT ASSUMED. The run can stop early at a refusal, and a report
    // that says ten when six left is a reliability figure computed from a
    // number nobody measured.
    var attempted = 0
    var why: String? = null
    for (n in 1..MiniSoak.COUNT) {
        val text = MiniSoak.message(fmt.format(java.util.Date()), n, MiniSoak.sizeFor(n))
        // TWO DIFFERENT TRANSMITTERS. A direct message is addressed to a key
        // and is acknowledged; a channel message goes to a slot and is NOT —
        // MeshCore group traffic carries no ack, so a channel soak can only
        // report what the radio accepted. What ARRIVED has to be read on the
        // receiving radio, which is exactly how the direct soak was verified.
        val res = if (onChannel) {
            link.slotOf(peerKey)?.let { link.sendToChannel(it, text) }
                ?: MeshLink.Sent.Refused("NO SUCH CHANNEL")
        } else {
            link.sendTo(peerKey, text)
        }
        attempted++
        link.noteAttempt(res is MeshLink.Sent.Ok)
        if (res is MeshLink.Sent.Ok) accepted++
        else if (why == null) why = (res as? MeshLink.Sent.Refused)?.why ?: res.toString()
        Log.i(
            TAG_UI,
            "[minisoak] %02d/%d %dB (%d chars) %s".format(
                n, MiniSoak.COUNT, MiniSoak.bytes(text), text.length,
                if (res is MeshLink.Sent.Ok) "accepted" else "REFUSED $why",
            ),
        )
        // A REFUSAL DOES NOT HEAL. The reasons sendTo can refuse are the
        // allow-list and a radio that is not there; neither changes in six
        // seconds, so the other nine attempts would only spend a minute
        // arriving at the same sentence.
        if (res is MeshLink.Sent.Refused) {
            Log.w(TAG_UI, "[minisoak] stopped at $n: $why")
            break
        }
        if (n < MiniSoak.COUNT) kotlinx.coroutines.delay(MiniSoak.EVERY_S * 1000L)
    }
    // LONG ENOUGH THAT SILENCE MEANS SOMETHING. The radio estimates 2.2 s
    // direct and 8 s flooded, and nothing measured here has ever come back past
    // 2.4 s — so twenty seconds is a generous multiple, and the sweep at the
    // end of it turns "no ack yet" into "no ack", which is what is counted.
    kotlinx.coroutines.delay(SOAK_SETTLE_MS)
    // NO OVERRIDE. Each message now carries the deadline the radio quoted for
    // it — at most 15.4 s of the 20 s already waited above — so by here every
    // one of them has either been acknowledged or run out of time on its own
    // terms, and a flat window would only overrule that with a worse number.
    link.sweepLost()
    val d = link.delivery.value
    val acked = (d.acked - before.acked).coerceAtLeast(0)
    val ledger = link.txAttempts()
    Log.i(
        TAG_UI,
        "[minisoak] DONE " + MiniSoak.report(attempted, accepted, acked, d.meanLatencyMs ?: 0L),
    )
    // AND WHERE THEY WENT. The line above is the count this app always had;
    // these are the slices that say which repair the loss is asking for.
    TxLog.report(ledger).forEach { Log.i(TAG_UI, "[minisoak] $it") }
    Alerts.info("SOAK", TxLog.headline(ledger))
    say(ctx.getString(R.string.n_soak_done, acked, MiniSoak.COUNT))
    return ledger
}


private const val GC_FAR_KM = 100.0

/** How many contacts a sweep would take right now, for the row's own label. */
/**
 * The set a filter-driven sweep would act on, computed the same way the panel
 * computes what it is showing. One function, so the number on the button and
 * the contacts that go cannot drift apart.
 */
private fun matchedForSweep(
    link: MeshLink,
    mesh: List<MeshNodes.Peer>,
    q: Search.Query,
    tags: NodeTags,
    hereSource: HereSource,
): List<MeshNodes.Peer> {
    val from = hereSource.resolve(link.here.value, MainActivity.homeOverride)
    val nowS = System.currentTimeMillis() / 1000
    return Search.apply(
        mesh, q,
        isFavourite = { it.favourite || tags.isFavourite(it.fullKey ?: it.key) },
        tagsOf = { tags.tagsFor(it.fullKey ?: it.key) },
        distanceKm = { p ->
            val la = p.lat
            val lo = p.lon
            if (!from.known || la == null || lo == null ||
                (kotlin.math.abs(la) < 1e-7 && kotlin.math.abs(lo) < 1e-7)
            ) {
                null
            } else {
                MeshNodes.haversineKm(from.lat!!, from.lon!!, la, lo)
            }
        },
        ageHours = { p ->
            if (p.lastSeenEpochSec <= 0L) null
            else (nowS - p.lastSeenEpochSec).coerceAtLeast(0L) / 3600.0
        },
    )
}

private fun gcCount(
    link: MeshLink,
    here: MeshNodes.Here,
    isFavourite: (String) -> Boolean,
): Int = link.farContacts(here, GC_FAR_KM, isFavourite).size

private const val LANG_SETTLE_MS = 1_200L
private const val NO_RADIO_AUTO_TRIES = 3
private const val NO_RADIO_RETRY_MS = 30_000L

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
    /** How many contacts a sweep would forget right now. */
    gcCount: Int = 0,
): List<com.iotj.meshmore.xr.spatial.Stack.Row> {
    fun row(id: String, name: String, on: Boolean, onWord: String = "ON", offWord: String = "OFF") =
        com.iotj.meshmore.xr.spatial.Stack.Row(
            id = id,
            label = com.iotj.meshmore.xr.spatial.settingLabel(
                name, on, armed = armedId == id, onWord = onWord, offWord = offWord,
                armedWord = ctx.getString(R.string.w_confirm),
                fallbackName = ctx.getString(R.string.w_setting),
            ),
            // AN ARMED ROW DOES NOT LIGHT. Lighting it would show the state it
            // is about to have rather than the one it has, which is a switch
            // that lies for six seconds.
            lit = on && armedId != id,
        )
    return listOf(
        // LANGUAGE FIRST, IN THE APP AS WELL AS IN THE OS.
        //
        // Android 13's per-app language picker is the CORRECT place for this
        // and the manifest opts into it — but it lives four screens deep in a
        // system Settings app that a wearer is not wearing, and the person who
        // most needs to flip this is a native speaker sitting down for twenty
        // minutes of testing. One row, two states, no menus.
        //
        // Not a toggle over a stored preference: it calls the platform, which
        // recreates the Activity in the new locale. That rebuild is not a
        // side-effect to be minimised, it is the mechanism — every panel in
        // this app is sized from a locale-specific template at build time and
        // cannot be re-drawn afterwards, so a language change HAS to be a new
        // scene.
        row(
            "LANG", ctx.getString(R.string.r_lang), L10n.ja,
            onWord = "日本語", offWord = "ENGLISH",
        ),
        row("LOCATION", ctx.getString(R.string.r_location), Settings.useDeviceLocation(ctx)),
        // Two location settings, and they are separate on purpose: using a fix
        // to compute bearings is local and private, putting it in an advert
        // broadcasts it unencrypted to anyone in range.
        row("SHARE", ctx.getString(R.string.r_share), Settings.shareLocation(ctx)),
        row("ALERTS", ctx.getString(R.string.r_alerts), Settings.alerts(ctx)),
        row("DIAG", ctx.getString(R.string.r_diag), Settings.diagnostics(ctx)),
        row("AUTOPEN", ctx.getString(R.string.r_autopen), Settings.autopen(ctx)),
        row("MOTION", ctx.getString(R.string.r_motion), Settings.reduceMotion(ctx)),
        // WHO MAY ASK THIS RADIO WHAT IT KNOWS. Three permissions, not one
        // switch, so it opens its own list rather than toggling here — see
        // telemetryRows.
        com.iotj.meshmore.xr.spatial.Stack.Row(
            id = "TELEM", label = ctx.getString(R.string.r_telem), lit = false,
        ),
        // AND THE OTHER END OF THE SAME SUBJECT: what this radio can learn by
        // asking. Next to the permissions row on purpose — a wearer deciding
        // what to share should see, in the same list, what sharing is for.
        com.iotj.meshmore.xr.spatial.Stack.Row(
            id = "WX", label = ctx.getString(R.string.r_wx), lit = false,
        ),
        row("CHANSEND", ctx.getString(R.string.r_chansend), Settings.channelSend(ctx), ctx.getString(R.string.w_allowed), "OFF"),
        // GARBAGE COLLECTION, because a full contact store locks you out of
        // your own radio. See MeshLink.farContacts for what it will never
        // take. The count is in the label: a destructive control that does not
        // say how much it destroys is asking for consent it has not earned.
        com.iotj.meshmore.xr.spatial.Stack.Row(
            id = "GC",
            label = com.iotj.meshmore.xr.spatial.settingLabel(
                ctx.getString(R.string.r_gc, GC_FAR_KM.toInt(), gcCount),
                on = false, armed = armedId == "GC", offWord = "",
                armedWord = ctx.getString(R.string.w_confirm),
            ).trimEnd(),
            lit = false,
        ),
        com.iotj.meshmore.xr.spatial.Stack.Row(
            id = "FORGET",
            label = com.iotj.meshmore.xr.spatial.settingLabel(
                ctx.getString(R.string.r_erase, link.msgs.value.size),
                on = false, armed = armedId == "FORGET", offWord = "",
                armedWord = ctx.getString(R.string.w_confirm),
            ).trimEnd(),
            lit = false,
        ),
    )
}

/**
 * The one-word verdict on a message we sent, or nothing at all.
 *
 * Deliberately quiet for DELIVERED. Two hours of measurement say roughly nine
 * in ten arrive, so marking the ordinary case would put a badge on almost
 * every line and train the eye to skip exactly the place the interesting word
 * appears. Silence means it worked; a word means it did not, or not yet.
 */
/**
 * WHAT BECAME OF A MESSAGE, IN PLACE OF WHEN IT WAS SENT.
 *
 * It used to be appended after the timestamp, and it did not fit: the head
 * panel is 26 cells and `name(15) + "99 MIN AGO"(10) + "  · NO ANSWER"(13)` is
 * 38. The panel is sized once and clips what it cannot hold, from the end —
 * so the mark, which is the entire point of the line, was the first thing
 * gone. In both locales, since the Japanese arithmetic comes to 33.
 *
 * Replacing the timestamp rather than following it fits, and is also the
 * better line: a message that is still SENDING is seconds old, so "8 MIN AGO"
 * is the least interesting thing that could be said about it, and NO ANSWER
 * is more use than the hour at which the silence started.
 */
private fun deliveryMark(ctx: android.content.Context, m: MeshLink.Msg): String = when (m.delivery) {
    MeshLink.Delivered.LOST -> ctx.getString(R.string.dm_lost)
    MeshLink.Delivered.SENT -> ctx.getString(R.string.dm_sent)
    else -> ""
}

/**
 * The word under a pip, in the wearer's language.
 *
 * The pip's NAME is its identity — the action table, setLit and pipAt all
 * switch on it — so it cannot itself be translated. This maps identity to the
 * word drawn beside it, which is the only part a reader sees. Anything without
 * an entry falls back to its own name, so a new pip is legible in English
 * rather than blank in every language.
 */
private fun dockLabel(ctx: android.content.Context, id: String): String = when (id) {
    "COMPASS" -> ctx.getString(R.string.d_compass)
    "LINK" -> ctx.getString(R.string.d_link)
    "SETUP" -> ctx.getString(R.string.d_setup)
    "HELP" -> ctx.getString(R.string.d_help)
    "HERE" -> ctx.getString(R.string.d_here)
    "WIDE" -> ctx.getString(R.string.d_wide)
    "INBOX" -> ctx.getString(R.string.d_inbox)
    "LIST" -> ctx.getString(R.string.d_list)
    "NORTH" -> ctx.getString(R.string.d_north)
    "FIND" -> ctx.getString(R.string.d_find)
    else -> id
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
private fun ago(ctx: android.content.Context, sec: Long): String = when {
    sec < 60 -> ctx.getString(R.string.ago_now)
    sec < 3600 -> ctx.getString(R.string.ago_min, sec / 60)
    sec < 86400 -> ctx.getString(R.string.ago_hr, sec / 3600)
    else -> ctx.getString(R.string.ago_day, sec / 86400)
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

/** Passing through home space. Deliberately almost nothing. */
@Composable
private fun HoldingScreen() {
    Box(Modifier.fillMaxSize().background(Ground)) {
        Text(
            "MESHMORE XR",
            color = Accent, fontSize = 22.sp,
            fontFamily = meshMono(LocalContext.current), fontWeight = FontWeight.SemiBold,
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
private fun HorizonScene(link: MeshLink) {
    val session = LocalSession.current ?: return
    val rawCtx = LocalContext.current
    // EVERY SURFACE IS BUILT FROM THE LOCALISED CONTEXT — a surface built from
    // the raw one in a `--es lang ja` run comes out English with nothing to say
    // why. Prefs and services are unaffected by a configuration context.
    val ctx = remember { L10n.wrap(rawCtx) }
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
    val rackRef = remember { mutableStateOf<Rack?>(null) }
    val dockRef = remember { mutableStateOf<Dock?>(null) }
    val handsRef = remember { mutableStateOf<Hands?>(null) }
    val tagPadRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.TagPad?>(null) }
    val menuRef = remember { mutableStateOf<RadialMenu?>(null) }
    /**
     * THE NODE'S OWN MENU — the first per-node actions in the app. Separate
     * from [menuRef] (the cluster menu) because the two can be open at once:
     * a cluster and a node are different subjects with different verbs.
     */
    val nodeMenuRef = remember { mutableStateOf<RadialMenu?>(null) }
    val adviceRef = remember { mutableStateOf<com.iotj.meshmore.xr.spatial.Advice?>(null) }
    // HOW MANY PEERS ARE ONE PERMISSION AWAY FROM BEING DRAWN. Zero unless the
    // app has no origin AND there is something the wearer can do about it —
    // see the mesh effect, which is the only place that knows both.
    val unplacedRef = remember { mutableStateOf(0) }
    /** The board's name, only when we believe that board has no GNSS. */
    val boardRef = remember { mutableStateOf<String?>(null) }
    /** The last board named to the wearer, so the band says it once per state. */
    val boardSaid = remember { mutableStateOf<String?>(null) }
    val deviceNoteRef = remember { mutableStateOf("") }
    /** What the card should be saying. Written by the frame loop, built by an effect. */
    val adviceKind = remember {
        mutableStateOf(com.iotj.meshmore.xr.spatial.Advice.Kind.NONE)
    }
    /** True while the soak is running, so a recomposition cannot start a second. */
    val soakRunning = remember { mutableStateOf(false) }
    // WHEN EACH NODE WAS LAST ASKED FOR TELEMETRY, kept for the session so a
    // cooldown means something. Sweeping twice in a minute should ask nobody
    // twice — see TelemetryAsk.COOLDOWN_S.
    val telAsked = remember { mutableMapOf<String, Long>() }
    val telSweeping = remember { mutableStateOf(false) }
    // Offered once, ever, and only after a sweep has actually happened.
    val sharingOffered = remember { mutableStateOf(false) }

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
     * THE SWEEP KEEPS ITS OWN ARM, and it has to.
     *
     * `armed` is cleared unconditionally at the top of every settings pick —
     * one line, above the table, older than any of this — so an arm set inside
     * a row's own handler is wiped by the very next pinch. The sweep therefore
     * armed, re-armed, and could never reach its confirm: pinched twice 1.1
     * seconds apart on a live radio and logged "armed — 191" both times, which
     * is what the operator saw as "I clicked immediately and nothing happened".
     * Same shape as chanArmedAt, and for the same reason.
     */
    val gcArmedAt = remember { mutableStateOf(0L) }
    /** Which node's FORGET spoke is armed, and when. See the node menu. */
    val nodeForget = remember { mutableStateOf<Pair<String, Long>?>(null) }
    /**
     * The same idea for the CHANNELS bay, and separate from [armed] on purpose:
     * they are two surfaces, and a rolled channel name left armed while the
     * wearer goes to the APP bay must not be cancelled by — or worse, confused
     * with — a pick over there.
     */
    /**
     * True while dictation is being used for a TAG rather than a message.
     *
     * Dictation has one final-result callback and the crown owns it, because
     * every other spoken thing in this app becomes a message. A tag is not a
     * message and must never become one — so this flag says which surface the
     * next result belongs to, and it is cleared the instant the result lands.
     */
    val hearingTag = remember { mutableStateOf(false) }
    val chanArmed = remember { mutableStateOf<ChanAction?>(null) }
    /**
     * ONE THEME COMMIT'S HEAVY WORK AT A TIME. The restyles and the dock
     * rebuild are launched off the frame loop (a rebuild suspends on material
     * creation, and the commit frame is the one the wearer is watching), which
     * meant two quick commits ran them CONCURRENTLY on the same Stack
     * instances — and the sweep proved where that ends: a native SIGABRT,
     * "OwnedPtr of type imp::Mesh released with 1 outstanding borrowed
     * objects", one commit disposing meshes the other still borrowed. No Java
     * stack, process gone. Serial is correct and cheap; a commit's work
     * finishes before the next begins.
     */
    val themeWork = remember { kotlinx.coroutines.sync.Mutex() }
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
    // The touch channel rides the same Cue events as the tones — the puck's
    // actuator was measured real (COMPOSE_EFFECTS) after the spec assumed none.
    val haptics = remember { Haptics(ctx) }
    cue.haptics = haptics
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
        else crownRef.value?.say(ctx.getString(R.string.n_mic_denied), android.os.SystemClock.uptimeMillis())
    }
    val voice = remember { VoicePrefs(ctx) }
    // TextToSpeech holds a system engine binding. Leaking one is not fatal but
    // it is the kind of thing a store review notices, and the fix is two lines.
    androidx.compose.runtime.DisposableEffect(Unit) {
        onDispose { speech.release(); dictation.release(); cue.release() }
    }
    // Bumped by the HERE marker so the mesh rebuild below re-runs on a toggle.
    val hereEpoch = remember { mutableStateOf(0) }
    // THE PERMISSION HALF OF THE HERE PIP. Asked at the moment of pinching
    // HERE, never at startup — same doctrine as the mic above. Until now the
    // pip flipped the preference and nobody ever asked the SYSTEM: on real
    // hardware deviceFix() said "enabled but not permitted" into the log and
    // returned null forever, so the remedy the empty ring names — pinch HERE —
    // was a dead end, and the wearer stood in a placed-nothing mesh with the
    // pip dutifully lit. The result lands in [locGrant]; the effect that
    // answers it lives below the mesh effect, where the refs it needs exist.
    val locGrant = remember { mutableStateOf<Boolean?>(null) }
    val askLocation = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        Log.i(TAG_UI, "[here] location granted=$granted")
        locGrant.value = granted
    }

    /**
     * TURN ON THE HEADSET FIX, whatever it takes.
     *
     * The HERE pip is a TOGGLE and this is not: it is the remedy named on the
     * NO POSITION card, and a remedy that turns the fix off when the wearer
     * pinches it twice is a trap. It also closes the gap the pip left for a
     * day — the preference alone moves nothing without the system's grant, so
     * whichever half is missing is the half this asks for.
     */
    val useHeadsetFix: () -> Unit = {
        Settings.setUseDeviceLocation(ctx, true)
        dockRef.value?.setLit("HERE", true)
        hereEpoch.value += 1
        Log.i(TAG_UI, "[here] headset GPS -> ON (from the advice card)")
        if (!hereSource.hasLocationPermission()) {
            askLocation.launch(android.Manifest.permission.ACCESS_FINE_LOCATION)
        } else {
            locGrant.value = true
        }
    }

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
        // Fourth place the sweep found the same disease: this effect restarts
        // per skin key, and the restart CANCELS a buildFloor mid-material —
        // the orphaned placeholder is then double-freed by the next
        // clearFloor. Same lock, same NonCancellable, same reasoning as the
        // horizon rebuild.
        themeWork.withLock {
            kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) {
                st.buildFloor(o, skin.value)
            }
        }
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

    // The full-rotation regression drive. Through picker.fire, so every
    // transition takes exactly the path a pinch takes.
    LaunchedEffect(themePickerRef.value) {
        if (!MainActivity.sweep) return@LaunchedEffect
        val picker = themePickerRef.value ?: return@LaunchedEffect
        kotlinx.coroutines.delay(9_000)
        com.iotj.meshmore.xr.spatial.Theme.ALL.forEachIndexed { i, s ->
            picker.fire(s)
            kotlinx.coroutines.delay(4_500)
            Log.i(TAG_UI, "[sweep] ${i + 1}/${com.iotj.meshmore.xr.spatial.Theme.ALL.size} ${s.key}")
        }
        Log.i(TAG_UI, "[sweep] complete — all themes committed and survived")
    }

    // IS IT CONNECTED? ANSWERED WITHOUT BEING ASKED — see Hud.lowerOn, which
    // now stands by default. The dock's LINK pip was the other candidate and
    // was deliberately NOT used: a pip caption is a reusable panel, and a
    // panel's words on this runtime are whatever it held when it was first
    // composited (see Advice). If those updates do not land, the pip would sit
    // there reading LINK while the radio was gone, which is worse than silence.
    // The band is stroke geometry and is REBUILT on every change, so it cannot
    // lie about this.

    // THE CROWN'S WORDS. Off the frame loop, because that is the only place
    // they land — see Crown.applyWords. Polled rather than keyed: the crown's
    // level and draft change inside the frame loop's own drain, and a Compose
    // key cannot see a field on a plain object.
    LaunchedEffect(crownRef.value) {
        val c = crownRef.value ?: return@LaunchedEffect
        while (true) {
            if (c.applyWords()) Log.i(TAG_UI, "[crown] words: ${c.state()}")
            kotlinx.coroutines.delay(80)
        }
    }

    // THE SWEEP, WITHOUT A HAND, AND WITHOUT REGRET BY DEFAULT.
    // See MainActivity.gcProbe.
    LaunchedEffect(signature) {
        val mode = MainActivity.gcProbe ?: return@LaunchedEffect
        if (link.status.value.state != io.iotone.meshcore.android.SessionState.READY) {
            return@LaunchedEffect
        }
        // Let the contact sync finish; a sweep over a half-loaded list would
        // report a number that means nothing.
        kotlinx.coroutines.delay(3_000)
        val here = hereSource.resolve(link.here.value, MainActivity.homeOverride)
        val all = link.mesh.value
        Log.i(TAG_UI, "[gc] probe '$mode' — ${all.size} contacts held, " +
            "origin known=${here.known} (${here.lat}, ${here.lon})")
        if (!here.known) {
            Log.w(TAG_UI, "[gc] no origin — a sweep would refuse, and so does this")
            return@LaunchedEffect
        }
        // WHAT EACH THRESHOLD WOULD ACTUALLY BUY, because the right number is
        // a property of the mesh you are standing in and not of this app. A
        // store that refills to capacity in a day needs a different answer
        // from one that fills over a season.
        Search.FAR_STEPS.forEach { km ->
            val n = link.farContacts(here, km) { tagsRef.isFavourite(it) }.size
            Log.i(TAG_UI, "[gc] over ${km.toInt()} km: $n of ${all.size}")
        }
        val doomed = link.farContacts(here, GC_FAR_KM) { tagsRef.isFavourite(it) }
        Log.i(TAG_UI, "[gc] ${doomed.size} of ${all.size} are over $GC_FAR_KM km")
        // WHY EACH SURVIVOR SURVIVED, for the first handful. "Nothing to do"
        // and "everything was excluded" look identical from a count.
        val kept = all - doomed.toSet()
        kept.take(6).forEach { p ->
            val d = if (p.lat != null && p.lon != null && here.lat != null && here.lon != null) {
                "%.0f km".format(MeshNodes.haversineKm(here.lat!!, here.lon!!, p.lat!!, p.lon!!))
            } else {
                "no position"
            }
            Log.i(TAG_UI, "[gc] keeping '${p.name.take(18)}' $d full=${p.fullKey?.length ?: 0}")
        }
        doomed.take(8).forEach { p ->
            Log.i(TAG_UI, "[gc] candidate '${p.name.take(18)}' " +
                "%.0f km".format(
                    MeshNodes.haversineKm(here.lat!!, here.lon!!, p.lat ?: 0.0, p.lon ?: 0.0),
                ) + " key=${p.key} full=${p.fullKey?.length ?: 0} hex")
        }
        if (mode != "go") {
            Log.i(TAG_UI, "[gc] DRY RUN — nothing sent. Pass --es gc go to sweep.")
            return@LaunchedEffect
        }
        val n = link.forgetContacts(doomed)
        Log.i(TAG_UI, "[gc] sent $n removal(s) of ${doomed.size} candidates")
        kotlinx.coroutines.delay(2_000)
        Log.i(TAG_UI, "[gc] app now holds ${link.mesh.value.size} contacts " +
            "(the radio's own count returns on the next connect)")
    }

    // WHO IS ONE HOP AWAY. See MainActivity.neighbourProbe.
    LaunchedEffect(link) {
        if (!MainActivity.neighbourProbe) return@LaunchedEffect
        while (link.status.value.state != io.iotone.meshcore.android.SessionState.READY) {
            kotlinx.coroutines.delay(2_000)
        }
        kotlinx.coroutines.delay(25_000)
        val now = System.currentTimeMillis() / 1000
        val all = link.mesh.value
        // MeshCore's own convention, and the same one the focus card reads:
        // 1 is a direct neighbour, 0 and 250+ mean the path is simply unknown,
        // and anything between is the number of relays in the stored route.
        val direct = all.filter { it.hops == 1 }
        val relayed = all.filter { it.hops in 2..249 }
        val unknown = all.size - direct.size - relayed.size
        Log.i(
            TAG_UI,
            "[near] of ${all.size} contacts: ${direct.size} direct (1 hop), " +
                "${relayed.size} with a known route, $unknown with no route at all",
        )
        direct.sortedByDescending { it.lastSeenEpochSec }.take(12).forEach { p ->
            val age = if (p.lastSeenEpochSec <= 0) "never heard"
                else "${((now - p.lastSeenEpochSec) / 60)} min ago"
            Log.i(TAG_UI, "[near] 1 hop — '${p.name.take(22)}' key=${p.key} $age")
        }
        // And the ones we have heard RECENTLY, whatever their stored path says:
        // being heard is RF adjacency, which is the thing actually being asked
        // about, and a stale route can hide it.
        // The same rule the ring uses, or this line reports the future-dated
        // contacts as the freshest thing on the mesh — which is exactly the
        // bug it was written to look for.
        all.filter {
            !MeshNodes.undated(it.lastSeenEpochSec, now) && now - it.lastSeenEpochSec < 3600
        }
            .sortedByDescending { it.lastSeenEpochSec }
            .take(12)
            .forEach { p ->
                Log.i(
                    TAG_UI,
                    "[near] heard within the hour — '${p.name.take(22)}' " +
                        "hops=${p.hops} ${(now - p.lastSeenEpochSec) / 60} min ago",
                )
            }
    }

    // GIVE UP ON THE UNANSWERED, on a timer.
    //
    // Nothing else can do it: an acknowledgement that never arrives generates
    // no event, so "lost" is a conclusion drawn from silence and somebody has
    // to be watching the clock to draw it. Ten seconds is often enough that a
    // wearer sees the state settle while still looking at what they sent.
    LaunchedEffect(link) {
        while (true) {
            kotlinx.coroutines.delay(10_000)
            link.sweepLost()
        }
    }

    // THE SOAK. See MainActivity.soakTo.
    //
    // KEYED ON THE LINK AND NOT ON THE MESH. Keyed on the mesh signature this
    // effect was cancelled and restarted every time a contact arrived — 350 of
    // them during the sync — and since the first invocation had already set
    // the running flag, every restart returned immediately at the guard. The
    // test never started and never said why. An hour-long soak must hang off
    // something that does not move.
    LaunchedEffect(link) {
        val want = MainActivity.soakTo ?: return@LaunchedEffect
        if (soakRunning.value) return@LaunchedEffect
        soakRunning.value = true
        // WAIT FOR THE RADIO RATHER THAN GIVING UP ON IT. This effect is keyed
        // on the mesh signature, which settles once the store is read — so a
        // single early "not ready yet" return meant the test never ran at all,
        // and said nothing about why. An hour-long test can afford a minute of
        // patience.
        var waited = 0
        while (link.status.value.state != io.iotone.meshcore.android.SessionState.READY &&
            waited < 120_000
        ) {
            kotlinx.coroutines.delay(2_000)
            waited += 2_000
        }
        if (link.status.value.state != io.iotone.meshcore.android.SessionState.READY) {
            Log.w(TAG_UI, "[soak] no link after ${waited / 1000}s — not starting")
            soakRunning.value = false
            return@LaunchedEffect
        }
        // AND FOR THE TARGET TO ARRIVE, not for a guessed number of seconds.
        // The contact sync takes about twenty seconds for 350 contacts and the
        // node under test is somewhere in the middle of it; a fixed eight-second
        // wait declared the mesh empty before the radio had finished reading
        // its own store.
        fun find() = link.mesh.value.firstOrNull { p ->
            p.name.endsWith(want, ignoreCase = true) ||
                (p.fullKey ?: p.key).endsWith(want, ignoreCase = true)
        }
        var looked = 0
        while (find() == null && looked < 120_000) {
            kotlinx.coroutines.delay(2_000)
            looked += 2_000
        }
        val target = find()
        if (target == null) {
            Log.w(TAG_UI, "[soak] no node matching '$want' in the store — nothing to test against")
            Alerts.warn("SOAK", "NO NODE MATCHING '$want'")
            return@LaunchedEffect
        }
        val key = target.fullKey ?: target.key
        val every = MainActivity.soakEverySec.coerceAtLeast(10) * 1000L
        val until = System.currentTimeMillis() + MainActivity.soakMinutes * 60_000L
        var drops = 0
        var lastState = link.status.value.state
        Log.i(
            TAG_UI,
            "[soak] start -> '${target.name}' key=${target.key} " +
                "every ${every / 1000}s for ${MainActivity.soakMinutes}min",
        )
        Alerts.info("SOAK", "STARTED TO ${target.name.take(16)}")
        var n = 0
        while (System.currentTimeMillis() < until) {
            // A DROP IS PART OF THE RESULT, not a reason to stop. The point of
            // an hour is to find out what happens across one.
            val st = link.status.value.state
            if (st != lastState) {
                if (st != io.iotone.meshcore.android.SessionState.READY) drops++
                Log.i(TAG_UI, "[soak] link $lastState -> $st (drops=$drops)")
                lastState = st
            }
            val stamp = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US)
                .format(java.util.Date())
            val text = "HELLO, TODAY IS $stamp. PLEASE CALL ME."
            val r = link.sendTo(key, text)
            n++
            link.noteAttempt(r is MeshLink.Sent.Ok)
            val d = link.delivery.value
            Log.i(
                TAG_UI,
                "[soak] #$n ${r.javaClass.simpleName}" +
                    (if (r is MeshLink.Sent.Refused) " (${r.why})" else "") +
                    " — attempted=${d.attempted} accepted=${d.accepted} acked=${d.acked} " +
                    "refused=${d.refused} drops=$drops pending=${link.lostAfter(0L)}",
            )
            kotlinx.coroutines.delay(every)
        }
        val d = link.delivery.value
        val lost = link.lostAfter(60_000L)
        Log.i(
            TAG_UI,
            "[soak] DONE sent=$n attempted=${d.attempted} accepted=${d.accepted} " +
                "acked=${d.acked} refused=${d.refused} unacked>60s=$lost drops=$drops " +
                "reliability=${d.reliability?.let { "%.1f%%".format(it) } ?: "n/a"} " +
                "meanLatency=${d.meanLatencyMs ?: -1}ms",
        )
        Alerts.info(
            "SOAK",
            "DONE — ${d.acked}/${d.accepted} ACKED, $drops DROP(S)",
        )
        soakRunning.value = false
    }

    // THE COMPOSE CROWN, WITHOUT A HAND. See MainActivity.dmProbe.
    LaunchedEffect(crownRef.value, nodesRef.value) {
        if (!MainActivity.dmProbe) return@LaunchedEffect
        val c = crownRef.value ?: return@LaunchedEffect
        val n = nodesRef.value.firstOrNull() ?: return@LaunchedEffect
        if (c.target != null) return@LaunchedEffect
        kotlinx.coroutines.delay(2_000)
        c.target = com.iotj.meshmore.xr.spatial.Crown.Target(n.fullKey ?: n.key, n.name)
        c.show()
        c.compose()
        c.say(
            ctx.getString(
                R.string.n_dm_to,
                com.iotj.meshmore.xr.spatial.TypeTier.clip(n.name, 14),
            ),
            android.os.SystemClock.uptimeMillis(),
        )
        Log.i(TAG_UI, "[dm] probe — composing to '${n.name}' key=${n.key}")
    }

    LaunchedEffect(crownRef.value, nodesRef.value) {
        if (!MainActivity.crownProbe) return@LaunchedEffect
        val c = crownRef.value ?: return@LaunchedEffect
        val all = nodesRef.value
        if (all.isEmpty() || c.target != null) return@LaunchedEffect
        kotlinx.coroutines.delay(2_000)
        // A STARRED NODE IF THERE IS ONE, because the row this probe exists to
        // look at is the one that only a starred node brings.
        val n = all.firstOrNull { link.isStarred(it.fullKey ?: it.key, tagsRef::isFavourite) }
            ?: all.first()
        c.target = com.iotj.meshmore.xr.spatial.Crown.Target(n.fullKey ?: n.key, n.name)
        c.show()
        Log.i(TAG_UI, "[crown] probe — actions on '${n.name}' key=${n.key}")
    }

    LaunchedEffect(link, nodesRef.value) {
        val runs = MainActivity.soakRuns
        if (runs <= 0 || soakRunning.value) return@LaunchedEffect
        val all = nodesRef.value
        if (all.isEmpty()) return@LaunchedEffect
        // A NODE THE OPERATOR OWNS, or nothing. The transmitter refuses
        // anything else anyway; picking a starred node here means the run
        // fails as "no authorised node in range" rather than as ten refusals.
        val n = all.firstOrNull { link.isStarred(it.fullKey ?: it.key, tagsRef::isFavourite) }
        if (n == null) {
            Log.w(TAG_UI, "[minisoak] --ei soak: no starred node in the mesh yet")
            return@LaunchedEffect
        }
        soakRunning.value = true
        val key = n.fullKey ?: n.key
        Log.i(TAG_UI, "[minisoak] probe — $runs run(s) at '${n.name}'")
        val all0 = mutableListOf<TxLog.Attempt>()
        repeat(runs) { i ->
            Log.i(TAG_UI, "[minisoak] === run ${i + 1}/$runs ===")
            all0 += runSoakAt(ctx, link, key)
            // THE WHOLE SESSION, NOT JUST THE LAST MINUTE. Each run clears the
            // ledger so its own report is about itself; this keeps the union so
            // the rate has enough packets under it to mean something.
            TxLog.report(all0).forEach { Log.i(TAG_UI, "[minisoak] all| $it") }
        }
        Log.i(TAG_UI, "[minisoak] probe complete — ${all0.size} packets over $runs run(s)")
        soakRunning.value = false
    }

    // THE CARD, BUILT OFF THE FRAME LOOP. Keyed on what it would say, so a
    // steady state costs nothing and a change costs four panels once.
    LaunchedEffect(adviceRef.value, adviceKind.value, boardRef.value) {
        adviceRef.value?.say(adviceKind.value, boardRef.value)
        // AND SAY WHICH BOARD, WHERE A BOARD CAN BE SAID.
        //
        // The card cannot name it — every line on it is a panel built around
        // its final string at startup, which is what makes the card certain to
        // appear and also what stops it composing anything. So the specific
        // half of the answer goes to the notice band, which exists to carry
        // runtime text: the card says a position is missing, the band says the
        // radio in question has no GNSS to give one.
        //
        // Only alongside NO_FIX. "M5 C6L HAS NO GPS" is true whenever it is
        // true, and announcing it to somebody who is not currently missing a
        // position is trivia.
        val board = boardRef.value
        if (adviceKind.value == com.iotj.meshmore.xr.spatial.Advice.Kind.NO_FIX &&
            board != null && board != boardSaid.value) {
            boardSaid.value = board
            noticeRef.value?.say(ctx.getString(R.string.nf_board_nogps, board))
        }
        if (adviceKind.value != com.iotj.meshmore.xr.spatial.Advice.Kind.NO_FIX) {
            boardSaid.value = null
        }
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
    val query = remember {
        mutableStateOf(
            Search.Query(
                text = MainActivity.queryOverride.orEmpty(),
                farKm = MainActivity.farOverride,
                staleHours = MainActivity.staleOverride,
            ),
        )
    }
    val searchOpen = remember { mutableStateOf(MainActivity.showFind) }
    // BUMPED WHEN A MARK CHANGES. Starring somebody alters which nodes match and
    // which the ranker floats, and neither the mesh nor the query has moved — so
    // without this the ring keeps showing the answer to the question that was
    // asked before the star.
    val tagEpoch = remember { mutableStateOf(0) }
    /**
     * False until the boot surface comes down.
     *
     * A separate flag rather than a `bootRef.value != null` test, because
     * bootRef starts NULL — it is only assigned once the scene builds, about a
     * second in — so reading it would leave the app unguarded during exactly
     * the window where a connect-time backlog arrives.
     */
    val bootOver = remember { mutableStateOf(false) }

    LaunchedEffect(
        signature, here, horizonRef.value, hereEpoch.value, query.value, tagEpoch.value,
    ) {
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
        //
        // BUT ONLY WHAT WE MEASURED. Broadcasting a position that came out of
        // the radio closes a loop with no sensor anywhere in it: the app reads
        // SelfInfo, re-advertises it as the wearer's location, and the radio
        // stores it again. On a board with no GNSS — the operator's — that
        // makes the first position it is ever given permanent. It survives
        // reboots, it goes out to the mesh on every launch, and it would
        // follow the radio to another city still naming the place it was
        // switched on. Observed on glass 2026-08-18:
        //
        //   [here] radio -> 45.507087, -122.766247
        //   [link] advertising position 45.507087, -122.766247
        //
        // A fix from the headset, or one the operator stated, is a real claim
        // about where they are and still goes out. An echo does not.
        val measured = hereSource.source == "headset" || hereSource.source == "stated"
        if (Settings.shareLocation(ctx) && measured) link.publishPosition(origin2)
        // THE WEARER'S OWN FAVOURITES, folded in before ranking rather than
        // taught to the ranker.
        //
        // MeshNodes.rank already puts favourites first and never clusters one
        // away — it just believed only the RADIO's flag. Marking the peer here
        // means an app-level favourite gets that behaviour for free and
        // MeshNodes stays ignorant of preferences, which is what keeps it pure
        // and testable.
        // NO LONGER SKIPPED FOR THE SIMULATION. It was, back when a simulated
        // mesh was a list of already-placed motes with no keys to tag; a
        // simulated PEER has a key like any other, and starring one on the
        // emulator has to behave exactly as it does on glass or the emulator is
        // testing something else.
        val marked = mesh.map { p ->
            if (p.favourite) p
            else if (tagsRef.isFavourite(p.fullKey ?: p.key)) p.copy(favourite = true)
            else p
        }
        // NARROWED BEFORE RANKED, never after. Ranking a filtered population is
        // the whole point: with four matches, all four are drawn, at their true
        // bearings, in the same ring as everything else. Filtering the RESULT
        // instead would leave the ranker's 24 arbitrary picks and hide most of
        // them, which is a way of showing less rather than of finding anything.
        val found = Search.apply(
            marked, query.value,
            isFavourite = { it.favourite || tagsRef.isFavourite(it.fullKey ?: it.key) },
            tagsOf = { tagsRef.tagsFor(it.fullKey ?: it.key) },
        )
        if (found.size != marked.size) {
            val q = query.value
            Log.i(
                TAG_UI,
                "[find] text='${q.text}' fav=${q.favourites} tag=${q.tag ?: "-"} " +
                    "-> ${found.size} of ${marked.size}",
            )
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
        // ONE PATH, SIMULATED OR NOT. The fake mesh is fake at the SOURCE and
        // nowhere else, so ranking, clustering, de-occlusion and the tabletop
        // cap all run on it — which is the entire reason it was moved upstream.
        val nodes = MeshNodes.build(
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
            val future = mesh.count {
                it.lastSeenEpochSec > nowS + MeshNodes.CLOCK_SLOP_SEC
            }
            mesh.forEach {
                val d = if (MeshNodes.undated(it.lastSeenEpochSec, nowS)) Long.MAX_VALUE
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
                "<6h ${buckets[2]}, <24h ${buckets[3]}, older ${buckets[4]}" +
                (if (future > 0) " — $future dated in the FUTURE, counted as never heard" else ""))
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
        // WHAT THIS RADIO IS, AND WHAT IT HAS ACTUALLY DONE.
        //
        // The companion protocol describes settings and never hardware, so a
        // board with no GNSS is indistinguishable from one that has not got a
        // fix yet — except by watching it, which is what RadioFacts is for.
        // Keyed by public key: the BLE name's hex suffix is a MAC, not a key,
        // and a fact filed under a name follows whoever renames their node.
        run {
            val self = link.status.value.selfInfo
            val radioKey = self?.publicKey()?.joinToString("") { "%02x".format(it) }
            // THE HARDWARE'S OWN WORD FOR ITSELF, now that DEVICE_QUERY is
            // wired: 'Unit C6L' is the manufacturer string the radio reports,
            // and it identifies the BOARD. The node name is a label a human
            // typed and is only a fallback — the catalogue was built to guess
            // from it because nothing better was reachable, and now something
            // is.
            val radioName = link.deviceInfo?.manufacturer()?.trim()?.ifBlank { null }
                ?: self?.name()
            if (self != null) {
                RadioFacts.notePosition(
                    ctx, radioKey,
                    MeshNodes.Here(self.latitude(), self.longitude()).known,
                    // The position may be one WE published a moment ago; see
                    // RadioFacts.notePosition. While sharing, this radio's
                    // SelfInfo is not evidence about this radio.
                    ours = Settings.shareLocation(ctx),
                )
                val note = DeviceBook.describe(ctx, radioKey, radioName)
                if (note != deviceNoteRef.value) {
                    deviceNoteRef.value = note
                    Log.i(TAG_UI, "[device] $note")
                    Alerts.info("RADIO", note)
                }
            }
            // NAMED ONLY WHEN THE NAME IS EVIDENCE. The card says "X HAS NO
            // GPS" only where the app believes that of X; otherwise it says
            // the radio sends no position, which is the observation itself and
            // cannot be wrong.
            boardRef.value =
                if (MainActivity.boardOverride != null) {
                    MainActivity.boardOverride
                } else if (DeviceBook.gpsOf(ctx, radioKey, radioName) == false) {
                    DeviceBook.nameOf(ctx, radioKey, radioName)
                } else {
                    null
                }
            // A CARD ONLY WHERE THERE IS A REMEDY. With the headset fix on and
            // permitted, a missing origin is a cold GNSS rather than a
            // misconfiguration — the notice covers that, and a standing card
            // telling the wearer to do what they have already done is nagging.
            val remedy = !(Settings.useDeviceLocation(ctx) && hereSource.hasLocationPermission())
            unplacedRef.value = if (!origin2.known && remedy) unplaced else 0
        }
        if (!origin2.known && unplaced > 0) {
            noticeRef.value?.say(
                if (Settings.useDeviceLocation(ctx)) {
                    ctx.getString(R.string.n_no_fix_wait, unplaced)
                } else {
                    // Names the SHORTEST remedy, not the fault. The APP bay has
                    // the same switch two pinches deep; the HERE pip is one, is
                    // on the dock in every theme, and lights when it is on.
                    ctx.getString(R.string.n_no_fix_pinch)
                },
            )
            Log.w(TAG_UI, "[here] no fix — $unplaced located peer(s) cannot be drawn")
        }
        nodesRef.value = nodes
        // UNDER THE THEME LOCK, AND UNSTOPPABLE ONCE STARTED. This effect
        // restarts whenever its keys move, and a restart CANCELS the previous
        // body — mid-build, mid-material-creation. The sweep caught the
        // consequence twice from two angles: a native abort on a material
        // "released with 1 outstanding borrowed objects", once from a rebuild
        // racing a commit's restyles, once from a cancelled build's half-made
        // placeholder being cleared by the next. The lock serialises this
        // against the theme work; NonCancellable means a build that begins,
        // finishes — the next rebuild is already queued behind the lock and
        // supersedes it wholesale.
        themeWork.withLock {
            kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) {
                h.build(nodes, o, st.floorHeight())
                // S5 — the channel band, above the node lanes. Rebuilt with the
                // horizon because it belongs to the same ring and shares its
                // origin.
                bandsRef.value?.show(
                    channelBands(ctx, link, voice),
                    o,
                )
            }
        }
        // WHERE AM I, on the one surface that is always there.
        dockRef.value?.let { d ->
            // Pinned only while magnified: at 1:1 there is nothing to say and
            // an always-on caption is one more thing between the user and the
            // room.
            d.setCaption("WIDE", if (lens == null) null else "OUT x${lensStack.size}")
            d.setLit("WIDE", lens != null)
        }
    }

    // WHAT THE SYSTEM SAID when the HERE pip asked. Granted: the fix is
    // usually already sitting in lastKnown — the puck runs a fused network
    // provider — so one epoch bump places the whole mesh on the spot. Denied:
    // the preference is rolled back so the pip's light does not stand there
    // claiming a fix that can never arrive.
    LaunchedEffect(locGrant.value) {
        when (locGrant.value) {
            true -> {
                noticeRef.value?.say(ctx.getString(R.string.n_loc_placed))
                hereEpoch.value += 1
            }
            false -> {
                Settings.setUseDeviceLocation(ctx, false)
                dockRef.value?.setLit("HERE", false)
                noticeRef.value?.say(ctx.getString(R.string.n_loc_denied))
                cue.denied()
            }
            null -> Unit
        }
        locGrant.value = null
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
        val origin0 = stage.recentre(wantPlanes, geoMode = MainActivity.earthMode)
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
        // boot, hud, rack — a PHASE, so its ~dozen suspend .build() calls spill
        // this small closure instead of the whole scene. See the JIT note.
        suspend fun buildCore() {
        val boot = Boot(session, skin.value, ctx)
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
        }
        buildCore()
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

        // menu, focus, notice, hands, help — a PHASE, so its ~dozen suspend .build() calls spill
        // this small closure instead of the whole scene. See the JIT note.
        suspend fun buildInput() {
        val menu = RadialMenu(session, palette, ctx)
        // THROUGH RESOURCES, like the node menu beside it. These four were
        // written before there was a second locale and stayed literals through
        // the whole localisation pass — so a Japanese wearer pinching a cluster
        // got four English words on a surface that can draw kanji perfectly
        // well, next to a node menu that reads correctly.
        menu.build(listOf(
            RadialMenu.Item("magnify", ctx.getString(R.string.cm_magnify)),
            RadialMenu.Item("bearing", ctx.getString(R.string.cm_bearing)),
            RadialMenu.Item("nearest", ctx.getString(R.string.cm_nearest)),
            RadialMenu.Item("dismiss", ctx.getString(R.string.na_close)),
        ))
        menuRef.value = menu
        val nodeMenu = RadialMenu(session, palette, ctx)
        nodeMenu.build(listOf(
            RadialMenu.Item("fav", ctx.getString(R.string.na_fav)),
            RadialMenu.Item("msg", ctx.getString(R.string.na_msg)),
            RadialMenu.Item("telem", ctx.getString(R.string.na_telem)),
            RadialMenu.Item("dismiss", ctx.getString(R.string.na_close)),
            // THE FIFTH SPOKE, straight up. One node, forgotten from the
            // radio's store — the single-node answer to the same problem the
            // sweep solves in bulk, for when you can see the offender and do
            // not want to describe it with a filter.
            RadialMenu.Item("forget", ctx.getString(R.string.na_forget)),
        ))
        nodeMenuRef.value = nodeMenu
        val focus = com.iotj.meshmore.xr.spatial.Focus(session, palette, ctx)
        focus.build()
        focusRef.value = focus

        val notice = Notice(session, palette, ctx)
        notice.build()
        noticeRef.value = notice

        val hands = Hands(session, palette, ctx)
        hands.build()
        handsRef.value = hands

        // THE TAG KEYBOARD, born hidden like every other panel. A tag is the
        // one string in this app that must be exact, and dictation cannot
        // produce an exact string — see TagPad for the four attempts that
        // settled it.
        val tagPad = com.iotj.meshmore.xr.spatial.TagPad(session, palette, ctx)
        tagPad.build()
        tagPadRef.value = tagPad
        tagPad.onDone = { typed ->
            val tag = com.iotj.meshmore.xr.Channels.joinTag(typed)
            if (typed.isBlank() || tag == "#") {
                noticeRef.value?.say(ctx.getString(R.string.n_tag_none))
                cue.denied()
            } else if (!com.iotj.meshmore.xr.Channels.fitsOnARow(tag)) {
                noticeRef.value?.say(ctx.getString(R.string.n_tag_long))
                cue.denied()
            } else {
                // THE SAME CONFIRM STEP THE SPOKEN PATH USES. Typing is more
                // reliable, not infallible, and the row showing the literal
                // string is where a stray character is caught either way.
                chanArmed.value = ChanAction.Join(tag)
                chanArmedAt.value = android.os.SystemClock.uptimeMillis()
                Log.i(TAG_UI, "[chan] typed tag '$tag'")
                channelsRef.value?.show(
                    channelRows(ctx, link, voice, chanArmed.value),
                    title = ctx.getString(R.string.t_channels),
                    footer = chanFooter(ctx, chanArmed.value),
                )
                cue.recognised()
            }
        }
        tagPad.onCancel = { cue.closed() }
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
        val advice = com.iotj.meshmore.xr.spatial.Advice(session, palette, ctx)
        advice.build(origin)
        adviceRef.value = advice

        // Roster picks, queued: Focus.showFor builds the spur and therefore
        }
        buildInput()
        // suspends, and a dock action is not a coroutine. Same shape as the
        // node-pinch queue below.
        val rosterWant = java.util.concurrent.ConcurrentLinkedQueue<
            com.iotj.meshmore.xr.spatial.Horizon.Node>()
        // the dock and its ten actions — a PHASE, so its ~dozen suspend .build() calls spill
        // this small closure instead of the whole scene. See the JIT note.
        // SKIN-PARAMETERIZED, because the dock is THEME GEOMETRY: its palette,
        // WHICH PIPS EXIST (four on a wrist, ten on the ground) and its drop
        // (a tabletop puts a map where the dock lives) all belong to the skin.
        // It was built once at launch, and a switch left the OLD theme's dock
        // standing in the NEW theme's world — photographed as NERV's orange
        // column planted through BIOLUME's table.
        suspend fun buildDock(s: com.iotj.meshmore.xr.spatial.Theme.Skin) {
        // The previous dock's entities die first, or every switch leaks a dock.
        dockRef.value?.clear()
        val dock = Dock(session, s.palette, ctx)
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
        val wristDock = s.active
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
        val tabletop = s.posture == com.iotj.meshmore.xr.spatial.Theme.Posture.TABLETOP
        val dockDrop = if (tabletop) {
            com.iotj.meshmore.xr.spatial.Dock.TABLETOP_DROP
        } else {
            com.iotj.meshmore.xr.spatial.Dock.DROP
        }
        val dockReach = if (tabletop) {
            com.iotj.meshmore.xr.spatial.Dock.TABLETOP_REACH
        } else {
            com.iotj.meshmore.xr.spatial.Dock.REACH
        }
        val dockRows = if (tabletop) {
            com.iotj.meshmore.xr.spatial.Dock.TABLETOP_ROWS
        } else {
            com.iotj.meshmore.xr.spatial.Dock.COLUMN_ROWS
        }
        val dockLeft = if (tabletop) {
            com.iotj.meshmore.xr.spatial.Dock.TABLETOP_PAD_LEFT
        } else {
            com.iotj.meshmore.xr.spatial.Dock.PAD_LEFT
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
                // The preference alone moves nothing without the system's
                // grant; ask the moment the wearer expresses the intent.
                if (on && !hereSource.hasLocationPermission()) {
                    askLocation.launch(android.Manifest.permission.ACCESS_FINE_LOCATION)
                }
                Unit
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
                            who = whoLine(com.iotj.meshmore.xr.spatial.TypeTier.clip(t.title, 14), last?.let { ago(ctx, now - it.atEpochSec) } ?: ""),
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
                dockRef.value?.setLit("FIND", searchOpen.value || query.value.active)
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
                            // THE NAME COLUMN IS PADDED IN CELLS. `%-14s` counts
                            // code units, and a node name is the one string here
                            // that is arbitrary user text in an arbitrary script
                            // — 中継局 is three units and six cells, so a
                            // Japanese name shifted the range and bearing eight
                            // cells left of the column every other row uses.
                            // That happens in the ENGLISH build too: it is a
                            // fact about the name, not about the locale.
                            padCells(
                                com.iotj.meshmore.xr.spatial.TypeTier.clip(n.name, 14),
                                "%5s %s".format(
                                    MeshNodes.km(n.dist.toDouble()),
                                    MeshNodes.compass(n.bearingRad),
                                ),
                                column = 15,
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
        ).filter { !wristDock || it.first in WRIST_SET }.map { (n, f) -> n to { f(); Unit } },
            dockDrop, dockReach, dockRows, dockLeft) { id -> dockLabel(ctx, id) }
        // A short tick when a pip takes focus. On a display where you cannot
        // feel a control, sound is the only confirmation that the pointer has
        // arrived — and it arrives BEFORE the pinch, which is when it helps.
            dockRef.value = dock
            // Rewired on EVERY build, not once at setup — a rebuilt dock with
            // no focus cue and a dark HERE pip is the launch bug back again.
            dock.onFocus = { cue.recognised() }
            dock.setLit("HERE", Settings.useDeviceLocation(ctx))
            // The pip agrees with the band it toggles, from the first frame.
            dock.setLit("LINK", hudRef.value?.lowerOn ?: true)
        }
        buildDock(skin.value)
        // THE DWELL FALLBACK (§8.2). Armed only when no hand is tracked, so it
        // is an alternative to the pinch rather than a second way to fire the
        // same control by accident.
        // reel, cuff, crown, thread, console, picker, channels, bands, ember, first light — a PHASE, so its ~dozen suspend .build() calls spill
        // this small closure instead of the whole scene. See the JIT note.
        suspend fun buildComms() {
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
            noticeRef.value?.say(ctx.getString(R.string.n_hands_busy))
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
        gaze.setTargets(dockRef.value?.gazeTargets() ?: emptyList())
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
        }
        buildComms()
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
                    ctx.getString(
                        R.string.n_urgent,
                        com.iotj.meshmore.xr.spatial.TypeTier.clip(
                            m.fromName.ifBlank {
                                m.channelName ?: ctx.getString(R.string.n_unknown_sender)
                            },
                            16,
                        ).uppercase(),
                    ),
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
                // NOT DURING THE BOOT SEQUENCE.
                //
                // A voice arriving over the wordmark is the worst-timed sound
                // the app can make. The wearer has just put the glasses on,
                // there is nothing on screen but a hero surface and a filling
                // cylinder, and a stranger's message is read aloud into a room
                // that may have other people in it — with no visible message,
                // no sender, and no surface to look at for context. It reads as
                // a malfunction even when it is working perfectly.
                //
                // It is also exactly WHEN this fires: the radio delivers its
                // backlog at connect, so the burst lands inside the one window
                // where nothing can be shown.
                //
                // HELD MEANS DROPPED, not queued. A queue would empty itself
                // into the wearer's ear the moment the ring appeared, which is
                // the same startle moved fifteen seconds later and multiplied
                // by however many arrived. The messages themselves are not
                // lost — they are in the inbox, with their unread marks, which
                // is where a message you did not hear belongs.
                if (!bootOver.value) {
                    Log.i(TAG_UI, "[tts] held — boot surface still up ('$who')")
                } else {
                    speech.say(ctx.getString(R.string.n_says, who, m.text))
                }
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
            if (hearingTag.value) {
                // A TAG, NOT A MESSAGE. Nothing is written yet: the words
                // become an armed row showing the literal string, and the
                // second pinch is what reaches the radio.
                hearingTag.value = false
                if (text.isBlank()) {
                    noticeRef.value?.say(ctx.getString(R.string.n_tag_none))
                    cue.denied()
                } else {
                    val tag = Channels.joinTag(text)
                    if (!Channels.fitsOnARow(tag)) {
                        // Refused rather than clipped — see Channels.TAG_MAX_SHOWN.
                        Log.w(TAG_UI, "[chan] tag '$tag' is too wide to confirm")
                        noticeRef.value?.say(ctx.getString(R.string.n_tag_long))
                        cue.denied()
                    } else {
                        chanArmed.value = ChanAction.Join(tag)
                        chanArmedAt.value = android.os.SystemClock.uptimeMillis()
                        Log.i(TAG_UI, "[chan] heard tag '$tag' from '$text'")
                        noticeRef.value?.say(ctx.getString(R.string.n_tag_heard, tag))
                        channelsRef.value?.show(
                            channelRows(ctx, link, voice, chanArmed.value),
                            title = ctx.getString(R.string.t_channels),
                            footer = chanFooter(ctx, chanArmed.value),
                        )
                        cue.recognised()
                    }
                }
            } else if (text.isNotBlank()) {
                crownRef.value?.propose(text)
            } else {
                crownRef.value?.compose()
            }
        }

        // The menu gets the same tick the dock does. On a display where you
        // cannot feel a control, sound is the only confirmation the pointer
        // arrived — and it arrives BEFORE the pinch, which is when it helps.
        // THE TWO OUTCOMES THE LEDGER ALREADY KNEW AND COULD NOT SAY.
        //
        // A message answered is a tick; a message given up on is the one
        // falling shape in the vocabulary, with a matching fall in the hand.
        // Both fire from MeshLink, which is where the verdict is actually
        // reached, rather than from whichever surface happens to be open —
        // the same argument that put the allow-list at the transmitter.
        link.onDelivered = { cue.delivered() }
        link.onLost = { cue.lost() }
        // NO SILENT SWITCH YET, and that is a gap rather than a decision: §6
        // asks for the audio pack and TTS to be separate switches, and only
        // TTS has one today. Cue.enabled is the seam it will hang on — the
        // synthesiser already honours it — so adding the row is a settings
        // change rather than an audio one.

        menuRef.value?.onFocus = { cue.recognised() }
        // THE ONE PIP THAT REMEMBERS. Every other pip toggles a surface that is
        // closed at launch, so an unlit dock is the truth for all of them.
        // Headset GPS is a stored setting that survives the app, and its pip
        // came up dark on a build where it was already on — the state was
        // persisted correctly and looked exactly like off, which is the wrong
        // half to get right.
        if (MainActivity.showHelp) {
            helpRef.value?.setVisible(true)
            dockRef.value?.setLit("HELP", true)
        }
        rackRef.value?.onDismiss = {
            rackRef.value?.setVisible(false)
            dockRef.value?.setLit("SETUP", false)
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
        // WALL CLOCK, not a frame count. See Boot.tick: this counter decided
        // how long the boot surface stands, in units of "one frame is 33 ms" —
        // an assertion, not a measurement. The emulator's loop runs at about a
        // third of that and the glasses run faster, so MIN_BOOT_S and
        // MAX_BOOT_S meant different amounts of time on every device, and on
        // the fast one the surface could come down before its hero finished.
        var boot0StartMs = 0L
        var boot0Elapsed = 0f
        var statusTick = 0f
        // How many slots the radio had confirmed last time the CHANNELS bay was
        // drawn. A write is confirmed asynchronously — the reply lands in
        // dumpChannel with nothing to redraw the bay — and comparing the count
        // is cheaper every frame than re-texting six panels on a timer.
        var chanCount = -1
        // One region-compliance check per session, once both facts exist.
        var regionChecked = false
        // The no-radio card's automatic rescans: a few, gently spaced. Initial
        // not-found is one attempt by design; a wearer staring at the card is
        // the signal to try again without being asked.
        var adviceTries = 0
        var adviceLastTry = 0L
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
                                    who = whoLine(com.iotj.meshmore.xr.spatial.TypeTier.clip(
                                            m.fromName.ifBlank { t.title }, 14,
                                        ), ago(ctx, nowS - m.atEpochSec)),
                                    words = com.iotj.meshmore.xr.spatial.TypeTier.clip(m.text, 24),
                                    mine = m.direct,
                                )
                            },
                            // The probe path answers too, or it is not
                            // exercising the surface a hand reaches.
                            peer = t.id to t.title,
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
                        // TWO OF THESE ARE OURS, and they carry the two
                        // states worth seeing: one still waiting for an
                        // acknowledgement, one that never got one. The sample
                        // exists to check geometry, and delivery marks are
                        // geometry too — they lengthen the line that already
                        // carries who and when.
                        listOf(
                            Triple("newest, nearest to you", "JUST NOW", ""),
                            Triple("mine, still in flight", "1 MIN AGO",
                                ctx.getString(R.string.dm_sent)),
                            Triple("mine, never answered", "8 MIN AGO",
                                ctx.getString(R.string.dm_lost)),
                            Triple("fourth step into the past", "20 MIN AGO", ""),
                            Triple("fifth, still readable", "1 HR AGO", ""),
                            Triple("sixth and furthest", "3 HR AGO", ""),
                        ).map { (t, w, mark) ->
                            com.iotj.meshmore.xr.spatial.Thread.Line(
                                // MIRRORS THE REAL LINE, including the part
                                // that changed: a delivery mark REPLACES the
                                // timestamp rather than following it. A probe
                                // that exercises a shape the app no longer
                                // draws is worse than no probe.
                                who = whoLine(
                                    if (mark.isEmpty()) "SAMPLE" else "ME",
                                    mark.ifEmpty { w },
                                ),
                                words = t, mine = mark.isNotEmpty(),
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
            // MESH WEATHER, opened in ONE place for the same reason the region
            // list is: two routes to a surface means the launch flag verifies
            // its own route rather than the one a hand takes.
            val openWx = {
                val nowS = System.currentTimeMillis() / 1000
                bayMode.value = "WX"
                armed.value = null
                aboutOpen.value = false
                consoleRef.value?.hide()
                appRef.value?.show(
                    wxRows(
                        ctx, link,
                        TelemetryAsk.plan(
                            link.mesh.value, hereSource.here.value, nowS, telAsked.toMap(),
                        ),
                        nowS,
                    ),
                    title = ctx.getString(R.string.t_wx),
                    footer = ctx.getString(R.string.f_wx),
                    // A SET, NOT A SEQUENCE — see Stack.show.
                    form = true,
                )
                dockRef.value?.setLit("SETUP", false)
                cue.opened()
            }

            if (MainActivity.chanClear >= 0) launch {
                kotlinx.coroutines.delay(20_000)
                val idx = MainActivity.chanClear
                when (val w = link.clearChannel(idx)) {
                    is MeshLink.Wrote.Ok -> Log.i(TAG_UI, "[chan] cleared slot $idx — reading back")
                    is MeshLink.Wrote.Refused -> Log.w(TAG_UI, "[chan] clear refused: ${w.why}")
                }
            }
            MainActivity.joinTag?.let { raw ->
                launch {
                    // After the connect-time slot enumeration, or freeSlot()
                    // has no table to choose from and the write is refused for
                    // a reason that has nothing to do with the channel.
                    kotlinx.coroutines.delay(20_000)
                    val tag = com.iotj.meshmore.xr.Channels.joinTag(raw)
                    val name = MainActivity.joinName
                        ?: com.iotj.meshmore.xr.Channels.nameFor(tag)
                    val psk = if (MainActivity.chanPublic) {
                        com.iotj.meshmore.xr.Channels.publicPsk()
                    } else {
                        com.iotj.meshmore.xr.Channels.pskFor(tag)
                    }
                    // THE TAG IS LOGGED AND THE KEY IS NOT. The tag is the
                    // shareable half — it is meant to be said out loud — and
                    // the key is the half that must never reach a surface a
                    // wearer can open. writeChannel logs four bytes of
                    // fingerprint so a write can be correlated with what the
                    // radio reports back, and no more.
                    Log.i(TAG_UI, "[chan] joining '$tag' as \"$name\"")
                    val slot = MainActivity.chanSlot
                    val w = if (slot >= 0) link.writeChannelAt(slot, name, psk)
                            else link.writeChannel(name, psk)
                    when (w) {
                        is MeshLink.Wrote.Ok ->
                            Log.i(TAG_UI, "[chan] joined '$tag' in slot ${w.idx}")
                        is MeshLink.Wrote.Refused ->
                            Log.w(TAG_UI, "[chan] refused: ${w.why}")
                    }
                }
            }
            if (MainActivity.wxSweep) launch {
                // Long enough for the contact sync to finish: a sweep planned
                // against a half-loaded store asks a fraction of the mesh and
                // reports a census that is wrong about the rest.
                kotlinx.coroutines.delay(45_000)
                openWx()
                kotlinx.coroutines.delay(1_500)
                Log.i(TAG_UI, "[wx] probe — sweeping")
                appRef.value?.fire("WXASK")
            }
            MainActivity.openBay?.let { bay ->
                launch {
                    // After the scene is up and the radio has enumerated its
                    // channels, or CHANNELS opens onto an empty list and the
                    // check says nothing.
                    kotlinx.coroutines.delay(9000)
                    // WX IS A ROW, NOT A PLATE, so the console cannot fire it.
                    // Same surface, same single route — see openWx.
                    if (bay == "WX") openWx() else consoleRef.value?.fire(bay)
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
                        // THROUGH THE QUEUE, not straight to showFor — the
                        // pinch path now also raises the node's action menu,
                        // and a flag that skipped the drain would verify a
                        // route no hand takes.
                        focusWant.add(n.first to n.second)
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
                    regionRows(ctx, hereSource.here.value, link.radio.live),
                    title = ctx.getString(R.string.t_region, Regions.labelFor(link.radio.live)),
                    footer = ctx.getString(R.string.f_region),
                    // A SET, NOT A SEQUENCE — see Stack.show.
                    form = true,
                )
                dockRef.value?.setLit("SETUP", false)
                cue.opened()
            }

            // THE FRAME LOOP'S BODY, AS NAMED PARTS — see the JIT note.
            //
            // A suspend lambda compiles into ONE invokeSuspend state machine,
            // and this loop's grew past ART's ~40k-instruction ceiling
            // (measured 46,076), so the whole frame path ran INTERPRETED.
            // Local functions compile as their own methods while keeping
            // closure access to the scene, which is why these are declared
            // here rather than at file scope with fifteen parameters each.
            suspend fun tickReel(nowMs: Long) {
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
                            // A CROWN WITH A TARGET IS NOT THE CARD'S. It was
                            // summoned from a node that has no card and no
                            // thread, so the card's life cannot end it — only
                            // sending, cancelling or B can.
                            val addressed = cw.target != null
                            if (addressed) {
                                if (!cw.open) { cw.show(); cw.compose() }
                            } else if (r.open && r.cardAt != null) {
                                if (!cw.open) cw.show()
                            } else if (cw.open) {
                                cw.hide()
                            }
                            // The crown's VOICE label has to agree with the
                            // store for the CURRENT message, not the one the
                            // wearer last toggled — otherwise turning voice on
                            // for one conversation appears to have turned it on
                            // for every message you scroll past.
                            val sel = if (cw.target != null) null
                                else link.msgs.value.getOrNull(r.selectedIndex)
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
                            // Offered only while something is actually
                            // unanswered. See Crown.canResend.
                            cw.canResend = link.lastUnanswered() != null
                            // OFFERED ONLY AT A FAVOURITE, and only at a
                            // person. Ten full-length packets is real airtime
                            // on a shared band; the nodes worth spending it on
                            // are the ones the operator has marked as theirs.
                            // A channel is excluded outright — a soak on a
                            // public band is ten messages of noise for
                            // everybody within range.
                            //
                            // Both notions of favourite count: the star this
                            // app keeps and the flag the radio itself stores,
                            // because a wearer who starred a node in either
                            // place means the same thing by it.
                            cw.canSoak = !soakRunning.value &&
                                if (cw.target?.channel == true) {
                                    // A PRIVATE CHANNEL THE WEARER AUTHORISED,
                                    // never the public band — see
                                    // MeshLink.soakableChannel. The operator
                                    // made #soaktest to soak on, and a blanket
                                    // "no channels" forbade the one case the
                                    // rule was never aimed at.
                                    link.soakableChannel(cw.target?.key)
                                } else {
                                    link.isStarred(
                                        cw.target?.key ?: sel?.fromKey,
                                        tagsRef::isFavourite,
                                    )
                                }
                            cw.tick(
                                // `at` only gates the crown; the rows are
                                // placed from the head and its yaw either way,
                                // so a targeted crown hangs off the wearer.
                                if (cw.target != null) hp?.translation else r.cardAt,
                                hp?.translation,
                                hp?.let { yawOf(it) } ?: 0f, nowMs,
                            )
                            while (true) {
                                val act = cw.poll() ?: break
                                onCrown(
                                    ctx, act, link, r, cw, threadRef.value, speech,
                                    dictation, voice, cue, stage, nowMs,
                                    askMic = {
                                        askMic.launch(android.Manifest.permission.RECORD_AUDIO)
                                    },
                                    // THE RUN LIVES IN THE FRAME LOOP'S SCOPE,
                                    // so it dies with the scene rather than
                                    // outliving it and transmitting into a
                                    // session that has gone.
                                    runSoak = { peerKey, onChannel ->
                                        soakRunning.value = true
                                        launch {
                                            runSoakAt(ctx, link, peerKey, onChannel) {
                                                cw.say(
                                                    it,
                                                    android.os.SystemClock.uptimeMillis(),
                                                )
                                            }
                                            soakRunning.value = false
                                        }
                                        Unit
                                    },
                                )
                            }
                        }
                    }
                }
            }
            suspend fun sayLinkStep() {
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
                            // Locale-blind: matches "STEP 1/4" and 手順 1/4 alike.
                            Regex("(\\d)/4").find(step)?.groupValues?.get(1)
                                ?.toIntOrNull()?.let { cue.linkStep(it) }
                            // A DROP GETS ITS OWN SOUND. The ladder is for
                            // arriving; losing the radio is the opposite motion
                            // and the one you need to hear while looking at a
                            // trail rather than at the band. Said once per
                            // outage — the string does not change while the
                            // retries run, so this cannot become a metronome.
                            if (link.status.value.droppedAtMs != null) cue.dropped()
                            Log.i(TAG_UI, "[link] $step")
                        } else {
                            // Arrival is worth one line too; it is the only
                            // moment the wearer learns the radio is theirs.
                            val who = link.status.value.deviceName
                            noticeRef.value?.say(
                                if (who != null) ctx.getString(R.string.n_linked, who.uppercase())
                                else ctx.getString(R.string.n_linked_anon),
                            )
                            Log.i(TAG_UI, "[link] READY (${who ?: "unnamed"})")
                            cue.linked()
                        }
                    }
                }
            }
            suspend fun drainChannels(nowMs: Long) {
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
                                    noticeRef.value?.say(ctx.getString(R.string.n_chan_made, tag))
                                    Log.i(TAG_UI, "[chan] made ${w.name} in slot ${w.idx}")
                                    cue.opened()
                                }
                                is MeshLink.Wrote.Refused -> {
                                    noticeRef.value?.say(ctx.getString(R.string.n_refused, w.why))
                                    cue.denied()
                                }
                            }
                        }
                        // SAY THE TAG. The mic is asked for at the moment of
                        // speaking, like every other spoken path in this app —
                        // a microphone prompt at launch reads as an app that
                        // wants to listen to the room.
                        // TYPED, WHICH IS THE ONE THAT WORKS. The pad is
                        // built at setup and hidden; this only places it and
                        // asks for the keyboard. See TagPad.
                        id == ROW_TYPETAG -> {
                            val h = stage.headNow()
                            if (h == null) {
                                noticeRef.value?.say(ctx.getString(R.string.n_not_tracking))
                                cue.denied()
                            } else {
                                chanArmed.value = null
                                tagPadRef.value?.showAt(h.translation, yawOf(h))
                                cue.opened()
                            }
                        }
                        // ARMED, LIKE EVERY OTHER IRREVERSIBLE ACT HERE. The
                        // second pinch is on a row that says what it will do,
                        // under a footer that says the key does not come back.
                        id.startsWith(ROW_DEL) && pending !is ChanAction.Delete -> {
                            val idx = id.removePrefix(ROW_DEL).toIntOrNull()
                            val c = idx?.let { i -> link.channels().firstOrNull { it.idx == i } }
                            if (c == null) {
                                cue.denied()
                            } else {
                                chanArmed.value = ChanAction.Delete(c.idx, c.name)
                                chanArmedAt.value = nowMs
                                cue.recognised()
                            }
                        }
                        id.startsWith(ROW_DEL) && pending is ChanAction.Delete -> {
                            val gone = pending.name
                            disarm()
                            when (val w = link.clearChannel(pending.idx)) {
                                is MeshLink.Wrote.Ok -> {
                                    Log.i(TAG_UI, "[chan] deleted '$gone' from slot ${pending.idx}")
                                    noticeRef.value?.say(
                                        ctx.getString(R.string.n_chan_gone, gone.uppercase()),
                                    )
                                    // AND STOP READING IT ALOUD. A deleted
                                    // channel that kept its read-aloud flag
                                    // would speak again the moment the slot was
                                    // reused for something else.
                                    voice.set("#${pending.idx}", false)
                                    cue.opened()
                                }
                                is MeshLink.Wrote.Refused -> {
                                    noticeRef.value?.say(
                                        ctx.getString(R.string.n_refused, w.why),
                                    )
                                    cue.denied()
                                }
                            }
                        }
                        id == ROW_SAYTAG -> {
                            if (ctx.checkSelfPermission(
                                    android.Manifest.permission.RECORD_AUDIO,
                                ) != android.content.pm.PackageManager.PERMISSION_GRANTED
                            ) {
                                askMic.launch(android.Manifest.permission.RECORD_AUDIO)
                            } else {
                                hearingTag.value = true
                                chanArmed.value = null
                                dictation.start()
                                noticeRef.value?.say(ctx.getString(R.string.n_say_tag))
                                cue.recognised()
                            }
                        }
                        id == ROW_JOINTAG && pending is ChanAction.Join -> {
                            val tag = pending.tag
                            disarm()
                            when (
                                val w = link.writeChannel(
                                    Channels.nameFor(tag), Channels.pskFor(tag),
                                )
                            ) {
                                is MeshLink.Wrote.Ok -> {
                                    Log.i(TAG_UI, "[chan] joined '$tag' in slot ${w.idx}")
                                    noticeRef.value?.say(
                                        ctx.getString(R.string.n_chan_made, tag),
                                    )
                                    cue.opened()
                                }
                                is MeshLink.Wrote.Refused -> {
                                    noticeRef.value?.say(
                                        ctx.getString(R.string.n_refused, w.why),
                                    )
                                    cue.denied()
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
                                    noticeRef.value?.say(ctx.getString(R.string.n_joined_public))
                                is MeshLink.Wrote.Refused ->
                                    noticeRef.value?.say(ctx.getString(R.string.n_refused, w.why))
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
                            noticeRef.value?.say(ctx.getString(R.string.n_public_warn))
                            cue.recognised()
                        }
                        // SPEAKING ON A CHANNEL IS WHAT A CHANNEL IS FOR.
                        //
                        // A pick used to toggle read-aloud, which left the app
                        // with no way to start a message on a channel at all —
                        // `replyTo` answers where a message came from, so a
                        // quiet channel could be joined, named and counted but
                        // never spoken on. Reported exactly that way.
                        //
                        // The read-aloud setting did not go anywhere: the crown
                        // owns it, under VOICE, keyed on the same thread id —
                        // which is also where it belongs, beside the rest of a
                        // conversation's settings rather than on a shelf.
                        else -> {
                            val c = crownRef.value
                            val idx = id.removePrefix("#").toIntOrNull()
                            if (c == null || idx == null) {
                                cue.closed()
                            } else {
                                val chan = link.channels().firstOrNull { it.idx == idx }
                                val name = chan?.name?.ifBlank { null }
                                    ?: ctx.getString(R.string.chan_numbered, idx)
                                channelsRef.value?.hide()
                                c.target = com.iotj.meshmore.xr.spatial.Crown.Target(
                                    id, name, channel = true,
                                )
                                c.show()
                                c.compose()
                                Log.i(TAG_UI, "[chan] composing on $id ('$name')")
                                cue.opened()
                            }
                        }
                    }
                    channelsRef.value?.update(
                        channelRows(ctx, link, voice, chanArmed.value), chanFooter(ctx, chanArmed.value),
                    )
                }
                // The arming lapses on its own, like the APP bay's. A rolled
                // name left hanging in the air is a write the wearer walked away
                // from, and it must not still be one pinch from happening when
                // they come back to the bay for something else.
                chanArmed.value?.let {
                    if (nowMs - chanArmedAt.value > ARM_MS) {
                        chanArmed.value = null
                        channelsRef.value?.update(channelRows(ctx, link, voice, null), chanFooter(ctx, null))
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
                        channelRows(ctx, link, voice, chanArmed.value), chanFooter(ctx, chanArmed.value),
                    )
                }
                // THE APP BAY. Two of its rows are GUARDED: the first pick
            }
            fun appGcCount(): Int = gcCount(
                link,
                hereSource.resolve(link.here.value, MainActivity.homeOverride),
            ) { tagsRef.isFavourite(it) }
            suspend fun drainAppBay(nowMs: Long) {
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
                        appRef.value?.update(
                            appRows(ctx, link, null, appGcCount()),
                            "LIT = ON    B TO CLOSE",
                        )
                    }
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
                                radioRows(ctx, link.radio, link.clockSkewSec),
                                title = com.iotj.meshmore.xr.spatial.radioTitle(
                                    link.radio.live?.freqMhz, link.radio.live?.txDbm,
                                ),
                                footer = if (link.radio.dirty()) ctx.getString(R.string.f_pending)
                                else ctx.getString(R.string.f_radio_idle),
                                // A SET, NOT A SEQUENCE — see Stack.show.
                                form = true,
                            )
                        }
                        cue.recognised()
                        continue
                    }
                    // MESH WEATHER. One control — ASK — and it says how many
                    // radios it is about to wake before it wakes them.
                    if (bayMode.value == "WX") {
                        val nowS = System.currentTimeMillis() / 1000
                        if (id == "WXASK" && !telSweeping.value) {
                            val plan = TelemetryAsk.plan(
                                link.mesh.value, hereSource.here.value, nowS, telAsked.toMap(),
                            )
                            telSweeping.value = true
                            noticeRef.value?.say(
                                ctx.getString(R.string.n_wx_start, plan.askCount),
                            )
                            launch {
                                val before = link.mesh.value.count { it.telemetry != null }
                                var asked = 0
                                plan.ask.forEach { p ->
                                    val full = p.fullKey ?: return@forEach
                                    if (link.askTelemetry(full)) {
                                        asked++
                                        telAsked[full] = System.currentTimeMillis() / 1000
                                    }
                                    // ONE AT A TIME, SPACED. The pacing is the
                                    // whole of this app's claim to be a polite
                                    // neighbour on a shared band.
                                    kotlinx.coroutines.delay(TelemetryAsk.GAP_MS)
                                }
                                // A beat for the last replies to come back.
                                kotlinx.coroutines.delay(20_000)
                                val now = link.mesh.value
                                val answered = now.count { it.telemetry != null } - before
                                val withEnv = now.count { it.telemetry?.tempC != null }
                                val line = TelemetryAsk.report(
                                    asked, answered.coerceAtLeast(0), withEnv,
                                )
                                Log.i(TAG_UI, "[wx] $line")
                                plan.census().forEach { Log.i(TAG_UI, "[wx] $it") }
                                Alerts.info("WX", line.uppercase())
                                // SILENCE, EXPLAINED. A sweep that asks
                                // thirteen radios and hears nothing back looks
                                // exactly like a broken app, and it is not:
                                // MeshCore ships with every telemetry class
                                // set to DENY — this operator's own radio
                                // reads raw 0x00 — so the ordinary case is
                                // that nobody may answer. Measured 2026-08-21:
                                // 13 asked, 0 answered.
                                if (asked > 0 && answered <= 0) {
                                    Alerts.warn("WX", ctx.getString(R.string.al_wx_silent))
                                    Log.i(TAG_UI, "[wx] nobody answered — permissions default to DENY")
                                }
                                noticeRef.value?.say(
                                    ctx.getString(
                                        R.string.n_wx_done,
                                        answered.coerceAtLeast(0), asked,
                                    ),
                                )
                                telSweeping.value = false
                                appRef.value?.update(
                                    wxRows(ctx, link, null, System.currentTimeMillis() / 1000),
                                    ctx.getString(R.string.f_wx),
                                )
                                // THE NUDGE, ONCE. Asking without sharing is
                                // allowed — the operator ruled on that — but
                                // the asymmetry is worth mentioning at the one
                                // moment it is concrete rather than abstract.
                                if (TelemetryAsk.shouldOfferSharing(
                                        link.telemetryPermissions().level(2),
                                        sharingOffered.value,
                                        asked,
                                    )
                                ) {
                                    sharingOffered.value = true
                                    kotlinx.coroutines.delay(2_500)
                                    noticeRef.value?.say(ctx.getString(R.string.n_wx_share))
                                    Alerts.info("WX", ctx.getString(R.string.n_wx_share))
                                }
                            }
                        }
                        appRef.value?.update(
                            wxRows(
                                ctx, link,
                                if (telSweeping.value) null else TelemetryAsk.plan(
                                    link.mesh.value, hereSource.here.value, nowS,
                                    telAsked.toMap(),
                                ),
                                nowS,
                            ),
                            ctx.getString(R.string.f_wx),
                        )
                        cue.recognised()
                        continue
                    }
                    // DID THEY ARRIVE. Read-only except for CLEAR, which is
                    // the only control a delivery record needs: everything else
                    // on this surface is the mesh answering for itself.
                    if (bayMode.value == "TX") {
                        if (id == "TXCLEAR") {
                            link.clearTxLog()
                            noticeRef.value?.say(ctx.getString(R.string.n_txcleared))
                        }
                        appRef.value?.update(txRows(ctx, link), ctx.getString(R.string.f_tx))
                        cue.recognised()
                        continue
                    }
                    // WHO MAY ASK ABOUT ME. Its own bay because the answer is
                    // three answers, and each row CYCLES because the useful
                    // level is the middle one and a toggle cannot reach it.
                    if (bayMode.value == "TELEM") {
                        val i = id.removePrefix("TELEM").toIntOrNull()
                        if (i != null) {
                            val perms = link.telemetryPermissions()
                            val next = (perms.level(i) + 1) %
                                (com.iotj.meshmore.xr.spatial.TelemetryPerms.ALLOW_ALL + 1)
                            // WRITTEN TO THE RADIO IMMEDIATELY, not staged. The
                            // radio parameters next door are staged because a
                            // wrong set makes it deaf and unrecoverable over
                            // the air; a permission is one byte, reversible by
                            // picking again, and leaving it pending would mean
                            // a wearer who thought they had closed something
                            // had not.
                            link.setTelemetryPermissions(perms.with(i, next))
                            noticeRef.value?.say(
                                "%s — %s".format(
                                    com.iotj.meshmore.xr.spatial.TelemetryPerms.CLASSES[i],
                                    com.iotj.meshmore.xr.spatial.TelemetryPerms.name(next),
                                ),
                            )
                        }
                        appRef.value?.update(telemetryRows(ctx, link), ctx.getString(R.string.f_telem))
                        cue.recognised()
                        continue
                    }
                    // A LANGUAGE IS PICKED, THEN ANNOUNCED, THEN APPLIED.
                    //
                    // setApplicationLocales recreates the Activity the moment
                    // it is called, so calling it inline meant the scene tore
                    // down under the wearer's hand with no warning — "abrupt
                    // and jarring", and they were right. The notice goes up
                    // first and the switch waits a beat behind it, so the last
                    // thing seen before the rebuild is a sentence explaining
                    // the rebuild.
                    if (bayMode.value == "LANG") {
                        val tag = when (id) {
                            "LANG_en" -> "en"
                            "LANG_ja" -> "ja"
                            else -> null
                        }
                        Log.i(TAG_UI, "[l10n] picked ${tag ?: "system default"}")
                        noticeRef.value?.say(ctx.getString(R.string.n_lang_switching))
                        cue.recognised()
                        launch {
                            kotlinx.coroutines.delay(LANG_SETTLE_MS)
                            runCatching {
                                ctx.getSystemService(android.app.LocaleManager::class.java)
                                    ?.applicationLocales =
                                    if (tag == null) {
                                        android.os.LocaleList.getEmptyLocaleList()
                                    } else {
                                        android.os.LocaleList.forLanguageTags(tag)
                                    }
                            }.onFailure {
                                Log.w(TAG_UI, "[l10n] locale switch refused: $it")
                                noticeRef.value?.say(ctx.getString(R.string.n_lang_failed))
                            }
                        }
                        continue
                    }
                    if (bayMode.value == "RADIO") {
                        // The way IN to the region list. It is not an edit, so
                        // it does not go through onRadioRow — that function
                        // stages parameters, and this one opens a surface.
                        if (id == "REGION") { openRegions(); continue }
                        // ACTIONS FIRST. They fire now; the parameter rows
                        // below only stage. See onRadioAction.
                        if (onRadioAction(ctx, id, link, armed, nowMs) { note ->
                                noticeRef.value?.say(note)
                            }
                        ) {
                            appRef.value?.update(
                                radioRows(ctx, link.radio, link.clockSkewSec),
                                if (armed.value?.first == "FLOOD") {
                                    ctx.getString(R.string.f_flood_arm)
                                } else {
                                    ctx.getString(R.string.f_radio_idle)
                                },
                            )
                            cue.recognised()
                            continue
                        }
                        onRadioRow(ctx, id, link.radio, armed, nowMs) { note ->
                            noticeRef.value?.say(note)
                        }
                        appRef.value?.update(
                            radioRows(ctx, link.radio, link.clockSkewSec),
                            if (armed.value?.first == "COMMIT") ctx.getString(R.string.f_commit_arm)
                            else if (link.radio.dirty()) ctx.getString(R.string.f_pending)
                            else ctx.getString(R.string.f_radio_idle),
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
                                "CHANSEND" -> ctx.getString(R.string.f_chansend_arm)
                                else -> ctx.getString(R.string.f_erase_arm)
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
                        "ALERTS" -> Settings.setAlerts(ctx, !Settings.alerts(ctx))
                        // SAID OUT LOUD, like every other switch that changes
                        // what the app records rather than what it shows. The
                        // spoken confirmation used to belong to the console
                        // plate; the plate now opens the delivery bay, and a
                        // toggle that changes logging with no acknowledgement
                        // is a toggle a wearer pinches twice to be sure.
                        "DIAG" -> {
                            val on = !Settings.diagnostics(ctx)
                            Settings.setDiagnostics(ctx, on)
                            noticeRef.value?.say(
                                ctx.getString(
                                    if (on) R.string.n_diag_on else R.string.n_diag_off,
                                ),
                            )
                        }
                        "AUTOPEN" -> Settings.setAutopen(ctx, !Settings.autopen(ctx))
                        // MESH WEATHER sits beside the permissions row because
                        // the two are the same subject seen from either end:
                        // who may ask about me, and what I may learn by asking.
                        "WX" -> { openWx(); continue }
                        "TELEM" -> {
                            bayMode.value = "TELEM"
                            appRef.value?.show(
                                telemetryRows(ctx, link),
                                title = ctx.getString(R.string.t_telem),
                                footer = ctx.getString(R.string.f_telem),
                                // A SET, NOT A SEQUENCE — see Stack.show.
                                form = true,
                            )
                            cue.opened()
                            continue
                        }
                        "MOTION" -> {
                            val on = !Settings.reduceMotion(ctx)
                            Settings.setReduceMotion(ctx, on)
                            // Read by every surface's reveal on the next frame;
                            // no rebuild, because a transition grammar is
                            // arithmetic rather than geometry.
                            com.iotj.meshmore.xr.spatial.Reveal.reduced = on
                        }
                        // THE WHOLE APP, IN THE OTHER LANGUAGE, NOW.
                        //
                        // setApplicationLocales is the platform's own per-app
                        // language switch — the same one Settings drives — so
                        // this row and the OS picker cannot disagree, and what
                        // a tester sets here survives a restart because the
                        // system stores it, not us.
                        //
                        // It recreates the Activity, and that is the point
                        // rather than the price: every panel is sized from a
                        // locale-specific template when it is built and cannot
                        // be redrawn afterwards, so switching language means
                        // building the scene again. The theme, the anchor and
                        // the radio link all survive it.
                        "LANG" -> {
                            bayMode.value = "LANG"
                            appRef.value?.show(
                                langRows(ctx),
                                title = ctx.getString(R.string.t_lang),
                                footer = ctx.getString(R.string.f_lang),
                                // A SET, NOT A SEQUENCE — see Stack.show.
                                form = true,
                            )
                            cue.opened()
                            continue
                        }
                        // THE ONE THAT WIDENS WHAT THE RADIO SAYS. MeshLink
                        // stays the single gate; this only sets the flag it
                        // reads, and the refusal path is untouched.
                        "CHANSEND" -> {
                            val on = !Settings.channelSend(ctx)
                            Settings.setChannelSend(ctx, on)
                            link.channelTxAuthorised = on
                            noticeRef.value?.say(
                                ctx.getString(
                                    if (on) R.string.n_chansend_on
                                    else R.string.n_chansend_off,
                                ),
                            )
                        }
                        // TWO PINCHES, AND THE FIRST ONE COUNTS OUT LOUD.
                        //
                        // The first pinch names the number it would forget and
                        // arms; the second, within ARM_MS, sends the removals.
                        // A wearer who pinched by accident sees a count and
                        // does nothing, which is the whole point of arming a
                        // control whose effect is on the RADIO and cannot be
                        // undone from the glasses.
                        "GC" -> {
                            val here = hereSource.resolve(link.here.value, MainActivity.homeOverride)
                            val doomed = link.farContacts(here, GC_FAR_KM) {
                                tagsRef.isFavourite(it)
                            }
                            val armedNow = nowMs - gcArmedAt.value <= ARM_MS
                            when {
                                !here.known -> {
                                    // Distance is measured FROM somewhere. With
                                    // no fix every contact is equally far and
                                    // equally near, and a sweep would be a coin
                                    // toss with someone's contact list.
                                    noticeRef.value?.say(ctx.getString(R.string.n_gc_nofix))
                                    gcArmedAt.value = 0L
                                    cue.denied()
                                }
                                doomed.isEmpty() -> {
                                    noticeRef.value?.say(
                                        ctx.getString(R.string.n_gc_none, GC_FAR_KM.toInt()),
                                    )
                                    gcArmedAt.value = 0L
                                    cue.closed()
                                }
                                !armedNow -> {
                                    gcArmedAt.value = nowMs
                                    noticeRef.value?.say(
                                        ctx.getString(R.string.r_gc, GC_FAR_KM.toInt(), doomed.size),
                                    )
                                    Log.i(TAG_UI, "[gc] armed — ${doomed.size} over $GC_FAR_KM km")
                                    // Refreshed HERE and the loop continued, so
                                    // the generic refresh below cannot rebuild
                                    // this row unarmed a frame later.
                                    appRef.value?.update(
                                        appRows(ctx, link, "GC", doomed.size),
                                        ctx.getString(R.string.f_gc_arm),
                                    )
                                    cue.opened()
                                    continue
                                }
                                else -> {
                                    val n = link.forgetContacts(doomed)
                                    gcArmedAt.value = 0L
                                    noticeRef.value?.say(ctx.getString(R.string.n_gc_done, n))
                                    Log.i(TAG_UI, "[gc] swept $n of ${doomed.size} candidates")
                                    Alerts.info("CONTACTS", ctx.getString(R.string.al_swept, n))
                                    hereEpoch.value += 1
                                }
                            }
                        }
                        "FORGET" -> {
                            val n = link.msgs.value.size
                            link.forgetMessages()
                            noticeRef.value?.say(ctx.getString(R.string.n_erased, n))
                        }
                    }
                    // ARMED SURVIVES THE REFRESH. Passing null here rebuilt the
                    // row unarmed the instant it was armed, so the confirm the
                    // sweep asks for could never be given.
                    appRef.value?.update(
                        appRows(ctx, link, armed.value?.first, appGcCount()),
                        "LIT = ON    B TO CLOSE",
                    )
                    cue.recognised()
                }
                // THE THEME PICKER. A pick retints the whole scene in place —
                // including the picker's own readout, and including the HORIZON
                // behind it, which is the point (§S11: "you see your real mesh
                // restyled in place"). Persisted here rather than in the
                // surface, so one place in the app owns what choosing means.
                themePickerRef.value?.tick(stage.headNow()?.translation)
            }
            suspend fun drainThemePicker() {
                while (true) {
                    var chosen = themePickerRef.value?.poll() ?: break
                    // A LAPPED QUEUE COMMITS ONLY ITS LAST PICK. Each commit
                    // rebuilds two bays, the dock and (via the epoch) the whole
                    // ring; when picks arrive faster than commits finish, the
                    // intermediate themes are rooms the wearer has already left
                    // — and building them anyway meant disposing entities
                    // milliseconds after their async creation, which is exactly
                    // the window the renderer's placeholder-material borrow
                    // abort lives in ("OwnedPtr ... Split Engine Placeholder").
                    while (true) {
                        val next = themePickerRef.value?.poll() ?: break
                        Log.i(TAG_UI, "[theme] '${chosen.key}' superseded in queue by '${next.key}'")
                        chosen = next
                    }
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
                        if (MainActivity.switchTo == null && !MainActivity.sweep) themePrefs.set(chosen)
                        // AND THE BAYS. A plate is GEOMETRY — a frame and a
                        // slab are different meshes — so the menus need a
                        // rebuild, not a repaint, and Ink cannot do it for
                        // them. Off the frame loop, because rebuilding two
                        // stacks means suspending on material creation and this
                        // is the frame the wearer is watching for a response.
                        launch {
                            themeWork.withLock {
                            // THE SCENE-MUTATION HALF LIVES UNDER THE LOCK —
                            // ALL of it. The first fix locked only the
                            // restyles, and the sweep died at 4/9 anyway:
                            // retint(N+1), still inline, walked the material
                            // registry while restyle(N) was disposing it
                            // inside the lock ("OwnedPtr of type imp::Material
                            // ... 1 outstanding borrowed"). Tones, prefs and
                            // the picker's own state stay inline — they touch
                            // no scene material and are what the wearer needs
                            // to feel immediately.
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
                        // SURFACES FROM THE OLD WORLD CLOSE. A theme change
                        // rebuilds the world; a roster listing it in the old
                        // theme's terms — photographed still standing over
                        // BIOLUME's table — is a window into a room that no
                        // longer exists. The stacks rebuild closed via
                        // restyle; these are the ones that would linger.
                        rosterRef.value?.hide()
                        inboxRef.value?.hide()
                        threadRef.value?.hide()
                        focusRef.value?.hide()
                        nodeMenuRef.value?.hide()
                        consoleRef.value?.hide()
                        helpRef.value?.setVisible(false)
                            channelsRef.value?.restyle(chosen)
                            appRef.value?.restyle(chosen)
                            // The dock last: it reads the settings the bays
                            // above may have just rebuilt, and it is the
                            // surface the wearer reaches for first in the new
                            // theme.
                            buildDock(chosen)
                            // ARRIVING AT A TABLETOP MID-SESSION starts the
                            // table hunt that until now only a tabletop LAUNCH
                            // ran — switching into BIOLUME left the model at
                            // the assumed drop forever, remembered desk or not.
                            if (chosen.posture ==
                                com.iotj.meshmore.xr.spatial.Theme.Posture.TABLETOP &&
                                stage.planesEnabled && tableRef.value == null
                            ) {
                                tableRef.value =
                                    com.iotj.meshmore.xr.spatial.TableAnchor(session, ctx)
                                        .also { if (!it.recall()) it.seek() }
                            }
                            }
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
            }
            suspend fun drainConsole(nowMs: Long) {
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
                                radioRows(ctx, link.radio, link.clockSkewSec),
                                title = com.iotj.meshmore.xr.spatial.radioTitle(
                                    link.radio.live?.freqMhz, link.radio.live?.txDbm,
                                ),
                                footer = if (link.radio.dirty()) ctx.getString(R.string.f_pending)
                                else ctx.getString(R.string.f_radio_idle),
                                // A SET, NOT A SEQUENCE — see Stack.show.
                                form = true,
                            )
                            dockRef.value?.setLit("SETUP", false)
                            cue.opened()
                        }
                        // Not a console tile — there is no REGION pip. It is
                        // here so `--es bay REGION` can reach the list the same
                        // way a hand does, since the surface it lives behind is
                        // two pinches deep and unverifiable from a shell.
                        "REGION" -> openRegions()
                        // AND THE TWO THAT LIVE INSIDE ANOTHER BAY, for the
                        // same reason REGION is here: they are rows on the APP
                        // surface, so reaching them takes two pinches and no
                        // shell could open them at all. LANG is the surface a
                        // Japanese build is switched with — being unable to
                        // look at it from a bench is the worst possible place
                        // for that gap.
                        "TELEM" -> {
                            consoleRef.value?.hide()
                            bayMode.value = "TELEM"
                            appRef.value?.show(
                                telemetryRows(ctx, link),
                                title = ctx.getString(R.string.t_telem),
                                footer = ctx.getString(R.string.f_telem),
                                // A SET, NOT A SEQUENCE — see Stack.show.
                                form = true,
                            )
                            cue.opened()
                        }
                        "LANG" -> {
                            consoleRef.value?.hide()
                            bayMode.value = "LANG"
                            appRef.value?.show(
                                langRows(ctx),
                                title = ctx.getString(R.string.t_lang),
                                footer = ctx.getString(R.string.f_lang),
                                // A SET, NOT A SEQUENCE — see Stack.show.
                                form = true,
                            )
                            cue.opened()
                        }
                        // DIAGNOSTICS. The plate promised "connect a radio,
                        // frame log" and delivered a silent settings toggle —
                        // one spoken notice and nothing to look at. It now
                        // opens what a wearer actually comes here to find out:
                        // whether the things they sent arrived. The frame-log
                        // toggle keeps its home in the APP bay, where every
                        // other app setting is.
                        "DIAG" -> {
                            consoleRef.value?.hide()
                            bayMode.value = "TX"
                            armed.value = null
                            aboutOpen.value = false
                            appRef.value?.show(
                                txRows(ctx, link),
                                title = ctx.getString(R.string.t_tx),
                                footer = ctx.getString(R.string.f_tx),
                                // A SET, NOT A SEQUENCE — see Stack.show.
                                form = true,
                            )
                            dockRef.value?.setLit("SETUP", false)
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
                                channelRows(ctx, link, voice, null),
                                title = ctx.getString(R.string.t_channels),
                                footer = if (link.channels().isEmpty())
                                    ctx.getString(R.string.f_chan_no_radio)
                                else chanFooter(ctx, null),
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
                                appRows(ctx, link, armed.value?.first, appGcCount()),
                                // THE STATE AS A WORD, NOT AN ENUM NAME. This
                                // title interpolated SessionState.name, so a
                                // Japanese wearer read "アプリ — 接続:
                                // DISCONNECTED" — a localised sentence with an
                                // untranslated identifier inside it. Nothing
                                // measures that: the string fits its plate and
                                // the parity test compares resources, and the
                                // gap is in the value the app supplies at
                                // runtime rather than in either file.
                                title = ctx.getString(R.string.t_app, linkWord(ctx, link)),
                                footer = ctx.getString(R.string.f_app),
                                // A SET, NOT A SEQUENCE — see Stack.show.
                                form = true,
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
                                aboutRows(ctx, link),
                                title = ctx.getString(R.string.t_about),
                                footer = ctx.getString(R.string.f_about),
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
                                noticeRef.value?.say(ctx.getString(R.string.n_not_tracking))
                            } else {
                                consoleRef.value?.hide()
                                themePickerRef.value?.showAt(
                                    h.translation, yawOf(h), skin.value,
                                )
                                dockRef.value?.setLit("SETUP", false)
                                cue.opened()
                            }
                        }
                        // A DOCK PIP IS A BAY TOO, and it is tried before
                        // giving up. INBOX, LIST and FIND are pips rather than
                        // console tiles, so no flag reached them and they could
                        // only be opened by a hand inside the glasses — which
                        // is how the inbox came to be rewriting every row
                        // fifteen times a second for however long that had been
                        // true. Firing the dock's own action runs exactly what
                        // a pinch runs, rather than a copy of it that can drift.
                        //
                        // HONEST ABOUT WHAT IS NOT BUILT, when it is neither. A
                        // plate that opens nothing and says nothing reads as a
                        // fault; one that says so reads as a roadmap.
                        else -> if (dockRef.value?.fire(bay) != true) {
                            noticeRef.value?.say(ctx.getString(R.string.n_not_built, bay))
                            cue.closed()
                        }
                    }
                }
            }
            suspend fun drainInbox() {
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
                                who = whoLine(com.iotj.meshmore.xr.spatial.TypeTier.clip(
                                        m.fromName.ifBlank { t.title }, 14,
                                    ), ago(ctx, nowS - m.atEpochSec)),
                                words = com.iotj.meshmore.xr.spatial.TypeTier.clip(m.text, 24),
                                mine = m.direct,
                            )
                        },
                    )
                    inboxRef.value?.hide()
                    cue.opened()
                }
            }
            suspend fun frameGestures(nowMs: Long) {
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
                        dockRef.value?.setLit("FIND", query.value.active)
                        cue.closed()
                        Log.i(TAG_UI, "[hand] $hand:B — find closed, query ${query.value}")
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
                    // IN A TABLETOP, RESET RESETS THE TABLE. The measured
                    // anchor beats the origin on purpose, so a recentre alone
                    // cannot rescue a model the anchor has put somewhere wrong
                    // — which is exactly when a wearer reaches for this
                    // gesture. H says "this is wrong, put it back in front of
                    // me": the live lock clears (the model re-places at the
                    // assumed drop immediately), the remembered anchor is
                    // forgotten, and the search runs again on this room.
                    if (skin.value.posture ==
                        com.iotj.meshmore.xr.spatial.Theme.Posture.TABLETOP &&
                        horizonRef.value?.tableAt != null
                    ) {
                        horizonRef.value?.tableAt = null
                        tableRef.value?.rejectAndReseek()
                        noticeRef.value?.say(ctx.getString(R.string.n_table_reset))
                    }
                    hereEpoch.value += 1
                    cue.opened()
                    noticeRef.value?.say(
                // NAMES WHAT MOVED. "VIEW RESET" reads as an undo — as though
                // something were being put back — when what happened is that
                // the scene picked itself up and re-centred on the wearer.
                ctx.getString(
                    if (northKnown) R.string.n_scene_moved
                    else R.string.n_scene_moved_nonorth,
                ),
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
            }
            suspend fun drainFocus() {
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
                        f.hide()
                        nodeMenuRef.value?.hide()
                        cue.closed()
                    } else {
                        f.showFor(n, p, head)
                        // THE VERBS, BESIDE THE CARD — the dock already taught
                        // this: a menu that opens on the thing it is about
                        // covers the thing it is about. The first cut lifted it
                        // 0.16 m and the spokes still printed through the
                        // card's name (photographed); the menu's spread is
                        // distance-scaled and a vertical lift large enough to
                        // clear it drifts the top spokes out of the field. So
                        // it opens to the RIGHT of the node as seen — sideways
                        // is the one direction the card does not grow.
                        // Only nodes with an identity get verbs — a cluster
                        // pseudo-node has no key to act on.
                        if (n.key.isNotEmpty()) {
                            val dx = p.x - head.x
                            val dz = p.z - head.z
                            val len = kotlin.math.sqrt(dx * dx + dz * dz)
                                .coerceAtLeast(1e-4f)
                            nodeMenuRef.value?.showAt(
                                Vector3(
                                    p.x - (dz / len) * NODE_MENU_SIDE,
                                    p.y + NODE_MENU_LIFT,
                                    p.z + (dx / len) * NODE_MENU_SIDE,
                                ),
                                n,
                            )
                        }
                        cue.opened()
                    }
                }
                // THE NODE MENU'S ANSWER. Every verb confirms in the notice
                // band, because half of these act on things (radio, storage)
                // whose change is not otherwise visible from the ring.
                while (true) {
                    val choice = nodeMenuRef.value?.poll() ?: break
                    val n = nodeMenuRef.value?.subject as? Horizon.Node ?: break
                    val id = n.fullKey ?: n.key
                    when (choice) {
                        "fav" -> {
                            val now = tagsRef.toggleFavourite(id)
                            tagEpoch.value += 1
                            noticeRef.value?.say(
                                ctx.getString(
                                    if (now) R.string.n_starred else R.string.n_unstarred,
                                    com.iotj.meshmore.xr.spatial.TypeTier.clip(n.name, 18),
                                ),
                            )
                            if (now) cue.opened() else cue.closed()
                        }
                        "msg" -> {
                            // THE ALLOW-LIST, POLITELY. MeshLink refuses the
                            // transmit anyway; this is the same rule applied
                            // before a surface opens, so a compose the app
                            // will not send from never appears.
                            if (!link.mayMessage(n.name, n.fullKey)) {
                                noticeRef.value?.say(ctx.getString(R.string.n_send_locked))
                                cue.denied()
                            } else {
                                val t = link.threads().firstOrNull { th ->
                                    th.direct && (
                                        (n.fullKey ?: "").startsWith(th.id, true) ||
                                            th.id.startsWith(n.key, true)
                                        )
                                }
                                val h = stage.headNow()
                                if (t == null) {
                                    // NO THREAD IS NOT A REFUSAL ANY MORE.
                                    // "NO THREAD YET" was the app describing
                                    // its own missing feature as though it
                                    // were a fact about the mesh. Address the
                                    // node: the crown opens on compose, the
                                    // canned openers and dictation are already
                                    // there, and CONFIRM sends to this key.
                                    crownRef.value?.let { c ->
                                        c.target = com.iotj.meshmore.xr.spatial.Crown.Target(
                                            n.fullKey ?: n.key, n.name,
                                        )
                                        // STRAIGHT TO THE WORDS. show() alone
                                        // lands on ACTIONS — read aloud, open
                                        // the thread, toggle this
                                        // conversation's voice — every one of
                                        // which is about a conversation that
                                        // does not exist yet. And it must be
                                        // said even when the crown is already
                                        // up for the reel, which is the state
                                        // it was in the first time this was
                                        // tried.
                                        c.show()
                                        c.compose()
                                        c.say(
                                            ctx.getString(
                                                R.string.n_dm_to,
                                                com.iotj.meshmore.xr.spatial.TypeTier.clip(n.name, 14),
                                            ),
                                            android.os.SystemClock.uptimeMillis(),
                                        )
                                        focusRef.value?.hide()
                                        cue.opened()
                                        Log.i(TAG_UI, "[dm] composing to '${n.name}' key=${n.key}")
                                    }
                                } else if (h == null) {
                                    cue.closed()
                                } else {
                                    val nowS = System.currentTimeMillis() / 1000
                                    threadRef.value?.showAt(
                                        h.translation, yawOf(h), t.id, t.title,
                                        t.messages.map { m ->
                                            com.iotj.meshmore.xr.spatial.Thread.Line(
                                                who = whoLine(
                                                    com.iotj.meshmore.xr.spatial.TypeTier.clip(
                                                        m.fromName.ifBlank { t.title }, 14,
                                                    ),
                                                    // WHAT BECAME OF IT, on the
                                                    // line that already carries
                                                    // who and when. Only for
                                                    // messages we sent; nothing
                                                    // is claimed about anyone
                                                    // else's.
                                                    deliveryMark(ctx, m)
                                                        .ifEmpty {
                                                            ago(ctx, nowS - m.atEpochSec)
                                                        },
                                                ),
                                                words = com.iotj.meshmore.xr.spatial.TypeTier
                                                    .clip(m.text, 24),
                                                mine = m.direct,
                                            )
                                        },
                                        // WHO THIS IS WITH, so the corridor's
                                        // REPLY knows where to send.
                                        peer = (n.fullKey ?: n.key) to n.name,
                                    )
                                    focusRef.value?.hide()
                                    cue.opened()
                                }
                            }
                        }
                        // ARMED, LIKE EVERY OTHER REMOVAL. The menu has no
                        // arming of its own, so the state lives here: the first
                        // pinch names the node and waits, the second within
                        // ARM_MS forgets it. A radial spoke is easy to catch
                        // with a stray hand and this one talks to the radio.
                        "forget" -> {
                            val peer = link.mesh.value.firstOrNull {
                                (it.fullKey ?: it.key).equals(id, ignoreCase = true) ||
                                    it.key.equals(n.key, ignoreCase = true)
                            }
                            val tNow = android.os.SystemClock.uptimeMillis()
                            val armedNow = nodeForget.value?.let {
                                it.first == id && tNow - it.second <= ARM_MS
                            } == true
                            when {
                                peer == null -> {
                                    noticeRef.value?.say(ctx.getString(R.string.n_forget_unknown))
                                    cue.denied()
                                }
                                link.forgettable(listOf(peer)) {
                                    tagsRef.isFavourite(it)
                                }.isEmpty() -> {
                                    // Own node, favourite, or no full key. The
                                    // refusal is the same rule the sweep uses,
                                    // said out loud rather than silently.
                                    noticeRef.value?.say(ctx.getString(R.string.n_forget_kept))
                                    cue.denied()
                                }
                                !armedNow -> {
                                    nodeForget.value = id to tNow
                                    noticeRef.value?.say(
                                        ctx.getString(
                                            R.string.n_forget_arm,
                                            com.iotj.meshmore.xr.spatial.TypeTier.clip(n.name, 14),
                                        ),
                                    )
                                    cue.opened()
                                }
                                else -> {
                                    nodeForget.value = null
                                    val ok = link.forgetContact(peer)
                                    noticeRef.value?.say(
                                        ctx.getString(
                                            if (ok) R.string.n_forget_done
                                            else R.string.n_forget_failed,
                                            com.iotj.meshmore.xr.spatial.TypeTier.clip(n.name, 14),
                                        ),
                                    )
                                    if (ok) {
                                        hereEpoch.value += 1
                                        cue.recognised()
                                    } else {
                                        cue.denied()
                                    }
                                }
                            }
                        }
                        "telem" -> {
                            val ok = link.askTelemetry(n.fullKey)
                            noticeRef.value?.say(
                                if (ok) {
                                    ctx.getString(
                                        R.string.n_asked_telem,
                                        com.iotj.meshmore.xr.spatial.TypeTier.clip(n.name, 16),
                                    )
                                } else {
                                    ctx.getString(R.string.n_radio_not_ready)
                                },
                            )
                            if (ok) cue.recognised() else cue.denied()
                        }
                    }
                    nodeMenuRef.value?.hide()
                }
            }
            suspend fun drainMenu() {
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
                                if (near.isEmpty()) ctx.getString(R.string.n_nothing_there)
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

            }
            suspend fun tickStatus() {

                // Link readout, refreshed about once a second. The strings are
                // short on purpose: the microhud answers "is the radio there
                // and how much of the mesh do I hold", not everything about it.
                statusTick += 0.033f
                if (statusTick > 1f) {
                    statusTick = 0f
                    // THE EMPTY RADAR EXPLAINS ITSELF. Shown only before the
                    // first-ever link: after a drop, LOST-and-reconnecting owns
                    // the story. Hidden while a scan runs, so the card itself
                    // shows the search happening.
                    run {
                        val st2 = link.status.value
                        // TWO WAYS TO DRAW NOTHING, and the radio question
                        // comes first: with no radio there is no position
                        // question to answer.
                        val waiting = unplacedRef.value
                        // A FULL STORE IS AN ALERT, NOT A CARD.
                        //
                        // Two conditions earn a surface in the world — no radio
                        // and no position — because both stop the app doing the
                        // thing it exists for. A full contact store does not:
                        // it explains why a node never appeared, it wants
                        // acting on eventually, and standing it in front of a
                        // wearer who is doing something else reads as an alarm.
                        // It goes where the radio log goes, and that is off
                        // unless asked for.
                        if (st2.maxContacts > 0 && st2.heldByRadio >= st2.maxContacts) {
                            Alerts.warn(
                                "CONTACTS",
                                ctx.getString(R.string.al_full, st2.heldByRadio, st2.maxContacts),
                            )
                        }
                        val kind = when {
                            !link.everConnected && !st2.scanning && st2.error != null ->
                                com.iotj.meshmore.xr.spatial.Advice.Kind.NO_RADIO
                            waiting > 0 ->
                                com.iotj.meshmore.xr.spatial.Advice.Kind.NO_FIX
                            else -> com.iotj.meshmore.xr.spatial.Advice.Kind.NONE
                        }
                        // THE FRAME LOOP DECIDES AND THE EFFECT BUILDS.
                        // A PanelEntity created from this coroutine is created
                        // and never attached — see Advice.say.
                        adviceKind.value = kind
                        val hunting = kind == com.iotj.meshmore.xr.spatial.Advice.Kind.NO_RADIO
                        val nowW = android.os.SystemClock.uptimeMillis()
                        // The retry clock starts when the card first SHOWS —
                        // at zero it fired instantly, so the card flashed for
                        // one frame and hid behind a scan it had not asked
                        // for. A card that appears must stand long enough to
                        // be read; thirty seconds is also about how long a
                        // person needs to walk over and switch a radio on.
                        if (hunting && adviceLastTry == 0L) adviceLastTry = nowW
                        if (adviceRef.value?.poll() == true) {
                            cue.recognised()
                            if (kind == com.iotj.meshmore.xr.spatial.Advice.Kind.NO_FIX) {
                                useHeadsetFix()
                            } else {
                                adviceTries = 0
                                adviceLastTry = nowW
                                link.connect()
                            }
                        } else if (hunting && adviceTries < NO_RADIO_AUTO_TRIES &&
                            nowW - adviceLastTry > NO_RADIO_RETRY_MS
                        ) {
                            adviceTries++
                            adviceLastTry = nowW
                            Log.i(TAG_UI, "[advice] auto-rescan $adviceTries/$NO_RADIO_AUTO_TRIES")
                            link.connect()
                        }
                    }
                    // WHERE YOU ARE vs WHAT THE RADIO IS SET TO — checked once
                    // per session, on the 1 Hz tick, as soon as both facts
                    // exist. The Giteki disclaimer says presets are not
                    // legality; this is the moment that paragraph becomes a
                    // behaviour: land in a country the preset does not cover
                    // and the app says so and opens the region list. The bay
                    // auto-opens once per DISTINCT mismatch (acknowledged by
                    // closing it); the notice repeats each boot, because a
                    // radio transmitting on the wrong band is worth a line a
                    // day and not worth a surface a day.
                    if (!regionChecked) {
                        val live = link.radio.live
                        val h = hereSource.here.value
                        if (live != null && h.known) {
                            regionChecked = true
                            val set = Regions.match(live)
                            val here2 = Regions.suggest(h.lat, h.lon)
                            if (here2 != null && set?.id != here2.id) {
                                val pair = (set?.id ?: "CUSTOM") + ">" + here2.id
                                // THE BAND SAYS THE SHORT TRUE THING, and the
                                // list that opens behind it names both regions.
                                // Naming them here cost the sentence its second
                                // half in Japanese, where the band is 30 cells
                                // and two region labels are fifty — and the
                                // half that went missing was where the wearer
                                // actually is.
                                noticeRef.value?.say(
                                    ctx.getString(R.string.n_region_mismatch),
                                )
                                cue.denied()
                                Log.w(TAG_UI, "[region] mismatch: radio=" +
                                    (set?.id ?: "custom") + " here=${here2.id}")
                                if (Settings.regionAck(ctx) != pair) {
                                    Settings.setRegionAck(ctx, pair)
                                    openRegions()
                                }
                            } else {
                                Log.i(TAG_UI, "[region] ok: ${set?.id ?: "custom"}")
                            }
                        }
                    }
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
            }
            suspend fun tickBoot() {
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
                if (boot0StartMs == 0L) boot0StartMs = android.os.SystemClock.uptimeMillis()
                boot0Elapsed = (android.os.SystemClock.uptimeMillis() - boot0StartMs) / 1000f
                val loading = boot0Elapsed < MAX_BOOT_S &&
                    (!load.done || boot0Elapsed < MIN_BOOT_S)
                if (loading) {
                    bootRef.value?.tick(load.fraction, load.total > 0)
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
                    // THE SCENE IS THE PLACE A VOICE CAN BE ANSWERED. Until
                    // here there is nowhere to look when the app speaks.
                    bootOver.value = true
                }
            }
            fun tickEarth() {
                if (!MainActivity.probeEarth || !stage.geoEnabled) return
                com.iotj.meshmore.xr.spatial.Earth.probe(
                    session, android.os.SystemClock.uptimeMillis(),
                )
            }
            suspend fun tickHead() {
                stage.headNow()?.let {
                    horizon.faceViewer(it.translation)
                    // Callsigns give way to the microhud bands where they cross.
                    // ONE FOCUS AT A TIME (§2.1 rule 3). Set before veil, which
                    // is what actually writes the alphas.
                    // Either FOCUS surface quiets the ring's names — §2.1 rule
                    // 3 is about how many things can hold the text layer, not
                    // about which one happens to be up.
                    //
                    // AND EVERY OTHER SURFACE MADE OF WORDS, which is the fix
                    // for green message text printed through cyan callsigns.
                    // The inbox, the roster and a thread all open at 1.4 m,
                    // INSIDE the 2.5 m ring, so the ring is directly behind
                    // them — two layers of text at different depths, both lit,
                    // and on an additive display neither occludes the other.
                    // The eye cannot separate them and the reader loses both.
                    //
                    // The rule was already written and only two surfaces had
                    // been told about it. It is not "focus recesses the ring",
                    // it is "one thing holds the text layer at a time".
                    horizon.setRecessed(
                        menuRef.value?.open == true ||
                            focusRef.value?.open == true ||
                            inboxRef.value?.open == true ||
                            rosterRef.value?.open == true ||
                            threadRef.value?.open == true,
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
                    nodeMenuRef.value?.tick(it.translation)
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
            }
            suspend fun tickGaze(nowMs: Long) {
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
            }
            suspend fun drainSmall(nowMs: Long) {
                // Show the dwelled pip's caption. Same focus state a pointer
                // produces, so the two input paths look identical as well as
                // firing identically.
                dockRef.value?.gazed = gazeRef.value?.onTarget
                consoleRef.value?.setGazed(gazeRef.value?.onTarget)
                themePickerRef.value?.setGazed(gazeRef.value?.onTarget)
                // Paging the corridor further back. One code path owns it: the
                // surface reports a pick, the host decides what a pick means.
                while (true) {
                    val t = threadRef.value?.poll() ?: break
                    if (t == com.iotj.meshmore.xr.spatial.Thread.REPLY) {
                        // THE OTHER HALF OF "MESSAGE". Reading a conversation
                        // and being unable to answer it is what got reported as
                        // a no-op: the verb opened the corridor, the corridor
                        // had no way out, and the only compose in the app was
                        // on the reel's crown — which is about the message
                        // under the wrist cursor, not about the node you are
                        // looking at.
                        val key = threadRef.value?.peerKey
                        val who = threadRef.value?.peerName.orEmpty()
                        if (key == null) {
                            cue.denied()
                        } else {
                            crownRef.value?.let { c ->
                                c.target = com.iotj.meshmore.xr.spatial.Crown.Target(key, who)
                                c.show()
                                c.compose()
                                c.say(
                                    ctx.getString(
                                        R.string.n_dm_to,
                                        com.iotj.meshmore.xr.spatial.TypeTier.clip(who, 14),
                                    ),
                                    android.os.SystemClock.uptimeMillis(),
                                )
                                Log.i(TAG_UI, "[dm] replying to '$who' from the thread")
                                cue.opened()
                            }
                        }
                    } else {
                        threadRef.value?.older()
                    }
                }
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
                        noticeRef.value?.say(ctx.getString(R.string.n_chan_quiet))
                        cue.closed()
                        null
                    } ?: continue
                    val nowS = System.currentTimeMillis() / 1000
                    threadRef.value?.showAt(
                        h.translation, yawOf(h), t.id, t.title,
                        t.messages.map { m ->
                            com.iotj.meshmore.xr.spatial.Thread.Line(
                                who = whoLine(com.iotj.meshmore.xr.spatial.TypeTier.clip(
                                        m.fromName.ifBlank { t.title }, 14,
                                    ), ago(ctx, nowS - m.atEpochSec)),
                                words = com.iotj.meshmore.xr.spatial.TypeTier.clip(m.text, 24),
                                mine = m.direct,
                            )
                        },
                    )
                    cue.opened()
                }
            }
            suspend fun tickPulse() {
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
            // ONE FRAME. Everything the loop does, as its own method —
            // the outer state machine keeps only the delay and this call.
            // THREE HUBS, NOT ONE — and the reason is the CLOSURE TAX.
            //
            // A local function's captures are passed as parameters, so a hub
            // that calls every helper receives every helper's captures — and a
            // suspend hub then spills that whole set at each of its ~25 resume
            // points. One frameTick calling everything measured 20,278 code
            // units while every body it called was under 600. Three hubs of
            // ~7 suspend sites each keep the product small.
            suspend fun frameSurfaces(nowMs: Long) {
                tickBoot()
                tickHead()
                tickEarth()
                tickGaze(nowMs)
                tickReel(nowMs)
                drainSmall(nowMs)
                sayLinkStep()
            }
            suspend fun frameBays(nowMs: Long) {
                channelsRef.value?.tick(
                    stage.headNow()?.translation,
                    stage.headNow()?.let { yawOf(it) } ?: 0f,
                )
                drainChannels(nowMs)
                drainAppBay(nowMs)
                drainThemePicker()
                // a frame is cheaper than making that safe.
                tableRef.value?.let { t ->
                    if (t.poll()) {
                        // A TABLE IS BELOW YOUR EYES AND WITHIN REACH, or it is
                        // not a table. A persisted anchor re-localising against
                        // a stale tracking map can resolve ANYWHERE — the
                        // reported case rendered BIOLUME on the ceiling, and
                        // because the measured table beats the origin by
                        // design, no recentre could undo it. Adopt only a
                        // plausible pose; reject the rest and search the room
                        // that exists.
                        val head = stage.headNow()?.translation
                        val at = t.at
                        val dy = if (head != null && at != null) head.y - at.y else null
                        val dh = if (head != null && at != null) {
                            val dx = at.x - head.x
                            val dz = at.z - head.z
                            kotlin.math.sqrt(dx * dx + dz * dz)
                        } else {
                            null
                        }
                        if (dy != null && dh != null && dy in 0.25f..1.6f && dh <= 2.5f) {
                            horizonRef.value?.tableAt = at
                            hereEpoch.value += 1
                        } else {
                            Log.w(
                                TAG_UI,
                                "[table] REJECTED anchor at dy=%s dh=%s — not a table"
                                    .format(dy?.toString() ?: "?", dh?.toString() ?: "?"),
                            )
                            t.rejectAndReseek()
                        }
                    }
                }
                drainConsole(nowMs)
                drainInbox()
            }
            suspend fun frameActions(nowMs: Long) {
                frameGestures(nowMs)
                horizon.drainSelections(origin)
                drainFocus()
                drainMenu()
                tickStatus()
                horizon.tick(0.033f)
                tickPulse()
            }
            suspend fun frameTick() {
                val nowMs = android.os.SystemClock.uptimeMillis()
                frameSurfaces(nowMs)
                frameBays(nowMs)
                frameActions(nowMs)
            }
            while (true) {
                delay(33)
                frameTick()
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
                SubspaceModifier.width(620.dp).height(460.dp)
                    .offset(x = 320.dp, y = (-60).dp, z = 260.dp)
                    .rotate(0f, -22f, 0f),
            ) {
                // The panel composes under the ACTIVITY context; provide the
                // localised one so stringResource follows --es lang.
                androidx.compose.runtime.CompositionLocalProvider(
                    androidx.compose.ui.platform.LocalContext provides ctx,
                ) {
                SearchSurface(
                    query = query.value,
                    onQuery = { query.value = it },
                    // WHAT THE QUERY FINDS, not what the ring drew. The ring
                    // caps at 24 (12 on a tabletop) and clusters the rest, so
                    // listing its output would hide most of a wide match — and
                    // the list is the one place the whole answer fits.
                    matches = remember(query.value, mesh, tagEpoch.value, hereEpoch.value) {
                        val from = hereSource.resolve(link.here.value, MainActivity.homeOverride)
                        val nowS = System.currentTimeMillis() / 1000
                        Search.apply(
                            mesh, query.value,
                            isFavourite = {
                                it.favourite || tagsRef.isFavourite(it.fullKey ?: it.key)
                            },
                            tagsOf = { tagsRef.tagsFor(it.fullKey ?: it.key) },
                            // NULL WHERE NOBODY KNOWS, in both of these. The
                            // filter treats null as "does not match" rather
                            // than as far or as stale, so an unplaceable node
                            // is never selected by a distance sweep and a node
                            // with no timestamp is never selected as silent.
                            distanceKm = { p ->
                                val la = p.lat
                                val lo = p.lon
                                if (!from.known || la == null || lo == null ||
                                    (kotlin.math.abs(la) < 1e-7 && kotlin.math.abs(lo) < 1e-7)
                                ) {
                                    null
                                } else {
                                    MeshNodes.haversineKm(from.lat!!, from.lon!!, la, lo)
                                }
                            },
                            ageHours = { p ->
                                if (p.lastSeenEpochSec <= 0L) null
                                else (nowS - p.lastSeenEpochSec).coerceAtLeast(0L) / 3600.0
                            },
                        )
                    },
                    total = mesh.size,
                    tags = remember(tagEpoch.value) { tagsRef.allTags() },
                    // A SET, NOT A LAMBDA — and the difference is whether the
                    // star moves. A lambda's answer changing is invisible to
                    // Compose: nothing in the row's inputs changed, so the row
                    // skipped recomposition and the star sat unfilled while
                    // the favourite was real everywhere else ("doesn't toggle
                    // visually, but appears to actually work"). A set rebuilt
                    // per tagEpoch is a new identity per toggle, which is the
                    // signal skipping listens to.
                    starred = remember(tagEpoch.value, mesh) {
                        mesh.filter {
                            it.favourite || tagsRef.isFavourite(it.fullKey ?: it.key)
                        }.map { it.fullKey ?: it.key }.toSet()
                    },
                    tagsOf = { tagsRef.tagsFor(it.fullKey ?: it.key) },
                    onStar = {
                        val now = tagsRef.toggleFavourite(it.fullKey ?: it.key)
                        tagEpoch.value += 1
                        Log.i(TAG_UI, "[find] ${it.name} favourite=$now")
                        if (now) cue.opened() else cue.closed()
                    },
                    onTag = { p, t ->
                        if (t.isNotBlank()) {
                            tagsRef.add(p.fullKey ?: p.key, t)
                            tagEpoch.value += 1
                            Log.i(TAG_UI, "[find] ${p.name} tagged '$t'")
                            cue.recognised()
                        }
                    },
                    onUntag = { p, t ->
                        tagsRef.remove(p.fullKey ?: p.key, t)
                        tagEpoch.value += 1
                        cue.closed()
                    },
                    forgettable = remember(query.value, mesh, tagEpoch.value, hereEpoch.value) {
                        if (!query.value.isSweepable) 0
                        else link.forgettable(matchedForSweep(link, mesh, query.value, tagsRef, hereSource)) {
                            tagsRef.isFavourite(it)
                        }.size
                    },
                    onForget = {
                        val doomed = link.forgettable(
                            matchedForSweep(link, mesh, query.value, tagsRef, hereSource),
                        ) { tagsRef.isFavourite(it) }
                        val n = link.forgetContacts(doomed)
                        Log.i(TAG_UI, "[gc] filter forgot $n of ${doomed.size}")
                        Alerts.info("CONTACTS", ctx.getString(R.string.al_swept, n))
                        noticeRef.value?.say(ctx.getString(R.string.n_gc_done, n))
                        hereEpoch.value += 1
                        tagEpoch.value += 1
                    },
                    onClose = { searchOpen.value = false },
                )
                }
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
    query: Search.Query,
    onQuery: (Search.Query) -> Unit,
    matches: List<MeshNodes.Peer>,
    total: Int,
    tags: List<String>,
    starred: Set<String>,
    tagsOf: (MeshNodes.Peer) -> List<String>,
    onStar: (MeshNodes.Peer) -> Unit,
    onTag: (MeshNodes.Peer, String) -> Unit,
    onUntag: (MeshNodes.Peer, String) -> Unit,
    onClose: () -> Unit,
    /**
     * How many of [matches] this app would actually forget, and the act of
     * doing it. Zero hides the control entirely — a destructive button that
     * does nothing is worse than no button, and with the exclusions in place
     * (own nodes, favourites) a filter can easily match forty and forget none.
     */
    forgettable: Int = 0,
    onForget: () -> Unit = {},
) {
    val focus = remember { FocusRequester() }
    // The panel wears the app's one face (see meshMono) — the ring outside
    // this window is set in the same file, and a search that types in a
    // different typeface than the mesh it filters reads as another app.
    androidx.compose.runtime.CompositionLocalProvider(
        LocalTextStyle provides LocalTextStyle.current.copy(
            fontFamily = meshMono(androidx.compose.ui.platform.LocalContext.current),
        ),
    ) {
    // THE KEYBOARD COMES UP WITH THE PANEL. A search you have to tap into
    // before you can type is a search with an extra step that exists only
    // because nobody asked for the focus.
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    // Which row is having a tag typed into it. One at a time: the keyboard is
    // one keyboard, and two open fields would be a race for it.
    val tagging = remember { mutableStateOf<String?>(null) }
    val draft = remember { mutableStateOf("") }
    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xE0121820))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        OutlinedTextField(
            value = query.text,
            onValueChange = { onQuery(query.copy(text = Search.normalise(it))) },
            singleLine = true,
            placeholder = { Text(androidx.compose.ui.res.stringResource(R.string.find_hint), color = Color(0xFF6E7C88)) },
            textStyle = LocalTextStyle.current.copy(color = Color(0xFFDDE7EF), fontSize = 20.sp),
            modifier = Modifier.fillMaxWidth().focusRequester(focus),
        )
        // THE MARKS, AS CHIPS. "I can't remember the names or UIDs of my
        // friend's nodes" — so the two things a person DOES remember get to be
        // one tap each, and neither of them requires typing anything.
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Chip(androidx.compose.ui.res.stringResource(R.string.find_favs), query.favourites) {
                onQuery(query.copy(favourites = !query.favourites))
            }
            // DISTANCE AND SILENCE, AS STEPS RATHER THAN SWITCHES.
            //
            // "In a busy environment we rapidly fill up the device contacts
            // list and it becomes impossible to see new nodes." Both of these
            // cycle through their thresholds and then off, because the right
            // number depends on the mesh you are standing in: 25 km is a city,
            // 250 km is a mountain range, and a fixed value would be wrong in
            // one of those places.
            Chip(
                query.farKm?.let { "≥ ${it.toInt()} KM" }
                    ?: androidx.compose.ui.res.stringResource(R.string.find_far),
                query.farKm != null,
            ) {
                val i = Search.FAR_STEPS.indexOf(query.farKm)
                onQuery(query.copy(farKm = Search.FAR_STEPS.getOrNull(i + 1)))
            }
            Chip(
                query.staleHours?.let { h ->
                    if (h >= 24) "≥ ${h / 24} D" else "≥ $h H"
                } ?: androidx.compose.ui.res.stringResource(R.string.find_stale),
                query.staleHours != null,
            ) {
                val i = Search.STALE_STEPS.indexOf(query.staleHours)
                onQuery(query.copy(staleHours = Search.STALE_STEPS.getOrNull(i + 1)))
            }
            tags.forEach { t ->
                Chip("#$t", query.tag.equals(t, ignoreCase = true)) {
                    // Tapping the live tag clears it. A chip that can only be
                    // turned on needs a second control to turn it off, and the
                    // one people try first is the chip.
                    onQuery(query.copy(tag = if (query.tag.equals(t, true)) null else t))
                }
            }
        }
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                // Localised here rather than in Search: the object stays pure
                // (its summary is pinned by tests and used in logs) and the
                // panel says the same thing in the wearer's language.
                when {
                    !query.active -> androidx.compose.ui.res.stringResource(R.string.find_all, total)
                    matches.isEmpty() -> androidx.compose.ui.res.stringResource(R.string.find_none, total)
                    else -> androidx.compose.ui.res.stringResource(R.string.find_some, matches.size, total)
                },
                color = if (matches.isEmpty() && query.active) {
                    Color(0xFFFF6B6B)
                } else {
                    Color(0xFFDDE7EF)
                },
                fontSize = 15.sp,
            )
            // CLEARING AND CLOSING ARE DIFFERENT ACTS, and both are needed: the
            // query outlives the panel on purpose, so without a CLEAR the only
            // way back to the whole mesh would be to reopen the panel and undo
            // every term by hand.
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                // THE FILTER IS THE SELECTION.
                //
                // No checkboxes, no marked list to lose track of: you narrow
                // with the chips until the count reads right, and this forgets
                // exactly the set the panel is showing. The ring behind the
                // panel is drawn from the same filter, so the thing being
                // destroyed is on screen the whole time.
                //
                // Shown only when the filter is ABOUT which nodes (distance or
                // silence) rather than about a name — bulk-forgetting a text
                // search is a way to delete half a mesh by typing "a" — and
                // only when something in it is actually forgettable.
                if (query.isSweepable && forgettable > 0) {
                    val armed = remember { mutableStateOf(false) }
                    TextButton(onClick = {
                        if (armed.value) { armed.value = false; onForget() } else armed.value = true
                    }) {
                        Text(
                            if (armed.value) {
                                androidx.compose.ui.res.stringResource(R.string.find_forget_arm)
                            } else {
                                androidx.compose.ui.res.stringResource(
                                    R.string.find_forget, forgettable,
                                )
                            },
                            color = if (armed.value) Color(0xFFFF6B6B) else Color(0xFFFFB86B),
                            fontSize = 14.sp,
                        )
                    }
                }
                TextButton(onClick = { onQuery(Search.Query()) }) {
                    Text(androidx.compose.ui.res.stringResource(R.string.find_clear), color = Color(0xFF66E8D0), fontSize = 14.sp)
                }
                TextButton(onClick = onClose) {
                    Text(androidx.compose.ui.res.stringResource(R.string.find_done), color = Color(0xFF66E8D0), fontSize = 14.sp)
                }
            }
        }
        // THE LIST IS WHERE MARKS GET MADE. Starring from the ring would mean
        // finding the node in the ring first, which is the thing you cannot do
        // — that is why you are here. So the matches are listed, and each row
        // carries the two acts that make it findable next time.
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            matches.take(FIND_ROWS).forEach { p ->
                val id = p.fullKey ?: p.key
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    val fav = (p.fullKey ?: p.key) in starred
                    TextButton(onClick = { onStar(p) }) {
                        Text(
                            if (fav) "★" else "☆",
                            color = if (fav) Color(0xFFD7FF00) else Color(0xFF6E7C88),
                            fontSize = 20.sp,
                        )
                    }
                    Column(Modifier.weight(1f)) {
                        Text(
                            p.name.ifBlank { p.key },
                            color = Color(0xFFDDE7EF),
                            fontSize = 16.sp,
                            maxLines = 1,
                        )
                        val own = tagsOf(p)
                        if (own.isNotEmpty()) {
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                own.forEach { t ->
                                    // Tapping your own tag on a node removes it.
                                    // The only other place it could live is a
                                    // second menu, for an act that is one tap
                                    // and always undoable by retyping it.
                                    TextButton(onClick = { onUntag(p, t) }) {
                                        Text("#$t", color = Color(0xFF66E8D0), fontSize = 13.sp)
                                    }
                                }
                            }
                        }
                    }
                    TextButton(onClick = {
                        tagging.value = if (tagging.value == id) null else id
                        draft.value = ""
                    }) {
                        Text(androidx.compose.ui.res.stringResource(R.string.find_tag), color = Color(0xFF66E8D0), fontSize = 13.sp)
                    }
                }
                if (tagging.value == id) {
                    OutlinedTextField(
                        value = draft.value,
                        onValueChange = { draft.value = it.take(NodeTags.TAG_MAX) },
                        singleLine = true,
                        placeholder = { Text(androidx.compose.ui.res.stringResource(R.string.find_tag_hint), color = Color(0xFF6E7C88)) },
                        textStyle = LocalTextStyle.current
                            .copy(color = Color(0xFFDDE7EF), fontSize = 16.sp),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = {
                            onTag(p, draft.value.trim())
                            draft.value = ""
                            tagging.value = null
                        }),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
            if (matches.size > FIND_ROWS) {
                // SAID, NEVER SILENT. A list that stops at fifteen without
                // saying so reads as "that is all there is", and the wearer
                // stops narrowing exactly when narrowing is what would help.
                Text(
                    androidx.compose.ui.res.stringResource(R.string.find_more, matches.size - FIND_ROWS),
                    color = Color(0xFF6E7C88),
                    fontSize = 13.sp,
                )
            }
        }
    }
    }
}

/**
 * How many matches the panel lists. The ring shows at most 24 and the panel is
 * 460 dp tall; fifteen rows is what fits without scrolling becoming the primary
 * way to read it, and anything past that is a query that has not been narrowed.
 */
private const val FIND_ROWS = 15

/** A filter chip: on is filled, off is outlined. One tap either way. */
@Composable
private fun Chip(label: String, on: Boolean, onClick: () -> Unit) {
    TextButton(
        onClick = onClick,
        modifier = Modifier.background(
            if (on) Color(0x3366E8D0) else Color(0x22FFFFFF),
        ),
    ) {
        Text(
            label,
            color = if (on) Color(0xFF66E8D0) else Color(0xFF9AA7B2),
            fontSize = 13.sp,
            maxLines = 1,
        )
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


/**
 * The radio transcript. Deliberately an ordinary widget: header, scrolling
 * list, two buttons.
 *
 * AUTOSCROLL FOLLOWS THE TAIL, AND STOPS WHEN YOU SCROLL. A log that yanks
 * itself back to the bottom while you are reading three lines up is unusable
 * for the one thing it is for, which is reading what already happened.
 */
/**
 * THE ALERTS PANEL — the same shape as the radio log, on purpose.
 *
 * A scrolling list with a timestamp per line is the right form for a history,
 * and the operator asked for exactly this: put it where the debug log is, and
 * leave it off. Newest at the bottom, warnings in amber, repeats collapsed to
 * a count rather than repeated — a standing condition should read as one line
 * that has been true for a while, not as forty identical ones.
 */
@Composable
private fun AlertsPanel() {
    val entries by Alerts.log.collectAsState()
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    LaunchedEffect(entries.size) {
        if (entries.isNotEmpty()) listState.scrollToItem(entries.size - 1)
    }
    val ctx = LocalContext.current
    Column(
        Modifier.fillMaxSize().background(Color(0xF00A0E12)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            androidx.compose.ui.res.stringResource(R.string.al_title, entries.size),
            color = Color(0xFF66E8D0),
            fontFamily = meshMono(ctx),
            fontSize = 14.sp,
        )
        androidx.compose.foundation.lazy.LazyColumn(
            state = listState,
            modifier = Modifier.weight(1f).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            items(entries.size) { i ->
                val e = entries[i]
                val clock = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US)
                    .format(java.util.Date(e.atMs))
                Text(
                    "$clock  ${e.tag}  ${e.text}" + if (e.count > 1) "  ×${e.count}" else "",
                    color = if (e.level == Alerts.Level.WARN) Color(0xFFFFB86B) else Color(0xFFAFC0CA),
                    fontFamily = meshMono(ctx),
                    fontSize = 11.sp,
                )
            }
        }
        if (entries.isEmpty()) {
            Text(
                androidx.compose.ui.res.stringResource(R.string.al_none),
                color = Color(0xFF6E7C88),
                fontFamily = meshMono(ctx),
                fontSize = 12.sp,
            )
        }
        TextButton(onClick = { Alerts.clear() }) {
            Text(
                androidx.compose.ui.res.stringResource(R.string.find_clear),
                color = Color(0xFF7A8C96),
                fontSize = 13.sp,
            )
        }
    }
}

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
            color = Color(0xFF66E8D0), fontFamily = meshMono(LocalContext.current),
            fontWeight = FontWeight.Bold, fontSize = 15.sp,
        )
        Text(
            "${st.state}   adverts ${st.adverts}   contacts ${st.contacts}   ${lines.size} lines",
            color = Color(0xFF7A8C96), fontFamily = meshMono(LocalContext.current), fontSize = 11.sp,
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
                    fontFamily = meshMono(LocalContext.current), fontSize = 11.sp,
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
            fontWeight = FontWeight.SemiBold, fontFamily = meshMono(LocalContext.current),
        )
        Text(
            if (spatial) "P0 · checkpoint 2 — SPATIAL PANEL" else "P0 · checkpoint 1 — home space (2D)",
            color = if (spatial) Ok else Dim,
            fontSize = 13.sp, fontFamily = meshMono(LocalContext.current),
            modifier = Modifier.padding(bottom = 12.dp),
        )

        facts.forEach { (k, v) -> FactRow(k, v) }

        FactRow("spatial UI", if (spatial) "YES" else "no (home space)")

        Text(
            "MESH LINK",
            color = Accent, fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold, fontFamily = meshMono(LocalContext.current),
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
            fontFamily = meshMono(LocalContext.current), fontWeight = FontWeight.Medium,
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
        Text(key, color = Dim, fontSize = 13.sp, fontFamily = meshMono(LocalContext.current))
        Text(
            value,
            color = if (value == "YES") Ok else TextC,
            fontSize = 13.sp, fontFamily = meshMono(LocalContext.current),
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
    ctx: android.content.Context,
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
    /** Start the ten-packet run at this key. Owned by the caller's scope. */
    runSoak: (String, Boolean) -> Unit = { _, _ -> },
) {
    // The REAL message, not the reel's display copy: the copy is clipped for
    // the card and acting on a clipped message would be its own bug.
    val msg = link.msgs.value.getOrNull(reel.selectedIndex)
    // THE CONVERSATION THE CROWN IS ACTUALLY IN. A channel target has no
    // message under the reel's cursor to derive an id from — that is the whole
    // point of being able to speak on a quiet channel — so asking the reel
    // would key VOICE to whatever card happened to be selected behind it.
    val threadId = crown.target?.takeIf { it.channel }?.key
        ?: msg?.let { if (it.direct) it.fromKey else (it.channel ?: "#") }
    // ADDRESSED, rather than answering. Set when the crown was summoned from a
    // node with no conversation; every branch that assumes a message under the
    // reel's cursor has to ask about this first.
    val to = crown.target
    when (act) {
        // AGAIN, THEN. The mesh does not retry and roughly one direct message
        // in ten goes unanswered, so this is the only recovery there is. A new
        // send with the same words: the old line keeps its NO ANSWER, because
        // it really did go unanswered and rewriting that would be the app
        // flattering itself.
        Crown.Act.RESEND -> {
            val lost = link.lastUnanswered()
            if (lost == null) {
                crown.say(ctx.getString(R.string.n_nothing_to_send), nowMs)
                cue.closed()
            } else {
                when (val r = link.resend(lost)) {
                    is MeshLink.Sent.Ok -> {
                        crown.say(
                            ctx.getString(
                                R.string.n_resent,
                                com.iotj.meshmore.xr.spatial.TypeTier.clip(lost.fromName, 12),
                            ),
                            nowMs,
                        )
                        cue.recognised()
                    }
                    is MeshLink.Sent.NotReady -> {
                        crown.say(ctx.getString(R.string.n_radio_not_ready), nowMs); cue.closed()
                    }
                    is MeshLink.Sent.Refused -> { crown.say(r.why, nowMs); cue.closed() }
                }
            }
        }
        // TEN PACKETS, SIX SECONDS APART, AT A NODE YOU OWN.
        //
        // Asked for to test one radio rather than the band: full-length
        // messages mixing latin, kanji and emoji, so the bytes and the
        // characters disagree by a factor of three and a firmware that counts
        // the wrong one fails on exactly this. The allow-list still gates every
        // send underneath — a favourite that is not on it is refused per
        // message, and the run says so rather than reporting a silent zero.
        // TEN PACKETS, SIX SECONDS APART, AT A NODE YOU OWN.
        //
        // Asked for to test one radio rather than the band: full-length
        // messages mixing latin, kanji and emoji, so the byte count and the
        // character count disagree by a factor of three and a firmware that
        // counts the wrong one fails on exactly this input. The allow-list
        // still gates every send underneath — a favourite that is not on it is
        // refused per message, and the run reports that rather than a silent
        // zero.
        Crown.Act.SOAK -> {
            // A CHANNEL SOAK ADDRESSES A SLOT, a person soak a key, and the
            // two take different paths to the radio. The crown already knows
            // which of the two it is holding.
            val onChannel = to?.channel == true
            val peer = if (onChannel) to?.key else (to?.key ?: msg?.fromKey)
            if (peer.isNullOrBlank()) {
                crown.say(ctx.getString(R.string.n_nothing_to_send), nowMs)
                cue.denied()
            } else {
                crown.say(ctx.getString(R.string.n_soak_start, MiniSoak.COUNT), nowMs)
                cue.recognised()
                runSoak(peer, onChannel)
            }
        }
        Crown.Act.REPLY -> { crown.compose(); cue.opened() }
        Crown.Act.BACK -> {
            dictation.cancel()
            // BACK OUT OF WHAT? An addressed crown has no actions level to go
            // back TO — ALOUD, THREAD and VOICE are all about a conversation
            // that does not exist yet — so back is out.
            if (to != null) crown.hide() else crown.backToActions()
            cue.closed()
        }
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
            // NAMED, AND IN THE WEARER'S LANGUAGE. These two lines were English
            // literals; the strings that used to carry them were orphaned when
            // the channel bay stopped owning this toggle, so they moved here
            // and gained the scope the message always wanted.
            val what = crown.voiceScope.ifBlank { ctx.getString(R.string.w_this) }
            crown.say(
                ctx.getString(if (now) R.string.n_reads_aloud else R.string.n_silent, what),
                nowMs,
            )
            cue.recognised()
        }
        Crown.Act.ALOUD -> {
            if (msg == null) {
                crown.say(ctx.getString(R.string.n_nothing_to_read), nowMs)
            } else {
                // WHO, then what. A disembodied sentence in your ear is a worse
                // experience than no audio at all.
                val who = msg.fromName.ifBlank { msg.channelName ?: "someone" }
                speech.say(ctx.getString(R.string.n_says, who, msg.text))
                crown.say(ctx.getString(R.string.n_reading), nowMs)
            }
            cue.recognised()
        }
        Crown.Act.SPEAK -> {
            when {
                dictation.listening -> dictation.stop()
                // The grant is requested HERE, the first time somebody asks to
                // talk, rather than at startup where it would look like the app
                // wanted to listen to the room.
                !dictation.hasPermission() -> { crown.say(ctx.getString(R.string.n_ask_mic), nowMs); askMic() }
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
                crown.say(ctx.getString(R.string.n_no_thread), nowMs)
                cue.closed()
            } else {
                val nowS = System.currentTimeMillis() / 1000
                thread?.showAt(
                    h.translation, yawOf(h), t.id, t.title,
                    t.messages.map { m ->
                        com.iotj.meshmore.xr.spatial.Thread.Line(
                            who = whoLine(com.iotj.meshmore.xr.spatial.TypeTier.clip(
                                    m.fromName.ifBlank { t.title }, 14,
                                ), ago(ctx, nowS - m.atEpochSec)),
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
        Crown.Act.SEND_1 -> { crown.propose(ctx.getString(R.string.q_roger)); cue.opened() }
        Crown.Act.SEND_2 -> { crown.propose(ctx.getString(R.string.q_omw)); cue.opened() }
        Crown.Act.SEND_3 -> { crown.propose(ctx.getString(R.string.q_standby)); cue.opened() }
        // AUTOPEN. Routed through the SAME confirm level as every other draft
        // -- proposeGenerated differs only in that it remembers the words were
        // not the wearer's, so the confirm screen can say so. The row is only
        // offered when there is a suggestion at all, so a null here means the
        // pick raced a card change and doing nothing is right.
        Crown.Act.SEND_AUTO -> {
            val s = crown.suggestion
            if (s.isNullOrBlank()) { crown.say(ctx.getString(R.string.n_no_suggestion), nowMs); cue.closed() }
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
            if ((msg == null && to == null) || text.isBlank()) {
                Log.w(TAG_UI, "[crown] nothing to send: msg=${msg != null} to=${to?.name} blank=${text.isBlank()}")
                crown.say(ctx.getString(R.string.n_nothing_to_send), nowMs)
                cue.closed()
                return
            }
            // THREE TRANSMITTERS, ONE CONFIRM. A channel target speaks on the
            // band, a node target opens a conversation, and no target at all
            // means this is an answer to whatever card is in front of us.
            val sent = when {
                to != null && to.channel ->
                    link.sendToChannel(to.key.removePrefix("#").toIntOrNull() ?: -1, text)
                to != null -> link.sendTo(to.key, text)
                else -> link.replyTo(msg!!, text)
            }
            when (val r = sent) {
                is MeshLink.Sent.Ok -> {
                    crown.say(ctx.getString(R.string.n_sent), nowMs)
                    // A FIRST MESSAGE ENDS THE CROWN. There is a thread now —
                    // the send remembered our own line — so the next MESSAGE on
                    // that node opens the conversation like any other, and
                    // leaving a compose screen standing invites a second send
                    // nobody asked for.
                    if (to != null) crown.hide() else crown.backToActions()
                    cue.recognised()
                }
                is MeshLink.Sent.NotReady -> { crown.say(ctx.getString(R.string.n_radio_not_ready), nowMs); cue.closed() }
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
