// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The transition grammar, and the two rules it exists under.
 *
 * These are cheap because [Reveal] is arithmetic, and they matter because the
 * failure modes are all invisible in a log: a surface that never settles, an
 * element that never arrives, a stagger that pushes a six-row bay past the
 * point where it stops feeling like a response to your hand.
 */
class RevealTest {

    @After fun resetReduced() { Reveal.reduced = false }

    private val rows = 6

    /**
     * THE CEILING, from the spec: "No transition may exceed 400 ms. Above that
     * a menu stops feeling like a response to your hand. This is the one place
     * where the aesthetic loses."
     *
     * Measured with the STAGGER INCLUDED, on the largest surface any bay draws.
     * Duration alone passing while the last row arrives at 600 ms is exactly
     * the mistake this catches.
     */
    @Test fun noThemeExceedsTheCeilingOnAFullSurface() {
        Theme.ALL.forEach { s ->
            val total = Reveal.totalMs(s, rows)
            assertTrue(
                "${s.key} takes ${total}ms for $rows rows, ceiling is ${Reveal.CEILING_MS}",
                total <= Reveal.CEILING_MS,
            )
        }
    }

    /** Everything settles, and settles exactly where the layout asked. */
    @Test fun everySurfaceSettlesCompletely() {
        Theme.ALL.forEach { s ->
            val after = Reveal.totalMs(s, rows).toLong() + 1
            for (i in 0 until rows) {
                val f = Reveal.at(s, i, rows, after)
                assertTrue("${s.key} row $i never arrived", f.on)
                assertEquals("${s.key} row $i off-position", 0f, f.along, 1e-4f)
                assertEquals("${s.key} row $i off-depth", 0f, f.depth, 1e-4f)
                assertEquals("${s.key} row $i wrong size", 1f, f.scale, 1e-4f)
            }
        }
    }

    /** ...and stays settled, so this is safe to call every frame forever. */
    @Test fun aSurfaceOpenForAMinuteIsStillSettled() {
        Theme.ALL.forEach { s ->
            val f = Reveal.at(s, 3, rows, 60_000L)
            assertEquals(s.key, 1f, f.scale, 1e-4f)
            assertTrue(s.key, f.on)
        }
    }

    /** Nothing is ever drawn at zero size, which reads as a flicker. */
    @Test fun nothingIsEverDrawnAtNothing() {
        Theme.ALL.forEach { s ->
            var t = 0L
            while (t <= Reveal.totalMs(s, rows) + 20L) {
                for (i in 0 until rows) {
                    val f = Reveal.at(s, i, rows, t)
                    if (f.on) assertTrue("${s.key} row $i at ${t}ms", f.scale > 0.01f)
                }
                t += 5L
            }
        }
    }

    /**
     * SEELE does not animate, at any point, ever. The absence IS the identity —
     * see the note in Reveal. A future flourish that "fixes" this fails here.
     */
    @Test fun seeleIsThereImmediatelyAndCompletely() {
        for (i in 0 until rows) {
            val f = Reveal.at(Theme.SEELE, i, rows, 0L)
            assertTrue(f.on)
            assertEquals(1f, f.scale, 1e-6f)
            assertEquals(0f, f.along, 1e-6f)
        }
        assertEquals(0, Reveal.totalMs(Theme.SEELE, rows))
    }

    /**
     * DR POP slams: full scale from the first frame, and all rows at once.
     * Simultaneity is the point, so a stagger here would be wrong.
     */
    @Test fun drPopArrivesAllAtOnceAtFullSize() {
        val first = Reveal.at(Theme.DRPOP, 0, rows, 0L)
        val last = Reveal.at(Theme.DRPOP, rows - 1, rows, 0L)
        assertTrue(first.on && last.on)
        assertEquals(1f, first.scale, 1e-6f)
        assertEquals(1f, last.scale, 1e-6f)
    }

    /** VOID types line by line, so a later row genuinely waits its turn. */
    @Test fun voidRevealsOneLineAtATime() {
        val early = Reveal.at(Theme.VOID, 5, rows, 10L)
        assertTrue("the last line should not be up yet", !early.on)
        assertTrue(Reveal.at(Theme.VOID, 0, rows, 10L).on)
    }

    /** BIOLUME grows from the bottom, the way something rooted does. */
    @Test fun biolumeArrivesBottomUp() {
        val t = 10L
        assertTrue(Reveal.at(Theme.BIOLUME, rows - 1, rows, t).on)
        assertTrue(!Reveal.at(Theme.BIOLUME, 0, rows, t).on)
    }

    /**
     * REDUCE MOTION KEEPS THE ORDER AND REMOVES THE TRAVEL.
     *
     * An instant cut would have thrown away the stagger too — and the stagger
     * is information about how sudden the change was. Without it all nine
     * themes arrive identically again, which is the problem this whole file
     * exists to solve.
     */
    @Test fun reduceMotionKeepsOrderAndDropsTravel() {
        Reveal.reduced = true
        Theme.ALL.forEach { s ->
            var t = 0L
            while (t <= Reveal.totalMs(s, rows)) {
                for (i in 0 until rows) {
                    val f = Reveal.at(s, i, rows, t)
                    if (f.on) {
                        assertEquals("${s.key} moved with reduce-motion on", 0f, f.along, 1e-6f)
                        assertEquals("${s.key} moved with reduce-motion on", 0f, f.depth, 1e-6f)
                        assertEquals("${s.key} scaled with reduce-motion on", 1f, f.scale, 1e-6f)
                    }
                }
                t += 7L
            }
        }
        // ...and VOID still arrives line by line.
        assertTrue(!Reveal.at(Theme.VOID, 5, rows, 10L).on)
    }

    /** A one-row surface has no stagger to serve, and must not stall. */
    @Test fun aSingleRowSurfaceIsFine() {
        Theme.ALL.forEach { s ->
            assertTrue(s.key, Reveal.at(s, 0, 1, Reveal.totalMs(s, 1).toLong() + 1).on)
        }
    }
}
