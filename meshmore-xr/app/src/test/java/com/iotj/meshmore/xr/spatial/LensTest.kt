// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The magnification transform. Almost every case here is about WRAP — the live
 * cluster this exists for spans 357.8 to 004.9, straddling north, which is
 * exactly where naive min/max and plain subtraction give confident wrong
 * answers.
 */
class LensTest {

    private fun deg(d: Double) = Math.toRadians(d).toFloat()
    private fun degOf(r: Float) = Math.toDegrees(r.toDouble()).toFloat()

    /** The real case: Seattle from Portland. */
    private fun seattle() = Lens(deg(357.8), deg(4.9))

    @Test fun aWedgeThatStraddlesNorthHasAPositiveSpan() {
        assertEquals(7.1f, degOf(seattle().span), 0.01f)
    }

    @Test fun theFactorIsTheRingOverTheWedge() {
        assertEquals(360f / 7.1f, seattle().factor, 0.1f)
    }

    @Test fun bearingsInsideTheWedgeAreInside() {
        val l = seattle()
        assertTrue(l.contains(deg(358.0)))
        assertTrue(l.contains(deg(0.0)))
        assertTrue(l.contains(deg(4.5)))
    }

    @Test fun bearingsOutsideAreOutside() {
        val l = seattle()
        assertFalse(l.contains(deg(10.0)))
        assertFalse(l.contains(deg(180.0)))
        assertFalse(l.contains(deg(350.0)))
    }

    /** Magnifying opens the ring AROUND what you pinched; the middle stays put. */
    @Test fun theMidpointDoesNotMove() {
        val l = seattle()
        assertEquals(degOf(l.midpoint), degOf(l.map(l.midpoint)), 0.01f)
    }

    /** The wedge's edges land at the far side — it fills the ring. */
    @Test fun theWedgeFillsTheRing() {
        val l = seattle()
        val a = l.map(deg(357.8))
        val b = l.map(deg(4.9))
        // Half a turn from the midpoint in each direction.
        val spread = Lens.norm(b - a)
        assertTrue("edges should be nearly opposite, got ${degOf(spread)}",
            degOf(spread) > 359f || degOf(spread) < 1f)
    }

    /** Two nodes a degree apart become fifty degrees apart. That is the point. */
    @Test fun neighboursSeparate() {
        val l = seattle()
        val d = Lens.norm(l.map(deg(1.0)) - l.map(deg(0.0)))
        assertEquals(l.factor, degOf(d), 2f)
    }

    // ---- building a lens over a set ---------------------------------------

    /**
     * The set that straddles north. A min/max extent would call this a 359
     * degree wedge — the whole ring minus a sliver — and magnify by nothing.
     */
    @Test fun aWrappedSetGetsTheShortWedgeNotTheLongOne() {
        val l = Lens.over(listOf(deg(358.0), deg(359.5), deg(1.0), deg(3.0)))
        assertNotNull(l)
        assertTrue("span should be ~5 deg plus padding, got ${degOf(l!!.span)}",
            degOf(l.span) in 5f..8f)
    }

    @Test fun anOrdinarySetIsUnsurprising() {
        val l = Lens.over(listOf(deg(100.0), deg(104.0), deg(107.0)))!!
        assertTrue(degOf(l.span) in 7f..10f)
        assertTrue(l.contains(deg(104.0)))
    }

    /** Padding keeps the outermost nodes off the seam behind the user's head. */
    @Test fun theWedgeIsPaddedBeyondItsMembers() {
        val l = Lens.over(listOf(deg(0.0), deg(6.0)))!!
        assertTrue(l.contains(deg(0.0)))
        assertTrue(l.contains(deg(6.0)))
        assertTrue("padded", degOf(l.span) > 6f)
    }

    @Test fun anEmptySetHasNoLens() {
        assertNull(Lens.over(emptyList()))
    }

    /** One node is a legitimate answer, not a division by zero. */
    @Test fun aSingleBearingIsSafe() {
        val l = Lens.over(listOf(deg(42.0)))!!
        assertTrue(l.factor.isFinite())
        assertTrue(l.factor > 1f)
    }

    /**
     * A vanishingly narrow wedge is clamped. At 0.1 degrees the factor is 3600
     * and a hand tremor sweeps the entire ring.
     */
    @Test fun anImpossiblyNarrowWedgeIsClamped() {
        val l = Lens(deg(10.0), deg(10.0))
        assertEquals(Lens.MIN_SPAN, l.span, 1e-6f)
        assertTrue(l.factor.isFinite())
    }

    @Test fun normalisationIsTotal() {
        assertEquals(0f, degOf(Lens.norm(deg(360.0))), 0.01f)
        assertEquals(350f, degOf(Lens.norm(deg(-10.0))), 0.01f)
        assertEquals(10f, degOf(Lens.norm(deg(730.0))), 0.01f)
    }
}

/** The lens applied to a real build: what actually reaches the ring. */
class LensBuildTest {

    private fun deg(d: Double) = Math.toRadians(d).toFloat()
    private val NOW = 1_770_000_000L
    private val here = MeshNodes.Here(45.5068, -122.7660)   // Portland

    /** 120 peers strung across Seattle: one bearing cluster, as in the field. */
    private fun seattleMesh() = (0 until 120).map {
        MeshNodes.Peer(
            key = "k$it", name = "node $it", type = 2, hops = 2,
            lat = 47.55 + (it % 12) * 0.02, lon = -122.40 + (it / 12) * 0.03,
            lastSeenEpochSec = NOW - it,
        )
    }

    /** Without a lens this is the situation the feature exists for. */
    @Test fun unmagnifiedMostOfTheMeshIsACount() {
        val out = MeshNodes.build(here, seattleMesh(), NOW)
        val labelled = out.count { it.cluster == 0 }
        val counted = out.sumOf { it.cluster }
        assertTrue("only a handful can be labelled, got $labelled", labelled <= MeshNodes.LANES)
        assertTrue("the rest are counted, got $counted", counted > 100)
    }

    /** With a lens over them, the same nodes get their own places. */
    @Test fun magnifiedFarMoreAreLabelled() {
        val mesh = seattleMesh()
        val bearings = mesh.map { MeshNodes.bearingRad(here.lat!!, here.lon!!, it.lat!!, it.lon!!) }
        val lens = Lens.over(bearings)!!
        val out = MeshNodes.build(here, mesh, NOW, lens = lens)
        val labelled = out.count { it.cluster == 0 }
        assertTrue("magnification should label many more, got $labelled",
            labelled > MeshNodes.LANES * 2)
    }

    /** Nothing outside the wedge is drawn — the ring belongs to the wedge now. */
    @Test fun theRestOfTheMeshIsExcluded() {
        val mesh = seattleMesh() + MeshNodes.Peer(
            key = "far", name = "elsewhere", type = 2, hops = 1,
            lat = 45.40, lon = -122.60, lastSeenEpochSec = NOW,   // just south
        )
        val bearings = seattleMesh().map {
            MeshNodes.bearingRad(here.lat!!, here.lon!!, it.lat!!, it.lon!!)
        }
        val out = MeshNodes.build(here, mesh, NOW, lens = Lens.over(bearings)!!)
        assertTrue("the southern node must not appear",
            out.none { it.name == "elsewhere" })
    }

    /** Magnification is ANGULAR. Range bands are untouched. */
    @Test fun distanceIsNotMagnified() {
        val mesh = seattleMesh()
        val bearings = mesh.map { MeshNodes.bearingRad(here.lat!!, here.lon!!, it.lat!!, it.lon!!) }
        val plain = MeshNodes.build(here, mesh, NOW)
        val lensed = MeshNodes.build(here, mesh, NOW, lens = Lens.over(bearings)!!)
        val a = plain.filter { it.cluster == 0 }.map { it.dist }.average()
        val b = lensed.filter { it.cluster == 0 }.map { it.dist }.average()
        assertEquals("range bands must not move", a, b, 0.25)
    }
}
