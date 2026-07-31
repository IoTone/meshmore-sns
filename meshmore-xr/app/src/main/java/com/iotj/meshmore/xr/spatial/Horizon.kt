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
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * S1 HORIZON — the always-on mesh, as geometry in the room.
 *
 * Not a screen, not a panel, not a list. A volumetric shell around the user:
 * every peer at its true bearing, its true elevation, and its true distance,
 * with the forward arc deliberately left clear because that window belongs to
 * the world.
 *
 * Everything here is a MeshEntity built from Prims. Nothing is Compose.
 */
class Horizon(private val session: Session, private val theme: Palette) {

    data class Node(
        val name: String,
        val bearingRad: Float,
        val elev: Float,          // -1..1, fraction of the shell's vertical span
        val dist: Float,          // 0..1, fraction of the outer range band
        val age: Float,           // 0 = just heard, 1 = stale
        val located: Boolean,
        val hops: Int,
        /** Real altitude in metres from telemetry, or null when unknown. */
        val altM: Double? = null,
    )

    data class Palette(
        val accent: Int, val alt: Int, val warn: Int, val text: Int,
    )

    private val entities = mutableListOf<Entity>()
    private val pulses = mutableListOf<Pulse>()
    private val labels = mutableListOf<Label>()
    private val peers = mutableListOf<Peer>()

    /** Selections raised on the input thread, drained by the frame loop. */
    private val selected = java.util.concurrent.ConcurrentLinkedQueue<Peer>()

    /** A callsign and the point it is anchored to, for per-frame billboarding. */
    private class Label(val entity: Entity, val at: Vector3)

    /**
     * One touchable node. Everything here is built up front and then only
     * *toggled* — no geometry is created in response to input, because
     * `Prims.material` is a suspend call and an input callback is not a
     * coroutine, and because building a mesh mid-gesture hitches the frame
     * exactly when the user is watching for a response.
     */
    private class Peer(
        val node: Node,
        val mote: MeshEntity,
        val label: Entity,
        val detail: MeshEntity,
        val at: Vector3,
        val dist: Float,
        val bearing: Float,
        val baseAlpha: Float,
        var open: Boolean = false,
    ) {
        /** Which pointers are currently on this peer. BOTH hands emit rays. */
        val pointers = mutableSetOf<String>()
        var hovered = false
        var exitAt = 0L
        var lastSelect = 0L
    }

    private class Pulse(val entity: MeshEntity, val base: Float, var life: Float = 1f)

    suspend fun build(nodes: List<Node>, o: Stage.Origin, floorY: Float) {
        clear()
        val root = session.scene.activitySpace

        // --- range halos: real tori, lying flat below eye level --------------
        // Distance is read from which band a mote sits in, so the bands are the
        // scale and have to be legible from any angle -- hence torus, not disc.
        listOf(0.40f, 0.70f, 1.00f).forEachIndexed { i, f ->
            val mesh = Prims.build(session, Prims.halo(R * f, 0.014f))
            val mat = Prims.material(session, theme.accent, 0.30f + i * 0.06f)
            MeshEntity.create(session, mesh, listOf(mat)).also {
                it.parent = root
                it.setPose(Pose(o.place(0f, 0f, EYE_DROP)), Space.ACTIVITY)
                entities += it
            }
        }

        // --- the peers -------------------------------------------------------
        nodes.forEach { n ->
            // A node with no position estimate MUST NOT be given a fake bearing.
            // It parks in a dedicated unlocated arc behind the dominant shoulder.
            val bearing = if (n.located) n.bearingRad else (PI * 0.78f).toFloat()
            val dist = if (n.located) n.dist else 0.42f
            val elev = if (n.located) n.elev else -0.3f

            // Bearings are measured from the user's LAUNCH FACING, so the mesh
            // wraps the body rather than the tracker's arbitrary origin.
            val v = o.place(bearing, R * dist, elev * R * 0.35f + EYE_DROP)
            val px = v.x; val py = v.y; val pz = v.z
            val dx = px - o.x; val dy = py - o.y; val dz = pz - o.z
            val range = kotlin.math.sqrt(dx * dx + dy * dy + dz * dz)

            // CONSTANT ANGULAR SIZE (~1.6 deg). A fixed-radius mote subtends 9
            // deg up close and 2 deg far away; distance is already carried by
            // the range bands, so letting it drive apparent size just makes
            // near nodes shout.
            val r = (range * 0.0140f).coerceAtLeast(0.010f)
            val lum = 1f - n.age * 0.72f

            val moteMesh = Prims.build(session, Prims.mote(r))
            val moteMat = Prims.material(
                session, if (n.located) theme.accent else theme.warn, lum.coerceIn(0.25f, 1f)
            )
            val mote = MeshEntity.create(session, moteMesh, listOf(moteMat)).also {
                it.parent = root
                it.setPose(Pose(Vector3(px, py, pz)), Space.ACTIVITY)
                entities += it
            }

            // Hop count as an equatorial BAND -- structure you see on a sphere
            // rather than a number you parse.
            if (n.hops > 1) {
                val bandMesh = Prims.build(session, Prims.halo(r * 1.55f, r * 0.16f, 24, 4))
                val bandMat = Prims.material(session, theme.alt, 0.75f * lum)
                MeshEntity.create(session, bandMesh, listOf(bandMat)).also {
                    it.parent = root
                    it.setPose(Pose(Vector3(px, py, pz)), Space.ACTIVITY)
                    entities += it
                }
            }

            // CALLSIGN — extruded stroke glyphs, so the label is made of light
            // in the room rather than printed on a surface. Sized by VISUAL
            // ANGLE (~1.3 deg cap height at its own range), never in absolute
            // metres, or distant nodes become unreadable.
            val capH = range * 0.0227f
            // Node names are arbitrary user text -- emoji, fullwidth kana,
            // accents, or nothing but a turtle. Callsign folds that into
            // something the stroke font can actually draw and tells us whether
            // to raise a badge for what it had to drop.
            val cs = Callsign.render(n.name)
            if (cs.badge || cs.tofu > 0 || cs.truncated) {
                Log.i(TAG, "[callsign] ${n.name} -> ${cs.text} " +
                    "badge=${cs.badge} tofu=${cs.tofu} cut=${cs.truncated}")
            }
            val label = if (n.located) cs.text else cs.text + " ?"
            val txtMesh = Prims.build(session, Glyphs.text(label, capH))
            val txtMat = Prims.material(session, theme.text, (0.45f + 0.55f * lum))
            val anchor = Vector3(px, py - r * 2.6f - capH, pz)
            val txt = MeshEntity.create(session, txtMesh, listOf(txtMat)).also {
                it.parent = root
                it.setPose(Pose(anchor), Space.ACTIVITY)
                entities += it
                labels += Label(it, anchor)
            }

            // PICTOGRAPH BADGE — the emoji we could not draw, acknowledged.
            // Parented to the label so it inherits the billboard rotation for
            // free and keeps its offset in the label's own frame; a sibling in
            // world space would need its offset re-rotated every frame.
            if (cs.badge) {
                val g = capH * 0.42f
                // rings=2, seg=4 makes an octahedron: a faceted gem, clearly a
                // MARK rather than another letter, and it reads as volume from
                // any angle even before the billboard turns it.
                val bMesh = Prims.build(session, Prims.mote(g, rings = 2, seg = 4))
                val bMat = Prims.material(session, theme.alt, 0.85f * lum)
                MeshEntity.create(session, bMesh, listOf(bMat)).also {
                    it.parent = txt
                    val x = -(Glyphs.width(label, capH) / 2f + g * 1.9f)
                    it.setPose(Pose(Vector3(x, capH * 0.5f, 0f)), Space.PARENT)
                    entities += it
                }
            }

            // NODE DETAIL — hidden until selected. Stroke glyphs, so selection
            // does not drag in the whole tier-R font pipeline for three numbers.
            // The horizon label is clipped to stay glanceable; the detail line
            // is where the full name lives, because exactly one node is open at
            // a time and the width costs nothing there. Truncating in both
            // places would mean the app never shows you what a node is called.
            val full = if (cs.truncated) Callsign.render(n.name, maxGlyphs = 40).text else ""
            val det = "%s%d HOP  %.1fKM  %s".format(
                if (full.isNotEmpty()) "$full   " else "",
                n.hops, dist * 5.0f, if (n.age < 0.34f) "LIVE" else "STALE",
            )
            val detMesh = Prims.build(session, Glyphs.text(det, capH * 0.78f))
            val detMat = Prims.material(session, theme.alt, 0.9f)
            val detail = MeshEntity.create(session, detMesh, listOf(detMat)).also {
                it.parent = txt          // inherits the billboard rotation
                it.setPose(Pose(Vector3(0f, -capH * 1.5f, 0f)), Space.PARENT)
                // setEnabled, NOT setAlpha(0). Alpha propagates down the
                // subtree, so the hover handler writing the LABEL's alpha also
                // rewrites this child's -- and the detail reveals itself the
                // moment the pointer passes anywhere near, with no selection.
                it.setEnabled(false)
                entities += it
            }

            // HIT PROXY — an invisible sphere ~3 deg across around the mote.
            // The mote itself is ~1.6 deg, which clears the 0.6 deg *visibility*
            // floor but is well under the ~2 deg the brief requires of anything
            // REACHED FOR (L7). Aiming a gaze ray at a 1.6 deg target is a test
            // of patience, so the thing you point at is deliberately bigger than
            // the thing you see.
            //
            // Alpha 0.02 rather than 0: a fully transparent entity is a
            // reasonable thing for a renderer to skip, and being skipped means
            // being unhittable. 0.02 emits nothing perceptible on an additive
            // display and keeps it in the pipeline.
            val proxy = MeshEntity.create(
                session, Prims.build(session, Prims.mote(r * 2.2f, 5, 8)), listOf(moteMat),
            ).also {
                it.parent = root
                it.setPose(Pose(Vector3(px, py, pz)), Space.ACTIVITY)
                it.setAlpha(0.02f)
                entities += it
            }

            val peer = Peer(
                node = n, mote = mote, label = txt, detail = detail,
                at = Vector3(px, py, pz), dist = dist, bearing = bearing,
                baseAlpha = lum.coerceIn(0.25f, 1f),
            )
            peers += peer
            runCatching {
                proxy.addComponent(
                    InteractableComponent.create(session) { ev -> onInput(peer, ev) },
                )
            }.onFailure { Log.w(TAG, "[horizon] no input on ${n.name}: $it") }

            // ALTITUDE, and only altitude. This caret used to fire on `elev`,
            // which is now also the de-occlusion lane -- pointing it at a lane
            // offset would turn a legibility trick into a claim that the node
            // is up a hill. It is drawn ONLY for a node with real telemetry
            // altitude, and it comes with the figure in metres, because "above
            // you" without a number is the kind of half-fact that gets someone
            // walking uphill for no reason.
            if (n.altM != null) {
                val up = n.altM >= 0
                val aMesh = Prims.build(session, Prims.caret(r * 0.9f, r * 1.6f))
                val aMat = Prims.material(session, theme.alt, 0.9f * lum)
                MeshEntity.create(session, aMesh, listOf(aMat)).also {
                    it.parent = root
                    it.setPose(
                        Pose(Vector3(px, py + if (up) r * 2.4f else -r * 3.8f, pz)),
                        Space.ACTIVITY,
                    )
                    entities += it
                }
                val txtAlt = "%.0fM".format(n.altM)
                val altMesh = Prims.build(session, Glyphs.text(txtAlt, capH * 0.72f))
                MeshEntity.create(
                    session, altMesh, listOf(Prims.material(session, theme.alt, 0.85f * lum)),
                ).also {
                    it.parent = txt          // billboards with the callsign
                    it.setPose(Pose(Vector3(0f, capH * 1.35f, 0f)), Space.PARENT)
                    entities += it
                }
            }

        }
        Log.i(TAG, "[horizon] built ${entities.size} entities for ${nodes.size} nodes")
    }

    /**
     * HOVER and SELECT. Runs on the input thread, so it does only what is safe
     * there: alpha and scale on entities that already exist. Anything needing a
     * coroutine (building a pulse) is queued for [drainSelections].
     */
    private fun onInput(p: Peer, ev: InputEvent) {
        // Log EVERY event, not just selections. The Aura reports only
        // hand_tracking -- no controller, no eye tracking -- and a lower
        // xr.api.spatial level than the emulator, so it is an open question
        // whether a ray reaches these entities at all. Without a hover line the
        // failure "no pointer ever arrives" is indistinguishable from "the
        // pinch was not recognised", and those need completely different fixes.
        if (ev.action != InputEvent.Action.HOVER_MOVE) {
            Log.i(TAG, "[input] ${ev.action} on ${p.node.name} src=${ev.source} ptr=${ev.pointerType}")
        }
        val key = ev.pointerType.toString()
        when (ev.action) {
            InputEvent.Action.HOVER_ENTER, InputEvent.Action.HOVER_MOVE -> p.pointers += key
            InputEvent.Action.HOVER_EXIT -> {
                p.pointers -= key
                p.exitAt = android.os.SystemClock.uptimeMillis()
            }
            InputEvent.Action.UP -> {
                // DEBOUNCE. Both hands are tracked, so a single pinch can arrive
                // as two UP events -- and against a toggle that means the node
                // opens and immediately closes again, which reads as "selection
                // does not work". Measured on device: gate-cam toggled four
                // times, twice inside 500 ms, for what was meant to be one or
                // two deliberate selections.
                val now = android.os.SystemClock.uptimeMillis()
                if (now - p.lastSelect < SELECT_DEBOUNCE_MS) {
                    Log.i(TAG, "[input] debounced repeat UP on ${p.node.name}")
                    return
                }
                p.lastSelect = now
                select(p)
            }
            else -> Unit
        }
    }

    /** Toggle a node open. Shared by real input and by [selfTest]. */
    private fun select(p: Peer) {
        p.open = !p.open
        p.detail.setEnabled(p.open)
        if (p.open) selected.add(p)
        Log.i(TAG, "[horizon] select ${p.node.name} open=${p.open}")
    }

    /**
     * Reconcile hover from pointer state, with a release grace period.
     *
     * Hand tracking jitters, and a ray that wobbles a few millimetres across a
     * small target produces a stream of ENTER/EXIT pairs -- 42% of measured
     * hover episodes lasted under 150 ms, three under 50 ms. Driving the visual
     * straight off those events makes the mote strobe between its two sizes.
     * So hover is a *state* derived from which pointers are on the target, and
     * losing the last one starts a timer rather than ending the hover.
     */
    private fun reconcileHover() {
        val now = android.os.SystemClock.uptimeMillis()
        peers.forEach { p ->
            val want = p.pointers.isNotEmpty() ||
                (p.hovered && now - p.exitAt < HOVER_GRACE_MS)
            if (want != p.hovered) {
                p.hovered = want
                apply(p, if (want) InputEvent.Action.HOVER_ENTER else InputEvent.Action.HOVER_EXIT)
            }
        }
    }

    private fun apply(p: Peer, action: InputEvent.Action) {
        when (action) {
            InputEvent.Action.HOVER_ENTER -> {
                p.mote.setScale(HOVER_SCALE)
                p.mote.setAlpha(1f)
                p.label.setAlpha(1f)
            }
            InputEvent.Action.HOVER_EXIT -> {
                p.mote.setScale(1f)
                p.mote.setAlpha(p.baseAlpha)
                p.label.setAlpha(p.baseAlpha)
            }
            else -> Unit
        }
    }

    /**
     * DEBUG ONLY — drive the response path with no pointer.
     *
     * `adb shell input` cannot reach the XR pointer: spatial input arrives from
     * the runtime's hand/controller ray, not from a touch on display 0. That
     * leaves the hit test unverifiable from a script, but everything downstream
     * of it -- hover growth, the detail reveal, the pulse -- is just entity
     * state, and this exercises exactly that. It splits the risk: if this looks
     * right, the only thing left to confirm on a head is whether the ray lands.
     *
     *     adb shell am start -n .../.MainActivity --ez selftest true
     */
    suspend fun selfTest(o: Stage.Origin) {
        // EVERY peer, not one: only ~2 of 11 nodes fall inside a 61 deg FOV, so
        // driving a single one has a 1-in-6 chance of being visible to whoever
        // is checking. Driving all of them means whatever is in frame responds.
        val live = peers.filter { it.node.located }
        if (live.isEmpty()) return
        Log.i(TAG, "[selftest] driving ${live.size} peers")
        // Drive the pointer SET, not apply(), so hover goes through the same
        // reconcile + grace path real hands do. A self-test that routes around
        // the state machine tests nothing that can break.
        live.forEach { it.pointers += "SELFTEST" }
        kotlinx.coroutines.delay(1800)
        live.forEach { select(it) }
        drainSelections(o)
        kotlinx.coroutines.delay(3000)
        live.forEach { select(it); it.pointers -= "SELFTEST" }
        Log.i(TAG, "[selftest] done")
    }

    /**
     * Fire the ring for anything selected since the last frame. Called from the
     * frame loop because [pulse] is suspend and the input callback is not.
     */
    suspend fun drainSelections(o: Stage.Origin) {
        while (true) {
            val p = selected.poll() ?: return
            pulse(p.bearing, p.dist, o)
        }
    }

    /** PULSE — the mesh visibly breathing. One expanding ring per packet. */
    suspend fun pulse(bearingRad: Float, dist: Float, o: Stage.Origin) {
        val v = o.place(bearingRad, R * dist, EYE_DROP)
        val r0 = (R * dist * 0.016f).coerceAtLeast(0.012f)
        val mesh = Prims.build(session, Prims.halo(r0, r0 * 0.28f, 24, 4))
        val mat = Prims.material(session, theme.accent, 0.55f)
        val e = MeshEntity.create(session, mesh, listOf(mat))
        e.parent = session.scene.activitySpace
        e.setPose(Pose(v), Space.ACTIVITY)
        pulses += Pulse(e, r0)
    }

    /**
     * BILLBOARD the callsigns at [head] (activity space).
     *
     * Yaw only. A full look-at billboard would also pitch and roll the text to
     * square it with the eye, and text that rolls as you tilt your head is both
     * harder to read and a reliable way to make people feel ill. Upright and
     * turned toward the viewer is what signage does, and it is what reads.
     *
     * The yaw has to match the glyph plane. Glyphs are built in XY with the pen
     * advancing along +X and the tube section straddling z=0, so the readable
     * FACE is the +Z side. A yaw of theta about +Y sends +Z to (sin t, 0, cos t),
     * and we want that pointing at the viewer, so theta = atan2(dx, dz).
     *
     * The tempting wrong answer is atan2(-dx, dz), which is what the ring-facing
     * version this replaces effectively used. That NEGATES the angle rather than
     * flipping it, so it is exactly right for a label straight ahead (dx = 0)
     * and progressively wrong off-axis -- edge labels end up showing their back,
     * i.e. mirrored text. Anything checked only while looking at it directly
     * will pass.
     */
    fun faceViewer(head: Vector3) {
        labels.forEach { l ->
            val dx = head.x - l.at.x
            val dz = head.z - l.at.z
            if (dx * dx + dz * dz < 1e-6f) return@forEach
            val yaw = Math.toDegrees(kotlin.math.atan2(dx, dz).toDouble()).toFloat()
            l.entity.setPose(
                Pose(l.at, Quaternion.fromEulerAngles(0f, yaw, 0f)), Space.ACTIVITY,
            )
        }
    }

    /** Drive the pulses. Called from a frame loop; cheap and allocation-free. */
    fun tick(dt: Float) {
        reconcileHover()
        val it = pulses.iterator()
        while (it.hasNext()) {
            val p = it.next()
            p.life -= dt / 0.7f
            if (p.life <= 0f) {
                runCatching { p.entity.dispose() }
                it.remove()
            } else {
                val grow = 1f + (1f - p.life) * 2.6f
                p.entity.setScale(grow)
                p.entity.setAlpha(p.life * 0.55f)
            }
        }
    }

    fun clear() {
        // DETACH BEFORE DISPOSING, or this double-frees.
        //
        // The badge and the detail line are parented to the callsign so they
        // inherit its billboard rotation -- but all three are also in this
        // list. Disposing a parent disposes its children, so by the time the
        // loop reached the child it had already been freed, and the native
        // allocator aborted the whole process:
        //
        //   Scudo ERROR: invalid chunk state when deallocating address ...
        //
        // It is a NATIVE abort, so the runCatching below never saw it -- there
        // is no Java exception to catch, the process is simply gone. And it
        // only fires on a REBUILD, which is why it looked like "crashes after
        // loading some nodes": every membership change ran this path.
        //
        // Breaking the parent links first makes every entity an independent
        // root, so each is freed exactly once.
        entities.forEach { runCatching { it.parent = null } }
        entities.forEach { runCatching { it.dispose() } }
        entities.clear()
        // Labels hold the same entities; drop the references or faceViewer()
        // would keep posing disposed handles every frame after a rebuild.
        labels.clear()
        peers.clear()
        selected.clear()
        pulses.forEach { runCatching { it.entity.dispose() } }
        pulses.clear()
    }

    companion object {
        private const val TAG = "MeshmoreXR"
        /** HORIZON radius, metres. Body-locked in the design; world-fixed for P1. */
        const val R = 2.5f
        /** Hover growth. Big enough to be unmistakable, small enough not to jump. */
        private const val HOVER_SCALE = 1.35f
        /** How long hover survives losing every pointer. Covers tracking jitter. */
        private const val HOVER_GRACE_MS = 180L
        /** Two hands, one pinch: ignore a second UP inside this window. */
        private const val SELECT_DEBOUNCE_MS = 350L
        /** The shell sits at and below eye level; the forward arc stays clear. */
        const val EYE_DROP = -0.30f
    }
}
