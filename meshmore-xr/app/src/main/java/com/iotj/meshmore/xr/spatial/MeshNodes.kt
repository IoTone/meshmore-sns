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
    fun build(here: Here, peers: List<Peer>, nowEpochSec: Long): List<Horizon.Node> =
        peers.map { p ->
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
            )
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
}
