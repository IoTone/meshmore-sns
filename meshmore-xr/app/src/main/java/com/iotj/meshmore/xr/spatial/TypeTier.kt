// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

/**
 * WHICH MACHINERY DRAWS THIS STRING — T1 of MeshmoreXR-typography.md.
 *
 * The app has two ways of putting text in the room and they are good at
 * opposite things:
 *
 *   S — STROKE   extruded segment geometry (Glyphs). Latin caps, digits, a few
 *                marks. Genuine volume, welded to a 3D object, and the reason
 *                the horizon reads as Wipeout rather than as a HUD overlay.
 *                Cannot draw anything outside its 4x6 stroke font.
 *
 *   R — RUN      a real font, rasterised by the platform. All of Unicode,
 *                including CJK, accents and emoji, via Android's own fallback
 *                chain. No volume; it is ink on a transparent ground.
 *
 * Until now there was no router, only Callsign.render() — which took ANY string
 * and forced it into tier S, folding what it could and drawing tofu boxes for
 * the rest. That is correct behaviour for a stroke font and the wrong behaviour
 * for the app: `中継局` became three boxes not because we cannot render it but
 * because we never asked whether something else should.
 *
 * This is that question, asked once, in one place. Callsign keeps its folding
 * and its tofu, but only for strings that are going to tier S — where a tofu box
 * is an honest report from a stroke font, not a failure of the product.
 *
 * DELIBERATELY PURE. No session, no Android, no rendering. The routing rule is
 * the part most likely to be wrong and the part that needs no hardware to
 * exercise — the same reason MeshNodes takes no session.
 */
object TypeTier {

    enum class Tier {
        /** Extruded stroke geometry. Latin, welded to a thing in the room. */
        STROKE,

        /** A real font on a transparent ground. Anything carrying language. */
        RUN,

        /**
         * Compose on a panel. Developer surfaces and the system IME ONLY.
         * Never routed to automatically; a caller has to ask for it by name.
         */
        PANEL,
    }

    /**
     * What tier S can actually draw, as a set rather than as a font lookup.
     *
     * Kept here rather than deferred to Glyphs.has() on purpose: routing must be
     * decidable without touching the renderer, so the rule can be tested and so
     * a future stroke-font addition is a deliberate change to this line rather
     * than a silent shift in what gets routed where.
     */
    private const val STROKE_SET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .-_/:?#*+!(),'="

    /**
     * Above this a stroke label stops being a label bound to an object and
     * becomes a paragraph floating in the room, so it goes to tier R where
     * proportional type and line breaking exist.
     */
    const val STROKE_MAX_CELLS = 16

    /**
     * Width of ONE CELL as a fraction of cap height, per tier. Measured on the
     * device, not derived — see TextRun's calibration check, which shouts if the
     * face ever stops agreeing with these.
     *
     *   STROKE  Glyphs advances 5.6 units on a 6-unit cap: 0.933 exactly.
     *   RUN     M PLUS 1 Code measured 0.6792 on device, identical across six
     *           runs of different lengths and scripts.
     *
     * That second number is a good sanity check on the whole approach: M PLUS
     * has a 0.730 em cap, so 0.6792 x 0.730 = 0.496 em of advance — half-width
     * to within half a percent, which is exactly what a monospaced CJK face is
     * supposed to be. The measurement agrees with the face's own design, so the
     * constant is describing something real rather than curve-fitting.
     *
     * It also moved a long way from the platform monospace it replaced (0.835),
     * which is the argument for shipping a face rather than borrowing one: the
     * layout was budgeting 23% too much width for every run.
     */
    const val STROKE_CELL_EM = 0.933f
    const val RUN_CELL_EM = 0.679f

    /** Cell width as a fraction of cap height for whatever tier [text] takes. */
    fun cellEm(text: String, kind: Kind = Kind.NAME): Float =
        if (of(text, kind) == Tier.STROKE) STROKE_CELL_EM else RUN_CELL_EM

    /**
     * What a string IS, which decides how it is drawn.
     *
     * The distinction that matters turned out not to be "bound to an object"
     * but WORDS VERSUS MARKS. On the live ring a proportional mixed-case name
     * sat beside an all-caps vector one and the two read as different
     * applications — but nobody minds that `042` on the compass and `FREQ` on
     * an encoder are vector strokes, because those are not words, they are
     * markings on an instrument.
     */
    enum class Kind {
        /**
         * A name, a message, a place — anything a person wrote or would read as
         * language. Always tier R: it may contain any script, and more
         * importantly all such text should look like each other.
         */
        NAME,

        /**
         * An instrument marking. A compass numeral, a rack legend, a unit, a
         * dock caption. Tier S where it can be, because extruded strokes are
         * the only text in this app with real volume — it is what makes the
         * horizon read as Wipeout rather than as a HUD overlay — and because a
         * hundred of these as panels would be a hundred Android Views.
         */
        MARK,
    }

    /**
     * Route [text].
     *
     * A NAME always takes the real font. A MARK takes strokes when the stroke
     * font can draw it and it is short enough to be a marking rather than a
     * sentence; anything else falls through to tier R, which can draw
     * everything.
     */
    fun of(text: String, kind: Kind = Kind.NAME): Tier {
        if (kind == Kind.NAME) return Tier.RUN
        // Anything outside the stroke set takes the real-font path. This is what
        // makes CJK, accents and emoji route themselves: no caller has to know,
        // and no caller can forget.
        if (!drawableAsStrokes(text)) return Tier.RUN
        if (cells(text) <= STROKE_MAX_CELLS) return Tier.STROKE
        return Tier.RUN
    }

    /** Compatibility shim for callers that still think in "bound to an object". */
    fun of(text: String, boundToObject: Boolean): Tier =
        of(text, if (boundToObject) Kind.MARK else Kind.NAME)

    /**
     * True when every code point is in the stroke set AFTER the folding Callsign
     * would apply.
     *
     * Folding first is what keeps `Ökonomy` and `ＡＢＣ` on the cheap path: both
     * are Latin that merely arrived decorated, and routing them to tier R over a
     * diacritic would cost a texture for no gain. Genuine non-Latin — kana,
     * kanji, emoji — survives folding and is routed out.
     */
    fun drawableAsStrokes(text: String): Boolean {
        if (text.isEmpty()) return true
        val folded = Callsign.render(text, maxGlyphs = Int.MAX_VALUE)
        // Callsign reports precisely the two conditions that mean "this string
        // contained something a stroke font cannot represent".
        if (folded.tofu > 0 || folded.badge) return false
        return folded.text.all { it in STROKE_SET }
    }

    /** Code points, not chars: an emoji is a surrogate pair and counts as one. */
    fun cells(text: String): Int = text.codePointCount(0, text.length)

    /**
     * Width in CELLS, where a full-width glyph counts two.
     *
     * A kanji is about twice as wide as a Latin letter at the same cap height —
     * that is what "full-width" means — so counting code points measures the
     * wrong thing the moment a name stops being Latin. `中継局` is three code
     * points and six cells wide, and a layout that believes the first number
     * reserves half the space the label needs.
     *
     * Everything downstream of this — the de-occlusion budget, the truncation
     * limit — is in these units, so both agree by construction.
     */
    fun displayCells(text: String): Int {
        var n = 0
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            i += Character.charCount(cp)
            n += cellsOf(cp)
        }
        return n
    }

    /**
     * Width of one code point in cells.
     *
     * EMOJI ARE THREE, NOT TWO, and that is a measurement rather than a guess.
     * They do not come from the body face at all -- no text font ships colour
     * emoji -- so they are drawn by the system emoji font at whatever advance IT
     * uses. Modelled as full-width (2 cells) the layout under-reserved, and the
     * calibration check caught it the moment M PLUS replaced the platform
     * monospace: '🐶🐾Woofy Repeater' measured 0.716 em/cell against 0.679
     * expected, which works out at ~1.24 em per emoji, or ~2.5 cells.
     *
     * Rounded UP. Over-reserving costs a little unused arc; under-reserving puts
     * a label through its neighbour, and the whole point of this number is that
     * the layout and the renderer agree.
     */
    fun cellsOf(cp: Int): Int = when {
        isEmoji(cp) -> 3
        isWide(cp) -> 2
        else -> 1
    }

    private fun isEmoji(cp: Int): Boolean = cp in 0x1F300..0x1FAFF || cp in 0x2600..0x27BF

    /**
     * The East Asian Wide and Fullwidth blocks, plus emoji, which render at
     * roughly square proportions in every fallback face we will meet.
     */
    private fun isWide(cp: Int): Boolean = when (cp) {
        in 0x1100..0x115F,   // Hangul Jamo
        in 0x2E80..0x303E,   // CJK radicals, Kangxi, punctuation
        in 0x3041..0x33FF,   // kana, Bopomofo, compatibility
        in 0x3400..0x4DBF,   // CJK ext A
        in 0x4E00..0x9FFF,   // CJK unified
        in 0xA000..0xA4CF,   // Yi
        in 0xAC00..0xD7A3,   // Hangul syllables
        in 0xF900..0xFAFF,   // CJK compatibility ideographs
        in 0xFE30..0xFE6F,   // CJK compatibility forms
        in 0xFF00..0xFF60,   // fullwidth forms
        in 0xFFE0..0xFFE6,
        in 0x1F300..0x1FAFF, // emoji — but see cellsOf: these are 3, not 2
        in 0x20000..0x2FA1F, // CJK ext B and beyond
        -> true
        else -> false
    }

    /**
     * Trim [text] to [maxCells] of display width, marking the cut.
     *
     * TIER R HAS TO BE CLIPPED TOO, and it was not. The stroke path capped
     * labels at Callsign.MAX_GLYPHS and tier R inherited no such limit, so the
     * first live run produced `RBP SENSE CAP REPEATER ` at 1.003 m wide — about
     * 23 degrees at its own range, against a horizon whose whole layout is built
     * on labels being a known size. Rendering the full name is not a kindness
     * when it prints through three of its neighbours.
     */
    fun clip(text: String, maxCells: Int): String {
        if (displayCells(text) <= maxCells) return text
        val sb = StringBuilder()
        var n = 0
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            // cellsOf, NOT a second copy of the width rule. This function had
            // its own `if (isWide) 2 else 1` and it silently disagreed with
            // displayCells the moment emoji became three cells: clip fitted
            // eight emoji into a budget displayCells then measured at 25. One
            // quantity, one implementation.
            val w = cellsOf(cp)
            // -1 leaves room for the ellipsis, which is itself one cell.
            if (n + w > maxCells - 1) break
            sb.appendCodePoint(cp)
            n += w
            i += Character.charCount(cp)
        }
        return sb.toString().trimEnd() + "\u2026"
    }
}
