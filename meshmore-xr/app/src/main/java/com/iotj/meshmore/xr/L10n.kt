// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.content.Context

/**
 * JAPANESE IS A LAUNCH LANGUAGE, and it is not a translation pass — it is a
 * SIZE. `MeshmoreXR-i18n-ja.md` §1: the 1.2° legibility floor is derived from
 * Latin letterforms at 2–4 strokes a glyph; a kanji carries fourteen strokes in
 * the same box and needs 1.8°. The floor scales with stroke density, so a
 * Japanese UI is physically larger than the same UI in English, and layouts are
 * designed at the JA size and allowed to look airy in EN — never the reverse.
 *
 * ## What this object is
 *
 * The three locale-dependent decisions, in one place, resolved ONCE at boot:
 *
 *  - [wrap]: the context every surface is built from. Android resources do the
 *    string fallback (ja → default) for free; the wrap exists so `--es lang ja`
 *    can force it on an English device, because a device test must not require
 *    changing the glasses' system language.
 *  - [cap]: the angular promotion. 1.8°/1.2° = ×1.5 on any Latin-derived cap
 *    height. Promotes, never demotes — a surface asking for its Latin cap in
 *    Japanese GETS the kanji floor, because the request is a floor request.
 *  - [cells]: the width consequence. A promoted cap on the same plate leaves
 *    fewer cells: budget ÷ 1.5, and CJK glyphs already count 2 cells each in
 *    [spatial.TypeTier.displayCells], so existing clip arithmetic holds.
 *
 * ## What never goes through here
 *
 * Callsigns, units and protocol tokens stay Latin in every locale (spec §5):
 * they are identifiers on the wire, and `-71dBm` transliterated helps nobody.
 * The stroke font ([spatial.Glyphs]) cannot draw CJK and is not asked to — all
 * localised text rides the TextView paths (TextRun panels, Compose), where
 * NotoSansCJK is present on both target devices (verified 2026-08-14).
 */
object L10n {

    /** `--es lang ja` — a test override, resolved by [wrap], never persisted. */
    var override: String? = null

    /**
     * True once [wrap] has resolved to Japanese, by device locale or override.
     *
     * A plain field rather than a live lookup so the JVM unit tests, which have
     * no Android Context, exercise the EN geometry by default and can set this
     * directly to pin the JA geometry.
     */
    var ja: Boolean = false

    /**
     * The context surfaces are built from. Call once, early, and pass the
     * result everywhere a ctx goes — a surface built from the raw context in a
     * ja-forced run would come out English and nobody would know why.
     */
    fun wrap(ctx: Context): Context {
        val wrapped = override?.let {
            val cfg = android.content.res.Configuration(ctx.resources.configuration)
            cfg.setLocale(java.util.Locale.forLanguageTag(it))
            ctx.createConfigurationContext(cfg)
        } ?: ctx
        ja = wrapped.resources.configuration.locales.get(0)?.language == "ja"
        return wrapped
    }

    /**
     * The kanji floor, applied. ×1.5 is 1.2° → 1.8° (spec §1) carried through
     * whatever Latin-derived cap the surface uses; a 1.3° house cap lands at
     * 1.95°, just over the floor, which is the right side to miss on.
     */
    fun cap(latinCap: Float): Float = if (ja) latinCap * KANJI_PROMOTE else latinCap

    /** The same promotion's cost in width: fewer cells on the same plate. */
    fun cells(latinBudget: Int): Int =
        if (ja) (latinBudget / KANJI_PROMOTE).toInt() else latinBudget

    /**
     * HOW WIDE A STRING ACTUALLY DRAWS, in half-cells.
     *
     * `String.length` counts code units, which is the wrong ruler for a row
     * that lines a value up beside a name: 周波数 is three code units and
     * draws as wide as six Latin characters. Rows measured with `length`
     * therefore believe a kanji label is tiny, hand it most of the plate, and
     * push the value off the end — which is the overflow already photographed
     * once on the APP bay, waiting to happen again in the locale nobody reads
     * the screenshots of.
     *
     * A Latin character is one half-cell; anything in the CJK ranges (kanji,
     * kana, fullwidth forms) is two. That is the same model the templates
     * were measured against — ROW_WIDEST is 28 Latin characters, ROW_WIDEST_JA
     * is 13 kanji, and 13 x 2 = 26 is the same plate to within a character.
     */
    fun width(s: String): Int = s.sumOf { c -> if (isWide(c)) 2 else 1 }

    /** True for the blocks that draw fullwidth. Ranges, not a table. */
    fun isWide(c: Char): Boolean = c.code.let { u ->
        (u in 0x1100..0x115F) ||        // hangul jamo
            (u in 0x2E80..0x303E) ||    // CJK radicals, kangxi, punctuation
            (u in 0x3041..0x33FF) ||    // kana, compatibility, squared forms
            (u in 0x3400..0x4DBF) ||    // CJK ext A
            (u in 0x4E00..0x9FFF) ||    // CJK unified
            (u in 0xA000..0xA4CF) ||    // yi
            (u in 0xF900..0xFAFF) ||    // compatibility ideographs
            (u in 0xFE30..0xFE6F) ||    // compatibility forms
            (u in 0xFF00..0xFF60) ||    // fullwidth forms
            (u in 0xFFE0..0xFFE6)
    }

    /**
     * Pick a sizing template per locale. Reusable panels are sized ONCE from
     * their template, so a JA surface must be sized from a JA-widest string —
     * a panel sized for M's and filled with kanji at a promoted cap clips.
     */
    fun tpl(latin: String, japanese: String): String = if (ja) japanese else latin

    const val KANJI_PROMOTE = 1.5f
}
