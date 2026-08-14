// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

/**
 * THE WORDS ON A [Stack] ROW. Pure, at file scope, testable without a Session.
 *
 * ## Why the templates are constants and why they are checked
 *
 * [TextRun.reusable] sizes a panel ONCE, for the longest string it will ever
 * hold, and never resizes — a readout that re-measures itself jitters, and on
 * this SDK it also rebuilds an Android View every time a word changes. The
 * consequence is that a row longer than its template does not grow the panel,
 * it gets CLIPPED inside it, silently, at whatever character the box ends.
 *
 * On a headset that presents as a channel whose name trails off, or worse, a
 * row whose state is missing because a name ran long, and nothing anywhere says
 * why. So the templates are the contract, the builders below keep it, and
 * `RowsTest` asserts it for every worst case — channel names come off other
 * people's radios and are not under our control.
 *
 * ONE TEMPLATE FOR EVERY BAY. The stack is a shared primitive, so its rows are
 * sized once for the widest row ANY bay will show. A per-bay template would
 * mean a per-bay panel and the primitive would stop being one.
 */

/**
 * The longest row any bay may render — and it is bounded by the PLATE, not by
 * taste.
 *
 * This was 36 characters, which at the old 1.49-degree cap rendered a 63.6 cm
 * panel onto a 40 cm plate: **23.6 cm of text hanging off both ends of its own
 * button**, photographed on the glasses 2026-08-09. The template had been
 * checked against itself and never against the thing it sits on.
 *
 * The chain is: 28 cells x 0.679 em/cell x 0.0227 m cap = 43.2 cm of text
 * inside a 46 cm plate, which is 26 degrees at a metre and fits the field.
 * `RowsTest` now asserts that relationship rather than the template's own
 * length, because the length was never the point.
 */
internal const val ROW_WIDEST = "PUBLIC  PORTLAND METRO  999+"

/**
 * The same contracts at the KANJI floor. A JA row runs at 1.5x the cap
 * (L10n.cap), so the same plate holds ~13 full-width glyphs instead of 28
 * cells — these templates are what TextRun sizes a JA bay from, and what
 * fit() clips against. 設 is a mid-density kanji: a fair widest-glyph proxy.
 */
internal val ROW_WIDEST_JA = "設".repeat(13)
internal val ROW_HEAD_WIDEST_JA = "設".repeat(14)
internal val ROW_NOTE_WIDEST_JA = "設".repeat(15)

/** The longest title, and the longest footer. Same reasoning, different panels. */
internal const val ROW_HEAD_WIDEST = "APP — CONNECTION: DISCONNECTED"
internal const val ROW_NOTE_WIDEST = "PICK AGAIN TO ALLOW CHANNEL SEND"

/** Longest channel name that fits [ROW_WIDEST]. */
internal const val CHAN_NAME_MAX = 14

/** Metrics of the row, kept beside the template so the two cannot drift. */
internal const val ROW_CAP_M = 0.0227f
internal const val ROW_CELL_EM = 0.679f
internal const val ROW_PLATE_W = 0.46f

/**
 * ...and the two that the FOCUS BUMP multiplies, here for the same reason.
 *
 * They lived in [Stack]'s private companion, which meant the only arithmetic
 * that could be checked without a headset was the arithmetic about width — so
 * the width relationship got a test and the height relationship did not, and
 * when focus started scaling the plate as well as the run, nothing anywhere
 * could say whether a focused row still cleared the one below it. It does, by
 * 4.8 mm at the widest theme. That is a number somebody should have to see.
 */
internal const val ROW_PLATE_H = 0.062f
internal const val ROW_PITCH = 0.078f

/**
 * One channel row.
 *
 * Order is deliberate: the PUBLIC warning first, because it is the thing that
 * changes what a person is willing to say and it should not be at the end of a
 * line that might be clipped. The name next, because it is what you are looking
 * for. The count, because weight tells you which band is alive. SPEAKS last,
 * because it is the state the plate's own lighting already carries — the word
 * is the confirmation, not the signal.
 */
internal fun channelLabel(
    name: String,
    publicKey: Boolean,
    count: Int,
    speaking: Boolean,
): String {
    val n = name.trim().uppercase().let {
        // Truncated with a real ellipsis rather than a hard cut, so a clipped
        // name reads as clipped rather than as a channel somebody named badly.
        if (it.length <= CHAN_NAME_MAX) it else it.take(CHAN_NAME_MAX - 1) + "…"
    }.ifBlank { "UNNAMED" }
    // Counts saturate, AND SAY SO. A four-digit count would push the row past
    // the template and clip the SPEAKS off the end — losing the state to show
    // the traffic, which is the wrong trade.
    //
    // The first cut rendered 1234 as "999", which is not a truncation, it is a
    // wrong number: this is a public band that really does carry four figures
    // in an evening, so it would have been wrong on the busiest channel and
    // right nowhere. The plus costs one character of a template we control.
    val c = if (count > 999) "999+" else count.toString()
    // NOT TWICE. The stock MeshCore slot 0 is literally named "Public" and
    // carries the public PSK, so the marker and the name are the same word and
    // the row came out "PUBLIC  PUBLIC  1234" — which reads as a rendering
    // fault, and worse, teaches the eye to skim past the marker on every OTHER
    // row where it is the only warning there is.
    val mark = publicKey && !n.startsWith("PUBLIC")
    // SPEAKS IS GONE, and the plate says it instead.
    //
    // It was the confirmation rather than the signal — the lit plate already
    // carries "this channel reads itself aloud" — and it was eight characters
    // of a template that turned out to be eight characters too long. When a row
    // has to lose something, it loses the part that was already being said.
    return buildString {
        if (mark) append("PUBLIC  ")
        append(n)
        append("  ").append(c)
    }
}

/**
 * Longest setting name that fits [ROW_WIDEST] beside its state word.
 *
 * Eighteen, because the widest state word is `CONFIRM?` and it arrives with two
 * spaces: 18 + 2 + 8 = 28, the whole template.
 */
internal const val SETTING_NAME_MAX = 18

/**
 * One settings row.
 *
 * THE STATE WORD IS ALWAYS THERE, on and off alike. The plate's light already
 * says which, so a word that appears only when on would be redundant — except
 * that a row reading just "SHARE LOCATION" gives a reader no way to tell an
 * unlit plate from a plate that failed to light, and the difference between
 * "off" and "broken" is the whole question somebody is asking when they come
 * looking for this bay.
 *
 * [armed] is for the guarded rows. It replaces the state word entirely rather
 * than sitting next to it, because a half-pressed switch is not a state the
 * setting is IN, it is a question being asked.
 */
internal fun settingLabel(
    name: String,
    on: Boolean,
    armed: Boolean = false,
    onWord: String = "ON",
    offWord: String = "OFF",
): String {
    val n = name.trim().uppercase().let {
        if (it.length <= SETTING_NAME_MAX) it else it.take(SETTING_NAME_MAX - 1) + "…"
    }.ifBlank { "SETTING" }
    return n + "  " + if (armed) "CONFIRM?" else if (on) onWord else offWord
}

// --- S9 · radio configuration -----------------------------------------------

/**
 * One radio parameter, as a row.
 *
 * REPLACES THE RACK'S KNOBS, and the arithmetic is why. At the rack's reach of
 * 0.62 m its face is 39 degrees wide — wider than the 34-degree field — while
 * its knobs are 2.4 degrees across, barely above the 2-degree floor for
 * anything reached for. Too big and too small at the same time is what "too
 * many controls on one surface" looks like, and it cannot be fixed by moving
 * it: at 0.5 m the same face is 47 degrees.
 *
 * The crown met this exact shape and the answer was fewer, bigger targets at
 * pointing distance. A row is 46 cm x 6.2 cm at a metre — 26 x 3.6 degrees —
 * and its hit volume IS the plate.
 *
 * PENDING IS SHOWN, NOT SUBSTITUTED. A staged value that simply replaced the
 * live one would let somebody walk away believing the radio had changed. The
 * arrow is the whole point: what it is, and what it will be if you commit.
 */
internal fun radioRow(name: String, live: String, pending: String?): String {
    // THE NAME IS CLAMPED FIRST. Clamping only the value let a long parameter
    // name push the whole row past the plate — the same overflow that was
    // photographed on the APP bay, reintroduced by a function that checked the
    // half it happened to be thinking about.
    val n = name.trim().uppercase().let {
        if (it.length <= RADIO_NAME_MAX) it else it.take(RADIO_NAME_MAX - 1) + "\u2026"
    }
    val v = if (pending == null || pending == live) live else live + "\u2192" + pending
    val room = (ROW_WIDEST.length - n.length - 2).coerceAtLeast(1)
    return n + "  " + (if (v.length <= room) v else v.take(room))
}

/** Longest parameter name that leaves room for a value and a pending arrow. */
internal const val RADIO_NAME_MAX = 14

/**
 * One region, as a row in the region list.
 *
 * THE FREQUENCY IS PART OF THE ROW, not decoration. A region name is a claim
 * about a jurisdiction and the number is the thing you can actually check — a
 * wearer who knows they are on 868 can see at a glance that JAPAN is not it,
 * without picking anything to find out. It is also the only value that survives
 * into the header after the pick, so showing it here means the confirmation and
 * the choice are stated in the same terms.
 *
 * The name is NOT clamped to [RADIO_NAME_MAX] the way a parameter name is:
 * `AUSTRALIA SA/WA/QLD` is nineteen characters and a region name that ends in
 * an ellipsis is a region you cannot identify. It is the frequency that gives
 * way, and `RegionsTest` asserts that no shipped region ever needs it to.
 */
internal fun regionRow(label: String, freqMhz: Double): String {
    val n = label.trim().uppercase()
    val f = "%.3f".format(freqMhz)
    val room = (ROW_WIDEST.length - n.length - 2).coerceAtLeast(0)
    return if (room >= f.length) "$n  $f" else n.take(ROW_WIDEST.length)
}

/**
 * The radio bay's header.
 *
 * IT SAYS WHAT THE ROWS DO NOT. The first cut pasted the radio's whole live
 * string into the title — `910.525MHz BW62.5 SF7 4/5 22dBm` — which was four
 * values already spelled out on the four rows immediately below it, plus one
 * that was not: the transmit power. At 36 characters against a 30-character
 * panel it clipped, and what it clipped off the end was the `dBm`. The header
 * lost the only thing it was contributing and kept the duplicates.
 *
 * So the header carries the frequency and the power, and nothing else. Both
 * earn their place by being unreachable from the rows: FREQ moves only with a
 * PRESET (see `onRadioRow`), and TX POWER has no row at all. The rest is
 * directly below, in a form you can pick.
 *
 * IT STAYS LIVE WHILE EDITS ARE PENDING. The rows show `62.5→125`; the header
 * does not, because with seven rows over two pages the COMMIT row is on a page
 * where no parameter is visible, and the question being asked at that moment is
 * "what is this radio right now" — an anchor that quietly followed the staged
 * edits would answer a question nobody asked. The footer says PENDING.
 */
internal fun radioTitle(freqMhz: Double?, txDbm: Int?): String {
    if (freqMhz == null) return "RADIO — NOT READ YET"
    val p = if (txDbm == null) "" else "  %ddBm".format(txDbm)
    return "RADIO — %.3fMHz%s".format(freqMhz, p)
}
