// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.MeshNodes

/**
 * FINDING ONE NODE IN THREE HUNDRED AND FIFTY.
 *
 * The horizon draws 24 motes. The radio holds 350 contacts. Those two numbers
 * are the whole reason this exists: the ranker decides which 24, and whatever
 * it decides, the node you are actually looking for is probably not among them.
 * On the mesh this was built against, 77 peers had been heard in the previous
 * ten minutes and 14 of them were drawn.
 *
 * A FILTER IS NOT A SORT. It does not compete with the ranker or try to be
 * cleverer than it — it shrinks the population the ranker chooses from, so that
 * when there are four matches all four are drawn, at their true bearings, in
 * the same ring as everything else. Search here is a way of looking at the
 * mesh, not a list you read instead of it.
 *
 * ## What matches
 *
 * NAME AND KEY, and nothing else. A callsign is what a person says out loud and
 * a key prefix is what they read off a screen when the callsign is duplicated
 * or missing — the two ways a node is identified in practice. Substring rather
 * than prefix, because the interesting part of "Collins View Open RS" is in the
 * middle, and MeshCore names are phrases rather than handles.
 *
 * CASE-INSENSITIVE, and on both sides. Names come off other people's radios in
 * whatever case they typed, and a wearer typing into a soft keyboard gets
 * whatever the IME decides to capitalise.
 */
object Search {

    /** The most a query can usefully be. Longer than any callsign we can draw. */
    const val MAX = 24

    /**
     * Tidied for matching AND for display — one function, so the string shown
     * on the panel is the string being matched against. Two normalisations
     * would eventually disagree and the wearer would be reading a query the
     * filter is not using.
     */
    fun normalise(q: String): String = q.trim().take(MAX)

    /** Is this peer one the wearer is asking for? */
    fun matches(p: MeshNodes.Peer, q: String): Boolean {
        val n = normalise(q)
        if (n.isEmpty()) return true
        val needle = n.lowercase()
        if (p.name.lowercase().contains(needle)) return true
        // THE KEY, and both forms of it. `key` is the short prefix the app
        // shows; `fullKey` is the whole thing, which is what somebody comparing
        // against another app's display will have in front of them. Matching
        // only one of the two would work in exactly half the cases and look
        // like an unreliable search rather than a narrow one.
        if (p.key.lowercase().contains(needle)) return true
        if (p.fullKey?.lowercase()?.contains(needle) == true) return true
        return false
    }

    /**
     * The mesh, narrowed. Order is preserved — the ranker runs after this and
     * is entitled to its own opinion about which of the survivors to draw.
     */
    fun apply(peers: List<MeshNodes.Peer>, q: String): List<MeshNodes.Peer> =
        if (normalise(q).isEmpty()) peers else peers.filter { matches(it, q) }

    /**
     * What the panel says under the field.
     *
     * ZERO IS THE ANSWER THAT MATTERS. A search that finds nothing and says
     * nothing looks identical to a search that has not run, and the wearer's
     * next move — retype it, or accept that the node is not there — depends
     * entirely on knowing which happened.
     */
    fun summary(matched: Int, total: Int, q: String): String = when {
        normalise(q).isEmpty() -> "$total NODES"
        matched == 0 -> "NO MATCH IN $total"
        else -> "$matched OF $total"
    }
}
