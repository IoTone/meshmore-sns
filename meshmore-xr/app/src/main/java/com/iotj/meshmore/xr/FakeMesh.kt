// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.MeshNodes
import java.util.Random

/**
 * A MESH THAT IS NOT THERE, shaped like the one that is.
 *
 * ## Why the old simulation could not test anything
 *
 * `--ez sim true` used to fabricate eleven `Horizon.Node`s — the type the
 * renderer consumes, AFTER ranking, clustering, filtering and placement have
 * already happened. It exercised the drawing and nothing else, which was
 * exactly what it was written for and is no longer enough: every recent
 * question has been about the stages it skipped. Does the ranker pick the right
 * two dozen out of three hundred. Does FIND narrow the ring. Do favourites
 * float. Does a tabletop stop at twelve. None of that could be answered without
 * a radio and a room.
 *
 * So this produces PEERS — the type the radio delivers — and lets the whole
 * pipeline run on them. The only thing faked is the source.
 *
 * ## Shaped like the real one, because the shape is what breaks things
 *
 * The distribution here is not invented. It is the census taken from the
 * operator's own mesh on 2026-08-12:
 *
 *     350 peers, 319 with a position, 0 undated
 *     heard <10m 77, <1h 8, <6h 43, <24h 64, older 158
 *
 * That shape is the whole problem in miniature — a large majority of contacts
 * are old, a live minority is scattered among them, and 24 slots have to be
 * chosen. A tidy fake with fifty uniformly fresh nodes would pass every test
 * the real mesh fails.
 *
 * NAMES ARE HOSTILE ON PURPOSE, for the same reason: they come off other
 * people's radios. Emoji, CJK, full-width Latin, names far past any width
 * budget, duplicates that differ only by key, and a few blanks. Every one of
 * those is in the operator's live mesh.
 *
 * SEEDED, so two runs are comparable and a screenshot means something. Nothing
 * here calls a clock either — [at] takes the time so the ages are exact rather
 * than approximately-now.
 */
object FakeMesh {

    /** The census this is shaped from. Buckets in seconds, and their counts. */
    private val AGE_MIX = listOf(
        600L to 77,        // heard in the last ten minutes
        3_600L to 8,       // within the hour
        21_600L to 43,     // within six
        86_400L to 64,     // within a day
        30 * 86_400L to 158, // older, which is most of any real contact list
    )

    /** How many of the 350 have no usable position. Matches 350 - 319. */
    private const val UNLOCATED = 31

    private val STEMS = listOf(
        "Downtown", "Collins View", "Harness Mountain", "Portland Metro",
        "Council Crest", "Rocky Butte", "Mt Tabor", "Sauvie", "Estacada",
        "Sandy River", "Hillsboro", "Beaverton", "Gresham", "Milwaukie",
        "St Johns", "Sellwood", "Lents", "Alberta", "Hawthorne", "Kenton",
    )

    private val SUFFIXES = listOf(
        "Repeater", "RS", "Solar", "Node", "Base", "Relay", "Gateway", "",
    )

    /**
     * The awkward ones. Every shape here has bitten a real surface: an emoji
     * the stroke font cannot draw, CJK that goes through a different pipeline,
     * full-width Latin that measures wider than it looks, a name past every
     * width budget in the app, and a blank one that has to fall back to a key.
     */
    private val AWKWARD = listOf(
        "WA7TCH 👾 REPEATER 2",
        "QueenAnneChonk 😸",
        "🐢 turtle relay",
        "中継局 山",
        "ＯＫａｙ",
        "MMaker Rak Solar",
        "a node with a truly unreasonable name that nobody will read",
        "",
        "🌊🌊",
        "Ökonomy",
    )

    /**
     * [count] peers around ([lat], [lon]), aged against [atEpochSec].
     *
     * The default count is the real one. Smaller counts keep the same age SHAPE
     * rather than the same absolute buckets, so a 50-peer run is still mostly
     * old with a live minority.
     */
    fun peers(
        lat: Double,
        lon: Double,
        atEpochSec: Long,
        count: Int = 350,
        seed: Long = 20260812L,
    ): List<MeshNodes.Peer> {
        val rng = Random(seed)
        val total = AGE_MIX.sumOf { it.second }
        val out = ArrayList<MeshNodes.Peer>(count)
        var i = 0
        AGE_MIX.forEach { (within, n) ->
            // Scaled, and at least one of each bucket: a count small enough to
            // round a bucket to zero would quietly drop the very case that
            // bucket exists to represent.
            val want = maxOf(1, (n.toDouble() / total * count).toInt())
            repeat(want) {
                if (out.size >= count) return@repeat
                out += one(i++, rng, lat, lon, atEpochSec, within)
            }
        }
        // Rounding leaves a few short of the asked-for count; fill from the
        // oldest bucket, which is where a real list's tail is.
        while (out.size < count) out += one(i++, rng, lat, lon, atEpochSec, 30 * 86_400L)
        return out
    }

    private fun one(
        i: Int,
        rng: Random,
        lat: Double,
        lon: Double,
        atEpochSec: Long,
        withinSec: Long,
    ): MeshNodes.Peer {
        // A KEY THAT LOOKS LIKE A KEY. 64 hex characters, deterministic from
        // the index — the app shows a prefix in some places and the whole thing
        // in others, and search has to find a node from either.
        //
        // THE INDEX GOES IN THE HEAD, and that is not cosmetic. The first cut
        // derived every byte from `i * 37 + b * 11` mod 256, which repeats
        // after 256 peers: a 350-node mesh had 256 distinct keys, 94 collisions
        // silently overwrote each other in MeshLink's keyed table, and the
        // simulation quietly became a different size than it claimed. Caught by
        // the test that says keys are unique, which is exactly the kind of
        // thing a fake dataset gets wrong and a real one never does.
        val full = "%08x".format(i) + buildString {
            repeat(28) { b -> append("%02x".format((i * 37 + b * 11 + 7) and 0xFF)) }
        }
        val name = if (i % 17 == 0) {
            AWKWARD[(i / 17) % AWKWARD.size]
        } else {
            val stem = STEMS[i % STEMS.size]
            val sfx = SUFFIXES[(i / STEMS.size) % SUFFIXES.size]
            // DUPLICATES ARE REAL. Every fifth name repeats a stem exactly, so
            // two peers differ only by key — which is what the roster, the
            // callsign renderer and search all have to survive.
            if (sfx.isEmpty()) stem else "$stem $sfx"
        }
        // Distance: mostly near, with a long tail. A uniform scatter over 50 km
        // would put almost everything at the rim, where the ring stops
        // separating them and the layout never gets exercised.
        val km = 0.2 + 49.8 * Math.pow(rng.nextDouble(), 2.6)
        val bearing = rng.nextDouble() * 2 * Math.PI
        val dLat = km / 111.0 * Math.cos(bearing)
        val dLon = km / (111.0 * Math.cos(Math.toRadians(lat))) * Math.sin(bearing)
        val located = i >= UNLOCATED
        return MeshNodes.Peer(
            key = full.take(12),
            name = name,
            // Roughly one in five is a repeater, which is what carries the
            // second silhouette on the horizon.
            type = if (i % 5 == 0) 2 else 1,
            hops = rng.nextInt(4),
            lat = if (located) lat + dLat else null,
            lon = if (located) lon + dLon else null,
            // Spread across the bucket rather than pinned to its edge, so the
            // fade has a gradient to draw and LIVE/STALE has a boundary to
            // fall on either side of.
            lastSeenEpochSec = atEpochSec - (rng.nextDouble() * withinSec).toLong(),
            fullKey = full,
            // A couple of radio-flagged favourites, so the ranker's
            // favourites-first rule has something to act on before the wearer
            // has starred anybody.
            favourite = i % 97 == 0,
        )
    }
}
