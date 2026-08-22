// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

/**
 * WHAT EACH EVENT SOUNDS LIKE, AND WHAT EACH THEME SOUNDS LIKE.
 *
 * Two tables, deliberately not one. The event owns the CONTOUR — the shape,
 * which is what a wearer learns and what survives a noisy street. The theme
 * owns the TIMBRE — what it is made of, which is what makes VOID sound like a
 * terminal and BIOLUME like something alive. Multiplying them gives nine
 * identities over one grammar, where a single combined table would give a
 * hundred and forty-four unrelated sounds and no grammar at all.
 *
 * ## The shapes, and why each is that shape
 *
 * Rising means something arrived and is worth turning toward. Falling means
 * something went away, and there is exactly one falling motif — [LOST] — so
 * that a descent is never ambiguous. Repetition means urgent, because
 * repetition is the only prosody that reads as urgent in every language this
 * app ships in. Unpitched means refusal: a thud is categorically not a
 * success, and cannot be mistaken for one at any volume.
 *
 * Frequencies sit between 300 and 1400 Hz. Below that a wearable's speaker has
 * nothing to give; above it, a cue starts competing with speech and with the
 * environment a wearer is supposed to be paying attention to.
 */
object Motifs {

    // --- the mesh speaking, which is what most of these are for --------------

    /**
     * A direct message. Two notes, rising a fourth: the most "spoken to" shape
     * in the set, because it is the one event that is about YOU.
     */
    val DM = Synth.Motif(
        root = 660f,
        steps = listOf(Synth.Step(0, 90), Synth.Step(5, 150)),
    )

    /**
     * A channel message. One note, flat, quieter.
     *
     * §2 requires E10 and E11 to be sonically distinct, and the distinction is
     * not decoration: overheard traffic on a busy channel would otherwise fire
     * the same alert as somebody addressing you by name, several times a
     * minute, until you turned all of it off.
     */
    val CHANNEL = Synth.Motif(
        root = 660f,
        steps = listOf(Synth.Step(0, 110, level = 0.55f)),
    )

    /** Delivered. One short high tick — closure, cheap enough to fire often. */
    val DELIVERED = Synth.Motif(
        root = 990f,
        steps = listOf(Synth.Step(0, 60, level = 0.5f)),
    )

    /**
     * Lost. A falling minor third, and the ONLY descending motif in the set.
     *
     * The reliability work measured this event to the millisecond and had
     * nowhere to say it: a wearer had to open a bay to discover that a message
     * they sent never arrived. Unpleasant on purpose, and short enough not to
     * be a punishment.
     */
    val LOST = Synth.Motif(
        root = 560f,
        steps = listOf(Synth.Step(3, 110), Synth.Step(0, 200)),
    )

    /** A node appeared. Three rising notes — an arrival larger than a message. */
    val NODE_FOUND = Synth.Motif(
        root = 520f,
        steps = listOf(Synth.Step(0, 70), Synth.Step(4, 70), Synth.Step(7, 140)),
    )

    /** And its mirror, so the pair is learned as one fact with two directions. */
    val NODE_LOST = Synth.Motif(
        root = 520f,
        steps = listOf(
            Synth.Step(7, 70, 0.7f), Synth.Step(4, 70, 0.7f), Synth.Step(0, 140, 0.7f),
        ),
    )

    /** The radio linked. Low to high, wide — the biggest good news there is. */
    val LINKED = Synth.Motif(
        root = 390f,
        steps = listOf(Synth.Step(0, 90), Synth.Step(12, 220)),
    )

    /** And dropped: the same interval, downward, slower. */
    val DROPPED = Synth.Motif(
        root = 390f,
        steps = listOf(Synth.Step(12, 90), Synth.Step(0, 320)),
    )

    /**
     * Critical. Three fast repeats of one note.
     *
     * §2.1 makes this the only interrupter and exempts it from the density
     * ceiling. It is the one sound in the app allowed to be unwelcome.
     */
    val CRITICAL = Synth.Motif(
        root = 880f,
        steps = listOf(Synth.Step(0, 70), Synth.Step(0, 70), Synth.Step(0, 140)),
    )

    // --- the app answering a hand -------------------------------------------

    /** Recognised. One soft tick. It fires 32 times a session; it stays small. */
    val RECOGNISED = Synth.Motif(
        root = 740f,
        steps = listOf(Synth.Step(0, 45, level = 0.45f)),
    )

    /**
     * Refused. Unpitched, low, short. Noise, so it cannot read as a note.
     *
     * FULL LEVEL, because measurement said the first draft was the quietest
     * thing in the app in all nine packs — heavily filtered noise carries far
     * less energy than a tone at the same nominal level. A refusal nobody
     * notices is the exact failure [Cue] was written to fix: a gesture that
     * silently did nothing, indistinguishable from a gesture that was never
     * seen.
     */
    val DENIED = Synth.Motif(
        root = 320f,
        steps = listOf(Synth.Step(0, 130, level = 1f)),
    )

    /** A surface arrived. Furniture: 93 of 148 calls, so nearly subliminal. */
    val OPENED = Synth.Motif(
        root = 620f,
        steps = listOf(Synth.Step(0, 40, level = 0.3f)),
    )

    /** And left. The same click, a tone lower. */
    val CLOSED = Synth.Motif(
        root = 560f,
        steps = listOf(Synth.Step(0, 40, level = 0.3f)),
    )

    /**
     * A detent on a reel or rail. The smallest sound the app can make — and it
     * still has to be heard through CODEC's band-limiting, which is what set
     * the level. Smallest is not the same as inaudible.
     */
    val TICK = Synth.Motif(
        root = 820f,
        steps = listOf(Synth.Step(0, 30, level = 0.32f)),
    )

    // --- the nine packs ------------------------------------------------------

    /**
     * One timbre per audio pack, keyed by [spatial.Theme.Skin.audio].
     *
     * The characters come from brief §7 and are read as instrument choices
     * rather than as adjectives: CODEC is band-limited because a radio codec
     * is, TRIBUNAL is nearly silent because that is its stated spec, TELETYPE
     * is a square wave because a terminal's beep was one.
     */
    val PACKS: Map<String, Synth.Timbre> = mapOf(
        // HALO — clean and unremarkable on purpose; the reference.
        "sonar" to Synth.Timbre(Synth.Wave.SINE, detune = 0.004f, bright = 0.6f),
        // NERV — hard, institutional, no width.
        "mission" to Synth.Timbre(Synth.Wave.SQUARE, bright = 0.35f, timeScale = 0.8f, gain = 0.8f),
        // AG-SYSTEMS — the fast one. Bright saw, quick envelopes.
        "velocity" to Synth.Timbre(Synth.Wave.SAW, detune = 0.008f, bright = 0.9f, timeScale = 0.7f),
        // SEELE — one slab of low tone. Nearly silent is its actual spec.
        "tribunal" to Synth.Timbre(Synth.Wave.SINE, bright = 0.25f, timeScale = 1.6f, gain = 0.45f),
        // DR POP — a bright stab.
        "purephase" to Synth.Timbre(Synth.Wave.SQUARE, detune = 0.01f, bright = 1f, timeScale = 0.6f, gain = 0.9f),
        // RECON — band-limited, like the radio it is named after.
        "codec" to Synth.Timbre(Synth.Wave.TRI, bright = 0.3f, timeScale = 0.75f, gain = 0.85f),
        // VECTORLINE — an arcade cabinet: pure, hard, no filter.
        "arcade" to Synth.Timbre(Synth.Wave.SQUARE, bright = 1f, timeScale = 0.65f, gain = 0.85f),
        // BIOLUME — soft, wide, breathing. The slowest envelopes in the set.
        "bloom" to Synth.Timbre(Synth.Wave.TRI, detune = 0.012f, bright = 0.5f, timeScale = 1.5f),
        // VOID — a terminal. Square, dry, quick.
        "teletype" to Synth.Timbre(Synth.Wave.SQUARE, bright = 0.7f, timeScale = 0.7f, gain = 0.8f),
    )

    /** DENIED is noise whatever the pack, because a refusal has no pitch. */
    fun timbreFor(pack: String, motif: Synth.Motif): Synth.Timbre {
        val base = PACKS[pack] ?: PACKS.getValue("sonar")
        // bright 0.45 rather than 0.25: still a thud rather than a hiss, but
        // through enough of the noise to be heard on a small speaker.
        return if (motif === DENIED) base.copy(wave = Synth.Wave.NOISE, bright = 0.45f) else base
    }

    /** Every motif, for the tests that must cover all of them. */
    val ALL: Map<String, Synth.Motif> = mapOf(
        "DM" to DM, "CHANNEL" to CHANNEL, "DELIVERED" to DELIVERED, "LOST" to LOST,
        "NODE_FOUND" to NODE_FOUND, "NODE_LOST" to NODE_LOST, "LINKED" to LINKED,
        "DROPPED" to DROPPED, "CRITICAL" to CRITICAL, "RECOGNISED" to RECOGNISED,
        "DENIED" to DENIED, "OPENED" to OPENED, "CLOSED" to CLOSED, "TICK" to TICK,
    )
}
