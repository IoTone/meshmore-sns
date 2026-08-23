// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

/**
 * READING OTHER PEOPLE'S BOTS, WHICH MEASURE THIS RADIO FOR FREE.
 *
 * There are auto-responders on this mesh. They answer a message with the
 * quality of the packet they received, and two different ones were seen on
 * 2026-08-22 using the same shape:
 *
 *     @[BNHMobile], ack: SNR -3.5 dB, RSSI -116 dBm, 3 hops via 42, CA, 37
 *     @[TC T096 ZephCore], ack: SNR -1.2 dB, RSSI -109 dBm, 5 hops via 1A, 77, 79, 98, B9
 *     Path 10 hops SNR 0 dB RSSI -102 dBm
 *
 * WHY THIS IS WORTH PARSING RATHER THAN JUST DISPLAYING. Everything this app
 * knows about its own transmissions comes from one bit: an acknowledgement
 * arrived, or it did not. That says a message got there and nothing about how
 * close it came to not getting there — a packet heard at -116 dBm and one heard
 * at -80 dBm both ack, and only one of them is about to stop working.
 *
 * A bot's reply is the missing half. It is the FAR END's measurement of OUR
 * transmitter, which no amount of listening on this side can produce, and it
 * arrives as an ordinary direct message that the app was already receiving and
 * throwing away as text.
 *
 * The parse is deliberately loose about everything except the numbers. These
 * are other people's formats and they will change without telling anybody; a
 * strict grammar would go quietly blind the first time somebody reworded their
 * bot. Anything with a decibel figure attached to SNR or RSSI is worth keeping,
 * and everything else in the line is left alone.
 */
object SignalReport {

    /**
     * What the far end heard.
     *
     * Every field is optional because every bot reports a different subset,
     * and a report with one number in it is still a measurement this app could
     * not otherwise make.
     */
    data class Report(
        val snrDb: Double? = null,
        val rssiDbm: Int? = null,
        val hops: Int? = null,
        /** The relays it came through, as the bot named them. Not always given. */
        val via: List<String> = emptyList(),
    ) {
        val empty: Boolean get() = snrDb == null && rssiDbm == null && hops == null

        /**
         * One line for a notice band, shortest useful first.
         *
         * RSSI leads because it is the number that predicts failure: SNR moves
         * with the noise floor and a bad RSSI is bad everywhere.
         */
        fun line(): String = buildList {
            rssiDbm?.let { add("$it dBm") }
            snrDb?.let { add("%.1f dB".format(it)) }
            hops?.let { add("$it hop" + if (it == 1) "" else "s") }
        }.joinToString("  ")
    }

    private val RSSI = Regex("""RSSI\s*(-?\d+(?:\.\d+)?)\s*dBm""", RegexOption.IGNORE_CASE)
    private val SNR = Regex("""SNR\s*(-?\d+(?:\.\d+)?)\s*dB(?!m)""", RegexOption.IGNORE_CASE)
    private val HOPS = Regex("""(\d+)\s*hops?""", RegexOption.IGNORE_CASE)
    private val VIA = Regex("""via\s+([0-9A-Fa-f]{1,2}(?:\s*,\s*[0-9A-Fa-f]{1,2})*)""")

    /**
     * Pull a report out of a message, or null if it is just a message.
     *
     * NULL IS THE COMMON CASE and has to stay cheap: every direct message the
     * app receives passes through here, and almost none of them are from a bot.
     */
    fun parse(text: String?): Report? {
        val t = text ?: return null
        if (t.isBlank()) return null
        // A cheap gate before the regexes. Nothing without one of these words
        // can match, and most traffic has neither.
        if (!t.contains("dB", true) && !t.contains("hop", true)) return null
        val r = Report(
            snrDb = SNR.find(t)?.groupValues?.get(1)?.toDoubleOrNull(),
            rssiDbm = RSSI.find(t)?.groupValues?.get(1)?.toDoubleOrNull()?.toInt(),
            hops = HOPS.find(t)?.groupValues?.get(1)?.toIntOrNull(),
            via = VIA.find(t)?.groupValues?.get(1)
                ?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }
                ?: emptyList(),
        )
        return if (r.empty) null else r
    }

    /**
     * IS THIS REPORT ABOUT US?
     *
     * A bot on a channel answers everybody, and its reply to somebody else is
     * a measurement of THEIR radio, not ours — recording it against our own
     * transmitter would be worse than not recording anything. The bots seen so
     * far address the subject by name in brackets, so a reply is ours when it
     * names us and not somebody else.
     *
     * A DIRECT message needs no such test: it was addressed to this radio by
     * the protocol, which is a stronger statement than any text convention.
     */
    fun addressesUs(text: String, ourName: String?): Boolean {
        val who = Regex("""@\[([^\]]{1,40})\]""").find(text)?.groupValues?.get(1)
            ?: return true // no addressee named: take it at face value
        val me = ourName?.trim().orEmpty()
        if (me.isEmpty()) return false
        return who.contains(me, ignoreCase = true) || me.contains(who, ignoreCase = true)
    }
}
