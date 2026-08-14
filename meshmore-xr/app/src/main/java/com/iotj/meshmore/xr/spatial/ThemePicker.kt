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

/**
 * S11 — THE THEME PICKER, and it previews by BEING the thing.
 *
 * The brief is unusually specific about this surface: "theme switching previews
 * live on the actual HORIZON, not in a swatch. You see your real mesh restyled
 * in place. Pick by living in it for five seconds." That was written as an
 * aspiration and it turns out to be the cheap option — [Ink] re-colours a scene
 * already built, so choosing here IS the preview and there is nothing else to
 * implement. Backing out restores what you arrived with.
 *
 * ## Why a grid and not the console's fan
 *
 * The console fans five plates vertically on 5.4° centres, which is the
 * separation below which hand tracking cannot tell two of them apart. Nine on
 * that pitch is 48° of arc in a 34° field: the top and bottom of the list would
 * be outside the display, and a picker you have to look around to see is a
 * scrolling list, which §2.1 forbids.
 *
 * Three by three is 21° x 16°, fits with room either side, and has a second
 * property worth more than the arithmetic — nine tiles at once is a COMPARISON.
 * The whole reason to offer nine skins is that people choose one by looking at
 * them together, and a fan shows you one and asks you to remember the last.
 *
 * ## The tiles are outside the theme, deliberately
 *
 * Each tile is painted in the palette it OFFERS: accent as the face, alt as the
 * underline, warn as the pip. That is three of the four roles previewed before
 * you commit to anything. They are built with `themed = false` so a retint
 * leaves them alone — otherwise picking one would repaint all nine to match it
 * and the grid would go flat at the exact moment it needed to be a comparison.
 */
class ThemePicker(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    private class Tile(
        val skin: Theme.Skin,
        val face: MeshEntity,
        val under: MeshEntity,
        val pip: MeshEntity,
        val proxy: MeshEntity,
    ) {
        var lastFire = 0L
        var at: Vector3 = Vector3(0f, 0f, 0f)
    }

    private val tiles = mutableListOf<Tile>()
    private val entities = mutableListOf<Entity>()
    private var name: TextRun.Run? = null
    private var line: TextRun.Run? = null
    private var note: TextRun.Run? = null
    private var cursor: MeshEntity? = null

    /** Picks, drained by the host, which owns what a pick MEANS. */
    private val fired = java.util.concurrent.ConcurrentLinkedQueue<Theme.Skin>()

    private var anchor: Vector3? = null
    private var yaw: Float = 0f

    var open: Boolean = false
        private set

    /**
     * What the wearer had when they walked in.
     *
     * Kept so [cancel] can put it back. A picker that previews live has to be
     * able to undo, or trying the ninth theme means hunting for the first
     * again — and the wearer who is only looking has no way to leave things as
     * they were.
     */
    private var arrivedWith: Theme.Skin = Theme.DEFAULT

    /** The theme currently being previewed, which is not yet the theme chosen. */
    var previewing: Theme.Skin = Theme.DEFAULT
        private set

    /** Raised when the preview changes, so the host can retint and sound a cue. */
    var onPreview: ((Theme.Skin) -> Unit)? = null

    private var pointerFocus: String? = null
    private var gazeFocus: String? = null
    private var announced: String? = null
    private val focused: String? get() = pointerFocus ?: gazeFocus

    var onFocus: ((Theme.Skin) -> Unit)? = null

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        Theme.ALL.forEach { s ->
            // themed = false on all three: see the class note.
            val face = MeshEntity.create(
                session, Prims.build(session, Prims.bar(TILE_W, TILE_H, DEPTH)),
                listOf(Prims.material(session, s.palette.accent, FACE_A, themed = false)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val under = MeshEntity.create(
                session, Prims.build(session, Prims.bar(TILE_W, UNDER_H, DEPTH)),
                listOf(Prims.material(session, s.palette.alt, 0.85f, themed = false)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val pip = MeshEntity.create(
                session, Prims.build(session, Prims.mote(PIP_R, 5, 8)),
                listOf(Prims.material(session, s.palette.warn, 0.9f, themed = false)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            val proxy = MeshEntity.create(
                session, Prims.build(session, Prims.bar(TILE_W, TILE_H + UNDER_H, HIT_D)),
                listOf(Prims.ghost(session)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }

            val t = Tile(s, face, under, pip, proxy)
            tiles += t
            runCatching {
                proxy.addComponent(InteractableComponent.create(session) { ev -> onInput(t, ev) })
            }.onFailure { Log.w(TAG, "[theme] no input on ${s.key}: $it") }
        }

        // WHICH ONE IS YOURS. A ring, not a brightness change: the tiles are
        // unthemed by design and a brightness change on one of nine competing
        // colours reads as that colour being different rather than that tile
        // being chosen. Form, not luminance (§S4).
        cursor = MeshEntity.create(
            session, Prims.build(session, Prims.oval(TILE_W * 0.62f, (TILE_H + UNDER_H) * 0.75f, 0.0025f)),
            listOf(Prims.material(session, theme.text, 0.95f)),
        ).also { it.parent = root; it.setEnabled(false); entities += it }

        name = run(root, WIDEST_NAME, NAME_CAP, theme.accent, "theme-name")
        line = run(root, WIDEST_LINE, LINE_CAP, theme.text, "theme-line")
        note = run(root, WIDEST_NOTE, LINE_CAP, theme.alt, "theme-note")
        Log.i(TAG, "[theme] picker built with ${tiles.size} tiles")
    }

    private suspend fun run(
        root: Entity, widest: String, cap: Float, rgb: Int, name: String,
    ): TextRun.Run? =
        TextRun.reusable(session, context, widest, cap, argb(rgb, 0.95f), name)
            ?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }

    /**
     * Open in front of [head], on the wearer's facing.
     *
     * [current] is what they are wearing now — remembered so [cancel] can put
     * it back, and used to place the cursor before anything is touched.
     */
    fun showAt(head: Vector3, yawRad: Float, current: Theme.Skin) {
        anchor = head
        yaw = yawRad
        arrivedWith = current
        previewing = current
        open = true
        pointerFocus = null; gazeFocus = null; announced = null
        fired.clear()
        place()
        Log.i(TAG, "[theme] open, wearing ${current.key}")
    }

    fun hide() {
        if (!open) return
        open = false
        pointerFocus = null; gazeFocus = null; announced = null
        fired.clear()
        tiles.forEach {
            runCatching {
                it.face.setEnabled(false); it.under.setEnabled(false)
                it.pip.setEnabled(false); it.proxy.setEnabled(false)
            }
        }
        runCatching {
            cursor?.setEnabled(false)
            name?.entity?.setEnabled(false)
            line?.entity?.setEnabled(false)
            note?.entity?.setEnabled(false)
        }
        Log.i(TAG, "[theme] closed")
    }

    /**
     * Leave without changing anything, restoring what the wearer walked in
     * with. Reported through [onPreview] like any other change, because as far
     * as the host is concerned a revert IS a retint.
     */
    fun cancel() {
        if (previewing != arrivedWith) {
            previewing = arrivedWith
            Log.i(TAG, "[theme] cancelled back to ${arrivedWith.key}")
            onPreview?.invoke(arrivedWith)
        }
        hide()
    }

    /** A pick the host has committed. Stops [cancel] undoing it. */
    fun commit(skin: Theme.Skin) {
        arrivedWith = skin
        previewing = skin
    }

    fun poll(): Theme.Skin? = fired.poll()

    /**
     * Raise a pick that no hand made — `--es switchto <key>`.
     *
     * Same argument as `Console.fire`: routed through the SAME queue a real
     * pinch uses, so what gets verified is the path the wearer takes rather
     * than a shortcut around it.
     *
     * It exists because the bug it tests is invisible from a shell. Choosing a
     * theme at LAUNCH has always applied that theme's structure; choosing one
     * in the picker only ever recoloured, and telling those two apart needs a
     * theme change to happen while the app is already running. Nothing else in
     * the app can produce one without a hand in front of the glasses.
     */
    fun fire(skin: Theme.Skin) {
        fired.add(skin)
        Log.i(TAG, "[theme] '${skin.key}' picked by launch flag")
    }

    fun tick(head: Vector3?) {
        if (!open) return
        val now = focused
        if (now != announced) {
            announced = now
            tiles.firstOrNull { it.skin.key == now }?.let { onFocus?.invoke(it.skin) }
            readout()
        }
        place()
    }

    private fun place() {
        val a = anchor ?: return
        // THE HOUSE YAW CONVENTION, and it is not the obvious one.
        //
        // `MainActivity.yawOf` reads the pose's local +Z axis and returns
        // atan2(-fx, fz) — but a head pose looks down its own -Z, so the
        // direction the wearer is actually FACING is the negative of that axis,
        // which works out to (sin yaw, 0, -cos yaw). Crown places its column on
        // exactly this and is the reference. Taking the +Z axis at face value
        // instead puts the whole grid behind the wearer's head, where it is
        // invisible and reads as "the picker does not open".
        val fx = kotlin.math.sin(yaw)
        val fz = -kotlin.math.cos(yaw)
        // Across = forward x up, so a positive u is to the wearer's right.
        val rx = kotlin.math.cos(yaw)
        val rz = kotlin.math.sin(yaw)
        fun at(u: Float, v: Float, d: Float = DIST) = Vector3(
            a.x + fx * d + rx * u, a.y + v, a.z + fz * d + rz * u,
        )
        // TURNED TOWARD THE EYE INDIVIDUALLY, not all on one plane. At the
        // outer columns the difference is about 8 degrees, which is the
        // difference between a swatch showing you its colour and a swatch
        // showing you its colour at a slant — on a grid whose entire job is
        // colour comparison, that is not a detail.
        fun facing(p: Vector3): Quaternion {
            val dx = a.x - p.x
            val dz = a.z - p.z
            if (dx * dx + dz * dz < 1e-6f) return Quaternion.fromEulerAngles(0f, 0f, 0f)
            return Quaternion.fromEulerAngles(
                0f, Math.toDegrees(kotlin.math.atan2(dx, dz).toDouble()).toFloat(), 0f,
            )
        }

        tiles.forEachIndexed { i, t ->
            val col = i % COLS
            val row = i / COLS
            val u = (col - (COLS - 1) / 2f) * PITCH_U
            val v = TOP_DROP - row * PITCH_V
            val p = at(u, v)
            t.at = p
            val rot = facing(p)
            val hot = t.skin.key == focused
            runCatching {
                t.face.setEnabled(true); t.under.setEnabled(true)
                t.pip.setEnabled(true); t.proxy.setEnabled(true)
                t.face.setPose(Pose(p, rot), Space.ACTIVITY)
                t.under.setPose(
                    Pose(at(u, v - TILE_H / 2f - UNDER_H / 2f), rot), Space.ACTIVITY,
                )
                t.pip.setPose(
                    Pose(at(u + TILE_W / 2f - PIP_R * 2f, v + TILE_H / 2f - PIP_R * 2f)),
                    Space.ACTIVITY,
                )
                t.proxy.setPose(Pose(at(u, v - UNDER_H / 2f)), Space.ACTIVITY)
                // FOCUS IS SCALE. See the cursor note: luminance is spoken for.
                t.face.setScale(if (hot) HOT else 1f)
            }
        }

        // The cursor sits on what is being PREVIEWED, which after a pick is the
        // thing you are now wearing — not on whatever the pointer is passing over.
        val ci = Theme.indexOf(previewing)
        val cu = (ci % COLS - (COLS - 1) / 2f) * PITCH_U
        val cv = TOP_DROP - (ci / COLS) * PITCH_V
        val cp = at(cu, cv - UNDER_H / 2f, DIST - 0.01f)
        runCatching {
            cursor?.setEnabled(true)
            cursor?.setPose(Pose(cp, facing(cp)), Space.ACTIVITY)
        }

        val ry = TOP_DROP - (ROWS - 1) * PITCH_V - READOUT_DROP
        val np = at(0f, ry)
        val lp = at(0f, ry - NAME_CAP * 2.0f)
        val op = at(0f, ry - NAME_CAP * 2.0f - LINE_CAP * 2.2f)
        runCatching {
            name?.entity?.setEnabled(true)
            line?.entity?.setEnabled(true)
            note?.entity?.setEnabled(true)
            name?.entity?.setPose(Pose(np, facing(np)), Space.ACTIVITY)
            line?.entity?.setPose(Pose(lp, facing(lp)), Space.ACTIVITY)
            note?.entity?.setPose(Pose(op, facing(op)), Space.ACTIVITY)
        }
    }

    /** Words describe what the pointer is ON; colour shows what you are WEARING. */
    private fun readout() {
        val s = tiles.firstOrNull { it.skin.key == focused }?.skin ?: previewing
        runCatching {
            name?.setText(s.name)
            line?.setText(s.line)
            note?.setText(noteFor(s))
        }
    }

    private fun noteFor(s: Theme.Skin): String {
        val posture = when (s.posture) {
            Theme.Posture.FIELD -> context.getString(com.iotj.meshmore.xr.R.string.pk_field)
            Theme.Posture.TABLETOP -> context.getString(com.iotj.meshmore.xr.R.string.pk_tabletop)
            Theme.Posture.TRANSIT -> context.getString(com.iotj.meshmore.xr.R.string.pk_transit)
        }
        val sub = when (s.substrate) {
            Theme.Substrate.PANEL -> context.getString(com.iotj.meshmore.xr.R.string.pk_panel)
            Theme.Substrate.ADDITIVE -> context.getString(com.iotj.meshmore.xr.R.string.pk_additive)
            Theme.Substrate.HYBRID -> context.getString(com.iotj.meshmore.xr.R.string.pk_hybrid)
        }
        val worn = if (s == previewing) " · WORN" else ""
        return "$sub · $posture · ${s.audio.uppercase()}$worn"
    }

    fun gazeTargets(): List<Gaze.Target> {
        if (!open) return emptyList()
        return tiles.map { t ->
            Gaze.Target("theme-${t.skin.key}", t.at, CONE_RAD) { fired.add(t.skin) }
        }
    }

    fun setGazed(id: String?) {
        gazeFocus = id?.removePrefix("theme-")?.takeIf { k -> tiles.any { it.skin.key == k } }
    }

    private fun onInput(t: Tile, ev: InputEvent) {
        if (!open) return
        when (ev.action) {
            InputEvent.Action.HOVER_ENTER, InputEvent.Action.HOVER_MOVE ->
                pointerFocus = t.skin.key
            InputEvent.Action.HOVER_EXIT ->
                if (pointerFocus == t.skin.key) pointerFocus = null
            InputEvent.Action.UP -> {
                val now = android.os.SystemClock.uptimeMillis()
                if (now - t.lastFire < DEBOUNCE_MS) return
                t.lastFire = now
                Reach.consumed()
                fired.add(t.skin)
            }
            else -> Unit
        }
    }

    /**
     * Apply a preview. Called by the host after a pick, once it has retinted —
     * the picker does not reach for [Ink] itself, so that one place in the app
     * owns what a theme change does and this surface stays a picker.
     */
    fun setPreviewing(skin: Theme.Skin) {
        previewing = skin
        readout()
        place()
    }

    fun clear() {
        tiles.clear(); cursor = null; name = null; line = null; note = null
        open = false; anchor = null; fired.clear()
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

        /**
         * A metre out — the crown's distance, and for the same reason. Closer
         * than that and a nine-tile grid subtends more than the field; further
         * and the tiles fall under the 3.0° icon floor unless they grow, which
         * puts the grid back over the field. One metre is where both fit.
         */
        const val DIST = 1.0f
        const val COLS = 3
        const val ROWS = 3

        /** 6.3° across and 4.3° tall at DIST — well clear of the 3.0° floor. */
        const val TILE_W = 0.110f
        const val TILE_H = 0.075f
        const val UNDER_H = 0.014f
        const val PIP_R = 0.007f
        const val DEPTH = 0.005f
        const val HIT_D = 0.03f

        /**
         * The swatch face, and it is not 1.0 on purpose.
         *
         * Nine solid tiles at full emission a metre from your eyes is the
         * brightest thing this app ever draws, and it would be drawn on the one
         * surface a wearer opens to compare subtleties of colour. Dimmed to
         * where the accents are still unmistakably themselves and the room is
         * still visible behind them — the room is the ground every one of these
         * palettes will actually sit on.
         */
        const val FACE_A = 0.55f

        /** Centres: 7.7° across, 6.0° down. Above the 5.4° hand-tracking floor. */
        const val PITCH_U = 0.135f
        const val PITCH_V = 0.105f

        /** Grid centred a little above eye-height's midline, so the readout has room. */
        const val TOP_DROP = 0.10f
        const val READOUT_DROP = 0.055f
        const val HOT = 1.18f
        const val CONE_RAD = 0.055f
        const val DEBOUNCE_MS = 350L

        /** 1.55° and 1.32° at DIST. §4.1 floor is 1.2°; house standard 1.30°. */
        const val NAME_CAP = 0.027f
        const val LINE_CAP = 0.023f

        const val WIDEST_NAME = "SEELE MONOLITH"
        const val WIDEST_LINE = "Drifting spores, mycelial threads, soft breathing light."
        const val WIDEST_NOTE = "ADDITIVE · TABLETOP · PUREPHASE · WORN"
    }
}
