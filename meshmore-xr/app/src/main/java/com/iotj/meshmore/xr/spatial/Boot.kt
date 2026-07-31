// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.util.Log
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Quaternion
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * THE BOOT SURFACE — what the room does while the mesh loads.
 *
 * Loading a contact list takes fifteen to thirty seconds against a real mesh,
 * and an empty room for thirty seconds reads as a broken app. The usual answer
 * is a spinner on a panel, which is exactly the thing this project exists to
 * avoid. So the wait is spatial: a wordmark turning slowly overhead and a
 * VESSEL that visibly fills with the data as it arrives.
 *
 * The progress is REAL. ContactsStartFrame announces how many contacts are
 * coming, so the fill is received/total and nothing is invented -- no bar that
 * sits at 90%, no indeterminate sweep pretending to be information. When the
 * radio does not tell us a total, the vessel shows arrivals without a fill line
 * rather than guessing one.
 *
 * Everything here is disposed the moment loading ends. A loading surface that
 * lingers is just clutter with a good excuse.
 */
class Boot(private val session: Session, private val theme: Horizon.Palette) {

    private val entities = mutableListOf<Entity>()
    private var wordmark: Entity? = null
    private var rings = mutableListOf<MeshEntity>()
    private var drop: MeshEntity? = null
    private var at: Vector3 = Vector3(0f, 0f, 0f)
    private var t = 0f

    /**
     * Build overhead and slightly forward. HIGH, because the horizon is at eye
     * level and the boot surface must not occupy the space the mesh is about to
     * arrive into -- the two should never fight for the same air.
     */
    suspend fun build(o: Stage.Origin) {
        clear()
        val root = session.scene.activitySpace
        at = o.place(0f, FORWARD, HEIGHT)

        // WORDMARK. Stroke glyphs, so it is made of the same light as the
        // symbology rather than being a logo pasted into the room.
        val mark = Prims.build(session, Glyphs.text("MESHMORE XR", CAP))
        wordmark = MeshEntity.create(
            session, mark, listOf(Prims.material(session, theme.accent, 0.9f)),
        ).also {
            it.parent = root
            it.setPose(Pose(at), Space.ACTIVITY)
            entities += it
        }

        // VESSEL. A cage, not a solid: on an additive display a filled tube
        // would wash out everything behind it, and the point is to watch the
        // level rise inside.
        val cageMat = Prims.material(session, theme.accent, 0.35f)
        listOf(0f, VESSEL_H).forEach { y ->
            MeshEntity.create(
                session, Prims.build(session, Prims.halo(RADIUS, 0.004f, 24, 4)), listOf(cageMat),
            ).also {
                it.parent = root
                it.setPose(Pose(Vector3(at.x, at.y - VESSEL_DROP + y, at.z)), Space.ACTIVITY)
                entities += it
            }
        }
        for (i in 0 until STAVES) {
            val a = 2.0 * PI * i / STAVES
            val x = (cos(a) * RADIUS).toFloat()
            val z = (sin(a) * RADIUS).toFloat()
            MeshEntity.create(
                session,
                Prims.build(session, Prims.spur(0f, 0f, 0f, 0f, VESSEL_H, 0f, 0.003f)),
                listOf(cageMat),
            ).also {
                it.parent = root
                it.setPose(Pose(Vector3(at.x + x, at.y - VESSEL_DROP, at.z + z)), Space.ACTIVITY)
                entities += it
            }
        }

        // FILL. One ring per layer, revealed from the bottom up. Rings rather
        // than a solid column because a ring reads as a LEVEL from any angle,
        // and because each one arriving is a visible event -- data stacking up
        // rather than a bar sliding.
        val fillMat = Prims.material(session, theme.alt, 0.75f)
        for (i in 0 until LAYERS) {
            val y = at.y - VESSEL_DROP + VESSEL_H * (i + 0.5f) / LAYERS
            MeshEntity.create(
                session, Prims.build(session, Prims.halo(RADIUS * 0.82f, 0.006f, 20, 4)), listOf(fillMat),
            ).also {
                it.parent = root
                it.setPose(Pose(Vector3(at.x, y, at.z)), Space.ACTIVITY)
                it.setEnabled(false)
                rings += it
                entities += it
            }
        }

        // The DROP — one mote falling in from above, recycled continuously.
        drop = MeshEntity.create(
            session, Prims.build(session, Prims.mote(0.018f, 5, 8)),
            listOf(Prims.material(session, theme.alt, 0.9f)),
        ).also {
            it.parent = root
            it.setPose(Pose(Vector3(at.x, at.y - VESSEL_DROP + VESSEL_H, at.z)), Space.ACTIVITY)
            entities += it
        }
        Log.i(TAG, "[boot] surface up: ${entities.size} entities")
    }

    /**
     * Drive it. [fraction] is real progress 0..1; [active] false starts the
     * teardown. Called from the same frame loop as everything else.
     */
    fun tick(dt: Float, fraction: Float, hasTotal: Boolean) {
        t += dt

        // Slow rotation. SLOW deliberately -- this sits above the user's eyeline
        // for half a minute, and anything brisk up there is a distraction you
        // cannot look away from.
        wordmark?.setPose(
            Pose(at, Quaternion.fromEulerAngles(0f, (t * SPIN_DEG_S) % 360f, 0f)),
            Space.ACTIVITY,
        )
        // Breathing alpha rather than a hard blink: a flashing wordmark at this
        // size reads as an alarm.
        val pulse = 0.55f + 0.45f * (0.5f + 0.5f * sin(t * 2.2f))
        wordmark?.setAlpha(pulse)

        // Fill to real progress. With no announced total we show arrivals only
        // by keeping the drop animating -- an honest "working" with no fake level.
        val lit = if (hasTotal) (fraction * LAYERS).toInt() else 0
        rings.forEachIndexed { i, r -> r.setEnabled(i < lit) }

        // The drop falls to the current surface and repeats.
        val fall = (t % DROP_PERIOD) / DROP_PERIOD
        val top = at.y - VESSEL_DROP + VESSEL_H
        val surface = at.y - VESSEL_DROP + VESSEL_H * (lit.toFloat() / LAYERS)
        drop?.setPose(
            Pose(Vector3(at.x, top - (top - surface) * fall, at.z)), Space.ACTIVITY,
        )
        drop?.setAlpha(0.9f * (1f - fall * 0.5f))
    }

    fun clear() {
        entities.forEach { runCatching { it.dispose() } }
        entities.clear(); rings.clear(); wordmark = null; drop = null
    }

    private companion object {
        const val TAG = "MeshmoreXR"
        /** Overhead: the horizon owns eye level, the boot surface must not. */
        const val HEIGHT = 0.95f
        const val FORWARD = 2.0f
        const val CAP = 0.115f
        const val RADIUS = 0.16f
        const val VESSEL_H = 0.42f
        const val VESSEL_DROP = 0.62f
        const val STAVES = 8
        const val LAYERS = 14
        const val SPIN_DEG_S = 18f
        const val DROP_PERIOD = 0.9f
    }
}
