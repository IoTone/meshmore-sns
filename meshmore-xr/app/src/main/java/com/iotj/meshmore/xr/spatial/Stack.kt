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
 * THE STACK — a column of state you can point at, reused by every bay.
 *
 * Console spec §5 asks for the stack as a REUSABLE PRIMITIVE, and §5.4 gives
 * the argument: "one widget, two depths, and the interaction the user learned
 * at the top level is the one that works inside." This is that widget. CHANNELS
 * and APP are two instances of it with different rows.
 *
 * ## The crown's form, not the console's fan
 *
 * The console fans plates carrying ICONS. A row here is identified by WORDS —
 * there is no silhouette for "Portland Metro" and none for "share location" —
 * so it takes the crown's shape instead: a slab with an edge, sized to its own
 * label, with the hit volume exactly the slab, at a metre where you can point
 * at it. That was the conclusion the crown reached the hard way and there is no
 * reason to reach it twice.
 *
 * ## LIT MEANS ON, NOT FOCUSED
 *
 * The crown lights the plate under the pointer, because there the light is the
 * only thing saying where you are. Here the plate carries a STATE that outlives
 * the glance — whether this channel speaks, whether this setting is on — and a
 * light that means "focused" on one surface and "on" on another is a light that
 * means nothing. Focus is the scale bump instead.
 *
 * ## Dumb on purpose
 *
 * It draws rows and reports picks. It does not know what a channel is, does not
 * know what a setting is, and does not decide what a pick MEANS — including
 * whether a pick needs confirming. That belongs to the host, which is the only
 * thing that knows both halves, and it is what lets one widget serve a list of
 * bands and a list of switches without either leaking into it.
 */
class Stack(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
    /**
     * Which theme's transition grammar this surface arrives under.
     *
     * Passed at construction like [Horizon]'s symbol and for the same reason: a
     * grammar changing mid-reveal would give a surface half of one entrance and
     * half of another.
     */
    private val skin: Theme.Skin = Theme.DEFAULT,
) {

    /**
     * One row, handed in by the host each time the stack opens.
     *
     * [id] is whatever the host wants back when this row is picked — a channel
     * thread id, a setting's name. This class never interprets it.
     */
    class Row(
        val id: String,
        val label: String,
        val lit: Boolean,
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
    private var title: String = ""
    private var footer: String = ""
    /** When this surface opened, for [Reveal]. */
    private var openedAt = 0L
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
                session, context, WIDEST, CAP, argb(theme.text, 0.98f), "stack",
            ) ?: return@repeat
            run.entity.parent = root
            run.entity.setEnabled(false)
            entities += run.entity
            // THE PLATE, per theme. See Theme.Plate: a filled slab washes out
            // the room behind it and a frame does not, which on additive optics
            // is a different mark rather than a cheaper one.
            val dimFacets = plateFacets(skin.plate, lit = false)
            val litFacets = plateFacets(skin.plate, lit = true)
            val plate = MeshEntity.create(
                session, Prims.build(session, dimFacets),
                listOf(Prims.material(session, theme.alt, plateAlpha(skin.plate, false))),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val lit = MeshEntity.create(
                session, Prims.build(session, litFacets),
                listOf(Prims.material(session, theme.accent, plateAlpha(skin.plate, true))),
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
            }.onFailure { Log.w(TAG, "[stack] no input on $index: $it") }
            slots += s
        }
        head0 = TextRun.reusable(
            session, context, HEAD_WIDEST, CAP, argb(theme.accent, 0.95f), "stack-head",
        )?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }
        note = TextRun.reusable(
            session, context, NOTE_WIDEST, CAP * 0.85f, argb(theme.alt, 0.9f), "stack-note",
        )?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }
        Log.i(TAG, "[stack] ${slots.size} slots")
    }

    /**
     * Open with [list].
     *
     * The host builds the rows because the host is what knows both halves — the
     * radio's slots and the wearer's voice preferences — and this surface is
     * deliberately ignorant of either. It draws rows and reports picks.
     */
    fun show(list: List<Row>, title: String, footer: String) {
        rows = list.take(MAX)
        this.title = title
        this.footer = footer
        open = true
        focused = -1
        fired.clear()
        openedAt = android.os.SystemClock.uptimeMillis()
        Log.i(TAG, "[stack] '$title' open with ${rows.size} of ${list.size} rows")
        // NO SILENT TRUNCATION. A bay that grows past MAX drops its last rows
        // and looks completely normal doing it — the setting is simply not
        // there, and the person looking for it concludes the app does not have
        // it. APP is already AT the ceiling, so the next row somebody adds is
        // the one that vanishes.
        if (list.size > MAX) {
            Log.w(TAG, "[stack] '$title' DROPPED ${list.size - MAX} row(s): " +
                list.drop(MAX).joinToString { it.id })
        }
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
        Log.i(TAG, "[stack] closed")
    }

    /** Which row was picked, by its [Row.id]. */
    fun poll(): String? = fired.poll()

    /** Re-label after a toggle, without rebuilding anything. */
    fun update(list: List<Row>, footer: String = this.footer) {
        rows = list.take(MAX)
        this.footer = footer
    }

    fun tick(head: Vector3?, yawRad: Float, nowMs: Long = android.os.SystemClock.uptimeMillis()) {
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
        // Across, so a theme whose entrance slides can slide sideways rather
        // than only toward the wearer.
        val rx = kotlin.math.cos(yawRad)
        val rz = kotlin.math.sin(yawRad)
        val cx = head.x + fx * DIST
        val cz = head.z + fz * DIST
        // The header sits above the column, so the first row is where the gaze
        // already is rather than one plate below a title.
        val top = head.y + TOP_DROP + (rows.size - 1) * PITCH / 2f

        runCatching {
            head0?.entity?.setEnabled(true)
            head0?.setText(title)
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
            // HOW IT ARRIVES, per theme. Settled after a few hundred ms, at
            // which point this is arithmetic that returns the layout's own
            // answer and costs nothing.
            val f = Reveal.at(skin, i, rows.size, nowMs - openedAt)
            if (!f.on) {
                runCatching {
                    s.run.entity.setEnabled(false); s.plate.setEnabled(false)
                    s.lit.setEnabled(false); s.proxy.setEnabled(false)
                }
                return@forEachIndexed
            }
            val p = Vector3(
                cx + rx * f.along - fx * f.depth,
                top - i * PITCH,
                cz + rz * f.along - fz * f.depth,
            )
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
                // NONE draws no plate at all; the row is its words. SEELE puts
                // type on nothing by design, and VOID is a terminal.
                val plated = skin.plate != Theme.Plate.NONE
                s.plate.setEnabled(plated && !row.lit)
                s.plate.setPose(Pose(back, r), Space.ACTIVITY)
                s.lit.setEnabled(plated && row.lit)
                s.lit.setPose(Pose(back, r), Space.ACTIVITY)
                s.run.entity.setScale((if (i == focused) HOT else 1f) * f.scale)
                s.proxy.setEnabled(true)
                s.proxy.setPose(Pose(p, r), Space.ACTIVITY)
            }
        }

        runCatching {
            note?.entity?.setEnabled(true)
            note?.setText(footer)
            val np = Vector3(cx, top - rows.size.coerceAtLeast(1) * PITCH - NOTE_DROP, cz)
            note?.entity?.setPose(Pose(np, facing(np, head)), Space.ACTIVITY)
        }
    }

    fun gazeTargets(): List<Gaze.Target> {
        if (!open) return emptyList()
        return emptyList()
    }

    /**
     * The plate's geometry for this theme.
     *
     * NONE still builds something and the caller never enables it. Same trade
     * the TEXT node symbol makes: every path downstream — focus, the lit swap,
     * the reveal — is written against a plate that exists, and making it
     * nullable to save one small mesh per row would put a branch in all of them
     * for two themes out of nine.
     */
    private fun plateFacets(p: Theme.Plate, lit: Boolean): Prims.Facets = when (p) {
        Theme.Plate.SOLID -> Prims.bar(PLATE_W, PLATE_H, DEPTH)
        // A rule box. Thicker when lit, because a frame cannot brighten its
        // middle — the only thing it has to say "on" with is its own weight.
        Theme.Plate.FRAME ->
            Prims.frame(PLATE_W, PLATE_H, if (lit) RULE * 2.2f else RULE, DEPTH)
        // The block, and behind it a second one offset down and right. Y2K
        // print, and the only plate in the set that is two solids.
        Theme.Plate.OFFSET -> Prims.Facets().also { f ->
            val back = Prims.bar(PLATE_W, PLATE_H, DEPTH)
            f.addTranslated(back, OFFSET_X, -OFFSET_X, -DEPTH)
            f.addTranslated(Prims.bar(PLATE_W, PLATE_H, DEPTH), 0f, 0f, 0f)
        }
        // Built and never shown. See the note above.
        Theme.Plate.NONE -> Prims.bar(PLATE_W * 0.02f, PLATE_H * 0.02f, DEPTH)
    }

    private fun plateAlpha(p: Theme.Plate, lit: Boolean): Float = when (p) {
        // A frame is a fraction of the area of a slab, so at the slab's alpha
        // it reads as a faint scratch. Emission is per-pixel and there are far
        // fewer pixels.
        Theme.Plate.FRAME -> if (lit) 0.95f else 0.55f
        Theme.Plate.OFFSET -> if (lit) 0.5f else 0.28f
        else -> if (lit) 0.42f else 0.16f
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
                rows.getOrNull(index)?.let { fired.add(it.id) }
            }
            else -> Unit
        }
    }

    fun clear() {
        slots.clear(); fired.clear(); rows = emptyList()
        title = ""; footer = ""
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
        const val PLATE_W = ROW_PLATE_W
        /** Frame stroke. Not a hairline — under ~2 mm it vanishes on a wall. */
        const val RULE = 0.0035f
        /** DR POP's shadow-block offset. Hard, and deliberately large. */
        const val OFFSET_X = 0.012f
        const val PLATE_H = 0.062f
        const val DEPTH = 0.004f
        const val PLATE_BACK = 0.006f
        const val HIT_D = 0.03f
        const val PITCH = 0.078f
        const val TOP_DROP = 0.02f
        const val NOTE_DROP = 0.03f
        const val HOT = 1.10f
        const val DEBOUNCE_MS = 350L

        /**
         * 1.30 degrees at DIST — the house standard, and it was 1.49.
         *
         * The larger cap is nicer to read and did not fit: at 1.49 degrees the
         * row template rendered 23.6 cm wider than the plate under it. Between
         * a legible row that overflows its button and one that sits inside it,
         * the button wins — a control whose label is not on it is not a control.
         */
        const val CAP = ROW_CAP_M

        /** Sized for the longest row this can hold, once, so it never re-measures. */
        const val WIDEST = ROW_WIDEST
        const val HEAD_WIDEST = ROW_HEAD_WIDEST
        const val NOTE_WIDEST = ROW_NOTE_WIDEST
    }
}
