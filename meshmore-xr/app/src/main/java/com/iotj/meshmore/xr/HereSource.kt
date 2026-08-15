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

    /** What was last logged, so a poll only speaks when something changed. */
    private var lastNote: String? = null

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
        // ONLY WHEN IT CHANGES. This used to run at launch and on a handful of
        // explicit events, so logging every call was free. It is now polled
        // every 15 seconds to keep the map measured from where the wearer
        // actually is, and an unconditional line here put four identical
        // entries a minute into the one log anybody debugs this app from.
        val note = "$source ${chosen.lat},${chosen.lon}"
        if (note != lastNote) {
            lastNote = note
            Log.i(TAG, "[here] $source -> ${chosen.lat}, ${chosen.lon} (known=${chosen.known})")
        }
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
    private const val KEY_TABLE_ANCHOR = "table_anchor_uuid"

    /**
     * THE TABLE THIS APP WAS LAST STOOD ON.
     *
     * A persisted anchor UUID, so a wearer sets their table up ONCE rather
     * than on every launch — the runtime relocalises against the room it
     * remembers and hands the same physical surface back.
     *
     * A UUID and not a position, deliberately. Coordinates are meaningless
     * across sessions: activity space is re-established wherever the app
     * happened to start, so yesterday's (x, y, z) points at a different part
     * of the room today. The UUID is the runtime's own handle on a place, and
     * it is the only thing that survives the origin moving.
     *
     * Null once the room stops being recognisable — a different building, a
     * rearranged desk — which is why every read of it has to tolerate a miss.
     */
    fun tableAnchor(context: Context): String? =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getString(KEY_TABLE_ANCHOR, null)

    fun setTableAnchor(context: Context, uuid: String?) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit().apply {
                if (uuid == null) remove(KEY_TABLE_ANCHOR) else putString(KEY_TABLE_ANCHOR, uuid)
            }.apply()
    }

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
     * The decoded-traffic panel. OFF by default, as the note below always said
     * it should be once it had done its job.
     *
     * It was on to prove the advert path, and the advert path is proven — the
     * horizon builds 24 motes from 50 peers off a live mesh. Shipping it on
     * would be exactly the accident the old comment warned about: a debugging
     * instrument becoming part of the product because nobody turned it off.
     *
     * Still one pinch away, in the console's DIAG plate and the APP bay.
     */
    fun diagnostics(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_DIAGNOSTICS, false)

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

    /**
     * WHETHER THIS APP MAY TRANSMIT ON A CHANNEL. Off until somebody says so.
     *
     * A direct message goes to one radio you chose. A CHANNEL message puts a
     * packet on a shared band addressed to everyone listening, most of whom are
     * strangers — a different act, and not one to enable on a wearer's behalf
     * because the reply button would otherwise look broken.
     *
     * Stored here rather than left as a source constant so it is the WEARER's
     * decision rather than a build's, made in the open, in a bay, with the
     * consequence written next to it. [MeshLink.channelTxAuthorised] is loaded
     * from this at startup and remains the single gate at the radio.
     */
    /**
     * The region mismatch the wearer has already been shown, as
     * "radioRegionId>hereRegionId" — so the bay auto-opens ONCE per distinct
     * mismatch rather than on every boot, while the notice may still repeat.
     * A wearer who deliberately runs an out-of-region preset has said so once
     * and is not nagged with a surface; a wearer who lands in a NEW country
     * gets the prompt again because the pair changed.
     */
    fun regionAck(context: Context): String? =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getString(KEY_REGION_ACK, null)

    fun setRegionAck(context: Context, pair: String?) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit().apply {
                if (pair == null) remove(KEY_REGION_ACK) else putString(KEY_REGION_ACK, pair)
            }.apply()
    }

    fun channelSend(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_CHANNEL_SEND, false)

    fun setChannelSend(context: Context, on: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_CHANNEL_SEND, on).apply()
    }

    /**
     * Whether AUTOPEN offers a drafted reply. ON, because it is opt-OUT.
     *
     * It proposes and never sends, it is marked as generated on both screens it
     * appears on, and it stays absent unless it has something the canned
     * replies do not cover — so the cost of it being on is one row that is
     * usually not there. The switch exists because a person who does not want a
     * machine writing in their voice should not have to argue with it, and
     * because the spec asked for one.
     */
    fun autopen(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_AUTOPEN, true)

    fun setAutopen(context: Context, on: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_AUTOPEN, on).apply()
    }

    /**
     * Whether FIRST LIGHT has been completed. Once per install, not per launch.
     *
     * Stored as "done" rather than "show me": the wearer never chose this, so
     * the app should stop asking as soon as it has its answer, and a preference
     * phrased the other way invites a future default that shows it again.
     */
    fun firstLightDone(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_FIRST_LIGHT, false)

    fun setFirstLightDone(context: Context, done: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_FIRST_LIGHT, done).apply()
    }

    /**
     * REDUCE MOTION. Off by default, and it is a WEARER's setting rather than
     * a theme's.
     *
     * The transition grammar has honoured this flag since it was written; it
     * simply had no control, because the APP bay was full at six rows and the
     * Stack could not show a seventh. That is a bad reason for an accessibility
     * setting to be unreachable, and it is why the Stack learned to page.
     */
    fun reduceMotion(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_REDUCE_MOTION, false)

    fun setReduceMotion(context: Context, on: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_REDUCE_MOTION, on).apply()
    }

    private const val KEY_REDUCE_MOTION = "reduce_motion"
    private const val KEY_FIRST_LIGHT = "first_light_done"
    private const val KEY_AUTOPEN = "autopen"
    private const val KEY_DIAGNOSTICS = "diagnostics_panel"
    private const val KEY_SHARE_LOCATION = "share_location"
    private const val KEY_REGION_ACK = "region_ack"
    private const val KEY_CHANNEL_SEND = "channel_send"
}
