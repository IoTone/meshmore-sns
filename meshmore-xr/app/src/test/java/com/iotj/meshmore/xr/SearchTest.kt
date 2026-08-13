// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.MeshNodes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * FINDING ONE NODE IN THREE HUNDRED AND FIFTY.
 *
 * The ring draws 24 of 350, and whichever 24 the ranker picks, the node the
 * wearer is looking for is probably not among them. These pin the narrowing:
 * what counts as a match, and what the panel says about it — because a search
 * that finds nothing and says nothing is indistinguishable from one that never
 * ran, and those call for opposite next moves.
 */
class SearchTest {

    private fun peer(
        name: String,
        key: String = "aabbcc",
        full: String? = null,
    ) = MeshNodes.Peer(
        key = key, name = name, type = 1, hops = 1,
        lat = null, lon = null, lastSeenEpochSec = 1_000L, fullKey = full,
    )

    private val mesh = listOf(
        peer("Collins View Open RS", key = "80db2b"),
        peer("Downtown Repeater", key = "11faf0"),
        peer("WA7TCH REPEATER 2", key = "99a11a"),
        peer("Harness Mountain", key = "c03f38", full = "c03f3811d666"),
    )

    /** An empty query is not a filter. The ring stays whole. */
    @Test fun nothingTypedMeansNothingHidden() {
        assertEquals(mesh.size, Search.apply(mesh, "").size)
        assertEquals(mesh.size, Search.apply(mesh, "   ").size)
    }

    /**
     * SUBSTRING, NOT PREFIX. MeshCore names are phrases — the useful word in
     * "Collins View Open RS" is in the middle, and a prefix search would find
     * it only for somebody who already knew how it started.
     */
    @Test fun theInterestingWordIsUsuallyInTheMiddle() {
        assertEquals(1, Search.apply(mesh, "view").size)
        assertEquals(2, Search.apply(mesh, "repeater").size)
    }

    /**
     * CASE ON BOTH SIDES. Names come off other people's radios in whatever case
     * they typed them, and a soft keyboard capitalises whatever it feels like.
     */
    @Test fun caseIsNeverTheReasonSomethingIsNotFound() {
        listOf("DOWNTOWN", "downtown", "DownTown").forEach {
            assertEquals("'$it' should match", 1, Search.apply(mesh, it).size)
        }
    }

    /**
     * THE KEY, AND BOTH FORMS OF IT. A key prefix is what somebody reads off
     * another app's screen when a callsign is duplicated or missing. Matching
     * only the short form would work in half the cases and read as an
     * unreliable search rather than a narrow one.
     */
    @Test fun aKeyFindsItsNode() {
        assertEquals(1, Search.apply(mesh, "80db").size)
        // The full key, which is what the other app was displaying.
        assertEquals(1, Search.apply(mesh, "11d666").size)
    }

    /** A query nothing matches returns nothing — not everything. */
    @Test fun noMatchIsAnEmptyRingAndNotAFullOne() {
        assertTrue(Search.apply(mesh, "zzzz").isEmpty())
    }

    /** Order survives; the ranker downstream is entitled to its own opinion. */
    @Test fun filteringDoesNotReorder() {
        val got = Search.apply(mesh, "e").map { it.name }
        assertEquals(got, mesh.filter { Search.matches(it, "e") }.map { it.name })
    }

    /**
     * ZERO IS THE ANSWER THAT MATTERS. "No matches" and "not searching" look
     * identical on a ring that was already sparse.
     */
    @Test fun theSummarySeparatesEmptyFromUnfiltered() {
        assertEquals("350 NODES", Search.summary(0, 350, ""))
        assertEquals("NO MATCH IN 350", Search.summary(0, 350, "zzz"))
        assertEquals("4 OF 350", Search.summary(4, 350, "rep"))
    }

    /**
     * The query is bounded, and bounded in ONE place — the panel shows what the
     * filter uses, so a query trimmed for matching but not for display would
     * have the wearer reading a search that is not the one running.
     */
    @Test fun theQueryIsBoundedOnceForBothUses() {
        val long = "M".repeat(100)
        assertEquals(Search.MAX, Search.normalise(long).length)
        assertEquals("abc", Search.normalise("  abc  "))
    }
}
