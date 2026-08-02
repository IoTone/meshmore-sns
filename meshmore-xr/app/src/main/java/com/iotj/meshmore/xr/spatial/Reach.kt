// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.os.SystemClock

/**
 * WHEN THE HAND IS BUSY REACHING, IT IS NOT SIGNING.
 *
 * Pinching and ASL 'A' are nearly the same shape — four fingers curled — and
 * HandSign.pinchGap now tells them apart by where the thumb sits. That is the
 * right fix and it should not be the only one.
 *
 * A threshold can be wrong by a little; an INTERLOCK cannot. When a pointer is
 * over something pinchable, or a pinch has just been delivered, the user is
 * plainly operating a control and any letter the classifier believes it sees is
 * a misreading of that intent. Refusing to look is free, and it is correct
 * regardless of where the threshold ends up.
 *
 * The asymmetry is what justifies it. A missed HUD toggle costs a second
 * gesture. A HUD that flips while you are selecting a node changes something
 * the user did not ask about, WHILE they are asking about something else — and
 * they then have to work out which of the two things they did caused it.
 *
 * Shared mutable state, deliberately. Every interactable surface can raise it
 * and the gesture loop reads it; threading a flag through Horizon, Dock, Rack
 * and HereMark to reach one call site would be more machinery for the same
 * meaning.
 */
object Reach {

    @Volatile private var busyUntil = 0L
    @Volatile private var hovering = false

    /** A pointer is over something pinchable. Set every frame it remains true. */
    fun setHovering(v: Boolean) { hovering = v }

    /** A pinch was just delivered to a control. */
    fun consumed() { busyUntil = SystemClock.uptimeMillis() + TAIL_MS }

    /**
     * True while gestures should be ignored.
     *
     * The TAIL is the important half: a pinch ends with the hand still curled
     * and still in view, which is a fist for as long as it takes to relax. The
     * dwell is 450 ms, so the tail has to outlast it or the letter fires just
     * after the selection it was part of.
     */
    fun busy(): Boolean = hovering || SystemClock.uptimeMillis() < busyUntil

    private const val TAIL_MS = 900L
}
