// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The row template is a contract, and this is what enforces it.
 *
 * A reusable TextRun's panel is sized once for the longest string it will ever
 * hold. A longer string does not grow the panel — it is clipped inside it,
 * silently, wherever the pixel box ends. On a headset that presents as a
 * channel whose name trails off, or worse, a row whose SPEAKS state is missing
 * because a name ran long, and nothing anywhere says why.
 *
 * Names come off other people's radios, so the input is not under our control.
 */
class RowsTest {

    /**
     * THE INVARIANT THAT WAS MISSING, and the reason a row could ship hanging
     * off both ends of its own button.
     *
     * Every check in this file compared a label to the TEMPLATE, and the
     * template was never compared to the PLATE. At the old cap the template
     * rendered 63.6 cm of text onto a 40 cm plate — 23.6 cm of overflow,
     * photographed on the glasses before anything here failed.
     *
     * A row's width is exactly known: cells x em/cell x cap. So is the plate.
     * This is that division, and it is the only one that matters.
     */
    @Test fun theRowTemplateFitsInsideThePlate() {
        val textW = ROW_WIDEST.length * ROW_CELL_EM * ROW_CAP_M
        assertTrue(
            "template renders %.1f cm onto a %.1f cm plate".format(textW * 100, ROW_PLATE_W * 100),
            textW <= ROW_PLATE_W,
        )
        // ...and with a real margin, so the ends are not touching the edge.
        assertTrue(
            "only %.1f cm of margin".format((ROW_PLATE_W - textW) * 100),
            ROW_PLATE_W - textW >= 0.02f,
        )
    }

    /** And the cap stays at or above the house standard while doing it. */
    @Test fun theRowCapIsStillAtTheHouseStandard() {
        val deg = Math.toDegrees(2.0 * Math.atan(ROW_CAP_M / 2.0))
        assertTrue("row cap is %.2f deg".format(deg), deg >= 1.29)
    }

    private fun fits(s: String) = assertTrue(
        "'$s' is ${s.length} chars, template is ${ROW_WIDEST.length}",
        s.length <= ROW_WIDEST.length,
    )

    @Test fun theOrdinaryCaseReadsAsIntended() {
        assertEquals("PORTLAND METRO  42", channelLabel("Portland Metro", false, 42, false))
    }

    /**
     * PUBLIC still leads. SPEAKS is gone — the lit plate says it, and the row
     * needed the eight characters more than it needed the confirmation.
     */
    @Test fun publicComesFirstAndSpeakingIsLeftToThePlate() {
        assertEquals("PUBLIC  MESH AMERICA  7", channelLabel("Mesh America", true, 7, true))
        assertEquals(
            "the speaking state must not change the row's width",
            channelLabel("Mesh America", true, 7, false),
            channelLabel("Mesh America", true, 7, true),
        )
    }

    @Test fun everyRowFitsTheTemplateEvenAtTheWorstCase() {
        fits(channelLabel("A Ridiculously Long Channel Name", true, 99999, true))
        fits(ROW_WIDEST)
    }

    @Test fun aLongNameIsEllipsisedNotCut() {
        val s = channelLabel("Cascadia Regional Emergency Net", false, 3, false)
        assertTrue(s, s.contains("…"))
        fits(s)
    }

    @Test fun aNameExactlyAtTheLimitIsNotTouched() {
        val exact = "A".repeat(CHAN_NAME_MAX)
        assertTrue(channelLabel(exact, false, 0, false).startsWith(exact))
    }

    /**
     * A busy public band really does carry four figures in an evening, so a
     * saturated count must read as saturated. Rendering 1234 as "999" is not a
     * truncation, it is a wrong number — and wrong on exactly the channel
     * anybody would check.
     */
    @Test fun countsSaturateAndSaySo() {
        val s = channelLabel("Public Chat", true, 12345, true)
        assertTrue(s, s.contains("999+"))
        assertTrue("a saturated count must still end the row cleanly", s.endsWith("999+"))
        fits(s)
    }

    @Test fun aCountJustUnderTheCapIsExact() {
        assertTrue(channelLabel("Quiet", false, 999, false).endsWith("999"))
        assertTrue(channelLabel("Quiet", false, 1000, false).endsWith("999+"))
    }

    /**
     * A blank name is a real case: MeshCore reports empty slots, and a row that
     * is just a number reads as a rendering fault rather than as an unnamed
     * channel.
     */
    @Test fun ablankNameSaysSoRatherThanRenderingEmpty() {
        assertTrue(channelLabel("   ", false, 0, false).startsWith("UNNAMED"))
        assertTrue(channelLabel("", true, 0, false).contains("UNNAMED"))
    }

    @Test fun namesAreUppercasedToMatchEverySurfaceAroundThem() {
        assertTrue(channelLabel("quiet net", false, 1, false).startsWith("QUIET NET"))
    }

    /**
     * The real case off a real radio: MeshCore's stock slot 0 is named "Public"
     * AND carries the public PSK, so the marker and the name are the same word.
     * "PUBLIC  PUBLIC  1234" reads as a fault and teaches the eye to skim the
     * marker on every other row, where it is the only warning there is.
     */
    @Test fun theMarkerIsNotRepeatedWhenTheNameAlreadySaysIt() {
        assertEquals("PUBLIC  999+", channelLabel("Public", true, 1234, false))
        assertEquals("PUBLIC  12", channelLabel("Public", true, 12, false))
        assertEquals("PUBLIC CHAT  8", channelLabel("Public Chat", true, 8, false))
        // and it is still there when the name does not say it
        assertTrue(channelLabel("Mesh America", true, 8, false).startsWith("PUBLIC  "))
    }

    /** A zero count is shown, not hidden: "0" is information, absence is ambiguous. */
    @Test fun zeroIsShown() {
        assertEquals("QUIET  0", channelLabel("Quiet", false, 0, false))
    }

    // --- settings rows -------------------------------------------------------

    /**
     * The state word is there on and off alike. The plate's light already says
     * which — but a row reading just "SHARE LOCATION" gives a reader no way to
     * tell an unlit plate from a plate that failed to light, and "off" versus
     * "broken" is the whole question somebody has when they come looking.
     */
    @Test fun aSettingAlwaysSaysItsState() {
        assertEquals("SHARE MY LOCATION  ON", settingLabel("Share my location", true))
        assertEquals("SHARE MY LOCATION  OFF", settingLabel("Share my location", false))
    }

    @Test fun aGuardedRowAsksRatherThanReportingAState() {
        val s = settingLabel("Send on channels", on = false, armed = true)
        assertTrue(s, s.endsWith("CONFIRM?"))
        // and the armed question replaces the state entirely — a half-pressed
        // switch is not a state the setting is in.
        assertTrue(s, !s.contains("OFF"))
        assertTrue(settingLabel("Send on channels", on = true, armed = true).let {
            !it.contains("ON  ") && it.endsWith("CONFIRM?")
        })
    }

    @Test fun aSettingCanNameItsOwnStateWords() {
        assertEquals(
            "SEND ON CHANNELS  ALLOWED",
            settingLabel("Send on channels", true, onWord = "ALLOWED", offWord = "OFF"),
        )
    }

    @Test fun everySettingRowFitsTheSharedTemplate() {
        fits(settingLabel("A Very Long Setting Name That Somebody Added Later", true))
        fits(settingLabel("Send on channels", false, armed = true, onWord = "ALLOWED"))
        fits(settingLabel("Erase 99999 messages", false, offWord = "").trimEnd())
    }

    /**
     * The title and footer are NOT plate-bounded — they have no plate under
     * them — so they are measured against the FIELD instead. Holding them to
     * the row template was the previous version of this test doing the right
     * arithmetic against the wrong object.
     */
    @Test fun theHeaderAndFooterFitTheFieldEvenThoughTheyAreLongerThanARow() {
        listOf(ROW_HEAD_WIDEST, ROW_NOTE_WIDEST).forEach { t ->
            val w = t.length * ROW_CELL_EM * ROW_CAP_M
            val deg = Math.toDegrees(2.0 * Math.atan(w / 2.0))
            assertTrue("'%s' is %.1f deg wide".format(t, deg), deg <= 30.0)
        }
    }

    /**
     * S12's safety lines share the Stack's row template with everything else. A
     * safety line clipped in half is worse than one that is absent, because it
     * still looks like a complete sentence — "DO NOT USE WHILE DRIV" reads as a
     * rendering fault, but "WATCH THE REAL WORLD" reads as advice.
     */
    @Test fun everyAboutLineFitsTheSharedTemplate() {
        listOf(
            "MESHMORE XR  0.1.0",
            "RADIO  MESHCORE-B727FE05",
            "MESHCORE  v1.7.1-companion",
            "DO NOT USE WHILE DRIVING",
            "WATCH THE ROOM, NOT THIS",
            "MIC ON ONLY WHEN YOU SPEAK",
            "ABOUT MESHMORE XR",
            "READ ONLY — B TO CLOSE",
        ).forEach { fits(it) }
    }

    @Test fun aBlankSettingNameStillRenders() {
        assertTrue(settingLabel("  ", false).startsWith("SETTING"))
    }

    /**
     * Both bays share one panel size, so the widest thing either can say has to
     * be inside the one template. A per-bay template would mean a per-bay
     * panel, and the stack would stop being a shared primitive.
     */
    @Test fun theHeaderAndFooterTemplatesCoverWhatTheBaysActuallySay() {
        listOf(
            "CHANNELS — PICK TO SPEAK",
            "APP — CONNECTION: DISCONNECTED",
            "ABOUT MESHMORE XR",
        ).forEach { assertTrue(it, it.length <= ROW_HEAD_WIDEST.length) }
        listOf(
            "CONNECT A RADIO TO SEE ITS SLOTS",
            "LIT = READS ALOUD    B TO CLOSE",
            "LIT = ON    B TO CLOSE",
            "PICK AGAIN TO ALLOW CHANNEL SEND",
        ).forEach { assertTrue(it, it.length <= ROW_NOTE_WIDEST.length) }
    }
}
