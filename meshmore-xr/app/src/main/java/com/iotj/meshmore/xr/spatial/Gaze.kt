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
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * LOOK AT A THING AND WAIT — the input path that does not need hands.
 *
 * §8.2 lists this as non-negotiable: "gaze-and-dwell as a full alternative to
 * pinch, for users who cannot reliably pinch and for when hand tracking is
 * denied or degraded". Until now every control in the app — dock pips, node
 * selection, the rack, the menu — was pinch-only, which made hand tracking a
 * single point of failure for the entire interface. It has already failed
 * repeatedly in testing.
 *
 * HEAD GAZE, NOT EYE GAZE. The Aura reports hand tracking and nothing else: no
 * controller, no eye tracker. So "gaze" is the direction the head is pointing,
 * which is the ordinary meaning on this class of hardware and is why the cone
 * has to be generous — you aim it with your neck.
 *
 * THE INDICATOR IS ON THE TARGET, NOT IN THE MIDDLE OF YOUR VIEW. The obvious
 * design is a crosshair with a filling ring, head-locked dead centre. §2.1 rule
 * 2 reserves a 34x20 degree centre in which NOTHING PERSISTENT may ever appear,
 * and a reticle you carry everywhere is the most persistent thing there could
 * be. Marking the thing you are about to activate is better anyway: it says
 * WHAT will happen, where a crosshair only says that something will.
 *
 * MIDAS TOUCH is the whole risk of dwell — everything you look at gets pressed.
 * Three defences, and they matter more than the timing:
 *
 *   1. It only runs when there are NO HANDS. A tracked hand means the pinch
 *      path is available and dwell would be a second, invisible way to fire the
 *      same control. This is a fallback, not a parallel input.
 *   2. Targets must be LEFT before they can fire again, exactly like the ASL
 *      gate — so resting your gaze does not repeat.
 *   3. The dock sits 30 degrees below eye level. You do not look there by
 *      accident, which is why it is the surface this is wired to first.
 */
class Gaze(
    private val session: Session,
    private val theme: Horizon.Palette,
) {

    /** Something that can be looked at. [fire] runs on the frame loop. */
    class Target(
        val id: String,
        val at: Vector3,
        /** Half-angle of the acceptance cone, radians. */
        val coneRad: Float,
        val fire: () -> Unit,
    )

    private val targets = mutableListOf<Target>()
    private var ring: MeshEntity? = null
    private val entities = mutableListOf<Entity>()

    /** Which target the gaze is on, and for how long. */
    private var onId: String? = null
    private var lastPose: Pair<Vector3, Quaternion>? = null
    private var lastMovedAt = 0L
    private var since = 0L
    private var firedId: String? = null

    /**
     * Whether dwell is currently doing anything. Driven by hand availability —
     * see the note above on why this is a fallback rather than a parallel path.
     */
    var active: Boolean = false
        private set

    /** Raised when a dwell completes, so the host can make the sound. */
    var onFire: ((String) -> Unit)? = null

    /**
     * Which target the gaze is resting on, or null. The host feeds this back to
     * the surface so the thing about to fire shows its ordinary focus state —
     * the dock pips carry icons at rest and their CAPTION is what disambiguates
     * them, so dwelling without it fires a control whose name you never saw.
     */
    val onTarget: String? get() = onId

    suspend fun build() {
        clear()
        // Gapped, so its rotation reads. The dwell winds it round: a ring that
        // only brightens says "something is happening" and not "how much
        // longer", and a progress cue you cannot read the end of is a cue that
        // makes people hold still for too long out of doubt.
        ring = MeshEntity.create(
            session, Prims.build(session, Prims.reticle(R, R * 0.22f, arcs = 4, duty = 0.5f)),
            listOf(Prims.material(session, theme.accent, 0.9f)),
        ).also {
            it.parent = session.scene.activitySpace
            it.setEnabled(false)
            entities += it
        }
        Log.i(TAG, "[gaze] ready")
    }

    fun setTargets(list: List<Target>) {
        targets.clear()
        targets += list
    }

    /**
     * [handsSeen] is whether ANY hand is currently tracked. Dwell stands down
     * while it is true.
     */
    fun tick(head: Pose?, handsSeen: Boolean, nowMs: Long) {
        // IS ANYONE WEARING THIS? A head that has not moved at all is a headset
        // on a table, and a headset on a table was quietly dwelling on whatever
        // dock pip it happened to be pointing at and pressing it. Nobody asked
        // for that, and an app that changes its own settings while unattended
        // does not feel competent whatever else it does right.
        //
        // A worn headset is never still: breathing alone moves it. So the test
        // is not "did the user look somewhere", it is "is this thing on a face
        // at all", and the threshold can be tiny.
        //
        // It starts DISARMED. The first version treated "no previous pose" as
        // motion, which armed dwell on the very first frame — and a headset
        // lying on a desk pointing at the dock fired a pip 900 ms later, before
        // the stillness test had two samples to compare. Movement has to be
        // observed, not assumed.
        head?.let { h ->
            val p = h.translation
            val q = h.rotation
            val moved = lastPose?.let { l ->
                kotlin.math.abs(p.x - l.first.x) + kotlin.math.abs(p.y - l.first.y) +
                    kotlin.math.abs(p.z - l.first.z) +
                    kotlin.math.abs(q.x - l.second.x) + kotlin.math.abs(q.y - l.second.y) +
                    kotlin.math.abs(q.z - l.second.z) + kotlin.math.abs(q.w - l.second.w)
            } ?: 0f   // no previous pose yet: OBSERVE, do not assume motion
            lastPose = p to q
            if (moved > STILL_EPS) lastMovedAt = nowMs
        }
        val worn = nowMs - lastMovedAt < STILL_MS

        val wasActive = active
        active = !handsSeen && worn
        if (wasActive != active) {
            Log.i(TAG, "[gaze] dwell " + if (active) "ARMED" else
                ("stood down (" + (if (handsSeen) "hands" else "still") + ")"))
        }
        if (!active || head == null) {
            onId = null
            runCatching { ring?.setEnabled(false) }
            return
        }

        val best = pick(head)
        if (best?.id != onId) {
            onId = best?.id
            since = nowMs
            // Left the target, so it may fire again. Same rule as the ASL gate:
            // one press per deliberate visit, not one per frame.
            if (best?.id != firedId) firedId = null
        }

        if (best == null) {
            runCatching { ring?.setEnabled(false) }
            return
        }

        val held = nowMs - since
        val t = (held.toFloat() / DWELL_MS).coerceIn(0f, 1f)
        runCatching {
            ring?.setEnabled(true)
            ring?.setPose(
                Pose(best.at, Quaternion.fromAxisAngle(Vector3(0f, 0f, 1f), t * 270f)),
                Space.ACTIVITY,
            )
            // SCALE AND ROTATION CARRY THE PROGRESS, and brightness does not —
            // MeshEntity.setAlpha is a no-op on this material path (proved on
            // the device 2026-08-02 by driving it to 0.0 and watching nothing
            // change). A ramp written on alpha would have looked like a working
            // progress cue in the source and shown a constant ring on the
            // glasses.
            //
            // Closes in as it fills, 1.8x down to 1.0x. That reads as a lock
            // rather than a highlight, and a size change survives being seen at
            // the edge of the field where a brightness change does not.
            ring?.setScale(1.8f - 0.8f * t)
        }

        if (t >= 1f && firedId != best.id) {
            firedId = best.id
            Log.i(TAG, "[gaze] fired ${best.id} after ${held}ms")
            onFire?.invoke(best.id)
            runCatching { best.fire() }
        }
    }

    /** The target nearest the head's forward axis, if any is inside its cone. */
    private fun pick(head: Pose): Target? {
        val q = head.rotation
        val t = head.translation
        // The camera looks down -Z, so forward is the NEGATED third column.
        val fx = -2f * (q.x * q.z + q.w * q.y)
        val fy = -2f * (q.y * q.z - q.w * q.x)
        val fz = -(1f - 2f * (q.x * q.x + q.y * q.y))
        var best: Target? = null
        var bestAng = Float.MAX_VALUE
        targets.forEach { g ->
            val dx = g.at.x - t.x
            val dy = g.at.y - t.y
            val dz = g.at.z - t.z
            val len = sqrt(dx * dx + dy * dy + dz * dz)
            if (len < 1e-4f) return@forEach
            val dot = ((fx * dx + fy * dy + fz * dz) / len).coerceIn(-1f, 1f)
            val ang = acos(dot)
            if (ang <= g.coneRad && ang < bestAng) { bestAng = ang; best = g }
        }
        return best
    }

    fun clear() {
        targets.clear(); ring = null; onId = null; firedId = null
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private companion object {
        const val TAG = "MeshmoreXR"
        /**
         * How long to hold. 900 ms is long enough that a glance across a
         * control does not press it and short enough that it does not feel
         * broken. It is a starting figure, not a measured one.
         */
        const val DWELL_MS = 900L
        /** The lock ring's radius at the dock's distance. About 2.6 degrees. */
        const val R = 0.035f
        /**
         * How much combined position+rotation change counts as "alive". Small
         * on purpose: a worn headset is never still, and the only thing being
         * excluded here is one that is not on a head.
         */
        const val STILL_EPS = 0.004f
        /** How long a motionless headset stays armed before standing down. */
        const val STILL_MS = 2500L
    }
}
