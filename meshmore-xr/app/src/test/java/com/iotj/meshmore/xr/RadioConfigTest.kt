// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The staged/commit/revert machine, and specifically the bit that has to
 * survive a process death — which is the whole reason the previous set lives on
 * disk rather than in a field.
 */
class RadioConfigTest {

    /** Stands in for SharedPreferences, and survives a "restart" by construction. */
    private class Disk : RadioConfig.Store {
        val map = HashMap<String, Any?>()
        override fun getString(key: String) = map[key] as? String
        override fun putString(key: String, value: String?) {
            if (value == null) map.remove(key) else map[key] = value
        }
        override fun getLong(key: String) = (map[key] as? Long) ?: 0L
        override fun putLong(key: String, value: Long) { map[key] = value }
    }

    private val A = RadioConfig.Params(910.525, 62.5, 7, 5, 22)
    private val B = RadioConfig.Params(869.525, 250.0, 11, 5, 14)

    @Test fun nothingIsStagedAtRest() {
        val c = RadioConfig(Disk()).also { it.observe(A) }
        assertFalse(c.dirty())
        assertEquals(A, c.pending)
    }

    @Test fun stagingDoesNotTouchLive() {
        val c = RadioConfig(Disk()).also { it.observe(A) }
        c.stage { it.copy(spreadingFactor = 10) }
        assertTrue(c.dirty())
        assertEquals(7, c.live!!.spreadingFactor)
        assertEquals(10, c.pending!!.spreadingFactor)
    }

    /** Self-info arrives constantly. It must not wipe an edit in progress. */
    @Test fun observeDoesNotDiscardAStagedEdit() {
        val c = RadioConfig(Disk()).also { it.observe(A) }
        c.stage { it.copy(spreadingFactor = 10) }
        c.observe(A)
        assertEquals(10, c.pending!!.spreadingFactor)
    }

    @Test fun commitMovesPendingToLiveAndKeepsThePreviousSet() {
        val c = RadioConfig(Disk()).also { it.observe(A) }
        c.stage { B }
        assertEquals(B, c.commit())
        assertFalse(c.dirty())
        assertEquals(A, c.previous)
    }

    /**
     * THE POINT OF THE WHOLE DESIGN. Commit a bad set, lose the mesh, close the
     * app, and come back tomorrow: the radio now reports its new wrong
     * parameters as its truth and has no memory of anything else. The only
     * record of what it used to be is the one we wrote to disk.
     */
    @Test fun thePreviousSetSurvivesAProcessDeath() {
        val disk = Disk()
        RadioConfig(disk).apply { observe(A); stage { B }; commit() }

        // New process. The radio reports the set it is now running.
        val next = RadioConfig(disk).apply { observe(B) }
        assertEquals("REVERT must be offered after a restart", A, next.previous)
        assertEquals(A, next.takePrevious())
        assertEquals(A, next.live)
        assertEquals(A, next.pending)
    }

    /** A revert restores ONE step. Keeping it would offer a way back to the fault. */
    @Test fun revertIsSingleUse() {
        val disk = Disk()
        val c = RadioConfig(disk).apply { observe(A); stage { B }; commit() }
        assertNotNull(c.takePrevious())
        assertNull(c.previous)
        assertNull(RadioConfig(disk).takePrevious())
    }

    @Test fun revertWithNoPreviousSetIsANoOp() {
        assertNull(RadioConfig(Disk()).apply { observe(A) }.takePrevious())
    }

    @Test fun discardDropsTheEditAndLeavesTheRadioAlone() {
        val c = RadioConfig(Disk()).also { it.observe(A) }
        c.stage { B }
        c.discard()
        assertFalse(c.dirty())
        assertEquals(A, c.pending)
        assertNull("a discarded edit is not a commit", c.previous)
    }

    @Test fun paramsRoundTripThroughStorage() {
        assertEquals(B, RadioConfig.Params.decode(B.encode()))
        assertNull(RadioConfig.Params.decode(null))
        assertNull(RadioConfig.Params.decode("910.525|62.5|7"))
        assertNull(RadioConfig.Params.decode("nonsense"))
    }

    /** Before self-info there is nothing to base an edit on, and no crash either. */
    @Test fun stagingBeforeSelfInfoIsSafe() {
        assertNull(RadioConfig(Disk()).stage { it })
    }
}
