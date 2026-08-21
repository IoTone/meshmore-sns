// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.MeshNodes

/**
 * ASKING THE MESH WHAT THE WEATHER IS, WITHOUT BEING A NUISANCE ABOUT IT.
 *
 * The operator's complaint is exact and it is not about policy: "it is so hard
 * to get telemetry from any of the hundreds of devices in range." Three
 * separate things make that true today, and only one of them is airtime.
 *
 *  1. **You can only ask one node at a time**, from a menu, by hand. Three
 *     hundred contacts at one pinch each is not a feature.
 *  2. **Nothing shows the answer.** The app already asks, already decodes
 *     temperature, humidity and voltage, and already stores them on the peer —
 *     and then no surface in the app reads any of it. A wearer who did
 *     everything right saw a spoken "asked NAME" and nothing else, ever.
 *  3. **Most of those hundreds cannot be asked at all**, for reasons that were
 *     never reported: no full key, too many hops, heard once from a hilltop
 *     300 km away. Silence looked identical to failure.
 *
 * This file is the answer to (1) and (3): it plans a sweep, and it counts what
 * it excluded and why, so "I asked 40 of your 350" comes with the other 310
 * accounted for. (2) is a surface, elsewhere.
 *
 * ## The rules, and where they came from
 *
 * The Flutter app has shipped an airtime-conscious poller against real meshes
 * for months, and its numbers are adopted here rather than reinvented: one
 * peer at a time, spaced; tiered by reachability, with a hard distance bound
 * on the furthest tier; a refresh floor so a node is not asked twice in a
 * quarter of an hour; and a short cache that makes a repeat sweep nearly free.
 *
 * What is deliberately NOT here is a reciprocity rule. It was proposed —
 * refuse to ask for a class you refuse to answer — and the operator declined
 * it (2026-08-21): asking is fine whether or not your own sharing is on. What
 * replaces it is a nudge, once, at the moment the asymmetry is visible: see
 * [shouldOfferSharing].
 */
object TelemetryAsk {

    /** Seconds between asks. One node at a time, never a burst. */
    const val GAP_MS = 4_000L

    /** Most nodes one sweep will wake, however many are in range. */
    const val MAX_PER_SWEEP = 40

    /** A reading younger than this needs no asking at all. */
    const val FRESH_S = 5 * 60L

    /** And a node asked more recently than this is left alone. */
    const val COOLDOWN_S = 15 * 60L

    /** Furthest tier: two hops, and only if we also know it is close. */
    const val MAX_HOPS = 2

    /**
     * At or above this, the hop count is not a hop count.
     *
     * MeshCore stores 0xFF in a contact's path length to mean NO STORED ROUTE,
     * and this app turns that into hops = 256. The rest of the app already
     * reads it correctly — the roster splits on `hops in 2..249`, node focus
     * says "unknown" at 250 and above — and the first version of this planner
     * did not, so it called 349 of 350 contacts "more than 2 hops away" and
     * asked exactly one radio for the weather. Measured on the operator's own
     * mesh, 2026-08-21, which is how it was found.
     *
     * An unrouted contact is not far. It is unrouted, and MeshCore reaches it
     * by flooding — reachable immediately, at a price.
     */
    const val HOPS_UNKNOWN = 250

    /**
     * How many UNROUTED nodes one sweep will ask.
     *
     * Lower than the sweep budget on purpose. A request to a node with a
     * stored path travels that path; a request to an unrouted one is repeated
     * by every repeater that hears it, so a dozen of those is already a
     * noticeable amount of somebody else's evening. Twelve is enough to fill a
     * weather readout and small enough to defend.
     */
    const val FLOOD_BUDGET = 12

    /**
     * And an unrouted node is only worth a flood if it has been heard lately.
     *
     * A contact last heard three days ago may be switched off, moved, or a
     * hilltop echo. Spending a flood on it is a shot in the dark that everyone
     * within range pays for; six hours is the window in which "it was there
     * recently" is still evidence.
     */
    const val FLOOD_MAX_AGE_S = 6 * 3600L

    /** Kilometres. A node heard from a hilltop is not a weather station. */
    const val MAX_KM = 100.0

    /**
     * Why a node was not asked. Each value is a line in the census, and the
     * order is the order the checks run.
     */
    enum class Skip {
        /** REMOVE_CONTACT and telemetry both need all 32 bytes; a prefix cannot be asked. */
        NO_FULL_KEY,

        /** Beyond [MAX_HOPS]. Every relay in between pays for the question. */
        TOO_FAR_IN_HOPS,

        /** Two hops away is only acceptable if it is also near. */
        TOO_FAR_IN_KM,

        /** No stored route, and not heard recently enough to justify a flood. */
        UNROUTED_AND_STALE,

        /** No stored route, heard lately, but past this sweep's flood budget. */
        OVER_FLOOD_BUDGET,

        /** We already know, recently enough. */
        ALREADY_FRESH,

        /** Asked lately; asking again would not be a measurement, it would be a habit. */
        COOLING_DOWN,

        /** Over the sweep's budget. Reported so the count is never silently short. */
        OVER_BUDGET,
    }

    data class Plan(
        /** In the order they should be asked. */
        val ask: List<MeshNodes.Peer>,
        /** Every exclusion, counted. */
        val skipped: Map<Skip, Int>,
        val considered: Int,
    ) {
        val askCount: Int get() = ask.size

        /**
         * The census, as lines FOR A LOG.
         *
         * English, like every other log line in this app, and deliberately not
         * what the bay shows: a surface a Japanese wearer reads cannot be
         * built from literals in Kotlin, and the parity test that guards the
         * two locales only sees strings.xml. So the numbers live here and the
         * words live in the resources — see wxRows.
         *
         * WRITTEN AS SUBTRACTION, because the question a wearer has is "why
         * only 40 of my 350?" and a list of totals does not answer it.
         */
        fun census(): List<String> = buildList {
            add("$considered in the contact store")
            Skip.entries.forEach { s ->
                skipped[s]?.takeIf { it > 0 }?.let { add("  -$it ${reason(s)}") }
            }
            add("= $askCount to ask")
        }

        private fun reason(s: Skip): String = when (s) {
            Skip.NO_FULL_KEY -> "no full key (heard, never synced)"
            Skip.TOO_FAR_IN_HOPS -> "more than $MAX_HOPS hops away"
            Skip.UNROUTED_AND_STALE -> "no route, not heard in ${FLOOD_MAX_AGE_S / 3600} h"
            Skip.OVER_FLOOD_BUDGET -> "no route, past the flood budget of $FLOOD_BUDGET"
            Skip.TOO_FAR_IN_KM -> "further than ${MAX_KM.toInt()} km"
            Skip.ALREADY_FRESH -> "already answered in the last ${FRESH_S / 60} min"
            Skip.COOLING_DOWN -> "asked in the last ${COOLDOWN_S / 60} min"
            Skip.OVER_BUDGET -> "over this sweep's budget of $MAX_PER_SWEEP"
        }
    }

    /**
     * Choose who to ask, and account for everyone else.
     *
     * [asked] is key to the epoch second we last asked, which the caller keeps
     * across sweeps — the cooldown is worthless if it resets every time the
     * surface opens.
     */
    fun plan(
        peers: List<MeshNodes.Peer>,
        origin: MeshNodes.Here?,
        nowEpochSec: Long,
        asked: Map<String, Long> = emptyMap(),
        budget: Int = MAX_PER_SWEEP,
    ): Plan {
        val skipped = mutableMapOf<Skip, Int>()
        fun drop(s: Skip) { skipped[s] = (skipped[s] ?: 0) + 1 }

        // ROUTED AND UNROUTED ARE DIFFERENT QUESTIONS, so they are separated
        // here and rejoined at the end. A routed node is judged on how far the
        // question has to travel; an unrouted one on whether it is worth a
        // flood at all.
        val routed = mutableListOf<Pair<MeshNodes.Peer, Double?>>()
        val unrouted = mutableListOf<MeshNodes.Peer>()

        peers.forEach { p ->
            val full = p.fullKey
            if (full == null || full.length != 64) { drop(Skip.NO_FULL_KEY); return@forEach }
            val age = p.telemetry?.atEpochSec?.let { nowEpochSec - it }
            if (age != null && age in 0 until FRESH_S) { drop(Skip.ALREADY_FRESH); return@forEach }
            val since = asked[full]?.let { nowEpochSec - it }
            if (since != null && since in 0 until COOLDOWN_S) { drop(Skip.COOLING_DOWN); return@forEach }

            if (p.hops >= HOPS_UNKNOWN || p.flood) {
                val heard = nowEpochSec - p.lastSeenEpochSec
                if (heard > FLOOD_MAX_AGE_S) { drop(Skip.UNROUTED_AND_STALE); return@forEach }
                unrouted += p
                return@forEach
            }
            if (p.hops > MAX_HOPS) { drop(Skip.TOO_FAR_IN_HOPS); return@forEach }
            val km = distanceKm(origin, p)
            // ONLY A KNOWN distance can disqualify. A node with no position is
            // not thereby far away — it is unmeasured, and the hop count has
            // already vouched for it.
            if (km != null && km > MAX_KM) { drop(Skip.TOO_FAR_IN_KM); return@forEach }
            routed += p to km
        }

        // NEAREST FIRST, IN THE SENSE THAT COSTS LEAST. Hops before kilometres
        // because hops are what other people's radios pay; a node with no
        // position sorts after the located ones at the same hop count rather
        // than being pushed to the back of the whole queue.
        val routedOrder = routed.sortedWith(
            compareBy<Pair<MeshNodes.Peer, Double?>>({ it.first.hops })
                .thenBy { it.second ?: Double.MAX_VALUE / 2 }
                .thenByDescending { it.first.lastSeenEpochSec },
        ).map { it.first }

        // MOST RECENTLY HEARD FIRST among the unrouted, because recency is the
        // only evidence available that a flood will reach anybody.
        val floodOrder = unrouted.sortedByDescending { it.lastSeenEpochSec }
        if (floodOrder.size > FLOOD_BUDGET) {
            skipped[Skip.OVER_FLOOD_BUDGET] = floodOrder.size - FLOOD_BUDGET
        }

        // Routed first: they are cheaper, and if the budget runs out it should
        // run out on the expensive ones.
        val ordered = routedOrder + floodOrder.take(FLOOD_BUDGET)

        if (ordered.size > budget) skipped[Skip.OVER_BUDGET] = ordered.size - budget
        return Plan(ordered.take(budget), skipped, peers.size)
    }

    private fun distanceKm(origin: MeshNodes.Here?, p: MeshNodes.Peer): Double? {
        val oLat = origin?.lat ?: return null
        val oLon = origin.lon ?: return null
        val lat = p.lat ?: return null
        val lon = p.lon ?: return null
        if (kotlin.math.abs(lat) < 1e-7 && kotlin.math.abs(lon) < 1e-7) return null
        return MeshNodes.haversineKm(oLat, oLon, lat, lon)
    }

    /**
     * SHOULD WE ASK THE WEARER TO TURN THEIR OWN SHARING ON?
     *
     * The operator's ruling was that asking without sharing is fine — no
     * reciprocity gate. But the asymmetry is worth mentioning ONCE, at the
     * moment it is concrete rather than hypothetical: they have just asked
     * forty strangers for a temperature while answering nobody.
     *
     * Once. A second prompt would be nagging, and nagging about a privacy
     * setting is how an app teaches people to dismiss its privacy settings
     * without reading them.
     */
    fun shouldOfferSharing(
        ownEnvironmentLevel: Int,
        alreadyOffered: Boolean,
        asksMade: Int,
    ): Boolean = !alreadyOffered &&
        asksMade > 0 &&
        ownEnvironmentLevel == com.iotj.meshmore.xr.spatial.TelemetryPerms.DENY

    /**
     * What came back, as one line.
     *
     * ANSWERED OVER ASKED, and both numbers shown, because the interesting
     * figure on a mesh is not how many nodes have a thermometer — it is how
     * many of the ones you asked said anything at all. A low number here is
     * the mesh's answer, not the app's failure, and the difference is only
     * visible if the denominator is printed.
     */
    fun report(asked: Int, answered: Int, withEnvironment: Int): String =
        "asked $asked, answered $answered" +
            (if (asked > 0) " (%.0f%%)".format(answered * 100.0 / asked) else "") +
            ", $withEnvironment with a sensor"
}
