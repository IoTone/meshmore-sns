// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The manual's parser, exercised without an asset manager or a headset.
 *
 * The documents are upstream snapshots — protocol.md is 724 lines of hex
 * tables and command names — so most of these tests are about NOT mangling
 * something that only looks like markdown.
 */
class DocsTest {

    private fun kinds(md: String) = Docs.parse(md).map { it.kind }
    private fun texts(md: String) = Docs.parse(md).map { it.text }

    @Test fun headingsAreRankedNotFlattened() {
        assertEquals(
            listOf(Docs.Kind.H1, Docs.Kind.H2, Docs.Kind.H3),
            kinds("# One\n## Two\n### Three"),
        )
        assertEquals(listOf("One", "Two", "Three"), texts("# One\n## Two\n### Three"))
    }

    @Test fun bulletsAndNumbersBothBecomeBullets() {
        assertEquals(
            listOf(Docs.Kind.BULLET, Docs.Kind.BULLET, Docs.Kind.BULLET),
            kinds("- a\n* b\n1. c"),
        )
        assertEquals(listOf("a", "b", "c"), texts("- a\n* b\n1. c"))
    }

    @Test fun inlineMarkersAreStrippedRatherThanShown() {
        assertEquals(listOf("bold word"), texts("**bold** word"))
        assertEquals(listOf("a code thing"), texts("a `code` thing"))
        assertEquals(listOf("an italic run"), texts("an *italic* run"))
        assertEquals(listOf("see the wiki"), texts("see [the wiki](https://example.com)"))
    }

    /**
     * THE ONE THAT MATTERS FOR protocol.md. Inside a fence, a leading '#' is a
     * comment and a leading '-' is a minus sign — re-read as markdown they
     * become a heading and a bullet, and the frame layout turns into prose.
     */
    @Test fun fencedCodeIsNotReinterpreted() {
        val md = "before\n```\n# CMD_APP_START\n- 0x01\n| a | b |\n```\nafter"
        val ls = Docs.parse(md)
        val code = ls.filter { it.kind == Docs.Kind.CODE }.map { it.text }
        assertEquals(listOf("# CMD_APP_START", "- 0x01", "| a | b |"), code)
        assertTrue("the fence markers are not lines", ls.none { it.text.startsWith("```") })
    }

    /** A table only lines up in monospace; re-wrapped as a sentence it is noise. */
    @Test fun tableRowsAreTreatedAsCode() {
        assertEquals(listOf(Docs.Kind.CODE), kinds("| cmd | value |"))
    }

    @Test fun quotesKeepTheirOwnKind() {
        assertEquals(listOf(Docs.Kind.QUOTE), kinds("> a note"))
        assertEquals(listOf("a note"), texts("> a note"))
    }

    @Test fun horizontalRulesAreRules() {
        assertEquals(listOf(Docs.Kind.RULE), kinds("---"))
    }

    /** Markdown is full of structural blanks; three in a row reads as the end. */
    @Test fun runsOfBlankLinesCollapseToOne() {
        assertEquals(
            listOf(Docs.Kind.BODY, Docs.Kind.BLANK, Docs.Kind.BODY),
            kinds("a\n\n\n\nb"),
        )
    }

    @Test fun leadingAndTrailingBlanksAreDropped() {
        assertEquals(listOf(Docs.Kind.BODY), kinds("\n\na\n\n\n"))
    }

    @Test fun theTitleIsTheFirstTopLevelHeading() {
        assertEquals("MeshmoreXR", Docs.titleOf(Docs.parse("# MeshmoreXR\n## Later")))
        assertEquals(null, Docs.titleOf(Docs.parse("no headings here")))
    }

    @Test fun anEmptyDocumentIsEmptyRatherThanBroken() {
        assertTrue(Docs.parse("").isEmpty())
        assertTrue(Docs.parse("\n\n\n").isEmpty())
    }

    @Test fun everySectionNamesADistinctBundledAsset() {
        val assets = Docs.Section.entries.map { it.asset }
        assertEquals(assets.size, assets.toSet().size)
        assertTrue(assets.all { it.startsWith("docs/") && it.endsWith(".md") })
    }

    // ---- the documents this build actually ships ---------------------------

    /**
     * PARSED FROM THE REAL FILES, not from a fixture. A parser that is correct
     * about invented markdown and wrong about the 724-line protocol snapshot
     * has tested nothing that ships.
     */
    private fun bundled(name: String): String =
        java.io.File("src/main/assets/docs/$name").readText()

    @Test fun everyBundledDocumentParsesIntoSomething() {
        Docs.Section.entries.forEach { sec ->
            val text = bundled(sec.asset.removePrefix("docs/"))
            val lines = Docs.parse(text)
            assertTrue("${sec.name} produced no lines", lines.size > 20)
            // A HEADING OF SOME RANK, not necessarily H1. The upstream
            // protocol snapshot opens at H2 ("## Moved") and has no H1 at all,
            // which is a fact about the document rather than a parser fault —
            // the first version of this assertion failed on the real file and
            // was wrong, not the parser.
            assertTrue(
                "${sec.name} has no heading",
                lines.any { it.kind == Docs.Kind.H1 || it.kind == Docs.Kind.H2 },
            )
            // Nothing may survive as a raw fence or a stray inline marker.
            assertTrue(
                "${sec.name} leaked a code fence",
                lines.none { it.text.trim().startsWith("```") },
            )
            assertTrue(
                "${sec.name} leaked bold markers",
                lines.filter { it.kind != Docs.Kind.CODE }.none { "**" in it.text },
            )
        }
    }

    @Test fun theAppGuideNamesThisApp() {
        assertEquals("MeshmoreXR", Docs.titleOf(Docs.parse(bundled("app.md"))))
    }
}
