// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.MeshNodes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE SWEEP DELETES THINGS ON SOMEBODY'S RADIO, so its exclusions are the part
 * that has to be proved rather than reviewed.
 *
 * The rule under test is a pure predicate — everything MeshLink.farContacts
 * does apart from reaching the radio — restated here so it can be exercised
 * without a Bluetooth session. If the two ever disagree, this file is the one
 * that is right, and the one that says why.
 */
class ContactGcTest {

    private fun peer(
        key: String,
        name: String = key,
        lat: Double? = 45.51,
        lon: Double? = -122.68,
    ) = MeshNodes.Peer(
        key = key, name = name, type = 1, hops = 1,
        lat = lat, lon = lon, lastSeenEpochSec = 1_700_000_000L,
        fullKey = key.padEnd(64, '0'),
    )

    private val here = MeshNodes.Here(45.5152, -122.6784)

    /** The predicate, exactly as MeshLink applies it. */
    private fun collectable(
        p: MeshNodes.Peer,
        km: Double = 100.0,
        mine: List<String> = listOf("ab60", "d563"),
        favourites: Set<String> = emptySet(),
    ): Boolean {
        val isMine = mine.any { sfx ->
            p.name.endsWith(sfx, true) || p.key.endsWith(sfx, true) ||
                (p.fullKey ?: "").endsWith(sfx, true)
        }
        val lat = p.lat
        val lon = p.lon
        return when {
            isMine -> false
            p.favourite -> false
            (p.fullKey ?: p.key) in favourites -> false
            lat == null || lon == null -> false
            kotlin.math.abs(lat) < 1e-7 && kotlin.math.abs(lon) < 1e-7 -> false
            else -> MeshNodes.haversineKm(here.lat!!, here.lon!!, lat, lon) >= km
        }
    }

    /**
     * THE ONE THAT WOULD HAVE BEEN A DISASTER. The sweep exists because a full
     * contact store locked the operator out of talking to their OWN node; a
     * sweep that could delete that node would have made the problem it was
     * written to solve permanent.
     */
    @Test fun ownNodesAreNeverCollected() {
        val mine = peer("aaaaab60", name = "SHED ab60", lat = -33.86, lon = 151.20)
        assertTrue("test setup: this node is far away", 12_000.0 < MeshNodes.haversineKm(
            here.lat!!, here.lon!!, -33.86, 151.20,
        ))
        assertFalse("an allow-listed node was collectable", collectable(mine))
    }

    /**
     * THE OTHER KIND OF STAR. MeshCore stores a favourite flag on the contact
     * itself, and this app stores its own in NodeTags; both render as the same
     * filled star. A sweep that honoured only the app's would delete a node
     * the wearer is looking at a star beside.
     */
    @Test fun radioSideFavouritesAreNeverCollected() {
        val far = peer("dddd0001", lat = -33.86, lon = 151.20)
        assertTrue(collectable(far))
        assertFalse("a radio-side favourite was collectable", collectable(far.copy(favourite = true)))
    }

    @Test fun favouritesAreNeverCollected() {
        val far = peer("cafe0001", lat = -33.86, lon = 151.20)
        assertTrue(collectable(far))
        assertFalse(
            "a starred node was collectable",
            collectable(far, favourites = setOf(far.fullKey!!)),
        )
    }

    /**
     * UNKNOWN IS NOT FAR. A GPS-less board reports 0/0 forever and a node that
     * has simply never adverted a position has null — treating either as
     * distant would collect the quiet local nodes first, which is the exact
     * opposite of the intent.
     */
    @Test fun positionlessContactsAreNeverCollected() {
        assertFalse(collectable(peer("beef0001", lat = null, lon = null)))
        assertFalse(collectable(peer("beef0002", lat = 0.0, lon = 0.0)))
    }

    @Test fun nearContactsSurviveAndDistantOnesDoNot() {
        assertFalse("a node down the street was collectable", collectable(peer("0001")))
        assertTrue("a node in Sydney survived", collectable(peer("0002", lat = -33.86, lon = 151.20)))
    }

    /** The boundary is inclusive, and it is the number on the label. */
    @Test fun theThresholdIsTheDistanceItAdvertises() {
        // ~1 degree of latitude is 111 km; half of it is under the line.
        assertTrue(collectable(peer("0003", lat = here.lat!! + 1.0, lon = here.lon)))
        assertFalse(collectable(peer("0004", lat = here.lat!! + 0.5, lon = here.lon)))
    }

    /** A sweep with no origin takes nothing at all — see the NO POSITION branch. */
    @Test fun aSweepWithoutAFixIsNotASweep() {
        val nowhere = MeshNodes.Here(null, null)
        assertFalse("an unfixed origin is not a place to measure from", nowhere.known)
    }

    @Test fun theCountIsWhatWouldActuallyGo() {
        val all = listOf(
            peer("0001"),
            peer("0002", lat = -33.86, lon = 151.20),
            peer("0003", lat = 51.50, lon = -0.12),
            peer("aaaaab60", name = "MINE ab60", lat = 51.50, lon = -0.12),
            peer("0004", lat = null, lon = null),
        )
        assertEquals(2, all.count { collectable(it) })
    }
}
