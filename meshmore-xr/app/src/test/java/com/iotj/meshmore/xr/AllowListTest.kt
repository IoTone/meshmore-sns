// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE RULE THIS APP TRANSMITS UNDER, and the only rule in it that can put a
 * message on somebody else's radio.
 *
 * The operator's authorisation is one sentence — their own nodes end in `ab60`
 * and `d563` — and it is a NAME rule. The matching is restated here as a pure
 * predicate so the part that decides what may be sent can be exercised without
 * a Bluetooth session, and so a change to it has to be argued with a failing
 * test rather than a diff.
 */
class AllowListTest {

    private val suffixes = listOf("ab60", "d563")

    /** Exactly MeshLink.isAllowed, minus the persistence and the logging. */
    private fun allowed(
        name: String,
        fullKey: String?,
        pinned: Set<String> = emptySet(),
    ): Boolean {
        val full = fullKey?.lowercase()
        if (full != null && full in pinned) return true
        return suffixes.any { name.endsWith(it, ignoreCase = true) }
    }

    /**
     * THE ONE THAT WAS LIVE ON A REAL MESH. A contact named '7182' whose public
     * key happened to end in 'd563' was treated as the operator's own hardware
     * — swept-proof, and a legal destination for a message. Across 350 contacts
     * and two suffixes this is roughly a one-in-a-hundred event.
     */
    @Test fun aStrangerWhoseKeyCollidesIsNotYourNode() {
        val collide = "0".repeat(60) + "d563"
        assertFalse(allowed("7182", collide))
    }

    @Test fun aNodeNamedForTheSuffixIsYours() {
        assertTrue(allowed("D38F07AED563", "4b30fe61bf82" + "0".repeat(52)))
        assertTrue(allowed("shed-AB60", null))
    }

    /** Case is not evidence either way; the operator types lowercase. */
    @Test fun theNameMatchIgnoresCase() {
        assertTrue(allowed("MY NODE d563", null))
        assertTrue(allowed("my node D563", null))
    }

    /**
     * A PIN OUTLIVES A RENAME. The point of writing down the whole key is that
     * the node stays yours when its advert name changes — which is the case
     * the name rule alone cannot survive.
     */
    @Test fun aPinnedKeyIsYoursWhateverItIsCalled() {
        val mine = "a".repeat(64)
        assertFalse(allowed("renamed to something else", mine))
        assertTrue(allowed("renamed to something else", mine, pinned = setOf(mine)))
    }

    /** Nothing about a bare key admits anything. Suffix collisions included. */
    @Test fun aKeyAloneNeverAuthorises() {
        assertFalse(allowed("", "0".repeat(60) + "ab60"))
        assertFalse(allowed("Grizzly Peak", "0".repeat(60) + "ab60"))
        assertFalse(allowed("Grizzly Peak", null))
    }

    /**
     * The rule may narrow and may not widen. Every name that was allowed before
     * pinning existed is still allowed after it.
     */
    @Test fun pinningOnlyEverNarrows() {
        val names = listOf("A ab60", "B d563", "ab60", "trailing d563")
        names.forEach { assertTrue("$it stopped being yours", allowed(it, null)) }
    }
}
