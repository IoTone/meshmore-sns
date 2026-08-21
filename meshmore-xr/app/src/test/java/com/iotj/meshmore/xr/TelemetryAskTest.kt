// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.MeshNodes
import com.iotj.meshmore.xr.spatial.TelemetryPerms
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * WHO GETS ASKED, AND WHERE THE OTHER THREE HUNDRED WENT.
 *
 * The complaint this answers is "it is so hard to get telemetry from any of
 * the hundreds of devices in range", and the most important property below is
 * not the choosing — it is the CENSUS. A sweep that asks 40 of 350 and cannot
 * say what happened to the other 310 is indistinguishable from a broken one.
 */
class TelemetryAskTest {

    private val NOW = 1_800_000_000L

    private fun peer(
        n: String,
        hops: Int = 1,
        full: Boolean = true,
        lat: Double? = 45.51,
        lon: Double? = -122.68,
        telemAgeS: Long? = null,
    ) = MeshNodes.Peer(
        key = n.take(12).padEnd(12, '0'),
        fullKey = if (full) n.padEnd(64, 'a') else null,
        name = n, type = 1, hops = hops,
        lat = lat, lon = lon,
        lastSeenEpochSec = NOW - 60,
        telemetry = telemAgeS?.let { MeshNodes.Telemetry(atEpochSec = NOW - it, tempC = 20.0) },
    )

    /**
     * A contact with NO STORED ROUTE, which is what MeshCore's 0xFF path
     * length becomes: hops = 256 and the flood flag set. On the operator's own
     * mesh this is 349 of 350 contacts.
     */
    private fun unrouted(n: String, heardAgoS: Long = 60) = peer(n).copy(
        hops = 256, flood = true, lastSeenEpochSec = NOW - heardAgoS,
    )

    private val here = MeshNodes.Here(45.5152, -122.6784)

    @Test fun aPlainNearbyNodeIsAsked() {
        val p = TelemetryAsk.plan(listOf(peer("near")), here, NOW)
        assertEquals(1, p.askCount)
        assertTrue(p.skipped.isEmpty())
    }

    /** A prefix cannot be asked at all — the request needs all 32 bytes. */
    @Test fun aNodeWithoutAFullKeyIsCountedNotIgnored() {
        val p = TelemetryAsk.plan(listOf(peer("heardonly", full = false)), here, NOW)
        assertEquals(0, p.askCount)
        assertEquals(1, p.skipped[TelemetryAsk.Skip.NO_FULL_KEY])
    }

    @Test fun distantInHopsAndDistantInKmAreDifferentReasons() {
        val far = peer("faraway", hops = 5)
        val hilltop = peer("hilltop", hops = 1, lat = 48.0, lon = -122.68)
        val p = TelemetryAsk.plan(listOf(far, hilltop), here, NOW)
        assertEquals(0, p.askCount)
        assertEquals(1, p.skipped[TelemetryAsk.Skip.TOO_FAR_IN_HOPS])
        assertEquals(1, p.skipped[TelemetryAsk.Skip.TOO_FAR_IN_KM])
    }

    /**
     * NO POSITION IS NOT FAR AWAY. Most of this operator's mesh has no
     * position, and excluding the unmeasured would empty the sweep.
     */
    @Test fun aNodeWithNoPositionIsStillAsked() {
        val p = TelemetryAsk.plan(listOf(peer("nowhere", lat = null, lon = null)), here, NOW)
        assertEquals(1, p.askCount)
    }

    /** And with no fix of our own, distance cannot disqualify anybody. */
    @Test fun withNoFixOfOurOwnDistanceIsNotUsed() {
        val hilltop = peer("hilltop", lat = 48.0, lon = -122.68)
        assertEquals(1, TelemetryAsk.plan(listOf(hilltop), null, NOW).askCount)
    }

    @Test fun aFreshReadingNeedsNoAsk() {
        val p = TelemetryAsk.plan(listOf(peer("warm", telemAgeS = 60)), here, NOW)
        assertEquals(0, p.askCount)
        assertEquals(1, p.skipped[TelemetryAsk.Skip.ALREADY_FRESH])
    }

    /** A stale one does. */
    @Test fun anOldReadingIsRefreshed() {
        val p = TelemetryAsk.plan(listOf(peer("cold", telemAgeS = 3600)), here, NOW)
        assertEquals(1, p.askCount)
    }

    @Test fun aNodeAskedRecentlyIsLeftAlone() {
        val n = peer("recent")
        val p = TelemetryAsk.plan(
            listOf(n), here, NOW, asked = mapOf(n.fullKey!! to NOW - 60),
        )
        assertEquals(0, p.askCount)
        assertEquals(1, p.skipped[TelemetryAsk.Skip.COOLING_DOWN])
    }

    /** The budget is reported, never silently applied. */
    @Test fun theBudgetIsCountedAsASkipReason() {
        val many = (1..60).map { peer("node$it") }
        val p = TelemetryAsk.plan(many, here, NOW)
        assertEquals(TelemetryAsk.MAX_PER_SWEEP, p.askCount)
        assertEquals(60 - TelemetryAsk.MAX_PER_SWEEP, p.skipped[TelemetryAsk.Skip.OVER_BUDGET])
    }

    /** Cheapest first: fewer hops beats nearer. */
    @Test fun theOrderSpendsOtherPeoplesRelaysLast() {
        val twoHopClose = peer("twohop", hops = 2, lat = 45.5152, lon = -122.6784)
        val oneHopFar = peer("onehop", hops = 1, lat = 45.9, lon = -122.68)
        val p = TelemetryAsk.plan(listOf(twoHopClose, oneHopFar), here, NOW)
        assertEquals(listOf("onehop", "twohop"), p.ask.map { it.name })
    }

    /**
     * THE CENSUS IS THE POINT. Every node is either asked or accounted for,
     * and the arithmetic has to close.
     */
    @Test fun everyNodeIsEitherAskedOrExplained() {
        val mesh = (1..30).map { peer("n$it") } +
            (1..12).map { peer("p$it", full = false) } +
            (1..7).map { peer("f$it", hops = 9) } +
            (1..5).map { peer("h$it", lat = 49.0, lon = -122.68) } +
            (1..3).map { peer("w$it", telemAgeS = 30) }
        val p = TelemetryAsk.plan(mesh, here, NOW)
        assertEquals(57, p.considered)
        assertEquals(p.considered, p.askCount + p.skipped.values.sum())
        val lines = p.census()
        assertTrue(lines.first().startsWith("57 "))
        assertTrue(lines.last() == "= ${p.askCount} to ask")
    }

    // --- the nudge ----------------------------------------------------------

    /** Offered once, and only when the wearer really is sharing nothing. */
    @Test fun sharingIsOfferedOnlyWhenAskingWhileDenying() {
        assertTrue(TelemetryAsk.shouldOfferSharing(TelemetryPerms.DENY, false, 12))
        assertFalse("already sharing", TelemetryAsk.shouldOfferSharing(TelemetryPerms.ALLOW_FLAGS, false, 12))
        assertFalse("asked before", TelemetryAsk.shouldOfferSharing(TelemetryPerms.DENY, true, 12))
        assertFalse("no sweep happened", TelemetryAsk.shouldOfferSharing(TelemetryPerms.DENY, false, 0))
    }

    /** The report prints the denominator, so a quiet mesh is legible as such. */
    @Test fun theReportShowsWhatWasAskedNotJustWhatAnswered() {
        assertEquals(
            "asked 40, answered 6 (15%), 4 with a sensor",
            TelemetryAsk.report(40, 6, 4),
        )
        assertEquals("asked 0, answered 0, 0 with a sensor", TelemetryAsk.report(0, 0, 0))
    }

    // --- the unrouted, which is nearly the whole mesh ------------------------

    /**
     * THE BUG THIS FILE EXISTS FOR. A first sweep on the real mesh asked ONE
     * radio of 350 and reported "-349 more than 2 hops away", because a
     * contact with no stored route arrives as hops = 256 and the planner read
     * the sentinel as a distance. The rest of the app already knew better —
     * the roster splits on `hops in 2..249`.
     */
    @Test fun anUnroutedNodeIsNotAFarawayNode() {
        val mesh = (1..20).map { unrouted("u$it") }
        val p = TelemetryAsk.plan(mesh, here, NOW)
        assertEquals(0, p.skipped[TelemetryAsk.Skip.TOO_FAR_IN_HOPS] ?: 0)
        assertEquals(TelemetryAsk.FLOOD_BUDGET, p.askCount)
    }

    /** Flooding is rationed separately, and the remainder is reported. */
    @Test fun unroutedNodesGetTheirOwnSmallerBudget() {
        val mesh = (1..30).map { unrouted("u$it") }
        val p = TelemetryAsk.plan(mesh, here, NOW)
        assertEquals(TelemetryAsk.FLOOD_BUDGET, p.askCount)
        assertEquals(30 - TelemetryAsk.FLOOD_BUDGET, p.skipped[TelemetryAsk.Skip.OVER_FLOOD_BUDGET])
    }

    /** A flood at a node nobody has heard from in days is a shot in the dark. */
    @Test fun anUnroutedNodeNotHeardLatelyIsNotWorthAFlood() {
        val p = TelemetryAsk.plan(listOf(unrouted("gone", heardAgoS = 3 * 24 * 3600)), here, NOW)
        assertEquals(0, p.askCount)
        assertEquals(1, p.skipped[TelemetryAsk.Skip.UNROUTED_AND_STALE])
    }

    /** Cheap before expensive: a stored route costs less than a flood. */
    @Test fun routedNodesAreAskedBeforeUnroutedOnes() {
        val mesh = listOf(unrouted("flood1"), peer("routed"), unrouted("flood2"))
        val p = TelemetryAsk.plan(mesh, here, NOW)
        assertEquals("routed", p.ask.first().name)
    }

    /** And among floods, the one heard most recently is the best bet. */
    @Test fun theMostRecentlyHeardFloodGoesFirst() {
        val mesh = listOf(unrouted("old", heardAgoS = 3000), unrouted("fresh", heardAgoS = 30))
        val p = TelemetryAsk.plan(mesh, here, NOW)
        assertEquals(listOf("fresh", "old"), p.ask.map { it.name })
    }

    /** The census still closes with the two new reasons in it. */
    @Test fun everyNodeIsStillEitherAskedOrExplained() {
        val mesh = (1..40).map { unrouted("u$it") } +
            (1..5).map { unrouted("s$it", heardAgoS = 9 * 3600) } +
            (1..10).map { peer("r$it") } +
            (1..6).map { peer("k$it", full = false) }
        val p = TelemetryAsk.plan(mesh, here, NOW)
        assertEquals(61, p.considered)
        assertEquals(p.considered, p.askCount + p.skipped.values.sum())
    }
}
