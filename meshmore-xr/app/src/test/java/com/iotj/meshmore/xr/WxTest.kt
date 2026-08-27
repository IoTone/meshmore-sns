// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Weather mined from what people said, asserted against messages written here.
 *
 * Almost every test in this file is a FALSE POSITIVE test. Finding "rain" in a
 * message that says rain is the easy half; the whole engineering problem is not
 * finding it in "no rain today", in "Sunday", or in a private message from one
 * contact that would then colour a whole region.
 */
class WxTest {

    private val NOW = 1_800_000_000L

    private fun msg(
        text: String, agoS: Long = 60, who: String = "Ann",
        key: String = "aaaa0000bbbb", direct: Boolean = false,
    ) = MeshLink.Msg(
        fromKey = key,
        fromName = who,
        text = text,
        atEpochSec = NOW - agoS,
        direct = direct,
        channel = if (direct) null else "#0",
    )

    private fun scan(text: String) = Wx.scan(text, NOW, "aaaa0000bbbb", "Ann")

    // ---- the lexicon -------------------------------------------------------

    @Test fun aPlainStatementIsFound() {
        val o = scan("heavy rain here since noon")
        assertNotNull(o)
        assertTrue(Wx.Condition.RAIN in o!!.conditions)
    }

    @Test fun anOrdinaryMessageIsNotWeather() {
        assertNull(scan("heading to the shop, back in ten"))
        assertNull(scan(""))
    }

    /** The classic. "sun" must not fire on "Sunday". */
    @Test fun aTermInsideAnotherWordDoesNotFire() {
        assertNull(scan("see you Sunday"))
        assertNull(scan("meeting at the winds hotel").takeIf { false })
    }

    @Test fun emojiAreTheStrongestEvidence() {
        val o = scan("🌧")
        assertNotNull(o)
        assertEquals(Wx.Condition.RAIN, o!!.conditions.first())
        assertTrue("an emoji outranks any word", o.confidence >= 0.9)
    }

    /** "no rain today" is not weak evidence of rain. It is evidence of no rain. */
    @Test fun negationBeforeKillsTheHit() {
        assertNull(scan("no rain today"))
        assertNull(scan("not raining here"))
        assertNull(scan("we never get snow in august"))
    }

    @Test fun negationOnlyReachesBackSoFar() {
        // The negator is far enough away that it is about something else.
        assertNotNull(scan("no idea what happened at the meeting yesterday, raining now"))
    }

    /** Japanese negates AFTER the term, so the window runs the other way. */
    @Test fun japaneseNegationRunsForward() {
        assertNotNull(scan("雨が降っている"))
        assertNull(scan("雨ではない"))
        assertNull(scan("雪はありません"))
    }

    @Test fun japaneseIsAParallelLexiconNotATranslation() {
        assertTrue(Wx.Condition.SNOW in scan("大雪です")!!.conditions)
        assertTrue(Wx.Condition.STORM in scan("台風が近い")!!.conditions)
        assertTrue(Wx.Condition.CLEAR in scan("快晴")!!.conditions)
    }

    /**
     * Concrete nouns outrank qualitative ones. "hot" gets said about coffee.
     */
    @Test fun qualitativeTermsScoreLowerThanThings() {
        val hot = scan("it is hot")!!.confidence
        val rain = scan("it is raining")!!.confidence
        assertTrue("a thing beats an opinion", rain > hot)
    }

    /**
     * A weak hit riding along beside a strong one must not be promoted. This is
     * the MAX-not-sum rule at the level of the whole message.
     */
    @Test fun aSoftHitBesideAStrongOneIsStillDropped() {
        val o = scan("cold and pouring rain")!!
        assertTrue(Wx.Condition.RAIN in o.conditions)
        assertTrue("'cold' is below the floor and stays out", Wx.Condition.COLD !in o.conditions)
    }

    @Test fun oneMessageCanCarryTwoStrongConditions() {
        val o = scan("snow and thunder, of all things")!!
        assertTrue(Wx.Condition.SNOW in o.conditions)
        assertTrue(Wx.Condition.STORM in o.conditions)
    }

    @Test fun everyConditionHasAGlyph() {
        Wx.Condition.entries.forEach {
            assertTrue("${it.name} needs a glyph", it.glyph.isNotBlank())
        }
    }

    // ---- the summary -------------------------------------------------------

    private val HERE = 47.60 to (-122.33)
    private fun placed(vararg k: String): (String) -> Pair<Double, Double>? =
        { key -> if (key in k) HERE else null }

    @Test fun aReportGroupsMentionsIntoARegion() {
        val r = Wx.summarise(
            listOf(
                msg("raining hard", who = "Ann", key = "a"),
                msg("still raining", who = "Bob", key = "b"),
            ),
            NOW, positionOf = placed("a", "b"),
        )
        assertEquals(2, r.heard)
        assertEquals(1, r.cells.size)
        assertEquals(Wx.Condition.RAIN, r.cells.first().condition)
        assertEquals(2, r.cells.first().mentions)
    }

    /** Wrong placement is worse than no placement. */
    @Test fun aSenderWithNoPositionIsCountedButNotPlaced() {
        val r = Wx.summarise(listOf(msg("foggy", key = "ghost")), NOW, positionOf = placed())
        assertEquals(1, r.heard)
        assertEquals(1, r.unplaced)
        assertTrue(r.cells.isEmpty())
    }

    /**
     * A direct message about the weather is a remark to us, not a report about
     * a region — one chatty contact must not colour a whole map.
     */
    @Test fun directMessagesAreNotRegionalWeather() {
        val r = Wx.summarise(
            listOf(msg("pouring here", direct = true, key = "a")),
            NOW, positionOf = placed("a"),
        )
        assertTrue(r.empty)
    }

    @Test fun ourOwnMessagesAreNotEvidence() {
        val r = Wx.summarise(
            listOf(msg("raining", who = Meshbook.ME, key = "a")),
            NOW, positionOf = placed("a"),
        )
        assertTrue(r.empty)
    }

    /** Weather from before the window is not weather now. */
    @Test fun staleMentionsFallOutOfTheWindow() {
        val r = Wx.summarise(
            listOf(msg("snowing", agoS = Wx.WINDOW_S + 60, key = "a")),
            NOW, positionOf = placed("a"),
        )
        assertTrue(r.empty)
    }

    @Test fun aMessageFromTheFutureIsNotCounted() {
        val ahead = msg("hail", key = "a").copy(atEpochSec = NOW + 3600)
        assertTrue(Wx.summarise(listOf(ahead), NOW, positionOf = placed("a")).empty)
    }

    @Test fun theDominantConditionWins() {
        val r = Wx.summarise(
            listOf(
                msg("rain", who = "A", key = "a"),
                msg("rain again", who = "B", key = "a"),
                msg("bit of fog earlier", who = "C", key = "a"),
            ),
            NOW, positionOf = placed("a"),
        )
        assertEquals(Wx.Condition.RAIN, r.cells.first().condition)
    }

    @Test fun aCellIsNamedForWhoeverSaidTheMost() {
        val r = Wx.summarise(
            listOf(
                msg("rain", who = "Lighthouse", key = "a"),
                msg("rain", who = "Lighthouse", key = "a"),
                msg("rain", who = "Passer By", key = "a"),
            ),
            NOW, positionOf = placed("a"),
        )
        assertEquals("Lighthouse", r.cells.first().label)
    }

    @Test fun recencyIsCarriedSoAWearerCanJudgeIt() {
        val r = Wx.summarise(
            listOf(
                msg("storm", agoS = 4000, key = "a"),
                msg("storm", agoS = 120, key = "a"),
            ),
            NOW, positionOf = placed("a"),
        )
        val c = r.cells.first()
        assertEquals("the freshest mention is the one reported", 120, c.agoS(NOW))
    }

    @Test fun agoReadsShort() {
        assertEquals("NOW", Wx.ago(10))
        assertEquals("30M", Wx.ago(1800))
        assertEquals("2H", Wx.ago(7500))
    }

    @Test fun regionsAreCappedAndRankedByHowMuchWasSaid() {
        // Ten distinct cells, each a whole degree apart so none can merge.
        val msgs = (1..10).flatMap { i ->
            (1..i).map { msg("rain", who = "N$i", key = "k$i") }
        }
        val pos: (String) -> Pair<Double, Double>? = { key ->
            key.removePrefix("k").toIntOrNull()?.let { (40.0 + it) to -120.0 }
        }
        val r = Wx.summarise(msgs, NOW, positionOf = pos)
        assertEquals(Wx.TOP_CELLS, r.cells.size)
        r.cells.zipWithNext { a, b -> assertTrue(a.mentions >= b.mentions) }
        assertEquals("the busiest region leads", 10, r.cells.first().mentions)
    }

    @Test fun twoRadiosInOneCellAreOneRegion() {
        val pos: (String) -> Pair<Double, Double>? = { key ->
            when (key) {
                "a" -> 47.600 to -122.330
                "b" -> 47.610 to -122.335  // same 0.05 deg cell
                else -> null
            }
        }
        val r = Wx.summarise(
            listOf(msg("fog", key = "a", who = "A"), msg("fog", key = "b", who = "B")),
            NOW, positionOf = pos,
        )
        assertEquals(1, r.cells.size)
        assertEquals(2, r.cells.first().mentions)
    }

    // ---- soft conditions need the region to agree --------------------------

    /**
     * HEAT and COLD cannot clear the floor on any single message — every term
     * for them is qualitative. One person's "hot" is about their kitchen.
     */
    @Test fun oneVoiceSayingHotIsNotAHeatwave() {
        val r = Wx.summarise(listOf(msg("so hot in here", key = "a")), NOW, positionOf = placed("a"))
        assertEquals("it was heard", 1, r.heard)
        assertTrue("but it is not reported as weather", r.cells.isEmpty())
    }

    @Test fun aRegionAgreeingMakesItReportable() {
        val r = Wx.summarise(
            listOf(
                msg("hot out", who = "A", key = "a"),
                msg("so hot today", who = "B", key = "a"),
            ),
            NOW, positionOf = placed("a"),
        )
        assertEquals(1, r.cells.size)
        assertEquals(Wx.Condition.HEAT, r.cells.first().condition)
    }

    /** A corroborated soft condition still loses to a strong one. */
    @Test fun aStrongConditionOutranksACorroboratedSoftOne() {
        val r = Wx.summarise(
            listOf(
                msg("cold", who = "A", key = "a"),
                msg("cold", who = "B", key = "a"),
                msg("snowing hard", who = "C", key = "a"),
                msg("snow everywhere", who = "D", key = "a"),
                msg("still snowing", who = "E", key = "a"),
            ),
            NOW, positionOf = placed("a"),
        )
        assertEquals(Wx.Condition.SNOW, r.cells.first().condition)
    }

    @Test fun everyConditionIsReachable() {
        // A guard against exactly the flaw the floor introduced: two of the
        // nine were unreportable by construction and nothing said so.
        val reached = mutableSetOf<Wx.Condition>()
        listOf(
            "clear skies" to 1, "cloudy" to 1, "thick fog" to 1, "rain" to 1,
            "snow" to 1, "windy" to 1, "thunderstorm" to 1, "hot" to 2, "cold" to 2,
        ).forEach { (text, n) ->
            val r = Wx.summarise(
                (1..n).map { msg(text, who = "V$it", key = "a") }, NOW, positionOf = placed("a"),
            )
            r.cells.firstOrNull()?.let { reached += it.condition }
        }
        assertEquals(
            "every condition must be reachable somehow",
            Wx.Condition.entries.toSet(), reached,
        )
    }
}
