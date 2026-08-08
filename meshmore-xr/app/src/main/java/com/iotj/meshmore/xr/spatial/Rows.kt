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

/** The longest row any bay may render. Everything below is measured against it. */
internal const val ROW_WIDEST = "PUBLIC  PORTLAND METRO  999+  SPEAKS"

/** The longest title, and the longest footer. Same reasoning, different panels. */
internal const val ROW_HEAD_WIDEST = "APP — CONNECTION: DISCONNECTED"
internal const val ROW_NOTE_WIDEST = "PICK AGAIN TO ALLOW CHANNEL SEND"

/** Longest channel name that fits [ROW_WIDEST]. */
internal const val CHAN_NAME_MAX = 14

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
    return buildString {
        if (mark) append("PUBLIC  ")
        append(n)
        append("  ").append(c)
        if (speaking) append("  SPEAKS")
    }
}

/** Longest setting name that fits [ROW_WIDEST] beside its state word. */
internal const val SETTING_NAME_MAX = 26

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
