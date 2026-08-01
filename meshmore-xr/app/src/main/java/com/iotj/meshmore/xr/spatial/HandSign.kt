// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import androidx.xr.arcore.HandJointType
import androidx.xr.runtime.math.Pose
import kotlin.math.sqrt

/**
 * ASL LETTERS AS QUICK ACTIONS.
 *
 * The Aura reports hand tracking and nothing else — no controller, no eye
 * tracking — so every command has to be a pinch on a target or a shape the hand
 * makes. Pinching a target costs world space and costs a glance: you have to
 * find the thing first. A HAND SHAPE costs neither, which is what makes it the
 * right register for "turn the HUD off", an action you want mid-stride without
 * looking at anything.
 *
 * ASL rather than an invented vocabulary, for three reasons: the shapes are
 * already designed to be distinguishable from each other by eye, they are
 * already learnable because a real teaching literature exists, and a user who
 * knows ASL gets them for free. An invented gesture set has none of those and
 * has to justify every shape from scratch.
 *
 * DELIBERATELY PURE. Joint poses in, letter out — no session, no ARCore
 * lifecycle. Classification is the part most likely to be wrong and it needs no
 * headset to exercise.
 *
 * WHAT THIS IS NOT: a general ASL recogniser. It knows a handful of letters
 * chosen to be far apart in shape space, and it is deliberately reluctant —
 * every letter needs a dwell before it fires, because a fist is something hands
 * do by accident all day and a HUD that vanishes when you pick up a mug is
 * worse than one you have to ask twice.
 */
object HandSign {

    enum class Letter { NONE, A, H }

    /**
     * Hand scale, from the wrist to the middle knuckle. Every threshold below is
     * a multiple of this, so the classifier works on a large hand and a small
     * one without a calibration step.
     */
    private fun scaleOf(j: Map<HandJointType, Pose>): Float {
        val w = j[HandJointType.WRIST]?.translation ?: return 0f
        val m = j[HandJointType.MIDDLE_METACARPAL]?.translation ?: return 0f
        return dist(w.x, w.y, w.z, m.x, m.y, m.z)
    }

    private fun dist(ax: Float, ay: Float, az: Float, bx: Float, by: Float, bz: Float): Float {
        val dx = ax - bx; val dy = ay - by; val dz = az - bz
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    /**
     * Is [tip] far enough from the wrist to count as an extended finger?
     *
     * Distance from the WRIST rather than a joint angle: angles need three
     * joints and two subtractions each and are noisier at the fingertip, where
     * tracking is worst. A curled finger folds its tip back toward the palm, so
     * wrist distance separates the two states cleanly and degrades gracefully
     * when a joint is briefly lost.
     */
    private fun extended(
        j: Map<HandJointType, Pose>, tip: HandJointType, scale: Float, k: Float = 1.55f,
    ): Boolean {
        val w = j[HandJointType.WRIST]?.translation ?: return false
        val t = j[tip]?.translation ?: return false
        return dist(w.x, w.y, w.z, t.x, t.y, t.z) > k * scale
    }

    /**
     * Classify one hand.
     *
     * Only shapes we actually use are recognised; everything else is NONE. A
     * classifier that returns its best guess for any input is a classifier that
     * fires constantly.
     */
    fun classify(joints: Map<HandJointType, Pose>): Letter {
        val scale = scaleOf(joints)
        if (scale <= 1e-4f) return Letter.NONE

        val index = extended(joints, HandJointType.INDEX_TIP, scale)
        val middle = extended(joints, HandJointType.MIDDLE_TIP, scale)
        val ring = extended(joints, HandJointType.RING_TIP, scale)
        val little = extended(joints, HandJointType.LITTLE_TIP, scale)
        // The thumb is shorter and sits on a different axis, so it needs its own
        // threshold — measured against the same scale, not a separate constant.
        val thumb = extended(joints, HandJointType.THUMB_TIP, scale, k = 1.15f)

        return when {
            // A — closed fist, thumb alongside. The four fingers curled is the
            // load-bearing half; the thumb only has to not be tucked inside.
            !index && !middle && !ring && !little && thumb -> Letter.A
            // H — index and middle extended together, ring and little down.
            // Distinguished from A by exactly the fingers A requires to be
            // curled, so the two cannot be confused by a threshold wobble.
            index && middle && !ring && !little -> Letter.H
            else -> Letter.NONE
        }
    }

    /**
     * A letter held long enough to be meant.
     *
     * Hands make shapes constantly and almost none of them are commands. This
     * fires ONCE when a letter has been held for [dwellMs], and will not fire
     * again until the hand has left that letter — so holding a fist does not
     * toggle a surface forty times a second, and neither does a fist that
     * happens on the way to picking something up.
     */
    class Gate(private val dwellMs: Long = 450L) {
        private var current = Letter.NONE
        private var since = 0L
        private var delivered = false

        /** Returns the letter exactly once per deliberate hold, else NONE. */
        fun update(letter: Letter, nowMs: Long): Letter {
            if (letter != current) {
                current = letter
                since = nowMs
                delivered = false
                return Letter.NONE
            }
            if (letter == Letter.NONE || delivered) return Letter.NONE
            if (nowMs - since < dwellMs) return Letter.NONE
            delivered = true
            return letter
        }
    }
}
