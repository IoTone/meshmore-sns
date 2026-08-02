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

/**
 * THE GESTURE CARD — what the hands can say, and how to say it.
 *
 * A gesture vocabulary with no teaching moment is a feature only its author can
 * use (design brief §9.7.1). This is a card you can summon that shows each
 * letter's hand shape and what it does.
 *
 * NOW DEPICTED, NOT DESCRIBED. It used to say "A = FIST, THUMB ALONGSIDE",
 * which is a workaround for not having a picture — and the gesture then failed
 * three times in testing partly because there was nothing to look at. The
 * letters are drawn from the Gallaudet chart (AslGlyphs), as contour only: no
 * skin fill, so the diagram takes the theme's ink and makes no claim about
 * whose hand it is.
 *
 * STILL OWED: the first-run tutorial §9.7.1 asks for, where the app can put the
 * user's OWN tracked hand beside the target shape and say when they match. The
 * skeleton renderer for that already exists (Hands); what is missing is the
 * comparison and the teaching sequence.
 */
class HelpCard(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    private val entities = mutableListOf<Entity>()
    private val lines = mutableListOf<Pair<Entity, Vector3>>()

    var visible: Boolean = false
        private set

    /**
     * One row per command: the letter's DRAWING, which hand, and what it does.
     *
     * The shape column used to be the words "A = FIST, THUMB ALONGSIDE". That is
     * a bad teacher — the gesture failed repeatedly in testing partly because
     * there was nothing to look at — so the letter is drawn now and the prose is
     * gone. A hand shape is a picture; describing it is a workaround for not
     * having one.
     */
    private data class Row(val letter: Char?, val hand: String, val does: String) {
        /**
         * Left-hand rows draw a MIRRORED glyph. The source chart is drawn
         * entirely with the right hand, so an unmirrored icon on a left-hand row
         * depicts the wrong hand — and since the two commands here differ ONLY
         * by which hand makes the shape, that is the one detail the row exists
         * to convey.
         */
        val mirrored: Boolean get() = hand == "LEFT"
    }

    private val rows = listOf(
        Row(null, "GESTURES", ""),
        Row('a', "RIGHT", "COMPASS BAND ON / OFF"),
        Row('a', "LEFT", "LINK BAND ON / OFF"),
        // B was reachable but undocumented, which for a gesture is the same as
        // absent: there is nothing to discover it from. It takes either hand.
        Row('b', "RIGHT", "BACK OUT ONE LEVEL"),
        Row('b', "LEFT", "BACK OUT ONE LEVEL"),
        Row(null, "", "B ONLY ANSWERS WHILE MAGNIFIED"),
        Row(null, "", "HOLD STILL FOR HALF A SECOND"),
        Row(null, "", "PALM AWAY - THE GLASSES SEE THE BACK"),
        Row(null, "", "OR PINCH A DOCK RING INSTEAD"),
    )

    suspend fun build(o: Stage.Origin) {
        clear()
        val root = session.scene.activitySpace
        // Off to the LEFT, at reading distance. Not in the forward arc, which
        // belongs to the mesh, and not where the rack is: two surfaces that
        // occupy the same place cannot be compared, and comparing them is what
        // a user does while learning.
        val base = o.place(-0.75f, READ, 0.05f)

        rows.forEachIndexed { i, r ->
            val y = base.y + (rows.size / 2f - i) * LINE
            r.letter?.let { ch ->
                AslIcon.create(
                    session, context, ch, ICON, argb(theme.accent, 0.95f), r.mirrored,
                )?.let { p ->
                    p.parent = root
                    p.setPose(Pose(Vector3(base.x - ICON * 0.9f, y, base.z)), Space.ACTIVITY)
                    p.setEnabled(false)
                    entities += p
                    lines += p as Entity to Vector3(base.x - ICON * 0.9f, y, base.z)
                }
            }
            // LEFT-ALIGNED, by measuring. Tier S centres a run on its anchor,
            // so a column addressed by its centre moves as the words change
            // length — and the longest row then reaches back across whatever is
            // to its left. That is what put "BACK OUT ONE LEVEL" through the
            // word "RIGHT". A table wants its columns to start in the same
            // place, which means anchoring the LEFT edge and letting the run
            // end where it ends.
            if (r.hand.isNotEmpty()) {
                line(root, r.hand, at(base, HAND_COL, r.hand, y), theme.text)
            }
            if (r.does.isNotEmpty()) {
                line(root, r.does, at(base, COL, r.does, y), theme.alt)
            }
        }
        setVisible(false)
        Log.i(TAG, "[help] card built, ${lines.size} lines")
    }

    /** Where a run must be anchored for its LEFT edge to sit at [left]. */
    private fun at(base: Vector3, left: Float, text: String, y: Float): Vector3 =
        Vector3(base.x + left + Glyphs.width(text, CAP) / 2f, y, base.z)

    private suspend fun line(root: Entity, text: String, at: Vector3, rgb: Int) {
        // Tier S: short, Latin, fixed. Exactly what the stroke font is for, and
        // it keeps the card in the same visual register as the rest of the app
        // rather than looking like documentation pasted into the room.
        MeshEntity.create(
            session, Prims.build(session, Glyphs.text(text, CAP)),
            listOf(Prims.material(session, rgb, 0.9f)),
        ).also {
            it.parent = root
            it.setPose(Pose(at), Space.ACTIVITY)
            it.setEnabled(false)
            entities += it
            lines += it as Entity to at
        }
    }

    fun setVisible(v: Boolean) {
        visible = v
        entities.forEach { runCatching { it.setEnabled(v) } }
    }

    /** Keep it readable as the user walks around it. */
    fun tick(head: Vector3?) {
        if (!visible || head == null) return
        lines.forEach { (e, at) ->
            val dx = head.x - at.x
            val dz = head.z - at.z
            if (dx * dx + dz * dz < 1e-6f) return@forEach
            runCatching {
                e.setPose(
                    Pose(at, Quaternion.fromEulerAngles(
                        0f, Math.toDegrees(atan2(dx, dz).toDouble()).toFloat(), 0f)),
                    Space.ACTIVITY,
                )
            }
        }
    }

    fun clear() {
        lines.clear()
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"
        const val READ = 1.5f
        const val LINE = 0.105f
        /** Left edge of the hand column, and of the description column. */
        const val HAND_COL = 0.06f
        const val COL = 0.30f
        const val CAP = 0.034f
        /** The hand diagram, square. Big enough that finger separations read. */
        const val ICON = 0.085f
    }
}
