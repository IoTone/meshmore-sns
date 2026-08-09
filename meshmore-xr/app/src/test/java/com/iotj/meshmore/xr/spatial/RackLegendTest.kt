// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE RACK'S LEGENDS FIT THEIR COLUMNS, and are above the §4.1 floor.
 *
 * Both halves are needed and neither is visible on a headset. Type under the
 * floor reads as a slightly blurry panel rather than as a violation, and two
 * legends running into each other reads as bad kerning — so the rack shipped
 * for weeks with "BCAST POS" printing through its neighbour and nothing
 * anywhere saying so.
 *
 * The arithmetic is not hard, it is just never done: a stroke font's advance is
 * a constant, so a legend's width is exactly known, and the column pitch is a
 * constant too. This is that division, run on every legend the rack draws.
 */
class RackLegendTest {

    // Rack geometry, mirrored from its companion. Duplicated deliberately: if
    // somebody changes the rack and not this file, the test should FAIL rather
    // than quietly follow them under the floor.
    private val reach = 0.62f
    private val rackW = 0.44f
    private val inset = 0.036f
    private val cap = 0.0141f

    // Glyphs' stroke metrics.
    private val gw = 4f
    private val gh = 6f
    private val adv = 5.6f

    private fun width(text: String): Float {
        val n = text.length
        return if (n == 0) 0f else (n * adv - (adv - gw)) * (cap / gh)
    }

    private fun col(f: Float) = -rackW / 2f + inset + f * (rackW - inset * 2f)

    private fun degOf(capM: Float) =
        Math.toDegrees(2.0 * Math.atan((capM / (2f * reach)).toDouble()))

    /** §4.1: the floor is 1.20°, the house standard 1.30°. */
    @Test fun legendsAreAtTheHouseStandard() {
        val d = degOf(cap)
        assertTrue("rack legends are %.2f deg, floor is 1.20".format(d), d >= 1.20)
        assertTrue("rack legends are %.2f deg, house standard is 1.30".format(d), d >= 1.29)
    }

    /**
     * Neighbouring legends do not touch.
     *
     * Both are centred on their control, so the clearance between two is the
     * gap minus half of each width. A 4 mm margin is the tolerance: less than
     * that and two stroke glyphs read as one word at reach.
     */
    private fun noOverlap(rows: List<Pair<Float, String>>, what: String) {
        val sorted = rows.sortedBy { it.first }
        for (i in 0 until sorted.size - 1) {
            val (fa, a) = sorted[i]
            val (fb, b) = sorted[i + 1]
            val gap = col(fb) - col(fa)
            val need = width(a) / 2f + width(b) / 2f + 0.004f
            assertTrue(
                "$what: '$a' and '$b' need %.1f cm but have %.1f cm"
                    .format(need * 100, gap * 100),
                gap >= need,
            )
        }
    }

    @Test fun theKnobRowFits() = noOverlap(
        listOf(
            0.08f to "PRESET", 0.29f to "FREQ", 0.47f to "BW",
            0.65f to "SF", 0.82f to "CR",
        ),
        "knob row",
    )

    /** The row that was actually broken. "BCAST POS" overlapped even at 0.92°. */
    @Test fun theStatusRowFits() = noOverlap(
        listOf(0.05f to "FIX", 0.72f to "GPS", 0.92f to "BCAST"),
        "status row",
    )

    @Test fun theLampRowFits() = noOverlap(
        listOf(0.04f to "LIVE", 0.44f to "PEND", 0.60f to "ARM"),
        "lamp row",
    )

    @Test fun theActionRowFits() = noOverlap(
        listOf(0.75f to "COMMIT", 0.93f to "UNDO"),
        "action row",
    )

    /** Nothing may hang off the edge of the face either. */
    @Test fun nothingOverhangsTheRackFace() {
        listOf(
            0.08f to "PRESET", 0.82f to "CR", 0.05f to "FIX", 0.92f to "BCAST",
            0.04f to "LIVE", 0.93f to "UNDO", 0.75f to "COMMIT",
        ).forEach { (f, t) ->
            val half = width(t) / 2f
            assertTrue("'$t' runs off the left", col(f) - half >= -rackW / 2f - 0.001f)
            assertTrue("'$t' runs off the right", col(f) + half <= rackW / 2f + 0.001f)
        }
    }

    /**
     * The old constant, kept as a regression: it was under the floor AND it
     * overlapped, so any change that lands back near it is wrong twice.
     */
    @Test fun theOldCapWasGenuinelyTooSmall() {
        assertTrue(degOf(0.010f) < 1.20)
    }
}
