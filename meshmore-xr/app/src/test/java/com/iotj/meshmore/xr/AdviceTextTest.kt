// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.Advice
import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The advice card is the surface a wearer meets on the worst day the app has,
 * and it is a REUSABLE panel: sized once from a template, filled later. A line
 * that overruns its template does not wrap and does not clip cleanly — it
 * renders against stale bounds, which reads as a rendering fault on top of
 * whatever it was trying to explain.
 *
 * So every line the card can ever say is measured here, in both languages,
 * against the template that language's panel is actually built from.
 */
class AdviceTextTest {

    private fun res(name: String): Map<String, String> {
        var d = File(System.getProperty("user.dir"))
        repeat(4) {
            val f = File(d, "src/main/res/$name/strings.xml")
                .takeIf { it.exists() } ?: File(d, "app/src/main/res/$name/strings.xml")
            if (f.exists()) {
                return Regex("<string name=\"([^\"]+)\">(.*?)</string>", RegexOption.DOT_MATCHES_ALL)
                    .findAll(f.readText())
                    .associate { it.groupValues[1] to it.groupValues[2].removeSurrounding("\"") }
            }
            d = d.parentFile ?: return@repeat
        }
        error("strings.xml for $name not found")
    }

    /** As rendered: format args replaced by the widest thing they can carry. */
    private fun filled(raw: String): String = raw
        .replace("%1\$d", "999")
        .replace("%1\$s", "")
        .replace("\\'", "'")
        .replace("&#8212;", "—")

    private val bodyKeys = listOf(
        "nr_check", "nr_phone", "nr_retry",
        "nf_board_nogps", "nf_nofix", "nf_stuck", "nf_act",
    )
    private val titleKeys = listOf("nr_title", "nf_title")

    @Test
    fun `every english line fits the english panel`() {
        val en = res("values")
        bodyKeys.forEach {
            val s = filled(en.getValue(it))
            assertTrue(
                "$it is ${s.length} chars, panel holds ${Advice.WIDEST.length}: '$s'",
                s.length <= Advice.WIDEST.length,
            )
        }
        titleKeys.forEach {
            val s = filled(en.getValue(it))
            assertTrue(
                "$it is ${s.length} chars, title panel holds ${Advice.WIDEST_TITLE.length}: '$s'",
                s.length <= Advice.WIDEST_TITLE.length,
            )
        }
    }

    /**
     * JAPANESE RUNS AT A PROMOTED CAP, so the same plate holds far fewer
     * glyphs — 15 rather than 33. A JA line checked against the Latin budget
     * would pass at nearly twice the width the panel can draw.
     */
    @Test
    fun `every japanese line fits the japanese panel`() {
        val ja = res("values-ja")
        bodyKeys.forEach {
            val s = filled(ja.getValue(it))
            assertTrue(
                "$it is ${s.length} glyphs, JA panel holds ${Advice.WIDEST_JA.length}: '$s'",
                s.length <= Advice.WIDEST_JA.length,
            )
        }
        titleKeys.forEach {
            val s = filled(ja.getValue(it))
            assertTrue(
                "$it is ${s.length} glyphs, JA title holds ${Advice.WIDEST_TITLE_JA.length}: '$s'",
                s.length <= Advice.WIDEST_TITLE_JA.length,
            )
        }
    }

    /**
     * A board name is DATA — the catalogue may name a board more verbosely
     * than any template allows — so the card must be able to clip rather than
     * refuse. This pins the rule the runtime relies on: with the longest name
     * the catalogue can supply, the sentence still has room to be clipped into
     * the panel rather than overrun it.
     */
    @Test
    fun `the longest catalogued board name is clippable into the panel`() {
        val longest = DeviceBook.parse(File("src/main/assets/devices.json").readText())
            .maxOf { it.name.length }
        val sentence = filled(res("values").getValue("nf_board_nogps"))
        assertTrue(
            "a $longest-char board name plus '$sentence' must be clipped, and clipping " +
                "must leave the board's name legible — shorten the sentence, not the name",
            sentence.length + 6 <= Advice.WIDEST.length,
        )
    }
}
