// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.content.Context
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.InputEvent
import androidx.xr.scenecore.InteractableComponent
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene
import android.util.Log
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * WHAT AN EMPTY RADAR OWES THE PERSON WEARING IT.
 *
 * Without a radio the scene used to load a ring with nothing on it and say
 * why exactly once — a five-second notice that was gone before most wearers
 * had their bearings. Everything after that was silence: an app that looked
 * finished loading and empty, when the truth was "your radio is not here and
 * I stopped looking." The operator's words: why is the UX so bad for no
 * radio connected — shouldn't we show something instead of nothing?
 *
 * This card is the something. It stands where the mesh would be, says the
 * two causes that account for nearly every case (the radio is off or out of
 * range; a phone is holding it — a connected BLE peripheral stops
 * advertising, so a bonded phone running Meshmore SNS makes the radio
 * invisible to everyone else), and carries its own retry: pinch it and the
 * scan runs again. The host also retries a few times on its own; the card
 * hides during each scan, so the surface itself shows the search happening.
 *
 * It exists only before the FIRST successful link. After a drop the LINK
 * LOST machinery owns the story — that wearer knows what a radio is and
 * where theirs is; this card is for the one who has never seen it work.
 */
class NoRadio(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    private val entities = mutableListOf<Entity>()
    private val fired = ConcurrentLinkedQueue<Unit>()
    private var shown = false

    var visible: Boolean = false
        private set

    suspend fun build(o: Stage.Origin) {
        clear()
        val root = session.scene.activitySpace
        val at = o.place(0f, DIST, DROP)

        fun line(idx: Int, text: String, rgb: Int, cap: Float) {
            val run = TextRun.reusable(
                session, context, text, com.iotj.meshmore.xr.L10n.cap(cap),
                argb(rgb, 0.95f), "noradio-$idx",
            ) ?: return
            run.setText(text)
            run.entity.parent = root
            run.entity.setPose(
                Pose(Vector3(at.x, at.y + TOP - idx * LINE, at.z)), Space.ACTIVITY,
            )
            run.entity.setEnabled(false)
            entities += run.entity
        }
        line(0, context.getString(com.iotj.meshmore.xr.R.string.nr_title), theme.accent, CAP_TITLE)
        line(1, context.getString(com.iotj.meshmore.xr.R.string.nr_check), theme.text, CAP)
        line(2, context.getString(com.iotj.meshmore.xr.R.string.nr_phone), theme.text, CAP)
        line(3, context.getString(com.iotj.meshmore.xr.R.string.nr_retry), theme.alt, CAP)

        // One proxy over the whole card: the card IS the button. A wearer
        // shown a wall of text and a separate small target will pinch the
        // text; meeting that beats correcting it.
        MeshEntity.create(
            session, Prims.build(session, Prims.mote(HIT_R, 5, 8)),
            listOf(Prims.ghost(session)),
        ).also {
            it.parent = root
            it.setPose(Pose(Vector3(at.x, at.y + TOP - 1.5f * LINE, at.z)), Space.ACTIVITY)
            it.setEnabled(false)
            entities += it
            runCatching {
                it.addComponent(
                    InteractableComponent.create(session) { ev ->
                        if (ev.action == InputEvent.Action.UP) fired.add(Unit)
                    },
                )
            }
        }
        Log.i(TAG, "[noradio] card built")
    }

    fun setVisible(v: Boolean) {
        if (v == shown) return
        shown = v
        visible = v
        entities.forEach { runCatching { it.setEnabled(v) } }
        if (v) Log.i(TAG, "[noradio] shown — no radio, not scanning")
    }

    /** True once per pinch on the card. */
    fun poll(): Boolean = fired.poll() != null

    fun clear() {
        entities.forEach { runCatching { it.parent = null } }
        entities.forEach { runCatching { it.dispose() } }
        entities.clear()
        shown = false
        visible = false
    }

    private fun argb(rgb: Int, a: Float): Int =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"
        /** Reading distance, straight ahead, a little below eye. */
        const val DIST = 1.35f
        const val DROP = -0.05f
        /** 1.35 m x 0.03 cap = 1.27 degrees; the title a step up. */
        const val CAP = 0.030f
        const val CAP_TITLE = 0.042f
        const val LINE = 0.085f
        const val TOP = 0.13f
        const val HIT_R = 0.24f
    }
}
