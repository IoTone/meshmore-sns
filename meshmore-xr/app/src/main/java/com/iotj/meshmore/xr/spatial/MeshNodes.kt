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
    ): List<Horizon.Node> =
        rank(here, peers, nowEpochSec).take(limit).map { p ->
            val located = here.known && valid(p.lat) && valid(p.lon)
            val km = if (located) haversineKm(here.lat!!, here.lon!!, p.lat!!, p.lon!!) else 0.0
            Horizon.Node(
                name = p.name.ifBlank { "#%04X".format(p.key.hashCode() and 0xFFFF) },
                bearingRad = if (located) bearingRad(here.lat!!, here.lon!!, p.lat!!, p.lon!!) else 0f,
                // No altitude anywhere in the MeshCore contact record, so there
                // is no elevation to show. Zero means Horizon draws no caret,
                // which is the honest outcome -- not a flat guess at "level".
                elev = 0f,
                dist = if (located) bandFor(km) else 0.42f,
                age = ageOf(p.lastSeenEpochSec, nowEpochSec),
                located = located,
                hops = p.hops.coerceAtLeast(1),
                altM = p.altM,
            )
        }.let { deOcclude(it) }

    /**
     * STOP MOTES HIDING BEHIND EACH OTHER.
     *
     * Bearing alone puts every node on one horizontal line, and a real mesh
     * clusters -- nodes in the same town share a bearing to within a degree, so
     * they stack into a single blob with their callsigns written over each
     * other. Spreading them vertically is the cheapest fix that keeps every
     * bearing truthful.
     *
     * THE TRAP, and the reason this is not simply "add some jitter": height is
     * already meaningful. A mote placed higher reads as *higher up*, and a
     * synthetic offset presented that way is a fabricated altitude -- exactly
     * the class of claim the brief forbids for bearing. So the two are kept
     * strictly apart:
     *
     *   altM != null -> the node has REAL telemetry altitude. Its height is its
     *                   own, it is never moved, and Horizon marks it with a
     *                   caret and the figure in metres.
     *   altM == null -> height carries no meaning, so it is free to use for
     *                   legibility. No marker is drawn, and the ABSENCE of the
     *                   marker is what tells the user this height is not a claim.
     *
     * Lanes alternate above and below the horizon plane so the ring stays
     * centred on eye level rather than drifting upward.
     */
    fun deOcclude(nodes: List<Horizon.Node>): List<Horizon.Node> {
        // Separation is driven by the LABEL, not by a constant. The mote is
        // ~1.6 degrees wide but its callsign is ten times that, so a fixed
        // angular gap tuned to the dot lets "ESTACADA SOLAR" and
        // "NORTH EVERETT" sit in different lanes and still overlap — which is
        // exactly what happened on the first live mesh. Two nodes may share a
        // lane only when their labels do not touch.
        val lanes = ArrayList<Pair<Float, Float>>()   // last bearing, its half-width
        val byBearing = nodes.sortedBy { it.bearingRad }
        val out = HashMap<Horizon.Node, Float>()
        byBearing.forEach { n ->
            if (n.altM != null || !n.located) { out[n] = n.elev; return@forEach }
            val half = labelHalfWidthRad(n.name)
            var lane = 0
            while (lane < lanes.size) {
                val (prevBearing, prevHalf) = lanes[lane]
                if (abs(n.bearingRad - prevBearing) >= half + prevHalf + LABEL_GAP_RAD) break
                lane++
            }
            if (lane == lanes.size) lanes.add(n.bearingRad to half) else lanes[lane] = n.bearingRad to half
            out[n] = laneElev(lane)
        }
        return nodes.map { it.copy(elev = out[it] ?: it.elev) }
    }

    /**
     * Half the angular width of a callsign, in radians.
     *
     * Labels are sized by VISUAL ANGLE, so this is independent of how far the
     * node is: cap height is a fixed fraction of range, which makes each glyph
     * cell a fixed angle. That is the whole point of the angular discipline —
     * the separation rule needs no distance term.
     */
    fun labelHalfWidthRad(name: String): Float =
        (name.codePointCount(0, name.length) * CELL_RAD) / 2f

    /** 0, +1, -1, +2, -2 … so the ring stays centred on eye level. */
    fun laneElev(lane: Int): Float {
        if (lane == 0) return 0f
        val step = (lane + 1) / 2
        val sign = if (lane % 2 == 1) 1 else -1
        return (sign * step * LANE_STEP).coerceIn(-1f, 1f)
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
    /** Breathing room between two labels sharing a lane. ~3 degrees. */
    const val LABEL_GAP_RAD = 0.05f
    /** Vertical step per lane, as a fraction of the shell's vertical span. */
    const val LANE_STEP = 0.34f
}
