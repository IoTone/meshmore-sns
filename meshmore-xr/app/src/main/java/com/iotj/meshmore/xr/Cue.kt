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
 * ToneGenerator rather than a shipped sound: no asset, no decode, no latency
 * worth measuring, and this is a confirmation beep rather than a designed audio
 * identity. The themes' audio packs (design brief §7) are a separate concern and
 * will replace this when they land.
 */
class Cue {

    private var gen: ToneGenerator? = null

    private fun tone(): ToneGenerator? {
        gen?.let { return it }
        // A missing or busy audio path must not take a gesture down with it.
        val t = runCatching { ToneGenerator(AudioManager.STREAM_MUSIC, VOLUME) }
            .onFailure { Log.w(TAG, "[cue] no tone generator: ${it.javaClass.simpleName}") }
            .getOrNull()
        gen = t
        return t
    }

    /** A letter was recognised. Fires BEFORE the action, on purpose. */
    fun recognised() = play(ToneGenerator.TONE_PROP_BEEP, 90)

    /** A surface opened. Higher and shorter than a rejection. */
    fun opened() = play(ToneGenerator.TONE_PROP_BEEP2, 120)

    /**
     * A DETENT PASSED — one notch of a continuous control.
     *
     * Deliberately the shortest and least eventful of these. A reel turned
     * through six slots fires this six times in about a second, and a tone
     * that is satisfying once is intolerable at that rate; this one has to
     * disappear into the gesture rather than announce it.
     */
    fun tick() = play(ToneGenerator.TONE_PROP_ACK, 30)

    /** A surface closed, or an action declined. */
    fun closed() = play(ToneGenerator.TONE_PROP_NACK, 140)

    private fun play(id: Int, ms: Int) {
        runCatching { tone()?.startTone(id, ms) }
            .onFailure { Log.w(TAG, "[cue] tone failed: ${it.javaClass.simpleName}") }
    }

    fun release() {
        runCatching { gen?.release() }
        gen = null
    }

    private companion object {
        const val TAG = "MeshmoreXR"
        /** Loud enough to hear on glasses speakers, quiet enough not to startle. */
        const val VOLUME = 70
    }
}
