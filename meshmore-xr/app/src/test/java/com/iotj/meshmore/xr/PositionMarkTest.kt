// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE STANDING ANSWER TO "IS THIS THING USING MY GPS, AND IS IT TELLING
 * ANYBODY".
 *
 * Two settings, and only one of them is the doxxing one. Working out which way
 * a node lies from a local fix is arithmetic that never leaves the headset;
 * putting coordinates into an advert is an unencrypted broadcast to everyone in
 * radio range. Both were invisible, so the safe one felt as risky as the
 * dangerous one — and with it off the horizon cannot draw anything at all.
 */
class PositionMarkTest {

    /** Off is silent. Chrome that says "no" continuously is chrome nobody reads. */
    @Test fun noPositionShowsNothing() {
        assertEquals("", positionMark("none", sharing = false))
    }

    /**
     * ARMED IS NOT IN USE. With the radio's own fix good, the headset setting
     * can be on and doing nothing — a band claiming GPS then would be saying
     * the wearer's own receiver is running when it is not.
     */
    @Test fun theMarkFollowsTheSourceInUse() {
        assertTrue(positionMark("headset", false).contains("GPS"))
        assertTrue(positionMark("radio", false).contains("RADIO"))
        assertTrue(positionMark("stated", false).contains("SET"))
        // The radio's own fix is not the headset's GPS and must not read as it.
        assertTrue(!positionMark("radio", false).contains("GPS"))
    }

    /**
     * SHARING IS A FACT ABOUT THE AIR, not about where the number came from, so
     * it shows on every source.
     */
    @Test fun sharingIsMarkedWhateverTheSource() {
        listOf("headset", "radio", "stated").forEach {
            assertTrue("$it lost its SHARED mark", positionMark(it, true).contains("SHARED"))
        }
    }

    /**
     * ...but there is nothing to share when there is no position, and a band
     * that says SHARED beside NO FIX describes a broadcast that is not
     * happening. This is the one combination that would frighten a wearer over
     * nothing.
     */
    @Test fun nothingIsSharedWhenThereIsNoPosition() {
        assertEquals("", positionMark("none", sharing = true))
    }

    /**
     * The mark rides on the end of a band that already carries the link, the
     * battery and the counts. Its worst case has to leave that legible: about
     * 50 characters fit inside the safe area at the band's cap height, and the
     * rest of the line can reach 32.
     */
    @Test fun theMarkLeavesRoomForTheRestOfTheBand() {
        val worst = listOf("headset", "radio", "stated")
            .maxOf { positionMark(it, true).length }
        assertTrue("worst mark is $worst chars", worst <= 18)
    }

    /** Leading space, always: it is appended to a line, never the line itself. */
    @Test fun theMarkAppendsRatherThanReplaces() {
        listOf("headset", "radio", "stated").forEach {
            assertTrue(positionMark(it, false).startsWith("  "))
        }
    }
}
