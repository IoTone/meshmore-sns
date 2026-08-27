// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.content.Context
import android.util.Log
import androidx.xr.arcore.HandJointType
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Quaternion
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.InputEvent
import androidx.xr.scenecore.InteractableComponent
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene
import kotlin.math.atan2

/**
 * S0 · FIRST LIGHT — one mote, and the word TOUCH.
 *
 * The brief: "The first-time XR user is the hardest user; most have never used
 * XR. This surface teaches the paradigm by DOING it, not by explaining it. A
 * single MOTE appears at arm's length. 'Touch it.' That is the entire first
 * instruction."
 *
 * That is all this is, and the restraint is the design. A tutorial that walks
 * through the reel, the crown, the console and the horizon teaches nothing,
 * because none of it is retained until there is a reason to want it. What a
 * first-time wearer actually needs to learn is that THINGS IN THE AIR RESPOND
 * TO YOUR HANDS, and one mote teaches that in about four seconds.
 *
 * ## It is also the diagnostic, which is why it ships before the tutorial does
 *
 * Hand tracking either works or it does not, and when it does not, every other
 * surface in this app presents as broken in a different way — the reel does not
 * turn, the crown does not answer, the console will not open. Testers report
 * five bugs. This turns all five into one question, asked once, in four seconds,
 * before anything else is on screen.
 *
 * ## The fail-safe is the point of the second line
 *
 * The brief requires that "every permission denial has a working path. No hand
 * tracking → gaze + head-dwell selection." So if the mote goes untouched for
 * [HINT_MS] it says so and offers the dwell, rather than leaving somebody
 * waving at a dot. Somebody who reaches that line has learned the more
 * important thing anyway: that this app has a way through when the hands do not
 * work.
 */
class FirstLight(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    private var mote: MeshEntity? = null
    private var ring: MeshEntity? = null
    private var proxy: MeshEntity? = null
    private var line: TextRun.Run? = null
    private var hint: TextRun.Run? = null
    private val entities = mutableListOf<Entity>()

    private var at: Vector3? = null
    private var shownAt = 0L
    private var touched = false

    /** The reach trail, hand to mote. Built once, posed per frame. */
    private val beads = mutableListOf<MeshEntity>()

    /** The yaw the mote was placed at, kept so the ghost trail knows which way is left. */
    private var yaw = 0f

    /** Whether the trail last ran from a tracked hand or from the ghost origin. */
    private var lastTrail = ""

    var open: Boolean = false
        private set

    /** Raised once, when the wearer touches it. The host decides what follows. */
    var onTouched: (() -> Unit)? = null

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        mote = MeshEntity.create(
            session, Prims.build(session, Prims.mote(R, 9, 14)),
            listOf(Prims.material(session, theme.accent, 0.7f)),
        ).also { it.parent = root; it.setEnabled(false); entities += it }
        // A BRIGHT KEYLINE, not a dark halo. On additive optics a dark edge
        // cannot subtract the room behind it, so the silhouette has to be drawn
        // in light — and a lone sphere against an unknown wall needs one.
        ring = MeshEntity.create(
            session, Prims.build(session, Prims.halo(R * 1.5f, R * 0.10f)),
            listOf(Prims.material(session, theme.alt, 0.9f)),
        ).also { it.parent = root; it.setEnabled(false); entities += it }
        proxy = MeshEntity.create(
            session, Prims.build(session, Prims.mote(R * 2.2f, 6, 10)),
            listOf(Prims.ghost(session)),
        ).also { it.parent = root; it.setEnabled(false); entities += it }
        runCatching {
            proxy?.addComponent(InteractableComponent.create(session) { ev -> onInput(ev) })
        }.onFailure { Log.w(TAG, "[first] no input on the mote: $it") }

        // THE REACH TRAIL. See [Beckon]: the operator has never once seen the
        // words under this mote, so the instruction is drawn instead of
        // written. Built here with everything else, because an entity created
        // after the scene is up does not attach.
        repeat(Beckon.BEADS) {
            beads += MeshEntity.create(
                session, Prims.build(session, Prims.mote(BEAD_R, 4, 6)),
                listOf(Prims.material(session, theme.accent, 0.85f)),
            ).also { b -> b.parent = root; b.setEnabled(false); entities += b }
        }

        line = run(root, com.iotj.meshmore.xr.L10n.tpl(WIDEST, "これに触れる"), "first-line", theme.text)
        hint = run(root, com.iotj.meshmore.xr.L10n.tpl(HINT_WIDEST, "見つめて保持でも可"), "first-hint", theme.alt)
        Log.i(TAG, "[first] built")
    }

    private suspend fun run(root: Entity, widest: String, name: String, rgb: Int): TextRun.Run? =
        TextRun.reusable(
            session, context, widest,
            com.iotj.meshmore.xr.L10n.cap(CAP), argb(rgb, 0.95f), name,
        )
            ?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }
            // LOUDLY, WHEN IT DOES NOT EXIST. These two runs carry S0's only
            // words and the operator reports never having seen either of them
            // in months of wearing this. A null here was silent, so the one
            // fact that would separate "the panel was never built" from "it was
            // built and is drawn somewhere I never look" was not being
            // recorded. The size is logged for the same reason: a run scaled to
            // nothing and a run correctly placed are indistinguishable from a
            // report, and distinguishable from one line.
            .also {
                if (it == null) {
                    Log.w(TAG, "[first] run '$name' FAILED TO BUILD — no text will show")
                } else {
                    Log.i(TAG, "[first] run '$name' %.3f x %.3f m".format(it.widthM, it.heightM))
                }
            }

    fun showAt(head: Vector3, yawRad: Float, nowMs: Long) {
        yaw = yawRad
        val fx = kotlin.math.sin(yawRad)
        val fz = -kotlin.math.cos(yawRad)
        // A NUDGE TO THE LEFT, so the left hand is the one that comes up.
        // The mote still takes a touch from either hand and from the gaze
        // dwell — this biases the reach, it does not require it.
        val lx = -kotlin.math.cos(yawRad)
        val lz = -kotlin.math.sin(yawRad)
        at = Vector3(
            head.x + fx * DIST + lx * LEFT_BIAS,
            head.y + DROP,
            head.z + fz * DIST + lz * LEFT_BIAS,
        )
        open = true
        touched = false
        shownAt = nowMs
        runCatching { line?.setText(context.getString(com.iotj.meshmore.xr.R.string.fl_touch)) }
        Log.i(TAG, "[first] open")
    }

    fun hide() {
        if (!open) return
        open = false
        (listOfNotNull<Entity>(mote, ring, proxy, line?.entity, hint?.entity) + beads)
            .forEach { runCatching { it.setEnabled(false) } }
        Log.i(TAG, "[first] closed")
    }

    fun tick(
        head: Vector3?,
        nowMs: Long,
        /**
         * The wearer's LEFT hand, in ARCore's perception frame. Null when the
         * tracker has not seen it, which is the case S0 exists to detect and
         * also the case a first-time wearer starts in.
         */
        leftJoints: Map<HandJointType, Pose>? = null,
    ) {
        if (!open) return
        val p = at ?: return
        if (head == null) return
        val r = facing(p, head)
        // A SLOW BREATH, in scale. Nothing else on the horizon idles (§7.1
        // "nothing idles"), and this is the one place where an exception earns
        // itself: a wearer who does not yet know that anything here is
        // interactive needs the object to look alive before they will reach for
        // it. It stops existing the moment it is touched.
        val t = ((nowMs - shownAt) % BREATH_MS).toFloat() / BREATH_MS
        val pulse = 1f + 0.06f * kotlin.math.sin(t * 2f * Math.PI.toFloat())
        runCatching {
            mote?.setEnabled(true); ring?.setEnabled(true); proxy?.setEnabled(true)
            mote?.setPose(Pose(p, r), Space.ACTIVITY)
            mote?.setScale(pulse)
            ring?.setPose(Pose(p, r), Space.ACTIVITY)
            ring?.setScale(pulse)
            proxy?.setPose(Pose(p), Space.ACTIVITY)
        }
        runCatching {
            line?.entity?.setEnabled(true)
            val lp = Vector3(p.x, p.y - LABEL_DROP, p.z)
            line?.entity?.setPose(Pose(lp, facing(lp, head)), Space.ACTIVITY)
            // THE WAY THROUGH, offered rather than waited for.
            val stuck = nowMs - shownAt > HINT_MS
            hint?.entity?.setEnabled(stuck)
            if (stuck) {
                hint?.setText(context.getString(com.iotj.meshmore.xr.R.string.fl_hint))
                val hp = Vector3(p.x, lp.y - CAP * 2.2f, p.z)
                hint?.entity?.setPose(Pose(hp, facing(hp, head)), Space.ACTIVITY)
            }
        }
        beckon(p, nowMs, leftJoints)
    }

    /**
     * DRAW THE WAY IN.
     *
     * From the wearer's own left hand when the tracker can see it, and from a
     * ghost origin down and to their left when it cannot. See [Beckon] for why
     * this is a drawing rather than a sentence.
     *
     * BRIGHTNESS IS SCALE, not alpha. The Cuff established that alpha does
     * nothing on this material path, and a bead that swells as the highlight
     * passes reads at least as clearly on additive optics as one that
     * brightens — arguably better, since a swell survives a bright room.
     */
    private fun beckon(p: Vector3, nowMs: Long, leftJoints: Map<HandJointType, Pose>?) {
        val hand = palm(leftJoints)
        val from = hand ?: run {
            val (gx, gy, gz) = Beckon.ghost(
                p.x, p.y, p.z,
                leftX = -kotlin.math.cos(yaw), leftZ = -kotlin.math.sin(yaw),
            )
            Vector3(gx, gy, gz)
        }
        // A TRACKED HAND FADES THE TRAIL AS IT ARRIVES; a ghost origin is a
        // fixed distance and always draws at full strength, because there is
        // no hand approaching for it to get out of the way of.
        val strength =
            if (hand == null) 1f
            else Beckon.strength(Beckon.distance(hand.x, hand.y, hand.z, p.x, p.y, p.z))
        val path = Beckon.trail(
            from.x, from.y, from.z, p.x, p.y, p.z,
            Beckon.phase(nowMs), strength,
        )
        // ONCE PER STATE CHANGE, not per frame. Whether the trail is anchored
        // to a real hand or running from the ghost origin is the one thing a
        // wearer cannot report reliably — both look like a trail — and it is
        // exactly what says whether the tracker saw the left hand.
        val state = if (hand == null) "ghost" else "hand"
        if (state != lastTrail) {
            lastTrail = state
            Log.i(TAG, "[first] trail $state — ${path.size} beads, strength %.2f".format(strength))
        }
        beads.forEachIndexed { i, b ->
            val bead = path.getOrNull(i)
            runCatching {
                if (bead == null) {
                    b.setEnabled(false)
                } else {
                    b.setEnabled(true)
                    b.setPose(Pose(Vector3(bead.x, bead.y, bead.z)), Space.ACTIVITY)
                    b.setScale(bead.alpha)
                }
            }
        }
    }

    /**
     * The centre of the palm, in the frame everything else here is posed in.
     *
     * MIDDLE_METACARPAL rather than a fingertip: the trail is aiming the HAND,
     * and a fingertip wanders with every curl of a finger, which would make the
     * trail's anchor jitter while the hand itself was still.
     *
     * The conversion is the one that has now bitten this codebase twice — hand
     * joints arrive in PERCEPTION space and posing them straight into ACTIVITY
     * puts them wherever the two origins happen to differ.
     */
    private fun palm(joints: Map<HandJointType, Pose>?): Vector3? {
        if (joints.isNullOrEmpty()) return null
        val j = joints[HandJointType.MIDDLE_METACARPAL]
            ?: joints[HandJointType.WRIST]
            ?: return null
        return runCatching {
            session.scene.perceptionSpace
                .getScenePoseFromPerceptionPose(j).poseInActivitySpace.translation
        }.getOrNull()
    }

    /** The dwell path, so a wearer with no hand tracking is not stranded. */
    fun gazeTargets(): List<Gaze.Target> {
        if (!open) return emptyList()
        val p = at ?: return emptyList()
        return listOf(Gaze.Target("first-mote", p, CONE_RAD) { fire() })
    }

    private fun onInput(ev: InputEvent) {
        if (!open) return
        if (ev.action == InputEvent.Action.UP) {
            Reach.consumed()
            fire()
        }
    }

    private fun fire() {
        if (touched) return
        touched = true
        Log.i(TAG, "[first] touched — hand tracking confirmed")
        onTouched?.invoke()
    }

    private fun facing(p: Vector3, head: Vector3): Quaternion {
        val dx = head.x - p.x
        val dz = head.z - p.z
        if (dx * dx + dz * dz < 1e-6f) return Quaternion.fromEulerAngles(0f, 0f, 0f)
        return Quaternion.fromEulerAngles(
            0f, Math.toDegrees(atan2(dx, dz).toDouble()).toFloat(), 0f,
        )
    }

    fun clear() {
        mote = null; ring = null; proxy = null; line = null; hint = null
        // THE BEAD LIST EMPTIES HERE TOO. A list left holding disposed handles
        // is a native crash the next time anything poses them — which is
        // exactly how HALO died once.
        beads.clear()
        open = false; at = null; touched = false; yaw = 0f; lastTrail = ""
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"

        /** Arm's length, as the brief says. Also where a first reach lands. */
        const val DIST = 0.45f

        /** A little below the eye line — where a hand goes without being told. */
        const val DROP = -0.08f

        /** 4.1° at DIST. Above the 3.0° icon floor, and deliberately inviting. */
        const val R = 0.016f

        /**
         * A bead of the reach trail, at full swell.
         *
         * Deliberately under a third of the mote and well under the mesh's own
         * 1.6° node: the trail is a route, and a route drawn in objects the
         * same size as destinations reads as a row of destinations.
         */
        const val BEAD_R = R * 0.28f

        /**
         * How far left of straight ahead the mote sits.
         *
         * About 13° at [DIST] — enough that the left hand is the one that comes
         * up without thinking, small enough that it is still plainly in front of
         * the wearer rather than off to one side.
         */
        const val LEFT_BIAS = 0.10f

        /** 1.30° at DIST, the house standard. */
        const val CAP = 0.0102f
        const val LABEL_DROP = 0.055f
        const val CONE_RAD = 0.05f
        const val BREATH_MS = 2400L

        /**
         * How long somebody waves at a dot before being offered another way.
         *
         * Long enough that a wearer who is simply looking around is not told
         * they have failed, short enough that somebody whose hand tracking is
         * genuinely dead is not left there.
         */
        const val HINT_MS = 12_000L

        const val WIDEST = "TOUCH THIS"
        const val HINT_WIDEST = "OR LOOK AT IT AND HOLD"
    }
}
