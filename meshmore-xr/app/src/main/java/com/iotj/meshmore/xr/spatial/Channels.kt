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
 * THE CHANNELS BAY — which bands exist, and which of them talk to you.
 *
 * The console spec (§10) asks for "a nested STACK, one plate per slot", and the
 * brief (§S5) asks for a TTS toggle per channel. This is both, in the CROWN's
 * form rather than the console's fan, because the console's fan carries ICONS
 * and a channel is identified by its NAME — there is no silhouette for
 * "Portland Metro" — and because the last thing said about the crown's plates
 * was that this is what a button should be here: a slab with an edge, sized to
 * its own label, at a distance you can point at.
 *
 * ## Why this bay exists at all, ahead of the other one
 *
 * "All channels should have a toggle on/off audible voice TTS" was asked for
 * directly, and it was half-built: [com.iotj.meshmore.xr.VoicePrefs] stores it
 * per thread and the CROWN can toggle the conversation you are reading. But the
 * crown only reaches a channel you have a MESSAGE from and are currently
 * looking at, which means the setting could not be found by somebody setting
 * the app up, and could not be turned off for a channel that had gone quiet —
 * the exact case where you want it off is the case where nothing arrives to
 * open a crown on.
 *
 * A bay that lists the slots fixes both, and it is the answer to "how do I turn
 * on the audio to always do TTS for this channel".
 *
 * ## Public keys are said out loud
 *
 * A slot carrying the well-known public PSK is marked PUBLIC. It is one word
 * and it is not decoration: the difference between a band anyone in range can
 * read and one only your group can is the difference that decides what a person
 * is willing to say on it, and a list of names alone hides it completely.
 */
class Channels(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    /** One row's state, handed in by the host each time the bay opens. */
    class Row(
        val threadId: String,
        val label: String,
        val speaking: Boolean,
    )

    private class Slot(
        val run: TextRun.Run,
        val plate: MeshEntity,
        val lit: MeshEntity,
        val proxy: MeshEntity,
    ) {
        var lastFire = 0L
    }

    private val slots = mutableListOf<Slot>()
    private val entities = mutableListOf<Entity>()
    private val fired = java.util.concurrent.ConcurrentLinkedQueue<String>()
    private var head0: TextRun.Run? = null
    private var note: TextRun.Run? = null

    private var rows: List<Row> = emptyList()
    private var focused: Int = -1

    var open: Boolean = false
        private set

    var onFocus: (() -> Unit)? = null

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        // BUILT AT STARTUP AND HIDDEN, all MAX of them, because Prims.material
        // is suspend and an input callback is not a coroutine — geometry made
        // in response to a pinch hitches the frame at the exact moment the
        // wearer is watching for a response.
        repeat(MAX) {
            val run = TextRun.reusable(
                session, context, WIDEST, CAP, argb(theme.text, 0.98f), "chan",
            ) ?: return@repeat
            run.entity.parent = root
            run.entity.setEnabled(false)
            entities += run.entity
            val plate = MeshEntity.create(
                session, Prims.build(session, Prims.bar(PLATE_W, PLATE_H, DEPTH)),
                listOf(Prims.material(session, theme.alt, 0.16f)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val lit = MeshEntity.create(
                session, Prims.build(session, Prims.bar(PLATE_W, PLATE_H, DEPTH)),
                listOf(Prims.material(session, theme.accent, 0.42f)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val proxy = MeshEntity.create(
                session, Prims.build(session, Prims.bar(PLATE_W, PLATE_H, HIT_D)),
                listOf(Prims.ghost(session)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val s = Slot(run, plate, lit, proxy)
            val index = slots.size
            runCatching {
                proxy.addComponent(
                    InteractableComponent.create(session) { ev -> onInput(index, s, ev) },
                )
            }.onFailure { Log.w(TAG, "[chan] no input on $index: $it") }
            slots += s
        }
        head0 = TextRun.reusable(
            session, context, HEAD_WIDEST, CAP, argb(theme.accent, 0.95f), "chan-head",
        )?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }
        note = TextRun.reusable(
            session, context, NOTE_WIDEST, CAP * 0.85f, argb(theme.alt, 0.9f), "chan-note",
        )?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }
        Log.i(TAG, "[chan] ${slots.size} slots")
    }

    /**
     * Open with [list].
     *
     * The host builds the rows because the host is what knows both halves — the
     * radio's slots and the wearer's voice preferences — and this surface is
     * deliberately ignorant of either. It draws rows and reports picks.
     */
    fun show(list: List<Row>) {
        rows = list.take(MAX)
        open = true
        focused = -1
        fired.clear()
        Log.i(TAG, "[chan] open with ${rows.size} of ${list.size} channels")
    }

    fun hide() {
        if (!open) return
        open = false
        focused = -1
        fired.clear()
        slots.forEach {
            runCatching {
                it.run.entity.setEnabled(false); it.plate.setEnabled(false)
                it.lit.setEnabled(false); it.proxy.setEnabled(false)
            }
        }
        runCatching {
            head0?.entity?.setEnabled(false)
            note?.entity?.setEnabled(false)
        }
        Log.i(TAG, "[chan] closed")
    }

    /** Which channel was picked, as a thread id. */
    fun poll(): String? = fired.poll()

    /** Re-label after a toggle, without rebuilding anything. */
    fun update(list: List<Row>) {
        rows = list.take(MAX)
    }

    fun tick(head: Vector3?, yawRad: Float) {
        if (!open) return
        if (head == null) {
            slots.forEach {
                runCatching {
                    it.run.entity.setEnabled(false); it.plate.setEnabled(false)
                    it.lit.setEnabled(false); it.proxy.setEnabled(false)
                }
            }
            return
        }
        // The house yaw convention: a head pose looks down its own -Z, so the
        // facing is the negative of the +Z axis yawOf reads. Same as Crown.
        val fx = kotlin.math.sin(yawRad)
        val fz = -kotlin.math.cos(yawRad)
        val cx = head.x + fx * DIST
        val cz = head.z + fz * DIST
        // The header sits above the column, so the first row is where the gaze
        // already is rather than one plate below a title.
        val top = head.y + TOP_DROP + (rows.size - 1) * PITCH / 2f

        runCatching {
            head0?.entity?.setEnabled(true)
            head0?.setText(
                if (rows.isEmpty()) "NO CHANNELS YET" else "CHANNELS — PICK TO SPEAK",
            )
            val hp = Vector3(cx, top + PITCH * 1.1f, cz)
            head0?.entity?.setPose(Pose(hp, facing(hp, head)), Space.ACTIVITY)
        }

        slots.forEachIndexed { i, s ->
            val row = rows.getOrNull(i)
            if (row == null) {
                runCatching {
                    s.run.entity.setEnabled(false); s.plate.setEnabled(false)
                    s.lit.setEnabled(false); s.proxy.setEnabled(false)
                }
                return@forEachIndexed
            }
            val p = Vector3(cx, top - i * PITCH, cz)
            val r = facing(p, head)
            runCatching {
                s.run.entity.setEnabled(true)
                s.run.setText(row.label)
                s.run.entity.setPose(Pose(p, r), Space.ACTIVITY)
                val back = Vector3(p.x - fx * PLATE_BACK, p.y, p.z - fz * PLATE_BACK)
                // LIT MEANS SPEAKING, not focused.
                //
                // The crown lights the plate under the pointer, because there
                // the light is the only thing saying where you are. Here the
                // plate is carrying a STATE that outlives the glance — whether
                // this channel reads itself aloud — and a light that means
                // "focused" on one surface and "on" on another is a light that
                // means nothing. Focus is the scale bump instead.
                s.plate.setEnabled(!row.speaking)
                s.plate.setPose(Pose(back, r), Space.ACTIVITY)
                s.lit.setEnabled(row.speaking)
                s.lit.setPose(Pose(back, r), Space.ACTIVITY)
                s.run.entity.setScale(if (i == focused) HOT else 1f)
                s.proxy.setEnabled(true)
                s.proxy.setPose(Pose(p, r), Space.ACTIVITY)
            }
        }

        runCatching {
            note?.entity?.setEnabled(true)
            note?.setText(
                if (rows.isEmpty()) "CONNECT A RADIO TO SEE ITS SLOTS"
                else "LIT = READS ALOUD    B TO CLOSE",
            )
            val np = Vector3(cx, top - rows.size.coerceAtLeast(1) * PITCH - NOTE_DROP, cz)
            note?.entity?.setPose(Pose(np, facing(np, head)), Space.ACTIVITY)
        }
    }

    fun gazeTargets(): List<Gaze.Target> {
        if (!open) return emptyList()
        return emptyList()
    }

    private fun facing(at: Vector3, head: Vector3): Quaternion {
        val dx = head.x - at.x
        val dz = head.z - at.z
        if (dx * dx + dz * dz < 1e-6f) return Quaternion.fromEulerAngles(0f, 0f, 0f)
        return Quaternion.fromEulerAngles(
            0f, Math.toDegrees(atan2(dx, dz).toDouble()).toFloat(), 0f,
        )
    }

    private fun onInput(index: Int, s: Slot, ev: InputEvent) {
        if (!open || index >= rows.size) return
        when (ev.action) {
            InputEvent.Action.HOVER_ENTER, InputEvent.Action.HOVER_MOVE -> {
                if (focused != index) { focused = index; onFocus?.invoke() }
            }
            InputEvent.Action.HOVER_EXIT -> if (focused == index) focused = -1
            InputEvent.Action.UP -> {
                val now = android.os.SystemClock.uptimeMillis()
                if (now - s.lastFire < DEBOUNCE_MS) return
                s.lastFire = now
                Reach.consumed()
                rows.getOrNull(index)?.let { fired.add(it.threadId) }
            }
            else -> Unit
        }
    }

    fun clear() {
        slots.clear(); fired.clear(); rows = emptyList()
        head0 = null; note = null; open = false; focused = -1
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"

        /**
         * Six rows, and the ceiling is the field rather than the protocol.
         *
         * At 1 m on the crown's 0.078 m pitch, six rows plus a header and a
         * footer is 0.62 m, which is 35 degrees — already at the edge of a
         * 34-degree field. A seventh would be off-screen, and a list you must
         * look around to see is the thing §2.1 forbids. MeshCore radios
         * commonly carry fewer than this; when one carries more the footer says
         * so rather than the rows silently stopping.
         */
        const val MAX = 6
        const val DIST = 1.0f
        const val PLATE_W = 0.40f
        const val PLATE_H = 0.062f
        const val DEPTH = 0.004f
        const val PLATE_BACK = 0.006f
        const val HIT_D = 0.03f
        const val PITCH = 0.078f
        const val TOP_DROP = 0.02f
        const val NOTE_DROP = 0.03f
        const val HOT = 1.10f
        const val DEBOUNCE_MS = 350L

        /** 1.5 degrees at DIST — §4.1's floor is 1.2, the house standard 1.30. */
        const val CAP = 0.026f

        /** Sized for the longest row this can hold, once, so it never re-measures. */
        const val WIDEST = CHAN_WIDEST
        const val HEAD_WIDEST = "CHANNELS — PICK TO SPEAK"
        const val NOTE_WIDEST = "CONNECT A RADIO TO SEE ITS SLOTS"
    }
}

/**
 * The template every row is measured against, and the reason it is a constant.
 *
 * [TextRun.reusable] sizes a panel ONCE, for the longest string it will ever
 * hold, and never resizes — a readout that re-measures itself jitters, and on
 * this SDK it also rebuilds an Android View every time a word changes. The
 * consequence is that a row longer than this template does not grow the panel,
 * it gets CLIPPED inside it, silently, at whatever character the box ends.
 *
 * So the template is the contract and [channelLabel] is what keeps it.
 */
internal const val CHAN_WIDEST = "PUBLIC  PORTLAND METRO  999+  SPEAKS"

/** Longest channel name that fits the row template. */
internal const val CHAN_NAME_MAX = 14

/**
 * One row's words. PURE, and at file scope so it is testable without a Session.
 *
 * Order is deliberate: the PUBLIC warning first, because it is the thing that
 * changes what a person is willing to say and it should not be at the end of a
 * line that might be clipped. The name next, because it is what you are looking
 * for. The count, because weight tells you which band is alive. SPEAKS last,
 * because it is the state the plate's own lighting already carries — the word
 * is the confirmation, not the signal.
 */
internal fun channelLabel(
    name: String,
    publicKey: Boolean,
    count: Int,
    speaking: Boolean,
): String {
    val n = name.trim().uppercase().let {
        // Truncated with a real ellipsis rather than a hard cut, so a clipped
        // name reads as clipped rather than as a channel somebody named badly.
        if (it.length <= CHAN_NAME_MAX) it else it.take(CHAN_NAME_MAX - 1) + "…"
    }.ifBlank { "UNNAMED" }
    // Counts saturate, AND SAY SO. A four-digit count would push the row past
    // the template and clip the SPEAKS off the end — losing the state to show
    // the traffic, which is the wrong trade.
    //
    // The first cut rendered 1234 as "999", which is not a truncation, it is a
    // wrong number: this is a public band that really does carry four figures
    // in an evening, so it would have been wrong on the busiest channel and
    // right nowhere. The plus costs one character of a template we control.
    val c = if (count > 999) "999+" else count.toString()
    // NOT TWICE. The stock MeshCore slot 0 is literally named "Public" and
    // carries the public PSK, so the marker and the name are the same word and
    // the row came out "PUBLIC  PUBLIC  1234" — which reads as a rendering
    // fault, and worse, teaches the eye to skim past the marker on every OTHER
    // row where it is the only warning there is.
    val mark = publicKey && !n.startsWith("PUBLIC")
    return buildString {
        if (mark) append("PUBLIC  ")
        append(n)
        append("  ").append(c)
        if (speaking) append("  SPEAKS")
    }
}
