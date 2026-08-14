// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.MeshNodes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE FAKE MESH HAS TO BE SHAPED LIKE THE REAL ONE, or it tests nothing.
 *
 * A tidy simulation — fifty uniformly fresh, evenly spread, plainly named nodes
 * — passes every check the operator's actual mesh fails. The failures this
 * project has spent its device time on are all consequences of SHAPE: 350
 * contacts of which most are old, competing for 24 slots; names that come off
 * other people's radios; a long tail of distance that puts everything at the
 * rim if you scatter uniformly.
 *
 * These pin the shape against the census taken on 2026-08-12:
 *
 *     350 peers, 319 with a position, 0 undated
 *     heard <10m 77, <1h 8, <6h 43, <24h 64, older 158
 */
class FakeMeshTest {

    private val now = 1_786_000_000L
    private val mesh = FakeMesh.peers(45.5152, -122.6784, now)

    private fun aged(within: Long) = mesh.count { now - it.lastSeenEpochSec < within }

    @Test fun itIsTheSizeOfTheRealOne() {
        assertEquals(350, mesh.size)
    }

    /**
     * MOSTLY OLD, WITH A LIVE MINORITY — the distribution that makes ranking
     * hard. If a majority were fresh, any ranker would look competent.
     */
    @Test fun theAgesAreShapedLikeTheCensus() {
        val fresh = aged(600)
        val day = aged(86_400)
        val old = mesh.size - day
        assertTrue("only $fresh heard in ten minutes", fresh in 60..95)
        // OLDER-THAN-A-DAY IS THE BIGGEST SINGLE BUCKET, which is the property
        // that makes ranking hard — not that old nodes are an outright
        // majority. The census is 158 older against 192 within the day, and an
        // earlier version of this test asserted the majority and was simply
        // wrong about the numbers it was quoting.
        assertTrue("$old older than a day, out of ${mesh.size}", old > 120)
        assertTrue("$old older is not the largest bucket", old > fresh)
    }

    /**
     * Every peer is dated. The real radio dates all 350, and an undated peer
     * reads as fully stale — a fake mesh that quietly included some would make
     * the STALE display look broken when it is not.
     */
    @Test fun nothingIsUndated() {
        assertTrue(mesh.all { it.lastSeenEpochSec > 0 })
    }

    /** 350 - 319 = 31 have no position, because that is what the radio holds. */
    @Test fun someHaveNoPosition() {
        val located = mesh.count { it.lat != null && it.lon != null }
        assertEquals(319, located)
    }

    /**
     * NEAR-HEAVY WITH A LONG TAIL. A uniform scatter over 50 km puts almost
     * everything at the rim, where the ring stops separating nodes and the
     * layout code never gets exercised.
     */
    @Test fun mostNodesAreNearAndAFewAreFar() {
        val km = mesh.filter { it.lat != null }.map {
            MeshNodes.haversineKm(45.5152, -122.6784, it.lat!!, it.lon!!)
        }
        val near = km.count { it < 10.0 }
        assertTrue("only $near of ${km.size} within 10 km", near > km.size / 2)
        assertTrue("nothing beyond 20 km", km.any { it > 20.0 })
        assertTrue("something is past the 50 km rim", km.all { it < 60.0 })
    }

    /**
     * NAMES ARE HOSTILE ON PURPOSE. Emoji the stroke font cannot draw, CJK on a
     * different pipeline, a name past every width budget, and a blank one that
     * has to fall back to a key. Every shape here is in the operator's live
     * mesh, and each has broken a surface at least once.
     */
    @Test fun theNamesIncludeTheOnesThatBreakThings() {
        assertTrue("no emoji", mesh.any { it.name.contains("😸") || it.name.contains("👾") })
        assertTrue("no CJK", mesh.any { it.name.any { c -> c.code in 0x4E00..0x9FFF } })
        assertTrue("nothing over-long", mesh.any { it.name.length > 40 })
        assertTrue("nothing blank", mesh.any { it.name.isBlank() })
    }

    /**
     * DUPLICATE NAMES, DIFFERENT KEYS. Two radios called the same thing must
     * stay two nodes — the roster, the callsign renderer and search all have to
     * survive it, and the mesh this is modelled on is full of them.
     */
    @Test fun namesRepeatAndKeysDoNot() {
        assertTrue("no duplicate names", mesh.distinctBy { it.name }.size < mesh.size)
        assertEquals("keys must be unique", mesh.size, mesh.distinctBy { it.key }.size)
        assertEquals("full keys must be unique", mesh.size, mesh.distinctBy { it.fullKey }.size)
    }

    /** A full key is a full key: 64 hex characters, and the short one is its head. */
    @Test fun theKeysLookLikeKeys() {
        mesh.take(20).forEach {
            assertEquals(64, it.fullKey!!.length)
            assertTrue(it.fullKey!!.all { c -> c.isDigit() || c in 'a'..'f' })
            assertTrue(it.fullKey!!.startsWith(it.key))
        }
    }

    /** Repeaters exist, or the second silhouette on the horizon never draws. */
    @Test fun someAreRepeaters() {
        val reps = mesh.count { it.type == 2 }
        assertTrue("$reps repeaters", reps > 20)
    }

    /**
     * SEEDED. Two runs must be identical or a screenshot means nothing and a
     * regression cannot be told from a reshuffle.
     */
    @Test fun twoRunsAreTheSameMesh() {
        val again = FakeMesh.peers(45.5152, -122.6784, now)
        assertEquals(mesh.map { it.key to it.name }, again.map { it.key to it.name })
        assertEquals(mesh.map { it.lastSeenEpochSec }, again.map { it.lastSeenEpochSec })
    }

    /**
     * THE WHOLE POINT OF THIS DATASET, AS AN ASSERTION.
     *
     * On the glasses, before the ranker was rescored: 350 peers of which 79 had
     * been heard within ten minutes, and the ring drew live=10 stale=19. This
     * is that measurement, on a bench, so the regression is caught here rather
     * than three device reports later.
     *
     * A MAJORITY OF WHAT IS DRAWN SHOULD BE ALIVE. Not all of it — a live node
     * at the rim can still lose to a fresher one, and clustering takes its own
     * share — but a ring that is mostly grey while eighty nodes are talking is
     * the defect this fake mesh exists to reproduce.
     */
    @Test fun theRingDrawsMostlyLiveNodes() {
        val here = MeshNodes.Here(45.5152, -122.6784)
        val drawn = MeshNodes.build(here, mesh, now)
        val live = drawn.count { it.age < 0.34f }
        val stale = drawn.size - live
        assertTrue(
            "drew $live live and $stale stale of ${drawn.size}, " +
                "from a mesh with ${aged(600)} heard in the last ten minutes",
            live > stale,
        )
    }

    /** A smaller mesh keeps the shape rather than losing its rare buckets. */
    @Test fun aSmallMeshIsStillShapedLikeAMesh() {
        val small = FakeMesh.peers(45.5152, -122.6784, now, count = 40)
        assertEquals(40, small.size)
        assertTrue(small.any { now - it.lastSeenEpochSec < 600 })
        assertTrue(small.any { now - it.lastSeenEpochSec > 86_400 })
    }
}
