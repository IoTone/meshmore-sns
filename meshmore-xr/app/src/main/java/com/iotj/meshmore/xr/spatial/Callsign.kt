// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import java.text.Normalizer

/**
 * CALLSIGNS ARE USER-SUPPLIED TEXT, AND USERS ARE NOT REASONABLE.
 *
 * A MeshCore node name is whatever somebody typed into a companion app. Real
 * ones on public meshes look like `🐢 turtle relay`, `ＫＡＮＡＫＯ`, `Ökonomy`,
 * `davi1 🚀🚀🚀`, or a name that is nothing but emoji. Our labels are drawn with
 * a 4x6 stroke font (Glyphs), which has letters, digits and a few marks and
 * nothing else -- so every one of those inputs is a failure mode:
 *
 *   * an emoji is a SUPPLEMENTARY code point, two Java chars. Walking a String
 *     char by char splits the surrogate pair and emits two blanks, and any
 *     length or truncation logic counts it as two characters.
 *   * a fullwidth or accented letter is drawable in principle -- ＡＢＣ is ABC
 *     and Ökonomy is OKONOMY -- but only after normalisation.
 *   * kana and kanji are genuinely not drawable here, and silently dropping
 *     them turns two different nodes into the same empty label. That is worse
 *     than admitting we cannot draw them.
 *
 * So: normalise (NFKD folds fullwidth and splits accents off their bases),
 * classify each code point, and produce something honest.
 *
 *   drawable letter/digit/mark  ->  kept, uppercased
 *   accent / control / joiner   ->  dropped silently, they carry no identity
 *   pictograph (emoji, symbol)  ->  dropped from the TEXT, raised as a BADGE
 *   any other letter (CJK, ...) ->  TOFU box, one per code point
 *
 * The badge is the point of the emoji path: we cannot draw a turtle in a stroke
 * font, but we can say "this name had a picture in it" with a mark that belongs
 * to the symbology, and keep the readable part readable. Callsigns whose entire
 * name is pictographs fall back to a short stable hash, so they still differ
 * from one another on the horizon.
 *
 * Latin-only output is deliberate and matches MeshmoreXR-i18n-ja.md: callsigns
 * stay Latin in every locale, and Japanese UI text goes through a different
 * surface with a real font behind it.
 */
object Callsign {

    data class Rendered(
        /** Drawable, uppercased, already truncated. Never empty. */
        val text: String,
        /** The name carried emoji/pictographs -- draw the badge. */
        val badge: Boolean,
        /** How many code points became tofu; a legibility warning, not an error. */
        val tofu: Int,
        /** True if [text] was cut to fit. */
        val truncated: Boolean,
    )

    /**
     * Above this the label stops being a callsign and becomes a paragraph
     * floating in the room. At ~1.3 deg per glyph a 14-glyph label already
     * spans about 18 deg of a 61 deg FOV.
     */
    const val MAX_GLYPHS = 14

    fun render(raw: String, maxGlyphs: Int = MAX_GLYPHS): Rendered {
        // NFKD, not NFKC: we WANT accents split off their base letters so the
        // base survives and the combining mark can be dropped. NFKC would keep
        // 'Ö' as one undrawable code point.
        val folded = runCatching { Normalizer.normalize(raw, Normalizer.Form.NFKD) }.getOrDefault(raw)

        val sb = StringBuilder()
        var badge = false
        var tofu = 0
        var i = 0
        while (i < folded.length) {
            val cp = folded.codePointAt(i)
            i += Character.charCount(cp)
            when {
                isPictograph(cp) -> badge = true
                isIgnorable(cp) -> Unit
                cp == ' '.code -> if (sb.isNotEmpty() && sb.last() != ' ') sb.append(' ')
                else -> {
                    // uppercase() can widen a single code point (ß -> SS), so
                    // accept it only if EVERY resulting char is drawable.
                    val up = String(Character.toChars(cp)).uppercase()
                    if (up.isNotEmpty() && up.all(Glyphs::has)) sb.append(up)
                    else { sb.append(TOFU); tofu++ }
                }
            }
        }

        var text = sb.toString().trim()
        val truncated = text.length > maxGlyphs
        if (truncated) text = text.take(maxGlyphs - 1).trimEnd() + ELLIPSIS

        // A name made entirely of emoji is common and must still be
        // distinguishable from the next one, so fall back to a stable short id
        // rather than a shared placeholder.
        if (text.isEmpty()) text = "#%04X".format(raw.hashCode() and 0xFFFF)

        return Rendered(text, badge, tofu, truncated)
    }

    /** The box we draw when a code point is a real letter we cannot render. */
    const val TOFU = '□'
    const val ELLIPSIS = '…'

    /**
     * Emoji and decorative symbols. Deliberately broad: a false positive costs
     * a badge instead of a tofu box, which is the better way to be wrong.
     */
    private fun isPictograph(cp: Int): Boolean = when (cp) {
        // Misc symbols, dingbats, arrows, geometric/decorative blocks
        in 0x2190..0x21FF, in 0x2300..0x23FF, in 0x25A0..0x27BF -> cp != TOFU.code
        in 0x2B00..0x2BFF, in 0x2900..0x297F -> true
        // Supplementary planes: emoji, pictographs, playing cards, symbols
        in 0x1F000..0x1FAFF -> true
        0x00A9, 0x00AE, 0x203C, 0x2049, 0x2122, 0x2139 -> true
        else -> false
    }

    /** Carries no identity: accents (already split by NFKD), joiners, controls. */
    private fun isIgnorable(cp: Int): Boolean =
        Character.getType(cp).let {
            it == Character.NON_SPACING_MARK.toInt() ||
                it == Character.ENCLOSING_MARK.toInt() ||
                it == Character.COMBINING_SPACING_MARK.toInt() ||
                it == Character.FORMAT.toInt() ||
                it == Character.CONTROL.toInt()
        } || cp == 0x200D || cp in 0xFE00..0xFE0F
}
