// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

/**
 * EVERY MESSAGE THIS APP HANDED TO THE RADIO, AND WHAT BECAME OF IT.
 *
 * [MeshLink.Delivery] counts three totals — attempted, accepted, acked — and
 * that was enough to establish that roughly one message in ten never arrives.
 * It is not enough to say anything about WHICH one, which is the only question
 * that leads anywhere: a loss that lands on the long messages is a payload
 * problem, one that lands on the flooded ones is an airtime problem, and one
 * spread evenly across both is the radio link itself. Three different repairs,
 * and a percentage cannot tell them apart.
 *
 * So each attempt keeps its own record. The ledger is pure and holds no
 * entities, no session and no context, which is what lets the analysis below
 * be exercised against a hand-built run rather than against a radio and an
 * afternoon.
 *
 * ## What is knowable, and what is guessed
 *
 * The radio reports two things this app does not otherwise know: whether it
 * FLOODED a message or sent it along a known route, and its own estimate of
 * how long an acknowledgement should take. Both arrive in the sent frame,
 * after the attempt — so a record is opened at the send and completed twice,
 * once by the radio's acceptance and once by an ack that may never come.
 *
 * An attempt with no acceptance never reached the air. An attempt accepted and
 * never acked did reach the air and is the loss being hunted. The two are
 * different failures and the ledger keeps them apart, because summing them
 * into "failed" is how the question got stuck in the first place.
 */
object TxLog {

    /** One message handed to the radio. */
    data class Attempt(
        val seq: Int,
        val atMs: Long,
        /** UTF-8 bytes, which is what occupies the air — not characters. */
        val bytes: Int,
        val peer: String,
        /** Hops to the peer as the contact store had it AT SEND TIME. */
        val hops: Int,
        /** False until the radio says it accepted it for transmission. */
        val accepted: Boolean = false,
        /**
         * Null until accepted. What the SENDING radio said it did.
         *
         * READ IT AS THE DISPATCH MODE, NOT AS THE ROUTE. On 2026-08-21 every
         * one of thirty messages was reported "direct" by the sending radio
         * and arrived at D38F07AED563 with pathLen 0xFF, which is FLOOD. That
         * looked like a contradiction and is not quite one — the two bytes are
         * produced at different layers, and the evidence says both are honest:
         *
         *  - The SENDER had a stored route to d563 with zero relays
         *    (outPathLen 0, which is how the ledger's hop count comes out at
         *    1), and it quoted 2448-3858 ms for the round trip. Its flooded
         *    estimate is around 8 s. So the sending radio believed it was
         *    doing something direct, and priced it that way.
         *  - The RECEIVER reports 0xFF, which the shipping SNS client reads
         *    the same way this one does. Every inbound message in every log
         *    captured here — 53 of them, both directions, several senders —
         *    says 0xFF. A field that never varies is not distinguishing
         *    anything.
         *
         * The reading that fits both: a neighbour with no relays between has
         * no path to put in the packet, so the delivery is not path-routed and
         * the receiver has no hops to report.
         *
         * WHAT IS STILL UNKNOWN, and it matters: whether such a packet is
         * repeated by every repeater that hears it. If it is, a direct message
         * to a node in the same room costs the band far more than this app has
         * been assuming. It cannot be settled from either end of the
         * conversation — it needs a third radio listening, and a repeater does
         * not show its companion what it repeated. Left open on purpose rather
         * than assumed either way.
         *
         * The by-route breakdown is therefore reporting the sender's dispatch
         * mode, which is a real thing, and on this mesh it has been the same
         * for every packet — so it has yet to discriminate anything.
         */
        val flood: Boolean? = null,
        /** The radio's own estimate of the round trip, milliseconds. */
        val estTimeoutMs: Long = 0L,
        val tag: Long = 0L,
        /** Round trip actually measured, or null if no acknowledgement came. */
        val ackMs: Long? = null,
        /** Set when the sweep gave up on it. Distinguishes "lost" from "in flight". */
        val gaveUp: Boolean = false,
    ) {
        val settled: Boolean get() = ackMs != null || gaveUp || !accepted
        val lost: Boolean get() = accepted && ackMs == null && gaveUp
    }

    /**
     * How many attempts are kept.
     *
     * An hour of soaking at one message every six seconds is 600, and the
     * question being asked is about a rate rather than a moment, so the window
     * has to be long enough to hold a run whole. Each record is six words.
     */
    const val KEEP = 600

    /**
     * SIZE BUCKETS, IN BYTES OF PAYLOAD.
     *
     * MeshCore's own limit is around 160 bytes of text; the soak sends 135 on
     * purpose, near the top. If loss concentrates in the top bucket the packet
     * is too long for the link budget in use, which is a spreading-factor
     * conversation and not a software one.
     */
    val SIZE_EDGES = listOf(32, 64, 96, 128, 160)

    fun sizeBucket(bytes: Int): String {
        var low = 0
        SIZE_EDGES.forEach { hi ->
            if (bytes <= hi) return "$low-$hi B"
            low = hi
        }
        return ">$low B"
    }

    /** One line of the breakdown: a name, how many were accepted, how many acked. */
    data class Slice(val name: String, val accepted: Int, val acked: Int) {
        val lost: Int get() = accepted - acked
        val reliability: Double? get() = if (accepted == 0) null else acked * 100.0 / accepted
        fun line(): String =
            "%-12s %3d sent  %3d ack  %s".format(
                name, accepted, acked,
                reliability?.let { "%3.0f%%".format(it) } ?: "  -",
            )
    }

    /**
     * Group settled attempts by a key.
     *
     * SETTLED ONLY — an attempt still inside its ack window is not a loss and
     * counting it as one makes every report taken during a run look worse than
     * the mesh is. That mistake is easy to make and impossible to see once the
     * numbers are averaged.
     */
    fun sliceBy(attempts: List<Attempt>, order: List<String>? = null, key: (Attempt) -> String):
        List<Slice> {
        val live = attempts.filter { it.accepted && it.settled }
        val groups = live.groupBy(key)
        val names = order?.filter { it in groups.keys } ?: groups.keys.sorted()
        return names.map { n ->
            val g = groups[n].orEmpty()
            Slice(n, g.size, g.count { it.ackMs != null })
        }
    }

    /**
     * Round trips at the median and the tail.
     *
     * The mean was the only latency figure this app had, and a mean cannot
     * show a bimodal link — a direct route answering in two seconds and a
     * flooded one in nine average to a number that describes neither. The 90th
     * percentile is also the number a timeout should be set from.
     */
    data class Latency(val n: Int, val p50: Long, val p90: Long, val worst: Long) {
        fun line(): String = "n=$n  p50=${p50}ms  p90=${p90}ms  worst=${worst}ms"
    }

    fun latency(attempts: List<Attempt>): Latency? {
        val ms = attempts.mapNotNull { it.ackMs }.sorted()
        if (ms.isEmpty()) return null
        fun at(q: Double) = ms[((ms.size - 1) * q).toInt().coerceIn(0, ms.size - 1)]
        return Latency(ms.size, at(0.5), at(0.9), ms.last())
    }

    /**
     * THE WHOLE FINDING, IN THE FEWEST LINES THAT CAN CARRY IT.
     *
     * Written for a log first and a panel second, so it is plain text with a
     * fixed left column. Each breakdown exists because it discriminates a
     * different repair; a slice with one row is printed anyway, because "every
     * message this run went the same way" is itself the answer to why the
     * comparison is empty.
     */
    fun report(attempts: List<Attempt>): List<String> {
        if (attempts.isEmpty()) return listOf("no sends recorded")
        val settled = attempts.filter { it.settled }
        val air = settled.filter { it.accepted }
        val refused = settled.count { !it.accepted }
        val acked = air.count { it.ackMs != null }
        val out = mutableListOf<String>()
        out += "%d attempts — %d never left the radio, %d reached the air".format(
            attempts.size, refused, air.size,
        )
        out += "%d acknowledged, %d lost in the air%s".format(
            acked, air.size - acked,
            if (air.isEmpty()) "" else " (%.0f%% delivered)".format(acked * 100.0 / air.size),
        )
        val inFlight = attempts.size - settled.size
        if (inFlight > 0) out += "$inFlight still inside its ack window, not counted"
        latency(air)?.let { out += "round trip ${it.line()}" }
        out += "-- by route --"
        sliceBy(air, listOf("direct", "flood")) {
            if (it.flood == true) "flood" else "direct"
        }.forEach { out += it.line() }
        out += "-- by size --"
        sliceBy(air, SIZE_EDGES.let { e ->
            val names = mutableListOf<String>()
            var low = 0
            e.forEach { hi -> names += "$low-$hi B"; low = hi }
            names + ">$low B"
        }) { sizeBucket(it.bytes) }.forEach { out += it.line() }
        out += "-- by hops --"
        sliceBy(air) { "${it.hops} hop" + if (it.hops == 1) "" else "s" }
            .forEach { out += it.line() }
        return out
    }

    /**
     * THE SAME FINDING, SHAPED FOR A ROW OF TYPE RATHER THAN A LOG LINE.
     *
     * A bay row is 28 cells in English and 26 in Japanese, and the log format
     * above is thirty-five characters of fixed columns — it would be clipped
     * exactly where the numbers are. So this returns name/value pairs for the
     * row builder to measure and fit, and it stays numeric wherever it can:
     * "128-160 B" and "2 HOPS" need no translation, and a count is a count in
     * every language.
     *
     * Ordered by what a wearer looks for first — did they arrive, how fast,
     * and only then the breakdowns.
     */
    /**
     * WHAT A ROW IS, WITHOUT SAYING IT IN ANY LANGUAGE.
     *
     * [rows] used to return English names — "SENT", "ROUND TRIP", "128-160 B" —
     * and the delivery bay printed them straight onto the glasses, so the whole
     * surface was in English on a Japanese build. Nothing could catch that: the
     * strings fit their plate, and the parity test compares resource files
     * while these lived in Kotlin.
     *
     * This file stays pure — no Context, no resources, so the analysis can be
     * exercised on a desktop JVM — by naming the row rather than wording it.
     * The words live in strings.xml where the parity test can see them, and
     * `wxRows`' sibling `txRows` does the joining.
     */
    sealed interface Name {
        data object Sent : Name
        data object Refused : Name
        data object Acked : Name
        data object InFlight : Name
        data object RoundTrip : Name
        data object Slowest : Name
        data object Direct : Name
        data object Flood : Name
        data class Hops(val n: Int) : Name
        data class Size(val lo: Int, val hi: Int) : Name
        data class Over(val lo: Int) : Name
    }

    /** A row: what it is, and the figures that go beside it. */
    data class Row(val name: Name, val value: String)

    private fun nameOfBucket(bytes: Int): Name {
        var low = 0
        SIZE_EDGES.forEach { hi ->
            if (bytes <= hi) return Name.Size(low, hi)
            low = hi
        }
        return Name.Over(low)
    }

    /**
     * THE SAME FINDING, SHAPED FOR A ROW OF TYPE RATHER THAN A LOG LINE.
     *
     * A bay row is 28 cells in English and 26 in Japanese, and the log format
     * is thirty-five columns wide — it would be clipped exactly where the
     * figures are. Ordered by what a wearer looks for first: did they arrive,
     * how fast, and only then the breakdowns.
     */
    fun rows(attempts: List<Attempt>): List<Row> {
        if (attempts.isEmpty()) return emptyList()
        val settled = attempts.filter { it.settled }
        val air = settled.filter { it.accepted }
        val acked = air.count { it.ackMs != null }
        val out = mutableListOf<Row>()
        out += Row(Name.Sent, "${attempts.size}")
        val refused = settled.count { !it.accepted }
        if (refused > 0) out += Row(Name.Refused, "$refused")
        out += Row(
            Name.Acked,
            "$acked / ${air.size}" +
                (if (air.isEmpty()) "" else "  %.0f%%".format(acked * 100.0 / air.size)),
        )
        val inFlight = attempts.size - settled.size
        if (inFlight > 0) out += Row(Name.InFlight, "$inFlight")
        latency(air)?.let {
            out += Row(Name.RoundTrip, "${it.p50}")
            out += Row(Name.Slowest, "${it.worst}")
        }
        fun slices(list: List<Slice>, name: (String) -> Name) = list.forEach { sl ->
            out += Row(
                name(sl.name),
                "${sl.acked}/${sl.accepted}" +
                    (sl.reliability?.let { "  %.0f%%".format(it) } ?: ""),
            )
        }
        slices(
            sliceBy(air, listOf("direct", "flood")) { if (it.flood == true) "flood" else "direct" },
        ) { if (it == "flood") Name.Flood else Name.Direct }
        // Bucketed by the same edges the log uses, but carried as numbers so
        // the unit is the resource's business rather than this file's.
        air.filter { it.settled }.groupBy { nameOfBucket(it.bytes) }.forEach { (n, g) ->
            out += Row(
                n,
                "${g.count { it.ackMs != null }}/${g.size}" +
                    "  %.0f%%".format(g.count { it.ackMs != null } * 100.0 / g.size),
            )
        }
        air.groupBy { it.hops }.toSortedMap().forEach { (h, g) ->
            out += Row(
                Name.Hops(h),
                "${g.count { it.ackMs != null }}/${g.size}" +
                    "  %.0f%%".format(g.count { it.ackMs != null } * 100.0 / g.size),
            )
        }
        return out
    }

    /**
     * How far below the run's own rate a slice must fall to be called out.
     *
     * A slice is only news if it is worse than the thing it is part of, and by
     * enough that a short run's luck does not produce it. At ten sends one
     * unlucky message moves a five-message slice by twenty points, so the
     * margin is set above that and the minimum sample below it — together they
     * mean a headline names a pattern rather than a coincidence.
     */
    const val WORSE_BY = 15.0

    /** Fewest sends in a slice before it may be named. */
    const val ENOUGH = 3

    /**
     * The one-line version, for a notice band or an alert.
     *
     * Names the WORST slice rather than the average, because the average is
     * what was already known and the worst slice is the lead. A slice that
     * covers the whole run is not a finding — it IS the average, wearing a
     * label — and neither is one that merely happens to hold the unlucky
     * message. Both were caught by tests that built the runs on purpose.
     */
    fun headline(attempts: List<Attempt>): String {
        val air = attempts.filter { it.accepted && it.settled }
        if (air.isEmpty()) return "NO SENDS TO REPORT"
        val acked = air.count { it.ackMs != null }
        val overall = acked * 100.0 / air.size
        val worst = (
            sliceBy(air, listOf("direct", "flood")) { if (it.flood == true) "flood" else "direct" } +
                sliceBy(air) { sizeBucket(it.bytes) } +
                sliceBy(air) { "${it.hops} hop" + if (it.hops == 1) "" else "s" }
            )
            .filter { it.accepted >= ENOUGH && it.accepted < air.size }
            .filter { (it.reliability ?: 100.0) <= overall - WORSE_BY }
            .minByOrNull { it.reliability ?: 100.0 }
        val head = "%d/%d DELIVERED".format(acked, air.size)
        return worst?.let { "$head — WORST ${it.name.uppercase()} %.0f%%".format(it.reliability) }
            ?: head
    }
}
