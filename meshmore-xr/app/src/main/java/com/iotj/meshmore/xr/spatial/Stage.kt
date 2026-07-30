// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.util.Log
import androidx.xr.arcore.ArDevice
import androidx.xr.runtime.Config
import androidx.xr.runtime.DeviceTrackingMode
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Quaternion
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * The STAGE — where the experience is, relative to the body, and the floor it
 * stands on.
 *
 * Two problems this solves, both of which make an XR app feel broken:
 *
 * 1. CONTENT BEHIND THE USER. activitySpace's origin is wherever the app
 *    happened to start, which is not where the user is standing or which way
 *    they are facing. Placing a 360-degree ring at that origin can leave the
 *    whole experience behind their back. We read the head pose ONCE at launch
 *    and recentre on it, taking only the YAW -- pitch and roll must not tip the
 *    world, and a horizon that rolls with your head is nauseating.
 *
 * 2. NO FLOOR. Without a ground plane there is no sense of scale or of standing
 *    anywhere. We estimate the floor from eye height and drop a Tron-style grid
 *    into it, so the first thing the experience does is claim the room.
 */
class Stage(private val session: Session, private val theme: Horizon.Palette) {

    /** Where the user was, and which way they faced, when the app opened. */
    data class Origin(val x: Float, val y: Float, val z: Float, val yawRad: Float) {
        /** Head-relative placement: bearing is measured from the launch facing. */
        fun place(bearingRad: Float, radius: Float, height: Float): Vector3 {
            val a = yawRad + bearingRad
            return Vector3(x + sin(a) * radius, y + height, z - cos(a) * radius)
        }
    }

    private val tiles = mutableListOf<MeshEntity>()
    private var floorY = 0f
    private var head: Pose? = null

    /**
     * A point [d] metres along the head's TRUE forward axis, pitch included.
     * Only for calibration: anything placed here is centred in the FOV whatever
     * the head is doing, which is what you need when the question is "does this
     * render at all" rather than "is it in the right place".
     */
    fun eyeline(d: Float): Vector3? {
        val h = head ?: return null
        val q = h.rotation
        val t = h.translation
        val fx = -2f * (q.x * q.z + q.w * q.y)
        val fy = -2f * (q.y * q.z - q.w * q.x)
        val fz = -(1f - 2f * (q.x * q.x + q.y * q.y))
        return Vector3(t.x + fx * d, t.y + fy * d, t.z + fz * d)
    }

    /**
     * Read the head pose. Returns a body-centred origin, or a safe default if
     * device tracking is unavailable -- a missing capability must degrade,
     * never throw.
     *
     * WHY THIS POLLS: `configure()` returns before the tracker has produced a
     * single sample, so reading `state.value` on the next line yields the
     * IDENTITY pose -- position (0,0,0), yaw 0. That is indistinguishable from
     * "the user is standing exactly on the tracking origin, facing its -Z", so
     * it fails silently and mis-anchors the entire experience: the floor lands
     * at the wrong height and the ring faces an arbitrary direction. Waiting a
     * few frames for a pose that has actually moved off the origin costs a
     * fraction of a second at launch and is the difference between the scene
     * landing on the body and landing wherever the tracker booted.
     */
    suspend fun recentre(): Origin {
        val fallback = Origin(0f, 0f, 0f, 0f)
        try {
            session.configure(Config(deviceTracking = DeviceTrackingMode.SPATIAL))
        } catch (t: Throwable) {
            Log.w(TAG, "[stage] no device tracking (${t.javaClass.simpleName}) — using activity origin")
            return fallback
        }

        var pose: Pose? = null
        for (i in 0 until POSE_TRIES) {
            val p = runCatching { ArDevice.getInstance(session).state.value.devicePose }.getOrNull()
            if (p != null) {
                pose = p
                val t = p.translation
                // Identity means "no sample yet". A real head pose is essentially
                // never exactly zero on all three axes.
                if (abs(t.x) > EPS || abs(t.y) > EPS || abs(t.z) > EPS) {
                    Log.i(TAG, "[stage] pose settled after $i polls")
                    break
                }
            }
            delay(POSE_POLL_MS)
        }
        val settled = pose ?: run {
            Log.w(TAG, "[stage] no device pose — using activity origin")
            return fallback
        }

        // FRAME CONVERSION -- the step whose absence makes everything invisible.
        // ArDevice reports the head in ARCore's PERCEPTION space. SceneCore's
        // Space.ACTIVITY is a different frame, so feeding a perception pose
        // straight into setPose(..., REAL_WORLD) silently scatters the scene
        // somewhere outside the FOV: entities report enabled, alpha 1, sane
        // bounds, and simply are not where you asked. perceptionSpace bridges
        // the two; from here on everything is placed in ACTIVITY space.
        val inActivity = session.scene.perceptionSpace
            .getScenePoseFromPerceptionPose(settled).poseInActivitySpace
        head = inActivity
        val p = inActivity.translation
        val q = inActivity.rotation
        // Forward vector of the head, flattened to the horizontal plane: yaw only.
        //
        // Rotating the camera's forward axis (0,0,-1) by q gives the NEGATED
        // third column of the rotation matrix:
        //     forward = ( -2(xz + wy),  -2(yz - wx),  -(1 - 2(x² + y²)) )
        // so with fx and fz as written below, forward.x = -fx and forward.z = -fz.
        val fx = 2f * (q.x * q.z + q.w * q.y)
        val fz = 1f - 2f * (q.x * q.x + q.y * q.y)
        // place() maps bearing 0 to (sin a, -cos a). Matching that to forward
        // needs sin a = forward.x = -fx and cos a = -forward.z = fz, i.e.
        // atan2(-fx, fz). The X sign is easy to lose because it VANISHES at
        // identity -- fx is 0 there, so atan2(fx, fz) also yields 0 and the bug
        // survives every bench test done facing the tracking origin. Off-axis it
        // MIRRORS the scene about the forward axis: at yaw 72 deg the entire
        // experience lands 144 deg away, just behind the user's shoulder.
        val yaw = atan2(-fx, fz)

        // EYE_HEIGHT is an estimate, not a measurement. A detected FLOOR plane
        // would be better, but plane detection takes seconds and the launch
        // must not wait on it -- so estimate now, refine later if we choose to.
        floorY = p.y - EYE_HEIGHT
        Log.i(TAG, "[stage] recentre at (%.2f, %.2f, %.2f) yaw=%.1f° floorY=%.2f"
            .format(p.x, p.y, p.z, Math.toDegrees(yaw.toDouble()), floorY))
        return Origin(p.x, p.y, p.z, yaw)
    }

    /**
     * The Tron floor. A grid of thin extruded bars laid on the estimated floor,
     * built once and then FALLEN into place: each ring of tiles drops from above
     * with a short stagger, so the room assembles outward from under the user.
     *
     * Bars, not lines: GPU line width is ignored on most platforms and a 1 px
     * line is invisible in bright passthrough anyway.
     */
    suspend fun buildFloor(o: Origin) {
        clearFloor()
        val root = session.scene.activitySpace
        val mat = Prims.material(session, theme.accent, 0.55f)
        val matDim = Prims.material(session, theme.accent, 0.22f)

        val half = GRID_N / 2
        for (i in -half..half) {
            val major = (i % 4 == 0)
            val len = GRID_N * CELL
            // one bar per grid line, both axes
            val alongX = Prims.build(session, Prims.bar(len, BAR, BAR))
            val alongZ = Prims.build(session, Prims.bar(BAR, BAR, len))
            listOf(alongX to Vector3(0f, 0f, i * CELL), alongZ to Vector3(i * CELL, 0f, 0f))
                .forEach { (mesh, off) ->
                    val e = MeshEntity.create(session, mesh, listOf(if (major) mat else matDim))
                    e.parent = root
                    // rotate the grid to the user's launch facing so it reads as
                    // "aligned to me", not to whatever the tracker's origin was
                    val a = o.yawRad
                    val rx = off.x * cos(a) - off.z * sin(a)
                    val rz = off.x * sin(a) + off.z * cos(a)
                    e.setPose(
                        Pose(
                            Vector3(o.x + rx, floorY, o.z + rz),
                            Quaternion.fromEulerAngles(0f, Math.toDegrees(a.toDouble()).toFloat(), 0f),
                        ),
                        Space.ACTIVITY,
                    )
                    e.setAlpha(0f)
                    tiles += e
                }
        }
        Log.i(TAG, "[stage] floor: ${tiles.size} bars at y=%.2f".format(floorY))
    }

    /**
     * Drive the fall-in. [t] runs 0..1; rings land outward from the centre so
     * the grid unrolls from under the user's feet.
     */
    fun tickFloor(t: Float) {
        val n = tiles.size
        tiles.forEachIndexed { i, e ->
            // ring index from the middle of the list -> stagger by distance
            val ring = kotlin.math.abs(i - n / 2).toFloat() / max(1, n / 2)
            val local = ((t - ring * 0.45f) / 0.55f).coerceIn(0f, 1f)
            val ease = 1f - (1f - local) * (1f - local)   // ease-out quad
            e.setAlpha(ease * 0.9f)
            val drop = (1f - ease) * FALL_FROM
            val p = e.getPose(Space.ACTIVITY)
            e.setPose(
                Pose(Vector3(p.translation.x, floorY + drop, p.translation.z), p.rotation),
                Space.ACTIVITY,
            )
        }
    }

    fun floorHeight() = floorY

    fun clearFloor() {
        tiles.forEach { runCatching { (it as Entity).dispose() } }
        tiles.clear()
    }

    companion object {
        private const val TAG = "MeshmoreXR"
        /** Standing eye height. An estimate; a FLOOR plane would refine it. */
        const val EYE_HEIGHT = 1.60f
        private const val GRID_N = 16
        private const val CELL = 0.6f
        private const val BAR = 0.012f
        private const val FALL_FROM = 2.2f
        /** ~1.2 s of polling: long enough for the tracker, short enough to feel instant. */
        private const val POSE_TRIES = 40
        private const val POSE_POLL_MS = 30L
        private const val EPS = 1e-4f
    }
}
