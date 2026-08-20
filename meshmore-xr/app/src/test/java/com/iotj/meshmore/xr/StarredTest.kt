// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.MeshNodes
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * WHO COUNTS AS THE OPERATOR'S OWN NODE.
 *
 * The soak sends ten full-length packets on a shared band, so the answer
 * decides how much airtime a wrong match costs somebody else. The rule was
 * wrong once in exactly the way this file now pins down: an empty key in the
 * peer list made `startsWith` true against every node in the mesh, and the
 * item appeared at a node with no star on it.
 */
class StarredTest {

    private fun peer(key: String, favourite: Boolean = false, full: String? = null) =
        MeshNodes.Peer(
            key = key, name = key, type = 1, hops = 1,
            lat = null, lon = null, lastSeenEpochSec = 1_700_000_000L,
            fullKey = full ?: key.padEnd(64, '0'), favourite = favourite,
        )

    private val mesh = listOf(
        peer("000000610c17", favourite = true),
        peer("aa11bb22cc33"),
        peer("", favourite = true),
    )

    @Test fun theAppsOwnStarIsEnough() {
        assertTrue(MeshLink.isStarred(emptyList(), "deadbeefcafe") { it == "deadbeefcafe" })
    }

    @Test fun theRadiosOwnFlagIsEnough() {
        assertTrue(MeshLink.isStarred(mesh, "000000610c17"))
    }

    @Test fun anUnstarredNodeIsNot() {
        assertFalse(MeshLink.isStarred(mesh, "aa11bb22cc33"))
    }

    /** THE BUG. A blank key must match nothing, in either direction. */
    @Test fun aBlankKeyStarsNobody() {
        assertFalse(MeshLink.isStarred(mesh, "aa11bb22cc33"))
        assertFalse(MeshLink.isStarred(mesh, ""))
        assertFalse(MeshLink.isStarred(mesh, null))
        assertFalse(MeshLink.isStarred(mesh, "   "))
    }

    /** A message carries a prefix; the contact carries the whole key. */
    @Test fun aPrefixOfAStarredKeyStillMatches() {
        assertTrue(MeshLink.isStarred(mesh, "000000610c"))
        assertTrue(MeshLink.isStarred(mesh, "000000610C17".lowercase()))
        assertTrue(MeshLink.isStarred(mesh, "000000610C"))
    }

    /** But not a prefix so short that it would match half the mesh. */
    @Test fun aTooShortPrefixDoesNot() {
        assertFalse(MeshLink.isStarred(mesh, "0000"))
    }
}
