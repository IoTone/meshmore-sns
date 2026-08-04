// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.content.Context
import android.util.Log
import androidx.xr.arcore.HandJointType
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Quaternion
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * THE REEL — the last dozen messages, on the chat palm.
 *
 * §S4 splits reading into two jobs and puts them in two places. *Triage*
 * happens on the hand: "turn the chat palm up and the REEL appears — an oval
 * ring buffer of the last ~12 messages, rotated with thumb-along-index, ~5
 * legible across the front arc." *Reading* happens in FOCUS, which is the
 * thread corridor.
 *
 * A RING BUFFER THAT LOOKS LIKE ONE. §S4: "the reel is a view of the last N,
 * never the archive — the shape is a ring buffer and it says so honestly."
 * That is why it is a closed oval rather than a list: a list implies a top and
 * an end and invites scrolling toward an archive that does not exist here.
 * Older hands off to the thread.
 *
 * FIVE LEGIBLE, TWELVE PRESENT. The slots on the far arc carry a mote and no
 * words, because at a palm's distance twelve legible lines cannot fit and
 * pretending otherwise means twelve illegible ones. The count is visible; the
 * words arrive as a slot comes round the front.
 *
 * HYSTERESIS IS MANDATORY, and §5 says why in as many words: reveal above 0.6,
 * hide below 0.45, because a single threshold makes the surface strobe as the
 * wrist hovers at the boundary and "flicker on a hand-anchored element is the
 * most nauseating failure mode available in XR". The gap is not tuning slack;
 * it is the feature.
 *
 * OWED: rotation by thumb-along-index, and the per-message CROWN. The reel
 * currently shows the newest at the front and does not turn.
 */
class Reel(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    /** One message, already formatted. */
    class Slot(val who: String, val words: String)

    private class Cell(val run: TextRun.Run, val mote: MeshEntity)

    private val cells = mutableListOf<Cell>()
    private val entities = mutableListOf<Entity>()
    private var slots: List<Slot> = emptyList()

    /** Revealed, with the hysteresis of §5 rather than a single threshold. */
    var open: Boolean = false
        private set

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        repeat(SLOTS) {
            val run = TextRun.reusable(
                session, context, WIDEST, CAP, argb(theme.text, 0.95f), "reel",
            ) ?: return@repeat
            run.entity.parent = root
            run.entity.setEnabled(false)
            entities += run.entity
            val mote = MeshEntity.create(
                session, Prims.build(session, Prims.mote(MOTE, 4, 6)),
                listOf(Prims.material(session, theme.alt, 0.85f)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            cells += Cell(run, mote)
        }
        Log.i(TAG, "[reel] $SLOTS slots, $FRONT legible")
    }

    fun setMessages(list: List<Slot>) {
        slots = list.take(SLOTS)
    }

    /**
     * [joints] are the CHAT hand's; [palmDot] how squarely its palm faces the
     * wearer; [head] where they are.
     */
    fun tick(
        joints: Map<HandJointType, Pose>?,
        palmDot: Float?,
        head: Vector3?,
        nowMs: Long,
    ) {
        val was = open
        open = when {
            joints.isNullOrEmpty() || palmDot == null || head == null -> false
            palmDot > REVEAL -> true
            palmDot < HIDE -> false
            else -> open          // the gap: neither reveal nor hide
        }
        if (was != open) Log.i(TAG, "[reel] ${if (open) "revealed" else "hidden"}")
        if (!open) {
            cells.forEach {
                runCatching { it.run.entity.setEnabled(false); it.mote.setEnabled(false) }
            }
            return
        }

        // Captured non-null: the reveal test above already required them, but
        // `open` is a var so the compiler cannot carry that through.
        val h = head ?: return
        val js = joints ?: return
        val ps = session.scene.perceptionSpace
        fun act(t: HandJointType): Vector3? = runCatching {
            ps.getScenePoseFromPerceptionPose(js[t] ?: return null)
                .poseInActivitySpace.translation
        }.getOrNull()
        val w = act(HandJointType.WRIST) ?: return
        val m = act(HandJointType.MIDDLE_METACARPAL) ?: return
        val ix = act(HandJointType.INDEX_PROXIMAL) ?: return
        val li = act(HandJointType.LITTLE_PROXIMAL) ?: return

        // The palm's own frame: along the hand, across it, and the normal.
        var ax = m.x - w.x; var ay = m.y - w.y; var az = m.z - w.z
        val al = sqrt(ax * ax + ay * ay + az * az).let { if (it > 1e-5f) it else return }
        ax /= al; ay /= al; az /= al
        var bx = li.x - ix.x; var by = li.y - ix.y; var bz = li.z - ix.z
        val bl = sqrt(bx * bx + by * by + bz * bz).let { if (it > 1e-5f) it else return }
        bx /= bl; by /= bl; bz /= bl
        // Normal = along x across, so the oval lies flat over the palm and
        // stands off it rather than intersecting the hand.
        val nx = ay * bz - az * by
        val ny = az * bx - ax * bz
        val nz = ax * by - ay * bx
        val nl = sqrt(nx * nx + ny * ny + nz * nz).let { if (it > 1e-5f) it else return }
        val ux = nx / nl; val uy = ny / nl; val uz = nz / nl
        // Toward the wearer, so the oval floats above the palm and not through
        // the back of the hand. The sign is settled by which way the palm is
        // facing rather than derived — this project has lost four arguments to
        // handedness signs written in comments.
        val toHead = ((h.x - w.x) * ux + (h.y - w.y) * uy + (h.z - w.z) * uz)
        val s = if (toHead >= 0f) 1f else -1f
        val cx = w.x + ax * (ALONG) + ux * s * STANDOFF
        val cy = w.y + ay * (ALONG) + uy * s * STANDOFF
        val cz = w.z + az * (ALONG) + uz * s * STANDOFF

        cells.forEachIndexed { i, c ->
            val msg = slots.getOrNull(i)
            // Slot 0 sits at the FRONT — nearest the wearer along the hand —
            // and the rest wrap round. Newest first, which is what triage wants.
            val t = (i.toFloat() / SLOTS) * TAU
            val ox = kotlin.math.sin(t) * RX
            val oy = -kotlin.math.cos(t) * RY
            val at = Vector3(
                cx + bx * ox + ax * oy,
                cy + by * ox + ay * oy,
                cz + bz * ox + az * oy,
            )
            val legible = msg != null && i < FRONT
            runCatching {
                c.mote.setEnabled(msg != null && !legible)
                c.mote.setPose(Pose(at), Space.ACTIVITY)
                c.run.entity.setEnabled(legible)
                if (!legible) return@runCatching
                c.run.setText("${msg!!.who}  ${msg.words}")
                c.run.entity.setPose(Pose(at, facing(at, h)), Space.ACTIVITY)
            }
        }
    }

    private fun facing(at: Vector3, head: Vector3): Quaternion {
        val dx = head.x - at.x
        val dz = head.z - at.z
        if (dx * dx + dz * dz < 1e-6f) return Quaternion.fromEulerAngles(0f, 0f, 0f)
        return Quaternion.fromEulerAngles(
            0f, Math.toDegrees(atan2(dx, dz).toDouble()).toFloat(), 0f,
        )
    }

    fun clear() {
        cells.clear(); slots = emptyList(); open = false
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"
        const val TAU = (2.0 * Math.PI).toFloat()
        /** "the last ~12 messages" (§S4). */
        const val SLOTS = 12
        /** "~5 legible across the front arc" (§S4). */
        const val FRONT = 5
        /** The oval, in the palm's plane. Wider than tall, hence oval. */
        const val RX = 0.085f
        const val RY = 0.055f
        /** How far up the hand its centre sits, from the wrist. */
        const val ALONG = 0.06f
        /** And how far off the palm, so it floats rather than intersects. */
        const val STANDOFF = 0.06f
        /** Small: a slot you cannot read still has to be countable. */
        const val MOTE = 0.005f
        /**
         * 1.2° at the ~0.45 m a raised palm sits from the eye. This is the one
         * surface where the floor genuinely binds — a hand is close, and close
         * means small in metres for the same angle.
         */
        const val CAP = 0.0094f
        /** §5's thresholds, verbatim. The gap between them is the feature. */
        const val REVEAL = 0.6f
        const val HIDE = 0.45f
        const val WIDEST = "MMMMMMMM MMMMMMMMMMMM"
    }
}
