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
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/**
 * A RADIAL MENU that blooms around whatever you pinched.
 *
 * A cluster mote says "+120" and that is all it can say. This is where you ask
 * it what it means: pinch it and four spokes open around it, each a pip you can
 * pinch in turn.
 *
 * RADIAL RATHER THAN A LIST, and not for style. A list needs somewhere to hang —
 * a top-left corner, a reading direction, a surface to sit on — and there is no
 * such place on a ring that wraps around the body. A radial menu has an origin
 * instead of a corner: it is anchored to the thing it acts on, so the object and
 * its options are never separated and there is nothing to scroll.
 *
 * BUILT ONCE, MOVED THEREAFTER. Geometry cannot be created in response to input
 * — Prims.material is a suspend call and an input callback is not a coroutine —
 * and building meshes mid-gesture hitches the frame exactly when the user is
 * watching for a response. So the spokes exist from startup, hidden, and
 * opening the menu is a pose and an enable.
 *
 * ON THE DIAGONALS, deliberately. The ring's own callsigns sit directly below
 * their motes and the range bands run horizontally through them; a spoke at
 * north, south, east or west would land on one or the other. The diagonals are
 * the only directions around a mote that are reliably empty.
 */
class RadialMenu(
    private val session: Session,
    private val theme: Horizon.Palette,
) {

    /** One spoke. [label] is what it says; [id] is what the caller switches on. */
    class Item(val id: String, val label: String)

    private class Spoke(
        val id: String,
        val ring: MeshEntity,
        val text: MeshEntity,
        val proxy: MeshEntity,
        val dx: Float,
        val dy: Float,
    ) {
        var lastFire = 0L
    }

    private val spokes = mutableListOf<Spoke>()
    private val entities = mutableListOf<Entity>()
    private val fired = java.util.concurrent.ConcurrentLinkedQueue<String>()

    var open: Boolean = false
        private set

    /** What the menu is currently acting on. Null when closed. */
    var subject: Any? = null
        private set

    private var at = Vector3(0f, 0f, 0f)

    suspend fun build(items: List<Item>) {
        clear()
        val root = session.scene.activitySpace
        // Four diagonals. More than four and the spokes crowd; fewer and the
        // menu stops looking like a menu.
        val dirs = listOf(
            -0.7071f to 0.7071f, 0.7071f to 0.7071f,
            -0.7071f to -0.7071f, 0.7071f to -0.7071f,
        )
        items.forEachIndexed { i, item ->
            val (dx, dy) = dirs.getOrElse(i) { 0f to 0f }
            val ring = MeshEntity.create(
                session, Prims.build(session, Prims.halo(R, R * 0.24f)),
                listOf(Prims.material(session, theme.alt, 0.85f)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val text = MeshEntity.create(
                session, Prims.build(session, Glyphs.text(item.label, CAP)),
                listOf(Prims.material(session, theme.text, 0.95f)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val proxy = MeshEntity.create(
                session, Prims.build(session, Prims.mote(R * 2.1f, 5, 8)),
                listOf(Prims.material(session, theme.accent, PROXY_A)),
            ).also {
                it.parent = root; it.setAlpha(PROXY_A); it.setEnabled(false); entities += it
            }
            val sp = Spoke(item.id, ring, text, proxy, dx, dy)
            spokes += sp
            runCatching {
                proxy.addComponent(InteractableComponent.create(session) { ev -> onInput(sp, ev) })
            }.onFailure { Log.w(TAG, "[menu] no input on ${item.id}: $it") }
        }
        Log.i(TAG, "[menu] ${spokes.size} spokes")
    }

    /** Open around [pos], acting on [on]. */
    fun showAt(pos: Vector3, on: Any?) {
        at = pos
        subject = on
        open = true
        spokes.forEach { s ->
            runCatching {
                s.ring.setEnabled(true); s.text.setEnabled(true); s.proxy.setEnabled(true)
            }
        }
        place(null)
        Log.i(TAG, "[menu] open on $on")
    }

    fun hide() {
        if (!open) return
        open = false
        subject = null
        fired.clear()
        spokes.forEach { s ->
            runCatching {
                s.ring.setEnabled(false); s.text.setEnabled(false); s.proxy.setEnabled(false)
            }
        }
        Log.i(TAG, "[menu] closed")
    }

    /**
     * Place and billboard. The spokes offset in the VIEWER'S frame rather than
     * in world axes, so the menu opens as a square around the mote from wherever
     * it is looked at — offsetting in world X and Y would make it a line seen
     * from the side.
     */
    fun tick(head: Vector3?) {
        if (!open) return
        place(head)
    }

    private fun place(head: Vector3?) {
        val yaw = head?.let {
            val dx = it.x - at.x
            val dz = it.z - at.z
            if (dx * dx + dz * dz < 1e-6f) 0f else atan2(dx, dz)
        } ?: 0f
        val rot = Quaternion.fromEulerAngles(0f, Math.toDegrees(yaw.toDouble()).toFloat(), 0f)
        val rx = cos(yaw); val rz = -sin(yaw)   // the viewer's right, on the ground plane
        spokes.forEach { s ->
            val ox = s.dx * SPREAD
            val oy = s.dy * SPREAD
            val p = Vector3(at.x + rx * ox, at.y + oy, at.z + rz * ox)
            runCatching {
                s.ring.setPose(Pose(p, rot), Space.ACTIVITY)
                s.proxy.setPose(Pose(p), Space.ACTIVITY)
                s.text.setPose(
                    Pose(Vector3(p.x, p.y - R * 1.9f, p.z), rot), Space.ACTIVITY,
                )
            }
        }
    }

    private fun onInput(s: Spoke, ev: InputEvent) {
        if (!open || ev.action != InputEvent.Action.UP) return
        val now = android.os.SystemClock.uptimeMillis()
        if (now - s.lastFire < DEBOUNCE_MS) return
        s.lastFire = now
        Reach.consumed()
        fired.add(s.id)
    }

    /** Drained on the frame loop. Returns the chosen id once, or null. */
    fun poll(): String? = fired.poll()

    fun clear() {
        spokes.clear(); fired.clear(); open = false; subject = null
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private companion object {
        const val TAG = "MeshmoreXR"
        const val R = 0.030f
        /** How far a spoke sits from the mote. Clear of a 1.6 deg mote and its label. */
        const val SPREAD = 0.16f
        const val CAP = 0.026f
        const val DEBOUNCE_MS = 350L
        const val PROXY_A = 0.004f
    }
}
