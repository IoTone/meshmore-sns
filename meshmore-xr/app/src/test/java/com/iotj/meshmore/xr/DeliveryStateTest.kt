// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * WHAT THE APP IS ALLOWED TO CLAIM ABOUT A MESSAGE.
 *
 * Two hours of soak established that roughly one direct message in ten is
 * never acknowledged, and that the app said "sent" for all of them. These are
 * the rules that replaced that claim, written as a pure state machine so the
 * part that decides what a wearer is told can be checked without a radio.
 */
class DeliveryStateTest {

    private fun msg(
        tag: Long? = null,
        state: MeshLink.Delivered? = null,
        me: Boolean = true,
    ) = MeshLink.Msg(
        fromKey = "abcd", fromName = if (me) "ME" else "THEM", text = "HELLO",
        atEpochSec = 1_700_000_000L, direct = true, delivery = state, ackTag = tag,
    )

    /** The three states, and the transitions the protocol actually provides. */
    @Test fun aSentMessageBecomesDeliveredOnlyOnItsOwnTag() {
        val a = msg(tag = 0x1111, state = MeshLink.Delivered.SENT)
        val b = msg(tag = 0x2222, state = MeshLink.Delivered.SENT)
        val acked = listOf(a, b).map {
            if (it.ackTag == 0x2222L) it.copy(delivery = MeshLink.Delivered.DELIVERED) else it
        }
        assertEquals(MeshLink.Delivered.SENT, acked[0].delivery)
        assertEquals(MeshLink.Delivered.DELIVERED, acked[1].delivery)
    }

    /**
     * SILENCE IS THE ONLY EVIDENCE OF LOSS, so it has to be timed. Everything
     * measured across two hours came back inside 2.4 seconds and the radio's
     * own estimate is 2.2 (direct) to 8 (flooded); a minute is a generous
     * multiple of the longest thing ever seen, not a judgement call.
     */
    @Test fun anUnansweredMessageIsLostOnlyAfterTheWindow() {
        val sentAt = 1_000_000L
        fun lostBy(now: Long) = now - sentAt > 60_000L
        assertTrue(!lostBy(sentAt + 2_400))
        assertTrue(!lostBy(sentAt + 59_000))
        assertTrue(lostBy(sentAt + 61_000))
    }

    /**
     * A RESEND IS A NEW MESSAGE. The mesh has no notion of the same message
     * twice, so the old line keeps its verdict — it really did go unanswered,
     * and rewriting that would be the app flattering itself.
     */
    @Test fun resendingDoesNotRewriteTheHistory() {
        val lost = msg(tag = 0x3333, state = MeshLink.Delivered.LOST)
        val again = lost.copy(ackTag = null, delivery = MeshLink.Delivered.SENT)
        assertEquals(MeshLink.Delivered.LOST, lost.delivery)
        assertEquals(MeshLink.Delivered.SENT, again.delivery)
        assertNull(again.ackTag)
    }

    /** Nothing is ever claimed about a message somebody else sent us. */
    @Test fun receivedMessagesCarryNoDeliveryState() {
        assertNull(msg(me = false).delivery)
    }

    /**
     * The store gained two fields and must still read records written before
     * they existed — a seven-field line is not corrupt, it is old, and it
     * decodes to a message whose delivery is simply unknown.
     */
    @Test fun olderRecordsStillLoad() {
        val store = object : MsgStore.Store {
            var v: String? = null
            override fun getString(key: String) = v
            override fun putString(key: String, value: String?) { v = value }
        }
        val us = ""
        store.v = listOf("abcd", "THEM", "HI", "1700000000", "1", "", "").joinToString(us)
        val out = MsgStore(store).load()
        assertEquals(1, out.size)
        assertEquals("HI", out[0].text)
        assertNull("an old record must not invent a delivery state", out[0].delivery)
    }

    /** And a round trip keeps what it was given. */
    @Test fun deliveryStateSurvivesTheRoundTrip() {
        val store = object : MsgStore.Store {
            var v: String? = null
            override fun getString(key: String) = v
            override fun putString(key: String, value: String?) { v = value }
        }
        val s = MsgStore(store)
        s.save(listOf(msg(tag = 0x4444, state = MeshLink.Delivered.LOST)))
        val back = s.load().single()
        assertEquals(MeshLink.Delivered.LOST, back.delivery)
        assertEquals(0x4444L, back.ackTag)
    }
}
