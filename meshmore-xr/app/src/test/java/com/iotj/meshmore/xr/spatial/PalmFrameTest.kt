// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Quaternion
import androidx.xr.runtime.math.Vector3
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * WHICH WAY DOES fromLookTowards POINT?
 *
 * The REEL's oval is not a circle, so unlike every other ring in this app it
 * cares about ROLL: put it on the palm a quarter turn out and the wide axis
 * runs up the fingers instead of across them. That makes the rotation
 * convention load-bearing for the first time.
 *
 * The library's own doc says "forward and upward" and does not say which local
 * axis each becomes, and this project has now lost four separate arguments to
 * directions asserted in comments — the panel sizing, the palm standoff, the
 * console lean, the north pip. So this measures it: build the rotation, apply
 * it to the three basis vectors, and record where they land. If a library
 * update changes the convention, this fails here rather than by putting the
 * reel sideways on someone's hand.
 */
class PalmFrameTest {

    private fun rot(q: Quaternion, v: Vector3): Vector3 =
        Pose(Vector3(0f, 0f, 0f), q).transformPoint(v)

    private fun near(tag: String, want: Vector3, got: Vector3) {
        assertEquals("$tag x", want.x, got.x, 1e-4f)
        assertEquals("$tag y", want.y, got.y, 1e-4f)
        assertEquals("$tag z", want.z, got.z, 1e-4f)
    }

    @Test
    fun `forward is local Z and up is local Y`() {
        // A frame rotated a clean 90 degrees so any axis mix-up is unmistakable:
        // forward -> +X, up -> +Y.
        val q = Quaternion.fromLookTowards(Vector3(1f, 0f, 0f), Vector3(0f, 1f, 0f))
        near("forward", Vector3(1f, 0f, 0f), rot(q, Vector3(0f, 0f, 1f)))
        near("up", Vector3(0f, 1f, 0f), rot(q, Vector3(0f, 1f, 0f)))
    }

    @Test
    fun `the third axis completes the frame the same way every time`() {
        val q = Quaternion.fromLookTowards(Vector3(1f, 0f, 0f), Vector3(0f, 1f, 0f))
        val x = rot(q, Vector3(1f, 0f, 0f))
        // Whatever handedness it is, record it: local X must land on ONE of the
        // two remaining directions, and which one decides the oval's wide axis.
        near("right", Vector3(0f, 0f, -1f), x)
    }
}

/**
 * THE CARD'S WRAP.
 *
 * A message at a readable size is wider than the display: 18 characters at the
 * card's cap height is about 40 degrees against a 34-degree field. So the
 * raised card wraps, and wrapping is exactly the kind of small text routine
 * that is fine until someone sends a 40-character URL with no spaces in it —
 * which on a mesh radio is a normal Tuesday.
 *
 * The contract being protected: never wider than the column count, never more
 * lines than the card has, and never an infinite loop on an unbreakable token.
 * The wrap lives at file scope in Reel.kt precisely so this can call the real
 * one — a test against a copied-out version of the logic tests the copy.
 */
class ReelWrapTest {

    private val cols = 14
    private val lines = 3

    private fun wrap(text: String) = wrap(text, cols, lines)

    private fun check(text: String) {
        val r = wrap(text)
        assertTrue("too many lines: $r", r.size <= lines)
        r.forEach { assertTrue("line too wide: '$it'", it.length <= cols) }
    }

    @Test
    fun `short text stays on one line`() {
        assertEquals(listOf("on my way"), wrap("on my way"))
    }

    @Test
    fun `it breaks at spaces`() {
        assertEquals(listOf("the repeater", "is back up"), wrap("the repeater is back up"))
    }

    @Test
    fun `an unbreakable token is chopped rather than hanging`() {
        // The case that would spin forever if the long-word branch forgot to
        // consume: no spaces at all, far wider than a line.
        check("https://example.invalid/a/very/long/path/indeed")
        assertEquals(14, wrap("https://example.invalid/a/very/long/path").first().length)
    }

    @Test
    fun `overflow is truncated, not stacked forever`() {
        check((1..80).joinToString(" ") { "word" })
    }

    @Test
    fun `text that fits the card is not silently shortened`() {
        // The failure this guards: the card's capacity and the feed's clip
        // drifting apart, so the feed trims to the OLD size and the card
        // renders a shortened message with no sign that anything was cut.
        // NINE, not twelve. Word packing never reaches the raw cols x lines
        // product -- a line ends when the next word will not fit, so "abc"
        // words give three per fourteen-column line and eleven of its
        // characters are used. Writing the naive product into this test is how
        // a capacity gets overstated, so it is spelled out: 3 lines x 3 words.
        val words = (1..9).joinToString(" ") { "abc" }
        assertEquals(words, wrap(words).joinToString(" "))
    }

    @Test
    fun `empty and whitespace do not produce a blank line`() {
        assertEquals(emptyList<String>(), wrap(""))
        assertEquals(emptyList<String>(), wrap("   "))
    }
}

/**
 * OVERFLOW IS VISIBLE.
 *
 * Word packing never reaches cols x lines, so a message sized against that
 * product overflows the card. Losing the tail is survivable -- the whole
 * message is in the thread corridor -- but losing it SILENTLY is not: the
 * wearer reads a sentence that stops and has no way to tell a terse message
 * from a truncated one.
 */
class ReelOverflowTest {

    @Test
    fun `an overlong message is marked, not merely cut`() {
        val long = (1..40).joinToString(" ") { "word" }
        val r = wrap(long, 18, 3)
        assertEquals(3, r.size)
        assertTrue("no ellipsis on '${r.last()}'", r.last().endsWith("…"))
        r.forEach { assertTrue("too wide: '$it'", it.length <= 18) }
    }

    @Test
    fun `a message that fits carries no ellipsis`() {
        val r = wrap("the repeater is back up", 18, 3)
        assertFalse(r.last().endsWith("…"))
    }

    @Test
    fun `an unbroken token that overflows is still marked`() {
        val r = wrap("x".repeat(200), 18, 3)
        assertEquals(3, r.size)
        assertTrue(r.last().endsWith("…"))
    }

    @Test
    fun `degenerate bounds return nothing rather than looping`() {
        assertEquals(emptyList<String>(), wrap("anything", 0, 3))
        assertEquals(emptyList<String>(), wrap("anything", 18, 0))
    }
}
