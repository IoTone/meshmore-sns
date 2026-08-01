// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import java.text.BreakIterator
import java.util.Locale

/**
 * T3 — WHAT YOU MAY DO TO A RUN, AND WHERE IT MAY BREAK.
 *
 * MeshmoreXR-typography.md §7. Four of these are prohibitions, and prohibitions
 * are the hard kind to enforce because nothing looks wrong at the call site:
 * `text.uppercase()` is correct on every Latin string anyone will test with, and
 * silently mangles a Japanese one. So the rules live here as functions the
 * renderer asks, rather than as advice in a document nobody re-reads.
 *
 * DELIBERATELY PURE — java.text only, no Android. Line breaking is the part most
 * likely to be subtly wrong, and it needs no hardware to exercise.
 */
object TypeRules {

    /**
     * May this run be uppercased?
     *
     * NO if it contains any CJK. `upperHeadings` is a Latin device; applied to a
     * mixed run it leaves the kana untouched and shouts the Latin half, so
     * `ridge-2 の中継局` becomes `RIDGE-2 の中継局` — two registers in one line,
     * which reads as a rendering fault rather than as emphasis.
     *
     * Tier S is exempt from the question entirely: it uppercases because its
     * font has no lowercase, and it never receives CJK because the router sent
     * it elsewhere.
     */
    fun mayUppercase(text: String): Boolean = !hasCjk(text)

    /**
     * May this run be letter-spaced?
     *
     * NO if it contains any CJK. Tracking is a Latin device. CJK is set on an em
     * grid and the grid IS the rhythm; adding space between ideographs does not
     * open the line up, it breaks the thing that made it readable.
     */
    fun mayTrack(text: String): Boolean = !hasCjk(text)

    /**
     * May a synthetic bold or italic be applied?
     *
     * NO if it contains any CJK. Synthetic bold smears a glyph sideways and
     * synthetic italic shears it; both are tolerable on a Latin letter with few
     * strokes and destroy a kanji, whose legibility at these sizes depends on
     * strokes staying separate. Use the face's own weight axis or nothing.
     */
    fun maySynthesiseWeight(text: String): Boolean = !hasCjk(text)

    /**
     * Longest line, in display cells.
     *
     * A CJK line is capped at half the Latin one because its cells are twice as
     * wide: both limits are the same physical length, which is what the eye
     * actually cares about. Beyond ~25 degrees of traverse the reader loses the
     * start of the line while finding the end of it.
     */
    fun maxCellsPerLine(text: String): Int = if (hasCjk(text)) CJK_LINE_CELLS else LATIN_LINE_CELLS

    /**
     * Break [text] into lines of at most [maxCells] display cells.
     *
     * NEVER ON WIDTH ALONE, which is the entire point. Japanese has no spaces,
     * so a naive width break lands mid-word — and worse, lands in the places
     * kinsoku exists to forbid: a line may not START with a closing bracket or a
     * full stop (they would hang orphaned at the left margin) and may not END
     * with an opening bracket (it would dangle). BreakIterator supplies the
     * legal opportunities; the kinsoku pass then rejects the ones that are legal
     * but ugly.
     */
    fun wrap(text: String, maxCells: Int = maxCellsPerLine(text)): List<String> {
        if (text.isEmpty()) return listOf("")
        if (TypeTier.displayCells(text) <= maxCells) return listOf(text)

        val it = BreakIterator.getLineInstance(Locale.JAPANESE)
        it.setText(text)
        // Every position the language says a line MAY end.
        val stops = ArrayList<Int>()
        var b = it.first()
        while (b != BreakIterator.DONE) { stops.add(b); b = it.next() }

        val lines = ArrayList<String>()
        var start = 0
        while (start < text.length) {
            var best = -1
            for (stop in stops) {
                if (stop <= start) continue
                if (TypeTier.displayCells(text.substring(start, stop)) > maxCells) break
                if (kinsokuOk(text, start, stop)) best = stop
            }
            if (best <= start) {
                // No legal opportunity fits: a single unbreakable token longer
                // than the line. Cut on width rather than overflow — a URL that
                // runs off the side is worse than one that is visibly chopped —
                // but never inside a code point.
                best = hardCut(text, start, maxCells)
            }
            lines.add(text.substring(start, best).trim())
            start = best
            // Leading spaces belong to the break, not the next line.
            while (start < text.length && text[start] == ' ') start++
        }
        return lines
    }

    /**
     * Would breaking between [start,stop) and the rest violate kinsoku?
     *
     * Two rules, both about characters that must not be stranded: a line may not
     * end on an opener, and the next line may not begin with a closer.
     */
    fun kinsokuOk(text: String, start: Int, stop: Int): Boolean {
        if (stop <= start || stop > text.length) return false
        val last = text[stop - 1]
        if (last in NO_LINE_END) return false
        if (stop < text.length && text[stop] in NO_LINE_START) return false
        return true
    }

    /** Largest index > [start] whose slice still fits, never splitting a code point. */
    private fun hardCut(text: String, start: Int, maxCells: Int): Int {
        var i = start
        var cells = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            val w = TypeTier.displayCells(String(Character.toChars(cp)))
            if (cells + w > maxCells) break
            cells += w
            i += Character.charCount(cp)
        }
        // Always consume at least one code point, or the loop never terminates.
        return if (i > start) i else (start + Character.charCount(text.codePointAt(start)))
    }

    fun hasCjk(text: String): Boolean {
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            i += Character.charCount(cp)
            if (cp in 0x2E80..0x9FFF || cp in 0xF900..0xFAFF ||
                cp in 0xFF00..0xFF60 || cp in 0x20000..0x2FA1F
            ) return true
        }
        return false
    }

    /** 行頭禁則 — may not begin a line. Closers, and the small kana. */
    private const val NO_LINE_START = "。、，．・：；？！）〕］｝〉》」』】”’ゝゞーぁぃぅぇぉっゃゅょゎヵヶァィゥェォッャュョヮ%"

    /** 行末禁則 — may not end a line. Openers. */
    private const val NO_LINE_END = "（〔［｛〈《「『【“‘"

    /** §7: same physical length, expressed in each script's own cells. */
    const val LATIN_LINE_CELLS = 30
    const val CJK_LINE_CELLS = 15
}
