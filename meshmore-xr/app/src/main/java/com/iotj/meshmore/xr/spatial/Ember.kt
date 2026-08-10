// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.util.Log
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene

/**
 * EMBER — the fourth arrival channel. A mote at the edge of vision, on the
 * sender's bearing, gone in about three seconds.
 *
 * §S4: "Nothing appears in front of your face, and nothing demands
 * acknowledgement. The mesh is ambient; you look when you choose to." An ember
 * is the smallest thing that can carry WHERE a message came from. The other
 * three arrival channels cannot: audio is spatialised but not everyone has
 * sound on, the cuff is on your wrist and says only what KIND of message, and
 * the unread counter is a number. None of them answers "who, and which way".
 *
 * It is deliberately at the EDGE and deliberately brief. A notification in the
 * centre of vision on a see-through display is worse than a phone's, because
 * you cannot put it face-down — it is over the road, or over the person you are
 * talking to. Peripheral vision is very good at motion and very bad at detail,
 * which is exactly the right trade for "something arrived, that way".
 *
 * ## Direction is the whole payload, so an unlocated sender gets no ember
 *
 * A mote at a bearing we do not know would have to go SOMEWHERE, and every
 * choice is a lie the wearer cannot detect — they would turn and look. The
 * brief already forbids inventing bearings for unlocated nodes on the horizon
 * and the same reasoning applies harder here, because an ember is gone before
 * anybody can check it. No bearing, no ember; the cuff and the counter still
 * fire, which is why §S4 says the design must survive losing any one channel.
 *
 * ## Why several, and why they decay by SCALE
 *
 * A busy channel lands three messages in a second and one reused mote would
 * only ever show the last. There is a small pool, oldest recycled first.
 *
 * They shrink rather than fade because `MeshEntity.setAlpha` is a no-op on this
 * material path. Colour on the material CAN now be animated ([Ink] proved it),
 * but an ember is exactly the wrong place to use it: [Ink.retint] owns every
 * registered material, and a per-frame writer on the same one is the two-writers
 * bug this codebase keeps meeting. Scale is nobody else's property.
 */
class Ember(
    private val session: Session,
    private val theme: Horizon.Palette,
) {

    private class Mote(val entity: MeshEntity, val direct: Boolean) {
        var bearing: Float = 0f
        var bornMs: Long = 0L
        var live: Boolean = false
    }

    private val motes = mutableListOf<Mote>()
    private val entities = mutableListOf<Entity>()
    private var next = 0

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        // TWO POOLS, because channel and DM differ BY FORM and never by colour
        // alone (§S4). A DM is a mote inside a ring; a channel message is a
        // bare mote. Built as separate geometry because the difference has to
        // survive a wearer who cannot tell the two accents apart.
        repeat(POOL) { i ->
            val direct = i >= POOL / 2
            val facets = if (direct) Prims.halo(R * 1.6f, R * 0.35f) else Prims.mote(R, 7, 10)
            val e = MeshEntity.create(
                session, Prims.build(session, facets),
                listOf(Prims.material(session, if (direct) theme.accent else theme.alt, 0.85f)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            motes += Mote(e, direct)
        }
        Log.i(TAG, "[ember] pool of ${motes.size}")
    }

    /**
     * Light one. [bearingRad] is the sender's TRUE bearing, already in the
     * ring's frame; null means we do not know and nothing is drawn.
     */
    fun arrived(bearingRad: Float?, direct: Boolean, nowMs: Long) {
        val b = bearingRad ?: run {
            Log.i(TAG, "[ember] no bearing for this sender — no ember (cuff still fires)")
            return
        }
        // Oldest of the right KIND, so a burst of channel traffic cannot evict
        // the ember for a direct message somebody actually needs to see.
        val pool = motes.filter { it.direct == direct }
        if (pool.isEmpty()) return
        val m = pool.firstOrNull { !it.live } ?: pool.minByOrNull { it.bornMs } ?: return
        m.bearing = b
        m.bornMs = nowMs
        m.live = true
        Log.i(TAG, "[ember] %s at %.0f deg".format(
            if (direct) "DM" else "channel", Math.toDegrees(b.toDouble())))
    }

    /**
     * Place and decay. [head] and [yawRad] are the wearer's pose; embers are
     * HEAD-RELATIVE, so one stays put in the corner of your eye while you turn
     * rather than sliding away from the direction it is reporting.
     *
     * That sounds backwards and is not: the ember's job is to say "that way",
     * and the way it does that is by sitting at the edge of vision on the side
     * the message came from. Once you turn toward it, it has done its job.
     */
    fun tick(head: Vector3?, yawRad: Float, nowMs: Long) {
        if (head == null) return
        motes.forEach { m ->
            if (!m.live) return@forEach
            val age = (nowMs - m.bornMs).toFloat() / LIFE_MS
            if (age >= 1f) {
                m.live = false
                runCatching { m.entity.setEnabled(false) }
                return@forEach
            }
            // Where it sits: the bearing RELATIVE to where the wearer is facing,
            // clamped to the edge of the field. A sender directly behind you
            // pins to whichever edge is the shorter turn, which is the answer
            // to "which way do I look" rather than a claim about geometry.
            var rel = m.bearing - yawRad
            while (rel > Math.PI) rel -= TWO_PI
            while (rel < -Math.PI) rel += TWO_PI
            val side = if (rel >= 0f) 1f else -1f
            val edge = side * EDGE_X
            // Height drops a little for something far behind, so front and back
            // are not the same mark in the same place.
            val behind = (kotlin.math.abs(rel) / Math.PI.toFloat()).coerceIn(0f, 1f)
            val y = head.y + EDGE_Y - behind * DROP

            val fx = kotlin.math.sin(yawRad)
            val fz = -kotlin.math.cos(yawRad)
            val rx = kotlin.math.cos(yawRad)
            val rz = kotlin.math.sin(yawRad)
            val p = Vector3(
                head.x + fx * DIST + rx * edge,
                y,
                head.z + fz * DIST + rz * edge,
            )
            // DECAY IS SCALE. A brief swell then a shrink to nothing: the swell
            // is what peripheral vision actually notices, and the shrink is what
            // makes it leave without a wearer having to dismiss it.
            val k = if (age < RISE) age / RISE else 1f - (age - RISE) / (1f - RISE)
            runCatching {
                m.entity.setEnabled(true)
                m.entity.setPose(Pose(p), Space.ACTIVITY)
                m.entity.setScale((0.15f + 0.85f * k).coerceAtLeast(0.02f))
            }
        }
    }

    /** How many are burning, for a test or a readout. */
    fun liveCount(): Int = motes.count { it.live }

    fun clear() {
        motes.clear(); next = 0
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private companion object {
        const val TAG = "MeshmoreXR"
        const val TWO_PI = (Math.PI * 2).toFloat()

        /** Six: three channel, three direct. A burst of three is common. */
        const val POOL = 6

        /** Near enough to be peripheral, far enough not to be in focus. */
        const val DIST = 0.9f

        /** 3.0 degrees at DIST — the icon floor. Small, but it is only a spark. */
        const val R = 0.024f

        /**
         * How far out to the side. At 0.9 m a 34-degree field is 0.55 m wide, so
         * 0.23 m is just inside the edge — present in peripheral vision, never
         * over the middle of the view where §S4 forbids it.
         */
        const val EDGE_X = 0.23f
        const val EDGE_Y = -0.02f
        const val DROP = 0.10f

        /** "Decaying over ~3 s", from the brief. */
        const val LIFE_MS = 3000f

        /** The first fifth is the swell; the rest is the decay. */
        const val RISE = 0.2f
    }
}
