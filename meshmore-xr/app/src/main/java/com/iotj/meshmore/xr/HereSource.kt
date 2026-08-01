// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.iotj.meshmore.xr.spatial.MeshNodes
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * WHERE THE USER IS — resolved in priority order.
 *
 * Every bearing on the horizon is measured from one point, and getting that
 * point is harder than it looks: the companion radio is the natural source
 * because it is on the user, but plenty of boards have no GPS at all. The C6L
 * reports 0/0 forever, and the result was 143 peers with perfectly good
 * coordinates all parked in the unlocated arc because we had nothing to
 * measure *from*.
 *
 *   1. THE RADIO. Preferred whenever it has a fix: it is the thing actually on
 *      the mesh, and its position is what its own adverts claim.
 *   2. THE HEADSET. Fallback when the radio has none, and only if the user has
 *      turned it on. Off by default -- turning on location is the user's call,
 *      not a silent consequence of plugging in a GPS-less board.
 *   3. A STATED POSITION. `--es home "lat,lon"`. Always wins when given,
 *      because someone who typed coordinates meant them.
 *
 * The headset is a *fallback*, never an override: if the radio has a fix we use
 * it even when device location is enabled and more precise, because the mesh's
 * own frame of reference is the radio's.
 */
class HereSource(private val context: Context) {

    private val _here = MutableStateFlow(MeshNodes.Here(null, null))
    val here: StateFlow<MeshNodes.Here> = _here.asStateFlow()

    /** Which source the current value came from — surfaced so it can be shown. */
    var source: String = "none"
        private set

    fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED

    /**
     * Resolve now. [radio] is whatever the companion reported; [stated] is the
     * launch override. Returns the winner and records which it was.
     */
    fun resolve(radio: MeshNodes.Here, stated: MeshNodes.Here?): MeshNodes.Here {
        val chosen = when {
            stated != null && stated.known -> { source = "stated"; stated }
            radio.known -> { source = "radio"; radio }
            Settings.useDeviceLocation(context) -> deviceFix()?.also { source = "headset" }
                ?: MeshNodes.Here(null, null).also { source = "none" }
            else -> { source = "none"; MeshNodes.Here(null, null) }
        }
        _here.value = chosen
        Log.i(TAG, "[here] $source -> ${chosen.lat}, ${chosen.lon} (known=${chosen.known})")
        return chosen
    }

    /**
     * Last known fix from the headset. Deliberately `getLastKnownLocation`
     * rather than a live request: the horizon is built once at launch, a cold
     * GPS fix takes tens of seconds, and blocking the scene on it would trade a
     * missing bearing for a missing experience. A live subscription belongs
     * with S3, when the horizon starts tracking movement.
     */
    private fun deviceFix(): MeshNodes.Here? {
        if (!hasLocationPermission()) {
            Log.i(TAG, "[here] device location enabled but not permitted")
            return null
        }
        val lm = context.getSystemService(LocationManager::class.java) ?: return null
        val best = runCatching {
            lm.getProviders(true).mapNotNull { p ->
                @Suppress("MissingPermission") lm.getLastKnownLocation(p)
            }.maxByOrNull { it.time }
        }.getOrNull()
        if (best == null) {
            Log.i(TAG, "[here] no last-known device fix")
            return null
        }
        return MeshNodes.Here(best.latitude, best.longitude)
    }

    private companion object { const val TAG = "MeshmoreXR" }
}

/**
 * Settings that must survive a relaunch. A real spatial settings surface is
 * still owed (design brief §9); this is the storage under it, so the toggle
 * exists and is honoured before the control to flip it does.
 */
object Settings {
    private const val FILE = "meshmore-xr"
    private const val KEY_DEVICE_LOCATION = "use_device_location"

    /**
     * OFF by default. Falling back to headset GPS is useful, but switching on
     * location because a board lacks a GPS chip is not a decision to make on
     * the user's behalf.
     */
    fun useDeviceLocation(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_DEVICE_LOCATION, false)

    fun setUseDeviceLocation(context: Context, on: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_DEVICE_LOCATION, on).apply()
    }

    /**
     * The decoded-traffic panel. ON by default FOR NOW: the advert path is
     * still unproven and the panel is how we prove it. This default is
     * temporary and should flip back to off once it has done its job -- a
     * debugging instrument left switched on becomes part of the product by
     * accident.
     */
    fun diagnostics(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_DIAGNOSTICS, true)

    fun setDiagnostics(context: Context, on: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_DIAGNOSTICS, on).apply()
    }

    /**
     * Whether to tell the mesh where we are.
     *
     * SEPARATE FROM [useDeviceLocation] on purpose. Using a fix to compute
     * bearings is local and private; putting it in an advert broadcasts it
     * unencrypted on a public channel to anyone in range. Those are different
     * decisions and one must not imply the other.
     */
    fun shareLocation(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_SHARE_LOCATION, true)

    fun setShareLocation(context: Context, on: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_SHARE_LOCATION, on).apply()
    }

    private const val KEY_DIAGNOSTICS = "diagnostics_panel"
    private const val KEY_SHARE_LOCATION = "share_location"
}
