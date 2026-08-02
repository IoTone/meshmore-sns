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
        /** Rendered width of [text] at nominal scale, for outward offsetting. */
        val labelW: Float,
    ) {
        var lastFire = 0L
        /** Which pointers are on it. BOTH hands emit rays, hence a set. */
        val pointers = mutableSetOf<String>()
        var hot = false
        var exitAt = 0L
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

    /**
     * Distance scale, recomputed each frame so the menu subtends the SAME ANGLE
     * wherever its subject sits.
     *
     * The geometry is built once at [NOMINAL_D] and scaled thereafter — it
     * cannot be rebuilt per open, because Prims.material suspends and this all
     * has to happen inside an input response.
     *
     * Everything here used to be an absolute size in metres while the thing it
     * opens around is anywhere from arm's length to the far edge of the ring.
     * On a cluster at 2.44 m that came out as 0.61° labels — half the §4.1
     * floor — 1.41° reticles, and spokes 3.75° apart, which is inside the ~5°
     * hand tracking needs to tell two targets apart. Hard to read, hard to aim,
     * hard to hit: three complaints, one cause.
     */
    private var k = 1f

    /** Raised when a spoke takes focus. The host makes the sound. */
    var onFocus: ((String) -> Unit)? = null

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
            // A RETICLE, not a halo. Prims.halo lies in the XZ plane, which is
            // right for the dock — below eye level, so it reads as an ellipse —
            // and wrong here: this menu opens around a node at roughly eye
            // height, where a horizontal ring is edge-on and reads as a line.
            // That is most of why these were hard to see and to aim at.
            //
            // Gapped, because the focus state spins it and a rotationally
            // symmetric ring spinning about its own axis shows nothing at all.
            val ring = MeshEntity.create(
                session, Prims.build(session, Prims.reticle(R, R * 0.20f)),
                listOf(Prims.material(session, theme.alt, 0.85f)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val text = MeshEntity.create(
                session, Prims.build(session, Glyphs.text(item.label, CAP)),
                listOf(Prims.material(session, theme.text, 0.95f)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            // GHOST, and bigger. A near-zero-alpha material is still drawn and
            // still writes depth, so the old proxy was a sphere quietly
            // occluding its own reticle; Prims.ghost discards the fragments
            // outright. The radius goes up because the complaint was that these
            // are hard to acquire, and the thing you point at should be larger
            // than the thing you see — 2.2x is 6.4° across, still inside the
            // 7.4° spoke spacing so two proxies never overlap.
            val proxy = MeshEntity.create(
                session, Prims.build(session, Prims.mote(R * 2.2f, 5, 8)),
                listOf(Prims.ghost(session)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val sp = Spoke(item.id, ring, text, proxy, dx, dy, Glyphs.width(item.label, CAP))
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
            s.pointers.clear(); s.hot = false
            runCatching {
                s.ring.setScale(1f)
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
        reconcileFocus()
        place(head)
    }

    /**
     * FOCUS, reconciled per frame — the same shape as the dock's, and for the
     * same reason: hand tracking drops HOVER_EXIT and re-enters constantly at
     * the edge of a target, so driving the visual straight from events makes it
     * strobe. The grace window is what stops that.
     *
     * There was no focus state here at all before. onInput listened only for
     * UP, so a spoke gave no sign it was under the pointer and the only way to
     * discover whether you were aiming at one was to pinch and find out.
     */
    private fun reconcileFocus() {
        val now = android.os.SystemClock.uptimeMillis()
        spokes.forEach { s ->
            val want = s.pointers.isNotEmpty() || (s.hot && now - s.exitAt < GRACE_MS)
            if (want == s.hot) return@forEach
            s.hot = want
            runCatching {
                s.ring.setAlpha(if (want) 1f else 0.85f)
                s.text.setAlpha(if (want) 1f else 0.75f)
            }
            if (want) onFocus?.invoke(s.id)
        }
    }

    private fun place(head: Vector3?) {
        head?.let {
            val d = kotlin.math.sqrt(
                (it.x - at.x) * (it.x - at.x) + (it.y - at.y) * (it.y - at.y) +
                    (it.z - at.z) * (it.z - at.z),
            )
            if (d > 0.05f) k = d / NOMINAL_D
        }
        val yaw = head?.let {
            val dx = it.x - at.x
            val dz = it.z - at.z
            if (dx * dx + dz * dz < 1e-6f) 0f else atan2(dx, dz)
        } ?: 0f
        val rot = Quaternion.fromEulerAngles(0f, Math.toDegrees(yaw.toDouble()).toFloat(), 0f)
        val rx = cos(yaw); val rz = -sin(yaw)   // the viewer's right, on the ground plane
        // SPIN PHASE from the clock, not from a delta. tick() carries no dt and
        // a frame-counted phase would run at whatever rate the loop happens to
        // manage; wall time makes the rotation the same speed on any frame rate.
        val phase = (android.os.SystemClock.uptimeMillis() % SPIN_MS) /
            SPIN_MS.toFloat() * 360f
        spokes.forEach { s ->
            val ox = s.dx * SPREAD * k
            val oy = s.dy * SPREAD * k
            val p = Vector3(at.x + rx * ox, at.y + oy, at.z + rz * ox)
            // The reticle faces +Z, so the billboard yaw already points its face
            // at the viewer; spinning about its own Z turns it in that plane,
            // which is the axis the gaps are visible around.
            val face = if (s.hot) {
                rot * Quaternion.fromAxisAngle(Vector3(0f, 0f, 1f), phase)
            } else {
                rot
            }
            runCatching {
                s.ring.setScale(k * if (s.hot) HOT_SCALE else 1f)
                s.proxy.setScale(k)
                s.text.setScale(k)
                s.ring.setPose(Pose(p, face), Space.ACTIVITY)
                s.proxy.setPose(Pose(p), Space.ACTIVITY)
                // LABELS GROW OUTWARD. Glyphs centres a run on its anchor, so
                // two labels under two spokes 0.33 m apart collide the moment
                // either is wider than that — and "BEARING" is 0.37 m. Pushing
                // each one out by its own half-width keeps the pair clear
                // whatever the words are, instead of forcing the menu wider to
                // suit the longest one it might ever hold.
                val lx = ox + s.dx * (s.labelW / 2f + LABEL_GAP) * k
                s.text.setPose(
                    Pose(
                        Vector3(at.x + rx * lx, p.y - R * 1.9f * k, at.z + rz * lx), rot,
                    ),
                    Space.ACTIVITY,
                )
            }
        }
    }

    private fun onInput(s: Spoke, ev: InputEvent) {
        if (!open) return
        val key = ev.pointerType.toString()
        when (ev.action) {
            InputEvent.Action.HOVER_ENTER, InputEvent.Action.HOVER_MOVE -> s.pointers += key
            InputEvent.Action.HOVER_EXIT -> {
                s.pointers -= key
                s.exitAt = android.os.SystemClock.uptimeMillis()
            }
            InputEvent.Action.UP -> {
                val now = android.os.SystemClock.uptimeMillis()
                if (now - s.lastFire < DEBOUNCE_MS) return
                s.lastFire = now
                Reach.consumed()
                fired.add(s.id)
            }
            else -> Unit
        }
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
        /**
         * The distance every size below is authored for. Sizes are then scaled
         * by (actual / nominal), so the numbers here can be read as angles: at
         * 2.5 m, 1 mm is 0.023°.
         */
        const val NOMINAL_D = 2.5f
        /** Reticle radius — 2.9° across, matching the icon datum from Marks. */
        const val R = 0.0633f
        /**
         * Spoke offset on each axis. Adjacent spokes are 2x this apart, which
         * works out at 7.4° — comfortably past the ~5° below which hand
         * tracking cannot reliably tell two targets apart.
         */
        const val SPREAD = 0.163f
        /** 1.30°, the same figure the ring labels use. */
        const val CAP = 0.0568f
        /** Clearance between two outward-offset labels, at nominal distance. */
        const val LABEL_GAP = 0.020f
        const val DEBOUNCE_MS = 350L
        /** Focus grace, as the dock uses. Hand tracking drops HOVER_EXIT. */
        const val GRACE_MS = 180L
        /** How much a focused reticle swells. Readable without being a lunge. */
        const val HOT_SCALE = 1.30f
        /** One turn. Slow enough to read as attention rather than as a spinner. */
        const val SPIN_MS = 2600L
    }
}
