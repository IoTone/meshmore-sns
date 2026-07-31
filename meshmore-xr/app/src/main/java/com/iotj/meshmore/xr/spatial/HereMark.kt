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

/**
 * WHERE "HERE" COMES FROM — the one setting you can change from inside.
 *
 * Every bearing on the horizon is measured from a single origin, and that
 * origin has three possible sources: the radio's own GPS, the headset's, or a
 * position stated on the command line. Which one is live decides whether the
 * mesh appears around you or does not appear at all, so it is the setting most
 * worth being able to see and change while wearing the glasses -- and until now
 * it could only be flipped with `--ez devloc true` from a laptop.
 *
 * IT IS NOT A SETTINGS PANEL. It is a marker on the floor in front of you that
 * says where the origin is coming from, and pinching it changes the answer.
 * The design brief's back-of-hand menu is still the intended home for controls
 * like this one; the interaction here -- read the state, pinch, watch the world
 * rebuild -- is what will move there, not the marker itself.
 *
 * Placed LOW and FORWARD, at about -34 degrees: clear of the world window
 * (+/-10) and of both microhud bands, so it never competes with the mesh, and
 * you have to look down at it deliberately. A setting you can trip over while
 * reading the horizon is worse than one you have to go and find.
 */
class HereMark(private val session: Session, private val theme: Horizon.Palette) {

    private val entities = mutableListOf<Entity>()
    private var label: MeshEntity? = null
    private var at = Vector3(0f, 0f, 0f)
    private var lastSelect = 0L
    private var lastText: String? = null

    /** Raised on the input thread; drained by the frame loop, as Horizon does. */
    private val pinched = java.util.concurrent.atomic.AtomicBoolean(false)

    /**
     * Build the marker [ahead] metres in front of the launch facing, [drop]
     * metres below eye level.
     */
    suspend fun build(o: Stage.Origin, text: String) {
        clear()
        val root = session.scene.activitySpace
        at = o.place(0f, AHEAD, -DROP)

        // A RING, not a mote. Everything spherical in this scene is a node; a
        // control that looked like a node would read as one more radio sitting
        // improbably close, and pinching it would look like it selected a peer.
        val ring = Prims.build(session, Prims.halo(R, R * 0.16f))
        val mat = Prims.material(session, theme.alt, 0.7f)
        MeshEntity.create(session, ring, listOf(mat)).also {
            it.parent = root
            it.setPose(Pose(at), Space.ACTIVITY)
            entities += it
        }

        setText(text)

        // Hit proxy, same reasoning as Horizon's: the thing you point at is
        // deliberately larger than the thing you see, and alpha 0.02 rather
        // than 0 so the renderer cannot decide to skip it.
        val proxy = MeshEntity.create(
            session, Prims.build(session, Prims.mote(R * 1.9f, 5, 8)), listOf(mat),
        ).also {
            it.parent = root
            it.setPose(Pose(at), Space.ACTIVITY)
            it.setAlpha(0.02f)
            entities += it
        }
        runCatching {
            proxy.addComponent(InteractableComponent.create(session) { ev -> onInput(ev) })
        }.onFailure { Log.w(TAG, "[here] no input on marker: $it") }
        Log.i(TAG, "[here] marker up: \"$text\"")
    }

    /** Rebuild the caption. Cheap enough: it changes on selection, not per frame. */
    suspend fun setText(text: String) {
        if (text == lastText) return
        lastText = text
        runCatching { label?.let { entities.remove(it); (it as Entity).dispose() } }
        label = MeshEntity.create(
            session, Prims.build(session, Glyphs.text(text, CAP)),
            listOf(Prims.material(session, theme.text, 0.85f)),
        ).also {
            it.parent = session.scene.activitySpace
            it.setPose(Pose(Vector3(at.x, at.y - R * 2.4f - CAP, at.z)), Space.ACTIVITY)
            entities += it
        }
    }

    /** Keep the caption readable as the user moves around it. */
    fun faceViewer(head: Vector3) {
        val l = label ?: return
        val dx = head.x - at.x
        val dz = head.z - at.z
        if (dx * dx + dz * dz < 1e-6f) return
        val yaw = Math.toDegrees(atan2(dx, dz).toDouble()).toFloat()
        l.setPose(
            Pose(
                Vector3(at.x, at.y - R * 2.4f - CAP, at.z),
                Quaternion.fromEulerAngles(0f, yaw, 0f),
            ),
            Space.ACTIVITY,
        )
    }

    /** True exactly once per pinch. */
    fun takePinch(): Boolean = pinched.getAndSet(false)

    private fun onInput(ev: InputEvent) {
        if (ev.action != InputEvent.Action.UP) return
        // Both hands emit rays, so one pinch can arrive twice. Against a TOGGLE
        // that means changing the setting and changing it straight back, which
        // reads as "the control does nothing".
        val now = android.os.SystemClock.uptimeMillis()
        if (now - lastSelect < SELECT_DEBOUNCE_MS) return
        lastSelect = now
        Log.i(TAG, "[here] marker pinched")
        pinched.set(true)
    }

    fun clear() {
        entities.forEach { runCatching { it.parent = null } }
        entities.forEach { runCatching { it.dispose() } }
        entities.clear()
        label = null
        lastText = null
    }

    private companion object {
        const val TAG = "MeshmoreXR"
        /** Forward distance and drop: about 34 degrees below eye level. */
        const val AHEAD = 1.30f
        const val DROP = 0.88f
        const val R = 0.045f
        const val CAP = 0.036f
        const val SELECT_DEBOUNCE_MS = 350L
    }
}
