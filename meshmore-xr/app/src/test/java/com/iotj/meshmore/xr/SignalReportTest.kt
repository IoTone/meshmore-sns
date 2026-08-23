// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE BOTS, AS SEEN ON THE OPERATOR'S OWN MESH.
 *
 * Every line below was captured on 2026-08-22 rather than invented, because
 * the whole risk in this file is guessing at somebody else's format. Two
 * different auto-responders and one hand-rolled report, all of which the app
 * was already receiving and discarding as ordinary text.
 */
class SignalReportTest {

    @Test fun theTwoBotsSeenOnThisMesh() {
        val a = SignalReport.parse(
            "@[BNHMobile], ack: SNR -3.5 dB, RSSI -116 dBm, 3 hops via 42, CA, 37",
        )!!
        assertEquals(-3.5, a.snrDb!!, 1e-9)
        assertEquals(-116, a.rssiDbm)
        assertEquals(3, a.hops)
        assertEquals(listOf("42", "CA", "37"), a.via)

        val b = SignalReport.parse(
            "@[TC T096 ZephCore], ack: SNR -1.2 dB, RSSI -109 dBm, " +
                "5 hops via 1A, 77, 79, 98, B9",
        )!!
        assertEquals(-109, b.rssiDbm)
        assertEquals(5, b.hops)
        assertEquals(5, b.via.size)
    }

    /** A different shape entirely, from somebody's own client. */
    @Test fun aHandRolledReportAlsoParses() {
        val r = SignalReport.parse("Path 10 hops SNR 0 dB RSSI -102 dBm")!!
        assertEquals(0.0, r.snrDb!!, 1e-9)
        assertEquals(-102, r.rssiDbm)
        assertEquals(10, r.hops)
        assertTrue(r.via.isEmpty())
    }

    /**
     * ORDINARY TRAFFIC MUST NOT PARSE. Every direct message goes through this,
     * and a false positive would record somebody's chat as a measurement of
     * this radio.
     */
    @Test fun realChatterIsNotAReport() {
        listOf(
            "Hello mesh",
            "Tacoma check in!! ",
            "@[Chuck@🏠] HI CHUCK!",
            "New antenna. Who dis? LOL 🤣",
            "1.17.1 might have made my repeater less annoying",
            "Ajinomoto dumplings",
            "",
        ).forEach { assertNull(it, SignalReport.parse(it)) }
    }

    /** "dB" alone is not a report; there has to be a number attached to it. */
    @Test fun theWordDecibelIsNotEnough() {
        assertNull(SignalReport.parse("my antenna has 6 dB gain apparently"))
        assertNull(SignalReport.parse("hops are fine today"))
    }

    /** dBm must not be read as dB — that would report RSSI as an SNR. */
    @Test fun rssiIsNotMistakenForSnr() {
        val r = SignalReport.parse("RSSI -116 dBm")!!
        assertEquals(-116, r.rssiDbm)
        assertNull("dBm is not an SNR", r.snrDb)
    }

    /** A partial report is still a measurement worth keeping. */
    @Test fun oneNumberIsEnough() {
        assertEquals(-99, SignalReport.parse("heard you at RSSI -99 dBm")!!.rssiDbm)
        assertEquals(2, SignalReport.parse("2 hops")!!.hops)
    }

    // --- whose radio is being measured ---------------------------------------

    /**
     * A BOT ON A CHANNEL ANSWERS EVERYBODY. Its reply about somebody else's
     * radio must never be recorded as a measurement of ours — that is worse
     * than recording nothing, because it looks like data.
     */
    @Test fun aReplyToSomebodyElseIsNotAboutUs() {
        val line = "@[BNHMobile], ack: SNR -3.5 dB, RSSI -116 dBm, 3 hops"
        assertFalse(SignalReport.addressesUs(line, "Unit C6L"))
        assertTrue(SignalReport.addressesUs(line, "BNHMobile"))
    }

    /** A line naming nobody is taken at face value — a DM already proved itself. */
    @Test fun anUnaddressedReportIsAccepted() {
        assertTrue(SignalReport.addressesUs("Path 10 hops SNR 0 dB", "Unit C6L"))
    }

    /** Names get decorated on this mesh; a contained match is still us. */
    @Test fun aDecoratedNameStillMatches() {
        assertTrue(
            SignalReport.addressesUs("@[PDX Unit C6L ☕] ack: 2 hops", "Unit C6L"),
        )
    }
}
