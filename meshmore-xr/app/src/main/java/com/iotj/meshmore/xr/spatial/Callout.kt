// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

/**
 * PIN · LEADER · HANDLE — reading a map that is smaller than its own labels.
 *
 * ## The problem, as arithmetic
 *
 * Everything in this app is sized by ANGLE, from measured eye distance: a mote
 * is `range * 0.0140` (1.6 deg) and a callsign cap is `range * 0.0227`
 * (1.3 deg). That is what let the tabletop work at all — shrink the model and
 * every mark follows it down, keeping its apparent size for free.
 *
 * It is also what makes the tabletop unreadable, because the rule cuts both
 * ways. Angular legibility is a FLOOR, not a preference, so the text does not
 * shrink with the model:
 *
 *               eye dist   cap     8-char label   model    label/model
 *   horizon     2.50 m     56.8mm  308 mm         5000 mm      6%
 *   tabletop    0.55 m     12.5mm   68 mm          320 mm     21%
 *
 * Five callsigns and the map is gone. The label is three and a half times
 * larger relative to the map than it is on the horizon, and today it hangs
 * directly at the node — so every label lands ON the diorama it is describing.
 *
 * ## The split
 *
 * Two jobs with different sizing laws are being done by one mark:
 *
 *   POSITION must be SEEN. It has no legibility floor — a dot only has to be
 *   noticed, never identified — so it can go small.
 *   IDENTITY must be READ. Floor 1.3 deg, non-negotiable, whatever the map is
 *   doing.
 *
 * So they separate. A PIN sits at the true position and stays tiny. A HANDLE
 * carries the text, lives outside the map entirely, and is big enough to grab.
 * A LEADER joins them. The map keeps its geometry; the labels get their floor;
 * neither has to lose.
 *
 * ## What this file is
 *
 * The arrangement, as pure arithmetic — no session, no entities, no headset.
 * It answers "where does each handle go, and does this fit" so those questions
 * can be settled by a test rather than by a photograph. Rendering is the
 * caller's problem.
 *
 * Deliberately not BIOLUME-specific. A crowded bearing on the horizon has the
 * same problem, and the deferred map suite will have it worse.
 */
object Callout {

    /** One thing on the map that wants a label. */
    data class Want(
        val id: String,
        /** Where it actually is, in the map's own plane: metres from centre. */
        val x: Float,
        val y: Float,
        /** What the handle has to say. */
        val text: String,
    )

    /** Where its handle ended up. */
    data class Placed(
        val id: String,
        val text: String,
        /** The pin, unchanged — the true position. */
        val pinX: Float,
        val pinY: Float,
        /** The handle, out in the rack. */
        val handleX: Float,
        val handleY: Float,
        /** Which side of the map it went to. */
        val left: Boolean,
        /** Slot index within its side, 0 at the top. */
        val slot: Int,
    )

    /**
     * The rules, as numbers. Defaults are the tabletop's, at 0.55 m.
     *
     * [rowPitch] is the one that decides how many labels a map can carry, and
     * it is not a taste parameter: it is the text row height plus a gap, and
     * the row height is fixed by the 1.3 deg legibility floor. Everything else
     * follows from it.
     */
    data class Rules(
        /** Half-width of the map itself. Handles never enter this. */
        val mapRadius: Float = 0.16f,
        /** Clear space between the map's edge and the rack. */
        val gutter: Float = 0.045f,
        /** Vertical distance between handles. Row height + gap. */
        val rowPitch: Float = 0.028f,
        /** How much vertical room the rack has, total. */
        val bandHeight: Float = 0.25f,
    ) {
        /** Handles per side. The budget, and the reason clustering exists. */
        val perSide: Int get() = ((bandHeight / rowPitch).toInt() + 1).coerceAtLeast(1)

        /** Total labels this map can carry before anything has to cluster. */
        val capacity: Int get() = perSide * 2

        /** Where the rack sits, out from centre. */
        val rackX: Float get() = mapRadius + gutter
    }

    /**
     * Place every want, or as many as the budget allows.
     *
     * ## R1 · handles never enter the map
     *
     * The rack starts one gutter beyond the map's edge. The map owns position;
     * the rack owns identity; nothing in the rack may cast over the disc. This
     * is the rule the whole design exists to keep — it is what a label hanging
     * at its node violates, and why the tabletop is unreadable today.
     *
     * ## R2 · order is preserved, so leaders cannot cross
     *
     * Handles are assigned top to bottom in the order their pins run top to
     * bottom, on each side independently. Matching order makes crossing
     * GEOMETRICALLY IMPOSSIBLE rather than merely unlikely: two leaders can
     * only cross if one pin is above another while its handle is below, which
     * sorting forbids. No collision test, no jitter, no frame-to-frame
     * reshuffling — the property falls out of the sort.
     *
     * ## R3 · side by half
     *
     * A pin left of centre gets a left handle. Halves the leader length and
     * stops leaders crossing the middle of the map, which is the one part of
     * the map somebody is actually looking at.
     *
     * ## R4 · the budget is honest
     *
     * Past capacity, the extras are DROPPED and reported rather than squeezed
     * in at a spacing that cannot be read. A caller that wants them anyway
     * should cluster them into one want, which is what the horizon's ranker
     * already does for its own labels.
     */
    fun place(wants: List<Want>, rules: Rules = Rules()): List<Placed> {
        val (left, right) = wants.partition { it.x < 0f }
        return side(left, rules, true) + side(right, rules, false)
    }

    private fun side(wants: List<Want>, r: Rules, left: Boolean): List<Placed> {
        // Topmost pin gets the topmost slot. This sort IS rule R2.
        val ordered = wants.sortedByDescending { it.y }.take(r.perSide)
        val n = ordered.size
        // Centre the used slots in the band, so four labels sit as a group in
        // the middle rather than hanging from the top edge.
        val top = (n - 1) * r.rowPitch / 2f
        return ordered.mapIndexed { i, w ->
            Placed(
                id = w.id,
                text = w.text,
                pinX = w.x,
                pinY = w.y,
                handleX = if (left) -r.rackX else r.rackX,
                handleY = top - i * r.rowPitch,
                left = left,
                slot = i,
            )
        }
    }

    /**
     * How many wants a map of these rules had to drop.
     *
     * Reported rather than silently absorbed: a surface that quietly shows 16
     * of 29 nodes reads as a surface showing all of them, which is the failure
     * mode the horizon's cluster counts exist to prevent.
     */
    fun dropped(wants: List<Want>, rules: Rules = Rules()): Int {
        val (l, r) = wants.partition { it.x < 0f }
        return (l.size - minOf(l.size, rules.perSide)) + (r.size - minOf(r.size, rules.perSide))
    }

    /**
     * THE 7-SHAPE, as two segments.
     *
     * A riser straight up from the pin, then a run out to the handle. Returned
     * as the elbow point, which is all a renderer needs: pin -> elbow -> handle.
     *
     * The riser is VERTICAL and the run is HORIZONTAL, both always. One fixed
     * direction each is what keeps a dozen leaders separable — a fan of
     * free-angled lines between two clouds of points reads as noise, while a
     * comb of right angles reads as a diagram. It costs nothing and it is the
     * difference between a schematic and a scribble.
     */
    fun elbow(p: Placed): Pair<Float, Float> = p.pinX to p.handleY
}
