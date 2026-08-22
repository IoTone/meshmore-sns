// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import io.iotone.meshcore.crypto.ChannelCrypto
import java.util.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * MAKING A CHANNEL THAT SOMEBODY ELSE CAN ACTUALLY JOIN.
 *
 * Everything here is about one failure: the wearer makes a channel, reads the
 * tag out to the person next to them, that person types it into the phone app,
 * and the two radios derive DIFFERENT keys. Nothing reports that. Both sides
 * see a channel with the right name in the right slot, and each hears silence
 * from the other forever.
 */
class ChannelsTest {

    /**
     * THE INTEROP VECTOR, from `ChannelCrypto`'s own documentation and the
     * phone app's `channel_crypto_test.dart`: `#test` derives
     * `9cd8fcf22a47333b591d96a2b848b73f`. If this ever changes, a channel made
     * on the glasses stops being joinable from the phone.
     */
    @Test fun theKeyIsTheSameKeyTheOtherAppsDerive() {
        val psk = Channels.pskFor("#test")
        assertEquals(
            "9cd8fcf22a47333b591d96a2b848b73f",
            psk.joinToString("") { "%02x".format(it) },
        )
        assertEquals(16, psk.size)
    }

    /** And it is the library's derivation, not a reimplementation of it. */
    @Test fun weDoNotRollOurOwn() {
        val tag = Channels.tagFor("PINE-FOX-47")
        assertTrue(
            Channels.pskFor(tag).contentEquals(ChannelCrypto.channelPskFromHashtag(tag)),
        )
    }

    /**
     * CASE IS PART OF THE KEY. The tag is hashed as literal UTF-8 bytes, so
     * `#PINE-FOX-47` and `#pine-fox-47` are two different channels that look
     * like one — the exact trap this test exists to keep shut. Canonical form
     * is lowercase, and it is what the bay renders, character for character.
     */
    @Test fun caseChangesTheKeySoTheTagIsCanonical() {
        assertEquals("#pine-fox-47", Channels.tagFor("PINE-FOX-47"))
        assertEquals("#pine-fox-47", Channels.tagFor("  pine-Fox-47 "))
        assertNotEquals(
            Channels.pskFor("#pine-fox-47").toList(),
            Channels.pskFor("#PINE-FOX-47").toList(),
        )
    }

    /** The hyphens are part of the string people type; they must survive. */
    @Test fun theTagKeepsItsShape() {
        assertTrue(Channels.tagFor("PINE-FOX-47").contains("-"))
    }

    /**
     * A rolled name has to fit the channel row's 14-character budget, or the
     * bay clips the name a wearer is about to read out — and a clipped name is
     * a tag nobody can retype. Checked over the whole word list rather than
     * over a sample, because a single six-letter word added later is enough to
     * break it.
     */
    @Test fun everyRollableNameFitsTheRow() {
        val worst = Channels.WORDS.maxOf { it.length }
        val longest = "X".repeat(worst) + "-" + "X".repeat(worst) + "-99"
        assertTrue(
            "widest possible roll is ${longest.length} chars: $longest",
            longest.length <= Channels.CHAN_NAME_MAX_LOCAL,
        )
    }

    /** Names are said out loud, so the list holds only speakable words. */
    @Test fun theWordsAreSayable() {
        Channels.WORDS.forEach {
            assertTrue("'$it' is not 3-5 uppercase letters", Regex("^[A-Z]{3,5}$").matches(it))
        }
        assertEquals("duplicate words halve the entropy", Channels.WORDS.size, Channels.WORDS.toSet().size)
    }

    /**
     * A roll is well-formed every time, not usually. Seeded so the failure is
     * reproducible rather than a flake somebody reruns until it passes.
     */
    @Test fun everyRollIsWellFormed() {
        val rng = Random(20260812L)
        repeat(500) {
            val n = Channels.roll(rng)
            assertTrue("'$n' is not a well-formed rolled name", Channels.wellFormed(n))
        }
    }

    /** PINE-PINE reads as a stutter and halves the work of guessing it. */
    @Test fun aRollNeverRepeatsItsOwnWord() {
        val rng = Random(7L)
        repeat(500) {
            val parts = Channels.roll(rng).split("-")
            assertNotEquals(parts[0], parts[1])
        }
    }

    /**
     * THE DIGITS ARE LOAD-BEARING. Two words out of this list is a few thousand
     * possibilities — an afternoon's work by hand. The pair of digits is the
     * hundredfold that makes casual guessing pointless, and it is also what
     * separates two groups on the same hill who roll the same pair.
     */
    @Test fun theNameCarriesItsDigits() {
        val rng = Random(99L)
        repeat(100) {
            val n = Channels.roll(rng)
            val tail = n.substringAfterLast("-")
            assertEquals("'$n' lost its digits", 2, tail.length)
            assertTrue("'$n' is not a two-digit tail", tail.toIntOrNull() != null)
            assertTrue("'$n' has a leading-zero tail", tail.toInt() >= 10)
        }
    }

    /**
     * Rolls differ. A generator that returned the same name to everybody would
     * put every group in the world on one channel while looking exactly like
     * this feature working.
     */
    @Test fun rollsAreNotAllTheSame() {
        val seen = (1..200).map { Channels.roll() }.toSet()
        assertTrue("only ${seen.size} distinct names in 200 rolls", seen.size > 150)
    }

    /** The public action writes the well-known key, not a lookalike. */
    @Test fun thePublicKeyIsTheWellKnownOne() {
        assertTrue(
            Channels.publicPsk()
                .contentEquals(io.iotone.meshcore.MeshcoreConstants.publicChannelPsk()),
        )
        assertEquals(16, Channels.publicPsk().size)
    }

    /**
     * A rolled channel is NOT the public channel — the check the bay uses to
     * decide whether to offer JOIN PUBLIC depends on the two being told apart
     * by key rather than by name.
     */
    @Test fun aRolledChannelIsNotThePublicOne() {
        val psk = Channels.pskFor(Channels.tagFor(Channels.roll()))
        assertTrue(!psk.contentEquals(Channels.publicPsk()))
    }

    // --- joining somebody else's channel -------------------------------------

    /**
     * THE OPERATOR'S OWN REQUIREMENT, 2026-08-22: a channel named "soak" whose
     * key comes from the tag "#soaktest" — a name and a tag that are
     * deliberately NOT the same string.
     *
     * The key is pinned to a literal here rather than recomputed, because a
     * test that derives the expected value the same way the code does would
     * pass even if both were wrong. This value is SHA-256("#soaktest")[0..16]
     * computed independently, and the derivation is the one the phone app
     * publishes a vector for.
     */
    @Test fun theOperatorsSoakChannel() {
        val tag = Channels.joinTag("soaktest")
        assertEquals("#soaktest", tag)
        assertEquals(
            "8ce85dc561fc89088212c2c3e4d306e9",
            Channels.pskFor(tag).joinToString("") { "%02x".format(it) },
        )
    }

    /** The published ecosystem vector, so a change to the derivation is caught. */
    @Test fun theDocumentedHashtagVector() {
        assertEquals(
            "9cd8fcf22a47333b591d96a2b848b73f",
            Channels.pskFor("#test").joinToString("") { "%02x".format(it) },
        )
    }

    /** A tag said aloud arrives with spaces; a tag typed arrives with a marker. */
    @Test fun aTagIsQuotedNotRewritten() {
        assertEquals("#soaktest", Channels.joinTag("  soaktest  "))
        assertEquals("#soaktest", Channels.joinTag("#soaktest"))
        assertEquals("#pine-fox-47", Channels.joinTag("pine fox 47"))
        assertEquals("#pine-fox-47", Channels.joinTag("#pine  fox\t47"))
    }

    /**
     * CASE IS NEVER FOLDED. "#Soak" and "#soak" are different channels, and a
     * join that quietly lowercased would put a wearer on a band the person who
     * gave them the tag is not on — with nothing anywhere saying why.
     */
    @Test fun caseIsPartOfTheChannel() {
        assertEquals("#Soak", Channels.joinTag("Soak"))
        val upper = Channels.pskFor("#Soak").joinToString("") { "%02x".format(it) }
        val lower = Channels.pskFor("#soak").joinToString("") { "%02x".format(it) }
        assertTrue("case must change the key", upper != lower)
    }

    /** The local name is decoration and defaults to the tag without its marker. */
    @Test fun theNameDefaultsToTheTag() {
        assertEquals("soaktest", Channels.nameFor("#soaktest"))
        assertTrue(Channels.nameFor("#" + "x".repeat(40)).length <= 14)
    }

    /**
     * A TAG THAT CANNOT BE READ CANNOT BE CHECKED.
     *
     * The confirm row's footer tells the wearer to check the tag character by
     * character, which is only honest if every character is on the row. Longer
     * tags are refused rather than clipped, because shortening one changes its
     * key silently and would put the wearer on a channel of one.
     */
    @Test fun aTagTooWideToShowIsRefused() {
        assertTrue(Channels.fitsOnARow("#soaktest"))
        assertTrue(Channels.fitsOnARow("#pine-fox-47"))
        assertFalse(Channels.fitsOnARow("#" + "a".repeat(Channels.TAG_MAX_SHOWN)))
        // Kanji are two cells each, so a Japanese tag runs out of row twice as
        // fast — the reason the limit is measured in cells and not characters.
        assertFalse(Channels.fitsOnARow("#" + "設".repeat(11)))
    }
}
