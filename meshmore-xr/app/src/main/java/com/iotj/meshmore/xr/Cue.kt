// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.media.AudioManager
import android.media.ToneGenerator
import android.util.Log

/**
 * AUDIBLE CONFIRMATION — the one channel a gesture can use.
 *
 * A pinch on a target confirms itself: the thing you touched moves. A GESTURE
 * has no such feedback. You make a shape at the air and either something happens
 * or it does not, and when it does not you cannot tell which of these failed:
 * the hand was not seen, the shape was not recognised, the recognition did not
 * reach the action, or the action did nothing visible. Four failures, one
 * silence.
 *
 * A sound splits that in half. It fires at RECOGNITION, before the action runs,
 * so hearing it means "the classifier saw the letter" and the remaining question
 * is only whether the action worked. Not hearing it means the problem is
 * upstream of the app's logic entirely. That is the single most useful bit of
 * information available while gestures are unreliable, and it costs one tone.
 *
 * DISTINCT TONES PER OUTCOME, because "I heard something" is much weaker than
 * "I heard the recognition tone rather than the rejection one".
 *
 * ## The nine packs, and what these are not
 *
 * Brief §7 gives every theme an audio pack with a name and a character —
 * "Sonar", "Codec", "Arcade", "Bloom". Those descriptions are of COMPOSED
 * packs: granular textures, breath, a scale that shifts with mesh activity.
 * None of that is here and none of it is pretended.
 *
 * What is here is the SEAM in the right place, filled with the best that
 * ToneGenerator can do. Each pack picks its own tones, lengths and volume from
 * the platform's built-in set, which is enough for nine identities that are
 * audibly different from each other and roughly the right character —
 * TRIBUNAL is low and nearly silent, PURE PHASE is a bright stab, CODEC is a
 * radio click. Swapping in real assets later means replacing [play] and
 * nothing else; every call site already says WHICH EVENT rather than which
 * sound, which is the part that is expensive to change and the part that is
 * already right.
 *
 * The alternative was one beep for all nine themes with a comment promising
 * better, which is what was here before, and which makes eight of the nine
 * themes silent about their own identity.
 */
class Cue {

    /**
     * One theme's sonic identity.
     *
     * [vol] is 0..100 into ToneGenerator. It varies per pack on purpose:
     * "near-silence otherwise" is TRIBUNAL's actual spec and a pack that is
     * quiet is a design choice rather than a broken one.
     */
    class Pack(
        val key: String,
        val recognised: Int,
        val recognisedMs: Int,
        val opened: Int,
        val openedMs: Int,
        val tick: Int,
        val tickMs: Int,
        val closed: Int,
        val closedMs: Int,
        val vol: Int = 70,
    )

    companion object {
        private const val TAG = "MeshmoreXR"

        /**
         * SONAR — HALO FIELD. A soft ping, sparse by design so it survives
         * eight hours outdoors without fatigue.
         */
        val SONAR = Pack(
            "sonar",
            ToneGenerator.TONE_PROP_BEEP, 90,
            ToneGenerator.TONE_PROP_BEEP2, 120,
            ToneGenerator.TONE_PROP_ACK, 30,
            ToneGenerator.TONE_PROP_NACK, 140,
        )

        /** MISSION CONTROL — NERV. Data chirps and a three-tone alert cadence. */
        val MISSION = Pack(
            "mission",
            ToneGenerator.TONE_CDMA_ABBR_ALERT, 100,
            ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 150,
            ToneGenerator.TONE_CDMA_PIP, 30,
            ToneGenerator.TONE_SUP_ERROR, 180,
            vol = 78,
        )

        /** VELOCITY — AG-SYSTEMS. Confident and glossy; a race-start triad. */
        val VELOCITY = Pack(
            "velocity",
            ToneGenerator.TONE_CDMA_HIGH_SLS, 90,
            ToneGenerator.TONE_CDMA_ANSWER, 140,
            ToneGenerator.TONE_CDMA_PIP, 25,
            ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 170,
            vol = 76,
        )

        /**
         * TRIBUNAL — SEELE. "Deep resonant strikes for critical events, and
         * near-silence otherwise." The quietest pack in the set, and the low
         * PBX tone is the deepest thing the platform offers.
         */
        val TRIBUNAL = Pack(
            "tribunal",
            ToneGenerator.TONE_CDMA_LOW_PBX_L, 110,
            ToneGenerator.TONE_CDMA_LOW_PBX_SS, 190,
            ToneGenerator.TONE_CDMA_LOW_PBX_L, 25,
            ToneGenerator.TONE_CDMA_LOW_PBX_SLS, 220,
            vol = 52,
        )

        /** PURE PHASE — DR POP. Y2K stabs. The loudest and most musical. */
        val PUREPHASE = Pack(
            "purephase",
            ToneGenerator.TONE_DTMF_D, 80,
            ToneGenerator.TONE_DTMF_A, 130,
            ToneGenerator.TONE_DTMF_1, 25,
            ToneGenerator.TONE_DTMF_S, 150,
            vol = 82,
        )

        /**
         * CODEC — RECON AMBER. Squelch bursts and morse-adjacent clicks.
         * "Monochrome sound to match monochrome light", so every event is the
         * same voice at a different length.
         */
        val CODEC = Pack(
            "codec",
            ToneGenerator.TONE_SUP_RADIO_ACK, 80,
            ToneGenerator.TONE_SUP_RADIO_NOTAVAIL, 120,
            ToneGenerator.TONE_CDMA_KEYPAD_VOLUME_KEY_LITE, 20,
            ToneGenerator.TONE_SUP_RADIO_NOTAVAIL, 180,
            vol = 66,
        )

        /**
         * ARCADE — VECTORLINE. Every interaction a note on a scale. Four DTMF
         * rows are four pitches, which is as close to "quantized to a scale" as
         * this gets without assets.
         */
        val ARCADE = Pack(
            "arcade",
            ToneGenerator.TONE_DTMF_5, 70,
            ToneGenerator.TONE_DTMF_9, 110,
            ToneGenerator.TONE_DTMF_3, 22,
            ToneGenerator.TONE_DTMF_0, 150,
            vol = 74,
        )

        /** BLOOM — BIOLUME. Soft chimes, the least fatiguing pack. */
        val BLOOM = Pack(
            "bloom",
            ToneGenerator.TONE_CDMA_ANSWER, 100,
            ToneGenerator.TONE_CDMA_NETWORK_USA_RINGBACK, 160,
            ToneGenerator.TONE_CDMA_PIP, 22,
            ToneGenerator.TONE_CDMA_ONE_MIN_BEEP, 190,
            vol = 60,
        )

        /** TELETYPE — TERMINAL VOID. Mechanical clacks, a real BEL. Lo-fi on purpose. */
        val TELETYPE = Pack(
            "teletype",
            ToneGenerator.TONE_PROP_ACK, 40,
            ToneGenerator.TONE_PROP_PROMPT, 80,
            ToneGenerator.TONE_PROP_ACK, 15,
            ToneGenerator.TONE_SUP_ERROR, 160,
            vol = 72,
        )

        val PACKS = listOf(
            SONAR, MISSION, VELOCITY, TRIBUNAL, PUREPHASE, CODEC, ARCADE, BLOOM, TELETYPE,
        )

        /**
         * A theme's pack by name, falling back to SONAR.
         *
         * Falls back rather than throwing: a theme with a typo'd pack name
         * should sound like the default, not take the audio path down.
         *
         * PURE, AND DELIBERATELY SILENT ABOUT THE FALLBACK. The obvious thing
         * is a warning here, and the first version had one — but a fallback
         * only reachable through a typo in a table that ships compiled does not
         * want a log line noticed at 3 a.m. on a headset, it wants a test.
         * `CuePackTest.everyThemesPackExists` walks every theme against every
         * pack and fails the build, which is a stronger guarantee and an
         * earlier one. Keeping this pure also keeps it callable from a JVM test
         * at all: android.util.Log is not mocked there and a warning would make
         * this function throw in exactly the case it exists to survive.
         */
        fun packFor(key: String): Pack = PACKS.firstOrNull { it.key == key } ?: SONAR
    }

    private var gen: ToneGenerator? = null
    private var genVol: Int = -1

    /**
     * The pack in force. Set on a theme change, including a picker PREVIEW —
     * §S11 asks that you "hear the theme's audio pack fire on a sample event",
     * and a picker that restyles the world silently is showing you two thirds
     * of what you are choosing.
     */
    var pack: Pack = SONAR
        set(value) {
            if (field.key == value.key) return
            field = value
            // The generator carries the volume, so a pack that is quieter than
            // the last one needs a new one. Released rather than kept: two live
            // ToneGenerators on the same stream is a way to find out that this
            // device only has so many.
            if (genVol != value.vol) {
                runCatching { gen?.release() }
                gen = null
            }
            Log.i(TAG, "[cue] pack -> ${value.key}")
        }

    private fun tone(): ToneGenerator? {
        gen?.let { return it }
        // A missing or busy audio path must not take a gesture down with it.
        val t = runCatching { ToneGenerator(AudioManager.STREAM_MUSIC, pack.vol) }
            .onFailure { Log.w(TAG, "[cue] no tone generator: ${it.javaClass.simpleName}") }
            .getOrNull()
        gen = t
        genVol = pack.vol
        return t
    }

    /** A letter was recognised. Fires BEFORE the action, on purpose. */
    fun recognised() = play(pack.recognised, pack.recognisedMs)

    /** A surface opened. Higher and shorter than a rejection. */
    fun opened() = play(pack.opened, pack.openedMs)

    /**
     * A DETENT PASSED — one notch of a continuous control.
     *
     * Deliberately the shortest and least eventful of these. A reel turned
     * through six slots fires this six times in about a second, and a tone
     * that is satisfying once is intolerable at that rate; this one has to
     * disappear into the gesture rather than announce it.
     */
    fun tick() = play(pack.tick, pack.tickMs)

    /** A surface closed, or an action declined. */
    fun closed() = play(pack.closed, pack.closedMs)

    /**
     * WHAT THIS PACK SOUNDS LIKE, on demand.
     *
     * The picker's sample event. Deliberately the OPEN tone rather than a
     * separate demo sound: a demo that plays something the app never plays is a
     * demo of nothing, and the point is to let somebody choose a pack they will
     * be hearing all day.
     */
    fun sample() = play(pack.opened, pack.openedMs)

    private fun play(id: Int, ms: Int) {
        runCatching { tone()?.startTone(id, ms) }
            .onFailure { Log.w(TAG, "[cue] tone failed: ${it.javaClass.simpleName}") }
    }

    fun release() {
        runCatching { gen?.release() }
        gen = null
        genVol = -1
    }
}
