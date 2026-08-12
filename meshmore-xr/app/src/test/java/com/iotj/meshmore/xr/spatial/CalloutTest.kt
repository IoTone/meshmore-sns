// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The rules that stop a labelled map obscuring itself.
 *
 * Every one of these is a property a photograph can only report by being
 * wrong — "the labels overlap the map" and "two leaders cross" are things you
 * see on the glasses after a build-and-look cycle, and they are things
 * arithmetic can forbid outright.
 */
class CalloutTest {

    private val r = Callout.Rules()

    private fun ring(n: Int): List<Callout.Want> = (0 until n).map {
        val a = it * 2.0 * Math.PI / n
        Callout.Want(
            id = "n$it",
            x = (Math.cos(a) * 0.12).toFloat(),
            y = (Math.sin(a) * 0.12).toFloat(),
            text = "NODE$it",
        )
    }

    /**
     * R1 — THE RULE THE WHOLE DESIGN EXISTS FOR.
     *
     * A label hanging at its node is what makes the tabletop unreadable: at
     * 0.55 m an 8-character callsign is 68 mm on a 320 mm map, so five of them
     * cover it. No handle may sit over the disc, ever, at any count.
     */
    @Test fun noHandleEverLandsOnTheMap() {
        listOf(1, 2, 5, 12, 40).forEach { n ->
            Callout.place(ring(n), r).forEach { p ->
                assertTrue(
                    "${p.id} handle at %.3f is inside the %.3f map".format(
                        Math.abs(p.handleX), r.mapRadius,
                    ),
                    Math.abs(p.handleX) >= r.mapRadius,
                )
                // ...and with the gutter, so it does not graze the edge either.
                assertEquals(r.rackX, Math.abs(p.handleX), 1e-6f)
            }
        }
    }

    /**
     * R2 — LEADERS CANNOT CROSS, and not because a collision test says so.
     *
     * Two leaders on one side cross only if one pin is above another while its
     * handle is below. Assigning slots in pin order forbids exactly that, so
     * the property falls out of a sort rather than out of a search — no
     * jitter, no frame-to-frame reshuffling, nothing to tune.
     */
    @Test fun leadersNeverCross() {
        val placed = Callout.place(ring(24), r)
        listOf(true, false).forEach { side ->
            val s = placed.filter { it.left == side }.sortedBy { it.slot }
            for (i in 0 until s.size - 1) {
                val a = s[i]
                val b = s[i + 1]
                // Handles descend...
                assertTrue("handles out of order", a.handleY > b.handleY)
                // ...and so do the pins they belong to. Both orders agreeing is
                // the no-crossing guarantee.
                assertTrue("${a.id}/${b.id} pins invert their handles", a.pinY >= b.pinY)
            }
        }
    }

    /** R3 — a pin on the left is labelled on the left. */
    @Test fun everyHandleIsOnItsPinsOwnSide() {
        Callout.place(ring(20), r).forEach { p ->
            assertEquals("${p.id} crossed the map", p.pinX < 0f, p.left)
            assertEquals(p.left, p.handleX < 0f)
        }
    }

    /**
     * R4 — the budget is real, and honest about itself.
     *
     * The row pitch is not a taste parameter: it is the 1.3-degree text row
     * plus a gap. That fixes how many labels a map can carry, and past it the
     * extras are dropped and COUNTED rather than squeezed to an unreadable
     * spacing — a surface quietly showing 16 of 29 reads as one showing all 29.
     */
    @Test fun theBudgetIsBoundedAndReported() {
        assertEquals(2 * r.perSide, r.capacity)
        val many = ring(60)
        val placed = Callout.place(many, r)
        assertTrue("placed ${placed.size} > capacity ${r.capacity}", placed.size <= r.capacity)
        assertEquals(many.size - placed.size, Callout.dropped(many, r))
    }

    /** Nothing is placed twice, and nothing invented. */
    @Test fun everyHandleBelongsToOneRealPin() {
        val wants = ring(9)
        val placed = Callout.place(wants, r)
        assertEquals(placed.size, placed.map { it.id }.toSet().size)
        placed.forEach { p -> assertTrue(wants.any { it.id == p.id }) }
    }

    /**
     * THE 7-SHAPE: a vertical riser off the pin, then a horizontal run out.
     *
     * One fixed direction each. A fan of free angles between two clouds of
     * points reads as noise; a comb of right angles reads as a diagram.
     */
    @Test fun theLeaderIsAVerticalThenAHorizontal() {
        Callout.place(ring(6), r).forEach { p ->
            val (ex, ey) = Callout.elbow(p)
            assertEquals("riser must be vertical", p.pinX, ex, 1e-6f)
            assertEquals("run must be horizontal", p.handleY, ey, 1e-6f)
        }
    }

    /**
     * The default rules have to fit the tabletop they were written for: a
     * 0.25 m band at a 0.028 m pitch is 8 a side, 16 in total, against a
     * horizon that labels 24 of 350 peers. Close enough that clustering still
     * matters, far enough that a normal room does not hit it.
     */
    @Test fun theTabletopDefaultsCarryAUsefulNumberOfLabels() {
        assertTrue("only ${r.capacity} labels", r.capacity >= 14)
        assertTrue("${r.capacity} labels is more than the map can hold", r.capacity <= 20)
        // And the rack clears a 0.32 m model.
        assertTrue(r.rackX > 0.16f)
    }

    /** An empty map places nothing rather than dividing by zero. */
    @Test fun nothingToLabelIsNotAFailure() {
        assertTrue(Callout.place(emptyList(), r).isEmpty())
        assertEquals(0, Callout.dropped(emptyList(), r))
    }
}
