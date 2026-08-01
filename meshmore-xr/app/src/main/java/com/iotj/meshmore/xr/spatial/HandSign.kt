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
     * A fingertip more than this many times its knuckle's distance from the
     * wrist is STRAIGHT. A straight finger measures near 2.0 and a curled one
     * near or below 1.0, so the midpoint is a wide, forgiving gate rather than
     * a tuned edge.
     */
    const val STRAIGHT = 1.5f

    /**
     * Hand scale, from the wrist to the middle knuckle.
     *
     * KEPT ONLY AS A SANITY CHECK. It was the divisor for every threshold and
     * it was the wrong one: on this hand model MIDDLE_METACARPAL sits almost on
     * the wrist, so the divisor is a couple of centimetres and every ratio blows
     * up. A real hand measured t4.90 i4.93 m2.38 r2.04 l2.15 against thresholds
     * of 1.55 — every finger "extended", always, so the fist could never be
     * recognised. See [extended] for what replaced it.
     */
    private fun scaleOf(j: Map<HandJointType, Pose>): Float {
        val w = j[HandJointType.WRIST]?.translation ?: return 0f
        val m = j[HandJointType.MIDDLE_METACARPAL]?.translation ?: return 0f
        return dist(w.x, w.y, w.z, m.x, m.y, m.z)
    }

    /** Each finger's tip and the knuckle it folds around. */
    private val FINGERS = listOf(
        HandJointType.INDEX_TIP to HandJointType.INDEX_PROXIMAL,
        HandJointType.MIDDLE_TIP to HandJointType.MIDDLE_PROXIMAL,
        HandJointType.RING_TIP to HandJointType.RING_PROXIMAL,
        HandJointType.LITTLE_TIP to HandJointType.LITTLE_PROXIMAL,
    )

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
        j: Map<HandJointType, Pose>, tip: HandJointType, scale: Float, k: Float = STRAIGHT,
    ): Boolean = reach(j, tip, knuckleFor(tip)) > k

    private fun knuckleFor(tip: HandJointType): HandJointType =
        FINGERS.firstOrNull { it.first == tip }?.second ?: HandJointType.THUMB_PROXIMAL

    /**
     * How far a fingertip reaches BEYOND ITS OWN KNUCKLE, as a ratio.
     *
     * This is the fix for the calibration failure above, and it is better than a
     * retuned constant would have been. Measuring the tip against a whole-hand
     * scale asks "is this finger long?", which depends on the hand, the model's
     * joint placement, and which joint the vendor calls a metacarpal. Measuring
     * it against its OWN proximal joint asks "is this finger straight?", which
     * is the actual question and is answered the same way by every hand:
     *
     *   straight  tip is roughly twice as far from the wrist as its knuckle
     *   curled    tip folds back toward the palm, landing at or inside it
     *
     * No hand-size term, no per-model constant, nothing to recalibrate when the
     * next headset numbers its joints differently.
     */
    fun reach(j: Map<HandJointType, Pose>, tip: HandJointType, knuckle: HandJointType): Float {
        val w = j[HandJointType.WRIST]?.translation ?: return -1f
        val t = j[tip]?.translation ?: return -1f
        val k = j[knuckle]?.translation ?: return -1f
        val dk = dist(w.x, w.y, w.z, k.x, k.y, k.z)
        if (dk < 1e-5f) return -1f
        return dist(w.x, w.y, w.z, t.x, t.y, t.z) / dk
    }

    /**
     * Classify one hand.
     *
     * Only shapes we actually use are recognised; everything else is NONE. A
     * classifier that returns its best guess for any input is a classifier that
     * fires constantly.
     */
    /** Finger extension as multiples of hand scale — the numbers the thresholds compare. */
    fun ratios(joints: Map<HandJointType, Pose>): String =
        "i%.2f m%.2f r%.2f l%.2f".format(
            reach(joints, HandJointType.INDEX_TIP, HandJointType.INDEX_PROXIMAL),
            reach(joints, HandJointType.MIDDLE_TIP, HandJointType.MIDDLE_PROXIMAL),
            reach(joints, HandJointType.RING_TIP, HandJointType.RING_PROXIMAL),
            reach(joints, HandJointType.LITTLE_TIP, HandJointType.LITTLE_PROXIMAL),
        )

    /** What the classifier saw. For calibrating thresholds against real hands. */
    fun describe(joints: Map<HandJointType, Pose>): String {
        val scale = scaleOf(joints)
        if (scale <= 1e-4f) return "joints=${joints.size} scale=0 (no wrist/metacarpal)"
        fun r(t: HandJointType): Float {
            val w = joints[HandJointType.WRIST]?.translation ?: return -1f
            val p = joints[t]?.translation ?: return -1f
            return dist(w.x, w.y, w.z, p.x, p.y, p.z) / scale
        }
        return "joints=${joints.size} scale=%.3f thumb=%.2f idx=%.2f mid=%.2f rng=%.2f lit=%.2f -> %s"
            .format(scale, r(HandJointType.THUMB_TIP), r(HandJointType.INDEX_TIP),
                r(HandJointType.MIDDLE_TIP), r(HandJointType.RING_TIP),
                r(HandJointType.LITTLE_TIP), classify(joints))
    }

    fun classify(joints: Map<HandJointType, Pose>): Letter {
        val scale = scaleOf(joints)
        if (scale <= 1e-4f) return Letter.NONE

        val index = extended(joints, HandJointType.INDEX_TIP, scale)
        val middle = extended(joints, HandJointType.MIDDLE_TIP, scale)
        val ring = extended(joints, HandJointType.RING_TIP, scale)
        val little = extended(joints, HandJointType.LITTLE_TIP, scale)

        return when {
            // A — a closed fist. The four fingers curled is the whole test.
            //
            // The thumb requirement is GONE. ASL distinguishes A (thumb
            // alongside) from S (thumb across the fingers) by the thumb, and
            // both are fists — but the thumb is the least reliably tracked joint
            // on the hand and we do not use S. Requiring it bought a distinction
            // nothing depends on at the cost of the gesture working at all.
            !index && !middle && !ring && !little -> Letter.A
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
