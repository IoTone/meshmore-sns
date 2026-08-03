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
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * S3 · NODE FOCUS — one peer, answered.
 *
 * Until now, pinching a node emitted a pulse ring and nothing else. Paradigm
 * rule 3 (§2.1) says ONE FOCUS AT A TIME and there was nothing to focus; the two
 * questions an operator actually has — *who is that* and *can I reach them* —
 * could not be answered by pointing at the thing they are about.
 *
 * TWO PARTS, and the brief is explicit that the second is the important one:
 *
 *   - The CARD: callsign, range, bearing, path and freshness. Reference.
 *   - The SPUR: a tube from where you stand out along the node's TRUE bearing.
 *     "The panel is reference; the spur is the actual answer to *where are
 *     they?*" (§S3)
 *
 * THE SPUR'S LENGTH IS NOT A CLAIM. Its BEARING is true — that is a real
 * compass direction to a real radio. Its length is the ring's compressed
 * representation of range, because the ring is logarithmic out to MAX_KM and a
 * spur drawn at true scale would leave the room. The card carries the honest
 * number in words; the spur carries the direction you would walk.
 *
 * WHY IT IS NOT A PANEL, since the same challenge applies here as to TextRun:
 * transparent ground, no corner radius, world-anchored at a place rather than
 * pinned to the viewport, one run per line and nothing that scrolls. It is
 * built from the same tier R runs the ring labels use.
 */
class Focus(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    private val entities = mutableListOf<Entity>()
    private var name: TextRun.Run? = null
    private var range: TextRun.Run? = null
    private var path: TextRun.Run? = null
    private var spur: MeshEntity? = null

    /** Where the card sits, world-anchored. Billboarded about Y only. */
    private var cardAt: Vector3? = null

    var open: Boolean = false
        private set

    /** Which node is up. Used to make a second pinch on the same one close it. */
    var subject: String? = null
        private set

    /**
     * Built once, hidden. Same reasoning as the radial menu: the lines are
     * reusable runs so that showing a node is a setText and a pose rather than
     * three panels created while the user waits.
     */
    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        name = run(root, WIDEST_NAME, NAME_CAP, theme.text, "focus-name")
        range = run(root, WIDEST_RANGE, READ_CAP, theme.accent, "focus-range")
        path = run(root, WIDEST_PATH, READ_CAP, theme.alt, "focus-path")
        Log.i(TAG, "[focus] card built")
    }

    private suspend fun run(
        root: Entity, widest: String, cap: Float, rgb: Int, tag: String,
    ): TextRun.Run? = TextRun.reusable(session, context, widest, cap, argb(rgb, 0.95f), tag)
        ?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }

    /**
     * Open on [node], which sits at [at] in activity space. [head] is where the
     * viewer is; the card is placed between the two and then left there.
     *
     * Suspend because the spur is real geometry with per-node endpoints, and a
     * uniform scale cannot stretch a tube without also fattening it. Building a
     * mesh here is the same thing `pulse` already does on every packet, and
     * unlike the radial menu this runs on the frame loop rather than inside an
     * input callback.
     */
    suspend fun showFor(node: Horizon.Node, at: Vector3, head: Vector3) {
        subject = node.name
        open = true

        // Horizontal direction from the viewer to the node. Flattened, so the
        // card stands upright rather than tipping to match a node's elevation.
        var dx = at.x - head.x
        var dz = at.z - head.z
        val flat = sqrt(dx * dx + dz * dz).let { if (it > 1e-4f) it else 1f }
        dx /= flat; dz /= flat

        val c = Vector3(head.x + dx * CARD_D, head.y - CARD_DROP, head.z + dz * CARD_D)
        cardAt = c

        // TIER R, so the REAL name — case, kana, emoji and all. Callsign.render
        // uppercases because the stroke font has no lowercase; running a tier R
        // line through it shouts a name the face could have set properly.
        name?.setText(TypeTier.clip(node.name, 22))
        // THE RANGE IS LOGARITHMIC AND MUST BE INVERTED, not scaled. MeshNodes
        // says so in as many words: a linear read of a log band puts a node at
        // 4 km when it is at 25, and a distance on a card is a claim someone
        // might act on.
        range?.setText(
            "%s  %s %03d".format(
                MeshNodes.km(node.dist.toDouble()),
                MeshNodes.compass(node.bearingRad),
                ((Math.toDegrees(node.bearingRad.toDouble()) % 360.0 + 360.0) % 360.0).toInt(),
            ),
        )
        path?.setText(pathOf(node))

        place()
        listOfNotNull(name, range, path).forEach { runCatching { it.entity.setEnabled(true) } }
        buildSpur(head, at, dx, dz)
        Log.i(TAG, "[focus] ${node.name} ${MeshNodes.km(node.dist.toDouble())} " +
            "${MeshNodes.compass(node.bearingRad)} hops=${node.hops}")
    }

    /**
     * Path and freshness, in words rather than a number nobody can calibrate.
     *
     * `hops` arrives as 255/256 when the radio has not resolved a route, which
     * is not "255 hops" and must not print as one.
     */
    private fun pathOf(n: Horizon.Node): String {
        val hops = when {
            n.hops <= 0 || n.hops >= 250 -> "PATH UNKNOWN"
            n.hops == 1 -> "DIRECT"
            else -> "%d HOPS".format(n.hops)
        }
        val fresh = if (n.age < 0.34f) "LIVE" else "STALE"
        val fix = if (n.located) "" else "  EST"
        return "$hops  $fresh$fix"
    }

    /**
     * The tube from where you stand to where they are — ALONG THE FLOOR, then
     * up.
     *
     * The first version ran straight from the eye to the mote, which is
     * degenerate by construction: at the moment you select a node you are
     * looking at it, so the spur lies along your own line of sight and
     * foreshortens to a few pixels. It only became visible by turning away from
     * the thing it was pointing at.
     *
     * On the floor it reads in perspective from the one place you are certain
     * to be standing, which is also where the brief wants it — "painted on the
     * real world", the direction you would walk. The riser at the far end joins
     * the ground answer to the mote so the two are visibly about the same node.
     */
    private suspend fun buildSpur(head: Vector3, at: Vector3, dx: Float, dz: Float) {
        val y = head.y - FLOOR_DROP
        val a = Vector3(head.x + dx * SPUR_NEAR, y, head.z + dz * SPUR_NEAR)
        val g = Vector3(at.x, y, at.z)
        // DASHED, not a continuous tube. A solid bar from your feet to the
        // horizon is a great deal of emitted light on a display that can only
        // add it, and at the near end it subtends enough angle to loom over the
        // dock. Dashes cost roughly half the light, and a repeating mark
        // pointing away from you reads as direction in a way a bar does not.
        val f = Prims.Facets()
        for (i in 0 until DASHES) {
            val t0 = i.toFloat() / DASHES
            val t1 = t0 + (1f / DASHES) * DASH_DUTY
            f.addTranslated(
                Prims.spur(
                    a.x + (g.x - a.x) * t0, y, a.z + (g.z - a.z) * t0,
                    a.x + (g.x - a.x) * t1, y, a.z + (g.z - a.z) * t1,
                    SPUR_R,
                ),
                0f, 0f, 0f,
            )
        }
        // The riser stays continuous: it is short, and a dashed one would read
        // as a fifth dash rather than as the join.
        f.addTranslated(
            Prims.spur(g.x, g.y, g.z, at.x, at.y, at.z, SPUR_R * 0.7f), 0f, 0f, 0f,
        )
        // BUILD, SWAP, THEN DISPOSE. Prims.build suspends and tick() poses this
        // field every frame, so disposing first leaves a window in which the
        // field names a dead entity — the crash HereMark and Hud both hit.
        val fresh = runCatching {
            MeshEntity.create(
                session, Prims.build(session, f),
                listOf(Prims.material(session, theme.accent, 0.8f)),
            ).also { it.parent = session.scene.activitySpace }
        }.getOrNull()
        val doomed: MeshEntity? = spur
        spur = fresh
        doomed?.let { entities.remove(it as Entity) }
        fresh?.let { entities += it as Entity }
        doomed?.let { runCatching { it.parent = null }; runCatching { it.dispose() } }
    }

    fun hide() {
        if (!open) return
        open = false
        subject = null
        cardAt = null
        listOfNotNull(name, range, path).forEach { runCatching { it.entity.setEnabled(false) } }
        spur?.let { runCatching { it.setEnabled(false) } }
        Log.i(TAG, "[focus] closed")
    }

    /** Billboard about Y. The card is at eye level, so yaw is the whole of it. */
    fun tick(head: Vector3?) {
        if (!open || head == null) return
        val c = cardAt ?: return
        val dx = head.x - c.x
        val dz = head.z - c.z
        if (dx * dx + dz * dz < 1e-6f) return
        val yaw = Math.toDegrees(atan2(dx, dz).toDouble()).toFloat()
        place(Quaternion.fromEulerAngles(0f, yaw, 0f))
    }

    private fun place(rot: Quaternion = Quaternion.fromEulerAngles(0f, 0f, 0f)) {
        val c = cardAt ?: return
        var y = c.y
        listOf(name to NAME_CAP, range to READ_CAP, path to READ_CAP).forEach { (r, cap) ->
            r ?: return@forEach
            runCatching { r.entity.setPose(Pose(Vector3(c.x, y, c.z), rot), Space.ACTIVITY) }
            y -= cap * LINE
        }
    }

    fun clear() {
        name = null; range = null; path = null; spur = null
        open = false; subject = null; cardAt = null
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"
        /** §S3: "exactly one FOCUS panel at 1.2 m along gaze". */
        const val CARD_D = 1.2f
        /** Below eye level, so the card sits under the world window, not in it. */
        const val CARD_DROP = 0.18f
        /**
         * 1.62° at CARD_D. Derived from §4.1's 1.2° floor with the margin the
         * ring labels use, not chosen by eye — the mistake every fixed-distance
         * surface in this app had made until 2026-08-02.
         */
        const val NAME_CAP = 0.034f
        /** 1.34° at CARD_D. */
        const val READ_CAP = 0.028f
        /** Line pitch, in multiples of the line's own cap height. */
        const val LINE = 1.9f
        /** How close to the viewer the spur starts. Past their own hands. */
        const val SPUR_NEAR = 0.70f
        /** Section radius. Under ~1 cm a tube is invisible in bright passthrough. */
        const val SPUR_R = 0.008f
        /** Dashes along the floor, and how much of each step is drawn. */
        const val DASHES = 9
        const val DASH_DUTY = 0.55f
        /** Floor, below the eye. The figure HereMark already stands on. */
        const val FLOOR_DROP = 0.88f

        const val WIDEST_NAME = "MMMMMMMMMMMMMMMMMMMMMM"
        const val WIDEST_RANGE = "9999KM  NNW 359"
        const val WIDEST_PATH = "PATH UNKNOWN  STALE  EST"
    }
}
