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
 * ONE CONVERSATION, WITH TIME AS DEPTH.
 *
 * A chat app stacks messages vertically and scrolls. That works on a phone
 * because a phone is a window you slide a document past, and it is the wrong
 * instrument here — §6.3 bans scrolling lists, and a vertical stack in a
 * 34-degree field holds four lines before it runs out of sky.
 *
 * So the thread recedes. The newest message is nearest and at eye level; each
 * older one steps BACK and slightly UP, like a corridor going away from you.
 * Looking further into the conversation is looking further away, which is a
 * thing a headset can do and a phone cannot, and it means the whole thread is
 * present at once rather than being a window onto a document.
 *
 * CONSTANT ANGULAR SIZE. Every message is drawn at the same 1.30 degrees
 * whatever its depth — cap height scales with distance, the same discipline
 * MeshNodes uses for ring labels. Without it the far end of the thread falls
 * under §4.1's floor and the effect becomes "old messages are unreadable",
 * which is a bug wearing perspective as a costume. Depth is carried by
 * position, occlusion and the step upward, not by things getting smaller than
 * the eye can resolve.
 *
 * NOT INFINITE. Six deep, because the seventh is 4 m away and there is nothing
 * useful past the point where a person stops being able to tell two lines
 * apart. Older than that is what paging is for.
 */
class Thread(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    /** One message in the corridor. */
    class Line(val who: String, val words: String, val mine: Boolean)

    private class Slot(val head: TextRun.Run, val body: TextRun.Run) {
        var at: Vector3 = Vector3(0f, 0f, 0f)
    }

    private val slots = mutableListOf<Slot>()
    private var header: TextRun.Run? = null
    /**
     * THE WAY FURTHER BACK.
     *
     * older() was written with the corridor and then never called by anything,
     * so a conversation showed its newest six and there was no way to reach the
     * seventh -- a paging control with no button, which is the same as no
     * paging at all. It sits at the FAR END of the corridor because that is
     * where the past already is: looking deeper into it is the gesture, and
     * putting an "older" control anywhere else would be asking people to learn
     * a second idea when the geometry has already taught them the first.
     */
    private var deeper: TextRun.Run? = null
    private var deeperProxy: MeshEntity? = null
    private var deeperAt: Vector3? = null
    private val fired = java.util.concurrent.ConcurrentLinkedQueue<Int>()
    private var lastFire = 0L
    private val entities = mutableListOf<Entity>()

    private var origin: Vector3? = null
    private var yaw = 0f
    private var headAt: Vector3? = null
    private var lines: List<Line> = emptyList()
    private var page = 0

    var open: Boolean = false
        private set

    var id: String? = null
        private set

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        header = run(root, WIDEST_HEAD, HEAD_CAP, theme.accent)
        repeat(DEPTH) { i ->
            // Sized for the depth it will sit at, so the far ones are BIGGER in
            // metres and identical in degrees. A pooled run cannot do this —
            // the pool rasterises once and scales — so each slot is its own
            // panel, which is affordable at six.
            val d = distAt(i)
            val head = run(root, WIDEST_HEAD, d * CAP_FRAC * 0.85f, theme.alt) ?: return@repeat
            val body = run(root, WIDEST_BODY, d * CAP_FRAC, theme.text) ?: return@repeat
            slots += Slot(head, body)
        }
        val far = distAt(DEPTH)
        deeper = run(root, WIDEST_DEEP, far * CAP_FRAC * 0.85f, theme.accent)
        deeperProxy = MeshEntity.create(
            session, Prims.build(session, Prims.bar(far * 0.5f, far * 0.12f, 0.02f)),
            listOf(Prims.ghost(session)),
        ).also { p ->
            p.parent = root; p.setEnabled(false); entities += p
            runCatching {
                p.addComponent(
                    InteractableComponent.create(session) { ev ->
                        if (open && ev.action == InputEvent.Action.UP) {
                            val now = android.os.SystemClock.uptimeMillis()
                            if (now - lastFire >= DEBOUNCE_MS) {
                                lastFire = now
                                Reach.consumed()
                                fired.add(1)
                            }
                        }
                    },
                )
            }.onFailure { Log.w(TAG, "[thread] no input on older: $it") }
        }
        Log.i(TAG, "[thread] ${slots.size} deep, paging wired")
    }

    private suspend fun run(root: Entity, widest: String, cap: Float, rgb: Int): TextRun.Run? =
        TextRun.reusable(session, context, widest, cap, argb(rgb, 0.95f), "thread")
            ?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }

    /** How far back the [i]th message sits. */
    private fun distAt(i: Int): Float = NEAR + i * STEP

    fun showAt(head: Vector3, yawRad: Float, threadId: String, title: String, msgs: List<Line>) {
        origin = head
        yaw = yawRad
        id = threadId
        lines = msgs
        page = 0
        open = true
        header?.setText(title)
        place()
        Log.i(TAG, "[thread] open '$title', ${msgs.size} message(s)")
    }

    fun hide() {
        if (!open) return
        open = false
        id = null
        slots.forEach {
            runCatching { it.head.entity.setEnabled(false); it.body.entity.setEnabled(false) }
        }
        runCatching {
            header?.entity?.setEnabled(false)
            deeper?.entity?.setEnabled(false)
            deeperProxy?.setEnabled(false)
        }
        fired.clear()
        Log.i(TAG, "[thread] closed")
    }

    /** Step further back in time. Wraps, so there is always a way out. */
    fun older() {
        if (lines.size <= DEPTH) return
        page = (page + 1) % pages()
        place()
        Log.i(TAG, "[thread] page ${page + 1} of ${pages()}")
    }

    private fun pages(): Int =
        if (lines.isEmpty()) 1 else (lines.size + DEPTH - 1) / DEPTH

    /** Drain picks. The host calls older() so one code path owns the paging. */
    fun poll(): Int? = fired.poll()

    fun gazeTargets(): List<Gaze.Target> {
        if (!open || lines.size <= DEPTH) return emptyList()
        val at = deeperAt ?: return emptyList()
        return listOf(Gaze.Target("thread-older", at, CONE) { fired.add(1) })
    }

    fun tick(head: Vector3?) {
        if (!open) return
        headAt = head
        place()
    }

    private fun place() {
        val o = origin ?: return
        val fx = kotlin.math.sin(yaw)
        val fz = -kotlin.math.cos(yaw)
        val first = page * DEPTH
        runCatching {
            header?.entity?.setEnabled(true)
            val hAt = Vector3(o.x + fx * NEAR, o.y + HEADER_UP, o.z + fz * NEAR)
            header?.entity?.setPose(Pose(hAt, facing(hAt)), Space.ACTIVITY)
        }
        // The marker for what is behind the last visible message. Hidden when
        // the whole conversation already fits: an "older" control that pages to
        // the same six messages is a lie about there being more.
        val more = lines.size > DEPTH
        val fd = distAt(DEPTH)
        val dAt = Vector3(o.x + fx * fd, o.y - EYE_DROP + DEPTH * RISE, o.z + fz * fd)
        deeperAt = dAt
        runCatching {
            deeper?.entity?.setEnabled(more)
            deeperProxy?.setEnabled(more)
            if (more) {
                deeper?.setText(
                    "OLDER   %d-%d OF %d".format(
                        first + 1, (first + DEPTH).coerceAtMost(lines.size), lines.size,
                    ),
                )
                deeper?.entity?.setPose(Pose(dAt, facing(dAt)), Space.ACTIVITY)
                deeperProxy?.setPose(Pose(dAt), Space.ACTIVITY)
            }
        }
        slots.forEachIndexed { i, s ->
            val line = lines.getOrNull(first + i)
            val d = distAt(i)
            // Back, and up. The rise is what stops the corridor from being a
            // single occluded pile — each older message clears the shoulder of
            // the one in front of it.
            val at = Vector3(o.x + fx * d, o.y - EYE_DROP + i * RISE, o.z + fz * d)
            s.at = at
            runCatching {
                s.head.entity.setEnabled(line != null)
                s.body.entity.setEnabled(line != null)
                if (line == null) return@runCatching
                s.head.setText(line.who)
                s.body.setText(line.words)
                val r = facing(at)
                s.head.entity.setPose(Pose(at, r), Space.ACTIVITY)
                s.body.entity.setPose(
                    Pose(Vector3(at.x, at.y - d * CAP_FRAC * 1.9f, at.z), r), Space.ACTIVITY,
                )
            }
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

    fun clear() {
        slots.clear(); header = null
        deeper = null; deeperProxy = null; deeperAt = null; fired.clear(); lastFire = 0L
        open = false; id = null; lines = emptyList(); page = 0; origin = null
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"
        /** How many messages are present at once. */
        const val DEPTH = 6
        /** The newest sits here. */
        const val NEAR = 1.25f
        /** And each older one this much further back. */
        const val STEP = 0.45f
        /** Rising as it recedes, so each clears the one in front. */
        const val RISE = 0.10f
        const val EYE_DROP = 0.12f
        const val HEADER_UP = 0.26f
        /**
         * 1.30° — the same figure the ring labels use. Multiplied by the
         * distance, which is what keeps the far end of the thread readable
         * instead of merely small.
         */
        const val CAP_FRAC = 0.0227f
        const val HEAD_CAP = 0.030f
        const val CONE = 0.05f
        const val DEBOUNCE_MS = 350L
        const val WIDEST_DEEP = "OLDER   99-99 OF 999"
        const val WIDEST_HEAD = "MMMMMMMMMMMMMM  99 MIN AGO"
        const val WIDEST_BODY = "MMMMMMMMMMMMMMMMMMMMMMMM"
    }
}
