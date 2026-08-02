// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import kotlin.math.abs

/**
 * ANGULAR MAGNIFICATION — a wedge of true bearing stretched across the ring.
 *
 * From Portland the entire Seattle mesh sits inside seven degrees of bearing.
 * The ring can label four nodes there (a node is ~4.2 degrees tall and the
 * world window is 20), so the other 116 collapse into a counted mote. This is
 * how you get inside that count.
 *
 * IT IS MAGNIFICATION, NOT TELEPORTATION, and the distinction is the whole
 * design rather than pedantry. Re-origining the horizon at the cluster's
 * centroid would make every bearing true FROM A PLACE THE USER IS NOT: the ring
 * would look entirely normal and every direction on it would be wrong. That is
 * the same failure the brief already forbids for unlocated nodes, which is why
 * they get no bearing at all rather than a plausible one.
 *
 * A lens keeps the origin. Bearings stay true; only the SCALE changes, and a
 * change of scale is something that can be shown — which is what makes it
 * honest and what obliges the surface to show it.
 *
 * Deliberately pure. This is the part most likely to be wrong about wrap-around
 * and it needs no headset to exercise.
 */
class Lens(loRad: Float, hiRad: Float) {

    /** Start of the wedge, normalised to [0, 2pi). */
    val lo: Float = norm(loRad)

    /**
     * Width of the wedge in radians, always positive and less than a full turn.
     *
     * Stored as a SPAN rather than as an end bearing because a wedge that
     * crosses north — 357 deg to 005 deg — has an end numerically smaller than
     * its start, and every comparison downstream would need to know that. A
     * span has no such case: it is 8 degrees whether or not it straddles zero.
     */
    val span: Float = (norm(hiRad - loRad)).let { if (it < MIN_SPAN) MIN_SPAN else it }

    /** How much the ring is stretched. 7 degrees across 360 is about 51x. */
    val factor: Float get() = TWO_PI / span

    /** Offset of [b] from the start of the wedge, 0..span when inside. */
    private fun offset(b: Float): Float = norm(b - lo)

    fun contains(bearingRad: Float): Boolean = offset(bearingRad) <= span

    /**
     * True bearing to displayed bearing.
     *
     * The wedge maps onto the whole circle, keeping its MIDPOINT where it was:
     * magnifying should feel like the ring opening up around what you pinched,
     * not like it jumping somewhere else. A bearing outside the wedge still
     * gets an answer — the caller decides whether to draw it — and that answer
     * runs off the far side of the circle, which is where it belongs.
     */
    fun map(bearingRad: Float): Float {
        val mid = norm(lo + span / 2f)
        var d = bearingRad - mid
        // Shortest signed difference, so a bearing just the other side of north
        // is a small negative rather than nearly a full turn.
        while (d > PI) d -= TWO_PI
        while (d < -PI) d += TWO_PI
        return norm(mid + d * factor)
    }

    /**
     * Displayed bearing back to true — the inverse of [map].
     *
     * NESTING NEEDS THIS. Magnifying a cluster that is itself inside a magnified
     * ring means building a lens over the TRUE bearings of its members, but the
     * only bearing to hand is the one on screen. Without an inverse the second
     * lens would be built over already-magnified angles and would magnify the
     * magnification — a factor of 2600 on the Seattle wedge, where every node
     * lands on the opposite side of the ring from where it should.
     *
     * Keeping every lens defined over TRUE bearings, and composing by unmapping
     * first, means depth costs nothing: the third level is the same arithmetic
     * as the first.
     */
    fun unmap(displayedRad: Float): Float {
        val mid = midpoint
        var d = displayedRad - mid
        while (d > PI) d -= TWO_PI
        while (d < -PI) d += TWO_PI
        return norm(mid + d / factor)
    }

    /** The wedge's centre, which is where the return marker goes. */
    val midpoint: Float get() = norm(lo + span / 2f)

    override fun toString() =
        "Lens(%.1f..%.1f deg, x%.0f)".format(
            Math.toDegrees(lo.toDouble()),
            Math.toDegrees(norm(lo + span).toDouble()),
            factor,
        )

    companion object {
        const val PI = Math.PI.toFloat()
        const val TWO_PI = PI * 2f

        /**
         * A wedge narrower than this magnifies past any use: at 0.1 degrees the
         * factor is 3600 and a hand tremor sweeps the whole ring. It is also the
         * guard against a zero-width wedge dividing by nothing.
         */
        val MIN_SPAN = Math.toRadians(0.25).toFloat()

        fun norm(r: Float): Float {
            var x = r % TWO_PI
            if (x < 0f) x += TWO_PI
            return x
        }

        /**
         * A lens over the nodes a cluster stands for, with a little air.
         *
         * The wedge is padded by a fraction of its own width so the outermost
         * nodes do not sit exactly on the seam behind the user's head, where
         * two neighbours a degree apart in truth would end up half a ring
         * apart on screen.
         */
        fun over(bearings: List<Float>, pad: Float = 0.12f): Lens? {
            if (bearings.isEmpty()) return null
            // Circular extent: find the largest GAP between adjacent bearings;
            // the wedge is everything else. A plain min/max is wrong the moment
            // the set straddles north, and a Seattle cluster seen from Portland
            // straddles north.
            val sorted = bearings.map { norm(it) }.sorted()
            var gapAt = 0
            var gap = norm(sorted.first() - sorted.last())
            for (i in 1 until sorted.size) {
                val g = sorted[i] - sorted[i - 1]
                if (g > gap) { gap = g; gapAt = i }
            }
            val start = sorted[gapAt]
            val extent = TWO_PI - gap
            val p = extent * pad
            return Lens(norm(start - p), norm(start + extent + p))
        }
    }
}
