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
import kotlin.math.atan2

/**
 * A FIXED SET OF LABELS, LENT OUT — because a PanelEntity is expensive and we
 * are about to want a lot of them.
 *
 * Every tier R label is a real Android View with its own Surface and texture.
 * At 24 labels that is merely wasteful; the magnified-cluster view wants 120,
 * which is roughly 40 MB of texture and 120 compositor layers, and churning six
 * of them several times a second was already enough to put the device into
 * thermal throttle this afternoon.
 *
 * So panels are never created per node. A fixed number exist for the life of
 * the surface, each rasterised once at a FIXED PIXEL SIZE, and a build borrows
 * them: set the text, set the world size, place it. Nothing is allocated, no
 * surface is created, no texture is uploaded.
 *
 * FIXED PIXELS, VARIABLE METRES. The two sizes a panel has are independent, and
 * that is what makes pooling possible at all: labels differ in length and in
 * range — a near node's callsign is physically larger than a far one's so that
 * both subtend the same angle — but they can all be rasterised into the same
 * box and then scaled in the world. Short text simply carries more transparent
 * margin, which on an additive display emits nothing.
 *
 * THE COST OF THIS DESIGN, stated plainly: every label rasterises at the same
 * pixel density, so a physically large label is sampled from the same texels as
 * a small one and will be softer. At the sizes involved — 1.4 degrees of cap
 * height either way — that is invisible. If a surface ever wants genuinely
 * large type, it should not come from here.
 */
class LabelPool(
    private val session: Session,
    private val context: Context,
    private val capacity: Int = DEFAULT_CAPACITY,
) {

    private class Slot(val run: TextRun.Run) {
        var at: Vector3 = Vector3(0f, 0f, 0f)
        var live = false
    }

    private val slots = mutableListOf<Slot>()
    private var lent = 0

    /** Built once. [argb] is the ink; per-label colour would need per-label panels. */
    suspend fun build(argb: Int) {
        clear()
        val root = session.scene.activitySpace
        repeat(capacity) {
            val run = TextRun.reusable(session, context, TEMPLATE, TEMPLATE_CAP, argb, "label")
                ?: return@repeat
            run.entity.parent = root
            run.entity.setEnabled(false)
            slots += Slot(run)
        }
        Log.i(TAG, "[labels] pool of ${slots.size}")
    }

    /** Start a build. Everything lent last time goes back. */
    fun begin() {
        lent = 0
        slots.forEach { it.live = false; runCatching { it.run.entity.setEnabled(false) } }
    }

    /**
     * Borrow a label. Returns false when the pool is empty, which is a real
     * answer rather than a failure: the caller draws the mote without a name,
     * exactly as it would for a node the layout could not label.
     */
    fun place(text: String, at: Vector3, capHeightM: Float): Boolean {
        if (lent >= slots.size) return false
        val s = slots[lent++]
        s.run.setText(text)
        // World size from cap height. The panel's PIXEL size never changes; only
        // how large that fixed raster is drawn in the room — which is why this
        // is a SCALE and not an assignment to `size`. Assigning `size` re-derives
        // the pixel size from the runtime's default density and silently
        // re-rasterises the view at whatever that comes to.
        s.run.setCapHeight(capHeightM)
        s.at = at
        s.live = true
        runCatching {
            s.run.entity.setEnabled(true)
            s.run.entity.setPose(Pose(at), Space.ACTIVITY)
        }
        return true
    }

    /** How many labels this build could not have. Worth logging, never guessing. */
    fun exhausted(wanted: Int): Int = (wanted - slots.size).coerceAtLeast(0)

    /**
     * Dim every live label. Used to recede the ring behind a FOCUS surface —
     * the pool owns these entities, so Horizon cannot reach them per-peer.
     */
    fun setAlpha(a: Float) {
        slots.forEach { s -> if (s.live) runCatching { s.run.entity.setAlpha(a) } }
    }

    /** Turn every live label toward the viewer. */
    fun faceViewer(head: Vector3) {
        slots.forEach { s ->
            if (!s.live) return@forEach
            val dx = head.x - s.at.x
            val dz = head.z - s.at.z
            if (dx * dx + dz * dz < 1e-6f) return@forEach
            runCatching {
                s.run.entity.setPose(
                    Pose(s.at, Quaternion.fromEulerAngles(
                        0f, Math.toDegrees(atan2(dx, dz).toDouble()).toFloat(), 0f)),
                    Space.ACTIVITY,
                )
            }
        }
    }

    fun clear() {
        val doomed = slots.map { it.run.entity }
        slots.clear(); lent = 0
        doomed.forEach { runCatching { (it as Entity).parent = null } }
        doomed.forEach { runCatching { (it as Entity).dispose() } }
    }

    private companion object {
        const val TAG = "MeshmoreXR"
        /**
         * Enough for a full ring plus the magnified-cluster view's forward arc.
         * Not enough for 120 at once, deliberately — see the culling rule in
         * Horizon: a label behind you is a texture nobody reads.
         */
        const val DEFAULT_CAPACITY = 40
        /**
         * The raster every label shares. Wide enough for a clipped callsign at
         * MAX_LABEL_CELLS, and under the 2048 px ceiling TextRun enforces.
         */
        const val TEMPLATE = "MMMMMMMMMMMMMMMMMM"
        const val TEMPLATE_CAP = 0.05f
    }
}
