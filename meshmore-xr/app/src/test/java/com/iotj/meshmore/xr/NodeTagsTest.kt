// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Favourites and tags, with SNS's semantics.
 *
 * The tests that matter are the silent ones: a tag that cannot be found because
 * the key was quoted in the other case, a tag list that grows tombstones, and a
 * separator smuggled in through a user-typed string. None of those fails
 * loudly — they present as "my tags disappeared", weeks later.
 */
class NodeTagsTest {

    private class Fake : NodeTags.Store {
        val map = HashMap<String, String>()
        override fun getString(key: String) = map[key]
        override fun putString(key: String, value: String?) {
            if (value == null) map.remove(key) else map[key] = value
        }
    }

    private val A = "a1b2c3d4"
    private val B = "ff00ee11"

    // --- favourites ----------------------------------------------------------

    @Test fun favouritingIsAToggleThatReportsWhatItDid() {
        val t = NodeTags(Fake())
        assertFalse(t.isFavourite(A))
        assertTrue(t.toggleFavourite(A))
        assertTrue(t.isFavourite(A))
        assertFalse(t.toggleFavourite(A))
        assertFalse(t.isFavourite(A))
    }

    @Test fun favouritesSurviveARestart() {
        val store = Fake()
        NodeTags(store).toggleFavourite(A)
        assertTrue(NodeTags(store).isFavourite(A))
    }

    /**
     * MeshCore hex is quoted in both cases by different tools. A favourite set
     * from one and read from the other has silently vanished as far as the
     * wearer is concerned.
     */
    @Test fun keysMatchRegardlessOfCase() {
        val t = NodeTags(Fake())
        t.toggleFavourite("A1B2C3D4")
        assertTrue(t.isFavourite("a1b2c3d4"))
        t.add("A1B2C3D4", "ridge")
        assertEquals(listOf("ridge"), t.tagsFor("a1b2c3d4"))
    }

    // --- tags ----------------------------------------------------------------

    @Test fun tagsAreKeptInTheOrderTheyWereAdded() {
        val t = NodeTags(Fake())
        t.add(A, "ridge"); t.add(A, "repeater"); t.add(A, "mine")
        assertEquals(listOf("ridge", "repeater", "mine"), t.tagsFor(A))
    }

    @Test fun tagsSurviveARestart() {
        val store = Fake()
        NodeTags(store).apply { add(A, "Mt. Hood"); add(B, "shed") }
        val after = NodeTags(store)
        assertEquals(listOf("Mt. Hood"), after.tagsFor(A))
        assertEquals(listOf("shed"), after.tagsFor(B))
    }

    /** SNS's rule: same tag to a person, so the same tag here. */
    @Test fun aTagIsNotAddedTwiceInDifferentCase() {
        val t = NodeTags(Fake())
        assertTrue(t.add(A, "Repeater"))
        assertFalse(t.add(A, "repeater"))
        assertFalse(t.add(A, "  REPEATER  "))
        assertEquals(1, t.tagsFor(A).size)
        // ...and the case the wearer typed is what is kept.
        assertEquals("Repeater", t.tagsFor(A).first())
    }

    @Test fun blankTagsAreRefusedAtTheDoor() {
        val t = NodeTags(Fake())
        assertFalse(t.add(A, ""))
        assertFalse(t.add(A, "   "))
        assertTrue(t.tagsFor(A).isEmpty())
    }

    /**
     * THE SEPARATOR, smuggled in through a user-typed tag. Storage is
     * separator-delimited, so a tag containing one would split into two on the
     * next load — or worse, merge two nodes' lists.
     */
    @Test fun aTagCannotContainTheStorageSeparators() {
        val store = Fake()
        val t = NodeTags(store)
        assertFalse(t.add(A, "ridgetop"))
        assertFalse(t.add(A, "ridgetop"))
        assertTrue(t.tagsFor(A).isEmpty())
    }

    @Test fun removingTheLastTagLeavesNoTombstone() {
        val store = Fake()
        val t = NodeTags(store)
        t.add(A, "ridge")
        assertTrue(t.remove(A, "ridge"))
        assertTrue(t.tagsFor(A).isEmpty())
        // The blob must not keep an entry for a node with nothing on it.
        assertEquals("", store.map["tags"] ?: "")
    }

    @Test fun removingIsCaseInsensitiveAndReportsWhetherItDidAnything() {
        val t = NodeTags(Fake())
        t.add(A, "Ridge")
        assertFalse(t.remove(A, "shed"))
        assertTrue(t.remove(A, "RIDGE"))
    }

    // --- the two queries a filter needs --------------------------------------

    @Test fun allTagsIsTheUnionOnceEachAndSorted() {
        val t = NodeTags(Fake())
        t.add(A, "ridge"); t.add(A, "repeater")
        t.add(B, "Ridge"); t.add(B, "shed")
        assertEquals(listOf("repeater", "ridge", "shed"), t.allTags())
    }

    @Test fun keysWithFindsEveryNodeCarryingATag() {
        val t = NodeTags(Fake())
        t.add(A, "ridge"); t.add(B, "RIDGE"); t.add(B, "shed")
        assertEquals(setOf(A, B), t.keysWith("Ridge"))
        assertEquals(setOf(B), t.keysWith("shed"))
        assertTrue(t.keysWith("nothing").isEmpty())
        assertTrue(t.keysWith("  ").isEmpty())
    }

    // --- the two sets stay orthogonal ----------------------------------------

    /**
     * SNS is explicit that these are separate: "a node can be tagged 'Mt. Hood
     * Repeater' without being a favourite, and vice versa". Collapsing them
     * would lose the second question.
     */
    @Test fun taggingDoesNotFavouriteAndFavouritingDoesNotTag() {
        val t = NodeTags(Fake())
        t.add(A, "ridge")
        assertFalse(t.isFavourite(A))
        t.toggleFavourite(B)
        assertTrue(t.tagsFor(B).isEmpty())
    }

    @Test fun hasUserDataIsTrueForEither() {
        val t = NodeTags(Fake())
        assertFalse(t.hasUserData(A))
        t.add(A, "ridge")
        assertTrue(t.hasUserData(A))
        t.remove(A, "ridge")
        assertFalse(t.hasUserData(A))
        t.toggleFavourite(A)
        assertTrue(t.hasUserData(A))
    }

    /** A blob from an older build must open empty rather than fail to start. */
    @Test fun corruptStorageOpensEmpty() {
        val store = Fake()
        store.putString("tags", "not a real record at all")
        val t = NodeTags(store)
        assertTrue(t.tagsFor(A).isEmpty())
        assertTrue(t.allTags().isEmpty())
        // ...and is still writable afterwards.
        assertTrue(t.add(A, "ridge"))
        assertEquals(listOf("ridge"), NodeTags(store).tagsFor(A))
    }

    @Test fun nullKeysAreHarmless() {
        val t = NodeTags(Fake())
        assertFalse(t.isFavourite(null))
        assertFalse(t.toggleFavourite(null))
        assertFalse(t.add(null, "x"))
        assertTrue(t.tagsFor(null).isEmpty())
    }
}
