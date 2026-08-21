// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * HOW LONG BEFORE A MESSAGE IS CALLED LOST.
 *
 * Checked against the numbers a real radio quoted rather than against a story
 * about them: thirty packets at D38F07AED563 on 2026-08-20 were quoted 2448 ms
 * for 48 bytes, 3000 ms for 96 and 3858 ms for 140, on the same direct route,
 * and every acknowledgement that came back did so inside 1535 ms.
 *
 * The old rule waited sixty seconds for all of them.
 */
class LostDeadlineTest {

    /** The three estimates this mesh actually produces. */
    private val MEASURED = listOf(2448L, 3000L, 3858L)

    @Test fun everyRealEstimateSettlesInsideTwentySeconds() {
        MEASURED.forEach { est ->
            val d = MeshLink.lostAfterMsFor(est)
            assertTrue("$est -> $d", d <= 20_000L)
        }
    }

    /** And none of them concludes before a wearer would expect it to. */
    @Test fun noneConcludesFasterThanTheFloor() {
        MEASURED.forEach { est ->
            assertTrue(MeshLink.lostAfterMsFor(est) >= MeshLink.LOST_FLOOR_MS)
        }
    }

    /**
     * THE MARGIN OVER WHAT WAS OBSERVED. The slowest ack ever measured here is
     * 1535 ms, so even the shortest deadline is more than six times it.
     */
    @Test fun theShortestDeadlineIsManyTimesTheSlowestAck() {
        val slowestObserved = 1535L
        val shortest = MEASURED.minOf { MeshLink.lostAfterMsFor(it) }
        assertTrue("$shortest vs $slowestObserved", shortest >= slowestObserved * 6)
    }

    @Test fun aFloodedEstimateIsCappedRatherThanBelieved() {
        assertEquals(MeshLink.LOST_CAP_MS, MeshLink.lostAfterMsFor(30_000L))
        assertEquals(MeshLink.LOST_CAP_MS, MeshLink.lostAfterMsFor(999_999L))
    }

    /** No estimate at all is the one case that keeps a flat window. */
    @Test fun noEstimateFallsBackToTheFlatWindow() {
        assertEquals(MeshLink.LOST_AFTER_DEFAULT_MS, MeshLink.lostAfterMsFor(0L))
        assertEquals(MeshLink.LOST_AFTER_DEFAULT_MS, MeshLink.lostAfterMsFor(-1L))
    }

    /** A bigger packet is quoted more time, so it must also be allowed more. */
    @Test fun aLongerMessageGetsLonger() {
        val short = MeshLink.lostAfterMsFor(2448L)
        val long = MeshLink.lostAfterMsFor(3858L)
        assertTrue("$short vs $long", long > short)
    }
}
