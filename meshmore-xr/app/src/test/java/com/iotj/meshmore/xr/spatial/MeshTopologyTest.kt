// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The topology resolver. Pure, so every claim it makes about what an edge
 * MEANS can be argued here rather than on the glasses — which matters more
 * than usual, because an edge is a statement about how the network is held
 * together and a wrong one is not visibly wrong.
 */
class MeshTopologyTest {

    private val self = "00aabbcc"

    private fun peer(
        key: String,
        type: Int = Horizon.TYPE_CHAT,
        path: List<Int>? = null,
        flood: Boolean = false,
    ) = MeshNodes.Peer(
        key = key, name = key, type = type, hops = 1,
        lat = null, lon = null, lastSeenEpochSec = 0L, path = path, flood = flood,
    )

    private fun repeater(key: String, path: List<Int>? = emptyList()) =
        peer(key, type = Horizon.TYPE_REPEATER, path = path)

    @Test fun `an empty path is a direct neighbour`() {
        val g = MeshTopology.resolve(self, listOf(peer("11aa", path = emptyList())))
        assertEquals(1, g.census.direct)
        assertEquals(
            listOf(MeshTopology.Edge(self, "11aa", MeshTopology.Kind.DIRECT)),
            g.edges,
        )
    }

    @Test fun `a flood peer is reachable but its route is not pinned`() {
        val g = MeshTopology.resolve(self, listOf(peer("11aa", flood = true)))
        assertEquals(1, g.census.flood)
        assertEquals(MeshTopology.Kind.FLOOD, g.edges.single().kind)
        assertEquals(0, g.census.floaters)
    }

    /** Advert-only: we know it exists and not where it sits. */
    @Test fun `no path and no flood is a floater with no edge`() {
        val g = MeshTopology.resolve(self, listOf(peer("11aa", path = null)))
        assertEquals(listOf("11aa"), g.floaters)
        assertTrue(g.edges.isEmpty())
    }

    @Test fun `a resolved chain becomes self to relay to peer`() {
        val g = MeshTopology.resolve(
            self,
            listOf(repeater("a1ffff"), peer("22bb", path = listOf(0xA1))),
        )
        assertEquals(1, g.census.relayed)
        // The repeater is a direct neighbour in this fixture, so self→R is
        // DIRECT rather than RELAY — one edge per pair, strongest claim wins.
        assertEquals(
            listOf(
                MeshTopology.Edge(self, "a1ffff", MeshTopology.Kind.DIRECT),
                MeshTopology.Edge("a1ffff", "22bb", MeshTopology.Kind.RELAY),
            ),
            g.edges,
        )
    }

    /** A relay we cannot reach directly is still a relay. */
    @Test fun `a relay that is not a neighbour keeps the relay kind`() {
        val g = MeshTopology.resolve(
            self,
            listOf(repeater("a1ffff", path = null), peer("22bb", path = listOf(0xA1))),
        )
        assertEquals(
            MeshTopology.Kind.RELAY,
            g.edges.single { it.fromKey == self && it.toKey == "a1ffff" }.kind,
        )
    }

    /** Many peers behind one repeater must not redraw the first hop. */
    @Test fun `a shared first hop is drawn once`() {
        val g = MeshTopology.resolve(
            self,
            listOf(
                repeater("a1ffff"),
                peer("22bb", path = listOf(0xA1)),
                peer("33cc", path = listOf(0xA1)),
            ),
        )
        assertEquals(1, g.edges.count { it.toKey == "a1ffff" })
        assertEquals(2, g.census.relayed)
    }

    /**
     * THE LOSSY BIT. A path stores one byte per hop, so two repeaters sharing
     * a first byte cannot be told apart — and the resolver must say so rather
     * than pick the one it happened to see first.
     */
    @Test fun `two repeaters sharing a first byte make the hop ambiguous`() {
        val g = MeshTopology.resolve(
            self,
            listOf(
                repeater("a1ffff"), repeater("a1eeee"),
                peer("22bb", path = listOf(0xA1)),
            ),
        )
        assertEquals(1, g.census.firstByteCollisions)
        assertEquals(1, g.census.ambiguousHops)
        assertEquals(0, g.census.relayed)
        assertTrue("the peer cannot be placed", g.floaters.contains("22bb"))
        assertTrue(g.edges.any { it.kind == MeshTopology.Kind.AMBIGUOUS })
    }

    /**
     * A hop we cannot name breaks the REST of the chain, not just itself: the
     * next byte is relative to a relay we did not identify, so claiming the
     * link after it would be inventing an edge.
     */
    @Test fun `an unknown hop truncates the chain and floats the peer`() {
        val g = MeshTopology.resolve(
            self,
            listOf(repeater("a1ffff"), peer("22bb", path = listOf(0x77, 0xA1))),
        )
        assertEquals(1, g.census.unresolvedHops)
        assertEquals(0, g.census.relayed)
        assertTrue(g.floaters.contains("22bb"))
        assertTrue(
            "no edge may be claimed past an unnamed hop",
            g.edges.none { it.toKey == "22bb" },
        )
    }

    /** Only repeaters can be path hops, so only they can collide. */
    @Test fun `chat nodes do not create collisions`() {
        val g = MeshTopology.resolve(
            self,
            listOf(
                repeater("a1ffff"), peer("a1eeee"),
                peer("22bb", path = listOf(0xA1)),
            ),
        )
        assertEquals(0, g.census.firstByteCollisions)
        assertEquals(1, g.census.relayed)
    }

    @Test fun `the census counts every peer exactly once`() {
        val peers = listOf(
            peer("11aa", path = emptyList()),
            peer("22bb", flood = true),
            peer("33cc", path = null),
            repeater("a1ffff"),
            peer("44dd", path = listOf(0xA1)),
        )
        val c = MeshTopology.resolve(self, peers).census
        assertEquals(5, c.peers)
        assertEquals(c.peers, c.direct + c.flood + c.floaters + c.relayed)
    }
}
