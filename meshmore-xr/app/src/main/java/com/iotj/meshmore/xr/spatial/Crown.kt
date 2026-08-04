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
import com.iotj.meshmore.xr.Dictation
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
    enum class Act {
        REPLY, ALOUD, VOICE, THREAD, DISMISS,
        SEND_1, SEND_2, SEND_3, SPEAK, BACK,
        CONFIRM, CANCEL,
    }

    /**
     * WHERE IN THE CROWN WE ARE.
     *
     * CONFIRM is a separate level rather than a flag on COMPOSE because it is a
     * different question. COMPOSE asks "what do you want to say"; CONFIRM asks
     * "shall this go out on the radio", and the second one deserves a screen
     * where the only two answers are yes and no.
     */
    enum class Level { ACTIONS, COMPOSE, CONFIRM }

    private class Item(val run: TextRun.Run, val proxy: MeshEntity) {
        var lastFire = 0L
    }

    private val items = mutableListOf<Item>()
    private val entities = mutableListOf<Entity>()
    private val fired = java.util.concurrent.ConcurrentLinkedQueue<Int>()
    private val slotAt = HashMap<Int, Vector3>()
    private var note: TextRun.Run? = null
    private var noteUntil = 0L
    /**
     * THE DRAFT, SHOWN BEFORE IT IS SENT — and the word count with it.
     *
     * The count is the limit made visible. A ceiling discovered afterwards, by
     * having your sentence cut in half on somebody else's screen, is not a
     * limit; it is a trap. So it reads "12/20" while you talk and says FULL
     * when it stops listening.
     */
    private var draft0: TextRun.Run? = null
    private var count0: TextRun.Run? = null

    private var level = Level.ACTIONS

    /**
     * The words waiting to go out, and the live dictation state under them.
     *
     * NOTHING IS SENT FROM THE COMPOSE LEVEL. Picking a canned reply used to
     * transmit on the spot, which is precisely the accidental send this was
     * asked to prevent — a pinch that lands slightly wrong put words on a
     * shared band. Every route now ends up here first.
     */
    private var draft = ""
    private var dictating = false
    private var spoken = 0
    private var full = false

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

    /** Whether this conversation reads itself aloud, for the toggle's label. */
    var voiceOn: Boolean = false

    private fun labels(): List<Pair<Act, String>> = when (level) {
        Level.ACTIONS -> listOf(
            Act.REPLY to "REPLY",
            Act.ALOUD to "READ ALOUD",
            Act.VOICE to if (voiceOn) "VOICE ON" else "VOICE OFF",
            Act.THREAD to "THREAD",
            Act.DISMISS to "CLOSE",
        )
        Level.COMPOSE -> quick.mapIndexed { i, q ->
            listOf(Act.SEND_1, Act.SEND_2, Act.SEND_3)[i] to q
        } + listOf(
            Act.SPEAK to if (dictating) "LISTENING" else "SPEAK",
            Act.BACK to "BACK",
        )
        // TWO ANSWERS AND NOTHING ELSE. A confirm screen with a third option is
        // a confirm screen somebody will misfire on.
        Level.CONFIRM -> listOf(Act.CONFIRM to "SEND", Act.CANCEL to "CANCEL")
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
        draft0 = TextRun.reusable(
            session, context, NOTE_WIDEST, CAP * 1.15f, argb(theme.text, 0.98f), "crown-draft",
        )?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }
        count0 = TextRun.reusable(
            session, context, "99/99 WORDS  FULL", CAP * 0.8f,
            argb(theme.alt, 0.9f), "crown-count",
        )?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }
        Log.i(TAG, "[crown] ${items.size} slots")
    }

    fun show() {
        open = true
        level = Level.ACTIONS
        draft = ""
    }

    fun compose() { level = Level.COMPOSE }

    /** Put words in the mouth and go to the one screen that can send them. */
    fun propose(text: String) {
        draft = text
        level = if (text.isBlank()) Level.COMPOSE else Level.CONFIRM
    }

    fun backToActions() { level = Level.ACTIONS; draft = ""; dictating = false }

    fun backToCompose() { level = Level.COMPOSE; draft = "" }

    val at: Level get() = level

    val pending: String get() = draft

    /** Live dictation state, for the word counter. */
    fun setDictation(text: String, words: Int, listening: Boolean, atLimit: Boolean) {
        draft = text
        spoken = words
        dictating = listening
        full = atLimit
    }

    fun hide() {
        if (!open) return
        open = false
        level = Level.ACTIONS
        draft = ""
        dictating = false
        fired.clear()
        items.forEach {
            runCatching { it.run.entity.setEnabled(false); it.proxy.setEnabled(false) }
        }
        runCatching {
            note?.entity?.setEnabled(false)
            draft0?.entity?.setEnabled(false)
            count0?.entity?.setEnabled(false)
        }
    }

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
        // The words themselves, under the actions, wherever they came from —
        // spoken, canned, or one day generated. One place to read what is about
        // to leave the radio.
        runCatching {
            val showing = level != Level.ACTIONS && (draft.isNotEmpty() || dictating)
            draft0?.entity?.setEnabled(showing)
            count0?.entity?.setEnabled(showing && (dictating || spoken > 0))
            if (showing) {
                val dp = Vector3(at.x, at.y + RISE - BOW - DRAFT_DROP, at.z)
                draft0?.setText(
                    if (draft.isBlank() && dictating) "LISTENING\u2026"
                    else TypeTier.clip(draft, DRAFT_COLS),
                )
                draft0?.entity?.setPose(Pose(dp, facing(dp, head)), Space.ACTIVITY)
                val cp = Vector3(at.x, dp.y - CAP * 1.9f, at.z)
                count0?.setText(
                    "$spoken/${Dictation.MAX_WORDS} WORDS" + if (full) "  FULL" else "",
                )
                count0?.entity?.setPose(Pose(cp, facing(cp, head)), Space.ACTIVITY)
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
        items.clear(); slotAt.clear(); fired.clear(); note = null; draft0 = null
        open = false; level = Level.ACTIONS; noteUntil = 0L
        draft = ""; dictating = false; spoken = 0; full = false
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"
        /** Five actions, or three quick replies plus SPEAK and a way back. */
        const val SLOTS = 5
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
        const val DRAFT_COLS = 20
        const val DRAFT_DROP = 0.035f
    }
}
