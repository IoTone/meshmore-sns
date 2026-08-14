// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.content.Context
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * THE THIRD CHANNEL — touch, from the puck in your hand.
 *
 * The audio-haptics spec (§3) was written to assume H0: "optical see-through
 * glasses in this class generally have no haptic actuator — assume this." The
 * measurement overturned it: the Aura's puck carries a real actuator with
 * COMPOSE_EFFECTS and AMPLITUDE_CONTROL, supporting exactly the
 * `VibrationEffect.Composition` primitives the spec's vocabulary was written
 * in. The system itself already fires it for touch. That is effectively H3 —
 * on-device, sub-10 ms — with one honest caveat: the motor is in the HAND, not
 * on the frame, so it speaks only when the wearer is holding or pocketing the
 * puck.
 *
 * ## What fires, and what deliberately does not
 *
 * Spec §3.2: haptics fire on COMMIT, DENY, SEAT, MSG_DIRECT, LINK and CRITICAL
 * only. Hover and detents are EXCLUDED even though this actuator is fast
 * enough, and the reason is worth keeping: the spec's rule was set for the
 * worst routing tier, and an event vocabulary that changes meaning with the
 * user's hardware is two vocabularies. The triple-cue law wants no channel
 * load-bearing alone — it does not want every channel on every event.
 *
 * ## Failure is silence
 *
 * No actuator (the emulator), a missing primitive, a dead service — every path
 * degrades: composition → predefined effect → one-shot → nothing. A buzz is an
 * augmentation, and an augmentation that can crash the gesture it decorates
 * has its priorities inverted.
 */
class Haptics(context: Context) {

    private val vib: Vibrator? = runCatching {
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
            ?.defaultVibrator?.takeIf { it.hasVibrator() }
    }.getOrNull()

    private val composes: Boolean = runCatching {
        vib?.areAllPrimitivesSupported(
            VibrationEffect.Composition.PRIMITIVE_CLICK,
            VibrationEffect.Composition.PRIMITIVE_TICK,
            VibrationEffect.Composition.PRIMITIVE_THUD,
            VibrationEffect.Composition.PRIMITIVE_QUICK_RISE,
            VibrationEffect.Composition.PRIMITIVE_QUICK_FALL,
        ) == true
    }.getOrDefault(false)

    init {
        Log.i(TAG, "[haptic] actuator=${vib != null} composed=$composes")
    }

    /** E3 COMMIT — a selection confirmed. One clean click. */
    fun click() = compose { addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK) }

    /** E6 SEAT — a control settling into a well. Softer than a commit. */
    fun seat() = compose { addPrimitive(VibrationEffect.Composition.PRIMITIVE_THUD, 0.7f) }

    /**
     * E4 DENY — two fast clicks, deliberately unpleasant (spec §3.3). A denial
     * that feels nice gets retried; one that feels wrong gets rethought.
     */
    fun refuse() = compose {
        addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK)
        addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 1f, 60)
    }

    /** E13 LINK_UP — the radio arrived. */
    fun rise() = compose { addPrimitive(VibrationEffect.Composition.PRIMITIVE_QUICK_RISE) }

    /** E13 LINK_DOWN — and left. The one you need to feel mid-stride. */
    fun fall() = compose { addPrimitive(VibrationEffect.Composition.PRIMITIVE_QUICK_FALL) }

    /**
     * E11 MSG_DIRECT — a "someone wants you" heartbeat: thud, beat, thud.
     * Channel traffic gets NO haptic at all; the difference between a room
     * talking and somebody talking TO YOU is the most valuable thing this
     * channel can carry, and it carries it by existing only for the second.
     */
    fun summon() = compose {
        addPrimitive(VibrationEffect.Composition.PRIMITIVE_THUD)
        addPrimitive(VibrationEffect.Composition.PRIMITIVE_THUD, 1f, 180)
    }

    /**
     * E16 CRITICAL — four full-amplitude clicks. Exempt from every scale and
     * every theme (spec: "a safety signal is not a preference").
     */
    fun alarm() {
        val v = vib ?: return
        runCatching {
            v.vibrate(
                VibrationEffect.createWaveform(
                    longArrayOf(0, 60, 90, 60, 90, 60, 90, 60),
                    intArrayOf(0, 255, 0, 255, 0, 255, 0, 255),
                    -1,
                ),
            )
        }.onFailure { Log.w(TAG, "[haptic] alarm failed: ${it.javaClass.simpleName}") }
    }

    private inline fun compose(block: VibrationEffect.Composition.() -> Unit) {
        val v = vib ?: return
        runCatching {
            if (composes) {
                v.vibrate(VibrationEffect.startComposition().apply(block).compose())
            } else {
                // The degraded rung: a plain click stands in for everything.
                // Wrong texture beats no confirmation, and beats crashing most.
                v.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK))
            }
        }.onFailure { Log.w(TAG, "[haptic] vibrate failed: ${it.javaClass.simpleName}") }
    }

    private companion object {
        const val TAG = "MeshmoreXR"
    }
}
