// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The dock and console marks.
 *
 * Artwork is not usually worth testing, but these fail SILENTLY in two ways.
 * A bay with no mark does not crash — `Console.build` falls back to a plain
 * ring, so the pip is still there, still pickable, and simply carries no
 * identity, which is the exact problem marks were introduced to solve. And a
 * mark that draws the wrong idea draws perfectly well: PROFILE spent months as
 * a circle with a hand at twelve and a hand at four, a stopwatch on the pip
 * that opens themes, with a comment above it describing a swatch ring.
 *
 * The geometry itself is not checkable here — the paths are parsed by
 * androidx PathParser into an android.graphics.Path, neither of which exists on
 * a JVM unit test classpath. What is checkable is coverage and syntax.
 */
class MarksTest {

    /**
     * Mirrors `Console.plates` and the dock's pips. Duplicated rather than
     * imported because both lists are instance state behind a private
     * companion; the failure this catches — a bay whose mark was never drawn —
     * is worth a list that has to be kept in step.
     */
    private val bays = listOf(
        "DEVICE", "APP", "PROFILE", "CHANNELS", "DIAG", "ABOUT",
    )

    private val pips = listOf(
        "COMPASS", "LINK", "RADIO", "HELP", "HERE", "WIDE",
        "SETUP", "INBOX", "LIST", "NORTH", "HANDS", "SCRUB",
    )

    /** A bay's mark may be filed under another name — see Console.MARK_FOR. */
    private fun markFor(bay: String) = Console.MARK_FOR[bay] ?: bay

    @Test fun everyBayAndPipHasAMark() {
        bays.forEach {
            assertTrue("$it falls back to a featureless ring", Marks.has(markFor(it)))
        }
        pips.forEach {
            assertTrue("$it falls back to a featureless ring", Marks.has(it))
        }
    }

    /**
     * PathParser is strict and throws on an unknown command, which
     * `AslIcon.fromPath` catches — so a typo'd command letter degrades to the
     * same silent fallback ring as a missing mark.
     */
    @Test fun everyPathUsesOnlyCommandsTheParserKnows() {
        (bays.map(::markFor) + pips).forEach { name ->
            val d = Marks[name]!!
            val bad = d.filter { it.isLetter() && it !in "MmLlHhVvAaQqCcSsTtZz" }
            assertFalse("$name uses '$bad'", bad.isNotEmpty())
            assertTrue("$name does not start with a move", d.trimStart().startsWith("M"))
        }
    }

    /**
     * THE CLOCK, PINNED SHUT.
     *
     * The old PROFILE was a ring plus `M50 20 V50 L76 65` — two hands. A
     * palette is all arcs and moves, so any straight segment reappearing in
     * this mark means the hands are back.
     */
    @Test fun theProfileMarkIsAPaletteAndNotAClock() {
        val d = Marks["PROFILE"]!!
        assertFalse("a hand is back on the profile mark", d.any { it in "LlHhVv" })
        // A body, a thumb hole, and three dabs: five subpaths, and the thumb
        // hole is what stops the body reading as an egg.
        assertTrue("expected five subpaths", d.count { it == 'M' } == 5)
    }

    /**
     * At 3° a mark is a silhouette, and the set already spends two of them on
     * concentric rings — HERE's crosshair and ABOUT's information glyph. A
     * third would be a coin toss, so PROFILE's body is an oval: unequal radii,
     * checked here because the difference is one character in a path.
     */
    @Test fun theProfileBodyIsAnOvalRatherThanAThirdRing() {
        val d = Marks["PROFILE"]!!
        // The body is the first arc pair; its radii are the two numbers after
        // the first 'a'.
        val firstArc = d.substringAfter(" a").trim().split(" ")
        val rx = firstArc[0].toFloat()
        val ry = firstArc[1].toFloat()
        assertTrue("body is $rx x $ry — a circle", rx != ry)
    }
}
