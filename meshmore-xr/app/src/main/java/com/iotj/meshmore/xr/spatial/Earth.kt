// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.util.Log
import androidx.xr.runtime.Session

/**
 * WHICH WAY IS NORTH — asked of the planet, because the glasses cannot say.
 *
 * This app has never known true north. Two sensors reach an application on
 * this hardware and neither is a magnetometer, so every bearing on the ring is
 * measured from wherever the wearer happened to be facing when the app
 * started. The heading band admits it in as many words:
 *
 *     [heading] ring is RELATIVE to launch facing — 'N' means 'the way you
 *     were pointing', not north
 *
 * ARCore's geospatial API resolves an EARTH-relative pose from GPS, VPS and
 * the device's own tracking, and it has been in the SDK the whole time: twelve
 * geospatial classes shipped in beta01, and beta02 added only the tracking
 * state enum. Nothing in this app had asked.
 *
 * A PROBE, NOT A FEATURE, and deliberately so. Earth-relative tracking wants a
 * location grant, a network, and a service that supports the device; it may
 * never resolve indoors, and its yaw accuracy may be too coarse to hang a
 * compass on even when it does. All of that is answerable in an afternoon of
 * logs and unanswerable by reading documentation, so this measures first and
 * claims nothing.
 */
object Earth {

    /** Degrees of yaw error the ring could tolerate before north is a lie. */
    const val USABLE_YAW_DEG = 15.0

    private var said = 0L

    /**
     * Read the current earth pose and say what it amounts to.
     *
     * Called from the frame loop, rate-limited hard: this is a diagnostic, and
     * a diagnostic that floods the log is one nobody can read — a lesson this
     * project paid for twice this week.
     */
    fun probe(session: Session, nowMs: Long) {
        if (nowMs - said < EVERY_MS) return
        said = nowMs
        val geo = runCatching { androidx.xr.arcore.Geospatial.getInstance(session) }
            .getOrElse {
                Log.w(TAG, "[earth] no geospatial instance (${it.javaClass.simpleName})")
                return
            }
        val st = geo.state.value
        val tracking = st.geospatialTrackingState
        if (tracking != androidx.xr.arcore.Geospatial.GeospatialTrackingState.RUNNING) {
            // NOT TRACKING IS AN ANSWER. Indoors, unauthorised, or unsupported
            // all land here, and which one it is matters more than the fact.
            Log.i(TAG, "[earth] $tracking — no earth pose")
            return
        }
        val p = st.geospatialPose
        // HEADING FROM THE EAST-UP-SOUTH FRAME. The quaternion rotates the
        // device into a frame whose axes are east, up and south, so the
        // device's forward vector expressed there gives a bearing directly:
        // atan2 of its east component over its north component, where north is
        // the negated south axis.
        val q = p.eastUpSouthQuaternion
        val fx = 2f * (q.x * q.z + q.w * q.y)
        val fz = 1f - 2f * (q.x * q.x + q.y * q.y)
        val bearing = ((Math.toDegrees(kotlin.math.atan2(fx, -fz).toDouble()) + 360.0) % 360.0)
        val usable = st.orientationYawAccuracy <= USABLE_YAW_DEG
        Log.i(
            TAG,
            ("[earth] RUNNING %.6f, %.6f alt %.1fm — heading %.1f° ±%.1f° " +
                "(h±%.1fm v±%.1fm) %s").format(
                p.latitude, p.longitude, p.altitude, bearing,
                st.orientationYawAccuracy, st.horizontalAccuracy, st.verticalAccuracy,
                if (usable) "— GOOD ENOUGH FOR A COMPASS" else "— too coarse to point with",
            ),
        )
    }

    private const val TAG = "MeshmoreXR"
    private const val EVERY_MS = 5_000L
}
