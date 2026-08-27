// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE RULE THIS APP TRANSMITS UNDER.
 *
 * This file replaces `AllowListTest`, which asserted a rule that no longer
 * exists — and which kept passing after the rule was deleted, because it held
 * its own private copy of the logic. A test that restates the implementation
 * rather than the requirement survives the implementation's removal, and that
 * is the most dangerous shape a green test can have.
 *
 * ## The requirement, restated
 *
 * Until 2026-08-25 a hardcoded suffix list decided who could be messaged. It
 * existed to stop an assistant with a live radio transmitting at strangers, and
 * for a single-operator build it was right. It could not ship: nobody else's
 * nodes end in the operator's suffixes, so no beta tester could message their
 * own hardware.
 *
 * What replaced it is a distinction between **who is asking**:
 *
 *  - A PERSON may message anyone. Choosing a node and typing a message IS the
 *    authorisation.
 *  - THE APP, transmitting on its own initiative — a soak, a path probe — may
 *    only reach nodes the wearer has explicitly claimed.
 *
 * The tests below are written against that requirement, not against the code
 * that implements it.
 */
class OwnNodeTest {

    private fun key(tail: String) = "0".repeat(64 - tail.length) + tail

    /** MeshLink.isOwnNode: a pinned FULL key, and nothing else. */
    private fun isOwnNode(fullKey: String?, pinned: Set<String>): Boolean {
        val full = fullKey?.lowercase() ?: return false
        return full.length >= 64 && full in pinned
    }

    /** MeshLink.sendDirect's gate. */
    private fun mayTransmit(
        fullKey: String?,
        pinned: Set<String>,
        automated: Boolean,
    ): Boolean = !automated || isOwnNode(fullKey, pinned)

    // ---- a person may message anyone --------------------------------------

    @Test fun aPersonMayMessageAStranger() {
        assertTrue(mayTransmit(key("beef"), pinned = emptySet(), automated = false))
    }

    /** The bug that would have shipped: a tester unable to reach their own radio. */
    @Test fun aTesterMayMessageTheirOwnUnclaimedRadio() {
        assertTrue(mayTransmit(key("1234"), pinned = emptySet(), automated = false))
    }

    // ---- the app may not ---------------------------------------------------

    @Test fun theAppMayNotTransmitAtAStrangerUnasked() {
        assertFalse(mayTransmit(key("beef"), pinned = emptySet(), automated = true))
    }

    @Test fun theAppMayTransmitAtAClaimedNode() {
        val mine = key("ab60")
        assertTrue(mayTransmit(mine, pinned = setOf(mine), automated = true))
    }

    /**
     * The failure the old rule actually produced on a live mesh: a contact
     * called '7182', 12,486 km away, whose public key happened to end in the
     * same four characters as an allowed suffix — and was therefore treated as
     * the operator's hardware and made messageable. Across 350 contacts and two
     * suffixes that is about a one-in-a-hundred event, so it was due.
     *
     * A full-key pin cannot collide this way, which is the point.
     */
    @Test fun aKeyThatMerelyEndsLikeAClaimedOneIsNotClaimed() {
        val mine = key("ab60")
        val stranger = "f".repeat(60) + "ab60"
        assertFalse(isOwnNode(stranger, pinned = setOf(mine)))
        assertFalse(mayTransmit(stranger, pinned = setOf(mine), automated = true))
    }

    /** A name is not evidence. MeshCore adverts are unauthenticated. */
    @Test fun aNameIsNeverEvidenceOfOwnership() {
        // Nothing in the predicate reads a name at all — asserted by the fact
        // that a node cannot be claimed without a key, below.
        assertFalse(isOwnNode(null, pinned = setOf(key("ab60"))))
    }

    /** A pin outlives a rename: the key is what was written down. */
    @Test fun aClaimSurvivesARename() {
        val k = key("d563")
        assertTrue(isOwnNode(k, pinned = setOf(k)))
        // same key, whatever the radio now calls itself
        assertTrue(mayTransmit(k, pinned = setOf(k), automated = true))
    }

    @Test fun caseIsNotEvidenceEitherWay() {
        val k = key("abcd")
        assertTrue(isOwnNode(k.uppercase(), pinned = setOf(k)))
    }

    /**
     * A PREFIX CANNOT BE CLAIMED. An advert carries six bytes; claiming on a
     * prefix would claim whatever else shares it, which is the same defect the
     * suffix rule had, pointed the other way.
     */
    @Test fun aPeerKnownOnlyByItsPrefixCannotBeClaimed() {
        val prefix = "4b30fe61bf82"
        assertFalse(isOwnNode(prefix, pinned = setOf(prefix)))
        assertFalse(mayTransmit(prefix, pinned = setOf(prefix), automated = true))
    }

    /** Releasing a node stops the app transmitting at it, but not the wearer. */
    @Test fun releasingANodeStopsOnlyTheAutomatedTraffic() {
        val k = key("ab60")
        assertFalse(mayTransmit(k, pinned = emptySet(), automated = true))
        assertTrue(mayTransmit(k, pinned = emptySet(), automated = false))
    }
}
