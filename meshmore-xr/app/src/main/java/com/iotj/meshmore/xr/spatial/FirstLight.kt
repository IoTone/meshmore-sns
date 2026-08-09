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
 * S0 · FIRST LIGHT — one mote, and the word TOUCH.
 *
 * The brief: "The first-time XR user is the hardest user; most have never used
 * XR. This surface teaches the paradigm by DOING it, not by explaining it. A
 * single MOTE appears at arm's length. 'Touch it.' That is the entire first
 * instruction."
 *
 * That is all this is, and the restraint is the design. A tutorial that walks
 * through the reel, the crown, the console and the horizon teaches nothing,
 * because none of it is retained until there is a reason to want it. What a
 * first-time wearer actually needs to learn is that THINGS IN THE AIR RESPOND
 * TO YOUR HANDS, and one mote teaches that in about four seconds.
 *
 * ## It is also the diagnostic, which is why it ships before the tutorial does
 *
 * Hand tracking either works or it does not, and when it does not, every other
 * surface in this app presents as broken in a different way — the reel does not
 * turn, the crown does not answer, the console will not open. Testers report
 * five bugs. This turns all five into one question, asked once, in four seconds,
 * before anything else is on screen.
 *
 * ## The fail-safe is the point of the second line
 *
 * The brief requires that "every permission denial has a working path. No hand
 * tracking → gaze + head-dwell selection." So if the mote goes untouched for
 * [HINT_MS] it says so and offers the dwell, rather than leaving somebody
 * waving at a dot. Somebody who reaches that line has learned the more
 * important thing anyway: that this app has a way through when the hands do not
 * work.
 */
class FirstLight(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    private var mote: MeshEntity? = null
    private var ring: MeshEntity? = null
    private var proxy: MeshEntity? = null
    private var line: TextRun.Run? = null
    private var hint: TextRun.Run? = null
    private val entities = mutableListOf<Entity>()

    private var at: Vector3? = null
    private var shownAt = 0L
    private var touched = false

    var open: Boolean = false
        private set

    /** Raised once, when the wearer touches it. The host decides what follows. */
    var onTouched: (() -> Unit)? = null

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        mote = MeshEntity.create(
            session, Prims.build(session, Prims.mote(R, 9, 14)),
            listOf(Prims.material(session, theme.accent, 0.7f)),
        ).also { it.parent = root; it.setEnabled(false); entities += it }
        // A BRIGHT KEYLINE, not a dark halo. On additive optics a dark edge
        // cannot subtract the room behind it, so the silhouette has to be drawn
        // in light — and a lone sphere against an unknown wall needs one.
        ring = MeshEntity.create(
            session, Prims.build(session, Prims.halo(R * 1.5f, R * 0.10f)),
            listOf(Prims.material(session, theme.alt, 0.9f)),
        ).also { it.parent = root; it.setEnabled(false); entities += it }
        proxy = MeshEntity.create(
            session, Prims.build(session, Prims.mote(R * 2.2f, 6, 10)),
            listOf(Prims.ghost(session)),
        ).also { it.parent = root; it.setEnabled(false); entities += it }
        runCatching {
            proxy?.addComponent(InteractableComponent.create(session) { ev -> onInput(ev) })
        }.onFailure { Log.w(TAG, "[first] no input on the mote: $it") }

        line = run(root, WIDEST, "first-line", theme.text)
        hint = run(root, HINT_WIDEST, "first-hint", theme.alt)
        Log.i(TAG, "[first] built")
    }

    private suspend fun run(root: Entity, widest: String, name: String, rgb: Int): TextRun.Run? =
        TextRun.reusable(session, context, widest, CAP, argb(rgb, 0.95f), name)
            ?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }

    fun showAt(head: Vector3, yawRad: Float, nowMs: Long) {
        val fx = kotlin.math.sin(yawRad)
        val fz = -kotlin.math.cos(yawRad)
        at = Vector3(head.x + fx * DIST, head.y + DROP, head.z + fz * DIST)
        open = true
        touched = false
        shownAt = nowMs
        runCatching { line?.setText("TOUCH THIS") }
        Log.i(TAG, "[first] open")
    }

    fun hide() {
        if (!open) return
        open = false
        listOfNotNull<Entity>(mote, ring, proxy, line?.entity, hint?.entity)
            .forEach { runCatching { it.setEnabled(false) } }
        Log.i(TAG, "[first] closed")
    }

    fun tick(head: Vector3?, nowMs: Long) {
        if (!open) return
        val p = at ?: return
        if (head == null) return
        val r = facing(p, head)
        // A SLOW BREATH, in scale. Nothing else on the horizon idles (§7.1
        // "nothing idles"), and this is the one place where an exception earns
        // itself: a wearer who does not yet know that anything here is
        // interactive needs the object to look alive before they will reach for
        // it. It stops existing the moment it is touched.
        val t = ((nowMs - shownAt) % BREATH_MS).toFloat() / BREATH_MS
        val pulse = 1f + 0.06f * kotlin.math.sin(t * 2f * Math.PI.toFloat())
        runCatching {
            mote?.setEnabled(true); ring?.setEnabled(true); proxy?.setEnabled(true)
            mote?.setPose(Pose(p, r), Space.ACTIVITY)
            mote?.setScale(pulse)
            ring?.setPose(Pose(p, r), Space.ACTIVITY)
            ring?.setScale(pulse)
            proxy?.setPose(Pose(p), Space.ACTIVITY)
        }
        runCatching {
            line?.entity?.setEnabled(true)
            val lp = Vector3(p.x, p.y - LABEL_DROP, p.z)
            line?.entity?.setPose(Pose(lp, facing(lp, head)), Space.ACTIVITY)
            // THE WAY THROUGH, offered rather than waited for.
            val stuck = nowMs - shownAt > HINT_MS
            hint?.entity?.setEnabled(stuck)
            if (stuck) {
                hint?.setText("OR LOOK AT IT AND HOLD")
                val hp = Vector3(p.x, lp.y - CAP * 2.2f, p.z)
                hint?.entity?.setPose(Pose(hp, facing(hp, head)), Space.ACTIVITY)
            }
        }
    }

    /** The dwell path, so a wearer with no hand tracking is not stranded. */
    fun gazeTargets(): List<Gaze.Target> {
        if (!open) return emptyList()
        val p = at ?: return emptyList()
        return listOf(Gaze.Target("first-mote", p, CONE_RAD) { fire() })
    }

    private fun onInput(ev: InputEvent) {
        if (!open) return
        if (ev.action == InputEvent.Action.UP) {
            Reach.consumed()
            fire()
        }
    }

    private fun fire() {
        if (touched) return
        touched = true
        Log.i(TAG, "[first] touched — hand tracking confirmed")
        onTouched?.invoke()
    }

    private fun facing(p: Vector3, head: Vector3): Quaternion {
        val dx = head.x - p.x
        val dz = head.z - p.z
        if (dx * dx + dz * dz < 1e-6f) return Quaternion.fromEulerAngles(0f, 0f, 0f)
        return Quaternion.fromEulerAngles(
            0f, Math.toDegrees(atan2(dx, dz).toDouble()).toFloat(), 0f,
        )
    }

    fun clear() {
        mote = null; ring = null; proxy = null; line = null; hint = null
        open = false; at = null; touched = false
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"

        /** Arm's length, as the brief says. Also where a first reach lands. */
        const val DIST = 0.45f

        /** A little below the eye line — where a hand goes without being told. */
        const val DROP = -0.08f

        /** 4.1° at DIST. Above the 3.0° icon floor, and deliberately inviting. */
        const val R = 0.016f

        /** 1.30° at DIST, the house standard. */
        const val CAP = 0.0102f
        const val LABEL_DROP = 0.055f
        const val CONE_RAD = 0.05f
        const val BREATH_MS = 2400L

        /**
         * How long somebody waves at a dot before being offered another way.
         *
         * Long enough that a wearer who is simply looking around is not told
         * they have failed, short enough that somebody whose hand tracking is
         * genuinely dead is not left there.
         */
        const val HINT_MS = 12_000L

        const val WIDEST = "TOUCH THIS"
        const val HINT_WIDEST = "OR LOOK AT IT AND HOLD"
    }
}
