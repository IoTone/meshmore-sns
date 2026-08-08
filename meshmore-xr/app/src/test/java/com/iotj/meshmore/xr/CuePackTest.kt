// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.Theme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The packs are a table, so they are checked like one.
 *
 * The test that earns its place is [everyThemesPackExists]: a theme names its
 * pack with a string, [Cue.packFor] falls back rather than throwing, and the
 * failure mode of a typo is therefore that one of the nine themes silently
 * sounds like HALO FIELD. Nobody would notice that on a headset, and it would
 * ship.
 */
class CuePackTest {

    @Test fun everyThemesPackExists() {
        Theme.ALL.forEach { s ->
            val p = Cue.PACKS.firstOrNull { it.key == s.audio }
            assertNotNull("${s.key} names audio pack '${s.audio}', which does not exist", p)
        }
    }

    @Test fun thereIsOnePackPerThemeAndNoSpares() {
        assertEquals(Theme.ALL.size, Cue.PACKS.size)
        assertEquals(Theme.ALL.map { it.audio }.toSet(), Cue.PACKS.map { it.key }.toSet())
    }

    @Test fun packKeysAreUnique() {
        assertEquals(Cue.PACKS.size, Cue.PACKS.map { it.key }.toSet().size)
    }

    /**
     * The detent fires several times a second on a turning reel. A pack whose
     * tick is as long as its other events would drone.
     */
    @Test fun theDetentIsTheShortestEventInEveryPack() {
        Cue.PACKS.forEach { p ->
            assertTrue(p.key, p.tickMs <= p.recognisedMs)
            assertTrue(p.key, p.tickMs <= p.openedMs)
            assertTrue(p.key, p.tickMs <= p.closedMs)
            assertTrue("${p.key}: a ${p.tickMs}ms detent will drone on a scrub", p.tickMs <= 40)
        }
    }

    /** A closed/declined event is the one that must not be missed. */
    @Test fun closingIsAlwaysAsLongAsOpening() {
        Cue.PACKS.forEach { p -> assertTrue(p.key, p.closedMs >= p.openedMs) }
    }

    @Test fun volumesAreAudibleButNeverStartling() {
        Cue.PACKS.forEach { p ->
            assertTrue("${p.key} at ${p.vol}", p.vol in 40..90)
        }
    }

    /** TRIBUNAL's spec is "near-silence otherwise". It should be the quietest. */
    @Test fun tribunalIsTheQuietestAndPurePhaseTheLoudest() {
        assertEquals(Cue.TRIBUNAL, Cue.PACKS.minByOrNull { it.vol })
        assertEquals(Cue.PUREPHASE, Cue.PACKS.maxByOrNull { it.vol })
    }

    @Test fun anUnknownPackFallsBackRatherThanThrowing() {
        assertEquals(Cue.SONAR, Cue.packFor("not-a-pack"))
        assertEquals(Cue.CODEC, Cue.packFor("codec"))
    }
}
