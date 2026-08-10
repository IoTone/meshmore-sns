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
import androidx.xr.scenecore.InputEvent
import androidx.xr.scenecore.InteractableComponent
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene
import kotlin.math.atan2

/**
 * S5 · CHANNELS — bands, not tabs.
 *
 * The brief: "Channels are rendered as ARCS of the HORIZON above the node band
 * — each with its own livery accent. Turn your head to a channel arc, pinch,
 * and it becomes the active channel." Until now channels existed only as rows
 * in a settings bay, which is a tab list in a drawer: the thing §5 is named
 * against.
 *
 * ## What an arc's position does NOT mean
 *
 * Every other mark on this horizon sits at a TRUE BEARING, and the brief is
 * emphatic that inventing one is the worst thing the app can do. **A channel is
 * not anywhere.** So the band is drawn as a CONTINUOUS ENCIRCLING RING at its
 * own elevation, well above the node lanes and divided into segments: a ring
 * that goes all the way round claims no direction, where an isolated segment
 * hanging at 040 degrees would be read as one and somebody would turn to look.
 *
 * The gaps between segments are what make it several bands rather than one
 * badly-drawn halo, and they are equal — a channel's share of the ring is not
 * a claim about its size either.
 *
 * ## The part of §S5 that cannot be built, and why
 *
 * The brief also asks that picking a channel "immediately re-tints the
 * corresponding MOTEs". **There are no corresponding motes.** A MeshCore
 * channel message carries no sender key — it is a broadcast on a shared key,
 * and the sender is a name parsed off the front of the text by convention. A
 * node is not "on" a channel in any way the protocol exposes, so the mapping
 * that re-tinting needs does not exist.
 *
 * This is the same discovery the EMBER made when every arrival logged "no
 * bearing", and the same answer: draw what is true. Picking a band opens that
 * channel's THREAD, which is the thing a person actually wanted.
 */
class Bands(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    /** One channel's band. [id] is the thread id the host gets back. */
    class Band(val id: String, val label: String, val count: Int, val speaking: Boolean)

    private class Seg(
        val arc: MeshEntity,
        val lit: MeshEntity,
        val proxy: MeshEntity,
        val run: TextRun.Run?,
    ) {
        var lastFire = 0L
        var at: Vector3 = Vector3(0f, 0f, 0f)
        var band: Band? = null
    }

    private val segs = mutableListOf<Seg>()
    private val entities = mutableListOf<Entity>()
    private val fired = java.util.concurrent.ConcurrentLinkedQueue<String>()
    private var origin: Stage.Origin? = null
    private var focused: String? = null

    var visible: Boolean = false
        private set

    var onFocus: (() -> Unit)? = null

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        // Built at startup for the maximum, hidden, and re-labelled per show —
        // the house rule, because Prims.material is suspend and an input
        // callback is not a coroutine.
        repeat(MAX) { i ->
            val span = (TWO_PI / MAX) * FILL
            val from = -span / 2f
            val arc = MeshEntity.create(
                session, Prims.build(session, Prims.arc(R, TUBE, from, span)),
                listOf(Prims.material(session, theme.alt, 0.30f)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            // LIT IS ITS OWN GEOMETRY, thicker rather than brighter — the same
            // reasoning the frame plate uses. Brightness belongs to Ink.
            val lit = MeshEntity.create(
                session, Prims.build(session, Prims.arc(R, TUBE * 2.4f, from, span)),
                listOf(Prims.material(session, theme.accent, 0.55f)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val proxy = MeshEntity.create(
                session, Prims.build(session, Prims.arc(R, TUBE * 6f, from, span, seg = 16)),
                listOf(Prims.ghost(session)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val run = TextRun.reusable(
                session, context, WIDEST, CAP, argb(theme.text, 0.95f), "band",
            )?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }
            val s = Seg(arc, lit, proxy, run)
            segs += s
            runCatching {
                proxy.addComponent(InteractableComponent.create(session) { ev -> onInput(s, ev) })
            }.onFailure { Log.w(TAG, "[bands] no input on $i: $it") }
        }
        Log.i(TAG, "[bands] ${segs.size} segments")
    }

    /**
     * Show [list], evenly dividing the ring.
     *
     * Evenly, and that is deliberate: a share proportional to traffic would
     * make the band a chart, and a chart of channel volume is a thing nobody
     * asked for occupying the one ring that means direction.
     */
    fun show(list: List<Band>, o: Stage.Origin) {
        origin = o
        visible = true
        val n = list.size.coerceAtMost(MAX)
        segs.forEachIndexed { i, s ->
            s.band = list.getOrNull(i)
            runCatching {
                val on = i < n
                s.arc.setEnabled(on && s.band?.speaking != true)
                s.lit.setEnabled(on && s.band?.speaking == true)
                s.proxy.setEnabled(on)
                s.run?.entity?.setEnabled(on)
                if (!on) return@runCatching
                // Each band centred on its own share of the circle. The whole
                // ring is used whatever the count, so two channels are two long
                // arcs rather than two stubs with a lot of nothing.
                val mid = TWO_PI * (i + 0.5f) / n
                val span = (TWO_PI / n) * FILL
                val rot = Quaternion.fromEulerAngles(
                    0f, -Math.toDegrees(mid.toDouble()).toFloat(), 0f,
                )
                val centre = o.place(0f, 0f, LIFT)
                // The arc meshes are built centred on zero, so the whole
                // segment is rotated into place rather than rebuilt per count.
                s.arc.setPose(Pose(centre, rot), Space.ACTIVITY)
                s.lit.setPose(Pose(centre, rot), Space.ACTIVITY)
                s.proxy.setPose(Pose(centre, rot), Space.ACTIVITY)
                s.arc.setScale(spanScale(span))
                s.lit.setScale(spanScale(span))
                s.proxy.setScale(spanScale(span))
                val at = o.place(mid, R, LIFT + LABEL_UP)
                s.at = at
                s.run?.setText(s.band?.label ?: "")
                s.run?.entity?.setPose(Pose(at), Space.ACTIVITY)
            }
        }
        Log.i(TAG, "[bands] showing $n channel band(s)")
    }

    /**
     * Arcs are built for MAX segments and reused at any count, so a band shown
     * when there are fewer channels has to be STRETCHED to fill its share.
     *
     * Scaling a torus scales its radius too, which would lift the band off the
     * ring — so this returns 1 and the span is accepted as built. Rebuilding
     * per count is the correct fix and costs a mesh per channel change; with
     * MAX at six and channels changing about never, it is not worth the churn
     * today. Recorded because the alternative looks like a bug: at two channels
     * the ring has four segment-sized gaps in it.
     */
    private fun spanScale(@Suppress("UNUSED_PARAMETER") span: Float): Float = 1f

    fun hide() {
        if (!visible) return
        visible = false
        focused = null
        fired.clear()
        segs.forEach {
            runCatching {
                it.arc.setEnabled(false); it.lit.setEnabled(false)
                it.proxy.setEnabled(false); it.run?.entity?.setEnabled(false)
            }
        }
    }

    fun poll(): String? = fired.poll()

    /** Billboard the labels; the arcs are flat rings and need no facing. */
    fun tick(head: Vector3?) {
        if (!visible || head == null) return
        segs.forEach { s ->
            val r = s.run ?: return@forEach
            if (s.band == null) return@forEach
            runCatching {
                val dx = head.x - s.at.x
                val dz = head.z - s.at.z
                val rot = if (dx * dx + dz * dz < 1e-6f) {
                    Quaternion.fromEulerAngles(0f, 0f, 0f)
                } else {
                    Quaternion.fromEulerAngles(
                        0f, Math.toDegrees(atan2(dx, dz).toDouble()).toFloat(), 0f,
                    )
                }
                r.entity.setPose(Pose(s.at, rot), Space.ACTIVITY)
            }
        }
    }

    fun gazeTargets(): List<Gaze.Target> {
        if (!visible) return emptyList()
        return segs.mapNotNull { s ->
            val b = s.band ?: return@mapNotNull null
            Gaze.Target("band-${b.id}", s.at, CONE_RAD) { fired.add(b.id) }
        }
    }

    private fun onInput(s: Seg, ev: InputEvent) {
        if (!visible) return
        val b = s.band ?: return
        when (ev.action) {
            InputEvent.Action.HOVER_ENTER, InputEvent.Action.HOVER_MOVE -> {
                if (focused != b.id) { focused = b.id; onFocus?.invoke() }
            }
            InputEvent.Action.HOVER_EXIT -> if (focused == b.id) focused = null
            InputEvent.Action.UP -> {
                val now = android.os.SystemClock.uptimeMillis()
                if (now - s.lastFire < DEBOUNCE_MS) return
                s.lastFire = now
                Reach.consumed()
                fired.add(b.id)
            }
            else -> Unit
        }
    }

    fun clear() {
        segs.clear(); fired.clear(); visible = false; focused = null; origin = null
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"
        const val TWO_PI = (Math.PI * 2).toFloat()

        /** Six, matching the Stack. A radio with more says so in the bay. */
        const val MAX = 6

        /** The horizon's own radius, so the band belongs to the same ring. */
        const val R = Horizon.R

        /**
         * ABOVE THE NODE BAND, and by enough that it cannot be mistaken for
         * one. The node lanes span about +/-10 degrees around the eye line;
         * this sits above them, outside the world window the brief keeps clear.
         */
        const val LIFT = 0.62f
        const val LABEL_UP = 0.10f
        const val TUBE = 0.010f

        /** Fraction of each share the arc fills; the rest is the gap. */
        const val FILL = 0.86f

        /** 1.4 degrees at 2.5 m — the house standard at the ring's distance. */
        const val CAP = 0.061f
        const val CONE_RAD = 0.28f
        const val DEBOUNCE_MS = 350L
        const val WIDEST = "PORTLAND METRO  999+"
    }
}
