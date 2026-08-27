// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import kotlin.math.sqrt

/**
 * THE TRAIL THAT SAYS "BRING THAT HAND HERE".
 *
 * S0 puts one mote at arm's length and the word TOUCH THIS under it, and the
 * operator's report after months of wearing it is exact: *"there is no text
 * I've ever seen associated with this. But yes, I always reach and grab it."*
 *
 * Both halves of that matter. The mote is doing its job — the affordance reads
 * without a word, which is the whole thesis of teaching the paradigm by doing
 * it. The words are not doing theirs. Whether that is a rendering fault or
 * simply nobody looking 5 cm below a glowing object they have already decided
 * to grab, the answer is the same: **a first-time wearer should not depend on
 * reading anything.** The instruction has to be drawn, in the same register as
 * the thing it is about.
 *
 * So: a trail of beads from the wearer's hand to the mote, with a highlight
 * that travels along it TOWARD the mote. Direction of motion is the message.
 * Nothing has to be read, and nothing has to be understood in a second
 * language — which is worth something in a build that ships in two.
 *
 * ## Why it is anchored to the actual hand
 *
 * A static arrow floating near the mote would say "reach", but it could not say
 * "with THAT hand, from THERE" — and it would keep saying it after the wearer
 * had already begun, which is nagging rather than instruction. Anchored to the
 * tracked hand the trail shortens as you close, fades as you arrive, and is
 * gone before it can cover the target. It also inherits S0's other job for
 * free: a trail that appears at all is proof the tracker sees that hand.
 *
 * When no hand is tracked there is nothing to anchor to, so the trail runs from
 * a GHOST origin down and to the wearer's left instead — which is the one case
 * where it is genuinely instructing rather than confirming, and the case a
 * first-time wearer with their hands still in their lap is actually in.
 *
 * ## Pure, because the alternative is testing it by wearing it
 *
 * Every number here is arithmetic on positions, so the whole path can be
 * asserted at a bench: that the beads run the right way, that the highlight
 * travels toward the mote and not away from it, that it fades to nothing on
 * arrival, and that a hand already at the target draws no trail at all. None of
 * that needs a headset, and none of it needs SceneCore. The class holds no
 * androidx type on purpose.
 */
object Beckon {

    /**
     * How many beads.
     *
     * Enough to read as a path rather than as a dotted line of separate
     * objects, few enough that they are never mistaken for the mesh's own
     * motes — which are the same primitive, and which the wearer is about to
     * spend the rest of the session reading.
     */
    const val BEADS = 7

    /** One trip of the highlight, hand to mote. Slower than a gesture, faster than a breath. */
    const val CYCLE_MS = 1500L

    /**
     * Hand this close to the mote: no trail at all.
     *
     * A path drawn across the last few centimetres lands ON the target it is
     * pointing at, and the wearer's own hand is already covering it. The
     * instruction is finished before this point; anything further is clutter
     * over the moment it exists to produce.
     */
    const val ARRIVED_M = 0.14f

    /** Full strength at this range and beyond; it ramps down from here to [ARRIVED_M]. */
    const val FADE_M = 0.32f

    /**
     * Where the trail starts when no hand has been seen.
     *
     * Down and to the wearer's LEFT, which is the operator's request — the left
     * hand is the one that should come up. It is a nudge and not a requirement:
     * the mote takes a touch from either hand, and from the gaze dwell, exactly
     * as before. Nothing here gates the interaction on which hand you own.
     */
    const val GHOST_LEFT = 0.30f
    const val GHOST_DROP = 0.26f

    /**
     * How far the path bows upward off the straight line.
     *
     * A straight segment between two points at similar height reads as a stick
     * — a thing in its own right — and it passes straight through where the
     * label hangs. An arc reads as a route, and it clears the text.
     */
    const val BOW = 0.05f

    /** Alpha at the hand end. The trail is brighter where it is going. */
    const val TAIL_ALPHA = 0.25f

    /** Alpha at the mote end, before the travelling highlight is applied. */
    const val HEAD_ALPHA = 0.70f

    /**
     * How much the travelling highlight adds on top of the ramp.
     *
     * [HEAD_ALPHA] + [PULSE] is exactly 1, and that is a constraint rather than
     * a coincidence. Letting the sum exceed opaque meant the brightest bead
     * CLAMPED — and once two beads both clamp they are equally bright, so at
     * the end of a sweep the highlight stopped one bead short of the mote and
     * the trail quietly stopped pointing all the way at its own target. Caught
     * by the direction test, not by looking.
     */
    const val PULSE = 0.30f

    /** How tight the highlight is: larger is narrower. */
    private const val PULSE_SHARPNESS = 9f

    data class Bead(
        val x: Float,
        val y: Float,
        val z: Float,
        /** 0 means "do not draw this one" — the caller disables the entity. */
        val alpha: Float,
    )

    fun distance(
        ax: Float, ay: Float, az: Float,
        bx: Float, by: Float, bz: Float,
    ): Float {
        val dx = bx - ax
        val dy = by - ay
        val dz = bz - az
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    /**
     * How loudly to draw, from how far the hand still has to travel.
     *
     * 1 while the hand is far, ramping to 0 at [ARRIVED_M]. Continuous rather
     * than a switch: a trail that vanished at a threshold would blink out mid
     * reach, which reads as a fault in the very surface that exists to prove
     * nothing is faulty.
     */
    fun strength(distM: Float): Float = when {
        distM <= ARRIVED_M -> 0f
        distM >= FADE_M -> 1f
        else -> (distM - ARRIVED_M) / (FADE_M - ARRIVED_M)
    }

    /** Where the highlight sits along the path, 0 at the hand and 1 at the mote. */
    fun phase(nowMs: Long): Float =
        (nowMs.mod(CYCLE_MS)).toFloat() / CYCLE_MS

    /**
     * The ghost origin, for a wearer whose hands the tracker has not seen.
     *
     * [leftX]/[leftZ] is the wearer's left in the activity frame, which the
     * caller already has from the yaw it placed the mote with.
     */
    fun ghost(
        moteX: Float, moteY: Float, moteZ: Float,
        leftX: Float, leftZ: Float,
    ): Triple<Float, Float, Float> = Triple(
        moteX + leftX * GHOST_LEFT,
        moteY - GHOST_DROP,
        moteZ + leftZ * GHOST_LEFT,
    )

    /**
     * The path itself.
     *
     * Bead 0 sits at the hand and bead [BEADS]-1 at the mote, so the list reads
     * in the direction of travel and a caller can trust the order.
     */
    fun trail(
        fromX: Float, fromY: Float, fromZ: Float,
        toX: Float, toY: Float, toZ: Float,
        phase: Float,
        strength: Float,
    ): List<Bead> {
        if (strength <= 0f) return emptyList()
        return (0 until BEADS).map { i ->
            val t = i.toFloat() / (BEADS - 1)
            // THE BOW. A half-sine is zero at both ends by construction, so the
            // path still starts exactly at the hand and ends exactly at the
            // mote however far it arcs in between.
            val lift = BOW * kotlin.math.sin(t * Math.PI.toFloat())
            // THE RAMP, brighter toward the target. On an additive display this
            // is the whole grammar of direction: there is no arrowhead to draw
            // that would not also be a small bright object competing with the
            // one bright object that matters.
            val ramp = TAIL_ALPHA + (HEAD_ALPHA - TAIL_ALPHA) * t
            // THE HIGHLIGHT. A narrow gaussian that sweeps hand-to-mote once per
            // cycle. It wraps at the ends rather than bouncing: a bead that ran
            // back down the path would say "away", which is the opposite
            // instruction.
            val d = t - phase
            val pulse = PULSE * kotlin.math.exp(-PULSE_SHARPNESS * d * d * BEADS)
            Bead(
                x = fromX + (toX - fromX) * t,
                y = fromY + (toY - fromY) * t + lift,
                z = fromZ + (toZ - fromZ) * t,
                alpha = ((ramp + pulse) * strength).coerceIn(0f, 1f),
            )
        }
    }
}
