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
 * WHAT PEOPLE HAVE SAID — the inbox.
 *
 * Until now the app could receive a direct message and had nowhere to put it.
 * This is the surface that makes the radio a companion rather than an
 * instrument: the mesh is full of people, and a tool that shows you their
 * positions but not their words has the priorities backwards.
 *
 * SENDER AND WORDS. NOT HOPS, NOT SNR, NOT PATH LENGTH. All of that is real
 * and none of it belongs here — it is on the diagnostics tape and in FOCUS for
 * anyone who wants it. A message surface that leads with "via 3 hop(s), SNR
 * -7 dB" is a site-operations tool wearing a chat app's hat, and the whole
 * point of this one is that it should feel like neither.
 *
 * TWO LINES PER MESSAGE, because one is a lie at this width. A callsign and a
 * relative time on top, the words underneath: at the §4.1 floor a row is about
 * twenty characters, and squeezing "who" and "what" onto one of them means
 * truncating the part people actually came for.
 *
 * It reuses the roster's shape deliberately — fixed rows, paged not scrolled,
 * pinch or dwell — so the second list in the app behaves exactly like the
 * first. Two list-like surfaces that page differently is how an app starts
 * feeling improvised.
 */
class Inbox(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    /**
     * One CONVERSATION, already formatted. [id] is what the host opens.
     *
     * The inbox lists threads rather than messages now. A flat feed of
     * everything the radio heard is a packet monitor; people think "what did
     * Astor say" and "what is happening on the channel", which are two
     * questions a single stream answers badly.
     */
    class Entry(val id: String, val who: String, val words: String, val mine: Boolean)

    private class Row(
        val head: TextRun.Run,
        val body: TextRun.Run,
        val proxy: MeshEntity,
    ) {
        var lastFire = 0L
    }

    private val rows = mutableListOf<Row>()
    private var pager: TextRun.Run? = null
    private var pagerProxy: MeshEntity? = null
    private val entities = mutableListOf<Entity>()
    private val fired = java.util.concurrent.ConcurrentLinkedQueue<Int>()
    private val rowAt = HashMap<Int, Vector3>()

    private var all: List<Entry> = emptyList()
    private var page = 0
    private var anchor: Vector3? = null
    private var headAt: Vector3? = null

    var open: Boolean = false
        private set

    var onFocus: ((String) -> Unit)? = null

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        repeat(ROWS) {
            val head = run(root, WIDEST_HEAD, HEAD_CAP, theme.alt) ?: return@repeat
            val body = run(root, WIDEST_BODY, BODY_CAP, theme.text) ?: return@repeat
            val proxy = MeshEntity.create(
                session, Prims.build(session, Prims.bar(HIT_W, HIT_H, 0.02f)),
                listOf(Prims.ghost(session)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val row = Row(head, body, proxy)
            val index = rows.size
            runCatching {
                proxy.addComponent(
                    InteractableComponent.create(session) { ev -> onInput(index, row, ev) },
                )
            }.onFailure { Log.w(TAG, "[inbox] no input on row $index: $it") }
            rows += row
        }
        pager = run(root, "NEWER   1-4 OF 60   OLDER", HEAD_CAP, theme.accent)
        pagerProxy = MeshEntity.create(
            session, Prims.build(session, Prims.bar(HIT_W, HIT_H * 0.7f, 0.02f)),
            listOf(Prims.ghost(session)),
        ).also { p ->
            p.parent = root; p.setEnabled(false); entities += p
            runCatching {
                p.addComponent(
                    InteractableComponent.create(session) { ev ->
                        if (open && ev.action == InputEvent.Action.UP) fired.add(PAGER)
                    },
                )
            }
        }
        Log.i(TAG, "[inbox] ${rows.size} rows")
    }

    private suspend fun run(root: Entity, widest: String, cap: Float, rgb: Int): TextRun.Run? =
        TextRun.reusable(session, context, widest, cap, argb(rgb, 0.95f), "inbox")
            ?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }

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
        Log.i(TAG, "[inbox] open, ${entries.size} message(s)")
    }

    fun hide() {
        if (!open) return
        open = false
        fired.clear()
        rows.forEach {
            runCatching {
                it.head.entity.setEnabled(false)
                it.body.entity.setEnabled(false)
                it.proxy.setEnabled(false)
            }
        }
        runCatching { pager?.entity?.setEnabled(false); pagerProxy?.setEnabled(false) }
        Log.i(TAG, "[inbox] closed")
    }

    fun poll(): Int? = fired.poll()

    /**
     * Act on a pick. Returns the conversation id when one was chosen, null
     * when the pick was the pager.
     */
    fun activate(index: Int): String? {
        if (index == PAGER) {
            page = (page + 1) % pages().coerceAtLeast(1)
            render()
            return null
        }
        return all.getOrNull(page * ROWS + index)?.id
    }

    private fun pages(): Int = if (all.isEmpty()) 1 else (all.size + ROWS - 1) / ROWS

    private fun render() {
        val a = anchor ?: return
        val first = page * ROWS
        rows.forEachIndexed { i, r ->
            val e = all.getOrNull(first + i)
            val y = a.y + (ROWS / 2f - i) * LINE
            rowAt[i] = Vector3(a.x, y, a.z)
            runCatching {
                r.head.entity.setEnabled(e != null)
                r.body.entity.setEnabled(e != null)
                r.proxy.setEnabled(e != null)
                if (e == null) return@runCatching
                r.head.setText(e.who)
                r.body.setText(e.words)
                r.head.entity.setPose(
                    Pose(Vector3(a.x, y, a.z), facing(a)), Space.ACTIVITY,
                )
                r.body.entity.setPose(
                    Pose(Vector3(a.x, y - HEAD_CAP * 1.9f, a.z), facing(a)), Space.ACTIVITY,
                )
                r.proxy.setPose(Pose(Vector3(a.x, y - HEAD_CAP, a.z)), Space.ACTIVITY)
            }
        }
        val py = a.y + (ROWS / 2f - ROWS) * LINE
        rowAt[PAGER] = Vector3(a.x, py, a.z)
        runCatching {
            val on = all.isNotEmpty()
            pager?.entity?.setEnabled(on)
            pagerProxy?.setEnabled(on)
            if (on) {
                pager?.setText(
                    if (all.size <= ROWS) "%d MESSAGE%s".format(
                        all.size, if (all.size == 1) "" else "S",
                    ) else "%d-%d OF %d   MORE".format(
                        first + 1, (first + ROWS).coerceAtMost(all.size), all.size,
                    ),
                )
                pager?.entity?.setPose(Pose(Vector3(a.x, py, a.z), facing(a)), Space.ACTIVITY)
                pagerProxy?.setPose(Pose(Vector3(a.x, py, a.z)), Space.ACTIVITY)
            }
        }
    }

    fun tick(head: Vector3?) {
        if (!open || head == null) return
        headAt = head
        render()
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

    fun gazeTargets(): List<Gaze.Target> {
        if (!open) return emptyList()
        val out = mutableListOf<Gaze.Target>()
        rows.indices.forEach { i ->
            if (all.getOrNull(page * ROWS + i) == null) return@forEach
            rowAt[i]?.let { out += Gaze.Target("inbox-$i", it, CONE) { fired.add(i) } }
        }
        rowAt[PAGER]?.let { out += Gaze.Target("inbox-more", it, CONE) { fired.add(PAGER) } }
        return out
    }

    private fun onInput(index: Int, r: Row, ev: InputEvent) {
        if (!open) return
        when (ev.action) {
            InputEvent.Action.HOVER_ENTER -> onFocus?.invoke("inbox-$index")
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
        rows.clear(); pager = null; pagerProxy = null; rowAt.clear(); fired.clear()
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
        const val PAGER = -1
        /** Four messages, two lines each. Nine lines fills the vertical field. */
        const val ROWS = 4
        const val DIST = 1.4f
        /** Pitch between MESSAGES, not between lines. */
        const val LINE = 0.175f
        /** 1.32° and 1.45° at DIST — derived from §4.1, not chosen by eye. */
        const val HEAD_CAP = 0.032f
        const val BODY_CAP = 0.035f
        const val HIT_W = 0.66f
        const val HIT_H = 0.15f
        const val CONE = 0.05f
        const val DEBOUNCE_MS = 350L
        const val WIDEST_HEAD = "MMMMMMMMMMMMMM  99 MIN AGO"
        const val WIDEST_BODY = "MMMMMMMMMMMMMMMMMMMMMMMM"
    }
}
