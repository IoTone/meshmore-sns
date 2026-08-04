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
