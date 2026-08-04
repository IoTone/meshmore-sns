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
 * THE CROWN — what you can DO about the message you are reading.
 *
 * Until this, the app could receive, store, sort, page and read aloud nothing
 * at all: every surface pointed one way. §S4 owes a per-message crown and this
 * is it, but the reason it comes now rather than later is simpler than the
 * brief — an app you cannot answer is a receiver, and the whole point of this
 * one is that it should feel like a companion.
 *
 * AN ARC OVER THE MESSAGE, not a menu beside it. The actions belong to the
 * message being read, so they are attached to it: curved over the top of the
 * raised card, following the same billboard, appearing and leaving with it.
 * Nothing about the message's position has to be remembered while choosing.
 *
 * TWO LEVELS IN ONE WIDGET. Choosing REPLY swaps the labels for quick replies
 * rather than opening a second surface. A second surface would need its own
 * place to live, its own way out, and its own answer to "where did the message
 * go" -- and the answer to all three is already here. The way back is the same
 * gesture that got in.
 *
 * WORDS, NOT ICONS, ON THIS ONE. The dock earns its marks: nine pips, always
 * present, at 3 degrees. Five actions that appear only while you are reading a
 * message are a different problem -- they are rare, they are consequential, and
 * REPLY and DELETE do not want to be told apart by silhouette at speed. §4.1's
 * floor is affordable here because the crown sits where the card sits.
 */
class Crown(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    /** What was chosen. The host decides what any of it means. */
    enum class Act { REPLY, ALOUD, THREAD, DISMISS, SEND_1, SEND_2, SEND_3, BACK }

    private class Item(val run: TextRun.Run, val proxy: MeshEntity) {
        var lastFire = 0L
    }

    private val items = mutableListOf<Item>()
    private val entities = mutableListOf<Entity>()
    private val fired = java.util.concurrent.ConcurrentLinkedQueue<Int>()
    private val slotAt = HashMap<Int, Vector3>()
    private var note: TextRun.Run? = null
    private var noteUntil = 0L

    /** Level 1 is the actions; level 2 is the quick replies. */
    private var replying = false

    var open: Boolean = false
        private set

    /**
     * The canned answers.
     *
     * NOT A KEYBOARD, and not a placeholder for one either. Dictation is the
     * right long answer on glasses and it is coming, but a mesh radio is a
     * low-bandwidth, high-latency link used mostly to say a handful of things,
     * and three of them cover most traffic. A surface that does the common case
     * in one pinch is not a lesser version of one that does everything in
     * twenty.
     */
    private val quick = listOf("ROGER", "ON MY WAY", "STAND BY")

    private fun labels(): List<Pair<Act, String>> =
        if (replying) {
            quick.mapIndexed { i, q ->
                listOf(Act.SEND_1, Act.SEND_2, Act.SEND_3)[i] to q
            } + (Act.BACK to "BACK")
        } else {
            listOf(
                Act.REPLY to "REPLY",
                Act.ALOUD to "READ ALOUD",
                Act.THREAD to "THREAD",
                Act.DISMISS to "CLOSE",
            )
        }

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        repeat(SLOTS) {
            val run = TextRun.reusable(
                session, context, WIDEST, CAP, argb(theme.accent, 0.95f), "crown",
            ) ?: return@repeat
            run.entity.parent = root
            run.entity.setEnabled(false)
            entities += run.entity
            val proxy = MeshEntity.create(
                session, Prims.build(session, Prims.bar(HIT_W, HIT_H, 0.02f)),
                listOf(Prims.ghost(session)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val item = Item(run, proxy)
            val index = items.size
            runCatching {
                proxy.addComponent(
                    InteractableComponent.create(session) { ev -> onInput(index, item, ev) },
                )
            }.onFailure { Log.w(TAG, "[crown] no input on $index: $it") }
            items += item
        }
        // The outcome line. A reply that vanishes with no word about whether it
        // left is worse than no reply button: on a mesh radio the wearer has no
        // other way to find out, and "did that send?" is not a question a
        // companion app should make people hold in their head.
        note = TextRun.reusable(
            session, context, NOTE_WIDEST, CAP, argb(theme.text, 0.95f), "crown-note",
        )?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }
        Log.i(TAG, "[crown] ${items.size} slots")
    }

    fun show() {
        open = true
        replying = false
    }

    fun hide() {
        if (!open) return
        open = false
        replying = false
        fired.clear()
        items.forEach {
            runCatching { it.run.entity.setEnabled(false); it.proxy.setEnabled(false) }
        }
        runCatching { note?.entity?.setEnabled(false) }
    }

    /** Step into the quick replies, or back out of them. */
    fun setReplying(on: Boolean) { replying = on }

    val inReply: Boolean get() = replying

    /** Say what happened, for a few seconds. */
    fun say(text: String, nowMs: Long) {
        note?.setText(text)
        noteUntil = nowMs + NOTE_MS
    }

    fun poll(): Act? = fired.poll()?.let { labels().getOrNull(it)?.first }

    /** [at] is the card's anchor; the crown arcs above it. */
    fun tick(at: Vector3?, head: Vector3?, nowMs: Long) {
        if (!open || at == null || head == null) {
            if (!open) return
            items.forEach {
                runCatching { it.run.entity.setEnabled(false); it.proxy.setEnabled(false) }
            }
            return
        }
        val ls = labels()
        // Across the top, on a shallow arc. Flat would collide with the card's
        // own header; a full ring would put half the actions behind the hand.
        val span = (ls.size - 1).coerceAtLeast(1)
        ls.forEachIndexed { i, (_, text) ->
            val f = i.toFloat() / span - 0.5f
            val p = Vector3(
                at.x + f * WIDTH,
                at.y + RISE - kotlin.math.abs(f) * BOW,
                at.z,
            )
            slotAt[i] = p
            val item = items.getOrNull(i) ?: return@forEachIndexed
            runCatching {
                item.run.entity.setEnabled(true)
                item.run.setText(text)
                item.run.entity.setPose(Pose(p, facing(p, head)), Space.ACTIVITY)
                item.proxy.setEnabled(true)
                item.proxy.setPose(Pose(p), Space.ACTIVITY)
            }
        }
        // Anything past the current level's count is off, not stale.
        for (i in ls.size until items.size) {
            runCatching {
                items[i].run.entity.setEnabled(false); items[i].proxy.setEnabled(false)
            }
        }
        runCatching {
            val on = nowMs < noteUntil
            note?.entity?.setEnabled(on)
            if (on) {
                val np = Vector3(at.x, at.y + RISE + BOW, at.z)
                note?.entity?.setPose(Pose(np, facing(np, head)), Space.ACTIVITY)
            }
        }
    }

    fun gazeTargets(): List<Gaze.Target> {
        if (!open) return emptyList()
        return labels().indices.mapNotNull { i ->
            slotAt[i]?.let { Gaze.Target("crown-$i", it, CONE) { fired.add(i) } }
        }
    }

    private fun onInput(index: Int, item: Item, ev: InputEvent) {
        if (!open) return
        if (ev.action != InputEvent.Action.UP) return
        val now = android.os.SystemClock.uptimeMillis()
        if (now - item.lastFire < DEBOUNCE_MS) return
        item.lastFire = now
        Reach.consumed()
        fired.add(index)
    }

    private fun facing(at: Vector3, head: Vector3): Quaternion {
        val dx = head.x - at.x
        val dz = head.z - at.z
        if (dx * dx + dz * dz < 1e-6f) return Quaternion.fromEulerAngles(0f, 0f, 0f)
        return Quaternion.fromEulerAngles(
            0f, Math.toDegrees(atan2(dx, dz).toDouble()).toFloat(), 0f,
        )
    }

    fun clear() {
        items.clear(); slotAt.clear(); fired.clear(); note = null
        open = false; replying = false; noteUntil = 0L
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"
        /** Four actions, or three quick replies plus a way back. */
        const val SLOTS = 4
        /** 1.9° where the card sits — the same reasoning as the card's own cap. */
        const val CAP = 0.011f
        const val WIDTH = 0.30f
        const val RISE = 0.10f
        /** How much the arc droops at its ends, so it reads as a crown. */
        const val BOW = 0.02f
        const val HIT_W = 0.09f
        const val HIT_H = 0.04f
        const val CONE = 0.045f
        const val DEBOUNCE_MS = 350L
        const val NOTE_MS = 3500L
        const val WIDEST = "MMMMMMMMMM"
        const val NOTE_WIDEST = "MMMMMMMMMMMMMMMMMMMM"
    }
}
