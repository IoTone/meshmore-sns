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

    /**
     * EVERY THEME ARRIVES IN ITS OWN VOICE.
     *
     * [Cue.welcomeFor] falls back to HALO's tune for an unknown key, which is
     * the right behaviour and the perfect hiding place: a theme whose line was
     * never added plays a neighbour's welcome, on a headset, once, at the
     * moment the wearer is busy looking at a new scene. Five of the nine were
     * in exactly that state until the last three tracks arrived and two more
     * were synthesised.
     */
    @Test fun everyThemeHasItsOwnWelcome() {
        val byKey = Theme.ALL.associate { it.key to Cue.welcomeFor(it.key) }
        val fallback = Cue.welcomeFor("no-such-theme")
        byKey.forEach { (k, res) ->
            if (k != "halo") {
                assertTrue("$k has no welcome of its own — it is playing HALO's", res != fallback)
            }
        }
        assertEquals(
            "two themes share a welcome tune",
            byKey.size, byKey.values.toSet().size,
        )
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

    /**
     * §2: E11 "must be sonically distinct from E10". The distinction being
     * carried is categorical — a room, or you — so it cannot be the same sound
     * at a different volume, and every pack has to make the difference itself.
     */
    @Test fun aDirectMessageNeverSoundsLikeAChannelOne() {
        Cue.PACKS.forEach { p ->
            val differs = p.msgDirect != p.msgChannel || p.msgDirectMs != p.msgChannelMs
            assertTrue("${p.key}: E10 and E11 are the same event", differs)
        }
    }

    /** A DM is the longer of the two everywhere — it is the one worth turning for. */
    @Test fun aDirectMessageIsAlwaysTheLongerEvent() {
        Cue.PACKS.forEach { p ->
            assertTrue(p.key, p.msgDirectMs > p.msgChannelMs)
        }
    }

    /**
     * §4.4 lets a theme declare an event silent. TRIBUNAL declares E10 silent
     * and that is the permission's whole purpose — but no pack may go silent on
     * a DM, which is the one arrival that is definitely for you.
     */
    @Test fun onlyChannelArrivalMayBeSilentAndOnlyForTribunal() {
        Cue.PACKS.forEach { p ->
            assertTrue("${p.key} silenced a DM", p.msgDirect != Cue.SILENT)
            if (p.msgChannel == Cue.SILENT) assertEquals(Cue.TRIBUNAL.key, p.key)
        }
        assertEquals(Cue.SILENT, Cue.TRIBUNAL.msgChannel)
    }

    /** WAKE covers a fourteen-second build, so it may run long — but not forever. */
    @Test fun wakeIsTheLongEventAndTheOnlyOne() {
        Cue.PACKS.forEach { p ->
            assertTrue("${p.key} wake ${p.wakeMs}", p.wakeMs in 600..1200)
            assertTrue("${p.key}", p.wakeMs > p.openedMs)
            assertTrue("${p.key}", p.msgDirectMs < p.wakeMs)
        }
    }

    @Test fun everyPackStatesAllOfItsArrivalTones() {
        Cue.PACKS.forEach { p ->
            assertTrue(p.key, p.linkUpMs > 0)
            assertTrue(p.key, p.msgChannelMs >= 0)
        }
    }

    /**
     * E16 CRITICAL IS NOT A PACK FIELD, AND THAT IS THE POINT.
     *
     * §4.4: "Any theme may declare an event silent; NO THEME MAY DECLARE E16
     * CRITICAL SILENT." Every other event in Cue.Pack is a theme's to choose,
     * so making this one a table entry would invite a future theme to give it a
     * soft chime or nothing at all — forbidden, and nobody would notice until
     * it mattered. It is the same tone at the same length in all nine.
     *
     * This test cannot call critical() without a device, so it checks the
     * structural guarantee instead: there is no per-pack field to weaken.
     */
    @Test fun noPackCanWeakenTheCriticalEvent() {
        val fields = Cue.Pack::class.java.declaredFields.map { it.name.lowercase() }
        listOf("critical", "alert", "emergency", "distress").forEach { banned ->
            assertTrue(
                "Cue.Pack has a '$banned' field — E16 must not be a theme's to choose",
                fields.none { it.contains(banned) },
            )
        }
    }

    /** E7 is the noisiest event, so it must also be the shortest. */
    @Test fun discoveryIsTheBriefestThingAPackSays() {
        Cue.PACKS.forEach { p ->
            assertTrue("${p.key} discovery ${p.nodeFoundMs}ms", p.nodeFoundMs <= 200)
            // A silent channel event bounds nothing, so the comparison only
            // means something where the pack actually speaks. TRIBUNAL is
            // silent on both, which is its spec rather than an oversight.
            if (p.msgChannel != Cue.SILENT) {
                assertTrue(
                    "${p.key} announces a stranger louder than a message",
                    p.nodeFoundMs <= p.msgChannelMs,
                )
            }
        }
    }

    /**
     * A pack that silences ordinary channel traffic must not then announce
     * every stranger it meets — that is louder overall, not quieter.
     */
    @Test fun aSilentChannelPackIsSilentOnDiscoveryToo() {
        Cue.PACKS.filter { it.msgChannel == Cue.SILENT }.forEach { p ->
            assertEquals("${p.key}", Cue.SILENT, p.nodeFound)
        }
    }

    @Test fun anUnknownPackFallsBackRatherThanThrowing() {
        assertEquals(Cue.SONAR, Cue.packFor("not-a-pack"))
        assertEquals(Cue.CODEC, Cue.packFor("codec"))
    }
}
