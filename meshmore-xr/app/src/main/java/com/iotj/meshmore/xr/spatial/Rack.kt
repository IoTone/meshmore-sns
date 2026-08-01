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
import com.iotj.meshmore.xr.RadioConfig

/**
 * THE RADIO RACK — design brief §9.6, on the glasses.
 *
 * The CONSOLE configures the app. This configures the RADIO, and the difference
 * is not cosmetic: four of these fields can leave the hardware deaf in the field
 * with no on-device way back. That asymmetry is the whole design, and it is why
 * this surface is HARD where the rest of the app is soft. Everywhere else you
 * are reading the mesh, which you cannot break by looking at it. A detented
 * encoder resists you. A guarded switch has to be uncovered before it can be
 * thrown. Nothing here is a row with a chevron.
 *
 * FOUR ROWS, FOUR CLASSES OF RISK, legible before you read a word:
 *
 *   IDENTITY  name, key, what we disclose        reversible / disclosure
 *   AIR       the four LoRa params + TX          STRANDING / regulatory
 *   COMMIT    live vs pending, commit, revert    the gate
 *   CHANNELS  slots, PSK fingerprints            key material
 *
 * THE CHASSIS IS EDGES AND LIGHT, not a face. On an additive display black is
 * transparent, and a 19-inch rack panel is mostly dark anodised metal — drawn
 * faithfully it renders as NOTHING, leaving lamps and legends floating with no
 * instrument under them. So rails, ears, screw bosses and unit seams are
 * extruded and lit, and the metal between them is implied by the frame around
 * it, exactly as a wireframe implies a solid.
 *
 * SIZED BY ANGLE. At true 19-inch scale and reach distance a rack face subtends
 * 49 degrees, which is wider than the comfortable field. Width comes from the
 * angle we are willing to spend and the unit height falls out of the real
 * 10.9:1 ratio.
 *
 * INTERACTION IS DETENTED, NOT DRAGGED. A pinch on an encoder advances it one
 * step, which is what a detented encoder does under a finger and is also the
 * only gesture the Aura reliably reports (hand tracking only, no controller).
 * Big moves are what PRESET is for; the raw encoders are fine adjustment.
 */
class Rack(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
    private val cfg: RadioConfig,
) {

    private val entities = mutableListOf<Entity>()
    private val controls = mutableListOf<Control>()
    private val facing = mutableListOf<Pair<Entity, Vector3>>()

    /** Raised on the input thread, drained by the frame loop — as Horizon does. */
    private val fired = java.util.concurrent.ConcurrentLinkedQueue<Control>()

    /** Something you can pinch. [act] runs on the frame loop, never on input. */
    private inner class Control(val name: String, val at: Vector3, val act: () -> Unit) {
        var lastFire = 0L
    }

    // ---- live state the panel reflects -------------------------------------
    private var segLive: Segment? = null
    private var segPend: Segment? = null
    private var lampPending: Lamp? = null
    private var bar: Bargraph? = null
    private var dirty = false

    /**
     * THE RACK IS NOT AMBIENT. It starts hidden and is summoned.
     *
     * Left permanently in the room it is a live radio configuration sitting in
     * the space you gesture in — eleven controls, four of which can strand the
     * hardware, all one stray pinch away while you are doing something else
     * entirely. Every other surface in this app is safe to have around because
     * looking at the mesh cannot change it. This one is not, and the difference
     * has to be expressed as PRESENCE rather than only as caution.
     */
    /**
     * FALSE, and the entities are created disabled to match — the flag has to
     * describe what the scene is actually doing, not what we intended.
     *
     * It briefly said true-in-effect the other way round: entities were built
     * enabled and disabled a frame later, which drew the console at launch and
     * then took it away. Both halves have to agree at every instant, including
     * during the build.
     */
    var visible: Boolean = false
        private set

    fun setVisible(v: Boolean) {
        if (v == visible) return
        visible = v
        // setEnabled, not alpha: a disabled entity is not hit-tested, so an
        // invisible rack cannot be pinched. Fading it out would leave every
        // control live behind a transparent panel, which is the same accident
        // with an extra step.
        entities.forEach { runCatching { it.setEnabled(v) } }
        armed = false
        // RE-ASSERT EVERY LAMP. setEnabled(true) turns the whole subtree back
        // on, including the GLOW ring of a lamp that is supposed to be dark —
        // so a PENDING that was lit when the rack was dismissed came back as a
        // gold ring floating in the room with no panel under it. Enabling is
        // not the same as restoring: the entities remember they were enabled,
        // not what they meant.
        armLamp?.set(false)
        if (v) refresh() else lampPending?.set(false)
        Log.i(TAG, "[rack] ${if (v) "summoned" else "dismissed"}")
    }

    // ------------------------------------------------------------------ build
    suspend fun build(o: Stage.Origin) {
        clear()
        val root = session.scene.activitySpace

        // Body-locked to the launch facing and tilted back like a real console:
        // a vertical face at reach height forces the head down and the eyes up.
        val base = o.place(0f, REACH, EYE_DROP)
        val yaw = Math.toDegrees(o.yawRad.toDouble()).toFloat()

        // ORIENTATION IS COMPOSED, NOT AN EULER TRIPLE. fromEulerAngles(tilt,
        // yaw, 0) put a visible ROLL on the panel -- the rails ran diagonally --
        // because this library's Euler ORDER is not the one that reading the
        // argument names suggests. The yaw term is verified against the horizon
        // billboards; multiplying a local-X rotation onto its right applies the
        // tilt in the panel's own frame, which is well-defined whatever the
        // order turns out to be. Same lesson as the microhud's +yaw bug: a
        // convention that agrees at zero is not a convention you have checked.
        val rot = Quaternion.fromEulerAngles(0f, -yaw, 0f) *
            Quaternion.fromAxisAngle(Vector3(1f, 0f, 0f), TILT_DEG)

        // AND POSITIONS GO THROUGH THE SAME ROTATION. Orienting each part by the
        // tilt while laying them out on an untilted plane makes a panel of
        // tilted tiles rather than a tilted panel — every part faces the right
        // way and none of them is where it belongs.
        val ct = kotlin.math.cos(Math.toRadians(TILT_DEG.toDouble())).toFloat()
        val st = kotlin.math.sin(Math.toRadians(TILT_DEG.toDouble())).toFloat()
        val cy = kotlin.math.cos(o.yawRad)
        val sy = kotlin.math.sin(o.yawRad)
        val pose = { x: Float, y: Float, z: Float ->
            // tilt about the panel's X, then yaw about world Y.
            val ty = y * ct - z * st
            val tz = y * st + z * ct
            // +Z IS TOWARD THE USER. It was away, and everything raised off the
            // face — knob bodies, witness marks, lamp domes, segment bars — was
            // therefore sunk BEHIND the chassis it should stand proud of, so the
            // knobs rendered as holes rather than as knobs.
            //
            // The user is at o and the rack sits REACH along (sin yaw, ·, -cos
            // yaw), so rack -> user is (-sin yaw, ·, +cos yaw). Depth has to be
            // added along THAT, not its negation. The x term keeps the right
            // vector (cos yaw, ·, sin yaw); only depth was inverted.
            Vector3(base.x + x * cy - tz * sy, base.y + ty, base.z + x * sy + tz * cy)
        }

        suspend fun mesh(f: Prims.Facets, rgb: Int, a: Float, x: Float, y: Float, z: Float = 0f):
            MeshEntity = MeshEntity.create(
            session, Prims.build(session, f), listOf(Prims.material(session, rgb, a)),
        ).also {
            it.parent = root
            it.setPose(Pose(pose(x, y, z), rot), Space.ACTIVITY)
            // BORN HIDDEN. Building enabled and disabling afterwards draws the
            // whole panel for the frames the build takes -- 276 entities, so
            // several -- and a radio console that flashes up at launch and
            // vanishes reads as a fault even though it is the correct end
            // state. There is no moment at which it should have been visible.
            it.setEnabled(false)
            entities += it
        }

        buildChassis(::mesh)
        val rows = (0 until 4).map { rowY(it) }
        buildIdentity(::mesh, rows[0])
        buildAir(::mesh, rows[1])
        buildCommit(::mesh, rows[2])
        buildChannels(::mesh, rows[3])

        // Hit proxies last, so they sit in front of everything they stand for.
        controls.forEach { c ->
            val proxy = MeshEntity.create(
                session, Prims.build(session, Prims.mote(HIT_R, 5, 8)),
                listOf(Prims.material(session, theme.accent, 0.02f)),
            ).also {
                it.parent = root
                it.setPose(Pose(pose(c.at.x, c.at.y, c.at.z + 0.02f), rot), Space.ACTIVITY)
                it.setAlpha(0.02f)
                it.setEnabled(false)
                entities += it
            }
            runCatching {
                proxy.addComponent(InteractableComponent.create(session) { ev -> onInput(c, ev) })
            }.onFailure { Log.w(TAG, "[rack] no input on ${c.name}: $it") }
        }
        refresh()
        Log.i(TAG, "[rack] built ${entities.size} entities, ${controls.size} controls")
    }

    private fun rowY(i: Int) = H / 2f - (U * ROW_U) / 2f - i * U * ROW_U
    private fun col(f: Float) = -RACK_W / 2f + INSET + f * (RACK_W - INSET * 2f)

    private suspend fun buildChassis(
        mesh: suspend (Prims.Facets, Int, Float, Float, Float, Float) -> MeshEntity,
    ) {
        // Rails and ears. These carry the entire silhouette on additive optics,
        // so they are the brightest thing on the panel and drawn first.
        mesh(Prims.bar(RACK_W, RAIL, 0.016f), theme.alt, 0.95f, 0f, H / 2f, 0f)
        mesh(Prims.bar(RACK_W, RAIL, 0.016f), theme.alt, 0.95f, 0f, -H / 2f, 0f)
        mesh(Prims.bar(RAIL, H, 0.016f), theme.alt, 0.95f, -RACK_W / 2f, 0f, 0f)
        mesh(Prims.bar(RAIL, H, 0.016f), theme.alt, 0.95f, RACK_W / 2f, 0f, 0f)
        for (s in listOf(-1f, 1f)) {
            mesh(Prims.bar(0.030f, H, 0.014f), theme.alt, 0.45f, s * (RACK_W / 2f - 0.015f), 0f, 0f)
            // Screw bosses at the standard 1U spacing. Nothing bolts to them;
            // they are what makes the thing read as rack-mounted rather than as
            // merely rectangular.
            for (i in 0 until 4) {
                mesh(Prims.halo(0.0055f, 0.0018f, 10, 4), theme.text, 0.7f,
                    s * (RACK_W / 2f - 0.015f), rowY(i), 0.008f)
            }
        }
        // Unit seams. One unbroken face reads as a slab.
        for (i in 1 until 4) {
            mesh(Prims.bar(RACK_W - 0.036f, 0.0015f, 0.012f), theme.alt, 0.35f,
                0f, H / 2f - i * U * ROW_U, 0.004f)
        }
        label("RADIO - MESHCORE COMPANION", col(0f) + 0.06f, H / 2f + 0.022f, mesh)
    }

    // ------------------------------------------------------------- ROW 1 ----
    private suspend fun buildIdentity(
        mesh: suspend (Prims.Facets, Int, Float, Float, Float, Float) -> MeshEntity, y: Float,
    ) {
        lamp(col(0.05f), y + 0.012f, "FIX", theme.alt, true, mesh)
        slate("NODE", cfg.live?.let { "B727FE05" } ?: "—", col(0.24f), y + 0.010f, mesh)

        // TWO DISCLOSURE SWITCHES, GUARDED SEPARATELY. The first says "use the
        // headset fix to draw the horizon", which never leaves the glasses. The
        // second says "put that fix in every advert", which broadcasts where the
        // wearer is, unencrypted, to anyone in range. Wiring one to the other
        // would be the single most consequential shortcut available here.
        guard(col(0.72f), y + 0.006f, "GPS SRC", theme.warn, mesh)
        guard(col(0.92f), y + 0.006f, "BCAST POS", theme.warn, mesh)
    }

    // ------------------------------------------------------------- ROW 2 ----
    private suspend fun buildAir(
        mesh: suspend (Prims.Facets, Int, Float, Float, Float, Float) -> MeshEntity, y: Float,
    ) {
        // PRESET first, raw parameters after. Nobody thinks "SF7" — they think
        // "the mesh my region is on", and offering the numbers first is how
        // someone ends up typing a spreading factor they read on a forum.
        knob(col(0.08f), y, "PRESET", mesh) { nextPreset() }
        knob(col(0.29f), y, "FREQ", mesh) { stage { it.copy(freqMhz = step(it.freqMhz)) } }
        knob(col(0.47f), y, "BW", mesh) { stage { it.copy(bandwidthKhz = nextIn(BWS, it.bandwidthKhz)) } }
        knob(col(0.65f), y, "SF", mesh) { stage { it.copy(spreadingFactor = nextInt(SFS, it.spreadingFactor)) } }
        knob(col(0.82f), y, "CR", mesh) { stage { it.copy(codingRate = nextInt(CRS, it.codingRate)) } }

        // TX power. The red zone is a REGULATORY ceiling, not a device one: the
        // radio will happily accept a figure the wearer may not lawfully
        // transmit at, so the panel is where that gets said.
        bar = Bargraph(col(0.955f), y - 0.002f, mesh).also { it.build() }
        knob(col(0.955f) - 0.001f, y - 0.030f, "TX", mesh) {
            stage { it.copy(txDbm = ((it.txDbm + 2 - 2) % 22) + 2) }
        }
    }

    // ------------------------------------------------------------- ROW 3 ----
    private suspend fun buildCommit(
        mesh: suspend (Prims.Facets, Int, Float, Float, Float, Float) -> MeshEntity, y: Float,
    ) {
        // LIVE above, PENDING below, ALWAYS BOTH. One readout that silently
        // switches between "what the radio is doing" and "what it would do" is
        // how you commit something you did not mean to.
        label("LIVE", col(0.04f), y + 0.014f, mesh)
        label("PEND", col(0.04f), y - 0.016f, mesh)
        segLive = Segment(col(0.24f), y + 0.014f, theme.alt, mesh).also { it.build(7) }
        segPend = Segment(col(0.24f), y - 0.016f, theme.warn, mesh).also { it.build(7) }
        lampPending = lamp(col(0.44f), y + 0.010f, "PENDING", theme.warn, false, mesh)
        armLamp = lamp(col(0.60f), y + 0.010f, "ARMED", theme.warn, false, mesh)

        // COMMIT IS TWO-STEP, like the disclosure guards and for the same
        // reason: it is the only control on this panel that reaches the radio.
        // Everything else stages, and staging is free — you can turn every
        // encoder to nonsense and walk away with the hardware untouched. One
        // pinch on a bare button undoes that whole protection, and it was a bare
        // button until the panel was seen sitting in a room being gestured near.
        //
        // First pinch ARMS and lights the lamp. Second commits. Anything else —
        // dismissing the rack, or staging a further edit — disarms, because an
        // arm that survives a change of mind is not a confirmation of anything.
        pebble(col(0.75f), y + 0.008f, "COMMIT", theme.alt, 0.016f, mesh) { armOrCommit() }
        pebble(col(0.93f), y + 0.008f, "REVERT", theme.warn, 0.013f, mesh) { revert() }
    }

    // ------------------------------------------------------------- ROW 4 ----
    private suspend fun buildChannels(
        mesh: suspend (Prims.Facets, Int, Float, Float, Float, Float) -> MeshEntity, y: Float,
    ) {
        lamp(col(0.05f), y + 0.012f, "PUBLIC", theme.alt, true, mesh)
        // A PSK is FINGERPRINTED, never printed. It decrypts every message on
        // the channel, so a panel that shows it is a panel that cannot be
        // photographed, screen-shared, or worn in public.
        slate("CH0", "Public 8b3387e9", col(0.32f), y + 0.010f, mesh)
        slate("CH1", "— empty —", col(0.66f), y + 0.010f, mesh)
        pebble(col(0.80f), y + 0.008f, "IMPORT", theme.alt, 0.012f, mesh) {
            Log.i(TAG, "[rack] channel import — QR scan not wired")
        }
        // A way out that does not require finding the thing that summoned it.
        pebble(col(0.96f), y + 0.008f, "CLOSE", theme.text, 0.013f, mesh) {
            onDismiss?.invoke()
        }
    }

    // ---------------------------------------------------------- components --
    private inner class Segment(
        val x: Float, val y: Float, val rgb: Int,
        val mesh: suspend (Prims.Facets, Int, Float, Float, Float, Float) -> MeshEntity,
    ) {
        val digits = ArrayList<MutableList<MeshEntity>>()
        suspend fun build(n: Int) {
            for (d in 0 until n) {
                val segs = ArrayList<MeshEntity>()
                val dx = x + (d - (n - 1) / 2f) * SEG_PITCH
                for (s in SEG_LAYOUT.indices) {
                    val (kind, ox, oy) = SEG_LAYOUT[s]
                    val f = if (kind == 0) Prims.bar(SEG_W - SEG_T, SEG_T, SEG_T)
                    else Prims.bar(SEG_T, SEG_H / 2f - SEG_T, SEG_T)
                    segs += mesh(f, rgb, 0.12f, dx + ox, y + oy, 0.004f)
                }
                digits.add(segs)
            }
        }
        /** A real segment display has DARK segments too — the ghost of the 8. */
        fun set(text: String) {
            val n = digits.size
            val chars = text.replace(".", "").takeLast(n).padStart(n, ' ')
            digits.forEachIndexed { i, segs ->
                val bits = SEG_BITS[chars[i]] ?: 0
                segs.forEachIndexed { s, e ->
                    e.setAlpha(if ((bits shr (6 - s)) and 1 == 1) 1f else 0.12f)
                }
            }
        }
    }

    private inner class Lamp(val dome: MeshEntity, val glow: MeshEntity) {
        fun set(on: Boolean) {
            dome.setAlpha(if (on) 1f else 0.14f)
            glow.setEnabled(on)
        }
    }

    private inner class Bargraph(
        val x: Float, val y: Float,
        val mesh: suspend (Prims.Facets, Int, Float, Float, Float, Float) -> MeshEntity,
    ) {
        val cells = ArrayList<MeshEntity>()
        suspend fun build() {
            for (i in 0 until BAR_N) {
                val red = i >= BAR_RED
                cells += mesh(
                    Prims.bar(0.010f, 0.0026f, 0.006f),
                    if (red) theme.warn else theme.accent, 0.12f,
                    x, y + (i - (BAR_N - 1) / 2f) * 0.0042f, 0.004f,
                )
            }
        }
        fun set(filled: Int) =
            cells.forEachIndexed { i, e -> e.setAlpha(if (i < filled) 1f else 0.12f) }
    }

    private suspend fun lamp(
        x: Float, y: Float, legend: String, rgb: Int, on: Boolean,
        mesh: suspend (Prims.Facets, Int, Float, Float, Float, Float) -> MeshEntity,
    ): Lamp {
        val dome = mesh(Prims.mote(0.0075f, 5, 8), rgb, 1f, x, y, 0.006f)
        mesh(Prims.halo(0.0112f, 0.0022f, 14, 4), theme.alt, 0.7f, x, y, 0.006f)
        val glow = mesh(Prims.halo(0.018f, 0.004f, 16, 4), rgb, 0.45f, x, y, 0.004f)
        label(legend, x, y - 0.026f, mesh)
        return Lamp(dome, glow).also { it.set(on) }
    }

    /**
     * A detented encoder. Knurled body, a witness mark that turns, and a ring of
     * position lamps — the value is read from those and from the segment display
     * it drives, never printed on the knob, because a number on a knob has to
     * face you and a knob that always faces you cannot look turned.
     */
    private suspend fun knob(
        x: Float, y: Float, legend: String,
        mesh: suspend (Prims.Facets, Int, Float, Float, Float, Float) -> MeshEntity,
        act: () -> Unit,
    ) {
        mesh(Prims.cyl(KNOB_R, 0.012f, 20), theme.text, 0.55f, x, y, 0.008f)
        for (i in 0 until 12) {
            val a = i / 12f * 2f * Math.PI.toFloat()
            mesh(Prims.bar(0.0022f, 0.0022f, 0.013f), theme.alt, 0.85f,
                x + kotlin.math.cos(a) * KNOB_R, y + kotlin.math.sin(a) * KNOB_R, 0.008f)
        }
        mesh(Prims.bar(0.0018f, KNOB_R * 0.8f, 0.004f), theme.accent, 1f,
            x, y + KNOB_R * 0.5f, 0.015f)
        label(legend, x, y - KNOB_R * 2.6f, mesh)
        controls += Control(legend, Vector3(x, y, 0.01f), act)
    }

    private suspend fun pebble(
        x: Float, y: Float, legend: String, rgb: Int, r: Float,
        mesh: suspend (Prims.Facets, Int, Float, Float, Float, Float) -> MeshEntity,
        act: () -> Unit,
    ) {
        mesh(Prims.mote(r, 7, 10), rgb, 0.9f, x, y, 0.010f)
        label(legend, x, y - r * 2.6f, mesh)
        controls += Control(legend, Vector3(x, y, 0.01f), act)
    }

    /**
     * A hinged cover over a switch that must not be thrown by accident. The one
     * interaction in this app with deliberate FRICTION: first pinch lifts the
     * cover, second throws the switch. Everything else is designed to be as easy
     * to operate as possible; these two are not, because throwing them
     * broadcasts the wearer's position.
     */
    private suspend fun guard(
        x: Float, y: Float, legend: String, rgb: Int,
        mesh: suspend (Prims.Facets, Int, Float, Float, Float, Float) -> MeshEntity,
    ) {
        mesh(Prims.cyl(0.010f, 0.005f, 14), theme.text, 0.5f, x, y, 0.006f)
        val toggle = mesh(Prims.bar(0.010f, 0.020f, 0.008f), rgb, 0.9f, x, y + 0.005f, 0.012f)
        val cover = ArrayList<MeshEntity>()
        for (ox in listOf(-0.010f, 0f, 0.010f)) {
            cover += mesh(Prims.bar(0.0020f, 0.034f, 0.0020f), theme.warn, 0.9f,
                x + ox, y - 0.004f, 0.022f)
        }
        cover += mesh(Prims.bar(0.024f, 0.0020f, 0.0020f), theme.warn, 0.9f, x, y - 0.021f, 0.022f)
        label(legend, x, y - 0.032f, mesh)

        var open = false
        var on = true
        controls += Control(legend, Vector3(x, y, 0.02f)) {
            if (!open) {
                open = true
                cover.forEach { it.setAlpha(0.25f) }
                Log.i(TAG, "[rack] $legend guard lifted")
            } else {
                on = !on
                open = false
                cover.forEach { it.setAlpha(0.9f) }
                toggle.setAlpha(if (on) 0.9f else 0.25f)
                Log.i(TAG, "[rack] $legend -> ${if (on) "ON" else "OFF"}")
            }
        }
    }

    /** A printed plate: a value you read here and cannot turn. */
    private suspend fun slate(
        caption: String, value: String, x: Float, y: Float,
        mesh: suspend (Prims.Facets, Int, Float, Float, Float, Float) -> MeshEntity,
    ) {
        label(caption, x - 0.05f, y + 0.014f, mesh)
        // Tier R: the value may be a channel name in any script the mesh uses.
        TextRun.create(session, context, value, CAP * 0.9f, argb(theme.text, 0.9f), "slate")?.let {
            it.entity.parent = session.scene.activitySpace
            entities += it.entity
            facing += it.entity to Vector3(x, y, 0.006f)
        }
    }

    /** Tier S: short, Latin, welded to a control. Exactly what strokes are for. */
    private suspend fun label(
        text: String, x: Float, y: Float,
        mesh: suspend (Prims.Facets, Int, Float, Float, Float, Float) -> MeshEntity,
    ) {
        mesh(Glyphs.text(text, CAP), theme.alt, 0.85f, x, y, 0.006f)
    }

    // ------------------------------------------------------------- actions --
    private fun stage(edit: (RadioConfig.Params) -> RadioConfig.Params) {
        // Staging DISARMS. An arm is a confirmation of one specific parameter
        // set; letting it survive an edit would let the second pinch commit
        // something the first one never saw.
        disarm()
        cfg.stage(edit); refresh()
    }

    private fun step(f: Double) = ((f * 1000).toLong() + 25).let { it / 1000.0 }
    private fun nextIn(xs: List<Double>, v: Double) = xs[(xs.indexOf(v).coerceAtLeast(0) + 1) % xs.size]
    private fun nextInt(xs: List<Int>, v: Int) = xs[(xs.indexOf(v).coerceAtLeast(0) + 1) % xs.size]

    private var presetIdx = 0
    private fun nextPreset() {
        presetIdx = (presetIdx + 1) % PRESETS.size
        val p = PRESETS[presetIdx]
        Log.i(TAG, "[rack] preset ${p.first}")
        stage { it.copy(freqMhz = p.second, bandwidthKhz = p.third, spreadingFactor = p.fourth, codingRate = p.fifth) }
    }

    var onCommit: (() -> Unit)? = null
    var onRevert: (() -> Unit)? = null
    var onDismiss: (() -> Unit)? = null

    private var armed = false
    private var armLamp: Lamp? = null

    private fun armOrCommit() {
        if (!cfg.dirty()) { Log.i(TAG, "[rack] nothing staged"); return }
        if (!armed) {
            armed = true
            armLamp?.set(true)
            Log.i(TAG, "[rack] COMMIT armed — pinch again to send")
            return
        }
        armed = false
        armLamp?.set(false)
        onCommit?.invoke()
        refresh()
    }

    private fun disarm() {
        if (!armed) return
        armed = false
        armLamp?.set(false)
        Log.i(TAG, "[rack] disarmed — the staged set changed")
    }

    private fun revert() { disarm(); onRevert?.invoke(); refresh() }

    fun refresh() {
        segLive?.set(cfg.live?.let { "%.3f".format(it.freqMhz) } ?: "  ---")
        segPend?.set(cfg.pending?.let { "%.3f".format(it.freqMhz) } ?: "  ---")
        dirty = cfg.dirty()
        lampPending?.set(dirty)
        bar?.set(((cfg.pending?.txDbm ?: 0) / 2).coerceIn(0, BAR_N))
    }

    // --------------------------------------------------------------- input --
    private fun onInput(c: Control, ev: InputEvent) {
        if (ev.action != InputEvent.Action.UP) return
        // Both hands emit rays, so one pinch can arrive twice — and against a
        // detented encoder that silently advances two steps.
        val now = android.os.SystemClock.uptimeMillis()
        if (now - c.lastFire < DEBOUNCE_MS) return
        c.lastFire = now
        fired.add(c)
    }

    /** Drain on the frame loop. Nothing mutates the radio from an input callback. */
    fun tick(head: Vector3?) {
        while (true) {
            val c = fired.poll() ?: break
            Log.i(TAG, "[rack] ${c.name}")
            runCatching { c.act() }.onFailure { Log.w(TAG, "[rack] ${c.name} failed: $it") }
        }
        head ?: return
        facing.forEach { (e, at) ->
            val dx = head.x - at.x; val dz = head.z - at.z
            if (dx * dx + dz * dz < 1e-6f) return@forEach
            e.setPose(
                Pose(at, Quaternion.fromEulerAngles(0f,
                    Math.toDegrees(kotlin.math.atan2(dx, dz).toDouble()).toFloat(), 0f)),
                Space.ACTIVITY,
            )
        }
    }

    fun clear() {
        segLive = null; segPend = null; lampPending = null; bar = null
        controls.clear(); facing.clear(); fired.clear()
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"
        /** Chosen from the angle we spend, not from 19 inches. ~39 deg at reach. */
        const val RACK_W = 0.44f
        const val U = RACK_W / 10.9f
        const val ROW_U = 2
        const val H = U * 8
        const val INSET = 0.036f
        const val RAIL = 0.004f
        const val REACH = 0.62f
        /**
         * How far below eye level the panel centre sits: -0.226 at 0.62 m is
         * -20 degrees, so the rack spans about -34 to -6 and stays clear of the
         * world window the horizon occupies. You look DOWN at an instrument,
         * which is also where a rack in a desk actually is.
         */
        const val EYE_DROP = -0.155f
        const val TILT_DEG = 14f
        const val CAP = 0.010f
        const val KNOB_R = 0.013f
        const val HIT_R = 0.026f
        const val DEBOUNCE_MS = 350L
        const val BAR_N = 12
        const val BAR_RED = 10

        const val SEG_W = 0.009f
        const val SEG_H = 0.015f
        const val SEG_T = 0.0016f
        const val SEG_PITCH = 0.0112f

        /** kind (0 = horizontal), x, y — a b c d e f g, the classic order. */
        val SEG_LAYOUT = listOf(
            Triple(0, 0f, SEG_H / 2f),
            Triple(1, SEG_W / 2f - SEG_T / 2f, SEG_H / 4f),
            Triple(1, SEG_W / 2f - SEG_T / 2f, -SEG_H / 4f),
            Triple(0, 0f, -SEG_H / 2f),
            Triple(1, -SEG_W / 2f + SEG_T / 2f, -SEG_H / 4f),
            Triple(1, -SEG_W / 2f + SEG_T / 2f, SEG_H / 4f),
            Triple(0, 0f, 0f),
        )
        val SEG_BITS = mapOf(
            '0' to 0b1111110, '1' to 0b0110000, '2' to 0b1101101, '3' to 0b1111001,
            '4' to 0b0110011, '5' to 0b1011011, '6' to 0b1011111, '7' to 0b1110000,
            '8' to 0b1111111, '9' to 0b1111011, '-' to 0b0000001, ' ' to 0,
        )

        val BWS = listOf(7.8, 10.4, 15.6, 20.8, 31.25, 41.7, 62.5, 125.0, 250.0, 500.0)
        val SFS = listOf(7, 8, 9, 10, 11, 12)
        val CRS = listOf(5, 6, 7, 8)
        /** name, freq, bw, sf, cr */
        val PRESETS = listOf(
            Quint("US915 FAST", 910.525, 62.5, 7, 5),
            Quint("US915 LONG", 910.525, 62.5, 10, 5),
            Quint("EU868", 869.525, 250.0, 11, 5),
            Quint("ANZ915", 915.800, 250.0, 11, 5),
        )
    }
}

/** Five fields, because a preset is a complete parameter set or it is nothing. */
data class Quint(
    val first: String, val second: Double, val third: Double,
    val fourth: Int, val fifth: Int,
)
