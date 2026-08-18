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
    private var theme: Palette,
    /** Needed to build tier R runs, which are real Android Views. */
    private val context: android.content.Context? = null,
    /**
     * What a node is made of in the current theme.
     *
     * Passed at construction rather than read from a global, because the
     * horizon rebuilds on mesh traffic and a symbol that changed under it
     * mid-build would produce a ring of half one kind and half the other. A
     * theme change rebuilds the horizon anyway.
     */
    private var symbol: Theme.Symbol = Theme.Symbol.SOLID,
    /**
     * WHERE THE RING GOES, per theme — see [Theme.Frame].
     *
     * Passed at construction for the same reason [symbol] is: a posture that
     * changed mid-build would leave half the peers on the horizon and half on
     * the table. A theme change rebuilds the horizon anyway.
     */
    private var posture: Theme.Posture = Theme.Posture.FIELD,
    private var active: Boolean = false,
) {

    /** The ring's geometry for this theme's posture. */
    private var frame = Theme.frameFor(posture, active)

    /**
     * ADOPT A NEW THEME'S STRUCTURE, not just its colours.
     *
     * [symbol] and [posture] arrive as constructor arguments because a rebuild
     * must not change shape halfway through — and the note above says a theme
     * change rebuilds the horizon anyway. It does not. Choosing a theme in the
     * picker calls `Ink.retint` and nothing else, so it repaints every material
     * and leaves every SHAPE and every POSITION exactly as the launch theme
     * built them.
     *
     * The effect was that eight of the nine themes' structural differences were
     * invisible unless you launched into one with `--es theme`: pick BIOLUME
     * from the picker and you got BIOLUME's greens on HALO's discs, standing on
     * HALO's floor, at HALO's horizon distance. Which is exactly the complaint
     * that started the whole nine-themes-not-nine-palettes effort.
     *
     * So the two facts become settable, and the caller follows with a rebuild.
     * They stay private and change together, because a symbol without its
     * posture is the half-applied theme this method exists to end.
     */
    fun retheme(
        symbol: Theme.Symbol,
        posture: Theme.Posture,
        active: Boolean,
        palette: Palette,
    ) {
        // THE PALETTE TOO, and this is the half that was missed.
        //
        // Ink.retint repaints every material that ALREADY EXISTS, which is what
        // makes a theme change instant. But a retheme is followed by a REBUILD —
        // a mote's silhouette is baked into its mesh, so the ring has to be made
        // again — and every material made during that rebuild was mixed from the
        // palette this object was CONSTRUCTED with. The launch one.
        //
        // So the sequence was: repaint everything correctly, then immediately
        // rebuild it all in the old colours. Switching to HALO left the mesh
        // wearing whatever had been on before, which is precisely how it was
        // reported, and it looked like the theme change had not happened at all.
        this.theme = palette
        this.symbol = symbol
        this.posture = posture
        this.active = active
        this.frame = Theme.frameFor(posture, active)
        Log.i(TAG, "[horizon] retheme -> $symbol / $posture" + if (active) " / ACTIVE" else "")
    }

    /**
     * The ring's centre in activity space.
     *
     * FIELD leaves it on the wearer, which is what "horizon" means — you stand
     * in the middle of it. TABLETOP pushes it out in front, because a model you
     * are standing inside is not a model, it is a room.
     */
    /**
     * A REAL TABLE, when the room has offered one — see [TableAnchor].
     *
     * Overrides the body-relative centre for TABLETOP only. Set by the host
     * when the anchor lands, which is also when it triggers a rebuild; null
     * means "no table yet, or none here", and the guessed position stands.
     */
    var tableAt: Vector3? = null

    private fun centre(o: Stage.Origin): Triple<Float, Float, Float> {
        // The measured table beats the assumed one. Only TABLETOP asks for a
        // table, so only TABLETOP can be moved onto it.
        tableAt?.takeIf { posture == Theme.Posture.TABLETOP }?.let {
            // CANCEL THE ASSUMED DROP. `at()` adds frame.drop — the -0.42 m
            // guess at where a table is under a seated wearer — to every
            // height. Once the table's REAL height is known that guess must
            // come back out, or the model is placed 42 cm into the furniture.
            // What replaces it is a couple of centimetres of clearance so the
            // diorama rests ON the surface rather than intersecting it.
            return Triple(it.x, it.y + TABLE_LIFT - frame.drop, it.z)
        }
        if (frame.forward == 0f) return Triple(o.x, o.y, o.z)
        val c = o.place(0f, frame.forward, 0f)
        return Triple(c.x, c.y, c.z)
    }

    /** [Stage.Origin.place], about this posture's centre rather than the wearer. */
    private fun at(o: Stage.Origin, bearing: Float, radius: Float, height: Float): Vector3 {
        val (cx, cy, cz) = centre(o)
        val v = o.place(bearing, radius, height)
        return Vector3(v.x + (cx - o.x), v.y + (cy - o.y), v.z + (cz - o.z))
    }

    /**
     * The same placement, from CARTESIAN map coordinates instead of polar ones.
     *
     * [at] takes a bearing and a radius because that is what a ring is. The
     * callout rack is not on the ring — its handles sit at fixed lateral
     * offsets beside the map, which is a position no bearing describes. Same
     * frame, same yaw, same centre; only the input differs.
     *
     * u is lateral (right positive), v is forward, both in the map's own plane
     * before the wearer's yaw is applied. Derived from [Stage.Origin.place], so
     * u = sin(b)·r and v = cos(b)·r land exactly where `at(o, b, r, h)` does.
     */
    private fun fromLocal(o: Stage.Origin, u: Float, v: Float, height: Float): Vector3 {
        val (cx, cy, cz) = centre(o)
        val cy0 = kotlin.math.cos(o.yawRad)
        val sy0 = kotlin.math.sin(o.yawRad)
        return Vector3(cx + u * cy0 + v * sy0, cy + height, cz + u * sy0 - v * cy0)
    }

    data class Node(
        val name: String,
        /**
         * WHO THIS IS, not just what it is called. Names are user-supplied and
         * duplicated; every per-node ACTION keys on these. Defaults keep the
         * display-only constructions (clusters, tests) honest: a node with no
         * key gets no actions.
         */
        val key: String = "",
        val fullKey: String? = null,
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
        /** The radio's favourite bit. Never clustered away — see MeshNodes.rank. */
        val favourite: Boolean = false,
        /**
         * When > 0 this mote is not a node but a COUNT: the number of nodes on
         * roughly this bearing that the vertical budget could not label. Its
         * bearing is their mean, so it points at a real place; everything else
         * about it is an aggregate and it is drawn so it cannot be mistaken
         * for a single radio.
         */
        val cluster: Int = 0,
    )

    /**
     * The ink a surface draws with.
     *
     * The first four are the working set: every material and every text run in
     * the app resolves to one of them, which is what makes a theme a table
     * rather than a rewrite (see [Theme]).
     *
     * [ground], [panel] and [alert] carry the rest of the brief's palette.
     * GROUND and PANEL only mean something to a PANEL-substrate theme — on
     * additive optics a dark slab is not drawable at all (brief section 1.3),
     * so an ADDITIVE theme carries them for completeness and never paints them.
     * Defaulted, so a caller that only cares about ink can still say so.
     */
    data class Palette(
        val accent: Int, val alt: Int, val warn: Int, val text: Int,
        val ground: Int = 0x070B10,
        val panel: Int = 0x101722,
        val alert: Int = 0xFF3B6B,
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

    /**
     * The range circles, kept apart from [entities] so they can FOLLOW.
     *
     * THE NODES MUST NOT SLIDE, which is a narrower claim than it first reads
     * as, and the difference matters.
     *
     * Sliding the mesh rigidly along with the wearer would be a lie: a repeater
     * on a hill stays on its hill, and carrying its mark along beside you keeps
     * a bearing pointing where the repeater ISN'T. That is what this follow
     * does not do.
     *
     * RE-DERIVING the mesh from a new position is the opposite operation and is
     * simply correct. Every bearing and range here is measured FROM the wearer,
     * so moving changes what the map SAYS: walk ten miles east and the node
     * that was north-east is now north-west, in a different range band. That
     * belongs to the mesh rebuild, keyed on position — see the location poll in
     * MainActivity — not here.
     *
     * What follows here is only the CIRCLES, because they are a scale measured
     * from the wearer — "100 m, 1 km, 10 km from me" — and one centred where
     * you stood ten minutes ago measures from nowhere. Three tori re-posed,
     * rather than reparenting a scene of 118 entities.
     */
    private val rings = mutableListOf<MeshEntity>()
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
        /**
         * True when the callsign came from the pool. Then [label] points at the
         * MOTE (the pooled entity is shared and must not be touched per-peer),
         * so anything that hides "the label" must not go through it.
         */
        val pooled: Boolean = false,
        /**
         * The callsign that only appears under a pointer. Non-null exactly where
         * standing labels were suppressed — the tabletop — and switched off
         * until [onInput] hovers it.
         */
        val hoverName: Entity? = null,
        var open: Boolean = false,
    ) {
        /** Which pointers are currently on this peer. BOTH hands emit rays. */
        val pointers = mutableSetOf<String>()
        var hovered = false
        var exitAt = 0L
        var lastSelect = 0L
    }

    private class Pulse(val entity: MeshEntity, val base: Float, var life: Float = 1f)

    /** Pins waiting for handles. Filled during the build, drained by [callouts]. */
    private val wants = mutableListOf<Callout.Want>()


    /**
     * WHAT A NAME COST, once it has been placed.
     *
     * A callsign can end up as a pooled panel, a stroke mesh, or nothing at all
     * with the mote standing in for it. Everything downstream — the veil, the
     * hover path — has to know which, because a pooled entity is SHARED and
     * dimming it dims whichever node borrows it next.
     */
    private class Named(val label: Entity, val pooled: Boolean, val hover: Entity?)

    /**
     * THE RING.
     *
     * Split into named steps rather than written as one long body, and not for
     * readability: ART refuses to JIT-compile a method over ~10,000 dex code
     * units and says nothing when it declines. This one reached 9,338 — six
     * percent short — while being the surface the app changes most often, so
     * the next feature added to a node was going to push the whole horizon
     * rebuild into the interpreter with no error to explain why it got slow.
     * The frame loop already hit this and was fixed the same way (see
     * `frameActions` and friends); the sizes are checked with dexdump.
     *
     * The steps are local functions on purpose. Everything they touch —
     * `root`, `entities`, `facing`, `wants`, the pool, the counters — is
     * either loop state or per-build state, and capturing it costs one
     * synthetic parameter each where hoisting them to members would mean
     * threading a dozen arguments through five signatures.
     */
    suspend fun build(nodes: List<Node>, o: Stage.Origin, floorY: Float) {
        // A BEAT BETWEEN UNMAKING AND THE LAST MAKING. Entity creation is
        // async on the renderer's side: a mesh created here carries a
        // placeholder material until the real one binds, and disposing it in
        // that window is a native abort, not an exception. Back-to-back
        // rebuilds (queued theme commits, rapid membership churn) put the
        // previous build's last entities exactly there. This waits out the
        // tail of the previous build before clear() unmakes it; a rebuild
        // that arrives later than SETTLE_MS pays nothing.
        val since = android.os.SystemClock.uptimeMillis() - lastBuiltAt
        if (lastBuiltAt != 0L && since < SETTLE_MS) {
            kotlinx.coroutines.delay(SETTLE_MS - since)
        }
        clear()
        // TRANSIT DRAWS NO RING. Moving, hands busy, eyes on the world: the
        // MICROHUD is head-locked and the cuff and the radial menu are on the
        // hand, and between them they carry what a walking wearer can act on.
        // A shell of 200 motes at 2.5 m is the one thing you do not want in
        // front of you while crossing a street.
        //
        // Cleared and returned rather than built-and-hidden, because a hidden
        // horizon is still several hundred entities the renderer walks every
        // frame on the theme whose entire premise is having less to carry.
        if (!frame.horizon) {
            Log.i(TAG, "[horizon] TRANSIT — no ring; hud and hand surfaces only")
            return
        }
        val root = session.scene.activitySpace
        if (labels == null && context != null) {
            labels = LabelPool(session, context).also { it.build(tintOf(theme.text, 0.95f)) }
        }
        labels?.begin()
        var unlabelled = 0
        val labelledAny = posture != Theme.Posture.TABLETOP

        // --- range halos: real tori, lying flat below eye level --------------
        // Distance is read from which band a mote sits in, so the bands are the
        // scale and have to be legible from any angle -- hence torus, not disc.
        suspend fun rangeHalos() {
            listOf(0.40f, 0.70f, 1.00f).forEachIndexed { i, f ->
                val mesh = Prims.build(session, Prims.halo(frame.radius * f, 0.014f))
                val mat = Prims.material(session, theme.accent, 0.30f + i * 0.06f)
                MeshEntity.create(session, mesh, listOf(mat)).also {
                    it.parent = root
                    it.setPose(Pose(at(o, 0f, 0f, frame.ringDrop)), Space.ACTIVITY)
                    entities += it
                    rings += it
                    if (ringY == null) {
                        ringY = it.getPose(Space.ACTIVITY).translation.y
                        ringAt = it.getPose(Space.ACTIVITY).translation
                    }
                }
            }
        }

        // --- one node's mark, and the band that says how far away it got -----
        suspend fun moteFor(
            n: Node, px: Float, py: Float, pz: Float, r: Float, lum: Float,
            isRepeater: Boolean, isCluster: Boolean, textOnly: Boolean,
        ): MeshEntity {
            // SILHOUETTE CARRIES TYPE. Until now every node was the same
            // sphere and the only way to tell a repeater from a phone was that
            // some owners happened to type "Repeater" into the name -- which
            // is unreliable, untranslatable, and occasionally just wrong. The
            // protocol says so authoritatively; the shape should too.
            //
            // WHAT A NODE IS MADE OF, per theme (Theme.Symbol).
            //
            // WIRE draws the same three silhouettes as open geometry — a ring
            // for a node, concentric rings for a repeater, a coarse wide ring
            // for a cluster. The distinctions §4 requires survive because they
            // were always carried by SIZE and FORM rather than by fill.
            //
            // TEXT builds a mote anyway and then hides it. That looks wasteful
            // and is the cheap option: every downstream path — hover, select,
            // veil, pulse, the hit proxy's anchor — is written against a mote
            // that exists, and making it nullable to save one small mesh per
            // node would put a branch in all of them for a theme that is one of
            // nine.
            val moteMesh = Prims.build(session, markFor(symbol, r, isRepeater, isCluster))
            val moteMat = Prims.material(
                session, if (n.located) theme.accent else theme.warn, lum.coerceIn(0.25f, 1f)
            )
            val mote = MeshEntity.create(session, moteMesh, listOf(moteMat)).also {
                it.parent = root
                it.setPose(Pose(Vector3(px, py, pz)), Space.ACTIVITY)
                entities += it
                // TERMINAL VOID: the node is its text and nothing else.
                if (textOnly) it.setEnabled(false)
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
            return mote
        }

        // --- the callsign, wherever it ends up being drawn -------------------
        suspend fun nameFor(
            n: Node, mote: MeshEntity, capH: Float, lum: Float, anchor: Vector3,
            bearing: Float, dist: Float, textOnly: Boolean, isCluster: Boolean,
        ): Named {
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
            // In TEXT themes the label IS the node, so it carries what the
            // mote would otherwise have said: range, and bearing as three
            // digits. Kept inside the same cell budget MeshNodes laid out
            // against — a longer label does not get more arc, it gets printed
            // through its neighbours.
            val shown = if (textOnly) {
                TypeTier.clip(
                    "%s %s %03d".format(
                        TypeTier.clip(n.name, MeshNodes.MAX_LABEL_CELLS - 9),
                        MeshNodes.km(n.dist.toDouble()),
                        ((Math.toDegrees(bearing.toDouble()).toInt() % 360) + 360) % 360,
                    ),
                    MeshNodes.MAX_LABEL_CELLS,
                )
            } else {
                TypeTier.clip(n.name, MeshNodes.MAX_LABEL_CELLS)
            }
            // NO CALLSIGNS ON A TABLETOP, until they have somewhere to live.
            //
            // A label is sized by ANGLE and does not shrink with the model. At
            // 0.55 m the cap is 12.5 mm, so an eight-character callsign is
            // 68 mm of ink — 21 percent of a 320 mm model, where the same name
            // on the horizon is 6 percent of a 5 m ring. Hanging one at each
            // node put twenty of them through each other and through the mesh
            // they were describing: photographed, and unreadable in a way no
            // amount of clipping fixes, because the problem is the RATIO.
            //
            // The motes stay. What a tabletop is good at is the SHAPE of the
            // mesh — where the density is, which way it runs — and that reads
            // perfectly well without a name on every dot. Identity comes from
            // focusing one, which already works.
            //
            // This is a holding position, not the answer. `Callout` is the
            // answer: pins on the map, handles in a rack outside it, leaders
            // between. It is written and tested and not yet wired to anything,
            // and wiring it is what lets the names come back.
            val labelled = labelledAny
            val pooled = labelled && tier == TypeTier.Tier.RUN && !isCluster &&
                labels?.place(shown, anchor, capH) == true
            val txt: Entity = if (!labelled) {
                // Point at the mote, exactly as the pooled path does: no run,
                // no stroke label, nothing drawn. Suppressing only the POOL
                // would have been worse than useless — the fallback below draws
                // the same words as vector strokes, so the pile would have come
                // back in a different typeface.
                mote
            } else if (pooled) {
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

            // THE NAME A TABLETOP CANNOT STAND ALL THE TIME, KEPT FOR HOVER.
            //
            // Two dozen callsigns on a half-metre model is the pile that made
            // labels go away here — but "no labels so it's hard to know where
            // things are" is the report that followed, and both are true at
            // once. A hover label is the resolution: built with everything
            // else, drawn for nobody, and switched on for the ONE orb a
            // pointer is over. One name at a time is legible at any scale.
            //
            // A STROKE LABEL RATHER THAN A POOLED PANEL, because the pool is
            // shared and lending an entity out on hover would take a name off
            // whichever node is holding it. This is per-node and switched off,
            // which costs one small mesh each and nothing to draw.
            val hoverName: Entity? = if (labelledAny) null else {
                strokeLabel(root, n, capH, lum, anchor).also {
                    runCatching { it.setEnabled(false) }
                }
            }

            // THE PIN'S PLACE IN THE MAP, kept for the callout pass.
            //
            // Collected here rather than recomputed later because bearing and
            // dist are the loop's own variables and re-deriving them from a
            // world position would mean inverting the yaw — the same arithmetic
            // twice, in two directions, with two chances to disagree.
            if (!labelledAny) {
                wants += Callout.Want(
                    // Unique per pin, not per name: duplicate callsigns are
                    // normal on a mesh and two wants sharing an id would be two
                    // handles that cannot be told apart.
                    id = n.name + "@" + wants.size,
                    x = kotlin.math.sin(bearing) * frame.radius * dist,
                    y = kotlin.math.cos(bearing) * frame.radius * dist,
                    text = Callsign.render(n.name, maxGlyphs = CALLOUT_GLYPHS).text,
                )
            }

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
            return Named(txt, pooled, hoverName)
        }

        // --- the line that only a selected node shows ------------------------
        suspend fun detailFor(
            n: Node, capH: Float, anchor: Vector3, isCluster: Boolean,
        ): MeshEntity {
            // NODE DETAIL — hidden until selected. Stroke glyphs, so selection
            // does not drag in the whole tier-R font pipeline for three numbers.
            // The horizon label is clipped to stay glanceable; the detail line
            // is where the full name lives, because exactly one node is open at
            // a time and the width costs nothing there. Truncating in both
            // places would mean the app never shows you what a node is called.
            val cs = Callsign.render(n.name)
            val full = if (cs.truncated) Callsign.render(n.name, maxGlyphs = 40).text else ""
            val det = if (isCluster) {
                // Say what it is, in words. "+19" alone is ambiguous -- it could
                // be a channel, a margin, a signal figure.
                "%d NODES NOT SHOWN  NEAR %s".format(
                    n.cluster, MeshNodes.km(n.dist.toDouble()))
            } else {
                // MeshNodes.km INVERTS the log band. `dist * 5` was a linear
                // read of it, which is the exact error km()'s own note warns
                // about: it puts a node at 4 km when it is at 25. A distance on
                // a label is a claim someone might walk on.
                "%s%d HOP  %s  %s".format(
                    if (full.isNotEmpty()) "$full   " else "",
                    n.hops, MeshNodes.km(n.dist.toDouble()),
                    if (n.age < 0.34f) "LIVE" else "STALE",
                )
            }
            val detMesh = Prims.build(session, Glyphs.text(det, capH * 0.78f))
            val detMat = Prims.material(session, theme.alt, 0.9f)
            // BILLBOARDED IN ITS OWN RIGHT, not by inheritance.
            //
            // This used to hang off `txt` to pick up the label's rotation, and
            // that only worked for the labels drawn as STROKES. When a callsign
            // comes from the pool, `txt` points at the MOTE — a sphere, which
            // never billboards because it does not need to — so the detail line
            // inherited nothing and stayed pinned facing wherever it was built.
            // Reported 2026-08-03: readable from one side of the ring and
            // mirrored from the other.
            //
            // Its own anchor in activity space and its own entry in `facing`
            // fixes it for both label paths, and stops the fix depending on
            // which tier a name happened to route to.
            val detAt = Vector3(anchor.x, anchor.y - capH * 1.5f, anchor.z)
            return MeshEntity.create(session, detMesh, listOf(detMat)).also {
                it.parent = root
                it.setPose(Pose(detAt), Space.ACTIVITY)
                // setEnabled, NOT setAlpha(0): a hidden line must not come back
                // the moment a pointer passes near the node, with no selection.
                it.setEnabled(false)
                entities += it
                facing += Facing(it, detAt)
            }
        }

        // --- height, for the nodes that actually report it -------------------
        suspend fun altitudeFor(
            n: Node, txt: Entity, px: Float, py: Float, pz: Float,
            r: Float, capH: Float, lum: Float,
        ) {
            // ALTITUDE, and only altitude. This caret used to fire on `elev`,
            // which is now also the de-occlusion lane -- pointing it at a lane
            // offset would turn a legibility trick into a claim that the node
            // is up a hill. It is drawn ONLY for a node with real telemetry
            // altitude, and it comes with the figure in metres, because "above
            // you" without a number is the kind of half-fact that gets someone
            // walking uphill for no reason.
            val altM = n.altM ?: return
            val up = altM >= 0
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
            val txtAlt = "%.0fM".format(altM)
            val altMesh = Prims.build(session, Glyphs.text(txtAlt, capH * 0.72f))
            MeshEntity.create(
                session, altMesh, listOf(Prims.material(session, theme.alt, 0.85f * lum)),
            ).also {
                it.parent = txt          // billboards with the callsign
                it.setPose(Pose(Vector3(0f, capH * 1.35f, 0f)), Space.PARENT)
                entities += it
            }
        }

        rangeHalos()

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
            val v = at(
                o, bearing, frame.radius * dist,
                elev * frame.radius * ELEV_SPAN + frame.drop,
            )
            val px = v.x; val py = v.y; val pz = v.z
            val dx = px - o.x; val dy = py - o.y; val dz = pz - o.z
            val range = kotlin.math.sqrt(dx * dx + dy * dy + dz * dz)

            // CONSTANT ANGULAR SIZE (~1.6 deg). A fixed-radius mote subtends 9
            // deg up close and 2 deg far away; distance is already carried by
            // the range bands, so letting it drive apparent size just makes
            // near nodes shout.
            val r = (range * 0.0140f).coerceAtLeast(0.010f)
            val lum = 1f - n.age * 0.72f

            val isRepeater = n.type == TYPE_REPEATER
            val isCluster = n.cluster > 0
            val textOnly = symbol == Theme.Symbol.TEXT

            val mote = moteFor(n, px, py, pz, r, lum, isRepeater, isCluster, textOnly)

            // CALLSIGN — extruded stroke glyphs, so the label is made of light
            // in the room rather than printed on a surface. Sized by VISUAL
            // ANGLE (~1.3 deg cap height at its own range), never in absolute
            // metres, or distant nodes become unreadable.
            val capH = range * 0.0227f
            // Node names are arbitrary user text -- emoji, fullwidth kana,
            // accents, or nothing but a turtle. Callsign folds that into
            // something the stroke font can actually draw and tells us whether
            // to raise a badge for what it had to drop.
            // TEXT HANGS BELOW ITS MOTE — except on a table, where "below"
            // is under the table. The wearer is looking DOWN at a tabletop, so
            // anything under a mote is behind the surface it sits on and reads
            // through the map rather than beside it. Reported as "data is below
            // the map, so hard to read". Above, on a tabletop.
            val anchor = if (posture == Theme.Posture.TABLETOP) {
                Vector3(px, py + r * 2.6f + capH, pz)
            } else {
                Vector3(px, py - r * 2.6f - capH, pz)
            }

            val named = nameFor(
                n, mote, capH, lum, anchor, bearing, dist, textOnly, isCluster,
            )
            val detail = detailFor(n, capH, anchor, isCluster)

            // HIT PROXY — an invisible sphere ~3 deg across around the mote.
            // The mote itself is ~1.6 deg, which clears the 0.6 deg *visibility*
            // floor but is well under the ~2 deg the brief requires of anything
            // REACHED FOR (L7). Aiming a gaze ray at a 1.6 deg target is a test
            // of patience, so the thing you point at is deliberately bigger than
            // the thing you see.
            //
            // ITS OWN MATERIAL, and specifically a GHOST.
            //
            // This shared `moteMat` with the mote, and one material handed to
            // two entities is what crashed the renderer:
            //
            //   OwnedPtr of type imp::Material named "Split Engine Placeholder"
            //   released with 1 outstanding borrowed objects
            //
            // Disposing either entity releases the material while the other
            // still borrows it, and the abort lands in native code with no
            // Kotlin frame to point at. On this runtime a material belongs to
            // exactly one entity. Reported 2026-08-02 as an occasional crash
            // when backing out with the dock's WIDE pip, which is a rebuild and
            // therefore a mass dispose.
            //
            // Ghost rather than alpha 0.02 for the same reason the dock's
            // proxies are: an alpha-mask material DISCARDS its fragments, so it
            // cannot write depth and quietly occlude what is behind it, whereas
            // a nearly-transparent one is still drawn. The 0.02 trick was there
            // to stop the renderer skipping — and being skipped means being
            // unhittable — but MASK keeps it in the pipeline without emitting.
            val proxy = MeshEntity.create(
                session, Prims.build(session, Prims.mote(r * 2.2f, 5, 8)),
                listOf(Prims.ghost(session)),
            ).also {
                it.parent = root
                it.setPose(Pose(Vector3(px, py, pz)), Space.ACTIVITY)
                entities += it
            }

            val peer = Peer(
                node = n, mote = mote, label = named.label, detail = detail,
                at = Vector3(px, py, pz), labelAt = anchor, dist = dist, bearing = bearing,
                baseAlpha = lum.coerceIn(0.25f, 1f), pooled = named.pooled,
                hoverName = named.hover,
            )
            peers += peer
            runCatching {
                proxy.addComponent(
                    InteractableComponent.create(session) { ev -> onInput(peer, ev) },
                )
            }.onFailure { Log.w(TAG, "[horizon] no input on ${n.name}: $it") }

            altitudeFor(n, named.label, px, py, pz, r, capH, lum)
        }
        if (unlabelled > 0) {
            Log.i(TAG, "[horizon] $unlabelled node(s) fell back to stroke labels — pool exhausted")
        }
        if (!labelledAny) callouts(root, o)
        lastBuiltAt = android.os.SystemClock.uptimeMillis()
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
     * WHAT A NODE IS MADE OF, per theme.
     *
     * THE INVARIANT, and it is the reason this is one function rather than nine
     * scattered branches: every symbol must keep NODE, REPEATER and CLUSTER
     * apart BY SILHOUETTE. At 1.5 degrees that is the only cue section 4
     * allows — colour is spoken for by recency, and a mark that needs its
     * colour read is a mark that stops working in RECON AMBER, which has one
     * hue on purpose.
     *
     * So each symbol answers all three, and the answers keep the same
     * relationships throughout: a repeater is WIDER and SHALLOWER than its
     * node, a cluster is BIGGER and visibly COARSER — built out of parts, which
     * is what it is.
     */
    private fun markFor(
        sym: Theme.Symbol, r: Float, isRepeater: Boolean, isCluster: Boolean,
    ): Prims.Facets = when (sym) {
        // Open geometry only — Tempest drew light, not surfaces.
        Theme.Symbol.WIRE -> when {
            isCluster -> Prims.halo(r * 1.5f, r * 0.16f, seg = 14)
            isRepeater -> Prims.halo(r * 1.65f, r * 0.12f, seg = 20)
            else -> Prims.halo(r, r * 0.20f, seg = 16)
        }
        // No geometry at all; the label IS the node. Something still has to
        // exist for hover, veil and the hit proxy's anchor, and the caller
        // hides it.
        Theme.Symbol.TEXT -> Prims.mote(r * 0.2f, 3, 4)
        // Six sides. A bipyramid is what a faceted hex looks like when it has
        // to read from every angle rather than face-on.
        Theme.Symbol.HEX -> when {
            isCluster -> Prims.mote(r * 1.5f, rings = 2, seg = 6)
            isRepeater -> Prims.dish(r * 1.65f, r * 0.45f, seg = 6)
            else -> Prims.mote(r, rings = 4, seg = 6)
        }
        // The craft HUD's velocity mark. A repeater is the same chevron opened
        // out and flattened, which reads as "this one passes things along".
        Theme.Symbol.CHEVRON -> when {
            isCluster -> Prims.caret(r * 1.5f, r * 1.8f, seg = 5)
            isRepeater -> Prims.caret(r * 1.7f, r * 0.9f)
            else -> Prims.caret(r, r * 1.6f)
        }
        // Nothing round anywhere. A monolith is a slab and so is everything
        // near it; the distinctions are in proportion, which is all SEELE uses.
        Theme.Symbol.SLAB -> when {
            isCluster -> Prims.bar(r * 2.4f, r * 1.9f, r * 0.35f)
            isRepeater -> Prims.bar(r * 2.6f, r * 0.7f, r * 0.35f)
            else -> Prims.bar(r * 1.1f, r * 1.7f, r * 0.35f)
        }
        // A hard cube, and a cluster that is obviously several of them.
        Theme.Symbol.BLOCK -> when {
            isCluster -> Prims.mote(r * 1.6f, rings = 2, seg = 4)
            isRepeater -> Prims.bar(r * 2.0f, r * 0.8f, r * 0.8f)
            else -> Prims.bar(r * 1.3f, r * 1.3f, r * 1.3f)
        }
        // An instrument mark: a GAPPED ring, because the gaps are what make a
        // ring legible edge-on and what let it read as a sweep rather than a
        // circle. Prims.reticle was built for exactly this and had no caller.
        Theme.Symbol.RADAR -> when {
            isCluster -> Prims.reticle(r * 1.5f, r * 0.15f, arcs = 5, duty = 0.45f)
            isRepeater -> Prims.reticle(r * 1.7f, r * 0.11f, arcs = 2, duty = 0.78f)
            else -> Prims.reticle(r, r * 0.16f, arcs = 3)
        }
        // Rounder and smoother than a disc — more rings is literally a softer
        // body, which is the difference between a mote and a spore.
        Theme.Symbol.SPORE -> when {
            isCluster -> Prims.mote(r * 1.5f, rings = 3, seg = 5)
            isRepeater -> Prims.dish(r * 1.65f, r * 0.5f)
            else -> Prims.mote(r * 0.9f, rings = 11, seg = 16)
        }
        Theme.Symbol.SOLID -> when {
            // A CLUSTER must not look like a node, or the count reads as one
            // radio with a strange name.
            isCluster -> Prims.mote(r * 1.5f, rings = 3, seg = 5)
            // Wide and SHALLOW: depth/radius near 0.3 reads as a dish, near 0.7
            // reads as a cup.
            isRepeater -> Prims.dish(r * 1.65f, r * 0.5f)
            else -> Prims.mote(r)
        }
    }

    /**
     * TIER S — the extruded stroke label, and the fallback when a run will not
     * build. Folding and tofu live here and only here: a tofu box is an honest
     * report from a stroke font, which is correct on this path and would be a
     * product failure on the other one.
     */
    /**
     * PIN · LEADER · HANDLE, built — the tabletop's names, off the map.
     *
     * [Callout] answered the arithmetic months before anything drew it: the
     * label is 21% of a 32 cm model against 6% of a 5 m ring, so five callsigns
     * hanging at their nodes bury the diorama. That is why the tabletop had no
     * names at all, and why "no labels so it's hard to know where things are"
     * was the next report. Hover fixed one name at a time; this is the answer
     * for all of them at once.
     *
     * ## The 7-shape, in three dimensions
     *
     * Callout works in a plane and the table is horizontal, so its two axes
     * land as: the pin's x stays lateral, the pin's y becomes DEPTH (a node
     * further across the table reads as higher from where the wearer sits, so
     * far pins take the top slots and the leaders still cannot cross), and the
     * handle's y becomes HEIGHT above the table.
     *
     * A riser goes straight UP from the pin to the rack's height, then a run
     * goes out to the handle. Both segments live above the model, so nothing in
     * the rack casts over the map — rule R1, which is the whole point.
     *
     * ## Why the rack is one plane through the centre
     *
     * Handles sit at the map's own depth rather than at their pin's, so all of
     * them are coplanar and face the wearer as a column. Following each pin's
     * depth would scatter the handles through the table's volume and the rack
     * would stop reading as a list, which is the one thing it has to be.
     */
    private suspend fun callouts(root: Entity, o: Stage.Origin) {
        if (wants.isEmpty()) return
        val rules = Callout.Rules(
            mapRadius = frame.radius,
            gutter = frame.radius * GUTTER_OF_RADIUS,
            rowPitch = ROW_PITCH_OF_RADIUS * frame.radius,
            bandHeight = BAND_OF_RADIUS * frame.radius,
        )
        val placed = Callout.place(wants, rules)
        val dropped = Callout.dropped(wants, rules)
        // The rack's cap height is set from ITS OWN range, like everything
        // else: it is nearer the wearer than the far edge of the map and the
        // 1.3 degree floor is about where a thing is, not what it is.
        val rackRange = kotlin.math.max(0.35f, frame.forward)
        val capH = rackRange * 0.0227f
        placed.forEach { p ->
            val pin = fromLocal(o, p.pinX, p.pinY, frame.drop)
            val top = frame.drop + RACK_LIFT + p.handleY
            val knee = fromLocal(o, p.pinX, p.pinY, top)
            val hand = fromLocal(o, p.handleX, 0f, top)
            listOf(pin to knee, knee to hand).forEach { (a, b) ->
                MeshEntity.create(
                    session,
                    Prims.build(session, Prims.spur(a.x, a.y, a.z, b.x, b.y, b.z, LEADER_R)),
                    listOf(Prims.material(session, theme.alt, 0.55f)),
                ).also { it.parent = root; entities += it }
            }
            // The handle's text sits just outside the elbow, on the side the
            // rack is on, so the leader arrives at the word rather than
            // through it.
            val pad = capH * 0.6f
            val label = fromLocal(o, p.handleX + if (p.left) -pad else pad, 0f, top)
            MeshEntity.create(
                session,
                Prims.build(session, Glyphs.text(p.text, capH)),
                listOf(Prims.material(session, theme.text, 0.95f)),
            ).also {
                it.parent = root
                it.setPose(Pose(label), Space.ACTIVITY)
                entities += it
                facing += Facing(it, label)
            }
        }
        // The rack's own angular extent, for comparison with the dock's. These
        // two surfaces occupied the same degrees and nothing said so.
        run {
            val hi = frame.drop + RACK_LIFT + rules.bandHeight / 2f
            val lo = frame.drop + RACK_LIFT - rules.bandHeight / 2f
            fun deg(y: Float) =
                Math.toDegrees(kotlin.math.atan2(-y.toDouble(), frame.forward.toDouble()))
            Log.i(
                TAG,
                "[callout] ${placed.size} handle(s), $dropped dropped, " +
                    "${rules.perSide} per side — rack spans %.0f to %.0f deg below eye".format(
                        deg(hi), deg(lo),
                    ),
            )
        }
    }

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
            // SCALE ONLY. Mote alpha moved to veil() for the same reason the
            // label's is there: one writer per property, and veil runs
            // continuously while these fire at transitions.
            InputEvent.Action.HOVER_ENTER -> {
                p.mote.setScale(HOVER_SCALE)
                p.mote.setAlpha(1f)
                // ONE NAME, THE ONE UNDER THE POINTER. On a tabletop the
                // callsigns are built and left dark; this is the only thing
                // that lights one, and only ever one at a time.
                p.hoverName?.let { runCatching { it.setEnabled(true) } }
            }
            InputEvent.Action.HOVER_EXIT -> {
                p.mote.setScale(1f)
                p.mote.setAlpha(p.baseAlpha)
                p.hoverName?.let { runCatching { it.setEnabled(false) } }
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

    /**
     * Raised when a single node is pinched. Carries where it sits, because the
     * host has to place a FOCUS card between the viewer and the thing.
     */
    var onNode: ((Node, Vector3) -> Unit)? = null

    /**
     * The first cluster mote on the ring, and where it sits. Only used by the
     * --ez menu launch flag, which needs something to open a menu ON.
     */
    fun firstCluster(): Pair<Node, Vector3>? =
        peers.firstOrNull { it.node.cluster > 0 }?.let { it.node to it.at }

    /** The first real node on the ring. For the --ez focus launch flag. */
    fun firstNode(): Pair<Node, Vector3>? =
        peers.firstOrNull { it.node.cluster == 0 }?.let { it.node to it.at }

    suspend fun drainSelections(o: Stage.Origin) {
        while (true) {
            val p = selected.poll() ?: return
            if (p.node.cluster > 0) {
                onCluster?.invoke(p.node, p.at)
                continue
            }
            // The pulse stays: it is the mesh answering, and it reads as the
            // response to the pinch. The FOCUS card is what the pinch was FOR.
            pulse(p.bearing, p.dist, o)
            onNode?.invoke(p.node, p.at)
        }
    }

    /** PULSE — the mesh visibly breathing. One expanding ring per packet. */
    suspend fun pulse(bearingRad: Float, dist: Float, o: Stage.Origin) {
        val v = at(o, bearingRad, frame.radius * dist, frame.drop)
        val r0 = (frame.radius * dist * 0.016f).coerceAtLeast(0.012f)
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
        // NOTHING TO VEIL ON A TABLETOP, and running it there deleted the map.
        //
        // The veil exists to stop CALLSIGNS colliding with the microHUD's lower
        // band. A tabletop has no callsigns — they do not fit, see the note at
        // the label — so every peer's `label` points at its own MOTE with
        // pooled = false, and this method then dimmed those motes to
        // VEIL_ALPHA and called setEnabled(false) on them. The model sits 37
        // degrees below the horizon, which is exactly where the veil considers
        // things recessed, so it hid the whole diorama. Reported as the map no
        // longer loading, and it had not: it was built, then switched off one
        // frame later.
        //
        // The band is also not something a tabletop can collide with. The model
        // is deliberately below the sightline; that is what a table is.
        if (posture == Theme.Posture.TABLETOP) return
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
            // THE RECESS IS AN ENABLE, NOT AN ALPHA — see the note on [recess].
            // A pooled label is the pool's entity and `label` points at the mote
            // instead, so going through it here would blank the node itself.
            if (!p.pooled) runCatching { p.label.setEnabled(!recessed) }
            if (hidden) veiled++
        }
        // Logged on CHANGE only. A per-frame line would be 30 Hz of noise, but
        // without any line at all "the bands are clear" is indistinguishable
        // from "the veil never ran", and those look identical in a screenshot.
        // Pooled labels are the pool's entities, not the peer's, so they need
        // telling separately — a peer whose label is pooled points `label` at
        // its own mote precisely because the pooled one is shared.
        // Pooled callsigns are the pool's entities, not the peer's — a peer
        // whose label is pooled points `label` at its own mote — so they are
        // told separately. Alpha rather than enable only because the pool
        // manages its own visibility; the effect is the same rule.
        runCatching { labels?.setAlpha(if (recessed) 0f else 1f) }

        if (veiled != lastVeiled) {
            lastVeiled = veiled
            Log.i(TAG, "[horizon] veiled $veiled callsign(s) under the hud (pitch %.0f°)"
                .format(pitchDeg))
        }
    }

    private var lastVeiled = -1

    /**
     * Whether the ring is receded behind a FOCUS surface.
     *
     * Paradigm rule 3 (§2.1): ONE FOCUS AT A TIME. When the cluster menu opens
     * it is the thing you are doing, and the ring's own callsigns were printing
     * straight through its labels — two layers of text at the same depth with
     * nothing saying which one you are meant to be reading.
     *
     * THE RING KEEPS ITS MOTES AND LOSES ITS NAMES. That is the rule, and it is
     * better than a uniform dim: the mesh is still THERE, in the same places,
     * so the menu has not closed the world window — but the text layer belongs
     * to whatever is in focus, and only one thing can hold it.
     *
     * It is an ENABLE rather than an alpha, and that was forced. Probed on the
     * device at recess 0.0: pooled callsigns (PanelEntity) vanished, while the
     * stroke callsigns and motes (MeshEntity) did not change at all — and
     * setEnabled(false) on the very same references hid them immediately. So
     * MeshEntity.setAlpha is not reaching this material path, whatever it does
     * elsewhere. Worth knowing beyond here: veil() dims callsigns under the HUD
     * bands by exactly that call, which means the veil has most likely never
     * done anything visible either. Its counter has always been honest about
     * how many labels it CHOSE; nothing was checking the result.
     */
    private var recessed = false

    /** Push the ring back, or bring it forward. Idempotent; call it per frame. */
    fun setRecessed(on: Boolean) {
        recessed = on
    }

    /** Drive the pulses. Called from a frame loop; cheap and allocation-free. */
    /**
     * Keep the range circles centred on the wearer. HALO only — see [Theme.Frame].
     *
     * Yaw is deliberately untouched: the circles are concentric, so rotating
     * them would be invisible work, and anything that DID rotate with the head
     * would take the mesh's bearings with it.
     */
    fun follow(head: Vector3?) {
        if (!frame.follows || rings.isEmpty()) return
        val h = head ?: return
        val y = ringY ?: return
        if (kotlin.math.abs(h.x - ringAt.x) < FOLLOW_SLACK &&
            kotlin.math.abs(h.z - ringAt.z) < FOLLOW_SLACK
        ) return
        ringAt = Vector3(h.x, y, h.z)
        rings.forEach { runCatching { it.setPose(Pose(ringAt), Space.ACTIVITY) } }
    }

    private var ringY: Float? = null
    private var ringAt = Vector3(0f, 0f, 0f)
    /** When the last build finished; see the settle wait at [build]'s top. */
    private var lastBuiltAt = 0L

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
        // AND THE RANGE CIRCLES, for exactly the reason facing is cleared —
        // except only HALO ever paid. follow() runs per frame solely when
        // frame.follows, so on every other theme these stale handles sat
        // harmless, and the one path that reads them was the one theme the
        // sweep never rebuilds mid-wear: switching INTO the active theme
        // disposed the tori here, follow() setPose'd the dead handles, and
        // the renderer aborted natively ~2 s later ("OwnedPtr of type
        // imp::Material ... outstanding borrowed objects"). No Java
        // exception, process gone — which on an additive display reads as
        // "HALO isn't populating", not as a crash.
        rings.clear()
        ringY = null
        peers.clear()
        selected.clear()
        // The callout pass reads this list at the END of a build, so a rebuild
        // that did not empty it would place handles for the previous ring's
        // pins as well as this one's — every rebuild adding another set.
        wants.clear()
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
        /** Renderer settle before a rebuild may dispose the previous one. */
        private const val SETTLE_MS = 600L
        private const val HOVER_SCALE = 1.35f
        /** How long hover survives losing every pointer. Covers tracking jitter. */
        private const val HOVER_GRACE_MS = 180L
        /** Two hands, one pinch: ignore a second UP inside this window. */
        private const val SELECT_DEBOUNCE_MS = 350L
        /** The shell sits at and below eye level; the forward arc stays clear. */
        const val EYE_DROP = -0.30f

        /** Clearance between a real tabletop and the model standing on it. */
        const val TABLE_LIFT = 0.02f

        // --- the callout rack -------------------------------------------------
        //
        // AS FRACTIONS OF THE MAP, not as metres. Callout's own defaults are
        // absolute, sized for a 0.16 m table, which was right when there was one
        // table; the tabletop's radius has already been argued about twice and
        // will be again, and a rack that does not follow it would end up either
        // inside the map or out of the field.

        /** Clear space between the map's edge and the rack. */
        const val GUTTER_OF_RADIUS = 0.28f

        /** Handle spacing: one text row plus a gap, at the 1.3 degree floor. */
        const val ROW_PITCH_OF_RADIUS = 0.175f

        /**
         * How tall the rack may be — taller than the map is wide, deliberately.
         * Vertical space beside a table is free and competes with nothing;
         * horizontal space IS the map.
         */
        const val BAND_OF_RADIUS = 1.55f

        /** How far the rack floats above the table plane. */
        const val RACK_LIFT = 0.10f

        /** Leader thickness. Thin enough to read as a line, thick enough to see. */
        const val LEADER_R = 0.0016f

        /**
         * Glyphs a handle carries. Wider than the ring's clip, because the rack
         * is off the map and has room the horizon never has — which is half the
         * reason for moving the names out there.
         */
        const val CALLOUT_GLYPHS = 12

        /**
         * How far the wearer may drift before the circles are re-centred.
         *
         * Not zero, and not for the arithmetic's sake: head tracking jitters by
         * a few millimetres while you stand still, and circles that chased that
         * would shimmer. 15 cm is under a single pace, so it reads as the
         * scale keeping up rather than as anything moving.
         */
        const val FOLLOW_SLACK = 0.15f
    }
}
