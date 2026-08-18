// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.content.Context
import android.util.Log
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
            session, context,
            com.iotj.meshmore.xr.L10n.tpl(WIDEST, WIDEST_JA),
            com.iotj.meshmore.xr.L10n.cap(CAP), argb(theme.text, 0.95f), "notice",
        )?.also {
            it.entity.parent = session.scene.activitySpace
            it.entity.setEnabled(false)
        }
    }

    /**
     * Show [text] for a few seconds.
     *
     * LOGGED, because a band is the one surface whose whole job is to have
     * said something and then stop existing. Nothing else records it, so an
     * unanswered "did it tell me?" had no way to be settled — including for
     * the notices raised on glass, where nobody can read a screenshot back.
     *
     * The clip is logged separately and as a warning: a sentence trimmed to
     * the template's width is not a shorter sentence, it is a different one,
     * and the Japanese template is a different length again.
     */
    fun say(text: String) {
        val r = run ?: return
        // IN CELLS, because the band's own template is. Counting code units
        // here cost the region warning half of itself the first time it was
        // said in Japanese —
        //
        //   CLIPPED at 23 of 42: 無線機はUSA / CANADA設定 — 現在地はJAPAN…
        //
        // 23 was the template's character count; the plate is 46 cells wide,
        // and the sentence is a mixture of kanji at two cells and Latin at one,
        // so measuring the mixture with `length` threw away everything after
        // the dash. That the sentence was the ILLEGAL-BAND warning is luck
        // deciding which string got mismeasured.
        val cap = TypeTier.displayCells(com.iotj.meshmore.xr.L10n.tpl(WIDEST, WIDEST_JA))
        val shown = if (TypeTier.displayCells(text) <= cap) text else TypeTier.clip(text, cap)
        if (shown !== text) {
            Log.w(TAG, "[notice] CLIPPED at $cap cells: '$text'")
        } else {
            Log.i(TAG, "[notice] $shown")
        }
        r.setText(shown)
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

    /**
     * INTERNAL, not private: the sizing templates are what every notice string
     * has to fit, and StringsParityTest measures them against it. A test that
     * copied these two strings instead would pass happily the day one of them
     * changed.
     */
    internal companion object {
        /** Sized once for the longest answer either spoke produces. */
        private const val TAG = "MeshmoreXR"
        const val WIDEST = "MMMMMMMMMMMMMM 99.9KM   MMMMMMMMMMMMMM 99.9KM"
        /** Widest JA notice: a 12-char tag plus the made-channel phrase. */
        const val WIDEST_JA = "MMMMMMMMMMMM 作成 — 口頭で共有"
        const val CAP = 0.026f
        const val DIST = 1.15f
        /** About -17 deg: under the world window, above the dock. */
        const val DROP = -0.35f
        const val HOLD_MS = 5000L
    }
}
