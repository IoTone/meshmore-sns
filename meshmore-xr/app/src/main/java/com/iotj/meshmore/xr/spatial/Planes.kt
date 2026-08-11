// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.util.Log
import androidx.xr.arcore.Plane
import androidx.xr.arcore.PlaneLabel
import androidx.xr.arcore.PlaneType
import androidx.xr.arcore.TrackingState
import androidx.xr.runtime.Session

/**
 * WHAT SURFACES THE ROOM ACTUALLY OFFERS — a probe, not a feature.
 *
 * S6-TABLETOP's plan rests on one fact nobody here has verified: that the
 * runtime reports a plane LABELLED as a table, rather than merely a horizontal
 * one. `PlaneSemanticType.TABLE` exists in scenecore-1.0.0-beta01 and
 * `PlaneLabel.TABLE` in arcore-1.0.0-beta01 — both confirmed in the API index —
 * but a constant existing in a jar says nothing about whether this device, or
 * the emulator's virtual room, ever produces one.
 *
 * If it does, `AnchorEntity.create(session, size, HORIZONTAL, TABLE, timeout)`
 * is a one-call answer to "put the model on the table". If it does not, that
 * call waits out its timeout and returns TIMED_OUT forever, and the design has
 * to fall back to the largest horizontal plane at a plausible height — which is
 * a different feature with different failure modes.
 *
 * So this prints the table and lets the room answer. It is deliberately
 * opt-in — `--ez planes true` — and deliberately writes nothing to the scene:
 * a probe that draws is a probe you end up debugging.
 *
 * Precedent: `TypeProbe` settled the texture question the same way, and the
 * answer there (Texture.create resolves against the AssetManager, so runtime
 * strings can never be sampled textures) closed off a whole planned mechanism.
 * Better to find that out from a probe than from a half-built feature.
 */
object Planes {

    private const val TAG = "MeshmoreXR"

    /**
     * Watch the plane set and report every change, until the scope dies.
     *
     * `Plane.subscribe` hands back a StateFlow of the CURRENT collection, so
     * planes appear, grow, and get subsumed into larger ones as the runtime
     * learns the room. The interesting output is therefore not the first
     * emission but the last: this logs each distinct census rather than each
     * emission, because the flow re-emits far faster than the room changes.
     */
    suspend fun watch(session: Session) {
        runCatching {
            Plane.subscribe(session).collect { planes ->
                census(planes)
            }
        }.onFailure {
            // The likely failure is a config that never enabled plane tracking,
            // or a permission that was never granted. Both are worth naming
            // rather than dying quietly inside a coroutine.
            Log.w(TAG, "[planes] subscribe failed: ${it.javaClass.simpleName}: ${it.message}")
        }
    }

    private var last = ""

    private fun census(planes: Collection<Plane>) {
        if (planes.isEmpty()) {
            say("[planes] none yet")
            return
        }
        val seen = planes.mapNotNull { p ->
            val s = runCatching { p.state.value }.getOrNull() ?: return@mapNotNull null
            val e = s.extents
            // AREA IS THE POINT. The tabletop model is 0.32 m across and needs
            // 0.40 m of surface, so a plane's usefulness is its smaller edge,
            // not its label alone — a 2 m x 0.1 m ledge is labelled the same as
            // a desk and will not hold the model.
            val minEdge = minOf(e.width, e.height)
            "%-8s %-5s %5.2f x %5.2f m (min %4.2f) at y=%+.2f %s".format(
                labelOf(s.label), typeOf(p.type), e.width, e.height, minEdge,
                s.centerPose.translation.y,
                if (s.trackingState == TrackingState.TRACKING) "" else "[not tracking]",
            ).let { labelOf(s.label) to it }
        }.sortedBy { it.second }
        val text = seen.joinToString("\n") { it.second }
        if (text == last) return
        last = text
        say("[planes] ${planes.size} plane(s):")
        seen.forEach { say("[planes]   ${it.second}") }
        val tables = seen.count { it.first == "TABLE" }
        // THE ONE LINE THIS PROBE EXISTS FOR.
        say(
            if (tables > 0) "[planes] TABLE: $tables — AnchorEntity(TABLE) is viable here"
            else "[planes] TABLE: none — semantic anchoring will TIME OUT here",
        )
    }

    /**
     * NAME THE CONSTANT BY COMPARING TO IT, not by asking it what it is called.
     *
     * `PlaneLabel` and `PlaneType` are value classes over an int, not enums, so
     * `toString()` gives `PlaneLabel@1d10409` — an identity, not a name. The
     * first run of this probe printed twelve of those and concluded "TABLE:
     * none", which would have sent the whole tabletop design down the fallback
     * path on the strength of a formatting bug. The data was visible in the same
     * output: three planes sharing one label identity, 0.61 x 0.61 m and
     * 1.05 x 0.40 m, sitting at 0.49 to 0.75 m off the floor. Table-shaped,
     * table-height, and labelled something this probe could not read.
     *
     * A probe that cannot name what it found is worse than no probe, because it
     * reports a confident negative.
     */
    private fun labelOf(l: PlaneLabel?): String = when (l) {
        PlaneLabel.TABLE -> "TABLE"
        PlaneLabel.FLOOR -> "FLOOR"
        PlaneLabel.WALL -> "WALL"
        PlaneLabel.CEILING -> "CEILING"
        PlaneLabel.UNKNOWN -> "UNKNOWN"
        else -> "?"
    }

    private fun typeOf(t: PlaneType?): String = when (t) {
        PlaneType.HORIZONTAL_UPWARD_FACING -> "UP"
        PlaneType.HORIZONTAL_DOWNWARD_FACING -> "DOWN"
        PlaneType.VERTICAL -> "VERT"
        else -> "?"
    }

    private fun say(s: String) = Log.i(TAG, s)
}
