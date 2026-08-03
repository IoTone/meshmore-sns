// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The packing is the kind of arithmetic that is silently wrong: a mis-shifted
 * field does not fail, it grants a permission nobody meant to grant. So it is
 * argued here rather than on a radio.
 */
class TelemetryPermsTest {

    @Test fun `each class lands in its own two bits`() {
        assertEquals(0b000001, TelemetryPerms.Perms(base = 1).packed())
        assertEquals(0b000100, TelemetryPerms.Perms(location = 1).packed())
        assertEquals(0b010000, TelemetryPerms.Perms(environment = 1).packed())
        assertEquals(
            0b101010,
            TelemetryPerms.Perms(2, 2, 2).packed(),
        )
    }

    @Test fun `unpack is the inverse of pack`() {
        for (b in 0..2) for (l in 0..2) for (e in 0..2) {
            val p = TelemetryPerms.Perms(b, l, e)
            assertEquals(p, TelemetryPerms.unpack(p.packed()))
        }
    }

    /**
     * 3 is undefined in the firmware. It must clamp UP to the highest defined
     * level, never down: showing DENY over a radio that is in fact answering
     * everyone would be the display lying in the dangerous direction.
     */
    @Test fun `the undefined level three clamps to allow all`() {
        val p = TelemetryPerms.unpack(0b110000)
        assertEquals(TelemetryPerms.ALLOW_ALL, p.environment)
        assertEquals("ANYONE", TelemetryPerms.name(3))
    }

    @Test fun `high bits above the three fields are ignored`() {
        assertEquals(
            TelemetryPerms.Perms(1, 1, 1),
            TelemetryPerms.unpack(0b11_010101),
        )
    }

    @Test fun `with sets one class and leaves the others alone`() {
        val p = TelemetryPerms.Perms(0, 2, 1).with(0, TelemetryPerms.ALLOW_FLAGS)
        assertEquals(TelemetryPerms.Perms(1, 2, 1), p)
    }

    @Test fun `location is separable from battery`() {
        // The whole reason the classes are not one switch.
        val p = TelemetryPerms.Perms(base = TelemetryPerms.ALLOW_ALL)
        assertEquals(TelemetryPerms.DENY, p.location)
        assertEquals(0b000010, p.packed())
    }
}
