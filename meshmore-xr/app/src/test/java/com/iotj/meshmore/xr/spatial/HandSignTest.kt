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
    ): Map<HandJointType, Pose> = mapOf(
        HandJointType.WRIST to at(0f),
        HandJointType.MIDDLE_METACARPAL to at(scale),
        HandJointType.THUMB_PROXIMAL to at(scale),
        HandJointType.INDEX_PROXIMAL to at(scale),
        HandJointType.MIDDLE_PROXIMAL to at(scale),
        HandJointType.RING_PROXIMAL to at(scale),
        HandJointType.LITTLE_PROXIMAL to at(scale),
        HandJointType.THUMB_TIP to at(thumb * scale),
        HandJointType.INDEX_TIP to at(index * scale),
        HandJointType.MIDDLE_TIP to at(middle * scale),
        HandJointType.RING_TIP to at(ring * scale),
        HandJointType.LITTLE_TIP to at(little * scale),
    )

    private fun at(y: Float) = Pose(Vector3(0f, y, 0f))

    /** A: a closed fist. Four curled fingers is the whole test. */
    @Test fun aIsAClosedFist() {
        assertEquals(HandSign.Letter.A, HandSign.classify(hand(1.4f, 1.0f, 1.0f, 1.0f, 1.0f)))
    }

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

    /** A and H disagree on exactly the fingers A needs curled, so no wobble confuses them. */
    @Test fun anOpenHandIsNeither() {
        assertEquals(HandSign.Letter.NONE, HandSign.classify(hand(1.4f, 2.0f, 2.0f, 2.0f, 2.0f)))
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
}

/**
 * Orientation. A hand shape is only half a letter: ASL forms its letters with
 * the palm toward the receiver, so a fist held palm-first at your own face is
 * the BACK of an 'A' rather than an 'A'.
 */
class HandFacingTest {

    /** Right palm toward +Z: index knuckle to -X, little to +X, fingers up. */
    private fun rightPalmToward() = HandSign.palmNormal(
        0f, 0f, 0f, -0.04f, 0.09f, 0f, 0.04f, 0.09f, 0f, rightHand = true,
    )

    /** Left hand is the mirror: index knuckle to +X. */
    private fun leftPalmToward() = HandSign.palmNormal(
        0f, 0f, 0f, 0.04f, 0.09f, 0f, -0.04f, 0.09f, 0f, rightHand = false,
    )

    @Test fun therightPalmNormalPointsOutOfThePalm() {
        val (_, _, nz) = rightPalmToward()
        assertTrue("right palm facing +Z should give a +Z normal, got $nz", nz > 0.9f)
    }

    @Test fun theLeftHandIsMirroredNotIdentical() {
        val (_, _, nz) = leftPalmToward()
        assertTrue("left palm facing +Z should give a +Z normal, got $nz", nz > 0.9f)
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
        HandJointType.THUMB_TIP to Pose(Vector3(0f, 0.126f, 0f)),
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
