// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE GHOST ROW, which cost a reply that never left the radio.
 *
 * The crown builds SLOTS rows once and re-labels them per level. Its tick only
 * ever touched rows `0 until labels().size`, so moving from a level with more
 * rows to a level with fewer left the surplus rows fully drawn — lit plates,
 * stale words, and LIVE HIT PROXIES. On the glasses that is a green slab
 * hanging in the room with no text on it (photographed 2026-08-08), and a
 * button that fires an index the current level has no label for. `poll()`
 * resolved that index to null, and a null ended the host's drain loop, so the
 * pick was swallowed in silence.
 *
 * Both halves are now fixed in Crown: surplus rows are disabled every frame,
 * and an action is resolved when the wearer PINCHES rather than when the host
 * drains. This pins the arithmetic that made it possible — the row counts per
 * level, and the fact that they differ.
 */
class CrownLevelTest {

    /** Mirrors Crown.labels(), which needs a Session and cannot be built here. */
    private fun rowsAt(level: String, suggestion: Boolean): Int = when (level) {
        "ACTIONS" -> 5
        "COMPOSE" -> 3 + (if (suggestion) 1 else 0) + 2
        "CONFIRM" -> 2
        else -> error(level)
    }

    private val slots = 6

    @Test fun everyLevelFitsInsideTheRowsThatWereBuilt() {
        listOf(
            "ACTIONS" to false, "ACTIONS" to true,
            "COMPOSE" to false, "COMPOSE" to true,
            "CONFIRM" to false, "CONFIRM" to true,
        ).forEach { (lvl, sug) ->
            val n = rowsAt(lvl, sug)
            assertTrue("$lvl needs $n rows, only $slots built", n <= slots)
        }
    }

    /**
     * The transition that produced the bug. Every one of these SHRINKS, which
     * is exactly when surplus rows are left behind.
     */
    @Test fun theShrinkingTransitionsAreTheDangerousOnes() {
        val shrinks = listOf(
            Triple("ACTIONS", "CONFIRM", false),
            Triple("COMPOSE", "CONFIRM", true),
            Triple("COMPOSE", "CONFIRM", false),
            Triple("ACTIONS", "CONFIRM", true),
        )
        shrinks.forEach { (from, to, sug) ->
            val a = rowsAt(from, sug)
            val b = rowsAt(to, sug)
            assertTrue(
                "$from -> $to does not shrink; this test is describing the wrong thing",
                b < a,
            )
        }
    }

    /**
     * CONFIRM is two answers and nothing else. A third row on the screen where
     * SEND lives is the one place a misfire actually transmits.
     */
    @Test fun confirmIsExactlyTwoRows() {
        assertEquals(2, rowsAt("CONFIRM", true))
        assertEquals(2, rowsAt("CONFIRM", false))
    }

    /** The autopen row appears and disappears, so COMPOSE changes size too. */
    @Test fun composeChangesSizeWithTheSuggestion() {
        assertEquals(5, rowsAt("COMPOSE", false))
        assertEquals(6, rowsAt("COMPOSE", true))
        // ...and six is the ceiling, so a seventh reply option needs more slots.
        assertEquals(slots, rowsAt("COMPOSE", true))
    }
}
