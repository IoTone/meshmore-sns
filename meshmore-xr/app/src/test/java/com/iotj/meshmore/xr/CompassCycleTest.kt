// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.Hud
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * ONE PIP, THREE STATES.
 *
 * The wrist dock has four slots and the compass is one of them, so the choice
 * between a bearing ribbon and a numeric heading has to live inside that pip
 * rather than beside it. Hud itself needs a Session and cannot be built on a
 * desktop JVM, so the transition table is restated here — if the two ever
 * disagree, this file is the one that is right and the one that says why.
 */
class CompassCycleTest {

    private fun next(m: Hud.Upper) = when (m) {
        Hud.Upper.OFF -> Hud.Upper.RIBBON
        Hud.Upper.RIBBON -> Hud.Upper.HEADING
        Hud.Upper.HEADING -> Hud.Upper.OFF
    }

    @Test fun threePinchesReturnToWhereItStarted() {
        var m = Hud.Upper.OFF
        m = next(m); assertEquals(Hud.Upper.RIBBON, m)
        m = next(m); assertEquals(Hud.Upper.HEADING, m)
        m = next(m); assertEquals(Hud.Upper.OFF, m)
    }

    /** Off is reachable from anywhere in at most three pinches. */
    @Test fun everyStateCanBeSwitchedOff() {
        Hud.Upper.entries.forEach { start ->
            var m = start
            var pinches = 0
            while (m != Hud.Upper.OFF && pinches < 4) { m = next(m); pinches++ }
            assertEquals("from $start", Hud.Upper.OFF, m)
            assertTrue("from $start took $pinches", pinches <= 3)
        }
    }

    /**
     * THE RIBBON COMES FIRST, and that ordering is the decision.
     *
     * A wearer reaching for the compass usually wants to know which way they
     * are pointing, which the strip answers at a glance; the number is for
     * reading a bearing off a node, which is the rarer job. One pinch should
     * land on the common one.
     */
    @Test fun theFirstPinchGivesTheRibbon() {
        assertEquals(Hud.Upper.RIBBON, next(Hud.Upper.OFF))
    }
}
