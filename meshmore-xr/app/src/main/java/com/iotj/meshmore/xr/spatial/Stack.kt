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
    private var skin: Theme.Skin = Theme.DEFAULT,
) {

    /**
     * One row, handed in by the host each time the stack opens.
     *
     * [id] is whatever the host wants back when this row is picked — a channel
     * thread id, a setting's name. This class never interprets it.
     */
    data class Row(
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

    /** Everything the host handed us, across all pages. */
    private var all: List<Row> = emptyList()
    /** Just what is on screen now — [all] windowed, plus a MORE row if needed. */
    private var rows: List<Row> = emptyList()
    private var page = 0
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
                session, context, WIDEST, CAP * skin.rowScale,
                argb(theme.text, 0.98f), "stack",
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
        all = fitAll(list)
        page = 0
        repage()
        this.title = fit(title, HEAD_WIDEST, "title")
        this.footer = fit(footer, NOTE_WIDEST, "footer")
        open = true
        focused = -1
        fired.clear()
        openedAt = android.os.SystemClock.uptimeMillis()
        Log.i(
            TAG,
            "[stack] '$title' open with ${list.size} row(s) over $pages page(s)",
        )
    }

    /**
     * THE PANEL ENFORCES ITS OWN TEMPLATE, because the caller kept forgetting.
     *
     * [TextRun.reusable] sizes the head and note panels ONCE, for [HEAD_WIDEST]
     * and [NOTE_WIDEST]. A longer string does not grow them — it is clipped
     * inside the box, silently, at whatever character the box ends. The radio
     * bay opened as `RADIO — 910.525MHz BW62.5 SF7 4/5 22`, having lost the
     * `dBm` off the end: 36 characters posted into a 30-character panel by a
     * caller that clamped the VALUE to 28 and forgot the 8-character prefix it
     * was about to put in front of it. That is the same half-checked clamp that
     * had already been fixed twice, in [radioRow] and in the row template, and
     * fixing it a third time at the call site would only have queued up a
     * fourth.
     *
     * So the clamp lives here, where the panel and its template are the same
     * object. Two consequences, both deliberate: an over-long title now ends in
     * an ellipsis, so a reader can SEE that something was cut rather than
     * reading a truncation as the whole value; and it logs a warning naming the
     * offender, so it is caught on the first launch of a new bay rather than in
     * a photograph. Callers that fit are unaffected — the builders in `Rows.kt`
     * are still the place the words are supposed to be made to fit, and
     * `RowsTest` still asserts that they do. This is the backstop, not the plan.
     */
    /**
     * The same clamp for row labels — applied where rows ENTER, never in the
     * draw. The draw runs every frame, and a clamp there would either log the
     * same warning sixty times a second or have to stay silent to avoid it;
     * doing it once per [show]/[update] gets one warning per offending list.
     */
    private fun fitAll(list: List<Row>): List<Row> = list.map {
        if (it.label.length <= WIDEST.length) it
        else it.copy(label = fit(it.label, WIDEST, "row '${it.id}'"))
    }

    private fun fit(s: String, template: String, what: String): String {
        if (s.length <= template.length) return s
        Log.w(
            TAG,
            "[stack] $what over template by ${s.length - template.length} " +
                "char(s), clipping: '$s'",
        )
        return s.take(template.length - 1) + "…"
    }

    /**
     * WEAR A DIFFERENT THEME — the half of a theme change this surface missed.
     *
     * Choosing a theme retints every material and rebuilds the horizon, and
     * until now did nothing at all to the bays. That left the menus wearing the
     * LAUNCH theme's structure while the mesh wore the chosen one: VECTORLINE's
     * wire nodes over HALO's solid slabs, SEELE's one-row-per-page discipline
     * silently not applying, a 1.23 row scale that never arrived. The reported
     * bug — "it just changes the theme color" — was fixed for the ring and left
     * standing here, which is the worse half: the app looks like it restyles
     * until you open a menu.
     *
     * A REBUILD, not a repaint, because [Theme.Plate] is GEOMETRY. A frame and
     * a slab are different meshes, and on additive optics that is the whole
     * difference between a control you can see the room through and one you
     * cannot — not a colour that [Ink] could swap under it.
     *
     * The contents survive: what is on screen is re-shown afterwards, so
     * restyling a bay you have open does not close it under your hand.
     */
    suspend fun restyle(next: Theme.Skin) {
        if (next.key == skin.key) return
        val was = open
        val rows0 = all
        val title0 = title
        val footer0 = footer
        val page0 = page
        skin = next
        build()
        if (was) {
            show(rows0, title0, footer0)
            // show() resets to the first page; put the reader back where they
            // were, unless the new theme's page size no longer reaches it.
            page = page0.coerceIn(0, (pages - 1).coerceAtLeast(0))
            repage()
        }
        Log.i(TAG, "[stack] restyled to ${next.key} (${next.plate}, ${skin.rowsPerPage}/page)")
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

    /**
     * Which row was picked, by its [Row.id].
     *
     * The MORE control is CONSUMED HERE and never reaches the host. Paging is
     * this widget's business — the host asked for a list of settings, not a
     * list of settings and a navigation control, and making every bay learn to
     * ignore an id it never supplied is how a shared primitive stops being
     * shared.
     */
    fun poll(): String? {
        while (true) {
            val id = fired.poll() ?: return null
            if (id != MORE) return id
            page++
            repage()
            Log.i(TAG, "[stack] page ${page + 1} of $pages")
        }
    }

    /**
     * Re-label after a toggle, without rebuilding anything and WITHOUT losing
     * the wearer's place. A toggle on page two that snapped back to page one
     * would make the second page unusable — every pick would throw you out of
     * it.
     */
    fun update(list: List<Row>, footer: String = this.footer) {
        all = fitAll(list)
        repage()
        this.footer = fit(footer, NOTE_WIDEST, "footer")
    }

    /**
     * Rows of CONTENT per page, for this theme.
     *
     * MAX when everything fits and there is no MORE control to house; one
     * fewer once paging starts, because the way forward has to occupy a row.
     * SEELE says one and means it — see [Theme.Skin.rowsPerPage].
     */
    private val perPage: Int
        get() {
            val want = skin.rowsPerPage.coerceIn(1, MAX)
            // A theme that shows fewer rows than the list has is ALWAYS paging,
            // so it always pays the MORE row. A theme at MAX only pays it when
            // the list actually overflows.
            return if (want < MAX) want else MAX - 1
        }

    /** How many pages the current list needs. */
    val pages: Int
        get() = if (all.size <= MAX && skin.rowsPerPage >= MAX) 1
        else ((all.size + perPage - 1) / perPage).coerceAtLeast(1)

    /**
     * Window [all] onto the visible rows, appending the MORE control when there
     * is more than one page.
     *
     * PER_PAGE IS MAX MINUS ONE WHEN PAGING, because the way forward has to
     * live somewhere and the only somewhere is a row. Five settings and a way
     * to the next five beats six settings and no way to reach the seventh.
     */
    private fun repage() {
        if (all.size <= MAX && skin.rowsPerPage >= MAX) {
            rows = all
            page = 0
            return
        }
        val n = pages
        page = ((page % n) + n) % n
        val from = page * perPage
        val window = all.drop(from).take(perPage)
        rows = window + Row(
            id = MORE,
            label = "MORE  ${page + 2} OF $n",
            lit = false,
        )
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
            // FOCUS IS SCALE AND A PUSH, per theme. Both are properties the
            // reveal already owns, so focus and arrival cannot fight: they add.
            val hot = i == focused
            val push = if (hot) skin.focusPush else 0f
            val p = Vector3(
                cx + rx * f.along - fx * (f.depth + push),
                top - i * PITCH,
                cz + rz * f.along - fz * (f.depth + push),
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
                // THE WHOLE ROW GROWS, not just the words on it.
                //
                // The focus bump used to scale the run alone and leave the plate
                // at its built size, which is invisible for as long as no row is
                // wide enough to reach the plate's edge — and every row was
                // short, so it stayed invisible. The region list is the first
                // surface whose labels actually spend the template: `AUSTRALIA
                // SA/WA/QLD  923.125` is all 28 cells, 43.2 cm of ink on a 46 cm
                // plate, and at a 1.10 focus bump it becomes 47.5 cm — text
                // hanging off both ends of its own button. At the widest theme's
                // 1.18 it is 51 cm, and 2.5 cm hangs off each end.
                //
                // Scaling the plate with it makes the relationship
                // scale-invariant, which is the property the layout arithmetic
                // has been assuming all along: a row is a row at any size. It
                // also matches what the bump is FOR — the plate is the button,
                // and a button that stays put while its label swells is not a
                // button reacting to focus, it is a label coming loose from one.
                //
                // THE HIT VOLUME DOES NOT GROW. It is the only part of the row
                // that stays put, because a target that expands under the
                // pointer expands the region that keeps it focused, and a row
                // that is easier to stay on than to leave is how a list starts
                // resisting the hand moving down it.
                val bump = (if (hot) skin.focusScale else 1f) * f.scale
                s.run.entity.setScale(bump)
                s.plate.setScale(bump)
                s.lit.setScale(bump)
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

        /** The paging control's id. Never leaves this class — see [poll]. */
        const val MORE = "\u0001more"
        const val DIST = 1.0f
        const val PLATE_W = ROW_PLATE_W
        /** Frame stroke. Not a hairline — under ~2 mm it vanishes on a wall. */
        const val RULE = 0.0035f
        /** DR POP's shadow-block offset. Hard, and deliberately large. */
        const val OFFSET_X = 0.012f
        const val PLATE_H = ROW_PLATE_H
        const val DEPTH = 0.004f
        const val PLATE_BACK = 0.006f
        const val HIT_D = 0.03f
        const val PITCH = ROW_PITCH
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
