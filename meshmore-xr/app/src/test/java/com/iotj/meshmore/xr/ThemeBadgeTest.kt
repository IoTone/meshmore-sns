// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.Theme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE MARKS UNDER A THEME TILE.
 *
 * They are derived rather than typed, so what needs proving is that the
 * derivation says something — a badge that appears on every tile is a
 * decoration, and one that never appears is a lie about the vocabulary.
 */
class ThemeBadgeTest {

    private val all = Theme.ALL

    /** Exactly one posture, always, because it is a choice between three. */
    @Test fun everyThemeCarriesOnePosture() {
        val postures = setOf(Theme.Badge.FIELD, Theme.Badge.TABLETOP, Theme.Badge.TRANSIT)
        all.forEach { s ->
            assertEquals(
                "${s.key} posture marks",
                1, Theme.badgesFor(s).count { it in postures },
            )
        }
    }

    /** A mark on all nine says nothing; a mark on none is dead vocabulary. */
    @Test fun everyOptionalMarkDiscriminates() {
        listOf(Theme.Badge.NIGHT, Theme.Badge.ACTIVE, Theme.Badge.ALIVE).forEach { b ->
            val n = all.count { b in Theme.badgesFor(it) }
            assertTrue("$b appears on $n of ${all.size}", n in 1 until all.size)
        }
    }

    /**
     * THE NIGHT RULE, ON THE THREE CASES THAT DEFINE IT. Amber and phosphor
     * pass; bone-white is monochrome but not dark-adapted, and is the case a
     * hand-written list gets wrong.
     */
    @Test fun nightIsLowBlueNotMerelyMonochrome() {
        fun night(key: String) = Theme.Badge.NIGHT in Theme.badgesFor(Theme.byKey(key))
        assertTrue("recon amber", night("recon"))
        assertTrue("void terminal", night("void"))
        assertFalse("seele is monochrome bone, not night", night("seele"))
        assertFalse("halo is cyan", night("halo"))
        // THE CASE THE MEAN GOT WRONG. NERV's accent, alt and warn hold no
        // blue at all, so an average made it a night theme and hid a near-white
        // text at 245 — the surface a wearer reads.
        assertFalse("nerv reads on bone white", night("nerv"))
        assertEquals(245, Theme.blueLevel(Theme.byKey("nerv").palette))
    }

    /** TRANSIT already says "worn while moving" — never both marks for one fact. */
    @Test fun activeIsNeverShownBesideTransit() {
        all.forEach { s ->
            val b = Theme.badgesFor(s)
            assertFalse(
                "${s.key} carries both",
                Theme.Badge.TRANSIT in b && Theme.Badge.ACTIVE in b,
            )
        }
    }

    /** Four marks is the most a tile can hold at the pitch the grid uses. */
    @Test fun noThemeCarriesMoreThanFour() {
        all.forEach { s ->
            val n = Theme.badgesFor(s).size
            assertTrue("${s.key} has $n marks", n <= 4)
        }
    }

    /** Exactly one substrate, always — the axis that splits the nine evenly. */
    @Test fun everyThemeCarriesOneSubstrate() {
        val subs = setOf(Theme.Badge.PANEL, Theme.Badge.ADDITIVE, Theme.Badge.HYBRID)
        all.forEach { s ->
            assertEquals("${s.key}", 1, Theme.badgesFor(s).count { it in subs })
        }
        // And it really does split them, rather than landing on one value.
        subs.forEach { b ->
            assertEquals("$b", 3, all.count { b in Theme.badgesFor(it) })
        }
    }

    /** No tile is left with nothing to say about itself. */
    @Test fun noTileCarriesFewerThanTwo() {
        all.forEach { s ->
            assertTrue("${s.key}", Theme.badgesFor(s).size >= 2)
        }
    }

    /** Every mark has a plain-text form for a font that lacks the glyph. */
    @Test fun everyMarkHasAFallback() {
        Theme.Badge.entries.forEach {
            assertTrue(it.name, it.glyph.isNotBlank() && it.plain.isNotBlank())
        }
    }
}
