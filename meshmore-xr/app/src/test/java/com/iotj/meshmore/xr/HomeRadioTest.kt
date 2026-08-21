// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * WHICH RADIO IS OURS, WHEN SEVERAL OF THEM ARE.
 *
 * The rule under test is the scan's comparator, restated here so it can be
 * exercised without Bluetooth. It exists because "bonded, then loudest" chose
 * by where somebody was standing the moment the glasses had two bonded radios
 * — which happened on 2026-08-21, when reading D38F07AED563's inbox required
 * bonding to it.
 *
 * If this and MeshLink ever disagree, this file is the one that is right, and
 * the one that says why.
 */
class HomeRadioTest {

    private data class Seen(val name: String, val bonded: Boolean, val rssi: Int)

    /** The comparator, exactly as MeshLink applies it. */
    private fun pick(seen: List<Seen>, home: String?): String? = seen.maxWithOrNull(
        compareBy(
            { if (home != null && it.name == home) 1 else 0 },
            { if (it.bonded) 1 else 0 },
            { it.rssi },
        ),
    )?.name

    private val room = listOf(
        Seen("MeshCore-B727FE05", bonded = true, rssi = -83),
        Seen("MeshCore-D38F07AED563", bonded = true, rssi = -58),
        Seen("MeshCore-C8DDE2F9AB60", bonded = false, rssi = -40),
    )

    /** THE BUG. Two bonded radios, and the nearer one is not the companion. */
    @Test fun theHomeRadioWinsEvenWhenItIsTheFaintest() {
        assertEquals("MeshCore-B727FE05", pick(room, "MeshCore-B727FE05"))
    }

    /** A stranger blasting at close range still never wins. */
    @Test fun aLoudStrangerNeverBeatsABondedRadio() {
        assertEquals("MeshCore-D38F07AED563", pick(room, null))
    }

    /** Before the first session there is no memory, and the old rule stands. */
    @Test fun withNoMemoryTheOldRuleApplies() {
        assertEquals("MeshCore-D38F07AED563", pick(room, null))
    }

    /** A remembered radio that is not in the room does not block the others. */
    @Test fun anAbsentHomeRadioFallsBackRatherThanFailing() {
        assertEquals("MeshCore-D38F07AED563", pick(room, "MeshCore-NOTHERE"))
    }

    /** One radio, remembered or not, is still the answer. */
    @Test fun oneRadioIsAlwaysTheAnswer() {
        val one = listOf(Seen("MeshCore-B727FE05", bonded = true, rssi = -90))
        assertEquals("MeshCore-B727FE05", pick(one, null))
        assertEquals("MeshCore-B727FE05", pick(one, "MeshCore-B727FE05"))
    }

    @Test fun anEmptyRoomPicksNothing() {
        assertEquals(null, pick(emptyList(), "MeshCore-B727FE05"))
    }
}
