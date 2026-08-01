// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** T3 — the CJK output rules. Prohibitions first; nothing looks wrong at the call site. */
class TypeRulesTest {

    @Test fun latinMayBeUppercasedAndTracked() {
        assertTrue(TypeRules.mayUppercase("north everett"))
        assertTrue(TypeRules.mayTrack("north everett"))
        assertTrue(TypeRules.maySynthesiseWeight("north everett"))
    }

    /** The mixed-run case: uppercasing shouts the Latin half and leaves the kana. */
    @Test fun aRunWithAnyCjkIsExemptFromAllThree() {
        val mixed = "ridge-2 の中継局"
        assertFalse(TypeRules.mayUppercase(mixed))
        assertFalse(TypeRules.mayTrack(mixed))
        assertFalse(TypeRules.maySynthesiseWeight(mixed))
    }

    @Test fun cjkDetectionCoversKanaKanjiAndFullwidth() {
        assertTrue(TypeRules.hasCjk("中継局"))
        assertTrue(TypeRules.hasCjk("ひらがな"))
        assertTrue(TypeRules.hasCjk("カタカナ"))
        assertTrue(TypeRules.hasCjk("ＡＢＣ"))
        assertFalse(TypeRules.hasCjk("PLAIN ASCII"))
        assertFalse(TypeRules.hasCjk("Ökonomy"))
    }

    /** Same physical length, expressed in each script's own cells. */
    @Test fun theCjkLineIsHalfTheLatinOne() {
        assertEquals(TypeRules.LATIN_LINE_CELLS, TypeRules.maxCellsPerLine("plain text"))
        assertEquals(TypeRules.CJK_LINE_CELLS, TypeRules.maxCellsPerLine("中継局"))
        assertEquals(TypeRules.LATIN_LINE_CELLS, 2 * TypeRules.CJK_LINE_CELLS)
    }

    @Test fun shortTextIsOneLine() {
        assertEquals(listOf("hello"), TypeRules.wrap("hello", 30))
        assertEquals(listOf("中継局"), TypeRules.wrap("中継局", 15))
    }

    @Test fun everyLineRespectsTheBudget() {
        val jp = "この中継局は応答していません。基地局の電源を確認してください。"
        TypeRules.wrap(jp, 15).forEach {
            assertTrue("'$it' is ${TypeTier.displayCells(it)} cells",
                TypeTier.displayCells(it) <= 15)
        }
    }

    /** Nothing may be lost or invented by wrapping. */
    @Test fun wrappingPreservesTheText() {
        val jp = "この中継局は応答していません。基地局の電源を確認してください。"
        assertEquals(jp.replace(" ", ""), TypeRules.wrap(jp, 15).joinToString("").replace(" ", ""))
    }

    /** 行頭禁則: a full stop may not be stranded at the start of a line. */
    @Test fun aLineMayNotBeginWithAClosingMark() {
        TypeRules.wrap("応答なし。応答なし。応答なし。応答なし。", 8)
            .forEach { assertFalse("'$it' starts with a closer", it.isNotEmpty() && it[0] in "。、）」") }
    }

    /** 行末禁則: an opening bracket may not dangle at the end of a line. */
    @Test fun aLineMayNotEndWithAnOpeningMark() {
        assertFalse(TypeRules.kinsokuOk("abc「def", 0, 4))
        assertTrue(TypeRules.kinsokuOk("abc「def", 0, 3))
    }

    /** An unbreakable token longer than the line is cut, not overflowed. */
    @Test fun anOverlongTokenIsHardCut() {
        val out = TypeRules.wrap("A".repeat(80), 20)
        assertTrue(out.size >= 4)
        out.forEach { assertTrue(TypeTier.displayCells(it) <= 20) }
    }

    /** A hard cut must never split a surrogate pair into two broken halves. */
    @Test fun aHardCutNeverSplitsACodePoint() {
        val out = TypeRules.wrap("🍁".repeat(40), 10)
        out.forEach { line ->
            assertEquals(line, String(line.codePoints().toArray(), 0, line.codePointCount(0, line.length)))
        }
    }

    @Test fun wrappingTerminatesOnPathologicalInput() {
        assertEquals(listOf(""), TypeRules.wrap("", 10))
        assertTrue(TypeRules.wrap("。。。。。。。。。。", 2).isNotEmpty())
    }
}
