// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The reach trail, asserted at a bench.
 *
 * S0 is the surface a first-time wearer meets before anything else, and it is
 * the one surface that cannot be checked by opening it twice: it shows once per
 * install, to somebody who has never seen this app. So the geometry is proved
 * here rather than by wearing it and forming an impression.
 */
class BeckonTest {

    private val HAND = Triple(-0.30f, 1.20f, -0.20f)
    private val MOTE = Triple(0.00f, 1.42f, -0.45f)

    private fun trailAt(phase: Float, strength: Float = 1f) = Beckon.trail(
        HAND.first, HAND.second, HAND.third,
        MOTE.first, MOTE.second, MOTE.third,
        phase, strength,
    )

    @Test
    fun `the path runs from the hand to the mote, in that order`() {
        val t = trailAt(0f)
        assertEquals(Beckon.BEADS, t.size)
        // The ends are exact: the bow is a half-sine and is zero at both.
        assertEquals(HAND.first, t.first().x, 1e-5f)
        assertEquals(HAND.second, t.first().y, 1e-5f)
        assertEquals(HAND.third, t.first().z, 1e-5f)
        assertEquals(MOTE.first, t.last().x, 1e-5f)
        assertEquals(MOTE.second, t.last().y, 1e-5f)
        assertEquals(MOTE.third, t.last().z, 1e-5f)
    }

    @Test
    fun `the trail bows upward so it does not run through the label`() {
        val t = trailAt(0f)
        val mid = t[Beckon.BEADS / 2]
        val straightY = HAND.second + (MOTE.second - HAND.second) * (Beckon.BEADS / 2) /
            (Beckon.BEADS - 1).toFloat()
        assertTrue("middle bead should sit above the straight line", mid.y > straightY)
        assertTrue("and not by more than the bow", mid.y - straightY <= Beckon.BOW + 1e-4f)
    }

    @Test
    fun `it is brighter at the mote than at the hand`() {
        // Highlight parked in the MIDDLE, where it contributes nothing at
        // either end, so the ramp is what is being measured.
        val t = trailAt(0.5f)
        assertTrue(t.last().alpha > t.first().alpha)
    }

    /**
     * THE ONE THAT CARRIES THE MEANING. The highlight has to move toward the
     * mote; a trail that swept the other way would be telling a first-time
     * wearer to pull their hand back.
     */
    @Test
    fun `the highlight travels toward the mote`() {
        // EACH BEAD AGAINST ITSELF, not against its neighbours. The ramp is a
        // static gradient that is always brightest at the mote end, so "which
        // bead is brightest right now" answers a question about the ramp and
        // says nothing about the moving part. What has to be true is that every
        // bead peaks when the highlight reaches IT.
        fun alphaOf(bead: Int, phase: Float) = trailAt(phase)[bead].alpha
        val last = Beckon.BEADS - 1
        val mid = last / 2

        assertTrue("bead at the hand peaks early", alphaOf(0, 0f) > alphaOf(0, 0.5f))
        assertTrue("and is dimmest when the sweep is at the far end",
            alphaOf(0, 0.5f) > alphaOf(0, 1f))

        assertTrue("the middle bead peaks in the middle", alphaOf(mid, 0.5f) > alphaOf(mid, 0f))
        assertTrue(alphaOf(mid, 0.5f) > alphaOf(mid, 1f))

        assertTrue("the bead at the mote peaks last", alphaOf(last, 1f) > alphaOf(last, 0.5f))
        assertTrue(alphaOf(last, 0.5f) > alphaOf(last, 0f))
    }

    /**
     * The sweep must reach the mote itself. An earlier draft let ramp + pulse
     * exceed opaque, and two clamped beads are indistinguishable — so the
     * highlight appeared to stop one bead short of the target it is pointing at.
     */
    @Test
    fun `the highlight actually arrives at the last bead`() {
        val last = Beckon.BEADS - 1
        val t = trailAt(1f)
        assertTrue("nothing may tie with the arriving bead",
            t.indices.filter { it != last }.all { t[it].alpha < t[last].alpha })
        assertEquals(1f, Beckon.HEAD_ALPHA + Beckon.PULSE, 1e-6f)
    }

    @Test
    fun `phase sweeps zero to one across a cycle and wraps`() {
        assertEquals(0f, Beckon.phase(0L), 1e-6f)
        assertEquals(0.5f, Beckon.phase(Beckon.CYCLE_MS / 2), 1e-3f)
        // It must not bounce back: two cycles later the same instant repeats.
        assertEquals(
            Beckon.phase(123L),
            Beckon.phase(123L + Beckon.CYCLE_MS * 2),
            1e-6f,
        )
    }

    @Test
    fun `a hand already at the mote draws nothing`() {
        assertEquals(0f, Beckon.strength(0f), 1e-6f)
        assertEquals(0f, Beckon.strength(Beckon.ARRIVED_M), 1e-6f)
        assertTrue(trailAt(0.5f, Beckon.strength(0.05f)).isEmpty())
    }

    @Test
    fun `strength ramps rather than switching`() {
        val mid = (Beckon.ARRIVED_M + Beckon.FADE_M) / 2f
        val s = Beckon.strength(mid)
        assertTrue("a partial value, not a switch", s > 0.2f && s < 0.8f)
        assertEquals(1f, Beckon.strength(Beckon.FADE_M), 1e-6f)
        assertEquals(1f, Beckon.strength(2f), 1e-6f)
        // Monotonic, so it can never brighten as the hand closes.
        var prev = 0f
        var d = Beckon.ARRIVED_M
        while (d <= Beckon.FADE_M) {
            val v = Beckon.strength(d)
            assertTrue("strength must not decrease with distance", v >= prev - 1e-6f)
            prev = v
            d += 0.005f
        }
    }

    @Test
    fun `strength scales every bead, so the trail fades out rather than blinking`() {
        val full = trailAt(0.5f, 1f)
        val half = trailAt(0.5f, 0.5f)
        full.indices.forEach { i ->
            assertEquals(full[i].alpha * 0.5f, half[i].alpha, 1e-5f)
        }
    }

    @Test
    fun `no bead is ever drawn brighter than opaque`() {
        var phase = 0f
        while (phase <= 1f) {
            trailAt(phase).forEach {
                assertTrue("alpha in range, was ${it.alpha}", it.alpha in 0f..1f)
            }
            phase += 0.02f
        }
    }

    /**
     * The ghost origin is where a wearer with their hands in their lap is told
     * to reach FROM. It has to be below the mote and on the wearer's left, or
     * the instruction points at the wrong arm.
     */
    @Test
    fun `the ghost origin sits down and to the wearer's left`() {
        // Facing -Z: the wearer's left is -X.
        val (gx, gy, gz) = Beckon.ghost(
            MOTE.first, MOTE.second, MOTE.third,
            leftX = -1f, leftZ = 0f,
        )
        assertTrue("left of the mote", gx < MOTE.first)
        assertTrue("below the mote", gy < MOTE.second)
        assertEquals(MOTE.third, gz, 1e-5f)
        assertEquals(Beckon.GHOST_LEFT, MOTE.first - gx, 1e-5f)
        assertEquals(Beckon.GHOST_DROP, MOTE.second - gy, 1e-5f)
    }

    @Test
    fun `the ghost origin is far enough away to draw at full strength`() {
        val (gx, gy, gz) = Beckon.ghost(
            MOTE.first, MOTE.second, MOTE.third,
            leftX = -1f, leftZ = 0f,
        )
        val d = Beckon.distance(gx, gy, gz, MOTE.first, MOTE.second, MOTE.third)
        assertTrue(
            "a ghost trail that started already faded would say nothing",
            Beckon.strength(d) == 1f,
        )
    }

    @Test
    fun `distance is symmetric and euclidean`() {
        assertEquals(5f, Beckon.distance(0f, 0f, 0f, 3f, 4f, 0f), 1e-5f)
        assertEquals(
            Beckon.distance(1f, 2f, 3f, -4f, 0.5f, 2f),
            Beckon.distance(-4f, 0.5f, 2f, 1f, 2f, 3f),
            1e-6f,
        )
    }
}
