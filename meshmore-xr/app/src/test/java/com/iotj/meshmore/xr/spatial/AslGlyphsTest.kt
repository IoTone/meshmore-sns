// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The generated hand shapes. Artwork is not usually worth testing, but this is
 * artwork produced by a script from a file fetched off the internet, and the
 * failure mode is silent: a glyph that extracted wrong still draws, it just
 * draws the wrong hand. These are the properties the generator promises.
 */
class AslGlyphsTest {

    private val expected =
        ('a'..'z').toList() + ('0'..'9').toList()

    @Test fun `every letter and digit is present`() {
        val missing = expected.filter { !AslGlyphs.has(it) }
        assertTrue("missing: $missing", missing.isEmpty())
        assertEquals(36, AslGlyphs.PATHS.size)
    }

    @Test fun `lookup is case insensitive`() {
        assertEquals(AslGlyphs['a'], AslGlyphs['A'])
        assertTrue(AslGlyphs.has('R'))
    }

    /**
     * Normalised into the authoring box, which is what lets AslIcon scale any
     * of them to a common optical size. A glyph outside it would be clipped or
     * drawn small with no obvious cause.
     */
    @Test fun `every glyph lies within the box`() {
        expected.forEach { ch ->
            val d = AslGlyphs[ch]!!
            val n = Regex("[-+]?\\d*\\.?\\d+").findAll(d).map { it.value.toFloat() }.toList()
            assertTrue("$ch is empty", n.isNotEmpty())
            val xs = n.filterIndexed { i, _ -> i % 2 == 0 }
            val ys = n.filterIndexed { i, _ -> i % 2 == 1 }
            assertTrue("$ch x out of box", xs.min() >= -1f && xs.max() <= AslGlyphs.BOX + 1f)
            assertTrue("$ch y out of box", ys.min() >= -1f && ys.max() <= AslGlyphs.BOX + 1f)
        }
    }

    /**
     * PathParser handles these; an arc would mean the generator hit something
     * it does not convert and quietly emitted it.
     */
    @Test fun `only the commands PathParser is given are used`() {
        expected.forEach { ch ->
            val cmds = AslGlyphs[ch]!!.filter { it.isLetter() }.toSet()
            assertTrue("$ch uses $cmds", cmds.all { it in "MLCQZ" })
        }
    }

    /**
     * Each shape fills one dimension of the box. A glyph that came out tiny
     * would be a normalisation that silently failed, and it would render as a
     * dot rather than as nothing — the kind of fault nobody reports.
     */
    @Test fun `every glyph fills the box in at least one axis`() {
        expected.forEach { ch ->
            val n = Regex("[-+]?\\d*\\.?\\d+").findAll(AslGlyphs[ch]!!)
                .map { it.value.toFloat() }.toList()
            val w = n.filterIndexed { i, _ -> i % 2 == 0 }.let { it.max() - it.min() }
            val h = n.filterIndexed { i, _ -> i % 2 == 1 }.let { it.max() - it.min() }
            assertTrue("$ch is ${w}x$h", maxOf(w, h) > AslGlyphs.BOX * 0.98f)
        }
    }

    /** The letters the gesture vocabulary actually binds today. */
    @Test fun `the bound letters are all drawable`() {
        listOf('a', 'b', 'h', 'r').forEach {
            assertTrue("$it has no artwork", AslGlyphs.has(it))
        }
    }
}
