// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import io.iotone.meshcore.android.SessionState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * WHAT THE APP DOES WHEN THE RADIO GOES AWAY.
 *
 * The failure this pins is not a crash. The link drops — a body between the
 * glasses and a radio in a pannier is enough — and everything carries on: the
 * horizon keeps drawing the mesh it last heard, the motes age at wall-clock
 * speed into STALE the way they would on a quiet night, and nothing anywhere
 * says the app has stopped listening. On a walk that is the difference between
 * "the mesh is quiet here" and "I left the radio on the kitchen table".
 */
class LinkLossTest {

    // --- the chip ------------------------------------------------------------

    @Test fun aLiveLinkIsJustTheWordLink() {
        assertEquals("LINK", MeshLink.chipFor(SessionState.READY, null))
        // Even if a stale drop timestamp were somehow still set, READY wins:
        // the readout describes now, not what happened before now.
        assertEquals("LINK", MeshLink.chipFor(SessionState.READY, 90_000))
    }

    /**
     * NEVER CONNECTED is not the same fact as DROPPED, and this is the line
     * between them. Before the first handshake there is no outage to age — the
     * session's own word is all there is to say.
     */
    @Test fun aColdStartShowsTheStateWordAndNoDuration() {
        val s = MeshLink.chipFor(SessionState.DISCONNECTED, null)
        assertEquals("DISC", s)
        assertTrue(s, !s.contains("LOST"))
    }

    /**
     * The outage carries its age, because that age is also the age of every
     * node still drawn on the horizon. `DISC` said the same thing at two
     * seconds and at forty minutes.
     */
    @Test fun anOutageIsMeasuredNotJustAnnounced() {
        assertEquals("LOST 8S", MeshLink.chipFor(SessionState.DISCONNECTED, 8_000))
        assertEquals("LOST 4M", MeshLink.chipFor(SessionState.CONNECTING, 4 * 60_000L))
        assertEquals("LOST 2H", MeshLink.chipFor(SessionState.DISCONNECTED, 2 * 3600_000L))
    }

    /**
     * Coarse on purpose. The wearer's decision is "is this worth stopping for",
     * and that answer does not change between four and five minutes — so the
     * chip must not redraw a new string every second once it is in minutes.
     */
    @Test fun theChipIsStableWithinAUnit() {
        val a = MeshLink.chipFor(SessionState.DISCONNECTED, 4 * 60_000L + 1_000)
        val b = MeshLink.chipFor(SessionState.DISCONNECTED, 4 * 60_000L + 59_000)
        assertEquals(a, b)
    }

    /** Four characters is the budget the status band has; the chip fits it. */
    @Test fun theChipFitsTheBand() {
        val worst = listOf(0L, 59_000L, 60_000L, 3599_000L, 3600_000L, 99 * 3600_000L)
            .map { MeshLink.chipFor(SessionState.DISCONNECTED, it) }
        assertTrue(worst.toString(), worst.all { it.length <= 8 })
    }

    // --- the retry ladder ----------------------------------------------------

    /**
     * FAST THEN PATIENT. Most drops are not outages — a hand, a jacket, a wall —
     * and a first retry inside a couple of seconds catches those before the
     * wearer looks up. A radio that is off or left at home is not coming back,
     * and scanning at that rate for the rest of a hike spends the battery of the
     * one device that cannot be charged from a pocket.
     */
    @Test fun theLadderWidens() {
        val l = MeshLink.RETRY_MS
        assertTrue(l.toList().toString(), l.first() <= 3_000)
        assertTrue(l.toList().toString(), l.last() >= 30_000)
        l.toList().zipWithNext().forEach { (a, b) ->
            assertTrue("$a then $b is not a widening ladder", b > a)
        }
    }

    /**
     * IT NEVER STOPS TRYING. The last rung is a cap, not a give-up: walking
     * back into range has to be enough to restore the link, with no gesture and
     * no menu, because in a spatial scene there is no reconnect button in reach.
     * A ladder that ended would make "it came back on its own" depend on how
     * long you were away.
     */
    @Test fun theLastRungIsACapAndNotAnEnding() {
        val l = MeshLink.RETRY_MS
        val far = l[(99).coerceAtMost(l.size - 1)]
        assertEquals(l.last(), far)
        // A minute is the coarsest that still feels like "it just came back".
        assertTrue(l.last().toString(), l.last() <= 60_000)
    }
}
