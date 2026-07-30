// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.content.pm.PackageManager
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.iotone.meshcore.MeshcoreBle
import io.iotone.meshcore.MeshcoreConstants

/**
 * P0 checkpoint 1 — proves the toolchain end to end.
 *
 * Deliberately NOT spatial yet: `Subspace`/`SpatialPanel` is checkpoint 2 and
 * BLE is checkpoint 3. What this screen is for is answering, on the actual
 * device, three questions that everything downstream depends on:
 *
 *   1. does the app build with compileSdk 36 + the Jetpack XR artifacts, and
 *      install and launch on the Aura;
 *   2. does the composite build to libmeshcore link AT RUNTIME (we read real
 *      constants out of it below, so a broken link is a crash, not a silent
 *      no-op);
 *   3. what does the device actually claim about XR — reported rather than
 *      assumed, because the emulator and the hardware disagree.
 *
 * Logging follows the starter guide: one tag, every branch, so a device you
 * are wearing can still be debugged from logcat.
 */
class MainActivity : ComponentActivity() {

    companion object { const val TAG = "MeshmoreXR" }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i(TAG, "[boot] onCreate — ${Build.MANUFACTURER} ${Build.MODEL} api=${Build.VERSION.SDK_INT}")

        val facts = collectFacts()
        facts.forEach { (k, v) -> Log.i(TAG, "[boot] $k = $v") }

        setContent { MaterialTheme { StatusScreen(facts) } }
        Log.i(TAG, "[boot] setContent done — checkpoint 1 UI up")
    }

    /**
     * Everything we want to see on device. Reading MeshcoreConstants and
     * MeshcoreBle here is the point: if the composite build were mis-wired
     * this would fail to resolve at runtime rather than quietly pass.
     */
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
            add("abi" to Build.SUPPORTED_ABIS.joinToString(","))
            xrFeatures.forEach { (name, present) ->
                add(name.removePrefix("android.") to if (present) "YES" else "no")
            }
            // --- proof the composite build links ---
            add("libmeshcore pin" to MeshcoreConstants.FIRMWARE_PIN_TAG)
            add("libmeshcore commit" to MeshcoreConstants.FIRMWARE_PIN_COMMIT.take(12))
            add("meshcore BLE svc" to MeshcoreBle.SERVICE_UUID.take(13) + "…")
        }
    }
}

// HALO FIELD — the chosen default theme (design brief 7.11).
private val Ground = Color(0xFF070B10)
private val Accent = Color(0xFF35E0F0)
private val TextC = Color(0xFFDDE7EF)
private val Dim = Color(0xFF6C8296)
private val Ok = Color(0xFF7CFF6B)

@Composable
private fun StatusScreen(facts: List<Pair<String, String>>) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Ground)
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            "MESHMORE XR",
            color = Accent,
            fontSize = 26.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = FontFamily.Monospace,
        )
        Text(
            "P0 · checkpoint 1 — toolchain",
            color = Dim,
            fontSize = 13.sp,
            fontFamily = FontFamily.Monospace,
            modifier = Modifier.padding(bottom = 12.dp),
        )
        facts.forEach { (k, v) -> FactRow(k, v) }
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
            fontSize = 13.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Medium,
        )
    }
}
