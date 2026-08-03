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
        val out = MeshNodes.layout(listOf(node(10.0), node(11.0), node(11.5), node(12.0)))
        assertEquals(4, out.map { it.elev }.toSet().size)
    }

    @Test fun wellSeparatedNodesAllStayOnTheHorizonPlane() {
        val out = MeshNodes.layout((0..5).map { node(it * 60.0) })
        assertTrue(out.all { it.elev == 0f })
    }

    /** The live-mesh failure: different lanes, still overlapping labels. */
    @Test fun longLabelsNeedMoreSeparationThanShortOnes() {
        val short = MeshNodes.layout(listOf(named("AB", 0.0), named("CD", 14.0)))
        assertTrue("short labels 14 deg apart should share a lane",
            short.all { it.elev == 0f })
        val long = MeshNodes.layout(
            listOf(named("ESTACADA SOLAR", 0.0), named("NORTH EVERETT", 14.0)),
        )
        assertEquals("14-glyph labels 14 deg apart must not share a lane",
            2, long.map { it.elev }.toSet().size)
    }

    /**
     * THE CAPACITY RULE. The window holds LANES nodes on one bearing and no
     * more. Asked for more it used to subdivide the span until the labels
     * overlapped again; it must now refuse and count instead.
     */
    @Test fun aSaturatedBearingRefusesRatherThanOverlapping() {
        val town = (0 until 20).map { named("SOLAR REPEATER $it", 8.0 + it * 0.1) }
        val out = MeshNodes.layout(town)
        val labelled = out.filter { it.cluster == 0 }
        assertEquals("only a full window of nodes may be labelled — the bottom " +
            "lane is reserved for counts", MeshNodes.CLUSTER_LANE, labelled.size)
        assertEquals("labelled nodes must each have their own height",
            labelled.size, labelled.map { it.elev }.toSet().size)
        val counted = out.filter { it.cluster > 0 }.sumOf { it.cluster }
        assertEquals("everything not labelled must be counted",
            20 - MeshNodes.CLUSTER_LANE, counted)
    }

    /** A cluster points at a real place: the mean bearing of what it holds. */
    @Test fun aClusterPointsAtItsMembers() {
        val town = (0 until 20).map { named("SOLAR REPEATER $it", 100.0 + it * 0.1) }
        val c = MeshNodes.layout(town).single { it.cluster > 0 }
        assertEquals(Math.toRadians(101.0).toFloat(), c.bearingRad, Math.toRadians(1.5).toFloat())
    }

    /** Every height the layout emits has to be inside the shell it was given. */
    @Test fun everyPlacedNodeStaysInsideTheWindow() {
        val many = (0 until 40).map { named("NODE $it", it * 3.0) }
        assertTrue(MeshNodes.layout(many).all { it.elev in -1f..1f })
    }

    @Test fun laneElevationsRoundTrip() {
        (0 until MeshNodes.LANES).forEach { lane ->
            assertEquals(lane, MeshNodes.laneAt(MeshNodes.elevOfLane(lane)))
        }
    }

    private fun named(name: String, bearingDeg: Double) = Horizon.Node(
        name = name, bearingRad = Math.toRadians(bearingDeg).toFloat(),
        elev = 0f, dist = 0.5f, age = 0f, located = true, hops = 1,
    )

    /** The whole point: a lane offset must never masquerade as altitude. */
    @Test fun nodesWithRealAltitudeAreNeverMoved() {
        val withAlt = node(10.0, alt = 412.0)
        val out = MeshNodes.layout(listOf(withAlt, node(10.2), node(10.4)))
        assertEquals(0f, out.single { it.altM != null }.elev, 0f)
    }

    @Test fun unlocatedNodesAreNotLaned() {
        val out = MeshNodes.layout(listOf(node(0.0, located = false), node(0.0, located = false)))
        assertTrue(out.all { it.elev == 0f })
    }

    /** They share one fabricated bearing, so they are capped, not packed. */
    @Test fun theUnlocatedArcIsCapped() {
        val out = MeshNodes.layout((0 until 12).map { node(0.0, located = false) })
        assertEquals(MeshNodes.MAX_UNLOCATED, out.count { !it.located })
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
     * The live-mesh case, with the real callsigns off the Seattle cluster.
     * Eight nodes inside eight degrees is more than the window holds, so the
     * requirement is no longer "every node gets a height" -- that was the
     * demand that produced 0.83 deg lanes and a column of overlapping spheres.
     * It is: everything DRAWN is separated, and nothing is silently lost.
     */
    @Test fun aDenseClusterSeparatesWhatItDrawsAndCountsTheRest() {
        val town = listOf(
            named("Vault 112 Overseer", 4.0), named("Alaska Junction SE", 7.2),
            named("Entropy Temple", 7.3), named("Brier_Hill_Solar", 8.2),
            named("Woofy Repeater", 8.4), named("North Everett", 8.6),
            named("W7MIR Repeater", 10.1), named("Esterra Solar", 11.3),
        )
        val out = MeshNodes.layout(town)
        val labelled = out.filter { it.cluster == 0 }
        assertEquals("every drawn node needs a distinct height",
            labelled.size, labelled.map { it.elev }.toSet().size)
        assertTrue("must stay inside the shell", out.all { it.elev in -1f..1f })
        assertEquals("no node may vanish without being counted",
            town.size, labelled.size + out.sumOf { it.cluster })
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
        val out = MeshNodes.layout(listOf(
            named("GM-EXT88 Repeater", 352.6),
            named("Cedar Hills", 267.5),
            named("Vault 112 Overseer", 4.0),
        ))
        val ext = out.first { it.name.startsWith("GM-EXT88") }
        val vault = out.first { it.name.startsWith("Vault") }
        assertTrue("wrap neighbours must not share a height", ext.elev != vault.elev)
    }

    @Test fun nodesEitherSideOfNorthDoNotShareALane() {
        val out = MeshNodes.layout(
            listOf(named("GM-EXT88 Repeater", 356.0), named("Vault 112 Overseer", 4.0)),
        )
        assertEquals(2, out.map { it.elev }.toSet().size)
    }

    /**
     * 60 peers strung north from London: they span enough bearing to place a
     * good many, and whatever will not fit must come back as a count. The cap
     * is on MOTES, so clusters count against it too -- the budget is what the
     * scene can draw, not what it can label.
     */
    @Test fun buildCapsTheRingAndCountsWhatItCouldNotDraw() {
        val many = (0 until 60).map { peer(name = "n$it", lat = 48.0 + it * 0.01, lon = 2.0) }
        val out = MeshNodes.build(MeshNodes.Here(londonLat, londonLon), many, NOW)
        assertTrue("must not exceed the mote budget",
            out.count { it.cluster == 0 } <= MeshNodes.MAX_MOTES)
        assertTrue("counts are bounded too", out.count { it.cluster > 0 } <= MeshNodes.MAX_CLUSTERS)
        assertEquals("every peer is either drawn or counted",
            60, out.count { it.cluster == 0 } + out.sumOf { it.cluster })
    }

    /**
     * nodeFor was lifted OUT of build() so NEAREST can describe a peer that
     * never got a mote — MAX_MOTES means most members of a cluster do not.
     * A refactor that quietly changed what build() produces would move every
     * node on the ring, so pin the two together.
     */
    @Test fun nodeForMatchesWhatBuildProduces() {
        val p = peer(name = "relay", lat = 51.52, lon = -0.10)
        val here = MeshNodes.Here(londonLat, londonLon)
        val built = MeshNodes.build(here, listOf(p), NOW).single()
        val direct = MeshNodes.nodeFor(here, p, NOW)
        assertEquals(built.name, direct.name)
        assertEquals(built.bearingRad, direct.bearingRad, 1e-6f)
        assertEquals(built.dist, direct.dist, 1e-6f)
        assertEquals(built.located, direct.located)
        assertEquals(built.hops, direct.hops)
    }

    /**
     * And it must give a TRUE bearing even when a lens is up: the spur it feeds
     * is painted on the real world, and a magnification is only a view.
     */
    @Test fun nodeForIgnoresAnyLens() {
        val p = peer(name = "relay", lat = 51.52, lon = -0.10)
        val here = MeshNodes.Here(londonLat, londonLon)
        val trueB = MeshNodes.nodeFor(here, p, NOW).bearingRad
        val lensed = MeshNodes.build(
            here, listOf(p), NOW, lens = Lens.over(listOf(trueB, trueB + 0.02f)),
        ).single()
        assertTrue(
            "a lens must move the DRAWN bearing but not nodeFor's",
            kotlin.math.abs(lensed.bearingRad - trueB) > 1e-4f,
        )
        assertEquals(trueB, MeshNodes.nodeFor(here, p, NOW).bearingRad, 1e-6f)
    }

    // --- findability: near, mine, and drawn ---------------------------------

    /**
     * A node a few metres away used to land at 0.06 of the ring radius — 15 cm
     * from the origin, which is inside the wearer. The operator could not find
     * their own T1000e on 2026-08-03 for exactly this reason.
     */
    @Test fun aVeryNearNodeIsDrawnAtArmsLength() {
        assertEquals(MeshNodes.NEAR_BAND, MeshNodes.bandFor(0.0), 1e-6f)
        // NOT equal to the floor — the range is remapped onto [NEAR_BAND, 1]
        // rather than clamped, so 50 m is still further out than 0 m. The first
        // version of this test asserted the clamp and would have locked in the
        // flattening it was written to prevent.
        assertTrue(MeshNodes.bandFor(0.05) > MeshNodes.NEAR_BAND)
        assertTrue(MeshNodes.bandFor(0.05) < MeshNodes.bandFor(0.5))
        assertTrue("0.6 m at a 2.5 m ring", MeshNodes.NEAR_BAND * 2.5f > 0.5f)
    }

    /** The band still grows with range; only the floor moved. */
    @Test fun theBandStillRisesWithDistance() {
        assertTrue(MeshNodes.bandFor(1.0) > MeshNodes.bandFor(0.0))
        assertTrue(MeshNodes.bandFor(20.0) > MeshNodes.bandFor(1.0))
        assertEquals(1.0f, MeshNodes.bandFor(50.0), 1e-6f)
    }

    /**
     * Ranking IS which nodes exist: layout fills lanes in this order and stops
     * at MAX_MOTES. A node in the same room must not rank below a chatty one
     * forty kilometres away.
     */
    @Test fun nearestOutranksMostRecentlyHeard() {
        val here = MeshNodes.Here(londonLat, londonLon)
        val far = peer(name = "far", lat = 51.9, lon = -0.9)
            .copy(lastSeenEpochSec = NOW)
        val near = peer(name = "near", lat = londonLat + 0.0005, lon = londonLon)
            .copy(lastSeenEpochSec = NOW - 3600)
        val out = MeshNodes.rank(here, listOf(far, near), NOW)
        assertEquals("near", out.first().name)
    }

    /** A favourite is the operator saying "this one is mine". It wins outright. */
    @Test fun aFavouriteOutranksEverything() {
        val here = MeshNodes.Here(londonLat, londonLon)
        val near = peer(name = "near", lat = londonLat + 0.0005, lon = londonLon)
        val mine = peer(name = "mine", lat = 51.9, lon = -0.9).copy(favourite = true)
        val out = MeshNodes.rank(here, listOf(near, mine), NOW)
        assertEquals("mine", out.first().name)
    }

    /** And it survives the trip into a Node, so the ring can mark it. */
    @Test fun favouriteReachesTheNode() {
        val here = MeshNodes.Here(londonLat, londonLon)
        val p = peer(name = "mine", lat = londonLat, lon = londonLon).copy(favourite = true)
        assertTrue(MeshNodes.nodeFor(here, p, NOW).favourite)
    }

    private fun peer(name: String = "relay", lat: Double? = null, lon: Double? = null) =
        MeshNodes.Peer("k1", name, 2, 2, lat, lon, NOW)

    private companion object { const val NOW = 1_785_000_000L }
}
