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
    private var lastText = ""

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
        setVisible(false)
        Log.i(TAG, "[hands] ${order.size} joints per hand")
    }

    private suspend fun joint(root: Entity, rgb: Int): MeshEntity = MeshEntity.create(
        session, Prims.build(session, Prims.mote(JOINT_R, 4, 6)),
        listOf(Prims.material(session, rgb, 0.9f)),
    ).also { it.parent = root; it.setEnabled(false); entities += it }

    fun setVisible(v: Boolean) {
        visible = v
        entities.forEach { runCatching { it.setEnabled(v) } }
        readout?.entity?.let { runCatching { it.setEnabled(v) } }
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

        val text = "R ${short(r?.trackingState?.toString())} ${letter(r?.handJoints)}   " +
            "L ${short(l?.trackingState?.toString())} ${letter(l?.handJoints)}"
        if (text != lastText) {
            lastText = text
            showReadout(text, head)
        }
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

    private fun short(s: String?): String =
        s?.substringAfter("(")?.substringBefore(")")?.take(4) ?: "----"

    /**
     * Tier R, because the readout carries state rather than a fixed legend.
     *
     * Placed along the head's FORWARD axis rather than at a fixed world offset.
     * The offset version sat at (x, y-0.3, z-0.75) whatever direction the user
     * was facing, so it drifted off to the side and was read edge-on — which is
     * why half of it appeared to be missing. It was not clipped; it was turned
     * away.
     */
    private suspend fun showReadout(text: String, head: Pose?) {
        if (head == null) return
        val q = head.rotation
        val t = head.translation
        // Head forward, flattened: the readout should sit in front of the user,
        // not tilt with their chin.
        val fx = 2f * (q.x * q.z + q.w * q.y)
        val fz = 1f - 2f * (q.x * q.x + q.y * q.y)
        val yaw = kotlin.math.atan2(-fx, fz)
        val at = Vector3(
            t.x + kotlin.math.sin(yaw) * READ_D,
            t.y - 0.26f,
            t.z - kotlin.math.cos(yaw) * READ_D,
        )
        val face = androidx.xr.runtime.math.Quaternion.fromEulerAngles(
            0f, -Math.toDegrees(yaw.toDouble()).toFloat(), 0f,
        )
        val fresh = TextRun.create(session, context, text, 0.020f, 0xFFCCE8F0.toInt(), "handdiag")
            ?: return
        fresh.entity.parent = session.scene.activitySpace
        fresh.entity.setPose(Pose(at, face), Space.ACTIVITY)
        val old = readout
        readout = fresh
        entities += fresh.entity
        runCatching {
            old?.entity?.let { entities.remove(it); it.parent = null; (it as Entity).dispose() }
        }
    }

    fun clear() {
        rightJoints.clear(); leftJoints.clear(); readout = null; lastText = ""
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
    }
}
