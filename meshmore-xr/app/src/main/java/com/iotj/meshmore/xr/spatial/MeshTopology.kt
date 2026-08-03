// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

/**
 * WHO ROUTES THROUGH WHOM — the mesh as a graph rather than as a compass.
 *
 * Step 1 of `MeshmoreXR-topology-spec.md`: the data, and a census of it. The
 * spec puts this first on purpose, because the whole surface rests on a number
 * nobody has measured — what fraction of a real mesh has a route we can
 * actually resolve. SNS's field note says the answer is "not much":
 *
 *   in practice almost every MeshCore contact is flood-routed, so a lower
 *   default shows only the handful of direct/repeater peers (the "3 nodes"
 *   surprise)
 *
 * PURE, so the argument can be had without a device. Everything hard here is a
 * claim about what an edge means, and claims are what tests are for.
 *
 * THE RESOLUTION IS LOSSY AND THE CODE SAYS SO. A stored path is a sequence of
 * ONE BYTE per hop — the first byte of a repeater's public key — so two
 * repeaters sharing a first byte are indistinguishable inside a path. SNS
 * builds a first-byte map and marks collisions ambiguous rather than picking a
 * winner; so does this. The brief forbids inventing a peer's position, and an
 * invented edge is the same offence against a different field.
 */
object MeshTopology {

    /** How we know about a link, which is not the same as how good it is. */
    enum class Kind {
        /** One hop: the contact stores an empty path. */
        DIRECT,
        /** A resolved relay in a stored path. */
        RELAY,
        /** Reachable, but the route is not pinned. Drawn dashed. */
        FLOOD,
        /** A path byte matched more than one known repeater. */
        AMBIGUOUS,
    }

    data class Edge(val fromKey: String, val toKey: String, val kind: Kind) {
        /**
         * Identity is the PAIR, not the pair and the kind.
         *
         * A repeater is usually a direct neighbour AND a hop in other peers'
         * paths, so keying on the kind too emitted self→R twice: once DIRECT,
         * once RELAY. Both statements are true and drawing them as two links
         * is a lie about the shape of the network, which is the one thing this
         * surface exists to tell the truth about. Caught by the tests before it
         * was ever drawn.
         */
        val dedupKey: String get() = "$fromKey|$toKey"
    }

    /**
     * What the mesh could be resolved into.
     *
     * [floaters] are peers we know exist and cannot place: no stored path and
     * not flood-routed. They are not a failure to report — "we know they are
     * there and not where they sit" is the honest state and the spec requires
     * it to be drawn as such.
     */
    data class Graph(
        val edges: List<Edge>,
        val floaters: List<String>,
        val census: Census,
    )

    /** The number the whole surface rests on. */
    data class Census(
        val peers: Int,
        val direct: Int,
        val relayed: Int,
        val flood: Int,
        val floaters: Int,
        val ambiguousHops: Int,
        val unresolvedHops: Int,
        val repeaters: Int,
        val firstByteCollisions: Int,
    ) {
        /** Peers whose route we can actually draw as a chain. */
        val resolvable: Int get() = direct + relayed

        override fun toString(): String =
            "peers=$peers resolvable=$resolvable (direct=$direct relayed=$relayed) " +
                "flood=$flood floaters=$floaters | repeaters=$repeaters " +
                "collisions=$firstByteCollisions ambiguousHops=$ambiguousHops " +
                "unresolvedHops=$unresolvedHops"
    }

    /** MeshCore's sentinel: this contact is reached by flooding, not a path. */
    const val PATH_LEN_FLOOD = 0xFF

    /**
     * Build the graph from [peers], rooted at [selfKey].
     *
     * A peer's [MeshNodes.Peer.path] is null when nothing is known (advert
     * only), empty when the contact is a direct neighbour, and otherwise the
     * ordered first-bytes of the relays between us and them.
     */
    fun resolve(selfKey: String, peers: List<MeshNodes.Peer>): Graph {
        // FIRST-BYTE MAP, over REPEATERS only. A path hop is a repeater by
        // construction, so including chat nodes would invent collisions that
        // cannot occur and suppress edges that are actually unambiguous.
        val repeaters = peers.filter { it.type == Horizon.TYPE_REPEATER }
        val byFirstByte = HashMap<Int, MeshNodes.Peer>()
        val ambiguous = HashSet<Int>()
        repeaters.forEach { r ->
            val b = firstByte(r.key) ?: return@forEach
            if (byFirstByte.containsKey(b)) ambiguous += b else byFirstByte[b] = r
        }

        val edges = LinkedHashMap<String, Edge>()
        val floaters = mutableListOf<String>()
        var direct = 0; var relayed = 0; var flood = 0
        var ambiguousHops = 0; var unresolvedHops = 0

        peers.forEach { p ->
            if (p.key == selfKey) return@forEach
            val path = p.path
            when {
                p.flood -> {
                    flood++
                    add(edges, Edge(selfKey, p.key, Kind.FLOOD))
                }
                path == null -> floaters += p.key
                path.isEmpty() -> {
                    direct++
                    add(edges, Edge(selfKey, p.key, Kind.DIRECT))
                }
                else -> {
                    // Walk the chain: self -> r0 -> r1 -> ... -> peer. A hop we
                    // cannot name breaks the chain, and the REST of it is then
                    // unknowable — you cannot skip a relay and claim the next
                    // link, because the next byte is relative to a hop you did
                    // not identify.
                    var from = selfKey
                    var broke = false
                    path.forEach { b ->
                        if (broke) return@forEach
                        when {
                            b in ambiguous -> {
                                ambiguousHops++
                                add(edges, Edge(from, "?$b", Kind.AMBIGUOUS))
                                broke = true
                            }
                            !byFirstByte.containsKey(b) -> {
                                unresolvedHops++
                                broke = true
                            }
                            else -> {
                                val r = byFirstByte.getValue(b)
                                add(edges, Edge(from, r.key, Kind.RELAY))
                                from = r.key
                            }
                        }
                    }
                    if (broke) {
                        floaters += p.key
                    } else {
                        relayed++
                        add(edges, Edge(from, p.key, Kind.RELAY))
                    }
                }
            }
        }

        return Graph(
            edges = edges.values.toList(),
            floaters = floaters,
            census = Census(
                peers = peers.count { it.key != selfKey },
                direct = direct, relayed = relayed, flood = flood,
                floaters = floaters.size,
                ambiguousHops = ambiguousHops, unresolvedHops = unresolvedHops,
                repeaters = repeaters.size, firstByteCollisions = ambiguous.size,
            ),
        )
    }

    /**
     * Keep one edge per pair, preferring the STRONGER claim.
     *
     * DIRECT beats RELAY: "I can reach it in one hop" is a fact about our own
     * radio, where "it appears in someone's path" is a fact about theirs.
     */
    private fun add(into: LinkedHashMap<String, Edge>, e: Edge) {
        val had = into[e.dedupKey]
        if (had == null || (e.kind == Kind.DIRECT && had.kind != Kind.DIRECT)) {
            into[e.dedupKey] = e
        }
    }

    /** The first byte of a hex public key, or null if it is not one. */
    fun firstByte(keyHex: String): Int? =
        keyHex.take(2).takeIf { it.length == 2 }?.toIntOrNull(16)
}
