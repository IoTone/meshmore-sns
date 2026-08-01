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
 * use (design brief §9.7.1). This is the smallest honest version of that: a card
 * you can summon that lists the letters and what they do, with the hand shape
 * described in words because a stroke font cannot draw a hand and a photograph
 * would be a panel.
 *
 * DESCRIBED, NOT DEPICTED, and that is a real limitation rather than a
 * preference — "fist, thumb alongside" is a worse teacher than seeing the shape.
 * The proper answer is the first-run tutorial §9.7.1 owes, where the app can
 * show the user their OWN hand next to the target shape and tell them when they
 * match. Until that exists this card is the difference between a discoverable
 * feature and a secret.
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

    /** Left column is the gesture, right is what it does. */
    private val rows = listOf(
        "GESTURES" to "",
        "" to "",
        "RIGHT HAND  A" to "COMPASS BAND ON/OFF",
        "LEFT HAND   A" to "LINK BAND ON/OFF",
        "" to "",
        "A = FIST, THUMB ALONGSIDE" to "",
        "HOLD IT STILL FOR HALF A SECOND" to "",
        "" to "",
        "PINCH A DOCK RING" to "SAME, IF HANDS ARE UNSEEN",
    )

    suspend fun build(o: Stage.Origin) {
        clear()
        val root = session.scene.activitySpace
        // Off to the LEFT, at reading distance. Not in the forward arc, which
        // belongs to the mesh, and not where the rack is: two surfaces that
        // occupy the same place cannot be compared, and comparing them is what
        // a user does while learning.
        val base = o.place(-0.75f, READ, 0.05f)

        rows.forEachIndexed { i, (left, right) ->
            val y = base.y + (rows.size / 2f - i) * LINE
            if (left.isNotEmpty()) line(root, left, Vector3(base.x, y, base.z), theme.text)
            if (right.isNotEmpty()) {
                line(root, right, Vector3(base.x + COL, y, base.z), theme.alt)
            }
        }
        setVisible(false)
        Log.i(TAG, "[help] card built, ${lines.size} lines")
    }

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

    private companion object {
        const val TAG = "MeshmoreXR"
        const val READ = 1.5f
        const val LINE = 0.075f
        const val COL = 0.42f
        const val CAP = 0.030f
    }
}
