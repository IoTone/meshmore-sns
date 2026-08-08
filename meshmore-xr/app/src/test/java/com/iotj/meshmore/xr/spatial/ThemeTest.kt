// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The theme table, and the property [Ink] depends on to restyle a live scene.
 *
 * The interesting test here is [rolesAreDistinguishableInEveryTheme]. Three of
 * the nine themes are single-hue by design and would collapse two roles onto
 * one value if left as the brief writes them; the palettes carry a one-unit
 * nudge to prevent that. Nothing on a headset would ever show the nudge being
 * lost — the symptom is that leaving RECON AMBER paints your body text in the
 * next theme's accent, which reads as a rendering bug in the theme you switched
 * TO. So it is asserted here, where it is cheap and where it fails loudly.
 */
class ThemeTest {

    @Test fun thereAreNine() {
        assertEquals(9, Theme.ALL.size)
    }

    @Test fun keysAreUniqueAndStable() {
        assertEquals(Theme.ALL.size, Theme.ALL.map { it.key }.toSet().size)
        // Persisted values. Changing one silently resets every wearer who chose it.
        assertEquals(
            listOf("halo", "seele", "recon", "aghud", "nerv", "drpop", "vector", "biolume", "void"),
            Theme.ALL.map { it.key },
        )
    }

    @Test fun defaultIsHaloFieldAndItIsFirst() {
        assertEquals("halo", Theme.DEFAULT.key)
        assertEquals("halo", Theme.ALL.first().key)
    }

    @Test fun everyColourIsAPlainRgbWithNoAlphaSmuggledIn() {
        // A palette entry with a byte in the top octet would survive every
        // comparison in Ink.roleOf (which masks) and then be written into
        // setBaseColorFactor's rgb shifts as garbage.
        Theme.ALL.forEach { s ->
            listOf(
                s.palette.accent, s.palette.alt, s.palette.warn, s.palette.text,
                s.palette.ground, s.palette.panel, s.palette.alert,
            ).forEach { c ->
                assertTrue("${s.key}: 0x%08X has bits above 24".format(c), c in 0..0xFFFFFF)
            }
        }
    }

    /** THE ONE THAT MATTERS. See the class note. */
    @Test fun rolesAreDistinguishableInEveryTheme() {
        Theme.ALL.forEach { s ->
            val p = s.palette
            val four = listOf(p.accent, p.alt, p.warn, p.text)
            assertEquals(
                "${s.key}: two roles share a value, so Ink cannot tell them apart",
                4, four.toSet().size,
            )
        }
    }

    /** And the nudge is genuinely invisible: one unit in one channel, at most. */
    @Test fun theNudgeIsBelowPerception() {
        listOf(Theme.SEELE, Theme.RECON, Theme.VOID).forEach { s ->
            val p = s.palette
            val four = listOf(p.accent, p.alt, p.warn, p.text)
            // Every pair that is nearly equal must differ by no more than 2/255
            // in a single channel — the nudge — and never by a whole step of hue.
            for (i in four.indices) for (j in i + 1 until four.size) {
                val d = channelDelta(four[i], four[j])
                assertTrue(
                    "${s.key}: 0x%06X vs 0x%06X differ by $d".format(four[i], four[j]),
                    d == 0 || d > 8 || d <= 2,
                )
            }
        }
    }

    @Test fun everyThemeSaysWhatItIs() {
        Theme.ALL.forEach { s ->
            assertTrue(s.key, s.name.isNotBlank())
            assertTrue(s.key, s.line.isNotBlank())
            assertTrue(s.key, s.audio.isNotBlank())
        }
        assertEquals(Theme.ALL.size, Theme.ALL.map { it.audio }.toSet().size)
    }

    /** Brief section 7.0: exactly two themes differ in posture, seven are FIELD. */
    @Test fun postureIsTheSecondAxisAndOnlyTwoThemesUseIt() {
        assertEquals(7, Theme.ALL.count { it.posture == Theme.Posture.FIELD })
        assertEquals(Theme.Posture.TRANSIT, Theme.RECON.posture)
        assertEquals(Theme.Posture.TABLETOP, Theme.BIOLUME.posture)
    }

    /**
     * Brief section 1.3: on additive optics a dark slab is not drawable, so an
     * ADDITIVE theme must never claim one.
     */
    @Test fun additiveThemesDoNotPaintASlab() {
        Theme.ALL.forEach { s ->
            assertEquals(s.key, s.substrate != Theme.Substrate.ADDITIVE, s.slab)
        }
    }

    @Test fun anUnknownKeyOpensIntoTheDefault() {
        assertEquals(Theme.DEFAULT, Theme.byKey(null))
        assertEquals(Theme.DEFAULT, Theme.byKey(""))
        assertEquals(Theme.DEFAULT, Theme.byKey("a-theme-from-a-later-build"))
        assertEquals(Theme.VECTOR, Theme.byKey("vector"))
    }

    @Test fun nextWrapsAllTheWayRound() {
        var s = Theme.DEFAULT
        repeat(Theme.ALL.size) { s = Theme.next(s) }
        assertEquals(Theme.DEFAULT, s)
    }

    // --- Ink's reverse lookup, which is pure and needs no session -------------

    @Test fun everyRoleLooksBackUpToItself() {
        Theme.ALL.forEach { s ->
            val p = s.palette
            assertEquals(s.key, Ink.Role.ACCENT, Ink.roleOf(p.accent, p))
            assertEquals(s.key, Ink.Role.ALT, Ink.roleOf(p.alt, p))
            assertEquals(s.key, Ink.Role.WARN, Ink.roleOf(p.warn, p))
            assertEquals(s.key, Ink.Role.TEXT, Ink.roleOf(p.text, p))
        }
    }

    @Test fun aColourOutsideThePaletteHasNoRoleAndIsLeftAlone() {
        // Hit proxies, the boot wordmark and the ruler overlay are deliberately
        // not themed. They must not be retinted, and must not throw.
        assertNull(Ink.roleOf(0x123456, Theme.HALO.palette))
    }

    @Test fun anAlphaCarryingArgbStillResolves() {
        // Text runs pass argb, not rgb — the alpha rides in the top octet.
        val argb = 0xF2.shl(24) or Theme.HALO.palette.text
        assertEquals(Ink.Role.TEXT, Ink.roleOf(argb, Theme.HALO.palette))
    }

    /**
     * A round trip through every theme resolves back to the same role every
     * time — which is the actual guarantee a retint chain needs. Switching
     * HALO -> RECON -> HALO must land back on the colours it started with.
     */
    @Test fun roleSurvivesEveryPairOfThemes() {
        Theme.ALL.forEach { from ->
            Theme.ALL.forEach { to ->
                Ink.Role.entries.forEach { role ->
                    val painted = Ink.rgbOf(role, to.palette)
                    assertEquals(
                        "${from.key} -> ${to.key} $role",
                        role, Ink.roleOf(painted, to.palette),
                    )
                }
            }
        }
    }

    @Test fun retintingAwayAndBackIsIdentity() {
        Ink.Role.entries.forEach { role ->
            val start = Ink.rgbOf(role, Theme.HALO.palette)
            val away = Ink.rgbOf(Ink.roleOf(start, Theme.HALO.palette)!!, Theme.RECON.palette)
            val back = Ink.rgbOf(Ink.roleOf(away, Theme.RECON.palette)!!, Theme.HALO.palette)
            assertEquals(start, back)
        }
    }

    @Test fun paletteDefaultsExistSoAnOldCallSiteStillCompilesMeaningfully() {
        val p = Horizon.Palette(accent = 1, alt = 2, warn = 3, text = 4)
        assertNotNull(p.ground)
        assertEquals(Theme.HALO.palette.ground, p.ground)
    }

    private fun channelDelta(a: Int, b: Int): Int = maxOf(
        Math.abs(((a shr 16) and 0xFF) - ((b shr 16) and 0xFF)),
        Math.abs(((a shr 8) and 0xFF) - ((b shr 8) and 0xFF)),
        Math.abs((a and 0xFF) - (b and 0xFF)),
    )
}
