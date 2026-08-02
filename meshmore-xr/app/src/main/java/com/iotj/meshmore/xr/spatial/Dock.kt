// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

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

/**
 * THE DOCK — how a surface gets summoned, and the only thing that is always on.
 *
 * The problem it answers, seen on hardware: the RADIO rack left standing in the
 * room is a live radio configuration sitting in the space you gesture in. Eleven
 * controls, four of which can strand the hardware, permanently one stray pinch
 * away while you are doing something else. Every other surface is safe to leave
 * around because reading the mesh cannot change it. Settings are not.
 *
 * So settings are SUMMONED. The dock is the summoning: a short row of pips, each
 * standing for a surface, low and off to the side where you have to go to it.
 *
 * WHAT THIS IS A DOWNPAYMENT ON. The design brief owes a back-of-hand menu, and
 * that is where these pips belong — anchored to the wrist, hidden until you turn
 * your hand over, which is the most deliberate "open settings" gesture available
 * and costs no world space at all. The Aura reports hand tracking, so the anchor
 * is reachable; what is not yet built is the palm-facing test and the wrist
 * pose. Until then the pips live at a fixed body-locked spot.
 *
 * The INTERACTION is the part that transfers, and it is deliberately identical
 * to what the hand menu will need: a pip is a target you pinch, it toggles one
 * surface, and exactly one surface is open at a time. Moving that to the wrist
 * later changes where the pips are and nothing else.
 */
class Dock(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: android.content.Context,
) {

    private var headAt: Vector3? = null

    /**
     * Face the caption at the viewer, in YAW AND PITCH.
     *
     * The dock sits about 30 degrees below eye level, so it is looked at from
     * above — and a vertical quad seen from 30 degrees above foreshortens to a
     * sliver. That is what "the labels are empty, cut off near the top of the
     * text" was: not empty and not clipped, but edge-on.
     *
     * Yaw alone is not enough here, which is the difference from the microhud.
     * The microhud is at eye level and only ever turned about; the dock is
     * BELOW you, so the pitch term is the whole problem.
     */
    private fun facing(at: Vector3): Quaternion {
        val h = headAt ?: return Quaternion.fromEulerAngles(0f, 0f, 0f)
        val dx = h.x - at.x
        val dy = h.y - at.y
        val dz = h.z - at.z
        val flat = kotlin.math.sqrt(dx * dx + dz * dz)
        if (flat < 1e-5f) return Quaternion.fromEulerAngles(0f, 0f, 0f)
        val yaw = Math.toDegrees(kotlin.math.atan2(dx, dz).toDouble()).toFloat()
        val pitch = Math.toDegrees(kotlin.math.atan2(dy, flat).toDouble()).toFloat()
        // Yaw about world Y, then pitch about the panel's own X — composed
        // rather than written as an Euler triple, for the reason the microhud
        // and the rack both learned: this library's Euler ORDER is not the one
        // the argument names suggest.
        //
        // The pitch is NEGATED, and that sign was settled by looking at it, not
        // by reasoning about it. The first build tilted the caption further away
        // from the eye instead of toward it, which on screen is the same symptom
        // as no rotation at all — a sliver — and is why deriving this in a
        // comment has been wrong four times in this project.
        return Quaternion.fromEulerAngles(0f, yaw, 0f) *
            Quaternion.fromAxisAngle(Vector3(1f, 0f, 0f), -pitch)
    }

    private val captions = HashMap<String, TextRun.Run>()
    private val entities = mutableListOf<Entity>()
    private val pips = mutableListOf<Pip>()
    private val fired = java.util.concurrent.ConcurrentLinkedQueue<Pip>()

    private inner class Pip(
        val name: String,
        val ring: MeshEntity,
        val lamp: MeshEntity,
        val captionAt: Vector3,
        val toggle: () -> Unit,
    ) {
        var lastFire = 0L
        var lit = false
        /** Which pointers are on it. BOTH hands emit rays, hence a set. */
        val pointers = mutableSetOf<String>()
        var hot = false
        var exitAt = 0L
    }

    /** Raised when a pip takes focus. The host makes the sound. */
    var onFocus: ((String) -> Unit)? = null

    suspend fun build(o: Stage.Origin, items: List<Pair<String, () -> Unit>>) {
        clear()
        val root = session.scene.activitySpace

        // LOW AND FORWARD, at about -30 degrees. Far enough down that it is never
        // in the world window or under the microhud, close enough that finding it
        // is one glance rather than a search. You look DOWN for settings, which
        // is the same place the HERE marker lives and the same place a wrist
        // would be.
        val base = o.place(0f, REACH, DROP)

        items.forEachIndexed { i, (name, act) ->
            val x = (i - (items.size - 1) / 2f) * PITCH
            val at = Vector3(base.x + x, base.y, base.z)

            // A RING, not a mote. Every sphere in this scene is a node; a pip
            // that looked like one would read as a radio improbably close by.
            val ring = MeshEntity.create(
                session, Prims.build(session, Prims.halo(R, R * 0.22f)),
                listOf(Prims.material(session, theme.alt, 0.75f)),
            ).also { it.parent = root; it.setPose(Pose(at), Space.ACTIVITY); entities += it }

            // The lamp inside says whether that surface is currently open. A
            // dock that cannot tell you what is already up is how you end up
            // summoning a thing that was behind you all along.
            val lamp = MeshEntity.create(
                session, Prims.build(session, Prims.mote(R * 0.45f, 5, 8)),
                listOf(Prims.material(session, theme.accent, 1f)),
            ).also {
                it.parent = root; it.setPose(Pose(at), Space.ACTIVITY)
                it.setAlpha(DIM); entities += it
            }

            // THE NAME STAYS UP. A dock you have to hover to identify is a
            // dock you learn by poking it, and seven unlabelled rings are a
            // guessing game — which is what these were, because they were sized
            // wrong rather than because a label could not fit.
            //
            // The old sizing reserved 18 characters ("IN +9999 NNE 999KM") for
            // a future magnified-area readout that was never built. At 0.137 m
            // against a 0.075 m pip pitch every caption overlapped both its
            // neighbours no matter how short the word was, and hiding all but
            // the focused one was the workaround for that.
            //
            // What a pip can actually say is its own name or a short state
            // string — COMPASS is the longest at 7, "OUT x99" also 7. Eight
            // cells is 0.063 m, which clears the pitch, and a shorter word just
            // carries transparent margin that emits nothing on this display.
            //
            // If a genuinely long readout is wanted later it does not belong in
            // this row: it wants its own line below the dock, where it can be as
            // wide as it likes without pushing the names around.
            TextRun.reusable(
                session, context, CAPTION_WIDEST, CAP, argb(theme.alt, 0.95f), "dock-caption",
            )?.also {
                captions[name] = it
                it.entity.parent = root
                it.setText(name)
                it.entity.setEnabled(true)
                runCatching { it.entity.setAlpha(CAPTION_DIM) }
                entities += it.entity
            }

            val pip = Pip(name, ring, lamp, Vector3(at.x, at.y - R * 2.4f, at.z), act)
            pips += pip

            // Hit proxy, same reasoning as everywhere else: the thing you point
            // at is deliberately bigger than the thing you see, and alpha 0.02
            // rather than 0 so the renderer cannot decide to skip it.
            MeshEntity.create(
                session, Prims.build(session, Prims.mote(R * 2.0f, 5, 8)),
                listOf(Prims.ghost(session)),
            ).also {
                it.parent = root; it.setPose(Pose(at), Space.ACTIVITY)
                entities += it
                runCatching {
                    it.addComponent(InteractableComponent.create(session) { ev -> onInput(pip, ev) })
                }.onFailure { e -> Log.w(TAG, "[dock] no input on $name: $e") }
            }
        }
        Log.i(TAG, "[dock] ${pips.size} pip(s) up")
    }

    /**
     * Rename a pip. This is the anchor for magnified navigation: the dock is
     * the one surface that is always present, so it is the only place a "you
     * are here" can live without competing with the ring for space.
     */
    /**
     * Give a pip something other than its own name to say. Null restores it.
     *
     * Used for state a pip carries that the user has to see without pointing at
     * it — the magnification depth, which is a "you are here" and would be
     * useless if you had to go and ask. It no longer pins anything visible:
     * every caption is visible.
     */
    fun setCaption(name: String, caption: String?) {
        captions[name]?.let { c ->
            // The words change; the label does not come and go. An override
            // that appeared and vanished was readable only as "something just
            // happened here", which is not what a state readout is for.
            runCatching { c.setText(caption ?: name) }
        }
    }

    /** Light the pip for whichever surface is open; dark for the rest. */
    fun setLit(name: String, lit: Boolean) {
        pips.firstOrNull { it.name == name }?.let {
            it.lit = lit
            it.lamp.setAlpha(if (lit) 1f else DIM)
        }
    }

    private fun onInput(p: Pip, ev: InputEvent) {
        val key = ev.pointerType.toString()
        when (ev.action) {
            InputEvent.Action.HOVER_ENTER, InputEvent.Action.HOVER_MOVE -> p.pointers += key
            InputEvent.Action.HOVER_EXIT -> {
                p.pointers -= key
                p.exitAt = android.os.SystemClock.uptimeMillis()
            }
            InputEvent.Action.UP -> {
                val now = android.os.SystemClock.uptimeMillis()
                if (now - p.lastFire < DEBOUNCE_MS) return
                p.lastFire = now
                Reach.consumed()
                fired.add(p)
            }
            else -> Unit
        }
    }

    /**
     * FOCUS, reconciled per frame rather than from the events themselves.
     *
     * A pip you cannot tell you are pointing at is a pip you aim by trial: you
     * pinch, nothing happens, and you cannot tell whether you missed or whether
     * the control is dead. Focus answers that before the pinch.
     *
     * Reconciled with a grace period because hand tracking drops HOVER_EXIT and
     * re-enters constantly at the edge of a target — driving the visual straight
     * from events makes it strobe.
     */
    private fun reconcileFocus() {
        val now = android.os.SystemClock.uptimeMillis()
        // Aim EVERY caption, every frame. They are all standing now, so a
        // caption that is only re-posed when its focus changes would be left
        // edge-on the moment the user moves.
        pips.forEach { p ->
            captions[p.name]?.let { c ->
                runCatching {
                    c.entity.setPose(Pose(p.captionAt, facing(p.captionAt)), Space.ACTIVITY)
                }
            }
        }
        pips.forEach { p ->
            val want = p.pointers.isNotEmpty() || (p.hot && now - p.exitAt < GRACE_MS)
            if (want == p.hot) return@forEach
            p.hot = want
            runCatching {
                // The RING swells and brightens, not the lamp — the lamp already
                // means "this surface is open", and one object cannot carry two
                // states without either becoming ambiguous.
                p.ring.setScale(if (want) HOT_SCALE else 1f)
                p.ring.setAlpha(if (want) 1f else 0.75f)
            }
            // BRIGHTNESS is the focus cue for the caption, since visibility is
            // no longer available to carry it. Every name is legible; the one
            // you are pointing at is the bright one, alongside the ring swelling.
            captions[p.name]?.let { c ->
                runCatching { c.entity.setAlpha(if (want) 1f else CAPTION_DIM) }
            }
            if (want) onFocus?.invoke(p.name)
        }
    }

    /** Drained on the frame loop — nothing opens a surface from an input callback. */
    /**
     * [head] in activity space. Needed because the caption is a PANEL and a
     * panel is a flat, one-sided quad — unlike every other thing in the dock,
     * which is extruded geometry that reads from any angle.
     */
    fun tick(head: Vector3? = null) {
        headAt = head
        reconcileFocus()
        while (true) {
            val p = fired.poll() ?: break
            Log.i(TAG, "[dock] ${p.name}")
            runCatching { p.toggle() }.onFailure { Log.w(TAG, "[dock] ${p.name} failed: $it") }
        }
    }

    fun clear() {
        pips.clear(); fired.clear(); captions.clear()
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private companion object {
        const val TAG = "MeshmoreXR"
        const val REACH = 0.66f
        /** -0.38 at 0.66 m is about -30 degrees: below everything, above the floor. */
        const val DROP = -0.38f
        const val R = 0.020f
        const val PITCH = 0.075f
        const val CAP = 0.011f
        const val DIM = 0.18f
        const val DEBOUNCE_MS = 350L
        const val GRACE_MS = 180L
        /** Enough swell to read at a glance, not so much it looks like a press. */
        const val HOT_SCALE = 1.35f
        /**
         * Sized once for the longest thing a caption ever says: a pip's own
         * name (COMPASS, 7) or a short state string ("OUT x99", 7). Eight cells
         * is 0.063 m against a 0.075 m pip pitch, so the row never collides.
         */
        const val CAPTION_WIDEST = "MMMMMMMM"
        /** Unfocused caption. Legible, but the focused one is plainly brighter. */
        const val CAPTION_DIM = 0.62f

        fun argb(rgb: Int, a: Float) =
            (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)
        /**
         * Hit proxies are meant to be reached for and not seen. 0.02 was chosen
         * so the renderer could not decide to skip a fully transparent entity —
         * but on an ADDITIVE display 2% of a bright accent still emits, and a
         * 4 cm sphere of it beside every pip read as a second, useless ring.
         * 0.004 is the smallest value observed to stay hit-tested.
         */
        const val PROXY_A = 0.004f
    }
}
