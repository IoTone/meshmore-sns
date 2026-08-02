// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.content.Context
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Quaternion
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene

/**
 * ONE LINE, BRIEFLY — the answer to a question you just asked.
 *
 * BEARING and NEAREST have something to say and nowhere to say it. Everything
 * else in this app is persistent: the ring is the mesh, the microhud is state,
 * the rack is configuration. An answer is none of those. It is a reply to a
 * question asked a second ago, it stops being interesting almost immediately,
 * and giving it a permanent home would mean the home is empty most of the time.
 *
 * So it appears in front of you, says one thing, and fades. Head-locked in yaw
 * because you asked while looking somewhere and the answer is about that place;
 * placed BELOW the world window so it never covers the thing it describes.
 *
 * ONE PANEL, REUSED — the readout lesson, applied without having to relearn it.
 * Building a panel per notice would churn an Android View and its surface every
 * time somebody pinched a menu.
 */
class Notice(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    private var run: TextRun.Run? = null
    private var until = 0L
    private var at = Vector3(0f, 0f, 0f)

    suspend fun build() {
        clear()
        run = TextRun.reusable(
            session, context, WIDEST, CAP, argb(theme.text, 0.95f), "notice",
        )?.also {
            it.entity.parent = session.scene.activitySpace
            it.entity.setEnabled(false)
        }
    }

    /** Show [text] for a few seconds. */
    fun say(text: String) {
        val r = run ?: return
        r.setText(text.take(WIDEST.length))
        until = android.os.SystemClock.uptimeMillis() + HOLD_MS
        runCatching { r.entity.setEnabled(true) }
    }

    fun tick(head: Pose?) {
        val r = run ?: return
        if (android.os.SystemClock.uptimeMillis() > until) {
            runCatching { r.entity.setEnabled(false) }
            return
        }
        head ?: return
        val q = head.rotation
        val t = head.translation
        val fx = 2f * (q.x * q.z + q.w * q.y)
        val fz = 1f - 2f * (q.x * q.x + q.y * q.y)
        val yaw = kotlin.math.atan2(-fx, fz)
        at = Vector3(
            t.x + kotlin.math.sin(yaw) * DIST,
            t.y + DROP,
            t.z - kotlin.math.cos(yaw) * DIST,
        )
        runCatching {
            r.entity.setPose(
                Pose(at, Quaternion.fromEulerAngles(
                    0f, -Math.toDegrees(yaw.toDouble()).toFloat(), 0f)),
                Space.ACTIVITY,
            )
        }
    }

    fun clear() {
        runCatching { run?.entity?.let { (it as Entity).parent = null; it.dispose() } }
        run = null
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        /** Sized once for the longest answer either spoke produces. */
        const val WIDEST = "MMMMMMMMMMMMMM 99.9KM   MMMMMMMMMMMMMM 99.9KM"
        const val CAP = 0.020f
        const val DIST = 1.15f
        /** About -17 deg: under the world window, above the dock. */
        const val DROP = -0.35f
        const val HOLD_MS = 5000L
    }
}
