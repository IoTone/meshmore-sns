// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.content.Context

/**
 * THE MANUAL, INSIDE THE APP AND AVAILABLE WITH EVERYTHING OFF.
 *
 * Meshmore SNS settled the shape and it is kept: **three sections** — the app's
 * own guide, the MeshCore companion-radio protocol, and the firmware README —
 * each with an offline snapshot bundled in the package. Somebody who knows the
 * phone app finds the same three things here.
 *
 * ## Two things differ, and both follow from the hardware
 *
 * **No remote refresh.** SNS re-fetches the upstream copies from GitHub when
 * it is online. This app's entire premise is that it works with no network at
 * all, and the online tier (S10 UPLINK) is not built. A doc that silently
 * needed the internet to be current would be the one surface that broke the
 * promise, so the bundled snapshot is the whole story and the reader says so.
 *
 * **A panel, not a spatial surface.** Almost everything in this app refuses to
 * be a flat panel on principle. Documentation is one of the three exceptions,
 * for the same reason the radio log and the alerts list are: a long scrolling
 * transcript is genuinely the right shape for reading, and the spatial version
 * would be worse. The protocol snapshot is 724 lines; at the 26-cell row budget
 * every other surface uses, it would be roughly nine hundred rows of stroke
 * geometry to page through one screenful at a time.
 *
 * The parsing is pure and lives here so it can be tested without an asset
 * manager, a display, or a headset.
 */
object Docs {

    /** The three, in SNS's order. */
    enum class Section(val asset: String) {
        APP("docs/app.md"),
        PROTOCOL("docs/protocol.md"),
        FIRMWARE("docs/firmware.md"),
    }

    /**
     * What a line is, which is all the styling a reader needs.
     *
     * Deliberately not a markdown tree. Nothing here nests, and a renderer that
     * only has to answer "how big and how bright" can be a dozen lines of
     * Compose rather than a parser with a rendering model attached.
     */
    enum class Kind { H1, H2, H3, BODY, BULLET, QUOTE, CODE, RULE, BLANK }

    data class Line(val kind: Kind, val text: String)

    /**
     * Markdown to lines.
     *
     * INLINE MARKERS ARE STRIPPED RATHER THAN RENDERED. `**bold**` in a
     * monospace reader at this size buys nothing and the asterisks are noise;
     * backticks around `CMD_APP_START` are removed for the same reason, since
     * the whole document is already set in one face.
     */
    fun parse(markdown: String): List<Line> {
        val out = mutableListOf<Line>()
        var inFence = false
        markdown.lineSequence().forEach { raw ->
            val line = raw.trimEnd()
            val t = line.trim()
            if (t.startsWith("```")) {
                // A FENCE IS A STATE, NOT A LINE. Everything between two of
                // them is code and must not be re-interpreted — protocol.md is
                // full of hex tables whose leading '#' and '-' would otherwise
                // become headings and bullets.
                inFence = !inFence
                return@forEach
            }
            if (inFence) { out += Line(Kind.CODE, line); return@forEach }
            when {
                t.isEmpty() -> out += Line(Kind.BLANK, "")
                t.startsWith("### ") -> out += Line(Kind.H3, clean(t.removePrefix("### ")))
                t.startsWith("## ") -> out += Line(Kind.H2, clean(t.removePrefix("## ")))
                t.startsWith("# ") -> out += Line(Kind.H1, clean(t.removePrefix("# ")))
                t.startsWith("> ") -> out += Line(Kind.QUOTE, clean(t.removePrefix("> ")))
                t == ">" -> out += Line(Kind.QUOTE, "")
                t.startsWith("- ") || t.startsWith("* ") ->
                    out += Line(Kind.BULLET, clean(t.drop(2)))
                NUMBERED.matches(t) ->
                    out += Line(Kind.BULLET, clean(t.substringAfter(". ")))
                t.all { it == '-' } && t.length >= 3 -> out += Line(Kind.RULE, "")
                // A TABLE ROW IS CODE, not prose. Its columns only line up in a
                // monospace face, and re-wrapped as a sentence it is gibberish.
                t.startsWith("|") -> out += Line(Kind.CODE, line)
                else -> out += Line(Kind.BODY, clean(t))
            }
        }
        return collapse(out)
    }

    private val NUMBERED = Regex("""^\d+\.\s+.*""")

    /** Inline markers removed; the reader has one face and one size per kind. */
    internal fun clean(s: String): String = s
        .replace(BOLD, "$1")
        .replace(ITALIC, "$1")
        .replace(TICK, "$1")
        .replace(LINK, "$1")
        .trim()

    private val BOLD = Regex("""\*\*(.+?)\*\*""")
    private val ITALIC = Regex("""(?<![*\w])\*([^*]+?)\*(?!\*)""")
    private val TICK = Regex("""`([^`]+?)`""")

    /** `[text](url)` keeps the text. A URL nobody can tap is not worth the room. */
    private val LINK = Regex("""\[([^\]]+)]\([^)]*\)""")

    /**
     * Runs of blank lines become one, and leading/trailing blanks go.
     *
     * Markdown uses blank lines structurally, so a faithful pass emits a lot of
     * them; three consecutive gaps in a reader look like the document ended.
     */
    private fun collapse(lines: List<Line>): List<Line> {
        val out = mutableListOf<Line>()
        lines.forEach { l ->
            if (l.kind == Kind.BLANK && (out.isEmpty() || out.last().kind == Kind.BLANK)) return@forEach
            out += l
        }
        while (out.isNotEmpty() && out.last().kind == Kind.BLANK) out.removeAt(out.size - 1)
        return out
    }

    /**
     * Read a bundled section.
     *
     * A missing or unreadable asset returns a one-line document saying so
     * rather than an empty one: a reader that opens on nothing is
     * indistinguishable from a reader that is broken, and this is the surface
     * somebody opens precisely when something else has already confused them.
     */
    fun load(context: Context, section: Section): List<Line> = runCatching {
        context.assets.open(section.asset).bufferedReader().use { it.readText() }
    }.map { parse(it) }
        .getOrElse { listOf(Line(Kind.BODY, "This document is not available in this build.")) }

    /** First heading in the document, for a hub row that names itself. */
    fun titleOf(lines: List<Line>): String? =
        lines.firstOrNull { it.kind == Kind.H1 }?.text
}
