// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.content.Context
import android.util.Log
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.InputEvent
import androidx.xr.scenecore.InteractableComponent
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * WHAT AN EMPTY RING OWES THE PERSON WEARING IT.
 *
 * There are exactly two reasons this app draws nothing while working
 * perfectly, and until this card existed it explained neither for longer than
 * five seconds:
 *
 *  - NO RADIO. Nothing to draw. Usually the radio is off or out of range, and
 *    the second-commonest cause is invisible by design: a connected BLE
 *    peripheral stops advertising, so a phone running Meshmore SNS makes the
 *    radio disappear from everything else.
 *  - NO POSITION. Plenty to draw and nowhere to put it. Every mark on the
 *    horizon is a BEARING AND RANGE FROM THE WEARER, so with no origin the
 *    whole mesh is undrawable — 316 positioned peers held, none placeable,
 *    ring empty. A board with no GNSS reports 0/0 forever and never says why;
 *    see [com.iotj.meshmore.xr.DeviceBook], which is where the app keeps what
 *    the protocol will not tell it.
 *
 * ONE CARD, ONE MESSAGE. They are shown by the same surface because they must
 * never both stand: a wearer facing two explanations picks neither, and no
 * radio makes the position question moot anyway.
 *
 * THE WHOLE CARD IS THE BUTTON. A wall of text beside a small separate target
 * gets pinched on the text; meeting that beats correcting it.
 */
class Advice(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    enum class Kind { NONE, NO_RADIO, NO_FIX }

    /** Every line of every message, built once, shown by the set. */
    private val sets = linkedMapOf<Kind, List<Entity>>()
    private var proxy: Entity? = null
    private var at: Vector3? = null
    private val fired = ConcurrentLinkedQueue<Unit>()

    var kind: Kind = Kind.NONE
        private set

    /**
     * BUILD EVERY WORD THIS CARD CAN EVER SAY, NOW, AND HIDE IT ALL.
     *
     * Two hard rules on this runtime, both learned by staring at a card that
     * logged perfect behaviour and drew nothing:
     *
     *  1. A PanelEntity created after the scene is up does not attach. It is
     *     created without error — TextRun logs its pixel size, no exception —
     *     and is simply not in the world. Not blank: absent, boundaries and
     *     all. This is why every panelled surface in this app (the stack's six
     *     rows, the horizon's forty labels, the six channel bands) is built at
     *     startup and reused forever, and it is not a performance habit.
     *  2. A panel's words are whatever it was HOLDING when it was created.
     *     [TextRun.reusable] blanks its template on purpose, and a later
     *     setText from the frame loop does not reach the surface — the card
     *     stood there as four correctly-placed, perfectly empty rectangles.
     *
     * Together those say: build each line around its final string, up front,
     * with [TextRun.create] so nothing blanks it. Eight small panels is the
     * whole cost of a card that cannot fail to appear.
     *
     * The price is that nothing on the card can be composed at runtime — no
     * live count of undrawable peers, no board name in the sentence. Those go
     * to the log and the notice band, which are built to change.
     */
    suspend fun build(o: Stage.Origin) {
        clear()
        val root = session.scene.activitySpace
        val here = o.place(0f, DIST, DROP)
        at = here
        val ctx = context

        suspend fun set(kind: Kind, text: List<String>) {
            val made = mutableListOf<Entity>()
            text.forEachIndexed { idx, t ->
                val cap = if (idx == 0) CAP_TITLE else CAP
                val rgb = when (idx) {
                    0 -> theme.accent
                    3 -> theme.alt
                    else -> theme.text
                }
                val run = TextRun.create(
                    session, ctx, t, com.iotj.meshmore.xr.L10n.cap(cap),
                    argb(rgb, 0.95f), "advice-${kind.name.lowercase()}-$idx",
                ) ?: return@forEachIndexed
                run.entity.parent = root
                run.entity.setPose(
                    Pose(Vector3(here.x, here.y + TOP - idx * LINE, here.z)), Space.ACTIVITY,
                )
                run.entity.setEnabled(false)
                made += run.entity
            }
            sets[kind] = made
        }

        set(
            Kind.NO_RADIO,
            listOf(
                ctx.getString(com.iotj.meshmore.xr.R.string.nr_title),
                ctx.getString(com.iotj.meshmore.xr.R.string.nr_check),
                ctx.getString(com.iotj.meshmore.xr.R.string.nr_phone),
                ctx.getString(com.iotj.meshmore.xr.R.string.nr_retry),
            ),
        )
        set(
            Kind.NO_FIX,
            listOf(
                ctx.getString(com.iotj.meshmore.xr.R.string.nf_title),
                ctx.getString(com.iotj.meshmore.xr.R.string.nf_nofix),
                ctx.getString(com.iotj.meshmore.xr.R.string.nf_stuck),
                ctx.getString(com.iotj.meshmore.xr.R.string.nf_act),
            ),
        )

        MeshEntity.create(
            session, Prims.build(session, Prims.mote(HIT_R, 5, 8)),
            listOf(Prims.ghost(session)),
        ).also {
            it.parent = root
            it.setPose(Pose(Vector3(here.x, here.y + TOP - 1.5f * LINE, here.z)), Space.ACTIVITY)
            it.setEnabled(false)
            proxy = it
        }
        Log.i(TAG, "[advice] built ${sets.values.sumOf { it.size }} line(s) for ${sets.size} message(s)")
    }

    /**
     * Show one of the two messages, or neither.
     *
     * Only ever an enable: see [build] for why nothing here composes text.
     * [board] is not written on the card — the runtime cannot — but it is what
     * the log says, and it is why this is worth knowing at all.
     */
    fun say(kind: Kind, board: String? = null) {
        if (kind == this.kind) return
        this.kind = kind
        sets.forEach { (k, ents) ->
            ents.forEach { runCatching { it.setEnabled(k == kind) } }
        }
        runCatching { proxy?.setEnabled(kind != Kind.NONE) }
        if (kind == Kind.NONE) fired.clear()
        Log.i(TAG, "[advice] $kind" + (board?.let { " (radio: $it)" } ?: ""))
    }

    /** True once per pinch on the card. */
    fun poll(): Boolean = fired.poll() != null

    fun clear() {
        val doomed = sets.values.flatten() + listOfNotNull(proxy)
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
        sets.clear()
        proxy = null
        at = null
        fired.clear()
        kind = Kind.NONE
    }

    private fun argb(rgb: Int, a: Float): Int =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    companion object {
        private const val TAG = "MeshmoreXR"
        /** Reading distance, straight ahead, a little below eye. */
        const val DIST = 1.35f
        const val DROP = -0.05f
        /** 1.35 m x 0.03 cap = 1.27 degrees; the title a step up. */
        const val CAP = 0.030f
        const val CAP_TITLE = 0.042f
        const val LINE = 0.085f
        const val TOP = 0.13f
        const val HIT_R = 0.24f

        /** The widest line either message can carry. See [build]. */
        const val WIDEST = "PINCH HERE — USE HEADSET LOCATION"
        const val WIDEST_TITLE = "NO POSITION"
        val WIDEST_JA = "設".repeat(15)
        val WIDEST_TITLE_JA = "設".repeat(8)
    }
}
