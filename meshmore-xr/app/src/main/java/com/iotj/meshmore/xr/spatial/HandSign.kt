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

    enum class Letter { NONE, A, B, H }

    /**
     * A fingertip more than this many times its knuckle's distance from the
     * wrist is STRAIGHT. A straight finger measures near 2.0 and a curled one
     * near or below 1.0, so the midpoint is a wide, forgiving gate rather than
     * a tuned edge.
     */
    const val STRAIGHT = 1.5f

    /**
     * Thumb-tip to index-tip, as a fraction of the wrist-to-index-knuckle
     * distance. Below this the hand is pinching rather than signing.
     *
     * MEASURED ON HARDWARE, 2026-08-01:
     *
     *     pinching   0.09 - 0.11
     *     open hand  0.77
     *     ASL 'A'    fires reliably at this threshold
     *
     * 0.42 sits between the two clusters with room on either side, so this is a
     * gap rather than an edge — the reading has to move by a factor of four
     * before it changes an answer. It was a guess when written and is not one
     * now; the readout prints `p0.NN` so it can be re-checked on any hand.
     */
    const val PINCH_GAP = 0.42f
    /**
     * Widest adjacent fingertip gap that still counts as "together", as a
     * fraction of the knuckle distance.
     *
     * PROVISIONAL. Derived from hand proportions — fingertips touching sit at
     * roughly 0.2 of the knuckle distance, a relaxed splay at roughly 0.45 —
     * and NOT yet settled on hardware, which is how every other threshold in
     * this file was eventually fixed. `ratios` now prints it (`s0.00`), so the
     * hands readout can be watched while opening and closing the fingers.
     *
     * Biased tight on purpose. A missed B costs one pinch on the WIDE pip; a
     * false B costs a magnification and an explanation.
     */
    const val B_SPREAD = 0.34f

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

    /**
     * PALM DIRECTION — which way the hand is turned.
     *
     * A hand shape is only half a letter. ASL forms its letters with the palm
     * toward the RECEIVER, so a fist held palm-first at your own face is not a
     * well-formed 'A'; it is the back of an 'A'. Ignoring that made the two
     * indistinguishable, which is wrong as ASL and also wrong as a command
     * vocabulary — it doubles the number of accidental hand positions that fire.
     *
     * Wearing the glasses puts the camera on the SIGNER, so a correctly formed
     * letter presents its BACK to them: you sign outward, as you would to a
     * person standing in front of you. Hence [palmAway].
     *
     * The normal comes from the two outer knuckles and the wrist, which is a
     * plane through the palm. Handedness flips it, because the two hands are
     * mirror images: whichever side the index knuckle falls on for one, it
     * falls on the other side for the other, and the cross product changes sign
     * with it.
     *
     * WHICH SIDE IS WHICH WAS SETTLED ON THE DEVICE, NOT DERIVED. I reasoned it
     * out from anatomical position and got it backwards — the first build fired
     * on a palm-first fist and refused a correctly formed one. That is the
     * fourth sign convention in this project I have argued my way to the wrong
     * answer on (head yaw, Euler order, panel depth, and now this), and the
     * pattern is clear enough to write down: a handedness or chirality sign is
     * not something to derive in a comment. Build it, look at it, and let the
     * hardware say. The readout prints `back` or `palm` precisely so this is
     * checkable in one glance instead of one release.
     */
    fun palmNormal(
        wx: Float, wy: Float, wz: Float,
        ix: Float, iy: Float, iz: Float,
        lx: Float, ly: Float, lz: Float,
        rightHand: Boolean,
    ): Triple<Float, Float, Float> {
        val ux = ix - wx; val uy = iy - wy; val uz = iz - wz
        val vx = lx - wx; val vy = ly - wy; val vz = lz - wz
        // u x v points out of the RIGHT palm; the left hand is its mirror.
        // Verified on hardware — see the note above about deriving this.
        var nx = uy * vz - uz * vy
        var ny = uz * vx - ux * vz
        var nz = ux * vy - uy * vx
        if (!rightHand) { nx = -nx; ny = -ny; nz = -nz }
        val m = sqrt(nx * nx + ny * ny + nz * nz)
        if (m < 1e-6f) return Triple(0f, 0f, 0f)
        return Triple(nx / m, ny / m, nz / m)
    }

    /**
     * IS THIS A PINCH? — the shape 'A' is nearly, and the one it must not be.
     *
     * A pinch curls all four fingers, which is exactly the test for 'A', so
     * selecting a node was toggling the compass band. That is not a threshold
     * being slightly off; the two shapes genuinely overlap on the only feature
     * being measured.
     *
     * What separates them is WHERE THE THUMB IS. In a pinch the thumb tip meets
     * the index tip — that is what pinching means. In ASL 'A' the thumb lies
     * ALONGSIDE the curled index, roughly level with its middle knuckle, while
     * the index tip is tucked into the palm; the two tips end up a good part of
     * a finger-length apart. So the gap between them, measured against the
     * hand's own knuckle distance, tells the shapes apart without either one
     * having to know about the other.
     *
     * Returns the gap as a ratio, or -1 when the joints are not there.
     */
    /**
     * FINGER SPREAD — how far apart the fingertips are, as a fraction of the
     * hand's own knuckle distance. Scale-free, like every other measure here.
     *
     * This is what tells a DELIBERATE flat hand from a relaxed open one, and it
     * is the discriminator ASL actually uses: B has the fingers together (and
     * the thumb folded across, which we do not test because the thumb is the
     * least reliably tracked joint on the hand). A hand at rest splays.
     *
     * Returns -1 when the joints are not there, which callers must treat as
     * "unknown" rather than "together".
     */
    fun spread(j: Map<HandJointType, Pose>): Float {
        val w = j[HandJointType.WRIST]?.translation ?: return -1f
        val k = j[HandJointType.INDEX_PROXIMAL]?.translation ?: return -1f
        val knuckle = dist(w.x, w.y, w.z, k.x, k.y, k.z)
        if (knuckle < 1e-5f) return -1f
        val tips = listOf(
            HandJointType.INDEX_TIP, HandJointType.MIDDLE_TIP,
            HandJointType.RING_TIP, HandJointType.LITTLE_TIP,
        ).map { j[it]?.translation ?: return -1f }
        // The WIDEST adjacent gap, not the mean: one splayed finger is a hand
        // that is not making the letter, and averaging hides it.
        var worst = 0f
        for (i in 0 until tips.size - 1) {
            val a = tips[i]; val b = tips[i + 1]
            worst = kotlin.math.max(worst, dist(a.x, a.y, a.z, b.x, b.y, b.z) / knuckle)
        }
        return worst
    }

    fun pinchGap(j: Map<HandJointType, Pose>): Float {
        val w = j[HandJointType.WRIST]?.translation ?: return -1f
        val k = j[HandJointType.INDEX_PROXIMAL]?.translation ?: return -1f
        val t = j[HandJointType.THUMB_TIP]?.translation ?: return -1f
        val i = j[HandJointType.INDEX_TIP]?.translation ?: return -1f
        val knuckle = dist(w.x, w.y, w.z, k.x, k.y, k.z)
        if (knuckle < 1e-5f) return -1f
        return dist(t.x, t.y, t.z, i.x, i.y, i.z) / knuckle
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
        "p%.2f i%.2f m%.2f r%.2f l%.2f".format(
            pinchGap(joints),
            reach(joints, HandJointType.INDEX_TIP, HandJointType.INDEX_PROXIMAL),
            reach(joints, HandJointType.MIDDLE_TIP, HandJointType.MIDDLE_PROXIMAL),
            reach(joints, HandJointType.RING_TIP, HandJointType.RING_PROXIMAL),
            reach(joints, HandJointType.LITTLE_TIP, HandJointType.LITTLE_PROXIMAL),
        ) + " s%.2f".format(spread(joints))

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

    /**
     * Classify, optionally requiring the palm to be turned away.
     *
     * [palmAway] null means the caller could not determine the orientation —
     * the wrist or a knuckle was not tracked, or there is no head pose. The
     * shape is then accepted on its own, because refusing every letter whenever
     * one joint drops out would make the vocabulary unusable in exactly the
     * conditions it is most needed.
     */
    fun classify(joints: Map<HandJointType, Pose>, palmAway: Boolean?): Letter {
        val shape = classify(joints)
        if (shape == Letter.NONE) return shape
        // Orientation only ever REJECTS. It cannot turn a non-letter into one.
        if (palmAway == false) return Letter.NONE
        return shape
    }

    fun classify(joints: Map<HandJointType, Pose>): Letter {
        val scale = scaleOf(joints)
        if (scale <= 1e-4f) return Letter.NONE

        val index = extended(joints, HandJointType.INDEX_TIP, scale)
        val middle = extended(joints, HandJointType.MIDDLE_TIP, scale)
        val ring = extended(joints, HandJointType.RING_TIP, scale)
        val little = extended(joints, HandJointType.LITTLE_TIP, scale)

        // A PINCH IS NOT A LETTER. Checked before anything else, because a
        // pinch satisfies every finger-curl test 'A' applies and the user is
        // usually pinching AT something — so a false 'A' does not merely fire a
        // command, it fires one while they are trying to issue a different one.
        val gap = pinchGap(joints)
        if (gap in 0f..PINCH_GAP) return Letter.NONE

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
            // B — flat hand, four fingers straight AND TOGETHER.
            //
            // The togetherness is not pedantry about ASL, it is the whole
            // defence. Without it the test is "four fingers extended", which is
            // an open hand — the most common resting shape there is — and the
            // note that used to sit here argued that was acceptable because a
            // false B only "undoes a view you can restore with one pinch".
            //
            // It was not acceptable. Reported 2026-08-02: the view kept
            // demagnifying on its own, from a hand the user was not gesturing
            // with, and because B is only listened to WHILE MAGNIFIED the only
            // time the flaw could bite was the exact time it mattered. The cost
            // of a false B is not one pinch, it is losing a magnification that
            // took finding a cluster, pinching it and choosing MAGNIFY to reach
            // — and having no idea why it went.
            //
            // ASL distinguishes B from 5 by the fingers being together and the
            // thumb folded across. The thumb we still do not test — least
            // reliably tracked joint — but adjacency is measured off the
            // fingertips, which are among the best tracked.
            index && middle && ring && little &&
                spread(joints).let { it in 0f..B_SPREAD } -> Letter.B
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
