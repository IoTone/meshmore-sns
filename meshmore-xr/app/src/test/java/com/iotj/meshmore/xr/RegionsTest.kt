// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.ROW_WIDEST
import com.iotj.meshmore.xr.spatial.regionRow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE PORT HAS TO STAY A PORT.
 *
 * These are values that decide what frequency a radio transmits on, copied from
 * another codebase in another language. The failure mode is not a crash — it is
 * a digit that drifts, and drift is exactly what happened to the four presets
 * this table replaced: XR's `ANZ915` had SF11 where the Dart says SF10, so two
 * apps from the same project could not have heard each other in Australia.
 *
 * So the tuples are asserted literally here, against the values in
 * `meshmore_sns_app/.../lib/meshcore/region_presets.dart`. A test that only
 * checked internal consistency would have passed on the drifted table.
 */
class RegionsTest {

    /**
     * Every tuple, spelled out. Deliberately verbose: this is the one place a
     * transcription error is catchable, and reading it against the Dart is a
     * thing a person can actually do.
     */
    @Test fun everyTupleMatchesTheSnsTable() {
        val want = mapOf(
            // id             freq      bw      sf  cr  tx
            "us_canada" to Q(910.525, 62.5, 7, 5, 22),
            "us_arizona" to Q(908.205, 62.5, 10, 5, 20),
            "jp_arib_t108" to Q(923.2, 125.0, 10, 5, 13),
            "jp_meshcore" to Q(920.8, 125.0, 12, 8, 13),
            "eu_uk_long" to Q(869.525, 250.0, 11, 5, 14),
            "eu_uk_medium" to Q(869.525, 250.0, 10, 5, 14),
            "eu_uk_narrow" to Q(869.618, 62.5, 8, 5, 14),
            "ch" to Q(869.618, 62.5, 8, 5, 14),
            "cz" to Q(869.432, 62.5, 7, 5, 14),
            "pt_869" to Q(869.618, 62.5, 7, 5, 14),
            "au_default" to Q(915.8, 250.0, 10, 5, 20),
            "au_narrow" to Q(916.575, 62.5, 7, 5, 20),
            "au_sa_wa_qld" to Q(923.125, 62.5, 8, 5, 20),
            "nz_default" to Q(917.375, 250.0, 11, 5, 20),
            "vn" to Q(920.250, 250.0, 11, 5, 20),
        )
        assertEquals("region count", want.size, Regions.ALL.size)
        Regions.ALL.forEach { r ->
            val w = want[r.id] ?: throw AssertionError("unknown region id ${r.id}")
            assertEquals("${r.id} freq", w.f, r.freqMhz, 1e-9)
            assertEquals("${r.id} bw", w.b, r.bandwidthKhz, 1e-9)
            assertEquals("${r.id} sf", w.sf, r.spreadingFactor)
            assertEquals("${r.id} cr", w.cr, r.codingRate)
            assertEquals("${r.id} tx", w.tx, r.txDbm)
        }
    }

    private data class Q(val f: Double, val b: Double, val sf: Int, val cr: Int, val tx: Int)

    /**
     * THE DEFECT THE OLD TABLE HAD, as a test.
     *
     * Australia is SF10. It was SF11 in XR for as long as the rack has existed.
     */
    @Test fun australiaIsSpreadingFactorTen() {
        assertEquals(10, Regions.byId("au_default")!!.spreadingFactor)
    }

    /**
     * THE OTHER DEFECT: a preset with no transmit power leaves the previous
     * region's power in place. Japan's ceiling is 13 dBm conducted and North
     * America's preset is 22 — so a traveller who picked JAPAN under the old
     * scheme would have kept transmitting at 22 on a 13 dBm band.
     */
    @Test fun everyRegionCarriesItsOwnTransmitPower() {
        Regions.ALL.forEach { assertTrue("${it.id} tx", it.txDbm in 1..30) }
        assertEquals(13, Regions.byId("jp_arib_t108")!!.txDbm)
        assertEquals(13, Regions.byId("jp_meshcore")!!.txDbm)
        // And it travels with the set, rather than beside it.
        assertEquals(13, Regions.byId("jp_arib_t108")!!.params().txDbm)
    }

    /** Ids are the interop contract with SNS. Renaming one silently unpairs the apps. */
    @Test fun idsAreStableAndUnique() {
        assertEquals(Regions.ALL.size, Regions.ALL.map { it.id }.toSet().size)
        Regions.ALL.forEach {
            assertTrue(it.id, it.id.matches(Regex("[a-z0-9_]+")))
        }
    }

    // --- what fits on glass ---------------------------------------------------

    @Test fun everyLabelFitsTheValueSlotBesideTheWordRegion() {
        Regions.ALL.forEach {
            assertTrue(
                "${it.label} is ${it.label.length}, slot is ${Regions.LABEL_MAX}",
                it.label.length <= Regions.LABEL_MAX,
            )
            assertEquals("${it.id} label must be uppercase", it.label.uppercase(), it.label)
        }
        assertTrue(Regions.CUSTOM.length <= Regions.LABEL_MAX)
    }

    /**
     * The region list's rows carry the frequency as well as the name, and the
     * builder drops the frequency rather than truncating a name it cannot fit.
     * No shipped region may be wide enough to trigger that.
     */
    @Test fun everyRegionRowKeepsBothItsNameAndItsFrequency() {
        Regions.ALL.forEach {
            val row = regionRow(it.label, it.freqMhz)
            assertTrue("$row is ${row.length}", row.length <= ROW_WIDEST.length)
            assertTrue(row, row.startsWith(it.label))
            assertTrue("$row lost its frequency", row.contains("%.3f".format(it.freqMhz)))
        }
    }

    /** Notes pass through Notice, which is 45 characters and clamps silently. */
    @Test fun everyNoteFitsTheNoticeLine() {
        Regions.ALL.mapNotNull { it.note }.forEach {
            assertTrue("$it is ${it.length}", it.length <= Regions.NOTE_MAX)
        }
    }

    /** The disclaimer is rendered as stack rows, so it wraps to the row width. */
    @Test fun theDisclaimerWrapsToTheRow() {
        assertTrue(Regions.DISCLAIMER.isNotEmpty())
        Regions.DISCLAIMER.forEach {
            assertTrue("$it is ${it.length}", it.length <= ROW_WIDEST.length)
        }
        // The Japanese hardware point is the part a wearer is least likely to
        // know and the part that is an offence to get wrong. It stays.
        assertTrue(Regions.DISCLAIMER.any { it.contains("GITEKI") })
        assertTrue(Regions.DISCLAIMER.any { it.contains("JAPAN") })
    }

    // --- matching -------------------------------------------------------------

    @Test fun aRadioOnAKnownSetMatchesItsRegion() {
        val p = RadioConfig.Params(910.525, 62.5, 7, 5, 22)
        assertEquals("us_canada", Regions.match(p)?.id)
        assertEquals("USA / CANADA", Regions.labelFor(p))
    }

    /**
     * Firmware clamps transmit power to what the hardware can actually do, so a
     * radio told 22 may report 20. That must not turn a correctly tuned radio
     * into CUSTOM — a word that appears when nothing is wrong is a word people
     * learn to ignore.
     */
    @Test fun powerIsNotPartOfTheMatch() {
        val clamped = RadioConfig.Params(910.525, 62.5, 7, 5, 17)
        assertEquals("us_canada", Regions.match(clamped)?.id)
    }

    /** The wire carries frequency as kHz in a uint32; the division rounds. */
    @Test fun matchingAbsorbsWireRounding() {
        assertEquals("us_canada", Regions.match(RadioConfig.Params(910.5251, 62.5, 7, 5, 22))?.id)
        assertNull(Regions.match(RadioConfig.Params(910.600, 62.5, 7, 5, 22)))
    }

    @Test fun anUnknownSetIsCustomAndSaysSo() {
        assertNull(Regions.match(RadioConfig.Params(902.0, 31.25, 9, 6, 20)))
        assertEquals(Regions.CUSTOM, Regions.labelFor(RadioConfig.Params(902.0, 31.25, 9, 6, 20)))
        assertEquals(Regions.CUSTOM, Regions.labelFor(null))
    }

    /**
     * Two regions share a tuple in the source table — Switzerland and the EU
     * narrow preset are the same four values — so match() returns the first,
     * and that is a documented consequence of a curated table rather than a
     * bug. This pins it so the ORDER of the list is understood to matter.
     */
    @Test fun anAmbiguousTupleResolvesToTheFirstEntry() {
        val p = RadioConfig.Params(869.618, 62.5, 8, 5, 14)
        assertEquals("eu_uk_narrow", Regions.match(p)?.id)
    }

    // --- geofence -------------------------------------------------------------

    @Test fun portlandSuggestsUsCanada() {
        // The radio's own reported position, from the boot log.
        assertEquals("us_canada", Regions.suggest(45.506881, -122.766028)?.id)
    }

    /** Order is the algorithm: the narrow Arizona box sits inside the US box. */
    @Test fun arizonaWinsOverTheBroaderUsBox() {
        assertEquals("us_arizona", Regions.suggest(33.45, -112.07)?.id)
        // Just outside it, the broad box takes over.
        assertEquals("us_canada", Regions.suggest(33.45, -105.0)?.id)
    }

    /** Same rule in Europe: Switzerland and Czechia precede the broad EU box. */
    @Test fun europeanOverridesPrecedeTheBroadBox() {
        assertEquals("ch", Regions.suggest(46.95, 7.45)?.id)
        assertEquals("cz", Regions.suggest(50.08, 14.44)?.id)
        assertEquals("pt_869", Regions.suggest(38.72, -9.14)?.id)
        assertEquals("eu_uk_long", Regions.suggest(51.51, -0.13)?.id)
    }

    @Test fun theAsiaPacificBoxesResolve() {
        assertEquals("jp_arib_t108", Regions.suggest(35.68, 139.69)?.id)
        assertEquals("vn", Regions.suggest(21.03, 105.85)?.id)
        assertEquals("au_default", Regions.suggest(-33.87, 151.21)?.id)
        assertEquals("nz_default", Regions.suggest(-36.85, 174.76)?.id)
    }

    /**
     * Mexico is inside the North American ISM box and correctly gets the same
     * preset — the overlap is intentional, not a leak.
     */
    @Test fun mexicoSharesTheNorthAmericanBand() {
        assertEquals("us_canada", Regions.suggest(19.43, -99.13)?.id)
    }

    /**
     * Outside every box there is NO suggestion. Guessing would be worse than
     * silence: the fallback is the full list, which is always correct.
     */
    @Test fun anUnmappedPositionSuggestsNothing() {
        assertNull(Regions.suggest(0.0, -30.0))      // mid-Atlantic
        assertNull(Regions.suggest(-89.0, 0.0))      // Antarctica
        assertNull(Regions.suggest(-25.0, 30.0))     // South Africa, no preset yet
        assertNull(Regions.suggest(null, null))
        assertNull(Regions.suggest(45.5, null))
    }

    /** Every box has to point at a region that exists, or it suggests nothing. */
    @Test fun everyBoxResolvesToAShippedRegion() {
        // Exercised through suggest() at each box's own centre, which is the
        // only way in without exposing the table.
        listOf(
            34.0 to -112.0, 40.0 to -100.0, 60.0 to -100.0, 35.0 to 135.0,
            16.0 to 106.0, -25.0 to 133.0, -41.0 to 172.0, 39.0 to -8.0,
            46.8 to 8.2, 49.8 to 15.4, 50.0 to 10.0,
        ).forEach { (lat, lon) ->
            assertNotNull("$lat,$lon", Regions.suggest(lat, lon))
        }
    }
}
