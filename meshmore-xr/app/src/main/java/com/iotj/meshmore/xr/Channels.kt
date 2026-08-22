// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import io.iotone.meshcore.MeshcoreConstants
import io.iotone.meshcore.crypto.ChannelCrypto
import java.security.SecureRandom

/**
 * MAKING A CHANNEL WITH NO KEYBOARD, NO CAMERA, AND NO SCREEN ANYONE ELSE CAN
 * SEE.
 *
 * A MeshCore channel is a name and a 16-byte key in one of the radio's slots.
 * Two radios talk when they hold the same key; the name is local decoration and
 * the on-air identity is `SHA256(psk)[0]` (`ChannelCrypto.channelHashFromPsk`).
 * So creating a channel is easy and SHARING it is the whole problem.
 *
 * The phone app solves sharing with a QR code. **That does not port.** These
 * are additive optical see-through glasses: the image is formed in the wearer's
 * eye and there is no external surface to photograph, so a QR shown here is a
 * QR nobody else can ever scan. A randomly-keyed channel created on the glasses
 * would therefore be a channel with exactly one possible member, which is not a
 * channel. There is also no keyboard to type a key into, and no camera path to
 * scan somebody else's.
 *
 * What IS available on a hillside is a human voice. So the key is derived from
 * the name — `SHA256(utf8("#name"))[0..16]`, the same `#hashtag` derivation the
 * phone app offers as `_PskSource.hashtag` — and sharing a channel becomes
 * saying two words out loud. The other person types the tag into Meshmore SNS
 * and their radio derives the identical key.
 *
 * ## What this costs, plainly
 *
 * A derived key is only as strong as the words it came from, and these words
 * come from a list in this file. [WORDS] squared times a hundred is about a
 * quarter of a million tags — enough that nobody stumbles onto yours, nowhere
 * near enough to resist somebody who decides to enumerate them. A hashtag
 * channel is PRIVATE THE WAY AN UNLISTED PHONE NUMBER IS PRIVATE. The surface
 * that offers it says so, in those words, because a wearer who believes it is
 * encrypted-and-secret has been told something false by the shape of the
 * feature.
 *
 * Strong keys stay where they can be distributed: the phone app has dice-roll
 * entropy, hex entry and QR export, and every one of those needs a surface this
 * device does not have. A channel created there arrives here through the radio.
 */
object Channels {

    /**
     * The words a rolled name is built from — five characters at most, because
     * the name has to survive [CHAN_NAME_MAX_LOCAL] AND being said across a
     * trail. Concrete nouns only: things you can picture do not get misheard
     * into each other the way abstractions do, and this list gets read aloud.
     */
    internal val WORDS = listOf(
        "AMBER", "ANVIL", "ARBOR", "ASHES", "BASIN", "BIRCH", "BLUFF", "BRINE",
        "CEDAR", "CHALK", "CLIFF", "COAST", "CRANE", "CREEK", "CROW", "DELTA",
        "DRIFT", "DUNE", "EAGLE", "EMBER", "FERN", "FIELD", "FLINT", "FOX",
        "GLADE", "GORSE", "GRASS", "GROVE", "HAWK", "HEATH", "HERON", "HILL",
        "INLET", "KELP", "LARCH", "LEDGE", "LOON", "MAPLE", "MARSH", "MOSS",
        "OTTER", "PEAK", "PINE", "PLAIN", "QUAIL", "REEF", "RIDGE", "RIVER",
        "SAGE", "SHALE", "SHORE", "SLATE", "STONE", "SWALE", "TARN", "THORN",
        "TIDE", "TROUT", "VALE", "VINE", "WHEAT", "WOLF", "WREN", "YEW",
    )

    /**
     * The longest channel name a [spatial.channelLabel] row can hold. Mirrored
     * from `CHAN_NAME_MAX` rather than imported, because that constant is about
     * a row template and this one is about what we are allowed to CREATE — if
     * the row ever widens, rolled names should not silently widen with it.
     */
    internal const val CHAN_NAME_MAX_LOCAL = 14

    /** Slot 0's stock name and key. */
    const val PUBLIC_NAME = "Public"

    /**
     * A rolled name: two words and two digits, e.g. `PINE-FOX-47`.
     *
     * THE DIGITS ARE NOT DECORATION. Two words out of this list is about three
     * thousand possibilities, which is a number a person could work through by
     * hand in an afternoon. The pair of digits multiplies it by a hundred for
     * the cost of three spoken syllables, and it also breaks the tie when two
     * groups on the same hill both roll PINE-FOX.
     */
    fun roll(rng: java.util.Random = SecureRandom()): String {
        val a = WORDS[rng.nextInt(WORDS.size)]
        var b = WORDS[rng.nextInt(WORDS.size)]
        // Never PINE-PINE: it halves the apparent effort of a guess and it
        // sounds like a stutter when read out.
        while (b == a) b = WORDS[rng.nextInt(WORDS.size)]
        val n = 10 + rng.nextInt(90)
        return "$a-$b-$n"
    }

    /**
     * The tag to say out loud, and the exact string the other person types.
     *
     * Canonical: `#` plus the name, lowercased, hyphens KEPT. The hyphens earn
     * their place — they are what make a spoken "pine fox forty seven" land as
     * three fields rather than one word somebody has to guess the spacing of,
     * and they mean what is on the glasses and what goes into the phone are the
     * same characters.
     */
    fun tagFor(name: String): String = "#" + name.trim().lowercase()

    /**
     * The 16-byte key for a tag, byte-identical to the phone app's hashtag
     * source — `ChannelCrypto.channelPskFromHashtag`, `SHA256(utf8(tag))[0..16]`.
     * Interop is the entire point of deriving it rather than inventing our own.
     */
    fun pskFor(tag: String): ByteArray = ChannelCrypto.channelPskFromHashtag(tag)

    /**
     * SOMEBODY ELSE'S TAG, TAKEN AS LITERALLY AS POSSIBLE.
     *
     * [tagFor] builds the tag this app would have rolled. This is the other
     * direction: a tag that already exists, said or typed by the person whose
     * channel it is, which this app must reproduce BYTE FOR BYTE or the two
     * radios derive different keys and neither ever hears the other.
     *
     * So the only edits are the ones that cannot change the meaning:
     *
     *  - Surrounding whitespace goes. Dictation and a soft keyboard both add
     *    it, and no tag can begin or end with a space anybody could reproduce
     *    on purpose.
     *  - Internal whitespace becomes a hyphen. "#pine fox 47" said aloud is
     *    "#pine-fox-47" written down — the convention [tagFor] already
     *    establishes for rolled names, and what makes a tag sayable at all.
     *  - A leading marker is added if absent, because every tag in the
     *    ecosystem carries one and a wearer saying "soaktest" means "#soaktest".
     *
     * WHAT IS DELIBERATELY NOT DONE IS LOWERCASING. "#Soak" and "#soak" are
     * different channels — the key is SHA-256 over the literal bytes — so
     * folding case here would silently join the wrong band whenever somebody
     * capitalised. [tagFor] lowercases because it is naming a channel this app
     * is inventing; this one is quoting somebody else's.
     */
    fun joinTag(raw: String): String {
        val body = raw.trim().replace(Regex("\\s+"), "-").trimStart('#')
        return "#" + body
    }

    /**
     * The default local NAME for a tag: the tag without its marker.
     *
     * The name is decoration — the radio stores it, the mesh never sees it,
     * and the on-air identity is SHA256(psk)[0]. So a wearer joining somebody
     * else's channel gets a sane label without being asked a second question,
     * and one who wants a different name says so.
     */
    fun nameFor(tag: String): String =
        tag.trimStart('#').take(CHAN_NAME_MAX_LOCAL)

    /** The well-known public key, for the JOIN PUBLIC action. */
    fun publicPsk(): ByteArray = MeshcoreConstants.publicChannelPsk()

    /**
     * Is this a name we could have rolled? Used only to keep the tests honest
     * about the width contract; the radio will accept anything.
     */
    internal fun wellFormed(name: String): Boolean =
        Regex("^[A-Z]{3,5}-[A-Z]{3,5}-[0-9]{2}$").matches(name) &&
            name.length <= CHAN_NAME_MAX_LOCAL
}
