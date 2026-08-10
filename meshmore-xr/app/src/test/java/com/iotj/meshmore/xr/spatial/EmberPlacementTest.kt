// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * WHICH SIDE THE EMBER LANDS ON, which is the whole message.
 *
 * An ember carries one bit of information — turn left, or turn right — and it
 * carries it for three seconds at the edge of vision. Getting the sign wrong
 * does not look like a bug, it looks like a mesh where people are somewhere
 * else, and nobody can catch it by eye because the ember is gone before you can
 * compare it to the horizon.
 *
 * Mirrors Ember.tick's arithmetic, which needs a Session to reach.
 */
class EmberPlacementTest {

    private val twoPi = (Math.PI * 2).toFloat()

    /** Returns +1 for the wearer's right, -1 for their left. */
    private fun side(bearingDeg: Float, facingDeg: Float): Float {
        var rel = Math.toRadians(bearingDeg.toDouble()).toFloat() -
            Math.toRadians(facingDeg.toDouble()).toFloat()
        while (rel > Math.PI) rel -= twoPi
        while (rel < -Math.PI) rel += twoPi
        return if (rel >= 0f) 1f else -1f
    }

    /** How far behind, 0 in front and 1 directly astern. */
    private fun behind(bearingDeg: Float, facingDeg: Float): Float {
        var rel = Math.toRadians(bearingDeg.toDouble()).toFloat() -
            Math.toRadians(facingDeg.toDouble()).toFloat()
        while (rel > Math.PI) rel -= twoPi
        while (rel < -Math.PI) rel += twoPi
        return (Math.abs(rel) / Math.PI.toFloat()).coerceIn(0f, 1f)
    }

    @Test fun somethingToYourRightPutsTheEmberOnTheRight() {
        assertEquals(1f, side(90f, 0f), 0f)
        assertEquals(1f, side(45f, 0f), 0f)
    }

    @Test fun somethingToYourLeftPutsTheEmberOnTheLeft() {
        assertEquals(-1f, side(270f, 0f), 0f)
        assertEquals(-1f, side(315f, 0f), 0f)
    }

    /**
     * THE WRAP CASE, which is where a sign error actually lives. Facing
     * north-west, a sender due north is to your RIGHT — and the naive
     * subtraction gives a large positive angle that looks like "behind left".
     */
    @Test fun itSurvivesTheSeamAtNorth() {
        assertEquals(1f, side(0f, 315f), 0f)
        assertEquals(-1f, side(315f, 0f), 0f)
        assertEquals(1f, side(10f, 350f), 0f)
        assertEquals(-1f, side(350f, 10f), 0f)
    }

    @Test fun aSenderInFrontIsNotTreatedAsBehind() {
        assertTrue(behind(0f, 0f) < 0.05f)
        assertTrue(behind(20f, 0f) < 0.2f)
    }

    @Test fun aSenderAsternIsFullyBehindWhicheverWayItWraps() {
        assertEquals(1f, behind(180f, 0f), 0.01f)
        assertEquals(1f, behind(0f, 180f), 0.01f)
    }

    /** Behind is symmetric: the drop must not depend on which way you turned. */
    @Test fun theDropIsTheSameOnBothSides() {
        assertEquals(behind(120f, 0f), behind(240f, 0f), 0.001f)
        assertEquals(behind(100f, 0f), behind(260f, 0f), 0.001f)
    }

    /** Every bearing lands somewhere, including the awkward exact ones. */
    @Test fun everyBearingResolves() {
        var d = 0f
        while (d < 360f) {
            val s = side(d, 37f)
            assertTrue("bearing $d", s == 1f || s == -1f)
            assertTrue("bearing $d", behind(d, 37f) in 0f..1f)
            d += 7.5f
        }
    }
}
