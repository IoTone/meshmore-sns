// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Turning a MeshCore contact list into a HORIZON.
 *
 * Deliberately pure: geography in, [Horizon.Node] out, no session, no entities,
 * no Android. That is what makes it checkable without a radio in the room --
 * the part most likely to be wrong is the trigonometry, and the trigonometry is
 * exactly the part that does not need hardware to exercise.
 *
 * WHERE "WE" ARE. Bearing needs an origin, and we do not ask Android for one:
 * the companion radio already reports its own position in `SelfInfo`, and the
 * radio is on the user. Using it means no location permission, no GPS warm-up,
 * and one fewer thing to explain in a permissions dialog.
 */
object MeshNodes {

    /** What the radio tells us about one peer, normalised across advert/contact. */
    data class Peer(
        val key: String,
        val name: String,
        val type: Int,
        val hops: Int,
        val lat: Double?,
        val lon: Double?,
        val lastSeenEpochSec: Long,
        /** Metres above sea level from CayenneLPP telemetry, or null. */
        val altM: Double? = null,
        /**
         * The stored route to this peer, as the first byte of each relay's
         * public key — MeshCore stores one byte per hop, which is why
         * MeshTopology has to treat collisions as ambiguous.
         *
         * null   = nothing known (advert-only). A floater.
         * empty  = a direct neighbour.
         * else   = the relays between us and them, in order.
         */
        val path: List<Int>? = null,
        /** Reachable by flooding: no pinned route. Mutually exclusive with [path]. */
        val flood: Boolean = false,
    )

    /** Where the radio thinks it is. Null when it has no fix. */
    data class Here(val lat: Double?, val lon: Double?) {
        val known: Boolean get() = valid(lat) && valid(lon)
    }

    /**
     * MeshCore reports an absent position as 0/0, not as null, and 0/0 is a real
     * place in the Gulf of Guinea. Treating it as a fix puts every node on a
     * bearing to Null Island, which looks exactly like a working compass and is
     * the kind of bug that survives a demo.
     */
    private fun valid(d: Double?): Boolean = d != null && abs(d) > 1e-7

    /**
     * Log distance mapping. A mesh spans three orders of magnitude -- the node
     * on the desk and the repeater on the ridge -- and a linear band would pin
     * everything indoors into the innermost ring and waste the other two.
     */
    /**
     * ONE peer as a node, at its TRUE bearing — no lens applied.
     *
     * Factored out of [build] so a caller that has a peer but no drawn mote can
     * still ask where it is. NEAREST is exactly that case: it names nodes found
     * inside a cluster, and MAX_MOTES means most of them were never given a
     * mote of their own, so there is nothing on the ring to point at.
     *
     * TRUE bearing, deliberately, even while a lens is up. A magnification is a
     * view transform; the spur it feeds is painted on the real world and has to
     * mean the direction you would actually walk.
     */
    fun nodeFor(here: Here, p: Peer, nowEpochSec: Long): Horizon.Node {
        val located = here.known && valid(p.lat) && valid(p.lon)
        val km = if (located) haversineKm(here.lat!!, here.lon!!, p.lat!!, p.lon!!) else 0.0
        return Horizon.Node(
            name = p.name.ifBlank { "#%04X".format(p.key.hashCode() and 0xFFFF) },
            bearingRad = if (located) bearingRad(here.lat!!, here.lon!!, p.lat!!, p.lon!!) else 0f,
            // No altitude anywhere in the MeshCore contact record, so there is
            // no elevation to show. Zero means Horizon draws no caret, which is
            // the honest outcome -- not a flat guess at "level".
            elev = 0f,
            dist = if (located) bandFor(km) else 0.42f,
            age = ageOf(p.lastSeenEpochSec, nowEpochSec),
            located = located,
            hops = p.hops.coerceAtLeast(1),
            altM = p.altM,
            type = p.type,
        )
    }

    fun bandFor(km: Double, maxKm: Double = MAX_KM): Float {
        if (km <= 0.0) return 0.06f
        val f = ln(1.0 + km) / ln(1.0 + maxKm)
        return f.coerceIn(0.06, 1.0).toFloat()
    }

    /** Great-circle distance in km. */
    fun haversineKm(aLat: Double, aLon: Double, bLat: Double, bLon: Double): Double {
        val dLat = Math.toRadians(bLat - aLat)
        val dLon = Math.toRadians(bLon - aLon)
        val la1 = Math.toRadians(aLat)
        val la2 = Math.toRadians(bLat)
        val h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * EARTH_KM * atan2(sqrt(h), sqrt(1 - h))
    }

    /** Initial great-circle bearing, radians clockwise from true north. */
    fun bearingRad(aLat: Double, aLon: Double, bLat: Double, bLon: Double): Float {
        val dLon = Math.toRadians(bLon - aLon)
        val la1 = Math.toRadians(aLat)
        val la2 = Math.toRadians(bLat)
        val y = sin(dLon) * cos(la2)
        val x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLon)
        val b = atan2(y, x)
        return ((b + 2 * Math.PI) % (2 * Math.PI)).toFloat()
    }

    /**
     * Build the horizon.
     *
     * A peer whose position we do not know gets `located = false` and NO
     * bearing. The brief is explicit that a fabricated bearing is forbidden --
     * a mote at a confident compass heading is a claim about the physical
     * world, and being wrong about it in the field is worse than being silent.
     * Horizon parks those in the unlocated arc.
     *
     * Note this means a bench with two radios that never advertise a position
     * produces two motes off the shoulder and an empty ring. That is the
     * correct picture of what the radio actually knows.
     */
    fun build(
        here: Here,
        peers: List<Peer>,
        nowEpochSec: Long,
        limit: Int = MAX_MOTES,
        /**
         * When set, only nodes inside the wedge are drawn and their bearings are
         * magnified across the whole ring.
         *
         * The remap happens BEFORE layout, deliberately: de-occlusion packs
         * labels by angular separation, and the separation that matters is the
         * one on screen. Laying out in true bearing and magnifying afterwards
         * would space labels for a 7 degree ring and then stretch them across
         * 360, leaving the ring nearly empty and the labels wherever they fell.
         */
        lens: Lens? = null,
    ): List<Horizon.Node> =
        // NOTE the whole ranked list goes to layout(), not a take(limit) of it.
        // Deferred nodes cost nothing -- they build no geometry -- and passing
        // them through is what lets a cluster carry a TRUE count. Capping the
        // input first made a cluster of 139 nodes announce itself as "+19",
        // which is a worse lie than not drawing it at all.
        rank(here, peers, nowEpochSec).map { p -> nodeFor(here, p, nowEpochSec) }
            .let { nodes ->
                if (lens == null) nodes
                else nodes.filter { !it.located || lens.contains(it.bearingRad) }
                    .map { if (it.located) it.copy(bearingRad = lens.map(it.bearingRad)) else it }
            }.let { layout(it, limit) }

    /**
     * PLACEMENT — fit what fits, and COUNT the rest.
     *
     * The previous version made every node a lane of its own when it had to,
     * then normalised the lanes to fill the vertical span. That guarantees no
     * two lanes coincide, and it is still wrong, because it assumes the span
     * can be divided arbitrarily finely. It cannot. Do the arithmetic:
     *
     *   mote           ~1.6 deg across (constant angular size, Horizon)
     *   callsign cap   ~1.3 deg, hung ~2.1 deg below the mote centre
     *   ------------------------------------------------------------
     *   one node       ~4.2 deg of vertical space, mote top to text bottom
     *
     * The world window is +/-10 deg, which is 20 deg, which holds FIVE of
     * those. Not twenty-four. Asked for twenty-four it produced lanes 0.83 deg
     * apart and drew a column of overlapping spheres with every callsign
     * printed through its neighbours -- the honest consequence of an algorithm
     * that could not say "no".
     *
     * So this one says no. Nodes are placed in rank order, each taking the
     * first lane whose existing occupants its label clears. A node that fits
     * nowhere is DEFERRED, and the deferred are grouped by bearing into
     * counted cluster motes: one object saying "+19" rather than nineteen
     * objects saying nothing legible. That is a real property of the mesh --
     * nineteen nodes really are over there -- rendered at the density the
     * available angle can carry.
     *
     * Placing in RANK order rather than bearing order also retires the seam
     * bug this function used to carry. Sorting by bearing put 359 deg and 4 deg
     * at opposite ends of the list, so a lane's "last occupant" was never the
     * one a node actually abutted, and the fix was to track the first and last
     * separately. Keeping every occupant and testing against all of them makes
     * the ordering irrelevant, and wrap is already handled by angularGap.
     *
     * HEIGHT IS STILL NOT ALTITUDE. The distinction the old comment drew holds
     * and is load-bearing:
     *
     *   altM != null -> REAL telemetry altitude. The node does not move: it
     *                   fits in the lane its altitude puts it in or it defers.
     *   altM == null -> height carries no meaning, so it is free to use for
     *                   legibility. Horizon draws no caret, and the ABSENCE of
     *                   the caret is what tells the user this is not a claim.
     */
    fun layout(nodes: List<Horizon.Node>, limit: Int = MAX_MOTES): List<Horizon.Node> {
        class Occupant(val b: Float, val half: Float)
        val lanes = List(LANES) { ArrayList<Occupant>() }
        val out = ArrayList<Horizon.Node>()
        val deferred = ArrayList<Horizon.Node>()
        var unlocated = 0

        fun clears(lane: Int, b: Float, half: Float): Boolean =
            lanes[lane].all { angularGap(b, it.b) >= half + it.half + LABEL_GAP_RAD }

        fun place(n: Horizon.Node, half: Float): Boolean {
            // Lane indices already run 0, +1, -1, +2, -2 outward from eye level
            // (see laneRing), so trying them in order keeps a sparse ring flat
            // and only reaches for the edges of the window when it must. The
            // bottom lane is not offered: it belongs to the clusters.
            val candidates =
                if (n.altM != null) listOf(laneAt(n.elev)) else (0 until CLUSTER_LANE).toList()
            val lane = candidates.firstOrNull { clears(it, n.bearingRad, half) } ?: return false
            lanes[lane].add(Occupant(n.bearingRad, half))
            out += if (n.altM != null) n else n.copy(elev = elevOfLane(lane))
            return true
        }

        nodes.forEach { n ->
            if (!n.located) {
                // The unlocated arc has no bearings to separate by, so it gets a
                // flat cap rather than a packing rule.
                if (unlocated < MAX_UNLOCATED && out.size < limit) { out += n; unlocated++ }
                return@forEach
            }
            if (out.size >= limit || !place(n, labelHalfWidthRad(n.name))) deferred += n
        }

        // CLUSTERS get the BOTTOM LANE to themselves, and it has to be that way.
        // A cluster stands at the mean bearing of the nodes it holds -- which
        // are, by definition, the nodes that just filled every lane on that
        // bearing. Offered the same lanes it clears none of them and is dropped
        // silently, so the count that was supposed to prevent nodes vanishing
        // vanishes instead. Reserving a lane makes room by construction.
        //
        // It also reads well: the counts run along the bottom of the window
        // like a footer, plainly a different KIND of thing from the named nodes
        // above them.
        if (deferred.isNotEmpty()) out += clustersFor(deferred)
        return out
    }

    /** One [Group] is a bearing bucket of deferred nodes, accumulated. */
    private class Group {
        var n = 0
        var sumB = 0.0
        var sumD = 0.0
        var age = 1f
        var hops = Int.MAX_VALUE
        val bearing: Float get() = (sumB / n).toFloat()
        fun add(x: Horizon.Node) {
            n++; sumB += x.bearingRad.toDouble(); sumD += x.dist.toDouble()
            age = minOf(age, x.age); hops = minOf(hops, x.hops)
        }
        fun absorb(o: Group) {
            n += o.n; sumB += o.sumB; sumD += o.sumD
            age = minOf(age, o.age); hops = minOf(hops, o.hops)
        }
    }

    /**
     * Turn the deferred nodes into counted motes.
     *
     * NOTHING MAY VANISH UNCOUNTED. A group that cannot be drawn -- because it
     * would collide with another count, or because the mote budget is spent --
     * is ABSORBED into its nearest neighbour rather than dropped. The bearing
     * blurs a little as counts merge, which is the honest trade: "+31 roughly
     * that way" is true, and a group that quietly disappears is not.
     */
    private fun clustersFor(deferred: List<Horizon.Node>): List<Horizon.Node> {
        val groups = LinkedHashMap<Int, Group>()
        deferred.filter { it.located }.forEach {
            groups.getOrPut((it.bearingRad / CLUSTER_RAD).toInt()) { Group() }.add(it)
        }
        val kept = ArrayList<Group>()
        groups.values.sortedByDescending { it.n }.forEach { g ->
            val room = kept.size < MAX_CLUSTERS &&
                kept.all { angularGap(g.bearing, it.bearing) >= CLUSTER_GAP_RAD }
            if (room || kept.isEmpty()) kept += g
            else kept.minByOrNull { angularGap(g.bearing, it.bearing) }!!.absorb(g)
        }
        return kept.map { g ->
            Horizon.Node(
                // WHAT IS IN THERE, not just how many. "+106" is a count and a
                // shrug: it says something is over there without saying where
                // "there" is or how far. The compass point and the mean range
                // are the two facts a count already implies and never states,
                // and they are what decide whether it is worth going in.
                name = "+${g.n} ${compass(g.bearing)} ${km(g.sumD / g.n)}",
                // Members share a bucket far narrower than the wrap, so a plain
                // mean is safe and a circular mean is not worth the arithmetic.
                bearingRad = g.bearing,
                elev = elevOfLane(CLUSTER_LANE),
                dist = (g.sumD / g.n).toFloat(),
                // Freshest member: the cluster is live if anything in it is.
                age = g.age,
                located = true,
                hops = g.hops,
                cluster = g.n,
            )
        }
    }

    /** Elevation (-1..1) of a lane index, spread evenly over the window. */
    fun elevOfLane(lane: Int): Float {
        val half = (LANES - 1) / 2
        return if (half == 0) 0f else laneRing(lane).toFloat() / half
    }

    /** The lane whose elevation is nearest [elev]. Inverse of [elevOfLane]. */
    fun laneAt(elev: Float): Int {
        val half = (LANES - 1) / 2
        val ring = Math.round(elev * half).coerceIn(-half, half)
        return (0 until LANES).first { laneRing(it) == ring }
    }

    /**
     * Smallest angle between two bearings, in radians.
     *
     * Bearings wrap, so a plain subtraction makes 359 deg and 4 deg look 355
     * apart when they are 5 -- two nodes either side of north would be treated
     * as opposite ends of the ring and allowed to share a lane.
     */
    fun angularGap(a: Float, b: Float): Float {
        val twoPi = (2.0 * Math.PI).toFloat()
        val d = abs(a - b) % twoPi
        return if (d > twoPi / 2f) twoPi - d else d
    }

    /** Signed ring for a lane index: 0, +1, -1, +2, -2 … centred on eye level. */
    fun laneRing(lane: Int): Int {
        if (lane == 0) return 0
        val step = (lane + 1) / 2
        return if (lane % 2 == 1) step else -step
    }

    /**
     * Half the angular width of a callsign, in radians.
     *
     * Labels are sized by VISUAL ANGLE, so this is independent of how far the
     * node is: cap height is a fixed fraction of range, which makes each glyph
     * cell a fixed angle. That is the whole point of the angular discipline —
     * the separation rule needs no distance term.
     */
    fun labelHalfWidthRad(name: String): Float {
        // DISPLAY cells, not code points. A kanji is twice as wide as a Latin
        // letter at the same cap height, so counting code points reserved half
        // the space a CJK label actually needs -- and every tier R label that
        // reached the ring after T2 was laid out against that wrong number.
        // Clipped first, because the label that gets drawn is the clipped one.
        val shown = TypeTier.clip(name, MAX_LABEL_CELLS)
        // And PER TIER, because a stroke cell and a monospace-run cell are not
        // the same width. Only 11% apart -- but the whole point of this function
        // is that the layout and the renderer agree, and 11% of an 18-cell label
        // is two characters of overlap.
        // A callsign is a NAME, so it is tier R and budgeted at the run cell
        // width. It used to be budgeted as a stroke label whenever it happened
        // to be short Latin, which meant the layout reserved a different width
        // than the renderer drew for exactly the labels that were most common.
        return (TypeTier.displayCells(shown) * CAP_FRACTION *
            TypeTier.cellEm(shown, TypeTier.Kind.NAME)) / 2f
    }

    /**
     * WHICH NODES GET A MOTE.
     *
     * A real public mesh is not eleven nodes, it is hundreds -- the first live
     * radio we pointed at this reported 165 contacts, and the horizon died
     * trying to draw them. Two independent reasons to cap it:
     *
     *  - COST. Every node is roughly six entities, each with its own mesh
     *    (sphere, hit proxy, callsign strokes, detail strokes). 165 nodes is
     *    ~1000 meshes built in one pass, and the app did not survive it.
     *
     *  - LEGIBILITY. 165 motes spread over 360 degrees is one every 2.2
     *    degrees, well inside each other's labels. A ring that dense carries
     *    less information than a ring of twenty, not more.
     *
     * Ranking prefers nodes we can actually place, then the ones heard most
     * recently -- "who is on the air near me", which is what the horizon is
     * for. The remainder are not lost; they are simply not motes, and the
     * caller is told how many were dropped rather than being left to assume
     * the mesh is small.
     */
    fun rank(here: Here, peers: List<Peer>, nowEpochSec: Long): List<Peer> =
        peers.sortedWith(
            compareByDescending<Peer> { here.known && valid(it.lat) && valid(it.lon) }
                .thenByDescending { it.lastSeenEpochSec }
        )

    /** How many of [peers] would be dropped at [limit]. For logging, not display. */
    fun droppedCount(peers: List<Peer>, limit: Int = MAX_MOTES): Int =
        (peers.size - limit).coerceAtLeast(0)

    /** Sixteen-point compass. Coarse on purpose: a cluster IS a spread. */
    fun compass(bearingRad: Float): String {
        val deg = Math.toDegrees(bearingRad.toDouble())
        val i = (((deg % 360.0 + 360.0) % 360.0) / 22.5).let { Math.round(it).toInt() % 16 }
        return POINTS[i]
    }

    private val POINTS = listOf(
        "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
        "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
    )

    /**
     * The band fraction back to kilometres, for display only.
     *
     * bandFor is logarithmic, so this inverts it rather than scaling it — a
     * linear read of a log band would put a node at 4 km when it is at 25, and
     * a distance on a label is a claim someone might walk on.
     */
    fun km(band: Double): String {
        val k = Math.exp(band * Math.log(1.0 + MAX_KM)) - 1.0
        return if (k < 10) "%.1fKM".format(k) else "%.0fKM".format(k)
    }

    /** 0 = heard just now, 1 = stale. Linear over [STALE_AFTER_SEC]. */
    fun ageOf(lastSeenEpochSec: Long, nowEpochSec: Long): Float {
        if (lastSeenEpochSec <= 0L) return 1f
        val d = (nowEpochSec - lastSeenEpochSec).coerceAtLeast(0L)
        return (d.toDouble() / STALE_AFTER_SEC).coerceIn(0.0, 1.0).toFloat()
    }

    private const val EARTH_KM = 6371.0088
    /** Outer range band. Beyond this everything pins to the rim. */
    const val MAX_KM = 50.0
    /** An hour with no advert and a node reads as fully stale. */
    const val STALE_AFTER_SEC = 3600.0
    /**
     * Motes on the horizon. Chosen for legibility first -- 24 over 360 degrees
     * is one every 15 degrees, which leaves room for a callsign beside each.
     */
    const val MAX_MOTES = 24
    /**
     * Angular width of one glyph cell: ADV/GH x the 0.0227 cap-height fraction
     * Horizon uses. ~1.2 degrees, so a 14-glyph callsign spans ~17.
     */
    const val CELL_RAD = 0.0212f
    /**
     * Cap height as a fraction of range — the one number that makes every label
     * the same visual angle whatever its distance. Horizon uses it directly; it
     * lives here because the width budget is derived from it.
     */
    const val CAP_FRACTION = 0.0227f
    /**
     * Widest a label may be, in display cells. Matches Callsign.MAX_GLYPHS so
     * the stroke and run paths cannot drift apart: both budgets have to be the
     * same number or the layout is estimating one path while drawing the other.
     */
    const val MAX_LABEL_CELLS = 18
    /** Breathing room between two labels sharing a lane. ~3 degrees. */
    const val LABEL_GAP_RAD = 0.05f
    /**
     * HOW MANY LANES THE WINDOW ACTUALLY HOLDS.
     *
     * The world window is +/-10 deg (Horizon.ELEV_SPAN) and one node --  mote
     * plus the callsign hung beneath it -- is about 4.2 deg tall. 20 / 4.2 is
     * 4.8, so five lanes, pitched 5 deg apart, leaving a little under a degree
     * of clear space between one node's callsign and the mote below it.
     *
     * Raising this does not fit more nodes, it just overlaps them again. If
     * more nodes need to be legible at once, the thing to change is the window
     * or the type size -- both of which have owners elsewhere -- not this.
     */
    const val LANES = 5
    /**
     * Bearing width of a cluster bucket, ~17 deg. Wide enough that a town does
     * not fragment into four counts, narrow enough that "+19 over there" still
     * points somewhere you could walk.
     */
    const val CLUSTER_RAD = 0.30f
    /**
     * The lane reserved for counts. laneRing puts the highest index at the
     * bottom of the window, which is where a footer belongs.
     */
    const val CLUSTER_LANE = LANES - 1
    /** Minimum separation between two counts sharing the cluster lane, ~9 deg. */
    const val CLUSTER_GAP_RAD = 0.16f
    /** Counts on screen at once. Beyond this they merge rather than multiply. */
    const val MAX_CLUSTERS = 5
    /**
     * Motes in the unlocated arc. They all share one fabricated bearing, so
     * they cannot be separated by the packing rule -- they are simply capped
     * before they become a pile.
     */
    const val MAX_UNLOCATED = 4

}
