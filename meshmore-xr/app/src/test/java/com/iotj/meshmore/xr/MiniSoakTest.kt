// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE PAYLOAD IS THE TEST, so it is the part with tests of its own.
 *
 * The point of this soak is to hand a radio the longest, most awkward thing it
 * will ever be asked to carry: a mixture of scripts where the byte count and
 * the character count disagree by a factor of three. A generator that quietly
 * overshoots the packet, or splits a kanji in half, would be testing the
 * generator rather than the radio.
 */
class MiniSoakTest {

    @Test fun everyMessageFitsTheByteBudget() {
        (1..MiniSoak.COUNT).forEach { n ->
            val m = MiniSoak.message("14:03:22", n)
            assertTrue(
                "message $n is ${MiniSoak.bytes(m)} bytes: '$m'",
                MiniSoak.bytes(m) <= MiniSoak.TARGET_BYTES,
            )
        }
    }

    /** Close to the budget, or it is not a full-length packet at all. */
    @Test fun everyMessageActuallyFillsIt() {
        val m = MiniSoak.message("14:03:22", 1)
        assertTrue("only ${MiniSoak.bytes(m)} bytes", MiniSoak.bytes(m) >= MiniSoak.TARGET_BYTES - 12)
    }

    /**
     * BYTES AND CHARACTERS MUST DISAGREE. If they ever match, the filler has
     * lost its multi-byte content and the soak has stopped testing the thing it
     * exists to test.
     */
    @Test fun theScriptsAreActuallyMixed() {
        val m = MiniSoak.message("14:03:22", 3)
        assertTrue("no kanji in '$m'", m.any { it.code in 0x4E00..0x9FFF })
        assertTrue("no emoji in '$m'", m.codePoints().anyMatch { it > 0xFFFF || it in 0x2600..0x27BF })
        assertTrue(
            "bytes and chars agree, so nothing multi-byte survived",
            MiniSoak.bytes(m) > m.length,
        )
    }

    /** The preamble stays readable even if the rest arrives as mojibake. */
    @Test fun thePreambleIsPlainAscii() {
        val m = MiniSoak.message("09:41:07", 7)
        val head = m.substringBefore(' ') + " " + m.split(' ')[1]
        assertEquals("09:41:07 #07", head)
        assertTrue(head.all { it.code < 128 })
    }

    /** No character is ever cut in half by the fill. */
    @Test fun nothingIsSplit() {
        val m = MiniSoak.message("00:00:00", 1)
        assertEquals(m, String(m.toByteArray(Charsets.UTF_8), Charsets.UTF_8))
    }

    /**
     * A RUN HAS TO VARY WHAT IT MEASURES.
     *
     * Twenty identical packets produced a by-size breakdown of exactly one
     * row, which is the aggregate wearing a label. Each length must land in a
     * different TxLog bucket or the comparison is not a comparison.
     */
    @Test
    fun aRunCoversThreeDifferentSizeBuckets() {
        val buckets = (1..MiniSoak.COUNT).map {
            TxLog.sizeBucket(MiniSoak.bytes(MiniSoak.message("14:03:22", it, MiniSoak.sizeFor(it))))
        }.toSet()
        org.junit.Assert.assertEquals(3, buckets.size)
    }

    /** And each length must actually be close to what it asked for. */
    @Test
    fun everyLengthFillsItsBudget() {
        MiniSoak.SIZES.forEach { want ->
            val n = MiniSoak.bytes(MiniSoak.message("14:03:22", 1, want))
            org.junit.Assert.assertTrue("$want asked, $n built", n <= want)
            org.junit.Assert.assertTrue("$want asked, only $n built", n >= want - 8)
        }
    }
}
