// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.util.Log
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.FloatSize2d
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.AnchorEntity
import androidx.xr.scenecore.PlaneOrientation
import androidx.xr.scenecore.PlaneSemanticType
import androidx.xr.scenecore.Space
import java.time.Duration

/**
 * S6-TABLETOP — PUT THE MODEL ON A REAL TABLE.
 *
 * The tabletop posture currently hangs its diorama in the air, 0.55 m ahead and
 * 0.42 m down, because that is where a table USUALLY is relative to a seated
 * person. This asks the room where the table ACTUALLY is.
 *
 * ONE CALL DOES THE SEARCH. `AnchorEntity.create(session, size, orientation,
 * semantic, timeout)` is declarative — "find me a horizontal surface labelled
 * TABLE, at least this big, and give up after this long" — so there is no plane
 * subscription to manage, no hit-testing, and no filtering to get subtly wrong.
 * The `Planes` probe confirmed the emulator's room offers three TABLE planes;
 * whether a given real room does is what the fallback below is for.
 *
 * 0.40 x 0.40 m BECAUSE THE MODEL IS 0.32 m ACROSS. That leaves 4 cm of margin
 * all round. It is not a formality: of the emulator room's three tables the
 * request rejects a 0.84 x 0.16 m ledge outright and sits exactly on the
 * boundary of a 1.05 x 0.40 m desk, which is the discrimination we want — a
 * model half off the edge of a shelf is worse than a model in the air.
 *
 * ## Failure is a first-class outcome
 *
 * There is no table in a field, on a bus, or in a room the wearer has not
 * looked around yet, and the anchor takes seconds to land even when there is
 * one. So this NEVER blocks and never replaces the tabletop — it offers a
 * better centre when it finds one. Until then, and forever if the room has no
 * table, the body-relative placement stands. That ordering matters: the
 * fallback is a working feature rather than an error state, so this can only
 * improve on it.
 */
class TableAnchor(private val session: Session) {

    private var entity: AnchorEntity? = null

    /** Where the table is, or null while there isn't one. */
    var at: Vector3? = null
        private set

    /**
     * Ask the room for a table. Returns immediately; [poll] reports progress.
     *
     * WHY THE SEARCH IS NOT AWAITED. `create` returns an entity in the
     * UNANCHORED state and moves it to ANCHORED, TIMED_OUT or ERROR on its own
     * schedule — the scene is already up and the wearer is already looking at
     * their mesh, so the model appearing in the air and later settling onto the
     * table is a much better sequence than fourteen seconds of nothing while a
     * search runs.
     */
    fun seek(): Boolean = runCatching {
        entity?.let { return@runCatching true }
        entity = AnchorEntity.create(
            session,
            FloatSize2d(FOOTPRINT, FOOTPRINT),
            PlaneOrientation.HORIZONTAL,
            PlaneSemanticType.TABLE,
            Duration.ofSeconds(SEARCH_S),
        )
        Log.i(TAG, "[table] seeking a ${FOOTPRINT}m table, ${SEARCH_S}s to give up")
        true
    }.onFailure {
        Log.w(TAG, "[table] cannot seek: ${it.javaClass.simpleName}: ${it.message}")
    }.getOrDefault(false)

    private var said: AnchorEntity.State? = null

    /**
     * Check on the search. Returns true the first time a table is found, which
     * is the caller's cue to re-place the model on it.
     *
     * Polled rather than listened to: the frame loop is already running and a
     * state callback would arrive on some other thread, where touching the
     * scene is not allowed. One enum read per frame is cheaper than making that
     * safe.
     */
    fun poll(): Boolean {
        val e = entity ?: return false
        val s = runCatching { e.state }.getOrNull() ?: return false
        if (s != said) {
            said = s
            Log.i(TAG, "[table] $s")
        }
        if (s != AnchorEntity.State.ANCHORED) return false
        if (at != null) return false
        val p = runCatching { e.getPose(Space.ACTIVITY) }.getOrNull() ?: return false
        at = p.translation
        Log.i(
            TAG,
            "[table] found at (%.2f, %.2f, %.2f) — the model moves onto it".format(
                p.translation.x, p.translation.y, p.translation.z,
            ),
        )
        return true
    }

    /** True once the search has ended without a table. Stops the caller retrying. */
    fun gaveUp(): Boolean {
        val s = runCatching { entity?.state }.getOrNull() ?: return false
        return s == AnchorEntity.State.TIMED_OUT || s == AnchorEntity.State.ERROR
    }

    fun dispose() {
        runCatching { entity?.dispose() }
        entity = null
        at = null
    }

    private companion object {
        const val TAG = "MeshmoreXR"

        /** The model is 0.32 m across; this leaves 4 cm of margin all round. */
        const val FOOTPRINT = 0.40f

        /**
         * Long enough for a wearer to glance across a desk, short enough that a
         * roomless environment stops burning the perception pipeline on it.
         */
        const val SEARCH_S = 20L
    }
}
