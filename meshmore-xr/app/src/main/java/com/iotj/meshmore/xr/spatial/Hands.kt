// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.content.Context
import android.util.Log
import androidx.xr.arcore.Hand
import androidx.xr.arcore.HandJointType
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene

/**
 * THE HANDS, DRAWN — so a gesture that does not fire can be told apart from a
 * hand that was never seen.
 *
 * The ASL toggles did not work on the glasses and the log could not say why.
 * Both hands reported PAUSED with zero joints, which is the correct reading for
 * "no hand in view" and is indistinguishable from "hand tracking is broken",
 * "the permission is missing", "the hand was outside the camera's cone", and
 * "the classifier's thresholds are wrong". Four different faults, one symptom,
 * no way to choose between them from a distance.
 *
 * So: draw the skeleton. A hand you can SEE tracked answers the first three
 * outright, and the fourth becomes a calibration problem rather than a mystery —
 * you can watch the letter readout change as you close your fingers and find
 * where the threshold actually sits.
 *
 * This is scaffolding with a real job, not a toy. It stays behind a dock pip
 * because a permanent skeleton is a permanent distraction, and it earns its
 * place for exactly as long as gestures are unreliable.
 */
class Hands(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    private val entities = mutableListOf<Entity>()
    private val rightJoints = mutableListOf<MeshEntity>()
    private val leftJoints = mutableListOf<MeshEntity>()
    private var readout: TextRun.Run? = null
    private var readoutL: TextRun.Run? = null
    private var lastText = ""
    private var lastAt = 0L

    var visible: Boolean = false
        private set

    private val order = HandJointType.entries.toList()

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        // Right and left are told apart by COLOUR, because the whole point is
        // to check that right-A and left-A do different things — and two
        // identical skeletons cannot tell you which one the app thinks it saw.
        repeat(order.size) {
            rightJoints += joint(root, theme.accent)
            leftJoints += joint(root, theme.alt)
        }

        // ONE panel, sized once for the widest string it will ever hold. Built
        // from a template rather than from live text so the geometry never
        // moves as the numbers change.
        // TWO LINES, ONE PER HAND. A single line carrying both was 88
        // characters and asked for a panel wider than the device would give.
        // It is also the wrong shape: you are looking at one hand at a time.
        val template = "R TRAC NONE back p0.00 i0.00 m0.00 r0.00 l0.00"
        readout = TextRun.reusable(
            session, context, template, 0.020f, 0xFFCCE8F0.toInt(), "handdiagR",
        )?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }
        readoutL = TextRun.reusable(
            session, context, template, 0.020f, 0xFFCCE8F0.toInt(), "handdiagL",
        )?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }
        setVisible(false)
        Log.i(TAG, "[hands] ${order.size} joints per hand")
    }

    private suspend fun joint(root: Entity, rgb: Int): MeshEntity = MeshEntity.create(
        session, Prims.build(session, Prims.mote(JOINT_R, 4, 6)),
        listOf(Prims.material(session, rgb, 0.9f)),
    ).also { it.parent = root; it.setEnabled(false); entities += it }

    fun setVisible(v: Boolean) {
        visible = v
        // Joints are enabled by tick() as the tracker reports them, so hiding
        // must not be undone by the next frame — but SHOWING must not enable
        // every joint either, or a hand that is not being tracked appears as a
        // full skeleton frozen wherever it last was.
        entities.forEach { runCatching { it.setEnabled(false) } }
        readout?.entity?.let { runCatching { it.setEnabled(v) } }
        readoutL?.entity?.let { runCatching { it.setEnabled(v) } }
        if (!v) lastText = ""
    }

    /**
     * Place the skeletons and update the readout.
     *
     * A joint the tracker did not report is HIDDEN rather than left where it
     * was. A stale joint is worse than a missing one: it looks like tracking,
     * and it is the last place the finger was rather than where it is.
     */
    suspend fun tick(right: Hand?, left: Hand?, head: Pose?) {
        if (!visible) return
        val r = right?.state?.value
        val l = left?.state?.value
        place(rightJoints, r?.handJoints)
        place(leftJoints, l?.handJoints)

        // THROTTLED. The classification flickers between letters as fingers
        // move, and updating on every change meant several panel writes a
        // second. 4 Hz is faster than anyone reads and slow enough to be free.
        val now = android.os.SystemClock.uptimeMillis()
        if (now - lastAt >= READOUT_MS) {
            lastAt = now
            // The RATIOS, not just the verdict. "NONE" tells you the classifier
            // rejected the shape and nothing about why; the numbers tell you
            // which finger it thinks is still extended, which is the one thing
            // needed to move a threshold. Debugging a classifier from its output
            // alone is guessing.
            val ar = palmAway(r?.handJoints, head, rightHand = true)
            val al = palmAway(l?.handJoints, head, rightHand = false)
            val tr = "R " + row(r?.trackingState?.toString(), r?.handJoints, ar)
            val tl = "L " + row(l?.trackingState?.toString(), l?.handJoints, al)
            if (tr + tl != lastText) {
                lastText = tr + tl
                readout?.setText(tr)
                readoutL?.setText(tl)
                // Logged too, so a test run leaves evidence even when nobody
                // thought to read the panel. The thresholds have now been
                // guessed at twice; this is the datum that ends that.
                Log.i(TAG, "[hands] $tr | $tl")
            }
        }
        place(readoutAt(head))
    }

    /** `TRAC A back i0.9 m0.9 r0.9 l0.9` — verdict, orientation, then evidence. */
    private fun row(
        state: String?, j: Map<HandJointType, Pose>?, away: Boolean?,
    ): String {
        val st = short(state)
        if (j.isNullOrEmpty()) return "$st --"
        val face = when (away) { true -> "back"; false -> "palm"; null -> "?" }
        return "$st ${HandSign.classify(j, away).name.take(4)} $face ${HandSign.ratios(j)}"
    }

    /**
     * THE FRAME CONVERSION, and the reason the skeleton floated in mid-air three
     * feet from the hand it belonged to.
     *
     * Hand joints arrive in ARCore's PERCEPTION space. SceneCore's Space.ACTIVITY
     * is a different frame, so posing a joint straight into it puts the hand
     * wherever the two origins happen to differ — which looks like a tiny
     * cluster of dots hovering somewhere in the room, tracking your fingers
     * perfectly and following none of your movements.
     *
     * This is the SAME bug the head pose had in P0, where it made the entire
     * scene land outside the FOV, and it is the same fix. It is worth noticing
     * that it recurred: any API that hands back a Pose from the perception layer
     * needs this, and nothing in the type system says so.
     */
    private fun place(into: List<MeshEntity>, joints: Map<HandJointType, Pose>?) {
        val ps = session.scene.perceptionSpace
        order.forEachIndexed { i, type ->
            val e = into.getOrNull(i) ?: return@forEachIndexed
            val p = joints?.get(type)
            if (p == null) {
                runCatching { e.setEnabled(false) }
            } else {
                runCatching {
                    val inActivity = ps.getScenePoseFromPerceptionPose(p).poseInActivitySpace
                    e.setEnabled(true)
                    e.setPose(Pose(inActivity.translation), Space.ACTIVITY)
                }
            }
        }
    }

    private fun letter(j: Map<HandJointType, Pose>?): String =
        if (j.isNullOrEmpty()) "--" else HandSign.classify(j).name

    /**
     * Is the palm turned away from the wearer?
     *
     * Everything is converted to ACTIVITY space first. The palm normal is a
     * DIRECTION, and the perception and activity frames need not share an
     * orientation — comparing a normal computed in one frame against a head
     * position in the other would be comparing two different rooms.
     *
     * Null when the joints or the head are not available: the caller treats
     * that as "unknown" and judges the shape alone, rather than refusing every
     * letter whenever a knuckle drops out.
     */
    fun palmAway(j: Map<HandJointType, Pose>?, head: Pose?, rightHand: Boolean): Boolean? {
        j ?: return null
        head ?: return null
        val ps = session.scene.perceptionSpace
        fun act(t: HandJointType): Vector3? = runCatching {
            ps.getScenePoseFromPerceptionPose(j[t] ?: return null).poseInActivitySpace.translation
        }.getOrNull()
        val w = act(HandJointType.WRIST) ?: return null
        val i = act(HandJointType.INDEX_PROXIMAL) ?: return null
        val l = act(HandJointType.LITTLE_PROXIMAL) ?: return null
        val (nx, ny, nz) = HandSign.palmNormal(
            w.x, w.y, w.z, i.x, i.y, i.z, l.x, l.y, l.z, rightHand,
        )
        if (nx == 0f && ny == 0f && nz == 0f) return null
        val h = head.translation
        // Away from the head: the normal and the head-to-hand direction agree.
        val dx = w.x - h.x; val dy = w.y - h.y; val dz = w.z - h.z
        val dot = nx * dx + ny * dy + nz * dz
        return dot > 0f
    }

    /**
     * Is this hand being PRESENTED, or just present?
     *
     * The spread test tells a deliberate flat hand from a splayed one, but it
     * is a threshold on a tracked joint and thresholds are wrong until hardware
     * says otherwise. This is the part that does not depend on one: a hand you
     * are signing with is UP, and a hand you have stopped using hangs.
     *
     * Only 'B' consults it. 'A' is a fist — a shape hands do not fall into by
     * relaxing — and it works today; adding a condition to it would risk what
     * is already right to guard against something that has never happened.
     *
     * Null when the joints or the head are unavailable, which callers treat as
     * "do not fire" rather than as "presented".
     */
    fun presented(j: Map<HandJointType, Pose>?, head: Pose?): Boolean? {
        j ?: return null
        head ?: return null
        val ps = session.scene.perceptionSpace
        val w = runCatching {
            ps.getScenePoseFromPerceptionPose(
                j[HandJointType.WRIST] ?: return null,
            ).poseInActivitySpace.translation
        }.getOrNull() ?: return null
        return w.y > head.translation.y - PRESENT_DROP
    }

    /**
     * HOW SQUARELY THE PALM FACES THE WEARER, from -1 to +1.
     *
     * [palmAway] answers the same question as a boolean, and a boolean cannot
     * carry hysteresis — §5 requires the reveal and the hide to sit at
     * DIFFERENT thresholds, because a single one makes a hand-anchored surface
     * strobe as the wrist hovers at the boundary, and "flicker on a
     * hand-anchored element is the most nauseating failure mode available in
     * XR". The gap between the two is the feature, so the caller needs the
     * number.
     *
     * +1 is the palm square on to the wearer. Null when the joints or the head
     * are unavailable, which callers must treat as "do not reveal" rather than
     * as zero.
     */
    fun palmDot(j: Map<HandJointType, Pose>?, head: Pose?, rightHand: Boolean): Float? {
        j ?: return null
        head ?: return null
        val ps = session.scene.perceptionSpace
        fun act(t: HandJointType): Vector3? = runCatching {
            ps.getScenePoseFromPerceptionPose(j[t] ?: return null).poseInActivitySpace.translation
        }.getOrNull()
        val w = act(HandJointType.WRIST) ?: return null
        val i = act(HandJointType.INDEX_PROXIMAL) ?: return null
        val l = act(HandJointType.LITTLE_PROXIMAL) ?: return null
        val (nx, ny, nz) = HandSign.palmNormal(
            w.x, w.y, w.z, i.x, i.y, i.z, l.x, l.y, l.z, rightHand,
        )
        if (nx == 0f && ny == 0f && nz == 0f) return null
        val h = head.translation
        var dx = w.x - h.x; var dy = w.y - h.y; var dz = w.z - h.z
        val d = kotlin.math.sqrt(dx * dx + dy * dy + dz * dz)
        if (d < 1e-4f) return null
        dx /= d; dy /= d; dz /= d
        val n = kotlin.math.sqrt(nx * nx + ny * ny + nz * nz)
        if (n < 1e-6f) return null
        // palmAway is this dot being POSITIVE, so facing the wearer is its
        // negation. Same convention, one more digit of it.
        return -((nx * dx + ny * dy + nz * dz) / n)
    }

    private fun short(s: String?): String =
        s?.substringAfter("(")?.substringBefore(")")?.take(4) ?: "----"

    /** Where the readout sits: in front of the head, facing it, level. */
    private fun readoutAt(head: Pose?): Pair<Vector3, androidx.xr.runtime.math.Quaternion>? {
        head ?: return null
        val q = head.rotation
        val t = head.translation
        // Head forward, FLATTENED. The readout should sit in front of the user
        // rather than tilt with their chin — and the earlier version placed it
        // at a fixed world offset regardless of facing, so it drifted to the
        // side and was read edge-on, which looks exactly like a label cut in
        // half through its own centre.
        val fx = 2f * (q.x * q.z + q.w * q.y)
        val fz = 1f - 2f * (q.x * q.x + q.y * q.y)
        val yaw = kotlin.math.atan2(-fx, fz)
        return Vector3(
            t.x + kotlin.math.sin(yaw) * READ_D,
            t.y - 0.24f,
            t.z - kotlin.math.cos(yaw) * READ_D,
        ) to androidx.xr.runtime.math.Quaternion.fromEulerAngles(
            0f, -Math.toDegrees(yaw.toDouble()).toFloat(), 0f,
        )
    }

    private fun place(at: Pair<Vector3, androidx.xr.runtime.math.Quaternion>?) {
        val (p, r) = at ?: return
        runCatching { readout?.entity?.setPose(Pose(p, r), Space.ACTIVITY) }
        runCatching {
            readoutL?.entity?.setPose(Pose(Vector3(p.x, p.y - LINE, p.z), r), Space.ACTIVITY)
        }
    }

    fun clear() {
        rightJoints.clear(); leftJoints.clear(); readout = null; readoutL = null
        lastText = ""; lastAt = 0L
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private companion object {
        const val TAG = "MeshmoreXR"
        /**
         * A joint marker, in metres. 9 mm against a ~20 cm hand reads as a
         * skeleton; much larger and adjacent knuckles merge into a mitten,
         * which is exactly the distinction the classifier is being judged on.
         *
         * It looked tiny before because it was in the wrong place — three feet
         * away, where 6 mm subtends almost nothing. At the hand it is right.
         */
        const val JOINT_R = 0.009f
        /** Readout distance: close enough to read, past the reach surfaces. */
        const val READ_D = 0.9f
        /** 4 Hz. Faster than anyone reads, slow enough to cost nothing. */
        const val READOUT_MS = 250L
        /** Gap between the two hand rows. */
        const val LINE = 0.032f
        /**
         * How far below the eye a wrist may be and still count as presented.
         * 0.55 m is about chest height on a standing adult: comfortably above
         * a hand at rest by the hip, comfortably below one held up to sign.
         */
        const val PRESENT_DROP = 0.55f
    }
}
