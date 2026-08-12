// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §S2's step semantics, pinned.
 *
 * A spinner says "something is happening", so a radio that is switched off, one
 * out of range, a bond the OS refused and a stalled handshake all look
 * identical, and a tester can only report "it didn't connect". The step number
 * says which of the four it got through, which is most of the diagnosis.
 *
 * MeshLink.linkStep needs a Context to construct, so the mapping is mirrored
 * here — deliberately, so that changing one without the other fails rather than
 * silently drifting.
 */
class LinkStepTest {

    private enum class St { DISCONNECTED, CONNECTING, HANDSHAKING, READY }

    private fun step(
        state: St,
        scanning: Boolean = false,
        deviceName: String? = null,
        error: String? = null,
        dropped: Boolean = false,
    ): String? {
        if (state == St.READY) return null
        if (dropped) return "LINK LOST — RECONNECTING"
        val n = when {
            scanning -> 1
            state == St.DISCONNECTED -> if (deviceName == null) 1 else 2
            state == St.CONNECTING -> 2
            state == St.HANDSHAKING -> 3
            else -> 4
        }
        val what = when (n) {
            1 -> "LOOKING FOR A RADIO"
            2 -> "CONNECTING TO ${deviceName ?: "RADIO"}"
            3 -> "HANDSHAKING"
            else -> "READING RADIO"
        }
        error?.let { return "LINK FAILED — ${it.uppercase()}" }
        return "STEP $n/4  $what"
    }

    @Test fun everyStageGetsItsOwnNumber() {
        assertTrue(step(St.DISCONNECTED, scanning = true)!!.startsWith("STEP 1/4"))
        assertTrue(step(St.CONNECTING, deviceName = "MeshCore-1")!!.startsWith("STEP 2/4"))
        assertTrue(step(St.HANDSHAKING, deviceName = "MeshCore-1")!!.startsWith("STEP 3/4"))
    }

    /** The four steps must be distinguishable, which is the entire point. */
    @Test fun theStepsAreAllDifferent() {
        val seen = listOf(
            step(St.DISCONNECTED, scanning = true),
            step(St.CONNECTING, deviceName = "r"),
            step(St.HANDSHAKING, deviceName = "r"),
        )
        assertEquals(seen.size, seen.toSet().size)
    }

    /** A readout that lingers after arrival is one people stop reading. */
    @Test fun readyIsSilent() {
        assertNull(step(St.READY))
        assertNull(step(St.READY, deviceName = "MeshCore-1"))
    }

    /**
     * A known reason beats the step it stopped on. "no radio found" is the
     * answer; "STEP 1/4" is only where it was standing when it gave up.
     */
    @Test fun aKnownFailureReplacesTheStep() {
        val s = step(St.DISCONNECTED, scanning = false, error = "no radio found")
        assertEquals("LINK FAILED — NO RADIO FOUND", s)
        assertTrue(s!!, !s.contains("STEP"))
    }

    /** Named where we know the name, because "RADIO" is not an identification. */
    @Test fun theRadioIsNamedOnceItIsKnown() {
        assertTrue(step(St.CONNECTING, deviceName = "MeshCore-ab60")!!.contains("MeshCore-ab60"))
        assertTrue(step(St.CONNECTING)!!.contains("RADIO"))
    }

    /**
     * Disconnected with a name already known is step 2, not step 1: we are
     * between finding it and being connected, and telling somebody we are still
     * looking for a radio we have already found is a lie that makes them move.
     */
    @Test fun disconnectedAfterAFindIsStepTwo() {
        assertTrue(step(St.DISCONNECTED, deviceName = "MeshCore-1")!!.startsWith("STEP 2/4"))
        assertTrue(step(St.DISCONNECTED)!!.startsWith("STEP 1/4"))
    }

    /**
     * A DROP IS NOT A COLD START. Re-entering the ladder at "LOOKING FOR A
     * RADIO" reads as a fresh boot; after a drop the wearer's question is
     * whether the radio is gone and whether it is coming back.
     */
    @Test fun aDropSaysSoRatherThanRestartingTheLadder() {
        val s = step(St.DISCONNECTED, deviceName = "MeshCore-1", dropped = true)
        assertEquals("LINK LOST — RECONNECTING", s)
        assertTrue(s!!, !s.contains("STEP"))
    }

    /**
     * The drop line OUTRANKS the attempt's own error, and this is the test that
     * keeps the notice band quiet. Each reconnect attempt ends in "no radio
     * found"; if that replaced the drop line, the band would alternate between
     * two strings for the length of the outage and announce both, over and over,
     * every retry cycle.
     */
    @Test fun theDropLineDoesNotFlapAgainstEachFailedRetry() {
        val attempts = listOf(
            step(St.DISCONNECTED, deviceName = "r", dropped = true),
            step(St.DISCONNECTED, deviceName = "r", dropped = true, error = "no radio found"),
            step(St.DISCONNECTED, deviceName = "r", scanning = true, dropped = true),
        )
        assertEquals(1, attempts.toSet().size)
    }

    /** Recovery is silent in the same way arrival is: READY says nothing. */
    @Test fun recoveryEndsTheDropLine() {
        assertNull(step(St.READY, deviceName = "r", dropped = true))
    }
}
