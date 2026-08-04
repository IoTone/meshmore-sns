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
 * THE CONSOLE — settings, projected.
 *
 * `MeshmoreXR-console-spec.md`, built. Five plates rise from an emitter on the
 * dock and fan toward the viewer; picking one opens its bay.
 *
 * WHY A HOLOGRAM, since it will be read as a costume: §1.3 of the brief says on
 * see-through glasses you cannot draw dark, only add light, and every
 * conventional metaphor fights that — a panel wants an opaque ground it cannot
 * have, a card wants a shadow it cannot cast. A projection is the one visual
 * language that IS what this hardware does: self-luminous, semi-transparent, no
 * black, and visibly coming from somewhere. The reference is famous; the idiom
 * is native.
 *
 * ICONS AT REST, WORDS ON FOCUS. A plate carries a MARK, and the full name
 * lands in a fixed readout by the emitter. At the §4.1 floor a one-word title
 * is 14° of arc and the SNS wording is far wider — icon-first is what lets the
 * readout say "Diagnostics & connect / Connect a radio · frame log" instead of
 * an abbreviation, and it keeps the stack a narrow column rather than a slab
 * across the view (§2.1 rule 2: more room means a bigger world window, not more
 * UI).
 *
 * THE READOUT IS FIXED, not per-plate. In a vertical fan, per-plate labels
 * share an axis and collide, and a label that moves as focus moves is a label
 * you chase. The dock gets away with per-pip captions only because a horizontal
 * row spreads them.
 */
class Console(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    /** One choice. [bay] is what the host switches on. */
    class Plate(val bay: String, val title: String, val subtitle: String)

    private class Slide(
        val plate: Plate,
        val mark: Entity,
        val proxy: MeshEntity,
    ) {
        var lastFire = 0L
        var at: Vector3 = Vector3(0f, 0f, 0f)
    }

    private val slides = mutableListOf<Slide>()
    private var cone: MeshEntity? = null
    private var title: TextRun.Run? = null
    private var subtitle: TextRun.Run? = null
    private val entities = mutableListOf<Entity>()
    private val fired = java.util.concurrent.ConcurrentLinkedQueue<String>()

    private var emitter: Vector3? = null
    private var headAt: Vector3? = null

    /**
     * TWO SOURCES OF FOCUS, ONE ANSWER, ONE ANNOUNCEMENT.
     *
     * These were a single field written by both the pointer and the gaze, and
     * they fought: setGazed ran every frame and HOVER_MOVE ran on every pointer
     * sample, so the value flipped continuously and the focus tone fired on
     * each flip. Reported as "little focus chime sounds over and over".
     *
     * A pointer is deliberate and beats a gaze that merely rested somewhere.
     * The tone is raised once, in tick, when the RESOLVED focus changes — not
     * by whichever writer happened to run last.
     */
    private var pointerFocus: String? = null
    private var gazeFocus: String? = null
    private var announced: String? = null
    private val focused: String? get() = pointerFocus ?: gazeFocus

    var open: Boolean = false
        private set

    var onFocus: ((String) -> Unit)? = null

    /**
     * The five, in SNS's order and with SNS's words.
     *
     * Somebody who knows the phone app should find the same five things in the
     * same sequence. Two of these span more than one of the brief's CONSOLE
     * stations (§9.3) and that is expected: SNS groups by what the user came to
     * do, the brief grouped by what the setting is.
     */
    val plates = listOf(
        Plate("DEVICE", "Device configuration", "Meshcore radio & device"),
        Plate("APP", "App settings", "Connection, language, data"),
        Plate("PROFILE", "Profile & personalization", "Theme, type, audio, access"),
        Plate("CHANNELS", "Channels", "Slots · name + key · active"),
        Plate("DIAG", "Diagnostics & connect", "Connect a radio · frame log"),
    )

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        plates.forEach { p ->
            val mark = Marks[markFor(p.bay)]?.let { path ->
                AslIcon.fromPath(
                    session, context, path, MARK, argb(theme.accent, 1f),
                    stroked = true, padPx = 12f, name = "plate-${p.bay}",
                )
            } ?: MeshEntity.create(
                session, Prims.build(session, Prims.halo(MARK * 0.4f, MARK * 0.08f)),
                listOf(Prims.material(session, theme.alt, 0.8f)),
            )
            mark.parent = root
            mark.setEnabled(false)
            entities += mark
            val proxy = MeshEntity.create(
                session, Prims.build(session, Prims.mote(MARK * 0.9f, 5, 8)),
                listOf(Prims.ghost(session)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val s = Slide(p, mark, proxy)
            slides += s
            runCatching {
                proxy.addComponent(
                    InteractableComponent.create(session) { ev -> onInput(s, ev) },
                )
            }.onFailure { Log.w(TAG, "[console] no input on ${p.bay}: $it") }
        }

        // THE CONE. It says where the stack came from, which is what makes
        // collapsing back into the emitter the obvious way out — a menu in
        // mid-air with no origin has no story about why it is there.
        cone = MeshEntity.create(
            session, Prims.build(session, Prims.spur(0f, 0f, 0f, 0f, 1f, 0f, 0.004f)),
            listOf(Prims.material(session, theme.accent, 0.35f)),
        ).also { it.parent = root; it.setEnabled(false); entities += it }

        title = run(root, WIDEST_TITLE, TITLE_CAP, theme.text)
        subtitle = run(root, WIDEST_SUB, SUB_CAP, theme.alt)
        Log.i(TAG, "[console] ${slides.size} plates")
    }

    private suspend fun run(root: Entity, widest: String, cap: Float, rgb: Int): TextRun.Run? =
        TextRun.reusable(session, context, widest, cap, argb(rgb, 0.95f), "console")
            ?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }

    private fun markFor(bay: String) = bay

    /** Project from [at] — the dock pip the stack rises out of. */
    fun showAt(at: Vector3) {
        emitter = at
        open = true
        pointerFocus = null; gazeFocus = null; announced = null
        place()
        Log.i(TAG, "[console] open")
    }

    fun hide() {
        if (!open) return
        open = false
        pointerFocus = null; gazeFocus = null; announced = null
        fired.clear()
        slides.forEach {
            runCatching { it.mark.setEnabled(false); it.proxy.setEnabled(false) }
        }
        runCatching {
            cone?.setEnabled(false)
            title?.entity?.setEnabled(false)
            subtitle?.entity?.setEnabled(false)
        }
        Log.i(TAG, "[console] closed")
    }

    fun poll(): String? = fired.poll()

    fun tick(head: Vector3?) {
        if (!open) return
        headAt = head
        val now = focused
        if (now != announced) {
            announced = now
            if (now != null) onFocus?.invoke(now)
        }
        place()
    }

    private fun place() {
        val e = emitter ?: return
        // The stack sits above and slightly beyond the emitter, and the whole
        // fan faces the viewer. Distances come from the spec: 0.90 m out,
        // centred about 11° below eye, plate pitch 5.4° so hand tracking can
        // tell two of them apart.
        val h = headAt
        val yaw = if (h == null) 0f else atan2(h.x - e.x, h.z - e.z)
        val rot = Quaternion.fromEulerAngles(0f, Math.toDegrees(yaw.toDouble()).toFloat(), 0f)
        // TOWARD THE VIEWER, not across them. This used the viewer's RIGHT
        // vector — copied from the radial menu, where sideways is the point —
        // so the stack staggered horizontally and leaned. A depth splay has to
        // move along the line from the emitter to the eye.
        val tx = kotlin.math.sin(yaw)
        val tz = kotlin.math.cos(yaw)
        val baseY = e.y + RISE
        slides.forEachIndexed { i, s ->
            val y = baseY + (slides.size / 2f - i) * PITCH
            // The top of the deck is nearest.
            val out = (slides.size / 2f - i) * DEPTH
            val at = Vector3(e.x + tx * out, y, e.z + tz * out)
            s.at = at
            runCatching {
                s.mark.setEnabled(true)
                s.proxy.setEnabled(true)
                s.mark.setPose(Pose(at, rot), Space.ACTIVITY)
                s.proxy.setPose(Pose(at), Space.ACTIVITY)
                s.mark.setScale(if (s.plate.bay == focused) HOT else 1f)
            }
        }
        // The cone, from the emitter up to the bottom plate.
        runCatching {
            cone?.setEnabled(true)
            val len = (baseY - (slides.size / 2f) * PITCH) - e.y
            cone?.setPose(Pose(e, rot), Space.ACTIVITY)
            cone?.setScale(len.coerceAtLeast(0.01f))
        }
        // The readout, at the emitter rather than on a plate.
        val f = slides.firstOrNull { it.plate.bay == focused }?.plate
            ?: slides.firstOrNull()?.plate
        runCatching {
            title?.entity?.setEnabled(true)
            subtitle?.entity?.setEnabled(true)
            f?.let {
                title?.setText(it.title)
                subtitle?.setText(it.subtitle)
            }
            val ty = e.y - READOUT_DROP
            title?.entity?.setPose(Pose(Vector3(e.x, ty, e.z), rot), Space.ACTIVITY)
            subtitle?.entity?.setPose(
                Pose(Vector3(e.x, ty - TITLE_CAP * 1.8f, e.z), rot), Space.ACTIVITY,
            )
        }
    }

    fun gazeTargets(): List<Gaze.Target> {
        if (!open) return emptyList()
        return slides.map { s ->
            Gaze.Target("console-${s.plate.bay}", s.at, CONE_RAD) { fired.add(s.plate.bay) }
        }
    }

    /** Which plate the gaze is on, so the readout follows it. */
    fun setGazed(id: String?) {
        gazeFocus = id?.removePrefix("console-")
            ?.takeIf { b -> slides.any { it.plate.bay == b } }
    }

    private fun onInput(s: Slide, ev: InputEvent) {
        if (!open) return
        when (ev.action) {
            InputEvent.Action.HOVER_ENTER, InputEvent.Action.HOVER_MOVE ->
                pointerFocus = s.plate.bay
            InputEvent.Action.HOVER_EXIT ->
                if (pointerFocus == s.plate.bay) pointerFocus = null
            InputEvent.Action.UP -> {
                val now = android.os.SystemClock.uptimeMillis()
                if (now - s.lastFire < DEBOUNCE_MS) return
                s.lastFire = now
                Reach.consumed()
                fired.add(s.plate.bay)
            }
            else -> Unit
        }
    }

    fun clear() {
        slides.clear(); cone = null; title = null; subtitle = null
        open = false; emitter = null; fired.clear()
        pointerFocus = null; gazeFocus = null; announced = null
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"
        /** 3.0° at the stack's distance — the icon floor argued in Marks. */
        const val MARK = 0.047f
        /** How far above the emitter the fan starts. */
        const val RISE = 0.30f
        /** 5.4°, the separation below which hand tracking cannot pick one. */
        const val PITCH = 0.085f
        /** The nearest plate is the top of the deck. */
        const val DEPTH = 0.02f
        const val HOT = 1.30f
        const val CONE_RAD = 0.05f
        const val DEBOUNCE_MS = 350L
        /** 1.48° and 1.35° at the readout's distance. Derived, not chosen. */
        const val TITLE_CAP = 0.022f
        const val SUB_CAP = 0.020f
        const val READOUT_DROP = 0.10f
        const val WIDEST_TITLE = "Profile & personalization"
        const val WIDEST_SUB = "Connection, language, data"
    }
}
