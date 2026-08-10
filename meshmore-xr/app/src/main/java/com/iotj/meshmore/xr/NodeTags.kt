// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.content.Context

/**
 * WHAT THE WEARER SAID ABOUT A NODE — favourites and free-text tags.
 *
 * Ported from Meshmore SNS rather than invented: `node_tags_store.dart` and
 * `favorite_store.dart`, and the semantics below are theirs. Somebody who
 * tagged a repeater "Mt. Hood" on the phone should find the same idea here,
 * spelled the same way.
 *
 * ## Keyed by PUBLIC KEY, never by name
 *
 * SNS keys on `pubKeyHex` and it is the right call for the reason [VoicePrefs]
 * already met: a name is user-supplied, duplicated across radios, and changed
 * on a whim, so a tag that follows the label silently detaches from the thing
 * it was put on. The key is the identity.
 *
 * ## Two sets, orthogonal, as SNS has them
 *
 * A node can be tagged "Mt. Hood Repeater" without being a favourite, and
 * favourited without being tagged. They answer different questions — "this one
 * is mine" and "this one is a kind of thing" — and collapsing them would lose
 * the second.
 *
 * FAVOURITES ARE THIS APP'S, not the radio's. MeshCore has its own
 * `FLAG_FAVOURITE` per contact and [spatial.MeshNodes.Peer] already carries it;
 * SNS keeps a separate app-level set anyway, and so does this. The radio's bit
 * belongs to whoever set it up; the wearer's belongs to the wearer, and the
 * horizon honours either — `MeshNodes.rank` puts favourites first and never
 * clusters one away, which is the most valuable thing either flag can do.
 *
 * ## Storage
 *
 * SNS uses one JSON blob under a single key, on the argument that the dataset
 * is tens of nodes with single-digit tags each. Same reasoning, different
 * spelling: this uses the separator-escaped format [MsgStore] already
 * established here, because it needs no JSON library and therefore works in a
 * plain JVM unit test — which is where the escaping bugs actually get caught.
 */
class NodeTags(private val store: Store) {

    interface Store {
        fun getString(key: String): String?
        fun putString(key: String, value: String?)
    }

    constructor(context: Context) : this(PrefsStore(context))

    private class PrefsStore(context: Context) : Store {
        private val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        override fun getString(key: String) = p.getString(key, null)
        override fun putString(key: String, value: String?) {
            p.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
        }
    }

    /** key -> its tags, in the order they were added. */
    private val tags: LinkedHashMap<String, MutableList<String>> by lazy { loadTags() }
    private val favs: MutableSet<String> by lazy {
        (store.getString(KEY_FAV) ?: "").split(SEP).filter { it.isNotBlank() }.toMutableSet()
    }

    // --- favourites ----------------------------------------------------------

    fun isFavourite(key: String?): Boolean = key != null && norm(key) in favs

    /** Returns the new state, so a toggle can report what it did. */
    fun toggleFavourite(key: String?): Boolean {
        val k = key?.let { norm(it) } ?: return false
        val next = k !in favs
        if (next) favs.add(k) else favs.remove(k)
        store.putString(KEY_FAV, favs.joinToString(SEP))
        return next
    }

    fun favourites(): Set<String> = favs.toSet()

    // --- tags ----------------------------------------------------------------

    fun tagsFor(key: String?): List<String> =
        key?.let { tags[norm(it)]?.toList() } ?: emptyList()

    /**
     * Every tag in use, once each, sorted.
     *
     * Deduplicated CASE-INSENSITIVELY while preserving the case that was typed
     * first — SNS's rule, and the reason is that "Repeater" and "repeater" are
     * the same tag to a person and two rows in a filter list.
     */
    fun allTags(): List<String> {
        val seen = LinkedHashMap<String, String>()
        tags.values.forEach { list ->
            list.forEach { t -> seen.putIfAbsent(t.lowercase(), t) }
        }
        return seen.values.sortedBy { it.lowercase() }
    }

    /** Which nodes carry [tag], matched case-insensitively. For filtering. */
    fun keysWith(tag: String): Set<String> {
        val t = tag.trim().lowercase()
        if (t.isEmpty()) return emptySet()
        return tags.entries
            .filter { (_, list) -> list.any { it.lowercase() == t } }
            .map { it.key }
            .toSet()
    }

    /**
     * Returns false when the tag was blank or already there.
     *
     * Blank is rejected at the door rather than stored and filtered later: an
     * empty tag is invisible in every list it appears in, so a wearer who
     * created one by accident would have no way to see it or remove it.
     */
    fun add(key: String?, tag: String): Boolean {
        val k = key?.let { norm(it) } ?: return false
        val t = tag.trim()
        if (t.isEmpty() || t.contains(SEP) || t.contains(REC)) return false
        val list = tags.getOrPut(k) { mutableListOf() }
        if (list.any { it.equals(t, ignoreCase = true) }) return false
        list.add(t)
        save()
        return true
    }

    fun remove(key: String?, tag: String): Boolean {
        val k = key?.let { norm(it) } ?: return false
        val list = tags[k] ?: return false
        val hit = list.removeAll { it.equals(tag.trim(), ignoreCase = true) }
        // NO TOMBSTONES. SNS drops empty lists on save for the same reason: a
        // node that has had every tag removed should leave no trace, or the
        // blob grows forever with entries that mean nothing.
        if (list.isEmpty()) tags.remove(k)
        if (hit) save()
        return hit
    }

    fun clear(key: String?) {
        val k = key?.let { norm(it) } ?: return
        if (tags.remove(k) != null) save()
    }

    /** True when this node holds anything the wearer would miss. */
    fun hasUserData(key: String?): Boolean =
        isFavourite(key) || tagsFor(key).isNotEmpty()

    // --- storage -------------------------------------------------------------

    private fun save() {
        store.putString(
            KEY_TAGS,
            tags.entries
                .filter { it.value.isNotEmpty() }
                .joinToString(REC) { (k, v) -> k + SEP + v.joinToString(SEP) },
        )
    }

    private fun loadTags(): LinkedHashMap<String, MutableList<String>> {
        val out = LinkedHashMap<String, MutableList<String>>()
        val raw = store.getString(KEY_TAGS) ?: return out
        // CORRUPT MEANS EMPTY, NOT CRASH — SNS's rule, and the right one: a
        // preferences blob from an older build is a thing that will happen, and
        // losing tags is annoying where failing to start is not survivable.
        raw.split(REC).forEach { rec ->
            val parts = rec.split(SEP).filter { it.isNotBlank() }
            if (parts.size >= 2) {
                out[parts[0]] = parts.drop(1).toMutableList()
            }
        }
        return out
    }

    /**
     * Keys are compared lowercase.
     *
     * MeshCore hex is quoted in both cases by different tools, and a tag put on
     * `A1B2` that cannot be found from `a1b2` is a tag that has silently
     * vanished as far as the wearer is concerned.
     */
    private fun norm(key: String) = key.trim().lowercase()

    private companion object {
        const val FILE = "meshmore-nodes"
        const val KEY_TAGS = "tags"
        const val KEY_FAV = "favourites"
        const val SEP = "\u001f"
        const val REC = "\u001e"
    }
}
