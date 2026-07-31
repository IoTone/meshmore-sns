// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The geography, checked without a radio. These are the numbers that decide
 * where a node appears in the room, and they are wrong in ways that still look
 * plausible -- a swapped sin/cos gives bearings that vary smoothly and are
 * simply not true. Reference values are standard great-circle results.
 */
class MeshNodesTest {

    private val londonLat = 51.5074; private val londonLon = -0.1278
    private val parisLat = 48.8566;  private val parisLon = 2.3522

    @Test fun distanceLondonToParis() {
        val km = MeshNodes.haversineKm(londonLat, londonLon, parisLat, parisLon)
        assertEquals(343.5, km, 2.0)
    }

    @Test fun bearingLondonToParis() {
        val deg = Math.toDegrees(
            MeshNodes.bearingRad(londonLat, londonLon, parisLat, parisLon).toDouble()
        )
        // 148.12, computed independently. NOT 156 -- that is the rhumb-line
        // figure often quoted for this pair, and a great-circle initial bearing
        // is a different number. Getting this reference wrong once already cost
        // a debugging round, so the second pair below is an independent check.
        assertEquals(148.12, deg, 0.2)
    }

    @Test fun bearingNewYorkToLondon() {
        val deg = Math.toDegrees(
            MeshNodes.bearingRad(40.7128, -74.0060, londonLat, londonLon).toDouble()
        )
        assertEquals(51.21, deg, 0.2)
        assertEquals(5570.2, MeshNodes.haversineKm(40.7128, -74.0060, londonLat, londonLon), 5.0)
    }

    @Test fun bearingDueNorthIsZeroAndDueEastIsNinety() {
        assertEquals(0.0, Math.toDegrees(MeshNodes.bearingRad(0.0, 0.0, 10.0, 0.0).toDouble()), 0.01)
        assertEquals(90.0, Math.toDegrees(MeshNodes.bearingRad(0.0, 0.0, 0.0, 10.0).toDouble()), 0.01)
    }

    /** 0/0 is Null Island, not "no fix". Treating it as a position aims the
     *  whole mesh at the Gulf of Guinea while looking like a working compass. */
    @Test fun nullIslandIsNotAFix() {
        val peers = listOf(peer(lat = 0.0, lon = 0.0))
        val n = MeshNodes.build(MeshNodes.Here(londonLat, londonLon), peers, NOW).single()
        assertFalse(n.located)
    }

    @Test fun noSelfFixMeansNothingIsLocated() {
        val peers = listOf(peer(lat = parisLat, lon = parisLon))
        val n = MeshNodes.build(MeshNodes.Here(null, null), peers, NOW).single()
        assertFalse(n.located)
        assertEquals(0f, n.bearingRad, 0f)
    }

    @Test fun locatedPeerGetsRealBearing() {
        val peers = listOf(peer(lat = parisLat, lon = parisLon))
        val n = MeshNodes.build(MeshNodes.Here(londonLat, londonLon), peers, NOW).single()
        assertTrue(n.located)
        assertEquals(148.12, Math.toDegrees(n.bearingRad.toDouble()), 0.2)
    }

    /** Bands must be monotonic and must spread across the ring rather than
     *  crushing everything indoors into the innermost one. */
    @Test fun bandsAreMonotonicAndSpread() {
        val near = MeshNodes.bandFor(0.05)
        val mid = MeshNodes.bandFor(2.0)
        val far = MeshNodes.bandFor(40.0)
        assertTrue("$near < $mid", near < mid)
        assertTrue("$mid < $far", mid < far)
        assertTrue("mid band should not hug the centre: $mid", mid > 0.25f)
        assertTrue(far <= 1.0f)
    }

    @Test fun ageSaturatesAndUnknownIsStale() {
        assertEquals(0f, MeshNodes.ageOf(NOW, NOW), 0.01f)
        assertEquals(1f, MeshNodes.ageOf(NOW - 7200, NOW), 0.01f)
        assertEquals(1f, MeshNodes.ageOf(0L, NOW), 0.01f)
    }

    @Test fun blankNameFallsBackToStableId() {
        val n = MeshNodes.build(
            MeshNodes.Here(null, null), listOf(peer(name = "")), NOW,
        ).single()
        assertTrue("expected a # fallback, got '${n.name}'", n.name.startsWith("#"))
    }

    private fun peer(name: String = "relay", lat: Double? = null, lon: Double? = null) =
        MeshNodes.Peer("k1", name, 2, 2, lat, lon, NOW)

    private companion object { const val NOW = 1_785_000_000L }
}
