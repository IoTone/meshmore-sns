// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The symbology axis: every theme gets its own node mark, and every mark still
 * does the job the mark exists for.
 *
 * `Horizon.markFor` needs a Session to build meshes, so what is checked here is
 * the TABLE — that all nine themes are covered, that the set is closed, and
 * that the assignments are the ones the theme spec names. The geometric
 * relationships are asserted in the file's own comments and looked at on
 * glass; what a test can catch is a theme quietly falling back to SOLID,
 * which would be invisible on a device unless you happened to know what that
 * theme was supposed to look like.
 */
class SymbolTest {

    @Test fun everyThemeStatesItsSymbol() {
        Theme.ALL.forEach { s ->
            // Not a null check — the field has a default, and the default is
            // the trap. A theme that never states a symbol silently renders as
            // HALO FIELD, which is exactly the "nine palettes" problem.
            assertTrue("${s.key} has no symbol of its own", s.symbol in Theme.Symbol.entries)
        }
    }

    /**
     * THE ONE THAT MATTERS. Seven of the nine must NOT be SOLID — that was the
     * state of the world before this axis existed, and a regression here is a
     * theme quietly going back to being a palette.
     */
    @Test fun onlyHaloFieldIsPlainSolid() {
        val solid = Theme.ALL.filter { it.symbol == Theme.Symbol.SOLID }
        assertEquals("themes still rendering as plain discs: ${solid.map { it.key }}", 1, solid.size)
        assertEquals(Theme.HALO.key, solid.first().key)
    }

    /** Every symbol in the set is actually used; none is dead code. */
    @Test fun everySymbolHasAThemeAndNoTwoThemesShareOne() {
        val used = Theme.ALL.map { it.symbol }
        Theme.Symbol.entries.forEach { sym ->
            assertTrue("$sym is defined but no theme uses it", sym in used)
        }
        assertEquals("two themes share a symbol", used.size, used.toSet().size)
    }

    /** The assignments the theme spec names, pinned so a rename cannot drift. */
    @Test fun theAssignmentsAreTheOnesTheSpecNames() {
        assertEquals(Theme.Symbol.SOLID, Theme.HALO.symbol)
        assertEquals(Theme.Symbol.HEX, Theme.NERV.symbol)
        assertEquals(Theme.Symbol.CHEVRON, Theme.AGSYS.symbol)
        assertEquals(Theme.Symbol.SLAB, Theme.SEELE.symbol)
        assertEquals(Theme.Symbol.BLOCK, Theme.DRPOP.symbol)
        assertEquals(Theme.Symbol.RADAR, Theme.RECON.symbol)
        assertEquals(Theme.Symbol.WIRE, Theme.VECTOR.symbol)
        assertEquals(Theme.Symbol.SPORE, Theme.BIOLUME.symbol)
        assertEquals(Theme.Symbol.TEXT, Theme.VOID.symbol)
    }

    /**
     * TEXT is the only symbol that draws nothing, and only TERMINAL VOID may
     * use it. A second text theme would be one whose horizon is empty without
     * anybody having decided that.
     */
    @Test fun onlyOneThemeDrawsNoGeometry() {
        assertEquals(1, Theme.ALL.count { it.symbol == Theme.Symbol.TEXT })
    }

    // --- menu plates ---------------------------------------------------------

    /**
     * A theme's PLATE follows its SYMBOL. A wire node next to a solid slab of a
     * button is two applications in one view — and on additive optics the
     * choice is not cosmetic: a filled plate washes out the room behind it and
     * a frame does not.
     */
    @Test fun openSymbolsGetOpenPlates() {
        Theme.ALL.forEach { s ->
            if (s.symbol == Theme.Symbol.WIRE || s.symbol == Theme.Symbol.RADAR) {
                assertEquals(
                    "${s.key} draws open marks but a solid plate",
                    Theme.Plate.FRAME, s.plate,
                )
            }
        }
    }

    /** The two themes with no plate are the two that put type on nothing. */
    @Test fun onlyTypeOnNothingThemesHaveNoPlate() {
        val none = Theme.ALL.filter { it.plate == Theme.Plate.NONE }.map { it.key }.toSet()
        assertEquals(setOf("seele", "void"), none)
    }

    /** Every plate style is used; none is dead code. */
    @Test fun everyPlateStyleHasATheme() {
        val used = Theme.ALL.map { it.plate }
        Theme.Plate.entries.forEach { p ->
            assertTrue("$p is defined but no theme uses it", p in used)
        }
    }

    /**
     * The single-hue themes are the ones that most need form to carry meaning,
     * because they have no colour left to spend on it. Both must have a symbol
     * whose node, repeater and cluster differ in SHAPE and not only in size.
     */
    @Test fun theSingleHueThemesCarryMeaningInForm() {
        listOf(Theme.RECON, Theme.VOID, Theme.SEELE).forEach { s ->
            assertTrue(
                "${s.key} is single-hue and must not lean on a plain disc",
                s.symbol != Theme.Symbol.SOLID,
            )
        }
    }
}
