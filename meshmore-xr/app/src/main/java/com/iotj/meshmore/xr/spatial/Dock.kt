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
class Dock(private val session: Session, private val theme: Horizon.Palette) {

    private val entities = mutableListOf<Entity>()
    private val pips = mutableListOf<Pip>()
    private val fired = java.util.concurrent.ConcurrentLinkedQueue<Pip>()

    private inner class Pip(
        val name: String,
        val lamp: MeshEntity,
        val toggle: () -> Unit,
    ) {
        var lastFire = 0L
        var lit = false
    }

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

            MeshEntity.create(
                session, Prims.build(session, Glyphs.text(name, CAP)),
                listOf(Prims.material(session, theme.alt, 0.85f)),
            ).also {
                it.parent = root
                it.setPose(Pose(Vector3(at.x, at.y - R * 2.2f, at.z)), Space.ACTIVITY)
                entities += it
            }

            val pip = Pip(name, lamp, act)
            pips += pip

            // Hit proxy, same reasoning as everywhere else: the thing you point
            // at is deliberately bigger than the thing you see, and alpha 0.02
            // rather than 0 so the renderer cannot decide to skip it.
            MeshEntity.create(
                session, Prims.build(session, Prims.mote(R * 2.0f, 5, 8)),
                listOf(Prims.material(session, theme.accent, PROXY_A)),
            ).also {
                it.parent = root; it.setPose(Pose(at), Space.ACTIVITY)
                it.setAlpha(PROXY_A); entities += it
                runCatching {
                    it.addComponent(InteractableComponent.create(session) { ev -> onInput(pip, ev) })
                }.onFailure { e -> Log.w(TAG, "[dock] no input on $name: $e") }
            }
        }
        Log.i(TAG, "[dock] ${pips.size} pip(s) up")
    }

    /** Light the pip for whichever surface is open; dark for the rest. */
    fun setLit(name: String, lit: Boolean) {
        pips.firstOrNull { it.name == name }?.let {
            it.lit = lit
            it.lamp.setAlpha(if (lit) 1f else DIM)
        }
    }

    private fun onInput(p: Pip, ev: InputEvent) {
        if (ev.action != InputEvent.Action.UP) return
        val now = android.os.SystemClock.uptimeMillis()
        if (now - p.lastFire < DEBOUNCE_MS) return
        p.lastFire = now
        fired.add(p)
    }

    /** Drained on the frame loop — nothing opens a surface from an input callback. */
    fun tick() {
        while (true) {
            val p = fired.poll() ?: break
            Log.i(TAG, "[dock] ${p.name}")
            runCatching { p.toggle() }.onFailure { Log.w(TAG, "[dock] ${p.name} failed: $it") }
        }
    }

    fun clear() {
        pips.clear(); fired.clear()
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
