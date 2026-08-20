// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.Crown
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE MENU HAS SIX PLACES AND SEVEN THINGS TO PUT IN THEM.
 *
 * Overflow was silent: the placement loop takes `items.getOrNull(i)`, so a
 * seventh row drew nothing at all — and the row that fell off the end was
 * CLOSE. This pins the two properties that make the screen usable no matter
 * which optional rows are offered.
 */
class CrownRowsTest {

    private fun rows(soak: Boolean, resend: Boolean) = Crown.actionOrder(soak, resend)

    @Test fun neverMoreRowsThanSlots() {
        listOf(false, true).forEach { s ->
            listOf(false, true).forEach { r ->
                val n = rows(s, r).size
                assertTrue("soak=$s resend=$r wants $n of ${Crown.SLOTS}", n <= Crown.SLOTS)
            }
        }
    }

    /** A menu you cannot leave is worse than no menu. */
    @Test fun closeIsAlwaysThere() {
        listOf(false, true).forEach { s ->
            listOf(false, true).forEach { r ->
                assertTrue("soak=$s resend=$r", Crown.Act.DISMISS in rows(s, r))
            }
        }
    }

    @Test fun replyLeadsAndTheOptionalRowsFollowIt() {
        assertEquals(Crown.Act.REPLY, rows(true, true).first())
        assertEquals(
            listOf(Crown.Act.SOAK, Crown.Act.RESEND),
            rows(true, true).drop(1).take(2),
        )
    }

    /** Offered rows are never the ones dropped — THREAD gives way instead. */
    @Test fun theThreadIsWhatGivesWay() {
        val full = rows(true, true)
        assertTrue(Crown.Act.SOAK in full && Crown.Act.RESEND in full)
        assertTrue(Crown.Act.THREAD !in full)
        assertTrue(Crown.Act.THREAD in rows(false, false))
        assertTrue(Crown.Act.THREAD in rows(true, false))
    }
}
