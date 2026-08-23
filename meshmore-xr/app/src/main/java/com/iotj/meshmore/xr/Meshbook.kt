// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

/**
 * THE LAST DAY ON THIS MESH, AS A SHAPE.
 *
 * Not a log — the inbox is the log, and reading it tells you what was said
 * without ever telling you what KIND of day it was. Meshbook answers the
 * questions a log cannot: was it busy, who carried it, did anyone answer YOU,
 * and when is this band actually awake.
 *
 * ## It costs nothing, and that is the point
 *
 * Every figure comes from messages already on this device. No query, no
 * airtime, no permission, no protocol work — and it is the one surface in the
 * app that is fully useful with the radio switched off. On the operator's own
 * glasses the store was carrying 67 KB of history while nothing in the app
 * could say a single thing about it.
 *
 * ## What is taken from SNS and what is not
 *
 * The phone app settled the shape and its decisions are kept: a ROLLING
 * twenty-four hours rather than a calendar day (collection does not run in the
 * background, so a midnight reset would erase the evening), and a
 * twenty-four-bucket histogram by local hour.
 *
 * Two things differ, and both are because this app knows more:
 *
 *  - **Replies.** SNS counts a message as a reply when its text begins with
 *    `>`, which is a typing convention and only works where people follow it.
 *    Here a reply is a message that ARRIVED after one of ours in the same
 *    thread, which is a fact rather than a habit. And the delivery ledger adds
 *    the figure SNS cannot compute at all: how many of ours were delivered.
 *  - **Scope.** SNS reads channel traffic only, where senders are anonymous
 *    and identity is a self-declared `name:` prefix. This includes direct
 *    messages, where the sender is a KEY, so "top voices" means something.
 */
object Meshbook {

    /** The window. Rolling, not a calendar day — see the class note. */
    const val WINDOW_S = 24 * 3600L

    /** How many voices a bay can usefully show before it becomes a list. */
    const val TOP_VOICES = 5

    data class Voice(val name: String, val said: Int, val lastAtEpochSec: Long)

    data class Book(
        /** Messages in the window, ours and theirs. */
        val total: Int,
        /** Of those, the ones we sent. */
        val mine: Int,
        /**
         * Ours that COULD be acknowledged — direct messages with a delivery
         * state. Channel sends are not in it: MeshCore group traffic carries
         * no ack, so counting them in the denominator reported the operator's
         * own mesh at 4% delivered when the direct soaks had measured 90%.
         */
        val trackable: Int,
        /** Ours that the far end acknowledged. */
        val delivered: Int,
        /** Ours the app gave up on. */
        val lost: Int,
        /** Ours that somebody answered in the same thread. */
        val answered: Int,
        /** Counts by local hour, index 0..23. */
        val hourly: List<Int>,
        val voices: List<Voice>,
        /** Distinct senders heard, ourselves excluded. */
        val speakers: Int,
    ) {
        val theirs: Int get() = total - mine

        /** Of the messages we sent, the share that was acknowledged. */
        val deliveryPct: Int?
            get() = if (trackable == 0) null else (delivered * 100.0 / trackable).toInt()

        /** And the share somebody replied to, which is a different question. */
        val replyPct: Int?
            get() = if (mine == 0) null else (answered * 100.0 / mine).toInt()

        val busiestHour: Int? get() = hourly.withIndex().maxByOrNull { it.value }
            ?.takeIf { it.value > 0 }?.index

        val peak: Int get() = hourly.maxOrNull() ?: 0
    }

    /**
     * THE ONE PLACE ALL OF THIS IS COMPUTED.
     *
     * [nowEpochSec] is passed rather than read so the whole thing is a pure
     * function of its inputs — which is what lets a day's traffic be built in
     * a test and the answers asserted, rather than waiting for a real day.
     *
     * [hourOf] converts an epoch second to a local hour, injected for the same
     * reason: a histogram bucketed by the machine's timezone cannot be checked
     * anywhere except in that timezone.
     */
    fun of(
        msgs: List<MeshLink.Msg>,
        nowEpochSec: Long,
        hourOf: (Long) -> Int,
    ): Book {
        val since = nowEpochSec - WINDOW_S
        // AT OR AFTER, and not in the future. A peer's clock can be days out —
        // 71 contacts on this mesh reported timestamps ahead of now — and a
        // message stamped tomorrow would sit in the window forever and land in
        // whatever bucket its wrong hour points at.
        val win = msgs.filter { it.atEpochSec in since..nowEpochSec }

        val hourly = MutableList(24) { 0 }
        win.forEach { hourly[hourOf(it.atEpochSec).coerceIn(0, 23)] += 1 }

        val mineList = win.filter { it.fromName == ME }
        val theirsList = win.filter { it.fromName != ME }

        // A NAME, A KEY, OR NOTHING AT ALL. Channel traffic carries no sender
        // key and its name is whatever the text was prefixed with, so a
        // message with neither produced a voice called "" — which drew as a
        // blank row with a count beside it, top of the list, on the operator's
        // own mesh. Those are grouped as one anonymous voice instead.
        val voices = theirsList
            .groupBy {
                it.fromName.ifBlank { it.fromKey.takeLast(4).ifBlank { ANON } }
            }
            .map { (name, m) -> Voice(name, m.size, m.maxOf { it.atEpochSec }) }
            .sortedWith(compareByDescending<Voice> { it.said }.thenBy { it.name })

        return Book(
            total = win.size,
            mine = mineList.size,
            trackable = mineList.count { it.delivery != null },
            delivered = mineList.count { it.delivery == MeshLink.Delivered.DELIVERED },
            lost = mineList.count { it.delivery == MeshLink.Delivered.LOST },
            answered = answered(win),
            hourly = hourly,
            voices = voices.take(TOP_VOICES),
            speakers = voices.size,
        )
    }

    /**
     * HOW MANY OF OUR MESSAGES SOMEBODY ANSWERED.
     *
     * A reply is somebody else's message arriving AFTER one of ours in the
     * same thread, and before we speak there again. That is a fact about the
     * conversation; SNS's rule — the text begins with `>` — is a fact about
     * how somebody types, and it undercounts every reply from a person who
     * does not use the convention, which on this mesh is nearly everybody.
     *
     * Counted once per message of ours, so a thread where four people answer
     * at once is one answered message rather than four.
     */
    private fun answered(win: List<MeshLink.Msg>): Int {
        var n = 0
        win.groupBy { it.channel ?: it.fromKey }.forEach { (_, thread) ->
            val ordered = thread.sortedBy { it.atEpochSec }
            ordered.forEachIndexed { i, m ->
                if (m.fromName != ME) return@forEachIndexed
                val replied = ordered.drop(i + 1)
                    .takeWhile { it.fromName != ME }
                    .any { it.fromName != ME }
                if (replied) n++
            }
        }
        return n
    }

    /** How the app marks its own messages, everywhere. */
    const val ME = "ME"

    /**
     * Everybody who spoke without saying who they were.
     *
     * One bucket rather than one voice each: on a channel there is no key to
     * tell them apart, so counting them separately would invent a crowd out of
     * what might be one person.
     */
    const val ANON = "?"

    /**
     * The histogram as a row of blocks, for a surface that has no geometry.
     *
     * Eight levels because that is what the block characters give, and the
     * scale is the peak rather than an absolute — a quiet day should still
     * show its own shape rather than a flat line.
     */
    fun sparkline(hourly: List<Int>): String {
        val peak = hourly.maxOrNull() ?: 0
        if (peak == 0) return "·".repeat(hourly.size)
        val bars = " ▁▂▃▄▅▆▇█"
        return hourly.joinToString("") { v ->
            if (v == 0) "·" else bars[(v * 8 / peak).coerceIn(1, 8)].toString()
        }
    }
}
