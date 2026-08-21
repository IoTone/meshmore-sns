// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE ANALYSIS, AGAINST RUNS WHOSE ANSWER IS KNOWN.
 *
 * The point of the ledger is to tell three different one-in-ten losses apart,
 * so each is built here on purpose and the report is required to name the
 * right one. A report that says "90%" for all three is the report this app
 * already had.
 */
class TxLogTest {

    private fun a(
        seq: Int, bytes: Int = 64, hops: Int = 1, flood: Boolean = false,
        acked: Boolean = true, accepted: Boolean = true, ms: Long = 2000,
    ) = TxLog.Attempt(
        seq = seq, atMs = seq * 1000L, bytes = bytes, peer = "d563", hops = hops,
        accepted = accepted, flood = if (accepted) flood else null,
        tag = seq.toLong(), ackMs = if (acked) ms else null, gaveUp = !acked,
    )

    /** A loss that lands only on the long messages is a payload problem. */
    @Test fun lossOnTheLongMessagesIsNamed() {
        val run = (1..10).map { a(it, bytes = if (it % 2 == 0) 140 else 40, acked = it % 4 != 0) }
        val head = TxLog.headline(run)
        assertTrue(head, head.contains("128-160 B"))
    }

    /** A loss that lands only on flooded messages is an airtime problem. */
    @Test fun lossOnTheFloodedMessagesIsNamed() {
        val run = (1..10).map { a(it, flood = it > 5, acked = it <= 7) }
        val head = TxLog.headline(run)
        assertTrue(head, head.contains("FLOOD"))
    }

    /** Spread evenly, there is no worst slice to name and it must not invent one. */
    @Test fun anEvenLossNamesNothing() {
        val run = (1..10).map { a(it, bytes = 40 + it, acked = it != 5) }
        assertEquals("9/10 DELIVERED", TxLog.headline(run))
    }

    /**
     * NEVER LEFT THE RADIO IS NOT LOST IN THE AIR. Summing them was the
     * mistake that made the original question unanswerable.
     */
    @Test fun refusalsAreKeptApartFromAirLosses() {
        val run = listOf(a(1), a(2, accepted = false, acked = false), a(3, acked = false))
        val r = TxLog.report(run).joinToString("\n")
        assertTrue(r, r.contains("1 never left the radio"))
        assertTrue(r, r.contains("2 reached the air"))
        assertTrue(r, r.contains("1 lost in the air"))
    }

    /** An attempt still inside its window is not a loss. */
    @Test fun messagesStillInFlightAreNotCountedAsLost() {
        val inFlight = TxLog.Attempt(
            seq = 9, atMs = 0, bytes = 64, peer = "d563", hops = 1,
            accepted = true, flood = false, ackMs = null, gaveUp = false,
        )
        val run = listOf(a(1), a(2), inFlight)
        val r = TxLog.report(run).joinToString("\n")
        assertTrue(r, r.contains("2 reached the air"))
        assertTrue(r, r.contains("1 still inside its ack window"))
        assertTrue(r, r.contains("0 lost in the air"))
    }

    /** A mean hides a bimodal link; percentiles are the point of keeping each one. */
    @Test fun percentilesSeparateTheTwoRoutes() {
        val fast = (1..9).map { a(it, ms = 2000) }
        val slow = listOf(a(10, flood = true, ms = 9000))
        val l = TxLog.latency(fast + slow)!!
        assertEquals(10, l.n)
        assertEquals(2000, l.p50)
        assertEquals(9000, l.worst)
    }

    @Test fun sizeBucketsCoverEverythingIncludingOversize() {
        assertEquals("0-32 B", TxLog.sizeBucket(1))
        assertEquals("0-32 B", TxLog.sizeBucket(32))
        assertEquals("32-64 B", TxLog.sizeBucket(33))
        assertEquals("128-160 B", TxLog.sizeBucket(135))
        assertEquals(">160 B", TxLog.sizeBucket(400))
    }

    @Test fun anEmptyLedgerSaysSoRatherThanDividingByZero() {
        assertEquals(listOf("no sends recorded"), TxLog.report(emptyList()))
        assertEquals("NO SENDS TO REPORT", TxLog.headline(emptyList()))
        assertNull(TxLog.latency(emptyList()))
    }

    /** A slice with too few sends must not be promoted to a finding. */
    @Test fun aSingleUnluckySendIsNotAFinding() {
        val run = (1..12).map { a(it, flood = it == 12, acked = it != 12) }
        assertEquals("11/12 DELIVERED", TxLog.headline(run))
    }

    /**
     * THE BAY'S OWN CONTENT.
     *
     * A row is 28 cells in English and 26 in Japanese, so the pairs have to be
     * short enough that the row builder is trimming nothing that matters. The
     * exact strings are asserted because this surface cannot be photographed:
     * the emulator's only display is FLAG_SECURE and the glass refuses too, so
     * a test is the only place the words can be read before a wearer reads
     * them.
     */
    @Test fun theBayRowsSayWhatHappened() {
        val run = (1..10).map { a(it, bytes = if (it % 2 == 0) 140 else 40, acked = it != 4) }
        val rows = TxLog.rows(run).toMap()
        assertEquals("10", rows["SENT"])
        assertEquals("9 / 10  90%", rows["ACKED"])
        assertEquals("2000 ms", rows["ROUND TRIP"])
        assertEquals("9/10  90%", rows["DIRECT"])
        assertEquals("4/5  80%", rows["128-160 B"])
        assertEquals("5/5  100%", rows["32-64 B"])
        // Nothing was refused and nothing is in flight, so neither row is shown
        // — a row that says zero is a row that has to be read to be dismissed.
        assertTrue(rows.keys.none { it == "REFUSED" || it == "IN FLIGHT" })
    }

    /** Every row must fit the plate it is drawn on, in both locales. */
    @Test fun everyRowFitsTheNarrowerPlate() {
        val run = (1..30).map { a(it, bytes = 40 + it * 4, hops = it % 3 + 1, acked = it % 7 != 0) }
        // ROW_WIDEST_JA is 13 wide characters = 26 cells, the narrower of the
        // two plates. Name and value share it with two spaces between.
        TxLog.rows(run).forEach { (name, value) ->
            val cells = name.length + 2 + value.length
            assertTrue("'$name  $value' is $cells cells", cells <= 26)
        }
    }

    /** A refusal and an in-flight message each get their own row when real. */
    @Test fun refusedAndInFlightAppearWhenTheyExist() {
        val run = listOf(
            a(1),
            a(2, accepted = false, acked = false),
            TxLog.Attempt(3, 0, 64, "d563", 1, accepted = true, flood = false),
        )
        val rows = TxLog.rows(run).toMap()
        assertEquals("1", rows["REFUSED"])
        assertEquals("1", rows["IN FLIGHT"])
    }
}
