// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import com.iotj.meshmore.xr.spatial.TypeTier.Tier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** T1 — the routing rule. Real MeshCore node names, off public meshes. */
class TypeTierTest {

    @Test fun latinBoundToAnObjectStaysStrokes() {
        assertEquals(Tier.STROKE, TypeTier.of("W7MIR REPEATER", boundToObject = true))
        assertEquals(Tier.STROKE, TypeTier.of("042", boundToObject = true))
        assertEquals(Tier.STROKE, TypeTier.of("SF7", boundToObject = true))
    }

    /** The whole point of T1: these used to become tofu boxes. */
    @Test fun cjkTakesTheRealFontPath() {
        assertEquals(Tier.RUN, TypeTier.of("中継局", boundToObject = true))
        assertEquals(Tier.RUN, TypeTier.of("ESTACADA の応答なし", boundToObject = true))
        assertEquals(Tier.RUN, TypeTier.of("かな", boundToObject = true))
    }

    @Test fun emojiTakesTheRealFontPath() {
        assertEquals(Tier.RUN, TypeTier.of("🍁 Hobart Nursery", boundToObject = true))
        assertEquals(Tier.RUN, TypeTier.of("Capitol Hill Prime💜", boundToObject = true))
    }

    /**
     * Decorated Latin is still Latin. Routing `Ökonomy` to a texture over one
     * diacritic would spend a run on something the stroke font draws fine once
     * NFKD has done its work.
     */
    @Test fun decoratedLatinFoldsAndStaysCheap() {
        assertTrue(TypeTier.drawableAsStrokes("Ökonomy"))
        assertTrue(TypeTier.drawableAsStrokes("ＡＢＣ"))
        assertEquals(Tier.STROKE, TypeTier.of("Ökonomy", boundToObject = true))
    }

    /** Not welded to anything means it is carrying language for its own sake. */
    @Test fun unboundTextIsAlwaysARun() {
        assertEquals(Tier.RUN, TypeTier.of("SETTINGS", boundToObject = false))
        assertEquals(Tier.RUN, TypeTier.of("W7MIR REPEATER"))
    }

    /** Past the cap a label stops being a label and becomes a paragraph. */
    @Test fun longLabelsLeaveTheStrokePath() {
        val long = "A".repeat(TypeTier.STROKE_MAX_CELLS + 1)
        assertEquals(Tier.RUN, TypeTier.of(long, boundToObject = true))
        val fits = "A".repeat(TypeTier.STROKE_MAX_CELLS)
        assertEquals(Tier.STROKE, TypeTier.of(fits, boundToObject = true))
    }

    /** An emoji is one cell, not two, or every length rule is off by one. */
    @Test fun cellsCountsCodePoints() {
        assertEquals(1, TypeTier.cells("🍁"))
        assertEquals(3, TypeTier.cells("A🍁B"))
        assertEquals(3, TypeTier.cells("中継局"))
    }

    @Test fun theEmptyStringIsHarmless() {
        assertTrue(TypeTier.drawableAsStrokes(""))
        assertEquals(Tier.STROKE, TypeTier.of("", boundToObject = true))
    }

    @Test fun cjkIsNotDrawableAsStrokes() {
        assertFalse(TypeTier.drawableAsStrokes("中"))
        assertFalse(TypeTier.drawableAsStrokes("🍁"))
    }

    /** PANEL is never routed to. A caller has to ask for it by name. */
    @Test fun panelIsNeverAutomatic() {
        val samples = listOf("中継局", "ABC", "🍁", "", "a".repeat(40), "ESTACADA の応答なし")
        assertTrue(samples.none { TypeTier.of(it) == Tier.PANEL })
        assertTrue(samples.none { TypeTier.of(it, boundToObject = true) == Tier.PANEL })
    }
}

/** Width budgeting — T2. A label the layout did not reserve space for is a collision. */
class TypeWidthTest {

    @Test fun kanjiCountsDouble() {
        assertEquals(6, TypeTier.displayCells("中継局"))
        assertEquals(3, TypeTier.displayCells("ABC"))
        assertEquals(2, TypeTier.displayCells("🍁"))
        assertEquals(8, TypeTier.displayCells("AB中継局"))
    }

    @Test fun shortTextIsNotClipped() {
        assertEquals("W7MIR", TypeTier.clip("W7MIR", 18))
        assertEquals("中継局", TypeTier.clip("中継局", 18))
    }

    /** The live failure: 23 cells rendered at 1.003 m, ~23 deg at its own range. */
    @Test fun theLiveOverrunIsClipped() {
        val out = TypeTier.clip("RBP SENSE CAP REPEATER ", 18)
        assertTrue("must be marked as cut", out.endsWith("…"))
        assertTrue("must fit the budget", TypeTier.displayCells(out) <= 18)
    }

    /** Clipping counts width, so a kanji name is cut at half the code points. */
    @Test fun clippingRespectsFullWidth() {
        val out = TypeTier.clip("中継局中継局中継局中継局", 18)
        assertTrue(TypeTier.displayCells(out) <= 18)
    }

    /** Never split a surrogate pair — half an emoji is a broken glyph, not a short one. */
    @Test fun clippingNeverSplitsACodePoint() {
        val out = TypeTier.clip("🍁".repeat(20), 18)
        assertEquals(out, String(out.codePoints().toArray(), 0, out.codePointCount(0, out.length)))
        assertTrue(TypeTier.displayCells(out) <= 18)
    }

    /** The estimate the layout uses must match what the renderer is handed. */
    @Test fun layoutBudgetsWhatIsActuallyDrawn() {
        val name = "RBP SENSE CAP REPEATER "
        val drawn = TypeTier.clip(name, MeshNodes.MAX_LABEL_CELLS)
        val estimatedCells = MeshNodes.labelHalfWidthRad(name) * 2f / MeshNodes.CELL_RAD
        assertEquals(TypeTier.displayCells(drawn).toFloat(), estimatedCells, 0.01f)
    }
}
