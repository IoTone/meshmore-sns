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
    private var meniscus: MeshEntity? = null
    private val body = mutableListOf<MeshEntity>()
    private val motes = mutableListOf<MeshEntity>()
    private var level = 0f
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

        // FLUID, not a stepped bar. The level RISES CONTINUOUSLY: one bright
        // meniscus ring at the surface plus fainter rings beneath it that move
        // with it, which on an additive display reads as a body of liquid
        // without filling the tube with light and hiding the room behind it.
        val fillMat = Prims.material(session, theme.alt, 0.85f)
        meniscus = MeshEntity.create(
            session, Prims.build(session, Prims.halo(RADIUS * 0.86f, 0.007f, 28, 4)), listOf(fillMat),
        ).also {
            it.parent = root
            it.setPose(Pose(Vector3(at.x, at.y - VESSEL_DROP, at.z)), Space.ACTIVITY)
            entities += it
        }
        val bodyMat = Prims.material(session, theme.alt, 0.28f)
        repeat(BODY_RINGS) {
            MeshEntity.create(
                session, Prims.build(session, Prims.halo(RADIUS * 0.80f, 0.004f, 20, 4)), listOf(bodyMat),
            ).also {
                it.parent = root
                it.setEnabled(false)
                body += it
                entities += it
            }
        }

        // PARTICLES. A continuous stream falling in, each on its own phase, so
        // the vessel always looks like it is being fed. They are the only thing
        // that moves when the radio announces no total -- an honest "working"
        // with no invented level under it.
        val moteMat = Prims.material(session, theme.alt, 0.9f)
        repeat(PARTICLES) {
            MeshEntity.create(
                session, Prims.build(session, Prims.mote(0.010f, 4, 6)), listOf(moteMat),
            ).also {
                it.parent = root
                motes += it
                entities += it
            }
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

        // Ease toward real progress rather than snapping. Contacts arrive in
        // bursts, and a level that jumps in steps reads as a progress bar
        // wearing a costume; a level that flows reads as filling.
        val target = if (hasTotal) fraction else 0f
        level += (target - level) * (dt * 3.2f).coerceAtMost(1f)

        val base = at.y - VESSEL_DROP
        val surfaceY = base + VESSEL_H * level
        meniscus?.setPose(Pose(Vector3(at.x, surfaceY, at.z)), Space.ACTIVITY)
        meniscus?.setEnabled(hasTotal)

        // Body rings sit under the surface and are revealed as depth allows.
        body.forEachIndexed { i, r ->
            val y = surfaceY - (i + 1) * BODY_GAP
            val visible = hasTotal && y > base
            r.setEnabled(visible)
            if (visible) r.setPose(Pose(Vector3(at.x, y, at.z)), Space.ACTIVITY)
        }

        // Particles fall from above into the surface, each offset so the stream
        // is continuous rather than pulsing in lockstep.
        val top = base + VESSEL_H + 0.10f
        motes.forEachIndexed { i, m ->
            val phase = ((t / DROP_PERIOD) + i.toFloat() / PARTICLES) % 1f
            val y = top - (top - surfaceY) * phase
            val a = 2.0 * PI * (i * 2.39f)          // golden-angle scatter
            val rr = RADIUS * 0.55f * ((i % 3) + 1) / 3f
            m.setPose(
                Pose(Vector3(at.x + (cos(a) * rr).toFloat(), y, at.z + (sin(a) * rr).toFloat())),
                Space.ACTIVITY,
            )
            // Fade in on entry and out as it merges with the surface, so a
            // particle never visibly pops out of existence at the meniscus.
            m.setAlpha(0.9f * kotlin.math.min(1f, (1f - phase) * 3f) * kotlin.math.min(1f, phase * 6f))
        }
    }

    fun clear() {
        entities.forEach { runCatching { it.dispose() } }
        entities.forEach { runCatching { it.parent = null } }
        entities.clear(); body.clear(); motes.clear()
        wordmark = null; meniscus = null; level = 0f
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
        const val BODY_RINGS = 5
        const val BODY_GAP = 0.045f
        const val PARTICLES = 14
        const val SPIN_DEG_S = 18f
        const val DROP_PERIOD = 0.9f
    }
}
