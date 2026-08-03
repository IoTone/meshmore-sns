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
 * THE ROSTER — every node reachable without turning around.
 *
 * §8.2, listed as non-negotiable: "No information by position alone. A node
 * behind you must be reachable without turning around. Every HORIZON element
 * has an equivalent entry in a FOCUS list view. This is both an accessibility
 * requirement and a seated-use requirement."
 *
 * Until now bearing was the ONLY access path to a node. That is the paradigm
 * working as designed for someone standing in a clear room who can turn 360
 * degrees, and it is a wall for everyone else — and the magnify work made it
 * worse, not better, by adding more ways to navigate spatially.
 *
 * YES, THIS IS A LIST, and §6.3 bans lists. The ban is about lists as the
 * PRIMARY access path — the phone habit of turning a spatial problem into rows
 * — and §8.2 is explicit that the equivalent list has to exist anyway. So it is
 * built as the alternate route it is: summoned, never standing; ordered by
 * range, which is the one ordering that does not pretend to be a ranking; and
 * every row leads to the same FOCUS a pinch on the mote would have opened, so
 * the two paths cannot tell you different things.
 *
 * IT DOES NOT SCROLL. Paging, not scrolling — a fixed set of rows that change
 * what they say, which is the same trick the label pool uses and for the same
 * reason: nothing is created, nothing is destroyed, and there is no momentum to
 * fight in mid-air.
 */
class Roster(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    /** One selectable line. [label] is already formatted; [pick] opens it. */
    class Entry(val label: String, val pick: () -> Unit)

    private class Row(val run: TextRun.Run, val proxy: MeshEntity, val at: Vector3) {
        var lastFire = 0L
    }

    private val rows = mutableListOf<Row>()
    private var pager: Row? = null
    private val entities = mutableListOf<Entity>()
    private val fired = java.util.concurrent.ConcurrentLinkedQueue<Int>()

    private var all: List<Entry> = emptyList()
    private var page = 0
    private var anchor: Vector3? = null

    var open: Boolean = false
        private set

    /** Raised when a row takes focus, so the host can make the sound. */
    var onFocus: ((String) -> Unit)? = null

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        repeat(ROWS + 1) { i ->
            val run = TextRun.reusable(session, context, WIDEST, CAP, argb(theme.text, 0.95f), "roster")
                ?: return@repeat
            run.entity.parent = root
            run.entity.setEnabled(false)
            entities += run.entity
            // A GHOST BOX, not a sphere: a row is wide and short, and a sphere
            // big enough to catch its ends would reach into its neighbours.
            val proxy = MeshEntity.create(
                session, Prims.build(session, Prims.bar(HIT_W, HIT_H, 0.02f)),
                listOf(Prims.ghost(session)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val row = Row(run, proxy, Vector3(0f, 0f, 0f))
            val index = i
            runCatching {
                proxy.addComponent(
                    InteractableComponent.create(session) { ev -> onInput(index, row, ev) },
                )
            }.onFailure { Log.w(TAG, "[roster] no input on row $i: $it") }
            if (i < ROWS) rows += row else pager = row
        }
        Log.i(TAG, "[roster] ${rows.size} rows + pager")
    }

    /** Open in front of [head], listing [entries] by whatever order they arrive. */
    fun showAt(head: Vector3, yawRad: Float, entries: List<Entry>) {
        all = entries
        page = 0
        open = true
        anchor = Vector3(
            head.x + kotlin.math.sin(yawRad) * DIST,
            head.y,
            head.z - kotlin.math.cos(yawRad) * DIST,
        )
        render()
        Log.i(TAG, "[roster] open, ${entries.size} entries")
    }

    fun hide() {
        if (!open) return
        open = false
        fired.clear()
        (rows + listOfNotNull(pager)).forEach {
            runCatching { it.run.entity.setEnabled(false); it.proxy.setEnabled(false) }
        }
        Log.i(TAG, "[roster] closed")
    }

    /** Drained on the frame loop. */
    fun poll(): Int? = fired.poll()

    /**
     * Act on a drained index. Separated from [poll] so the host can decide
     * whether a pick should also close the surface.
     */
    fun activate(index: Int): Boolean {
        if (index == PAGER) {
            val pages = pages()
            page = (page + 1) % pages.coerceAtLeast(1)
            render()
            return false
        }
        val e = all.getOrNull(page * ROWS + index) ?: return false
        runCatching { e.pick() }
        return true
    }

    private fun pages(): Int =
        if (all.isEmpty()) 1 else (all.size + ROWS - 1) / ROWS

    private fun render() {
        val a = anchor ?: return
        val first = page * ROWS
        rows.forEachIndexed { i, r ->
            val e = all.getOrNull(first + i)
            val y = a.y + (ROWS / 2f - i) * LINE
            val at = Vector3(a.x, y, a.z)
            place(r, at, e != null)
            if (e != null) r.run.setText(e.label)
        }
        pager?.let { p ->
            val y = a.y + (ROWS / 2f - ROWS) * LINE - LINE * 0.4f
            place(p, Vector3(a.x, y, a.z), true)
            // Says where you are as well as what it does. "MORE" alone in a
            // list of 300 is a button with no scale attached to it.
            p.run.setText(
                "%d-%d OF %d   MORE".format(
                    (first + 1).coerceAtMost(all.size),
                    (first + ROWS).coerceAtMost(all.size), all.size,
                ),
            )
        }
    }

    private fun place(r: Row, at: Vector3, on: Boolean) {
        runCatching {
            r.run.entity.setEnabled(on)
            r.proxy.setEnabled(on)
            if (!on) return
            r.run.entity.setPose(Pose(at, facing(at)), Space.ACTIVITY)
            r.proxy.setPose(Pose(at), Space.ACTIVITY)
        }
        rowAt[r] = at
    }

    private val rowAt = HashMap<Row, Vector3>()
    private var headAt: Vector3? = null

    /** Keep it readable as the user moves. Yaw only: it stands at eye level. */
    fun tick(head: Vector3?) {
        if (!open || head == null) return
        headAt = head
        (rows + listOfNotNull(pager)).forEach { r ->
            val at = rowAt[r] ?: return@forEach
            runCatching { r.run.entity.setPose(Pose(at, facing(at)), Space.ACTIVITY) }
        }
    }

    private fun facing(at: Vector3): Quaternion {
        val h = headAt ?: return Quaternion.fromEulerAngles(0f, 0f, 0f)
        val dx = h.x - at.x
        val dz = h.z - at.z
        if (dx * dx + dz * dz < 1e-6f) return Quaternion.fromEulerAngles(0f, 0f, 0f)
        return Quaternion.fromEulerAngles(
            0f, Math.toDegrees(atan2(dx, dz).toDouble()).toFloat(), 0f,
        )
    }

    /** The rows as gaze targets, so the dwell path reaches this too. */
    fun gazeTargets(): List<Gaze.Target> {
        if (!open) return emptyList()
        val out = mutableListOf<Gaze.Target>()
        rows.forEachIndexed { i, r ->
            val at = rowAt[r] ?: return@forEachIndexed
            if (r.run.entity.isEnabled(false)) return@forEachIndexed
            out += Gaze.Target("roster-$i", at, CONE) { fired.add(i) }
        }
        pager?.let { p -> rowAt[p]?.let { out += Gaze.Target("roster-more", it, CONE) { fired.add(PAGER) } } }
        return out
    }

    private fun onInput(index: Int, r: Row, ev: InputEvent) {
        if (!open) return
        when (ev.action) {
            InputEvent.Action.HOVER_ENTER -> onFocus?.invoke("roster-$index")
            InputEvent.Action.UP -> {
                val now = android.os.SystemClock.uptimeMillis()
                if (now - r.lastFire < DEBOUNCE_MS) return
                r.lastFire = now
                Reach.consumed()
                fired.add(index)
            }
            else -> Unit
        }
    }

    fun clear() {
        rows.clear(); pager = null; rowAt.clear(); fired.clear()
        open = false; all = emptyList(); page = 0; anchor = null
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"
        /** The pager's index in the fired queue. Never a real row. */
        const val PAGER = -1
        /**
         * Six rows and a pager. Seven lines at [LINE] is about 31 degrees of a
         * 34 degree vertical field — which is acceptable for a surface you
         * SUMMONED and are looking at on purpose, and would not be for anything
         * that stood there.
         */
        const val ROWS = 6
        const val DIST = 1.4f
        /**
         * Row pitch. 4.6 degrees at [DIST] — under the ~5 the ring's targets
         * use, which is safe here only because a row is a wide box rather than
         * a small sphere, so the pointer has the whole width to land in.
         */
        const val LINE = 0.113f
        /** 1.32° at [DIST]. Derived from §4.1's floor, not chosen by eye. */
        const val CAP = 0.032f
        const val HIT_W = 0.62f
        const val HIT_H = 0.10f
        const val CONE = 0.045f
        const val DEBOUNCE_MS = 350L
        const val WIDEST = "MMMMMMMMMMMMMM 999KM NNW"
    }
}
