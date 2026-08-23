// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A DAY ON THE MESH, BUILT ON PURPOSE.
 *
 * The whole value of Meshbook being a pure function is here: a day's traffic
 * is assembled with the answers known in advance, rather than waiting for a
 * real day and hoping the numbers look plausible.
 */
class MeshbookTest {

    private val NOW = 1_800_000_000L
    private val H = 3600L

    private fun msg(
        who: String, agoH: Long, text: String = "hi",
        channel: String? = "#0",
        delivery: MeshLink.Delivered? = null,
    ) = MeshLink.Msg(
        fromKey = who.lowercase().take(12).padEnd(12, '0'),
        fromName = who,
        text = text,
        atEpochSec = NOW - (agoH * H),
        direct = channel == null,
        channel = channel,
        delivery = delivery,
    )

    /** Bucket by "hour" deterministically: hours since epoch, mod 24. */
    private val hourOf: (Long) -> Int = { ((it / H) % 24).toInt() }

    private fun book(m: List<MeshLink.Msg>) = Meshbook.of(m, NOW, hourOf)

    @Test fun anEmptyDayIsEmptyRatherThanBroken() {
        val b = book(emptyList())
        assertEquals(0, b.total)
        assertEquals(0, b.speakers)
        assertNull("no messages, so no delivery rate", b.deliveryPct)
        assertNull(b.replyPct)
        assertNull(b.busiestHour)
        assertEquals(24, b.hourly.size)
    }

    /** Anything older than the window is not this day. */
    @Test fun theWindowIsTwentyFourRollingHours() {
        val b = book(listOf(msg("Jeff", 1), msg("Jeff", 23), msg("Jeff", 25)))
        assertEquals(2, b.total)
    }

    /**
     * A PEER'S CLOCK CAN BE WRONG. 71 contacts on this mesh reported stamps
     * ahead of now; a message from the future would sit in the window forever
     * and land in whatever bucket its wrong hour points at.
     */
    @Test fun aMessageFromTheFutureIsNotCounted() {
        val ahead = msg("Skew", 0).copy(atEpochSec = NOW + 5 * H)
        assertEquals(0, book(listOf(ahead)).total)
    }

    @Test fun voicesAreRankedAndCapped() {
        val m = (1..4).map { msg("Zombie Tracker", it.toLong()) } +
            (1..7).map { msg("Chuck", it.toLong()) } +
            (1..9).map { msg("V$it", 2) }
        val b = book(m)
        assertEquals("Chuck", b.voices.first().name)
        assertEquals(7, b.voices.first().said)
        assertEquals(Meshbook.TOP_VOICES, b.voices.size)
        assertEquals("but every speaker is still counted", 11, b.speakers)
    }

    /** Our own messages are not a voice on the mesh. */
    @Test fun weAreNotOneOfTheVoices() {
        val b = book(listOf(msg(Meshbook.ME, 1), msg("Jeff", 1)))
        assertEquals(1, b.speakers)
        assertEquals("Jeff", b.voices.single().name)
        assertEquals(1, b.mine)
        assertEquals(1, b.theirs)
    }

    // --- the two figures SNS cannot compute ---------------------------------

    /** Delivery comes from the ledger, not from a typing convention. */
    @Test fun deliveryRateIsFromTheLedger() {
        val b = book(
            listOf(
                msg(Meshbook.ME, 1, delivery = MeshLink.Delivered.DELIVERED),
                msg(Meshbook.ME, 2, delivery = MeshLink.Delivered.DELIVERED),
                msg(Meshbook.ME, 3, delivery = MeshLink.Delivered.LOST),
                msg(Meshbook.ME, 4, delivery = MeshLink.Delivered.SENT),
            ),
        )
        assertEquals(4, b.mine)
        assertEquals(2, b.delivered)
        assertEquals(1, b.lost)
        assertEquals(50, b.deliveryPct)
    }

    /**
     * A REPLY IS SOMEBODY ANSWERING, not somebody typing a quote marker. Ours
     * at hour 5, theirs at hour 4 (later) in the same thread — answered.
     */
    @Test fun aReplyIsAnAnswerInTheSameThread() {
        val b = book(listOf(msg(Meshbook.ME, 5), msg("Jeff", 4)))
        assertEquals(1, b.answered)
        assertEquals(100, b.replyPct)
    }

    /** Silence is not a reply. */
    @Test fun nobodyAnsweringCountsAsNothing() {
        val b = book(listOf(msg(Meshbook.ME, 5), msg(Meshbook.ME, 4)))
        assertEquals(0, b.answered)
        assertEquals(0, b.replyPct)
    }

    /** An answer on a DIFFERENT thread is not an answer to this one. */
    @Test fun aThreadIsNotAnswereByAnotherThread() {
        val b = book(
            listOf(
                msg(Meshbook.ME, 5, channel = "#0"),
                msg("Jeff", 4, channel = "#1"),
            ),
        )
        assertEquals(0, b.answered)
    }

    /** Four people answering at once is one message answered, not four. */
    @Test fun oneMessageAnsweredIsCountedOnce() {
        val b = book(
            listOf(
                msg(Meshbook.ME, 6),
                msg("A", 5), msg("B", 4), msg("C", 3), msg("D", 2),
            ),
        )
        assertEquals(1, b.answered)
    }

    // --- the shape ------------------------------------------------------------

    @Test fun theHistogramHasTwentyFourBucketsAndFindsItsPeak() {
        val m = (1..6).map { msg("Jeff", 3) } + listOf(msg("Jeff", 9))
        val b = book(m)
        assertEquals(24, b.hourly.size)
        assertEquals(7, b.hourly.sum())
        assertEquals(6, b.peak)
        assertEquals(hourOf(NOW - 3 * H), b.busiestHour)
    }

    /** A quiet day still shows its own shape rather than one flat line. */
    @Test fun theSparklineScalesToItsOwnPeak() {
        val quiet = Meshbook.sparkline(List(24) { if (it == 3) 2 else 0 })
        assertEquals(24, quiet.length)
        assertTrue("the busy hour is drawn", quiet[3] != '·')
        assertTrue("the empty ones are dots", quiet[0] == '·')
        assertEquals("·".repeat(24), Meshbook.sparkline(List(24) { 0 }))
    }

    // --- what the operator's own mesh caught ---------------------------------

    /**
     * A CHANNEL SEND CANNOT BE ACKNOWLEDGED, so it must not sit in the
     * delivery denominator. On the real mesh this read "DELIVERED 1 OF 22 4%"
     * on a day whose direct soaks had measured 90% — twenty-one of those
     * twenty-two were channel messages that no ack was ever coming for.
     */
    @Test fun channelSendsAreNotCountedAgainstDelivery() {
        val b = book(
            listOf(
                msg(Meshbook.ME, 1, delivery = MeshLink.Delivered.DELIVERED),
                msg(Meshbook.ME, 2, delivery = MeshLink.Delivered.LOST),
                // Channel sends: remembered with no delivery state at all.
                msg(Meshbook.ME, 3), msg(Meshbook.ME, 4), msg(Meshbook.ME, 5),
            ),
        )
        assertEquals("all five were sent", 5, b.mine)
        assertEquals("only two could ever be acked", 2, b.trackable)
        assertEquals(50, b.deliveryPct)
    }

    /** With nothing trackable there is no rate to state, rather than 0%. */
    @Test fun aChannelOnlyDayHasNoDeliveryRate() {
        assertNull(book(listOf(msg(Meshbook.ME, 1), msg(Meshbook.ME, 2))).deliveryPct)
    }

    /**
     * CHANNEL TRAFFIC HAS NO KEY AND MAY HAVE NO NAME. On the real mesh this
     * drew as a blank row with 37 beside it, at the top of the voices.
     */
    @Test fun namelessSendersBecomeOneAnonymousVoice() {
        val nameless = (1..3).map {
            msg("Jeff", it.toLong()).copy(fromName = "", fromKey = "")
        }
        val b = book(nameless + listOf(msg("Jeff", 1)))
        val anon = b.voices.first { it.name == Meshbook.ANON }
        assertEquals(3, anon.said)
        assertEquals("one bucket, not three voices", 2, b.speakers)
        assertTrue("no blank names anywhere", b.voices.none { it.name.isBlank() })
    }
}
