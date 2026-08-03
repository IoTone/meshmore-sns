// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import androidx.xr.arcore.HandJointType
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Vector3
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The ASL classifier. Joints are synthesised along +Y from the wrist, which is
 * all the classifier looks at — distance from the wrist, scaled by hand size.
 */
class HandSignTest {

    /**
     * [index]..[little] are TIP REACH: how far the tip sits from the wrist as a
     * multiple of its own knuckle's distance. ~2.0 is a straight finger, ~1.0 a
     * curled one — the quantity the classifier actually tests.
     */
    private fun hand(
        thumb: Float, index: Float, middle: Float, ring: Float, little: Float,
        scale: Float = 0.09f,
        /**
         * Lateral separation between adjacent fingertips, as a fraction of
         * [scale]. 0 is the original fixture — every finger on one axis, which
         * cannot express a splayed hand at all and is why "four fingers
         * extended" went unchallenged as the whole test for B.
         */
        spread: Float = 0f,
    ): Map<HandJointType, Pose> = mapOf(
        HandJointType.WRIST to at(0f),
        HandJointType.MIDDLE_METACARPAL to at(scale),
        HandJointType.THUMB_PROXIMAL to at(scale),
        HandJointType.INDEX_PROXIMAL to at(scale),
        HandJointType.MIDDLE_PROXIMAL to at(scale),
        HandJointType.RING_PROXIMAL to at(scale),
        HandJointType.LITTLE_PROXIMAL to at(scale),
        // THE THUMB IS LATERAL. Placing it on the same axis as the fingers put
        // its tip within a few millimetres of the index tip, which is the
        // definition of a pinch — so every synthetic 'A' was being rejected as
        // one. The fixture was anatomically degenerate and the pinch test is
        // what exposed it.
        HandJointType.THUMB_TIP to Pose(Vector3(THUMB_OUT, thumb * scale, 0f)),
        HandJointType.INDEX_TIP to tip(index * scale, -1.5f * spread * scale),
        HandJointType.MIDDLE_TIP to tip(middle * scale, -0.5f * spread * scale),
        HandJointType.RING_TIP to tip(ring * scale, 0.5f * spread * scale),
        HandJointType.LITTLE_TIP to tip(little * scale, 1.5f * spread * scale),
    )

    private fun tip(y: Float, x: Float) = Pose(Vector3(x, y, 0f))

    private fun at(y: Float) = Pose(Vector3(0f, y, 0f))

    /** How far the thumb sits off the finger axis. About right for a hand. */
    private val THUMB_OUT = 0.05f

    /** A: a closed fist. Four curled fingers, thumb NOT on the index tip. */
    @Test fun aIsAClosedFist() {
        assertEquals(HandSign.Letter.A, HandSign.classify(hand(1.4f, 1.0f, 1.0f, 1.0f, 1.0f)))
    }

    /**
     * A PINCH IS NOT A LETTER, and this is the case that shipped broken:
     * selecting a node toggled the compass band, because a pinch curls all four
     * fingers and that was the entire test for 'A'.
     *
     * The two are separated by where the THUMB sits — meeting the index tip in
     * a pinch, alongside the curled index in 'A'.
     */
    @Test fun aPinchIsNotAnA() {
        assertEquals(HandSign.Letter.NONE, HandSign.classify(pinch()))
    }

    @Test fun theGapIsWhatSeparatesThem() {
        assertTrue("a pinch closes the gap", HandSign.pinchGap(pinch()) < HandSign.PINCH_GAP)
        assertTrue("an A holds it open", HandSign.pinchGap(fistA()) > HandSign.PINCH_GAP)
    }

    /** Missing joints must not read as a pinch and silently swallow every letter. */
    @Test fun anUnmeasurableGapDoesNotBlockLetters() {
        assertEquals(-1f, HandSign.pinchGap(emptyMap()), 1e-5f)
        assertEquals(HandSign.Letter.A, HandSign.classify(hand(1.4f, 1f, 1f, 1f, 1f)))
    }

    /** Thumb tip ON the index tip: the defining feature of a pinch. */
    private fun pinch() = hand(1.0f, 1.0f, 1.0f, 1.0f, 1.0f).toMutableMap().apply {
        this[HandJointType.INDEX_TIP] = at(0.09f)
        this[HandJointType.THUMB_TIP] = Pose(Vector3(0.002f, 0.091f, 0f))
    }

    /** Thumb alongside the curled index — the ASL 'A' position. */
    private fun fistA() = hand(1.4f, 1.0f, 1.0f, 1.0f, 1.0f)

    /**
     * The thumb is deliberately NOT part of it. ASL tells A from S by the thumb
     * and both are fists, but the thumb is the least reliably tracked joint on
     * the hand and we do not use S — requiring it bought a distinction nothing
     * depends on at the cost of the gesture working at all.
     */
    @Test fun theThumbDoesNotDecideIt() {
        assertEquals(HandSign.Letter.A, HandSign.classify(hand(0.8f, 1.0f, 1.0f, 1.0f, 1.0f)))
    }

    /** H: index and middle out together, ring and little down. */
    @Test fun hIsTwoFingers() {
        assertEquals(HandSign.Letter.H, HandSign.classify(hand(0.9f, 2.0f, 2.0f, 1.0f, 1.0f)))
    }

    /** The measured live hand: index straight, the other three folded. */
    @Test fun aPointingHandIsNotAFist() {
        assertEquals(HandSign.Letter.NONE, HandSign.classify(hand(2.0f, 2.0f, 1.1f, 1.0f, 1.0f)))
    }

    /**
     * An open hand is B, and that is a deliberate cost rather than an accident.
     *
     * ASL tells B from 5 by the thumb — folded across the palm for B, spread
     * for 5 — and we do not test the thumb, for the same reason it was dropped
     * from A: it is the least reliably tracked joint on the hand. So a relaxed
     * open hand reads as B.
     *
     * That is acceptable only because of what B DOES. It returns a magnified
     * ring to true bearing and is listened to ONLY while magnified, so a false
     * B undoes a view one pinch restores. A false A would change something the
     * user was not touching, which is why A keeps its stricter shape.
     */
    @Test fun anOpenHandIsB() {
        assertEquals(HandSign.Letter.B, HandSign.classify(hand(1.4f, 2.0f, 2.0f, 2.0f, 2.0f)))
    }

    @Test fun aHandWithNoJointsIsSilent() {
        assertEquals(HandSign.Letter.NONE, HandSign.classify(emptyMap()))
    }

    /** Thresholds scale with the hand, so a small hand is not permanently a fist. */
    @Test fun classificationIsScaleInvariant() {
        assertEquals(HandSign.Letter.A, HandSign.classify(hand(1.4f, 1f, 1f, 1f, 1f, scale = 0.05f)))
        assertEquals(HandSign.Letter.A, HandSign.classify(hand(1.4f, 1f, 1f, 1f, 1f, scale = 0.14f)))
    }

    // ---- the gate ---------------------------------------------------------

    /** A shape has to be HELD. Hands make shapes constantly; almost none are commands. */
    @Test fun aLetterMustBeHeldBeforeItFires() {
        val g = HandSign.Gate(dwellMs = 400)
        assertEquals(HandSign.Letter.NONE, g.update(HandSign.Letter.A, 0))
        assertEquals(HandSign.Letter.NONE, g.update(HandSign.Letter.A, 399))
        assertEquals(HandSign.Letter.A, g.update(HandSign.Letter.A, 400))
    }

    /** And fires ONCE — holding a fist must not toggle a surface forty times a second. */
    @Test fun holdingDoesNotRepeat() {
        val g = HandSign.Gate(dwellMs = 400)
        g.update(HandSign.Letter.A, 0)
        assertEquals(HandSign.Letter.A, g.update(HandSign.Letter.A, 500))
        assertEquals(HandSign.Letter.NONE, g.update(HandSign.Letter.A, 900))
        assertEquals(HandSign.Letter.NONE, g.update(HandSign.Letter.A, 5000))
    }

    /** Leaving the shape re-arms it. */
    @Test fun releasingAllowsAnotherFire() {
        val g = HandSign.Gate(dwellMs = 400)
        g.update(HandSign.Letter.A, 0)
        assertEquals(HandSign.Letter.A, g.update(HandSign.Letter.A, 400))
        g.update(HandSign.Letter.NONE, 500)
        g.update(HandSign.Letter.A, 600)
        assertEquals(HandSign.Letter.A, g.update(HandSign.Letter.A, 1000))
    }

    /** A shape passed through on the way to another must not fire. */
    @Test fun aTransientShapeIsIgnored() {
        val g = HandSign.Gate(dwellMs = 400)
        g.update(HandSign.Letter.A, 0)
        g.update(HandSign.Letter.H, 100)
        assertEquals(HandSign.Letter.NONE, g.update(HandSign.Letter.A, 300))
    }

    // --- B is a DELIBERATE flat hand, not any open one -----------------------

    /**
     * The bug of 2026-08-02: the magnified view kept collapsing on its own.
     * 'B' tested only that four fingers were extended, which is an open hand —
     * so a hand resting in view issued a command, and because B is only
     * listened to while magnified, the one moment it could fire was the one
     * moment it destroyed work.
     */
    @Test fun bNeedsTheFingersTogether() {
        assertEquals(
            HandSign.Letter.B,
            HandSign.classify(hand(1.2f, 2f, 2f, 2f, 2f, spread = 0.15f)),
        )
        assertEquals(
            "a splayed open hand is not a letter",
            HandSign.Letter.NONE,
            HandSign.classify(hand(1.2f, 2f, 2f, 2f, 2f, spread = 0.9f)),
        )
    }

    /** Spread is scale-free, like every other measure in the classifier. */
    @Test fun spreadDoesNotDependOnHandSize() {
        val small = HandSign.spread(hand(1.2f, 2f, 2f, 2f, 2f, scale = 0.06f, spread = 0.5f))
        val large = HandSign.spread(hand(1.2f, 2f, 2f, 2f, 2f, scale = 0.12f, spread = 0.5f))
        assertTrue("small=$small large=$large", kotlin.math.abs(small - large) < 0.02f)
    }

    /** Missing joints are UNKNOWN, and unknown must not read as "together". */
    @Test fun spreadIsNegativeWhenJointsAreMissing() {
        assertTrue(HandSign.spread(emptyMap()) < 0f)
        assertEquals(HandSign.Letter.NONE, HandSign.classify(emptyMap()))
    }

    /**
     * A and H are unaffected: neither depends on the fingers being together.
     *
     * Splayed to 0.45, a relaxed hand, and NOT to the 0.9 the B rejection uses.
     * The fixture offsets tips laterally, which lengthens wrist-to-tip — so an
     * anatomically absurd splay makes a CURLED finger measure as extended and
     * the test fails for a reason that has nothing to do with what it checks.
     * Written down because it caught me: the first version of this test failed
     * on H and the classifier was right.
     */
    @Test fun spreadDoesNotDisturbTheOtherLetters() {
        assertEquals(
            HandSign.Letter.A,
            HandSign.classify(hand(1.4f, 1.0f, 1.0f, 1.0f, 1.0f, spread = 0.45f)),
        )
        assertEquals(
            HandSign.Letter.H,
            HandSign.classify(hand(1.4f, 2.0f, 2.0f, 1.0f, 1.0f, spread = 0.45f)),
        )
    }
}

/**
 * Orientation. A hand shape is only half a letter: ASL forms its letters with
 * the palm toward the receiver, so a fist held palm-first at your own face is
 * the BACK of an 'A' rather than an 'A'.
 */
class HandFacingTest {

    /**
     * The joint layout that produced a correctly-oriented 'A' on the device,
     * with the convention pinned by observation rather than by derivation —
     * see HandSign.palmNormal. What these lock down is that the two hands stay
     * MIRRORED: the same physical gesture must give the same answer on either
     * hand, and that is the part a sign error breaks silently.
     */
    private fun rightHandNormal() = HandSign.palmNormal(
        0f, 0f, 0f, -0.04f, 0.09f, 0f, 0.04f, 0.09f, 0f, rightHand = true,
    )

    private fun leftHandNormal() = HandSign.palmNormal(
        0f, 0f, 0f, 0.04f, 0.09f, 0f, -0.04f, 0.09f, 0f, rightHand = false,
    )

    /**
     * THE INVARIANT THAT MATTERS. Mirror the knuckles and flip the hand flag —
     * the same gesture on the other hand — and the normal must come out the
     * same way. If it does not, one hand accepts the letter and the other
     * refuses it, which presents as "it only works with my left hand" and is
     * exactly what a handedness sign error does.
     */
    @Test fun bothHandsAgreeOnTheSameGesture() {
        val (rx, ry, rz) = rightHandNormal()
        val (lx, ly, lz) = leftHandNormal()
        assertEquals(rx, lx, 1e-5f)
        assertEquals(ry, ly, 1e-5f)
        assertEquals(rz, lz, 1e-5f)
    }

    @Test fun theNormalIsPerpendicularToThePalmPlane() {
        val (nx, ny, nz) = rightHandNormal()
        // Knuckles and wrist lie in the XY plane here, so the normal is on Z.
        assertEquals(0f, nx, 1e-5f)
        assertEquals(0f, ny, 1e-5f)
        assertTrue("normal must be a unit direction along Z, got $nz",
            kotlin.math.abs(nz) > 0.99f)
    }

    /** Degenerate input must not produce a confident direction. */
    @Test fun collinearJointsGiveNoNormal() {
        val n = HandSign.palmNormal(0f, 0f, 0f, 0f, 0.09f, 0f, 0f, 0.18f, 0f, rightHand = true)
        assertEquals(Triple(0f, 0f, 0f), n)
    }

    private val fist = mapOf(
        HandJointType.WRIST to Pose(Vector3(0f, 0f, 0f)),
        HandJointType.MIDDLE_METACARPAL to Pose(Vector3(0f, 0.09f, 0f)),
        HandJointType.THUMB_PROXIMAL to Pose(Vector3(0f, 0.09f, 0f)),
        HandJointType.INDEX_PROXIMAL to Pose(Vector3(0f, 0.09f, 0f)),
        HandJointType.MIDDLE_PROXIMAL to Pose(Vector3(0f, 0.09f, 0f)),
        HandJointType.RING_PROXIMAL to Pose(Vector3(0f, 0.09f, 0f)),
        HandJointType.LITTLE_PROXIMAL to Pose(Vector3(0f, 0.09f, 0f)),
        // Lateral, like a real thumb — see the note in HandSignTest.hand().
        HandJointType.THUMB_TIP to Pose(Vector3(0.05f, 0.126f, 0f)),
        HandJointType.INDEX_TIP to Pose(Vector3(0f, 0.09f, 0f)),
        HandJointType.MIDDLE_TIP to Pose(Vector3(0f, 0.09f, 0f)),
        HandJointType.RING_TIP to Pose(Vector3(0f, 0.09f, 0f)),
        HandJointType.LITTLE_TIP to Pose(Vector3(0f, 0.09f, 0f)),
    )

    @Test fun aFistWithThePalmAwayIsAnA() {
        assertEquals(HandSign.Letter.A, HandSign.classify(fist, palmAway = true))
    }

    /** The case reported from the glasses: it fired from either side. */
    @Test fun aFistWithThePalmTowardTheWearerIsNot() {
        assertEquals(HandSign.Letter.NONE, HandSign.classify(fist, palmAway = false))
    }

    /**
     * Unknown orientation accepts the shape. Refusing every letter whenever one
     * knuckle drops out would make the vocabulary fail exactly when tracking is
     * marginal, which is when it is most needed.
     */
    @Test fun unknownOrientationJudgesTheShapeAlone() {
        assertEquals(HandSign.Letter.A, HandSign.classify(fist, palmAway = null))
    }

    /** Orientation can only reject. It cannot invent a letter. */
    @Test fun orientationNeverCreatesALetter() {
        assertEquals(HandSign.Letter.NONE, HandSign.classify(emptyMap(), palmAway = true))
    }
}

/** B — the flat hand that returns a magnified ring to true bearing. */
class HandBTest {

    private fun at(y: Float) = Pose(Vector3(0f, y, 0f))
    private val OUT = 0.05f

    private fun hand(thumb: Float, i: Float, m: Float, r: Float, l: Float, s: Float = 0.09f) = mapOf(
        HandJointType.WRIST to at(0f),
        HandJointType.MIDDLE_METACARPAL to at(s),
        HandJointType.THUMB_PROXIMAL to at(s),
        HandJointType.INDEX_PROXIMAL to at(s),
        HandJointType.MIDDLE_PROXIMAL to at(s),
        HandJointType.RING_PROXIMAL to at(s),
        HandJointType.LITTLE_PROXIMAL to at(s),
        HandJointType.THUMB_TIP to Pose(Vector3(OUT, thumb * s, 0f)),
        HandJointType.INDEX_TIP to at(i * s),
        HandJointType.MIDDLE_TIP to at(m * s),
        HandJointType.RING_TIP to at(r * s),
        HandJointType.LITTLE_TIP to at(l * s),
    )

    @Test fun bIsAFlatHand() {
        assertEquals(HandSign.Letter.B, HandSign.classify(hand(1.2f, 2f, 2f, 2f, 2f)))
    }

    /** The three letters must not overlap: each needs a different finger set. */
    @Test fun theLettersAreDistinct() {
        assertEquals(HandSign.Letter.A, HandSign.classify(hand(1.4f, 1f, 1f, 1f, 1f)))
        assertEquals(HandSign.Letter.H, HandSign.classify(hand(1.0f, 2f, 2f, 1f, 1f)))
        assertEquals(HandSign.Letter.B, HandSign.classify(hand(1.2f, 2f, 2f, 2f, 2f)))
    }

    /** Orientation applies to every letter, not only to A. */
    @Test fun bAlsoNeedsThePalmAway() {
        assertEquals(HandSign.Letter.NONE,
            HandSign.classify(hand(1.2f, 2f, 2f, 2f, 2f), palmAway = false))
    }

}
