// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

/**
 * WHO MAY ASK THIS RADIO WHAT IT KNOWS.
 *
 * MeshCore packs three separate permissions into one byte — bits 0-1 base
 * (battery), 2-3 location, 4-5 environment — each at one of three levels. It
 * governs PERMISSION, not capability: allowing a class the device has no
 * sensor for simply yields nothing.
 *
 * SEPARATE CLASSES BECAUSE THEY ARE SEPARATE DECISIONS. Battery level is
 * nearly harmless; LOCATION is where the operator is standing. A single
 * "telemetry on/off" switch would force those two to be answered together,
 * and the one people would get wrong is the one that matters.
 *
 * Pure, so the packing can be argued without a radio — and it is the kind of
 * arithmetic that is silently wrong: a mis-shifted field does not fail, it
 * grants a permission somebody did not intend to grant.
 */
object TelemetryPerms {

    /** Nobody may ask. */
    const val DENY = 0
    /** Only contacts whose per-contact flags allow it (Contact.FLAG_TELEM_*). */
    const val ALLOW_FLAGS = 1
    /** Anyone who asks. */
    const val ALLOW_ALL = 2

    data class Perms(
        val base: Int = DENY,
        val location: Int = DENY,
        val environment: Int = DENY,
    ) {
        /** The byte the radio wants. */
        fun packed(): Int =
            clamp(base) or (clamp(location) shl 2) or (clamp(environment) shl 4)

        fun with(index: Int, level: Int): Perms = when (index) {
            0 -> copy(base = clamp(level))
            1 -> copy(location = clamp(level))
            else -> copy(environment = clamp(level))
        }

        fun level(index: Int): Int = when (index) {
            0 -> base
            1 -> location
            else -> environment
        }

        override fun toString(): String =
            "base=${name(base)} loc=${name(location)} env=${name(environment)}"
    }

    /** The three classes, in the order they sit in the byte. */
    val CLASSES = listOf("BATTERY", "LOCATION", "ENVIRONMENT")

    fun name(level: Int): String = when (clamp(level)) {
        DENY -> "DENY"
        ALLOW_FLAGS -> "CONTACTS"
        else -> "ANYONE"
    }

    /**
     * Unpack the radio's byte.
     *
     * 3 is undefined in the firmware, so it clamps to the highest DEFINED
     * level rather than being passed through — an unknown value must not read
     * as a stricter setting than the device is actually applying, because that
     * would show "DENY" over a radio answering everyone.
     */
    fun unpack(raw: Int): Perms = Perms(
        base = clamp(raw and 0x03),
        location = clamp((raw shr 2) and 0x03),
        environment = clamp((raw shr 4) and 0x03),
    )

    private fun clamp(v: Int): Int = v.coerceIn(DENY, ALLOW_ALL)
}
