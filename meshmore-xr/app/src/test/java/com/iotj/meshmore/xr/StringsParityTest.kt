// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
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
