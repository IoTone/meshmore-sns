// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import com.iotj.meshmore.xr.spatial.Crown
import com.iotj.meshmore.xr.spatial.Dock
import com.iotj.meshmore.xr.spatial.Notice
import com.iotj.meshmore.xr.spatial.TypeTier
import org.w3c.dom.Element

/**
 * THE JAPANESE BUILD, CHECKED WITHOUT A JAPANESE READER.
 *
 * A native speaker has to judge whether the words are right. Nobody needs to
 * be a speaker to catch the three ways this file set breaks silently, and all
 * three have happened here:
 *
 *  1. A KEY ADDED TO ONE LOCALE ONLY. Android falls back to the default, so a
 *     Japanese wearer gets an English line and no error anywhere. Half the
 *     complaint that opened the localisation work — "lots of missing texts" —
 *     was exactly this.
 *  2. FORMAT SPECIFIERS THAT DISAGREE. `%1$s` in one locale and `%1$d` in the
 *     other is not a translation question, it is an IllegalFormatConversion at
 *     the moment the string is shown, in the language nobody tests in.
 *  3. KEYS NOTHING READS. Dead strings cost a reviewer real time and imply the
 *     app says things it does not; four of them survived a feature being moved
 *     to the alerts log, and the HERE caption outlived its surface by weeks.
 *
 * Run against the resources themselves rather than R, because the point is to
 * fail before an APK exists.
 */
class StringsParityTest {

    private class Res(val strings: Map<String, String>, val arrays: Map<String, Int>)

    /** Thread.WIDEST_HEAD, and MainActivity's WHO_COLUMN — both private. */
    private val THREAD_HEAD = "MMMMMMMMMMMMMM  99 MIN AGO"
    private val NAME_COLUMN = 15

    private fun read(path: String): Res {
        val f = File(path)
        assertTrue("missing $path", f.exists())
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(f)
        val s = mutableMapOf<String, String>()
        doc.getElementsByTagName("string").let { n ->
            for (i in 0 until n.length) {
                val e = n.item(i) as Element
                s[e.getAttribute("name")] = e.textContent ?: ""
            }
        }
        val a = mutableMapOf<String, Int>()
        doc.getElementsByTagName("string-array").let { n ->
            for (i in 0 until n.length) {
                val e = n.item(i) as Element
                a[e.getAttribute("name")] = e.getElementsByTagName("item").length
            }
        }
        return Res(s, a)
    }

    private val en get() = read("src/main/res/values/strings.xml")
    private val ja get() = read("src/main/res/values-ja/strings.xml")

    @Test fun everyStringExistsInBothLocales() {
        val e = en
        val j = ja
        assertEquals(
            "keys in the default locale with no Japanese",
            emptySet<String>(), e.strings.keys - j.strings.keys,
        )
        assertEquals(
            "Japanese keys the default locale no longer has",
            emptySet<String>(), j.strings.keys - e.strings.keys,
        )
        assertEquals(
            "arrays in the default locale with no Japanese",
            emptySet<String>(), e.arrays.keys - j.arrays.keys,
        )
    }

    /**
     * ARGUMENTS, NOT WORDS. Order may differ between languages — that is what
     * positional specifiers are for — so this compares the SET of arguments
     * each string consumes, which must be identical or `getString` throws.
     */
    @Test fun formatArgumentsAgree() {
        val e = en
        val j = ja
        val spec = Regex("""%(\d+)\$([a-zA-Z])""")
        fun argsOf(t: String) = spec.findAll(t).map { it.groupValues[1] + it.groupValues[2] }.toSet()
        val bad = e.strings.keys.intersect(j.strings.keys).mapNotNull { k ->
            val a = argsOf(e.strings.getValue(k))
            val b = argsOf(j.strings.getValue(k))
            if (a != b) "$k: default$a vs ja$b" else null
        }
        assertEquals("format specifiers must match exactly", emptyList<String>(), bad)
    }

    /**
     * An array of PRE-WRAPPED LINES is allowed to differ in length — kanji
     * carry a line's meaning in fewer cells, and forcing a matching count
     * would mean padding one locale with an empty row. What is not allowed is
     * an empty item, which draws as a blank line in the middle of a warning.
     */
    @Test fun disclaimerLinesAreAllNonEmpty() {
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder()
        listOf("src/main/res/values/strings.xml", "src/main/res/values-ja/strings.xml").forEach { p ->
            val arrays = doc.parse(File(p)).getElementsByTagName("string-array")
            for (i in 0 until arrays.length) {
                val e = arrays.item(i) as Element
                val items = e.getElementsByTagName("item")
                assertTrue("${e.getAttribute("name")} in $p is empty", items.length > 0)
                for (k in 0 until items.length) {
                    assertTrue(
                        "${e.getAttribute("name")}[$k] in $p is blank",
                        (items.item(k).textContent ?: "").isNotBlank(),
                    )
                }
            }
        }
    }

    /**
     * A NOTICE HAS TO FIT THE BAND.
     *
     * The band is one head-locked line, sized once from a per-locale template
     * and never re-sized. Anything longer is cut, and until the band started
     * logging, cut silently — which is how the illegal-band warning came to
     * show a Japanese wearer that their radio was set to USA / CANADA and
     * nothing at all about where they were standing.
     *
     * The Japanese band is 30 cells where the English one is 45. That is not a
     * smaller band: kanji are set 1.5x larger so they can be read at all, so
     * the same strip of the world holds fewer of them. A translation that is
     * the same length as its English source is therefore too long by half, and
     * the only place that can be caught before a wearer sees it is here.
     *
     * Arguments are filled with a plausible worst case — a fourteen-cell name,
     * a three-digit count — because a notice is only ever seen filled in.
     */
    @Test fun everyNoticeFitsTheBandInBothLocales() {
        // THE BAND'S OWN TEMPLATES, read from the band. Copying them here
        // would make this test pass on the day one of them changed, which is
        // the day it would matter.
        val enBand = TypeTier.displayCells(Notice.WIDEST)
        val jaBand = TypeTier.displayCells(Notice.WIDEST_JA)
        fun fill(t: String) = t
            .replace(Regex("%\\d+[$]s"), "MMMMMMMMMMMMMM")
            .replace(Regex("%\\d+[$]d"), "999")
        val over = mutableListOf<String>()
        listOf(Triple("default", en, enBand), Triple("ja", ja, jaBand)).forEach { (label, res, band) ->
            res.strings.filterKeys { it.startsWith("n_") }.forEach { (k, v) ->
                val w = TypeTier.displayCells(fill(v))
                if (w > band) over += "$label/$k is $w cells, band is $band: ${fill(v)}"
            }
        }
        assertEquals("notices wider than the band they are shown in", emptyList<String>(), over)
    }

    /**
     * AND EVERY OTHER FIXED-WIDTH SURFACE.
     *
     * The band was the first of these to be measured and the first to be found
     * cutting a warning in half. The rest of the app's fixed vocabularies sit
     * on plates sized once from a template, and every one of them has the same
     * failure mode and the same silence: the crown's verbs, the dock's
     * captions, the help card's rows.
     *
     * They all pass today. That is the point of writing it down — the check
     * costs nothing and the next translation to arrive is the one that would
     * have gone over.
     */
    @Test fun everyFixedVocabularyFitsItsPlate() {
        val over = mutableListOf<String>()
        fun check(what: String, prefix: String, enPlate: String, jaPlate: String) {
            val e = en
            val j = ja
            e.strings.keys.filter { it.startsWith(prefix) }.forEach { k ->
                listOf("default" to (e.strings[k] to enPlate), "ja" to (j.strings[k] to jaPlate))
                    .forEach { (loc, pair) ->
                        val (text, plate) = pair
                        if (text == null) return@forEach
                        val w = TypeTier.displayCells(text)
                        val b = TypeTier.displayCells(plate)
                        if (w > b) over += "$loc/$k on $what is $w cells of $b: $text"
                    }
            }
        }
        check("the crown", "a_", Crown.WIDEST, Crown.WIDEST)
        check("the dock", "d_", Dock.CAPTION_WIDEST, Dock.CAPTION_WIDEST_JA)
        assertEquals("words wider than the surface that holds them", emptyList<String>(), over)
    }

    /**
     * THE MESSAGE LINE, WITH THE WORST CASE IN EVERY SLOT.
     *
     * `name + when-or-what` on a 26-cell head panel. This is the check that
     * was missing when delivery marks were added: they were appended AFTER the
     * timestamp, which came to 38 cells in English and 33 in Japanese, and a
     * panel sized once clips from the end — so the mark was the first thing
     * lost, on the line that exists to carry it.
     *
     * The name column is 15 by construction (`WHO_COLUMN`), so the only free
     * variable is what follows it, and the widest of those is what this
     * measures.
     */
    @Test fun theMessageLineFitsItsPanelWithADeliveryMark() {
        val plate = TypeTier.displayCells(THREAD_HEAD)
        val over = mutableListOf<String>()
        listOf("default" to en, "ja" to ja).forEach { (loc, res) ->
            val tails = res.strings.filterKeys {
                it.startsWith("dm_") || it.startsWith("ago_")
            }.map { (k, v) -> k to v.replace(Regex("""%\d+[$]d"""), "99") }
            tails.forEach { (k, tail) ->
                val w = NAME_COLUMN + TypeTier.displayCells(tail)
                if (w > plate) over += "$loc/$k makes the line $w cells of $plate: '$tail'"
            }
        }
        assertEquals("message lines wider than the panel", emptyList<String>(), over)
    }

    /**
     * EVERY KEY IS READ BY SOMETHING.
     *
     * Scans the sources for `R.string.x`, `R.array.x` and `@string/x`. A key
     * reached only through a function that nothing calls still counts here —
     * this test cannot see a call graph — so it catches the cheap case, which
     * is also the common one: a string written for a surface that changed
     * shape before it shipped.
     */
    @Test fun noStringIsWrittenForNobody() {
        val used = mutableSetOf<String>()
        val fromCode = Regex("""R\.(?:string|array)\.([A-Za-z0-9_]+)""")
        val fromXml = Regex("""@(?:string|array)/([A-Za-z0-9_]+)""")
        listOf("src/main/java", "src/main/res", "src/main/AndroidManifest.xml").forEach { root ->
            File(root).walkTopDown().filter { it.isFile }.forEach { f ->
                if (f.extension in listOf("kt", "java", "xml")) {
                    val t = f.readText()
                    fromCode.findAll(t).forEach { used += it.groupValues[1] }
                    fromXml.findAll(t).forEach { used += it.groupValues[1] }
                }
            }
        }
        val e = en
        val dead = (e.strings.keys + e.arrays.keys).filter { it !in used }.sorted()
        assertEquals("strings nothing reads", emptyList<String>(), dead)
    }
}
