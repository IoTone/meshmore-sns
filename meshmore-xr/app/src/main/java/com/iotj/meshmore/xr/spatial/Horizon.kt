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
class Horizon(
    private val session: Session,
    private val theme: Palette,
    /** Needed to build tier R runs, which are real Android Views. */
    private val context: android.content.Context? = null,
) {

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
        /** MeshCore advert type nibble: 0 none, 1 chat, 2 repeater, 3 room, 4 sensor. */
        val type: Int = TYPE_NONE,
        /**
         * When > 0 this mote is not a node but a COUNT: the number of nodes on
         * roughly this bearing that the vertical budget could not label. Its
         * bearing is their mean, so it points at a real place; everything else
         * about it is an aggregate and it is drawn so it cannot be mistaken
         * for a single radio.
         */
        val cluster: Int = 0,
    )

    data class Palette(
        val accent: Int, val alt: Int, val warn: Int, val text: Int,
    )

    /**
     * Labels come from here, not from new panels each build.
     *
     * A horizon rebuild happens whenever mesh membership changes — on a live
     * 350-peer mesh that is every few seconds — and each rebuild was disposing
     * 24 Android Views and their surfaces and creating 24 more. The pool is
     * built once and lent out; a rebuild now costs a setText per label.
     */
    private var labels: LabelPool? = null

    private val entities = mutableListOf<Entity>()
    private val pulses = mutableListOf<Pulse>()
    private val facing = mutableListOf<Facing>()
    private val peers = mutableListOf<Peer>()

    /** Selections raised on the input thread, drained by the frame loop. */
    private val selected = java.util.concurrent.ConcurrentLinkedQueue<Peer>()

    /**
     * Anything that must keep turning toward the viewer, and where it lives.
     * Callsigns need it to stay readable; repeater dishes need it because a
     * bowl seen from behind is just a lump.
     */
    private class Facing(val entity: Entity, val at: Vector3)

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
        /** Where the CALLSIGN hangs — lower than the mote, and what gets veiled. */
        val labelAt: Vector3,
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
        if (labels == null && context != null) {
            labels = LabelPool(session, context).also { it.build(tintOf(theme.text, 0.95f)) }
        }
        labels?.begin()
        var unlabelled = 0

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
            // ELEV_SPAN keeps the ring inside the WORLD WINDOW. The microhud
            // spec reserves +/-10 deg for world content and places its ribbon
            // and stats bands outside that; at 0.35 the outermost lane reached
            // +/-19 deg and node callsigns printed straight through the link
            // readout. atan(R * 0.176 / R) is 10 deg, so the full lane spread
            // now exactly fills the window it was given and no further.
            val v = o.place(bearing, R * dist, elev * R * ELEV_SPAN + EYE_DROP)
            val px = v.x; val py = v.y; val pz = v.z
            val dx = px - o.x; val dy = py - o.y; val dz = pz - o.z
            val range = kotlin.math.sqrt(dx * dx + dy * dy + dz * dz)

            // CONSTANT ANGULAR SIZE (~1.6 deg). A fixed-radius mote subtends 9
            // deg up close and 2 deg far away; distance is already carried by
            // the range bands, so letting it drive apparent size just makes
            // near nodes shout.
            val r = (range * 0.0140f).coerceAtLeast(0.010f)
            val lum = 1f - n.age * 0.72f

            // SILHOUETTE CARRIES TYPE. Until now every node was the same
            // sphere and the only way to tell a repeater from a phone was that
            // some owners happened to type "Repeater" into the name -- which
            // is unreliable, untranslatable, and occasionally just wrong. The
            // protocol says so authoritatively; the shape should too.
            val isRepeater = n.type == TYPE_REPEATER
            val isCluster = n.cluster > 0
            val moteMesh = Prims.build(
                session,
                when {
                    // A CLUSTER must not look like a node, or the count reads as
                    // one radio with a strange name. Coarse facets and half again
                    // the size: bigger than any node and visibly built out of
                    // parts, which is what it is.
                    isCluster -> Prims.mote(r * 1.5f, rings = 3, seg = 5)
                    // Wide and SHALLOW: depth/radius near 0.3 reads as a dish,
                    // near 0.7 reads as a cup. Wider than the mote radius so the
                    // two are distinguishable by silhouette alone at 1.5 degrees,
                    // which is the only cue the brief allows at this size.
                    isRepeater -> Prims.dish(r * 1.65f, r * 0.5f)
                    else -> Prims.mote(r)
                },
            )
            val moteMat = Prims.material(
                session, if (n.located) theme.accent else theme.warn, lum.coerceIn(0.25f, 1f)
            )
            val mote = MeshEntity.create(session, moteMesh, listOf(moteMat)).also {
                it.parent = root
                it.setPose(Pose(Vector3(px, py, pz)), Space.ACTIVITY)
                entities += it
                // A dish only reads as a dish from its open side, so it turns
                // with the viewer exactly as the callsigns do.
                if (isRepeater) facing += Facing(it, Vector3(px, py, pz))
            }

            // Hop count as an equatorial BAND -- structure you see on a sphere
            // rather than a number you parse. A cluster's hop count is an
            // aggregate over nodes at different depths in the mesh, so it gets
            // no band: the band is a fact about ONE radio's path.
            if (n.hops > 1 && !isCluster) {
                val bandMesh = Prims.build(session, Prims.halo(r * 1.55f, r * 0.16f, 24, 4))
                val bandMat = Prims.material(session, theme.alt, 0.75f * lum)
                MeshEntity.create(session, bandMesh, listOf(bandMat)).also {
                    it.parent = root
                    it.setPose(Pose(Vector3(px, py, pz)), Space.ACTIVITY)
                    entities += it
                    // IT HAS TO TURN, like the dish does. A torus lying in a
                    // fixed plane is a ring only from one direction; from
                    // anywhere else it foreshortens to an ellipse, and once the
                    // mote inside it is faint that ellipse reads as a stray ring
                    // floating in the room with nothing to do with the node it
                    // belongs to. It was the only unbilloarded thing left in the
                    // scene and it looked exactly like a bug.
                    facing += Facing(it, Vector3(px, py, pz))
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
            val anchor = Vector3(px, py - r * 2.6f - capH, pz)

            // WHICH MACHINERY DRAWS THIS NAME (T1). Latin goes to the stroke
            // font, which is the only text here with genuine volume and the
            // reason the ring reads as Wipeout. Anything else -- kanji, kana,
            // an accented place name, a turtle -- goes to tier R, where a real
            // face and the platform's fallback chain can actually draw it.
            //
            // Before this, `中継局` became three tofu boxes. Not because we
            // could not render it, but because nothing ever asked whether
            // something other than the stroke font should.
            // A node name is a NAME. It goes to the real font whatever script
            // it is in, so every name on the ring looks like every other name —
            // which was the actual complaint: proportional mixed-case sitting
            // next to all-caps vector strokes read as two applications.
            val tier = TypeTier.of(n.name, TypeTier.Kind.NAME)
            // Clipped to the SAME budget MeshNodes laid out against. The layout
            // reserves space for a label of MAX_LABEL_CELLS; drawing a wider one
            // puts it through the neighbours the layout just carefully cleared.
            val shown = TypeTier.clip(n.name, MeshNodes.MAX_LABEL_CELLS)
            val pooled = tier == TypeTier.Tier.RUN && !isCluster &&
                labels?.place(shown, anchor, capH) == true
            val txt: Entity = if (pooled) {
                // The pool owns the entity and its billboarding. Peer.label is
                // only used for the veil, and a pooled label is shared — dimming
                // it would dim whichever node borrows it next. Point the peer at
                // its MOTE instead, which is per-node and already alpha-managed.
                mote
            } else {
                // No pool, no context, or the pool ran dry: a cluster count and
                // anything unlabelled still needs SOMETHING, and tier S is the
                // path that costs one mesh rather than one Android View.
                if (tier == TypeTier.Tier.RUN && !isCluster) unlabelled++
                strokeLabel(root, n, capH, lum, anchor)
            }
            val cs = Callsign.render(n.name)

            // PICTOGRAPH BADGE — the emoji we could not draw, acknowledged.
            // Parented to the label so it inherits the billboard rotation for
            // free and keeps its offset in the label's own frame; a sibling in
            // world space would need its offset re-rotated every frame.
            //
            // TIER S ONLY. The badge exists because a stroke font cannot draw a
            // turtle; tier R draws the turtle. Raising it there would announce a
            // loss that did not happen and put a gem next to the emoji it stands
            // for.
            if (cs.badge && tier == TypeTier.Tier.STROKE) {
                val g = capH * 0.42f
                // rings=2, seg=4 makes an octahedron: a faceted gem, clearly a
                // MARK rather than another letter, and it reads as volume from
                // any angle even before the billboard turns it.
                val bMesh = Prims.build(session, Prims.mote(g, rings = 2, seg = 4))
                val bMat = Prims.material(session, theme.alt, 0.85f * lum)
                MeshEntity.create(session, bMesh, listOf(bMat)).also {
                    it.parent = txt
                    val x = -(Glyphs.width(cs.text, capH) / 2f + g * 1.9f)
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
            val det = if (isCluster) {
                // Say what it is, in words. "+19" alone is ambiguous -- it could
                // be a channel, a margin, a signal figure.
                "%d NODES NOT SHOWN  NEAR %.1fKM".format(n.cluster, dist * 5.0f)
            } else {
                "%s%d HOP  %.1fKM  %s".format(
                    if (full.isNotEmpty()) "$full   " else "",
                    n.hops, dist * 5.0f, if (n.age < 0.34f) "LIVE" else "STALE",
                )
            }
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
                at = Vector3(px, py, pz), labelAt = anchor, dist = dist, bearing = bearing,
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
        if (unlabelled > 0) {
            Log.i(TAG, "[horizon] $unlabelled node(s) fell back to stroke labels — pool exhausted")
        }
        Log.i(TAG, "[horizon] built ${entities.size} entities for ${nodes.size} nodes " +
            "(${nodes.count { it.type == TYPE_REPEATER }} repeaters, " +
            "${nodes.count { it.type == TYPE_CHAT }} chat, " +
            "${nodes.count { it.type !in listOf(TYPE_REPEATER, TYPE_CHAT) }} other)")
    }

    /**
     * HOVER and SELECT. Runs on the input thread, so it does only what is safe
     * there: alpha and scale on entities that already exist. Anything needing a
     * coroutine (building a pulse) is queued for [drainSelections].
     */
    /**
     * TIER S — the extruded stroke label, and the fallback when a run will not
     * build. Folding and tofu live here and only here: a tofu box is an honest
     * report from a stroke font, which is correct on this path and would be a
     * product failure on the other one.
     */
    private suspend fun strokeLabel(
        root: Entity, n: Node, capH: Float, lum: Float, anchor: Vector3,
    ): Entity {
        val cs = Callsign.render(n.name)
        if (cs.badge || cs.tofu > 0 || cs.truncated) {
            Log.i(TAG, "[callsign] ${n.name} -> ${cs.text} " +
                "badge=${cs.badge} tofu=${cs.tofu} cut=${cs.truncated}")
        }
        val label = if (n.located) cs.text else cs.text + " ?"
        val mesh = Prims.build(session, Glyphs.text(label, capH))
        val mat = Prims.material(session, theme.text, (0.45f + 0.55f * lum))
        return MeshEntity.create(session, mesh, listOf(mat)).also {
            it.parent = root
            it.setPose(Pose(anchor), Space.ACTIVITY)
            entities += it
            facing += Facing(it, anchor)
        }
    }

    /** Theme colour at [a] alpha, as the ARGB int a TextView wants. */
    private fun tintOf(rgb: Int, a: Float): Int =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

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
                Reach.consumed()
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
        // A pointer resting on a node is a hand that is reaching, not signing.
        Reach.setHovering(peers.any { it.pointers.isNotEmpty() })
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
            // Label alpha is NOT written here. veil() owns it and runs every
            // frame; two writers on one property means whichever fired last
            // wins, and the hover events fire at transitions while the veil
            // fires continuously — so hovering inside a HUD band would light
            // the callsign back up and leave it lit.
            InputEvent.Action.HOVER_ENTER -> {
                p.mote.setScale(HOVER_SCALE)
                p.mote.setAlpha(1f)
            }
            InputEvent.Action.HOVER_EXIT -> {
                p.mote.setScale(1f)
                p.mote.setAlpha(p.baseAlpha)
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
    /**
     * Raised when a CLUSTER mote is pinched. A count is the one mote whose
     * selection cannot mean "show me this node" — there is no node — so the
     * host opens a menu on it instead of the detail line.
     */
    var onCluster: ((Node, Vector3) -> Unit)? = null

    suspend fun drainSelections(o: Stage.Origin) {
        while (true) {
            val p = selected.poll() ?: return
            if (p.node.cluster > 0) {
                onCluster?.invoke(p.node, p.at)
                continue
            }
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
        labels?.faceViewer(head)
        facing.forEach { l ->
            val dx = head.x - l.at.x
            val dz = head.z - l.at.z
            if (dx * dx + dz * dz < 1e-6f) return@forEach
            val yaw = Math.toDegrees(kotlin.math.atan2(dx, dz).toDouble()).toFloat()
            l.entity.setPose(
                Pose(l.at, Quaternion.fromEulerAngles(0f, yaw, 0f)), Space.ACTIVITY,
            )
        }
    }

    /**
     * FADE CALLSIGNS THAT DRIFT UNDER THE MICROHUD.
     *
     * The HUD is view-fixed and the mesh is world-fixed, so the two cross
     * whenever the head pitches — no amount of pinning prevents it, and the
     * result is a node name printed through the link readout with both
     * illegible. One of them has to give way, and it is the callsign: the HUD
     * band is a fixed, tiny, known strip that the user relies on being able to
     * read at a glance, while a callsign that has wandered into it will wander
     * out again the moment they look level.
     *
     * The MOTE is left alone deliberately. Losing the name where it is
     * unreadable anyway costs nothing; losing the dot would punch holes in the
     * ring and misrepresent where the mesh is. You lose the label, not the node.
     *
     * The view angle is (world elevation - head pitch), which is exactly how
     * Hud.place positions a band: a mark at local y sits at pitch + atan(y/D).
     * The two therefore agree by construction rather than by tuning.
     */
    fun veil(head: Pose) {
        val t = head.translation
        val q = head.rotation
        val fy = -2f * (q.y * q.z - q.w * q.x)
        val pitchDeg = Math.toDegrees(kotlin.math.asin(fy.coerceIn(-1f, 1f)).toDouble()).toFloat()
        var veiled = 0
        peers.forEach { p ->
            val dx = p.labelAt.x - t.x
            val dy = p.labelAt.y - t.y
            val dz = p.labelAt.z - t.z
            val r = kotlin.math.sqrt(dx * dx + dy * dy + dz * dz)
            if (r < 1e-3f) return@forEach
            val view = Math.toDegrees(
                kotlin.math.asin((dy / r).coerceIn(-1f, 1f)).toDouble()
            ).toFloat() - pitchDeg
            val a = kotlin.math.abs(view)
            val hidden = a >= Hud.BAND_INNER_DEG && a <= Hud.BAND_OUTER_DEG
            val base = if (p.hovered) 1f else p.baseAlpha
            p.label.setAlpha(if (hidden) base * VEIL_ALPHA else base)
            if (hidden) veiled++
        }
        // Logged on CHANGE only. A per-frame line would be 30 Hz of noise, but
        // without any line at all "the bands are clear" is indistinguishable
        // from "the veil never ran", and those look identical in a screenshot.
        if (veiled != lastVeiled) {
            lastVeiled = veiled
            Log.i(TAG, "[horizon] veiled $veiled callsign(s) under the hud (pitch %.0f°)"
                .format(pitchDeg))
        }
    }

    private var lastVeiled = -1

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

    /** The pool outlives a rebuild; only a teardown of the surface disposes it. */
    fun dispose() {
        clear()
        labels?.clear()
        labels = null
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
        facing.clear()
        peers.clear()
        selected.clear()
        pulses.forEach { runCatching { it.entity.dispose() } }
        pulses.clear()
    }

    companion object {
        private const val TAG = "MeshmoreXR"
        /** HORIZON radius, metres. Body-locked in the design; world-fixed for P1. */
        const val R = 2.5f

        // MeshCore advert types. The protocol calls the phone/glasses role
        // CHAT while the product calls it COMPANION -- the brief is explicit
        // that the two must not drift in code, so the protocol name stays here
        // and the product name stays in the UI.
        /** Vertical half-span of the ring, as a fraction of R. 0.176 = 10 deg. */
        const val ELEV_SPAN = 0.176f

        const val TYPE_NONE = 0
        const val TYPE_CHAT = 1
        const val TYPE_REPEATER = 2
        const val TYPE_ROOM = 3
        const val TYPE_SENSOR = 4
        /** Hover growth. Big enough to be unmistakable, small enough not to jump. */
        /**
         * How far a veiled callsign drops. Not zero: it still reads as "a node
         * is there, its name is behind the instrument", which is true and is
         * information. Disappearing entirely would look like the mesh thinned
         * out every time the user tipped their head.
         */
        private const val VEIL_ALPHA = 0.12f
        private const val HOVER_SCALE = 1.35f
        /** How long hover survives losing every pointer. Covers tracking jitter. */
        private const val HOVER_GRACE_MS = 180L
        /** Two hands, one pinch: ignore a second UP inside this window. */
        private const val SELECT_DEBOUNCE_MS = 350L
        /** The shell sits at and below eye level; the forward arc stays clear. */
        const val EYE_DROP = -0.30f
    }
}
