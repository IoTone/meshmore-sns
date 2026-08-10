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

    private fun fits(s: String) = assertTrue(
        "'$s' is ${s.length} chars, template is ${ROW_WIDEST.length}",
        s.length <= ROW_WIDEST.length,
    )

    @Test fun theOrdinaryCaseReadsAsIntended() {
        assertEquals("PORTLAND METRO  42", channelLabel("Portland Metro", false, 42, false))
    }

    @Test fun publicComesFirstAndSpeaksLast() {
        assertEquals(
            "PUBLIC  MESH AMERICA  7  SPEAKS",
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
        assertTrue("the state must survive a huge count", s.endsWith("SPEAKS"))
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
        fits(ROW_HEAD_WIDEST)
        fits(ROW_NOTE_WIDEST)
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
            "WATCH THE REAL WORLD, NOT THIS",
            "MIC IS ON ONLY WHILE YOU SPEAK",
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
        ).forEach { assertTrue(it, it.length <= ROW_HEAD_WIDEST.length) }
        listOf(
            "CONNECT A RADIO TO SEE ITS SLOTS",
            "LIT = READS ALOUD    B TO CLOSE",
            "LIT = ON    B TO CLOSE",
            "PICK AGAIN TO ALLOW CHANNEL SEND",
        ).forEach { assertTrue(it, it.length <= ROW_NOTE_WIDEST.length) }
    }
}
