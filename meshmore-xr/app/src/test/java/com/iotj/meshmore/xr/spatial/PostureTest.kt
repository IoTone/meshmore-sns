// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE AXIS THAT WAS ONLY A CAPTION.
 *
 * `posture` was declared on two of the nine themes and read by exactly one
 * thing — the picker's subtitle, which printed the word TABLETOP under BIOLUME
 * and TRANSIT under RECON AMBER and then changed nothing at all. Both themes
 * advertised a spatial arrangement the app did not have.
 *
 * These are the properties that make the arrangement real, and they are checked
 * here because every one of them is arithmetic that a headset can only tell you
 * about by being wrong in front of you.
 */
class PostureTest {

    /** The window the brief gives a wearer without a head turn. */
    private val fieldDeg = 34.0

    private fun deg(halfWidth: Float, distance: Float) =
        Math.toDegrees(2.0 * Math.atan(halfWidth.toDouble() / distance))

    /**
     * FIELD IS UNCHANGED, to the last decimal.
     *
     * Seven of the nine themes are FIELD, so this refactor's first duty is to
     * have moved nothing. These were the literals in Horizon before the frame
     * existed: R = 2.5 and EYE_DROP = -0.30, about the wearer.
     */
    @Test fun fieldIsExactlyWhatTheHorizonAlwaysDid() {
        val f = Theme.frameFor(Theme.Posture.FIELD)
        assertEquals(2.5f, f.radius, 0f)
        assertEquals(-0.30f, f.drop, 0f)
        assertEquals("FIELD must stay centred on the wearer", 0f, f.forward, 0f)
        assertTrue(f.horizon)
    }

    /**
     * A TABLETOP YOU CANNOT SEE AT ONCE IS NOT A TABLETOP.
     *
     * The whole proposition is a model you take in with your eyes rather than
     * your neck. At 0.16 m radius, 0.55 m out, that is 32.4 degrees across
     * against a 34 degree window — deliberately close, because a smaller model
     * loses the node separation that makes it readable.
     */
    @Test fun theTabletopFitsInsideTheFieldOfView() {
        val f = Theme.frameFor(Theme.Posture.TABLETOP)
        val across = deg(f.radius, f.forward)
        assertTrue("tabletop is %.1f deg across".format(across), across <= fieldDeg)
        assertTrue("tabletop is only %.1f deg — too small to read".format(across), across >= 24.0)
    }

    /**
     * ...and it is IN FRONT of you, not around you.
     *
     * A ring centred on the wearer is a horizon however small you make it: at
     * 0.16 m you would be standing inside a 32 cm shell with peers behind your
     * own head. The forward push is what turns a shell into a model, so it has
     * to exceed the radius or the wearer is still inside it.
     */
    @Test fun theWearerStandsOutsideTheTabletop() {
        val f = Theme.frameFor(Theme.Posture.TABLETOP)
        assertTrue(
            "forward %.2f m does not clear a %.2f m radius".format(f.forward, f.radius),
            f.forward > f.radius,
        )
    }

    /**
     * MARKS KEEP THEIR APPARENT SIZE FOR FREE.
     *
     * Horizon sizes a mote as `range * 0.0140` where range is its MEASURED
     * distance to the eye, which works out at a constant 1.6 degrees. Moving
     * the ring changes that distance, so the arithmetic follows the model down
     * to the table with no scale factor anywhere — this pins that, because the
     * obvious "fix" for a small tabletop is a markScale, and adding one would
     * silently double-count.
     */
    @Test fun aTabletopNodeSubtendsTheSameAngleAsAHorizonNode() {
        val k = 0.0140f
        val horizonNode = deg(2.5f * k, 2.5f)
        val tableNode = deg(0.55f * k, 0.55f)
        assertEquals(horizonNode, tableNode, 0.001)
        assertEquals("the house node angle", 1.60, horizonNode, 0.02)
    }

    /**
     * TRANSIT IS A SUBTRACTION. It has no geometry of its own — the flag is the
     * feature, and the surfaces that remain were already built and already
     * head- or hand-locked.
     */
    @Test fun transitDrawsNoRing() {
        assertFalse(Theme.frameFor(Theme.Posture.TRANSIT).horizon)
        assertTrue(Theme.frameFor(Theme.Posture.FIELD).horizon)
        assertTrue(Theme.frameFor(Theme.Posture.TABLETOP).horizon)
    }

    /**
     * THE ACTIVE STANCE — HALO, and only HALO.
     *
     * §7.1 calls it "the one you can wear for eight hours", which is a promise
     * about being worn WHILE MOVING: hiking, cycling, riding as a passenger. It
     * is the only theme that claims it, and each thing the stance changes has to
     * both serve a moving wearer and draw less.
     */
    @Test fun onlyHaloTakesTheActiveStance() {
        val active = Theme.ALL.filter { it.active }
        assertEquals(active.map { it.key }.toString(), 1, active.size)
        assertEquals("halo", active.first().key)
    }

    @Test fun theActiveStanceGetsOutOfAWalkersWay() {
        val f = Theme.frameFor(Theme.Posture.FIELD, active = true)
        val still = Theme.frameFor(Theme.Posture.FIELD, active = false)
        // Tighter than the standing ring — you turn with it instead of
        // repeatedly walking out of it.
        assertTrue("active radius %.2f".format(f.radius), f.radius < still.radius)
        // THE CIRCLES GO LOW, AND STAY IN THE FIELD. Two requirements, and the
        // first version of this test only had the first — it asserted the
        // circles were on the FLOOR, which is how they ended up 34.8 degrees
        // down at the 1.8 m ring: past the lower edge of a 34-degree window,
        // out of sight, with the grid already deleted. The theme rendered an
        // empty room and the test was green, because the test was checking
        // "low" when the requirement is "low AND visible".
        assertTrue("rings must sit below the nodes", f.ringDrop < f.drop)
        val below = Math.toDegrees(Math.atan(-f.ringDrop.toDouble() / f.radius))
        assertTrue("circles are %.1f deg down, out of the field".format(below), below <= 17.0)
        assertTrue("circles at %.1f deg are in the sightline".format(below), below >= 10.0)
        // And the grid goes away entirely: the circles already say scale.
        assertFalse("active use must not draw the floor grid", f.floorGrid)
        assertTrue("every other FIELD theme keeps its floor", still.floorGrid)
    }

    /**
     * THE CIRCLES FOLLOW; THE MESH DOES NOT.
     *
     * The distinction is the whole of what "moves with you" means here. A node
     * sits at a real place — a repeater on a hill stays on its hill — and a
     * mesh that slid along with the wearer would be lying about every bearing
     * it draws. The circles are a scale measured FROM the wearer, and one
     * centred where they stood ten minutes ago measures from nowhere.
     */
    @Test fun onlyTheActiveStanceFollowsTheWearer() {
        assertTrue(Theme.frameFor(Theme.Posture.FIELD, active = true).follows)
        assertFalse(Theme.frameFor(Theme.Posture.FIELD).follows)
        assertFalse(Theme.frameFor(Theme.Posture.TABLETOP).follows)
        // A tabletop that chased the wearer would drag the model off its table.
        assertFalse(Theme.frameFor(Theme.Posture.TRANSIT).follows)
    }

    /**
     * A stance that draws MORE would be the wrong stance. Both of the frames
     * that get out of the way also cost less, which is the property that makes
     * this affordable on a thermally-limited headset.
     */
    @Test fun theStancesThatGetOutOfTheWayAlsoDrawLess() {
        listOf(
            Theme.frameFor(Theme.Posture.FIELD, active = true),
            Theme.frameFor(Theme.Posture.TABLETOP),
        ).forEach { assertFalse(it.floorGrid) }
        assertTrue(Theme.frameFor(Theme.Posture.FIELD).floorGrid)
    }

    /**
     * The two odd themes are still the two odd themes. If a posture is ever
     * dropped from one of them this test says so, rather than the theme quietly
     * becoming the eighth FIELD theme in the picker.
     */
    @Test fun exactlyTwoThemesLeaveTheFieldPosture() {
        val odd = Theme.ALL.filter { it.posture != Theme.Posture.FIELD }
        assertEquals(odd.map { it.key }.toString(), 2, odd.size)
        assertEquals(Theme.Posture.TABLETOP, Theme.ALL.first { it.key == "biolume" }.posture)
        assertEquals(Theme.Posture.TRANSIT, Theme.ALL.first { it.key == "recon" }.posture)
    }

    /**
     * A TABLETOP THEME HAS TO BE REACHABLE FROM A CHAIR.
     *
     * 0.42 m below the eye is a table under a seated wearer. Shallower and the
     * model floats in the window where the world should be; deeper and a seated
     * person is looking at their own lap.
     */
    @Test fun theTabletopSitsWhereATableIs() {
        val f = Theme.frameFor(Theme.Posture.TABLETOP)
        assertTrue("drop is %.2f m".format(f.drop), f.drop <= -0.35f && f.drop >= -0.55f)
        // And below the horizon's own eye drop, or it is not a table at all.
        assertTrue(f.drop < Theme.frameFor(Theme.Posture.FIELD).drop)
    }
}
