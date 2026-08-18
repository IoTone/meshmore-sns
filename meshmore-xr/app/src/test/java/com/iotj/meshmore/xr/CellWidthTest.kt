// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.RADIO_NAME_MAX
import com.iotj.meshmore.xr.spatial.ROW_WIDEST
import com.iotj.meshmore.xr.spatial.ROW_WIDEST_JA
import com.iotj.meshmore.xr.spatial.TypeTier
import com.iotj.meshmore.xr.spatial.radioRow
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * WIDTH, WHICH IS NOT LENGTH.
 *
 * Every row on a plate lines a value up beside a name by counting characters,
 * and that count was `String.length` everywhere. It is right for Latin and
 * wrong by a factor of two for the locale that is release-blocking: 周波数 is
 * three code units and draws as wide as six letters. A row that measures with
 * length gives a kanji label almost the whole plate and then trims the value
 * that was the point of the row.
 *
 * None of this is visible on the emulator, which cannot render text written to
 * a panel after creation in either language, so it is checked here or not at
 * all.
 */
class CellWidthTest {

    @After fun reset() { L10n.ja = false }

    @Test fun latinCountsOneAndKanjiCountsTwo() {
        assertEquals(3, TypeTier.displayCells("ABC"))
        assertEquals(6, TypeTier.displayCells("周波数"))
        assertEquals(9, TypeTier.displayCells("周波数ABC"))
        assertEquals(0, TypeTier.displayCells(""))
    }

    /** Kana and fullwidth forms draw wide too, not only kanji. */
    @Test fun kanaAndFullwidthAreWide() {
        assertEquals(10, TypeTier.displayCells("ゼロホップ"))
        assertEquals(4, TypeTier.displayCells("ＡＢ"))
        assertEquals("wide punctuation, plus one narrow space", 3, TypeTier.displayCells("。 "))
    }

    /**
     * THE TWO TEMPLATES DESCRIBE THE SAME PLATE. They were measured
     * independently on the device — 28 Latin characters, and 13 kanji — and if
     * the width model is right they must come out within a character of each
     * other. This is the check that the model matches the hardware rather than
     * matching itself.
     */
    @Test fun bothRowTemplatesMeasureTheSamePlate() {
        val en = TypeTier.displayCells(ROW_WIDEST)
        val ja = TypeTier.displayCells(ROW_WIDEST_JA)
        assertTrue("en=$en ja=$ja", kotlin.math.abs(en - ja) <= 2)
    }

    /**
     * CLIPPING IS TypeTier'S, not a second copy of it. TypeTier.clip reserves
     * one cell for the ellipsis it appends and never splits a wide character,
     * which is what a row needs and what this asserts rather than reimplements.
     */
    @Test fun clippingNeverSplitsAWideCharacter() {
        assertEquals("全中…", TypeTier.clip("全中継局", 6))
        assertEquals("ABCD…", TypeTier.clip("ABCDEFG", 5))
        assertEquals("全中継局", TypeTier.clip("全中継局", 8))
    }

    /** A Latin row is exactly what it always was — nothing regressed. */
    @Test fun latinRowsAreUnchanged() {
        L10n.ja = false
        assertEquals("FREQ  910.525", radioRow("FREQ", "910.525", null))
        assertEquals("BANDWIDTH  62.5→250", radioRow("BANDWIDTH", "62.5", "250"))
    }

    /**
     * AND A KANJI ROW KEEPS ITS VALUE. The failure this replaces is silent —
     * the name fits, the value is trimmed to nothing, and the row reads as a
     * label with no reading beside it.
     */
    @Test fun aKanjiNameLeavesRoomForTheValue() {
        L10n.ja = true
        val r = radioRow("無線機を再検索", "Bluetooth", null)
        // Only the NAME is uppercased by radioRow; a value is shown as given.
        assertTrue("value was trimmed away: '$r'", r.endsWith("Bluetooth"))
        assertTrue("row is wider than the plate: '$r'", TypeTier.displayCells(r) <= TypeTier.displayCells(ROW_WIDEST_JA) + 2)
    }

    /** An over-long kanji name is clipped by WIDTH and marked as clipped. */
    @Test fun anOverlongKanjiNameIsClippedNotOverflowed() {
        L10n.ja = true
        val r = radioRow("無線機を再検索するとても長い名前", "X", null)
        assertTrue("no ellipsis: '$r'", r.contains("…"))
        assertTrue(
            "name took more than its budget: '$r'",
            TypeTier.displayCells(r.substringBefore("  ")) <= RADIO_NAME_MAX,
        )
    }
}
