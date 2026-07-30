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
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
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
import androidx.xr.compose.platform.LocalSpatialCapabilities
import androidx.xr.compose.platform.requestFullSpace
import androidx.xr.compose.platform.requestHomeSpace
import androidx.xr.compose.spatial.Subspace
import androidx.xr.compose.subspace.SpatialPanel
import androidx.xr.compose.subspace.layout.SubspaceModifier
import androidx.xr.compose.subspace.layout.height
import androidx.xr.compose.subspace.layout.width
import io.iotone.meshcore.android.SessionState
import io.iotone.meshcore.MeshcoreBle
import io.iotone.meshcore.MeshcoreConstants
import kotlinx.coroutines.launch

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

    companion object { const val TAG = "MeshmoreXR" }

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
        setContent { MaterialTheme { Root(facts, link, pin) } }
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
private fun Root(facts: List<Pair<String, String>>, link: MeshLink, pinOverride: String?) {
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
        // CHECKPOINT 2 — real spatial UI. SpatialPanel sizes are in Dp here and
        // are converted to metres by the runtime; ordinary Compose renders onto
        // the panel surface.
        Subspace {
            SpatialPanel(SubspaceModifier.width(1024.dp).height(720.dp)) {
                StatusScreen(facts, link, spatial = true)
            }
        }
    } else {
        // Home Space: an ordinary 2D window. Fully functional, per the brief's
        // rule that no spatial capability must ever be load-bearing.
        StatusScreen(facts, link, spatial = false)
    }
}

private const val TAG_UI = "MeshmoreXR"

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
            Button(
                enabled = !busy && activity != null,
                colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Ground),
                onClick = {
                    val a = activity ?: return@Button
                    busy = true
                    scope.launch {
                        // Suspend, and it can be refused -- hence the result log.
                        val res = if (spatial) a.requestHomeSpace() else a.requestFullSpace()
                        Log.i(TAG_UI, "[spatial] request ${if (spatial) "HOME" else "FULL"} -> $res")
                        busy = false
                    }
                },
            ) { Text(if (spatial) "TO HOME SPACE" else "REQUEST FULL SPACE", fontFamily = FontFamily.Monospace) }

            Button(
                enabled = mesh.state == SessionState.DISCONNECTED && !mesh.scanning,
                colors = ButtonDefaults.buttonColors(containerColor = Ok, contentColor = Ground),
                onClick = {
                    if (link.hasBlePermissions()) link.connect()
                    else perms.launch(arrayOf(
                        android.Manifest.permission.BLUETOOTH_SCAN,
                        android.Manifest.permission.BLUETOOTH_CONNECT,
                    ))
                },
            ) { Text("LINK RADIO", fontFamily = FontFamily.Monospace) }
        }
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
