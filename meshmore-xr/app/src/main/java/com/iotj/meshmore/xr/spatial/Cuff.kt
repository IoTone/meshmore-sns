// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.util.Log
import androidx.xr.arcore.HandJointType
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Quaternion
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene
import kotlin.math.sqrt

/**
 * THE CUFF — unread, on the wrist.
 *
 * §S4's arrival table gives it one job: "the wrist ring lights — a single arc
 * segment for a channel message, the whole cuff pulsing for a DM". §5 gives
 * the reason it is on the wrist rather than the back of the hand, and it is a
 * good one:
 *
 *   a ring encircling the wrist is legible whichever way the hand is turned,
 *   so an unread indicator cannot be accidentally faced away from. A flat
 *   badge can.
 *
 * So the ring's axis follows the FOREARM, not the viewer. It is the one
 * surface in the app that is deliberately not billboarded: billboarding it
 * would turn it back into a badge and give away the only property it was
 * chosen for.
 *
 * COUNT BY FORM, NOT BY NUMBER. Channel traffic lights one segment per
 * message; a DM lights the ring and pulses it. §S4 requires channel and DM to
 * be "distinguished by form in every channel — and never by colour alone",
 * which on a wrist ring means geometry and motion.
 *
 * THE PULSE IS A SCALE, NOT A FADE. MeshEntity.setAlpha is a no-op on this
 * material path — proved on the device on 2026-08-02 — so a brightness pulse
 * would look like a working animation in the source and a motionless ring on
 * the glasses. Size survives being seen at the edge of vision anyway, which is
 * where a wrist usually is.
 */
class Cuff(
    private val session: Session,
    private val theme: Horizon.Palette,
) {

    private var root: MeshEntity? = null
    private val segments = mutableListOf<MeshEntity>()
    private val entities = mutableListOf<Entity>()

    /** Channel messages waiting. One segment each, capped at the ring. */
    private var arcs = 0
    /** When the last DM landed, for the pulse. */
    private var dmAt = 0L
    private var lastChannelAt = 0L
    private var lit = false

    suspend fun build() {
        clear()
        val rootNode = session.scene.activitySpace
        // An invisible parent so the ring can be posed once and its segments
        // carry local offsets — twelve world poses a frame for a thing on a
        // wrist is work nobody sees.
        root = MeshEntity.create(
            session, Prims.build(session, Prims.mote(0.002f, 3, 4)),
            listOf(Prims.ghost(session)),
        ).also { it.parent = rootNode; it.setEnabled(true); entities += it }

        // A dodecagon of short chords. A torus sector primitive would be
        // prettier and this is 8 mm across on a wrist; the facets are smaller
        // than the eye resolves at that size.
        repeat(SEGMENTS) { i ->
            val a0 = (i.toFloat() / SEGMENTS) * TAU
            val a1 = ((i + GAP) / SEGMENTS) * TAU
            val f = Prims.spur(
                kotlin.math.cos(a0) * R, 0f, kotlin.math.sin(a0) * R,
                kotlin.math.cos(a1) * R, 0f, kotlin.math.sin(a1) * R,
                TUBE,
            )
            MeshEntity.create(
                session, Prims.build(session, f),
                listOf(Prims.material(session, theme.accent, 0.95f)),
            ).also {
                it.parent = root
                it.setPose(Pose(Vector3(0f, 0f, 0f)), Space.PARENT)
                it.setEnabled(false)
                segments += it
                entities += it
            }
        }
        Log.i(TAG, "[cuff] $SEGMENTS segments")
    }

    /**
     * Auto-clear: channel arcs fade after a while, DMs do not.
     *
     * §9.2 makes this a theme-owned setting and gives the reason — "a cuff
     * glowing since breakfast is noise". A busy channel fills all twelve
     * segments in a minute, and a ring that is always full has stopped being
     * an indicator and become decoration.
     *
     * DIRECT MESSAGES DO NOT EXPIRE. Somebody addressed you personally, and a
     * count that quietly forgets that is worse than no count. Only ambient
     * channel traffic ages out.
     */
    var autoClear: Boolean = true

    /** A channel message landed: one more segment. */
    fun channelArrived() {
        arcs = (arcs + 1).coerceAtMost(SEGMENTS)
        lastChannelAt = android.os.SystemClock.uptimeMillis()
        apply()
    }

    /** A direct message landed: the whole ring, and it pulses. */
    fun directArrived() {
        arcs = SEGMENTS
        dmAt = android.os.SystemClock.uptimeMillis()
        apply()
    }

    /** They have been looked at. */
    fun clearUnread() {
        arcs = 0
        dmAt = 0L
        lastChannelAt = 0L
        apply()
    }

    private fun apply() {
        segments.forEachIndexed { i, s -> runCatching { s.setEnabled(i < arcs) } }
        lit = arcs > 0
    }

    /**
     * Follow the wrist. [joints] are the CHAT hand's, in perception space.
     *
     * Hidden when the hand is not tracked rather than left where it last was:
     * a cuff floating in the room having lost its arm is worse than no cuff,
     * because it still reads as an indicator.
     */
    fun tick(joints: Map<HandJointType, Pose>?, nowMs: Long) {
        val r = root ?: return
        // Age out ambient traffic, one segment at a time so it drains rather
        // than blinking off — the difference between "you missed nothing" and
        // "something just cleared itself".
        if (autoClear && dmAt == 0L && arcs > 0 && nowMs - lastChannelAt > FADE_MS) {
            arcs--
            lastChannelAt = nowMs
            apply()
        }
        if (joints.isNullOrEmpty()) {
            runCatching { r.setEnabled(false) }
            return
        }
        val ps = session.scene.perceptionSpace
        fun act(t: HandJointType): Vector3? = runCatching {
            ps.getScenePoseFromPerceptionPose(joints[t] ?: return null)
                .poseInActivitySpace.translation
        }.getOrNull()
        val w = act(HandJointType.WRIST) ?: return
        val m = act(HandJointType.MIDDLE_METACARPAL) ?: return

        // The forearm runs BACK from the wrist, away from the knuckles, so the
        // ring's axis is the hand direction and the ring sits a little along it
        // toward the elbow — which is where a cuff is.
        var ax = w.x - m.x; var ay = w.y - m.y; var az = w.z - m.z
        val len = sqrt(ax * ax + ay * ay + az * az)
        if (len < 1e-4f) return
        ax /= len; ay /= len; az /= len
        val at = Vector3(w.x + ax * BACK, w.y + ay * BACK, w.z + az * BACK)

        runCatching {
            r.setEnabled(lit)
            r.setPose(Pose(at, alignY(ax, ay, az)), Space.ACTIVITY)
            // The DM pulse: a size beat that decays. Scale, because alpha does
            // nothing on this material path.
            val since = nowMs - dmAt
            val k = if (dmAt > 0L && since < PULSE_MS) {
                val t = since / PULSE_MS.toFloat()
                1f + 0.35f * (1f - t) * kotlin.math.sin(t * TAU * PULSE_BEATS)
            } else {
                1f
            }
            r.setScale(k)
        }
    }

    /** A rotation taking +Y (the halo's axis) onto [x],[y],[z]. */
    private fun alignY(x: Float, y: Float, z: Float): Quaternion {
        // Shortest arc from (0,1,0) to the target. The degenerate case is the
        // target pointing straight down, where the axis is undefined and any
        // perpendicular will do.
        val dot = y.coerceIn(-1f, 1f)
        if (dot > 0.9999f) return Quaternion.fromEulerAngles(0f, 0f, 0f)
        if (dot < -0.9999f) return Quaternion.fromAxisAngle(Vector3(1f, 0f, 0f), 180f)
        val cx = z          // (0,1,0) x (x,y,z)
        val cy = 0f
        val cz = -x
        val cl = sqrt(cx * cx + cy * cy + cz * cz)
        if (cl < 1e-6f) return Quaternion.fromEulerAngles(0f, 0f, 0f)
        val ang = Math.toDegrees(kotlin.math.acos(dot).toDouble()).toFloat()
        return Quaternion.fromAxisAngle(Vector3(cx / cl, cy / cl, cz / cl), ang)
    }

    fun clear() {
        segments.clear(); root = null; arcs = 0; dmAt = 0L; lit = false
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private companion object {
        const val TAG = "MeshmoreXR"
        const val TAU = (2.0 * Math.PI).toFloat()
        /** Twelve, matching the reel's depth: one segment is one message. */
        const val SEGMENTS = 12
        /** How much of each step is drawn, leaving the gaps that make it count. */
        const val GAP = 0.72f
        /** Wrist radius, near enough. */
        const val R = 0.032f
        const val TUBE = 0.0035f
        /** How far along the forearm from the wrist joint. */
        const val BACK = 0.025f
        /** How long one channel segment survives untouched. */
        const val FADE_MS = 20_000L
        const val PULSE_MS = 1800L
        const val PULSE_BEATS = 3f
    }
}
