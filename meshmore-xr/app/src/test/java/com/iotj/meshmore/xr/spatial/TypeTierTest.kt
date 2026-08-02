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

    /** Instrument markings keep the stroke font — they are not words. */
    @Test fun marksStayStrokes() {
        assertEquals(Tier.STROKE, TypeTier.of("042", TypeTier.Kind.MARK))
        assertEquals(Tier.STROKE, TypeTier.of("SF7", TypeTier.Kind.MARK))
        assertEquals(Tier.STROKE, TypeTier.of("FREQ", TypeTier.Kind.MARK))
    }

    /**
     * A NAME always takes the real font, even plain Latin. This is the whole
     * point of the split: on the ring a proportional mixed-case name beside an
     * all-caps vector one read as two different applications.
     */
    @Test fun namesAlwaysTakeTheRealFont() {
        assertEquals(Tier.RUN, TypeTier.of("W7MIR REPEATER", TypeTier.Kind.NAME))
        assertEquals(Tier.RUN, TypeTier.of("中継局", TypeTier.Kind.NAME))
        assertEquals(Tier.RUN, TypeTier.of("Woofy Repeater", TypeTier.Kind.NAME))
    }

    /** The whole point of T1: these used to become tofu boxes. */
    /** Even asked for as a MARK, a script the stroke font cannot draw routes out. */
    @Test fun cjkTakesTheRealFontPath() {
        assertEquals(Tier.RUN, TypeTier.of("中継局", TypeTier.Kind.MARK))
        assertEquals(Tier.RUN, TypeTier.of("ESTACADA の応答なし", TypeTier.Kind.MARK))
        assertEquals(Tier.RUN, TypeTier.of("かな", TypeTier.Kind.MARK))
    }

    @Test fun emojiTakesTheRealFontPath() {
        assertEquals(Tier.RUN, TypeTier.of("🍁 Hobart Nursery", TypeTier.Kind.MARK))
        assertEquals(Tier.RUN, TypeTier.of("Capitol Hill Prime💜", TypeTier.Kind.MARK))
    }

    /**
     * Decorated Latin is still Latin. Routing `Ökonomy` to a texture over one
     * diacritic would spend a run on something the stroke font draws fine once
     * NFKD has done its work.
     */
    @Test fun decoratedLatinFoldsAndStaysCheap() {
        assertTrue(TypeTier.drawableAsStrokes("Ökonomy"))
        assertTrue(TypeTier.drawableAsStrokes("ＡＢＣ"))
        assertEquals(Tier.STROKE, TypeTier.of("Ökonomy", TypeTier.Kind.MARK))
    }

    /** Not welded to anything means it is carrying language for its own sake. */
    @Test fun theDefaultKindIsName() {
        assertEquals(Tier.RUN, TypeTier.of("SETTINGS"))
        assertEquals(Tier.RUN, TypeTier.of("W7MIR REPEATER"))
    }

    /** Past the cap a label stops being a label and becomes a paragraph. */
    @Test fun longLabelsLeaveTheStrokePath() {
        val long = "A".repeat(TypeTier.STROKE_MAX_CELLS + 1)
        assertEquals(Tier.RUN, TypeTier.of(long, TypeTier.Kind.MARK))
        val fits = "A".repeat(TypeTier.STROKE_MAX_CELLS)
        assertEquals(Tier.STROKE, TypeTier.of(fits, TypeTier.Kind.MARK))
    }

    /** An emoji is one cell, not two, or every length rule is off by one. */
    @Test fun cellsCountsCodePoints() {
        assertEquals(1, TypeTier.cells("🍁"))
        assertEquals(3, TypeTier.cells("A🍁B"))
        assertEquals(3, TypeTier.cells("中継局"))
    }

    @Test fun theEmptyStringIsHarmless() {
        assertTrue(TypeTier.drawableAsStrokes(""))
        assertEquals(Tier.STROKE, TypeTier.of("", TypeTier.Kind.MARK))
    }

    @Test fun cjkIsNotDrawableAsStrokes() {
        assertFalse(TypeTier.drawableAsStrokes("中"))
        assertFalse(TypeTier.drawableAsStrokes("🍁"))
    }

    /** PANEL is never routed to. A caller has to ask for it by name. */
    @Test fun panelIsNeverAutomatic() {
        val samples = listOf("中継局", "ABC", "🍁", "", "a".repeat(40), "ESTACADA の応答なし")
        assertTrue(samples.none { TypeTier.of(it) == Tier.PANEL })
        assertTrue(samples.none { TypeTier.of(it, TypeTier.Kind.MARK) == Tier.PANEL })
    }
}

/** Width budgeting — T2. A label the layout did not reserve space for is a collision. */
class TypeWidthTest {

    @Test fun kanjiCountsDouble() {
        assertEquals(6, TypeTier.displayCells("中継局"))
        assertEquals(3, TypeTier.displayCells("ABC"))
        // Emoji are 3: measured ~1.24 em from the system emoji font, which is
        // wider than a full-width CJK cell. See TypeTier.cellsOf.
        assertEquals(3, TypeTier.displayCells("🍁"))
        assertEquals(8, TypeTier.displayCells("AB中継局"))
        assertEquals(5, TypeTier.displayCells("AB🍁"))
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
        val cellRad = MeshNodes.CAP_FRACTION * TypeTier.cellEm(drawn, TypeTier.Kind.NAME)
        val estimatedCells = MeshNodes.labelHalfWidthRad(name) * 2f / cellRad
        assertEquals(TypeTier.displayCells(drawn).toFloat(), estimatedCells, 0.01f)
    }

    /**
     * A stroke label and a run of the same cell count are NOT the same width.
     * Budgeting both with one constant is how an 18-cell label ends up two
     * characters into its neighbour.
     */
    @Test fun theTwoTiersAreBudgetedSeparately() {
        val stroke = "W7MIR REPEATER"                 // Latin, 14 cells -> STROKE
        val run = "中継局中継局中"                      // CJK, 14 cells -> RUN
        assertEquals(14, TypeTier.displayCells(stroke))
        assertEquals(14, TypeTier.displayCells(run))
        assertEquals(TypeTier.STROKE_CELL_EM, TypeTier.cellEm(stroke, TypeTier.Kind.MARK), 1e-4f)
        assertEquals(TypeTier.RUN_CELL_EM, TypeTier.cellEm(run, TypeTier.Kind.MARK), 1e-4f)
        // As NAMES both are runs, so both budget the same — which is the point:
        // the ring's labels are now one kind of thing.
        assertEquals(MeshNodes.labelHalfWidthRad(stroke), MeshNodes.labelHalfWidthRad(run), 1e-5f)
    }

    /** The stroke constant is the font's own geometry, not a guess: 5.6/6. */
    @Test fun theStrokeCellMatchesTheFontMetrics() {
        assertEquals(5.6f / 6f, TypeTier.STROKE_CELL_EM, 1e-3f)
    }
}
