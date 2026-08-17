// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.MeshNodes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

    // --- the wearer's own marks ---------------------------------------------
    //
    // "I can't remember the names or UIDs of my friend's nodes." A MeshCore name
    // is whatever its owner typed and a key is 64 hex characters; what a person
    // remembers is that it was a friend, or that it was on that trip.

    private val favs = setOf("Downtown Repeater")
    private val tagged = mapOf(
        "Harness Mountain" to listOf("hike"),
        "Downtown Repeater" to listOf("Hike", "work"),
    )

    private fun apply(q: Search.Query) = Search.apply(
        mesh, q,
        isFavourite = { it.name in favs },
        tagsOf = { tagged[it.name] ?: emptyList() },
    )

    /** An empty query is still not a filter, whatever shape it has. */
    @Test fun anEmptyQueryIsNotActive() {
        assertTrue(!Search.Query().active)
        assertEquals(mesh.size, apply(Search.Query()).size)
    }

    @Test fun favouritesNarrowToTheOnesYouMarked() {
        val got = apply(Search.Query(favourites = true))
        assertEquals(1, got.size)
        assertEquals("Downtown Repeater", got[0].name)
    }

    /**
     * TAGS MATCH CASE-INSENSITIVELY. A tag typed at the node and a tag tapped
     * on a chip are the same tag however either keyboard capitalised it — "Hike"
     * on one node and "hike" on another is one group to a person.
     */
    @Test fun aTagFindsItsGroupWhateverTheCase() {
        assertEquals(2, apply(Search.Query(tag = "hike")).size)
        assertEquals(2, apply(Search.Query(tag = "HIKE")).size)
        assertEquals(1, apply(Search.Query(tag = "work")).size)
    }

    /**
     * ANDed, NOT ORed. Narrowing is the whole job: favourites OR anything
     * matching "rep" is a bigger ring than the one you started from, which is
     * the opposite of what somebody who opened a search wanted.
     */
    @Test fun theTermsNarrowEachOther() {
        // "hike" alone is two; a favourite alone is one; together, one.
        assertEquals(1, apply(Search.Query(tag = "hike", favourites = true)).size)
        // ...and text narrows it further, to nothing.
        assertTrue(
            apply(Search.Query(text = "harness", tag = "hike", favourites = true)).isEmpty(),
        )
    }

    /**
     * A wearer who taps FAVOURITES having starred nobody gets an empty ring, and
     * "350 NODES" under it would be the app disagreeing with itself.
     */
    @Test fun aMarkOnlyQueryStillReportsNoMatch() {
        assertEquals("NO MATCH IN 350", Search.summary(0, 350, Search.Query(favourites = true)))
        assertEquals("350 NODES", Search.summary(350, 350, Search.Query()))
        assertEquals("2 OF 350", Search.summary(2, 350, Search.Query(tag = "hike")))
    }

    // ------------------------------------------------------------------
    // DISTANCE AND SILENCE — the two axes a crowded mesh is pruned along.
    // ------------------------------------------------------------------

    private fun far(km: Double) = Search.Query(farKm = km)

    /**
     * NULL IS NOT FAR, and this is the test that says so. A GPS-less board
     * reports nothing forever; if "unknown" satisfied a distance filter, the
     * bulk forget behind that filter would select precisely the quiet local
     * nodes the operator is trying to keep.
     */
    @Test fun unknownDistanceNeverMatchesAFarFilter() {
        val peers = listOf(peer("a", key = "a"), peer("b", key = "b"))
        val out = Search.apply(
            peers, far(50.0), isFavourite = { false }, tagsOf = { emptyList() },
            distanceKm = { p -> if (p.key == "a") 400.0 else null },
        )
        assertEquals(listOf("a"), out.map { it.key })
    }

    @Test fun theFarFilterIsInclusiveAtItsThreshold() {
        val peers = listOf(peer("under", key = "under"), peer("on", key = "on"), peer("over", key = "over"))
        val d = mapOf("under" to 49.9, "on" to 50.0, "over" to 50.1)
        val out = Search.apply(
            peers, far(50.0), isFavourite = { false }, tagsOf = { emptyList() },
            distanceKm = { d[it.key] },
        )
        assertEquals(listOf("on", "over"), out.map { it.key })
    }

    @Test fun unknownAgeNeverMatchesAStaleFilter() {
        val peers = listOf(peer("old", key = "old"), peer("undated", key = "undated"))
        val out = Search.apply(
            peers, Search.Query(staleHours = 6), isFavourite = { false }, tagsOf = { emptyList() },
            ageHours = { p -> if (p.key == "old") 48.0 else null },
        )
        assertEquals(listOf("old"), out.map { it.key })
    }

    /** Terms narrow together, so FAR + STALE is the intersection and not the union. */
    @Test fun distanceAndSilenceNarrowTogether() {
        val peers = listOf(peer("farOld", key = "farOld"), peer("farFresh", key = "farFresh"), peer("nearOld", key = "nearOld"))
        val km = mapOf("farOld" to 300.0, "farFresh" to 300.0, "nearOld" to 2.0)
        val hrs = mapOf("farOld" to 90.0, "farFresh" to 0.2, "nearOld" to 90.0)
        val out = Search.apply(
            peers, Search.Query(farKm = 100.0, staleHours = 24),
            isFavourite = { false }, tagsOf = { emptyList() },
            distanceKm = { km[it.key] }, ageHours = { hrs[it.key] },
        )
        assertEquals(listOf("farOld"), out.map { it.key })
    }

    /**
     * A TEXT SEARCH IS NOT A SWEEP. The bulk forget only appears for filters
     * that are about WHICH nodes; without this, typing "a" and hitting forget
     * would delete half a mesh.
     */
    @Test fun onlyDistanceOrSilenceMakesAQuerySweepable() {
        assertFalse(Search.Query(text = "portland").isSweepable)
        assertFalse(Search.Query(favourites = true).isSweepable)
        assertFalse(Search.Query(tag = "hike").isSweepable)
        assertTrue(Search.Query(farKm = 25.0).isSweepable)
        assertTrue(Search.Query(staleHours = 6).isSweepable)
    }

    @Test fun theStepsAreOrderedAndEndInOff() {
        assertEquals(Search.FAR_STEPS.sorted(), Search.FAR_STEPS)
        assertEquals(Search.STALE_STEPS.sorted(), Search.STALE_STEPS)
        // Stepping past the last one turns the chip off, which is how a wearer
        // gets back to "no distance filter" without a second control.
        assertEquals(null, Search.FAR_STEPS.getOrNull(Search.FAR_STEPS.size))
        assertEquals(null, Search.STALE_STEPS.getOrNull(Search.STALE_STEPS.size))
    }
}
