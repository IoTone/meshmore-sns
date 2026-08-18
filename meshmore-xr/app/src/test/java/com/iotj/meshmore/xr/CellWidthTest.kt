// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.RADIO_NAME_MAX
import com.iotj.meshmore.xr.spatial.ROW_WIDEST
import com.iotj.meshmore.xr.spatial.ROW_WIDEST_JA
import com.iotj.meshmore.xr.spatial.clipTo
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
        assertEquals(3, L10n.width("ABC"))
        assertEquals(6, L10n.width("周波数"))
        assertEquals(9, L10n.width("周波数ABC"))
        assertEquals(0, L10n.width(""))
    }

    /** Kana and fullwidth forms draw wide too, not only kanji. */
    @Test fun kanaAndFullwidthAreWide() {
        assertEquals(10, L10n.width("ゼロホップ"))
        assertEquals(4, L10n.width("ＡＢ"))
        assertEquals("wide punctuation, plus one narrow space", 3, L10n.width("。 "))
    }

    /**
     * THE TWO TEMPLATES DESCRIBE THE SAME PLATE. They were measured
     * independently on the device — 28 Latin characters, and 13 kanji — and if
     * the width model is right they must come out within a character of each
     * other. This is the check that the model matches the hardware rather than
     * matching itself.
     */
    @Test fun bothRowTemplatesMeasureTheSamePlate() {
        val en = L10n.width(ROW_WIDEST)
        val ja = L10n.width(ROW_WIDEST_JA)
        assertTrue("en=$en ja=$ja", kotlin.math.abs(en - ja) <= 2)
    }

    @Test fun clippingNeverSplitsAWideCharacter() {
        // 5 half-cells of "全中継局" (8 wide) must stop at two characters, not
        // take two and a half.
        assertEquals("全中", clipTo("全中継局", 5))
        assertEquals("全中継", clipTo("全中継局", 6))
        assertEquals("ABCD", clipTo("ABCDE", 4))
        assertEquals("", clipTo("全", 1))
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
        assertTrue("row is wider than the plate: '$r'", L10n.width(r) <= L10n.width(ROW_WIDEST_JA) + 2)
    }

    /** An over-long kanji name is clipped by WIDTH and marked as clipped. */
    @Test fun anOverlongKanjiNameIsClippedNotOverflowed() {
        L10n.ja = true
        val r = radioRow("無線機を再検索するとても長い名前", "X", null)
        assertTrue("no ellipsis: '$r'", r.contains("…"))
        assertTrue(
            "name took more than its budget: '$r'",
            L10n.width(r.substringBefore("  ")) <= RADIO_NAME_MAX,
        )
    }
}
