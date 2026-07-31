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

    // ---- de-occlusion -----------------------------------------------------

    private fun node(bearingDeg: Double, alt: Double? = null, located: Boolean = true) =
        Horizon.Node(
            name = "n$bearingDeg", bearingRad = Math.toRadians(bearingDeg).toFloat(),
            elev = 0f, dist = 0.5f, age = 0f, located = located, hops = 1, altM = alt,
        )

    @Test fun clusteredNodesGetDifferentHeights() {
        // Four nodes within two degrees of each other: the real-mesh case, where
        // a whole town shares one bearing and stacks into a single blob.
        val out = MeshNodes.deOcclude(listOf(node(10.0), node(11.0), node(11.5), node(12.0)))
        assertEquals(4, out.map { it.elev }.toSet().size)
    }

    @Test fun wellSeparatedNodesAllStayOnTheHorizonPlane() {
        val out = MeshNodes.deOcclude((0..5).map { node(it * 60.0) })
        assertTrue(out.all { it.elev == 0f })
    }

    /** The live-mesh failure: different lanes, still overlapping labels. */
    @Test fun longLabelsNeedMoreSeparationThanShortOnes() {
        val short = MeshNodes.deOcclude(listOf(named("AB", 0.0), named("CD", 14.0)))
        assertTrue("short labels 14 deg apart should share a lane",
            short.all { it.elev == 0f })
        val long = MeshNodes.deOcclude(
            listOf(named("ESTACADA SOLAR", 0.0), named("NORTH EVERETT", 14.0)),
        )
        assertEquals("14-glyph labels 14 deg apart must not share a lane",
            2, long.map { it.elev }.toSet().size)
    }

    private fun named(name: String, bearingDeg: Double) = Horizon.Node(
        name = name, bearingRad = Math.toRadians(bearingDeg).toFloat(),
        elev = 0f, dist = 0.5f, age = 0f, located = true, hops = 1,
    )

    /** The whole point: a lane offset must never masquerade as altitude. */
    @Test fun nodesWithRealAltitudeAreNeverMoved() {
        val withAlt = node(10.0, alt = 412.0)
        val out = MeshNodes.deOcclude(listOf(withAlt, node(10.2), node(10.4)))
        assertEquals(0f, out.single { it.altM != null }.elev, 0f)
    }

    @Test fun unlocatedNodesAreNotLaned() {
        val out = MeshNodes.deOcclude(listOf(node(0.0, located = false), node(0.0, located = false)))
        assertTrue(out.all { it.elev == 0f })
    }

    /** Lanes must alternate so the ring stays centred on eye level. */
    @Test fun lanesAlternateAboutZero() {
        assertEquals(0, MeshNodes.laneRing(0))
        assertTrue(MeshNodes.laneRing(1) > 0)
        assertTrue(MeshNodes.laneRing(2) < 0)
        assertTrue(MeshNodes.laneRing(3) > MeshNodes.laneRing(1))
        assertTrue(MeshNodes.laneRing(4) < MeshNodes.laneRing(2))
    }

    /**
     * The live-mesh bug: a cluster needing eight lanes had lane 7 clamped onto
     * lane 5, putting "North Everett" and "Esterra Solar" back on one line.
     * Every occupied lane must end up at its own height.
     */
    @Test fun aDenseClusterGivesEveryNodeItsOwnHeight() {
        val cluster = listOf(
            named("Vault 112 Overseer", 4.0), named("Alaska Junction SE", 7.2),
            named("Entropy Temple", 7.3), named("Brier_Hill_Solar", 8.2),
            named("Woofy Repeater", 8.4), named("North Everett", 8.6),
            named("W7MIR Repeater", 10.1), named("Esterra Solar", 11.3),
        )
        val out = MeshNodes.deOcclude(cluster)
        assertEquals("every node needs a distinct height",
            cluster.size, out.map { it.elev }.toSet().size)
        assertTrue("must stay inside the shell", out.all { it.elev in -1f..1f })
    }

    /** Bearings wrap: 359 and 4 are five degrees apart, not 355. */
    @Test fun angularGapWrapsAroundNorth() {
        assertEquals(
            Math.toRadians(5.0).toFloat(),
            MeshNodes.angularGap(Math.toRadians(359.0).toFloat(), Math.toRadians(4.0).toFloat()),
            1e-4f,
        )
    }

    /**
     * The seam case: sorting by bearing separates 352 deg from 4 deg by the
     * whole list, so a lane's most-recent occupant is never its wrap neighbour.
     * Nodes in between must not let the two ends collide.
     */
    @Test fun theRingSeamIsCheckedNotJustTheLastEntry() {
        val out = MeshNodes.deOcclude(listOf(
            named("GM-EXT88 Repeater", 352.6),
            named("Cedar Hills", 267.5),
            named("Vault 112 Overseer", 4.0),
        ))
        val ext = out.first { it.name.startsWith("GM-EXT88") }
        val vault = out.first { it.name.startsWith("Vault") }
        assertTrue("wrap neighbours must not share a height", ext.elev != vault.elev)
    }

    @Test fun nodesEitherSideOfNorthDoNotShareALane() {
        val out = MeshNodes.deOcclude(
            listOf(named("GM-EXT88 Repeater", 356.0), named("Vault 112 Overseer", 4.0)),
        )
        assertEquals(2, out.map { it.elev }.toSet().size)
    }

    @Test fun buildCapsTheRingAndReportsWhatItDropped() {
        val many = (0 until 60).map { peer(name = "n$it", lat = 48.0 + it * 0.01, lon = 2.0) }
        val out = MeshNodes.build(MeshNodes.Here(londonLat, londonLon), many, NOW)
        assertEquals(MeshNodes.MAX_MOTES, out.size)
        assertEquals(60 - MeshNodes.MAX_MOTES, MeshNodes.droppedCount(many))
    }

    private fun peer(name: String = "relay", lat: Double? = null, lon: Double? = null) =
        MeshNodes.Peer("k1", name, 2, 2, lat, lon, NOW)

    private companion object { const val NOW = 1_785_000_000L }
}
