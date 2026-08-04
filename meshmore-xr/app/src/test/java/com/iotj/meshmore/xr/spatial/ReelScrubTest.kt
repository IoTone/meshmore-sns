// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import androidx.xr.runtime.math.Vector3
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THUMB ALONG INDEX — the geometry, without a hand in it.
 *
 * §5 makes this the reel's turning gesture and the app's only real haptic. It
 * is also the joint this project has found least reliable, so the arithmetic
 * gets pinned here rather than on someone's face: every on-glasses attempt at
 * a gesture threshold costs minutes, and a sign error looks exactly like a
 * tracking failure from inside the headset.
 *
 * The index runs along +X from the origin, 0.08 m long — near enough a real
 * one — and the thumb is placed against it at various points.
 */
class ReelScrubTest {

    private val prox = Vector3(0f, 0f, 0f)
    private val tip = Vector3(0.08f, 0f, 0f)

    @Test
    fun `t runs zero at the knuckle and one at the tip`() {
        assertEquals(0f, scrub(prox, tip, Vector3(0f, 0.01f, 0f)).t, 1e-4f)
        assertEquals(1f, scrub(prox, tip, Vector3(0.08f, 0.01f, 0f)).t, 1e-4f)
        assertEquals(0.5f, scrub(prox, tip, Vector3(0.04f, 0.01f, 0f)).t, 1e-4f)
    }

    @Test
    fun `a thumb resting on the finger is in contact`() {
        // 22 mm off the axis of a 75 mm finger is where a real thumb sits.
        assertTrue(scrub(Vector3(0f, 0f, 0f), Vector3(0.075f, 0f, 0f),
            Vector3(0.037f, 0.022f, 0f)).on)
    }

    @Test
    fun `a thumb held away from the finger is not`() {
        // Half the finger's length away sideways: an open hand, not a scrub.
        assertFalse(scrub(prox, tip, Vector3(0.04f, 0.04f, 0f)).on)
    }

    @Test
    fun `a thumb out past the fingertip is not riding the finger`() {
        // t clamps to 1, and the distance is then measured from the TIP — which
        // is the whole reason the clamp happens before the perpendicular and
        // not after. Measured from the infinite axis this would read as
        // contact, and the reel would turn while the hand was open.
        assertFalse(scrub(prox, tip, Vector3(0.16f, 0f, 0f)).on)
    }

    @Test
    fun `contact scales with the hand, not with millimetres`() {
        // The same pose on a hand half the size must give the same answer.
        val small = Vector3(0.04f, 0f, 0f)
        val big = scrub(prox, tip, Vector3(0.04f, 0.012f, 0f))
        val little = scrub(prox, small, Vector3(0.02f, 0.006f, 0f))
        assertEquals(big.on, little.on)
        assertEquals(big.t, little.t, 1e-4f)
    }

    @Test
    fun `a degenerate finger does not turn the reel`() {
        val s = scrub(prox, prox, Vector3(0.01f, 0f, 0f))
        assertFalse(s.on)
    }
}

/**
 * THE CURLED FINGER — the pose the gesture is actually made in.
 *
 * Nobody slides a thumb along a rigid index. The first version measured the
 * thumb's distance from the straight chord between knuckle and fingertip,
 * which describes the finger only while it is straight; curl it and the middle
 * of the finger stands well off its own chord, so a thumb resting ON the finger
 * measures as far away FROM it and the gesture stops registering.
 *
 * The failure is silent and looks exactly like bad hand tracking, which is why
 * it survived two rounds of "doesn't seem to work". These are the numbers that
 * decide it, and they now live here rather than on someone's face.
 */
class ReelCurledScrubTest {

    /** A ~75 mm index curled about 40 degrees, four joints, in the XY plane. */
    private val curled = listOf(
        Vector3(0f, 0f, 0f),
        Vector3(0.030f, 0.008f, 0f),
        Vector3(0.052f, 0.024f, 0f),
        Vector3(0.066f, 0.046f, 0f),
    )

    @Test
    fun `a thumb on a curled finger registers`() {
        // Resting on the middle joint, 20 mm off the finger's surface normal.
        val thumb = Vector3(0.052f + 0.014f, 0.024f - 0.014f, 0f)
        assertTrue("bones", scrub(curled, thumb).on)
    }

    @Test
    fun `the bones measure a curled finger as closer than its chord does`() {
        // HOW MUCH this matters, stated honestly rather than assumed. Writing
        // this test as "the chord fails and the bones pass" FAILED: at the
        // current 0.45 tolerance the chord still registers a 40-degree curl,
        // so the polyline is a margin improvement here, not the whole fix for
        // the gesture not firing. What it does buy is real and measurable --
        // the thumb reads as materially nearer the finger it is touching --
        // and the margin is what tracking jitter eats into.
        //
        // Written this way so the next person does not inherit a claim the
        // arithmetic never supported.
        val thumb = Vector3(0.052f + 0.014f, 0.024f - 0.014f, 0f)
        assertTrue(scrub(curled, thumb).on)
        assertTrue(dist(curled, thumb) < dist(listOf(curled.first(), curled.last()), thumb))
    }

    /** Perpendicular distance implied by a Scrub, recovered from the threshold. */
    private fun dist(bones: List<Vector3>, thumb: Vector3): Float {
        var lo = 0f
        var hi = 1f
        // The contact test is `d < frac * total`, so bisecting on the fraction
        // recovers d/total -- enough to compare two measurements of the same
        // pose without exposing the internals.
        repeat(40) {
            val mid = (lo + hi) / 2f
            if (scrubAt(bones, thumb, mid)) hi = mid else lo = mid
        }
        return (lo + hi) / 2f
    }

    private fun scrubAt(bones: List<Vector3>, thumb: Vector3, frac: Float): Boolean {
        // Same arithmetic, with the tolerance as a parameter.
        var total = 0f
        for (k in 0 until bones.size - 1) total += len(bones[k], bones[k + 1])
        var best = Float.MAX_VALUE
        for (k in 0 until bones.size - 1) {
            val a = bones[k]
            val b = bones[k + 1]
            val l2 = len(a, b) * len(a, b)
            if (l2 < 1e-10f) continue
            val vx = thumb.x - a.x
            val vy = thumb.y - a.y
            val vz = thumb.z - a.z
            val dx = b.x - a.x
            val dy = b.y - a.y
            val dz = b.z - a.z
            val u = ((vx * dx + vy * dy + vz * dz) / l2).coerceIn(0f, 1f)
            val px = vx - dx * u
            val py = vy - dy * u
            val pz = vz - dz * u
            val d = kotlin.math.sqrt(px * px + py * py + pz * pz)
            if (d < best) best = d
        }
        return best < frac * total
    }

    private fun len(a: Vector3, b: Vector3) = kotlin.math.sqrt(
        (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) + (b.z - a.z) * (b.z - a.z),
    )

    @Test
    fun `t still runs knuckle to tip along the arc`() {
        assertEquals(0f, scrub(curled, curled.first()).t, 0.02f)
        assertEquals(1f, scrub(curled, curled.last()).t, 0.02f)
        // The middle joint is past halfway along the arc of this curl.
        val mid = scrub(curled, curled[2]).t
        assertTrue("mid was $mid", mid in 0.4f..0.9f)
    }

    @Test
    fun `an open hand still does not turn the reel`() {
        // Thumb abducted well clear of a curled finger.
        assertFalse(scrub(curled, Vector3(0.02f, -0.055f, 0f)).on)
    }

    @Test
    fun `a single tracked joint is not a finger`() {
        assertFalse(scrub(listOf(Vector3(0f, 0f, 0f)), Vector3(0f, 0f, 0f)).on)
        assertFalse(scrub(emptyList(), Vector3(0f, 0f, 0f)).on)
    }
}
