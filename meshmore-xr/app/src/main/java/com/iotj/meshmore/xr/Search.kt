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
     * WHAT IS BEING ASKED FOR — three things, ANDed.
     *
     * "I can't remember the names or UIDs of my friend's nodes" is the report
     * that made this a structure rather than a string, and it is the ordinary
     * case rather than an edge one: a MeshCore name is whatever its owner typed
     * into their radio, a key is 64 hex characters, and neither is something a
     * person recalls about somebody they hiked with once. What they DO remember
     * is that it was a friend, or that it was on that trip.
     *
     * So the wearer's own marks are first-class query terms beside the text. A
     * favourite is a fact about a person, a tag is a fact about a group, and a
     * substring is a fact about a name — three ways of remembering, and the one
     * you have is not always the one the search wants.
     *
     * ANDed rather than ORed. Narrowing is the whole job: a ring showing
     * favourites OR anything matching "rep" is bigger than the one you started
     * from, which is the opposite of what somebody who opened a search wanted.
     */
    data class Query(
        val text: String = "",
        val favourites: Boolean = false,
        val tag: String? = null,
    ) {
        /** Is this narrowing anything at all? */
        val active: Boolean
            get() = normalise(text).isNotEmpty() || favourites || tag != null
    }

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
     * The same, for the full query.
     *
     * The marks arrive as LAMBDAS rather than as a NodeTags. This object stays
     * ignorant of storage and of Android — which is what lets every rule here
     * be tested on a plain JVM, and is the same reason MeshNodes never learned
     * about favourites either.
     */
    fun apply(
        peers: List<MeshNodes.Peer>,
        q: Query,
        isFavourite: (MeshNodes.Peer) -> Boolean,
        tagsOf: (MeshNodes.Peer) -> List<String>,
    ): List<MeshNodes.Peer> {
        if (!q.active) return peers
        return peers.filter { p ->
            if (!matches(p, q.text)) return@filter false
            if (q.favourites && !isFavourite(p)) return@filter false
            // TAGS COMPARE CASE-INSENSITIVELY, because a tag typed at the node
            // and a tag tapped on a chip are the same tag however the keyboard
            // capitalised either of them.
            val t = q.tag
            if (t != null && tagsOf(p).none { it.equals(t, ignoreCase = true) }) return@filter false
            true
        }
    }

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

    /**
     * The same, for the full query — and it must not go quiet when the only
     * term is a mark.
     *
     * A wearer who taps FAVOURITES and has never starred anybody gets an empty
     * ring, and "350 NODES" underneath it would be the app disagreeing with
     * itself. NO MATCH is the true answer whichever term produced it.
     */
    fun summary(matched: Int, total: Int, q: Query): String = when {
        !q.active -> "$total NODES"
        matched == 0 -> "NO MATCH IN $total"
        else -> "$matched OF $total"
    }
}
