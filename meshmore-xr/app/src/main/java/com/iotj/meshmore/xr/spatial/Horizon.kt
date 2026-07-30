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
 * S1 HORIZON — the always-on mesh, as geometry in the room.
 *
 * Not a screen, not a panel, not a list. A volumetric shell around the user:
 * every peer at its true bearing, its true elevation, and its true distance,
 * with the forward arc deliberately left clear because that window belongs to
 * the world.
 *
 * Everything here is a MeshEntity built from Prims. Nothing is Compose.
 */
class Horizon(private val session: Session, private val theme: Palette) {

    data class Node(
        val name: String,
        val bearingRad: Float,
        val elev: Float,          // -1..1, fraction of the shell's vertical span
        val dist: Float,          // 0..1, fraction of the outer range band
        val age: Float,           // 0 = just heard, 1 = stale
        val located: Boolean,
        val hops: Int,
    )

    data class Palette(
        val accent: Int, val alt: Int, val warn: Int, val text: Int,
    )

    private val entities = mutableListOf<Entity>()
    private val pulses = mutableListOf<Pulse>()

    private class Pulse(val entity: MeshEntity, val base: Float, var life: Float = 1f)

    suspend fun build(nodes: List<Node>, o: Stage.Origin, floorY: Float) {
        clear()
        val root = session.scene.activitySpace

        // --- range halos: real tori, lying flat below eye level --------------
        // Distance is read from which band a mote sits in, so the bands are the
        // scale and have to be legible from any angle -- hence torus, not disc.
        listOf(0.40f, 0.70f, 1.00f).forEachIndexed { i, f ->
            val mesh = Prims.build(session, Prims.halo(R * f, 0.014f))
            val mat = Prims.material(session, theme.accent, 0.30f + i * 0.06f)
            MeshEntity.create(session, mesh, listOf(mat)).also {
                it.parent = root
                it.setPose(Pose(o.place(0f, 0f, EYE_DROP)), Space.ACTIVITY)
                entities += it
            }
        }

        // --- the peers -------------------------------------------------------
        nodes.forEach { n ->
            // A node with no position estimate MUST NOT be given a fake bearing.
            // It parks in a dedicated unlocated arc behind the dominant shoulder.
            val bearing = if (n.located) n.bearingRad else (PI * 0.78f).toFloat()
            val dist = if (n.located) n.dist else 0.42f
            val elev = if (n.located) n.elev else -0.3f

            // Bearings are measured from the user's LAUNCH FACING, so the mesh
            // wraps the body rather than the tracker's arbitrary origin.
            val v = o.place(bearing, R * dist, elev * R * 0.35f + EYE_DROP)
            val px = v.x; val py = v.y; val pz = v.z
            val dx = px - o.x; val dy = py - o.y; val dz = pz - o.z
            val range = kotlin.math.sqrt(dx * dx + dy * dy + dz * dz)

            // CONSTANT ANGULAR SIZE (~1.6 deg). A fixed-radius mote subtends 9
            // deg up close and 2 deg far away; distance is already carried by
            // the range bands, so letting it drive apparent size just makes
            // near nodes shout.
            val r = (range * 0.0140f).coerceAtLeast(0.010f)
            val lum = 1f - n.age * 0.72f

            val moteMesh = Prims.build(session, Prims.mote(r))
            val moteMat = Prims.material(
                session, if (n.located) theme.accent else theme.warn, lum.coerceIn(0.25f, 1f)
            )
            MeshEntity.create(session, moteMesh, listOf(moteMat)).also {
                it.parent = root
                it.setPose(Pose(Vector3(px, py, pz)), Space.ACTIVITY)
                entities += it
            }

            // Hop count as an equatorial BAND -- structure you see on a sphere
            // rather than a number you parse.
            if (n.hops > 1) {
                val bandMesh = Prims.build(session, Prims.halo(r * 1.55f, r * 0.16f, 24, 4))
                val bandMat = Prims.material(session, theme.alt, 0.75f * lum)
                MeshEntity.create(session, bandMesh, listOf(bandMat)).also {
                    it.parent = root
                    it.setPose(Pose(Vector3(px, py, pz)), Space.ACTIVITY)
                    entities += it
                }
            }

            // CALLSIGN — extruded stroke glyphs, so the label is made of light
            // in the room rather than printed on a surface. Sized by VISUAL
            // ANGLE (~1.3 deg cap height at its own range), never in absolute
            // metres, or distant nodes become unreadable.
            val capH = range * 0.0227f
            val label = if (n.located) n.name else n.name + " ?"
            val txtMesh = Prims.build(session, Glyphs.text(label, capH))
            val txtMat = Prims.material(session, theme.text, (0.45f + 0.55f * lum))
            MeshEntity.create(session, txtMesh, listOf(txtMat)).also {
                it.parent = root
                // Face the user: labels sit on the ring, turned inward. A true
                // billboard needs a per-frame head pose; ring-facing is stable,
                // costs nothing, and is correct wherever the user is standing.
                val face = Math.toDegrees((o.yawRad + bearing).toDouble()).toFloat()
                it.setPose(
                    Pose(
                        Vector3(px, py - r * 2.6f - capH, pz),
                        Quaternion.fromEulerAngles(0f, face, 0f),
                    ),
                    Space.ACTIVITY,
                )
                entities += it
            }

            // Elevation CARET: "the ridge station is above you" as a fact you
            // perceive, not a figure you read.
            if (n.located && kotlin.math.abs(n.elev) > 0.25f) {
                val up = n.elev > 0
                val cMesh = Prims.build(session, Prims.caret(r * 0.9f, r * 1.6f))
                val cMat = Prims.material(session, theme.alt, 0.85f * lum)
                MeshEntity.create(session, cMesh, listOf(cMat)).also {
                    it.parent = root
                    val dy = if (up) r * 2.4f else -r * 3.8f
                    it.setPose(Pose(Vector3(px, py + dy, pz)), Space.ACTIVITY)
                    entities += it
                }
            }
        }
        Log.i(TAG, "[horizon] built ${entities.size} entities for ${nodes.size} nodes")
    }

    /** PULSE — the mesh visibly breathing. One expanding ring per packet. */
    suspend fun pulse(bearingRad: Float, dist: Float, o: Stage.Origin) {
        val v = o.place(bearingRad, R * dist, EYE_DROP)
        val r0 = (R * dist * 0.016f).coerceAtLeast(0.012f)
        val mesh = Prims.build(session, Prims.halo(r0, r0 * 0.28f, 24, 4))
        val mat = Prims.material(session, theme.accent, 0.55f)
        val e = MeshEntity.create(session, mesh, listOf(mat))
        e.parent = session.scene.activitySpace
        e.setPose(Pose(v), Space.ACTIVITY)
        pulses += Pulse(e, r0)
    }

    /** Drive the pulses. Called from a frame loop; cheap and allocation-free. */
    fun tick(dt: Float) {
        val it = pulses.iterator()
        while (it.hasNext()) {
            val p = it.next()
            p.life -= dt / 0.7f
            if (p.life <= 0f) {
                runCatching { p.entity.dispose() }
                it.remove()
            } else {
                val grow = 1f + (1f - p.life) * 2.6f
                p.entity.setScale(grow)
                p.entity.setAlpha(p.life * 0.55f)
            }
        }
    }

    fun clear() {
        entities.forEach { runCatching { it.dispose() } }
        entities.clear()
        pulses.forEach { runCatching { it.entity.dispose() } }
        pulses.clear()
    }

    companion object {
        private const val TAG = "MeshmoreXR"
        /** HORIZON radius, metres. Body-locked in the design; world-fixed for P1. */
        const val R = 2.5f
        /** The shell sits at and below eye level; the forward arc stays clear. */
        const val EYE_DROP = -0.30f
    }
}
