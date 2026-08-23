// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * WHAT A DICTATION WAS FOR, AND WHY IT MUST NOT BE A FLAG.
 *
 * Voice sending broke because the host kept a boolean meaning "the next result
 * is a channel tag". It was set when the tag row was pinched and cleared when
 * a result arrived — and a result does not always arrive. Cancelling produces
 * none. An error with nothing heard produces none. So opening the tag field
 * and saying nothing left the flag set, and every message dictated afterwards
 * was turned into a channel tag instead of being sent.
 *
 * The routing rule is restated here as a pure function, because Dictation
 * itself needs a SpeechRecognizer and cannot be built on a desktop JVM. What
 * matters is the property the flag lacked: EVERY way a session can end has to
 * leave the next one ordinary.
 */
class DictationPurposeTest {

    /** A tiny stand-in for the session's lifecycle. */
    private class Session {
        var purpose: String? = null
        fun start(why: String? = null) { purpose = why }
        /** The recogniser returned words. */
        fun results(): String? { val w = purpose; purpose = null; return w }
        /** The recogniser gave up. Reports nothing when nothing was heard. */
        fun error(heardSomething: Boolean): String? {
            val w = purpose
            purpose = null
            return if (heardSomething) w else null
        }
        fun cancel() { purpose = null }
    }

    @Test fun anOrdinaryDictationHasNoPurpose() {
        val s = Session()
        s.start()
        assertNull(s.results())
    }

    @Test fun aTagDictationReportsItsPurpose() {
        val s = Session()
        s.start("tag")
        assertEquals("tag", s.results())
    }

    /** THE BUG. Cancel produces no result, so nothing would clear a flag. */
    @Test fun aCancelledTagDoesNotCaptureTheNextMessage() {
        val s = Session()
        s.start("tag")
        s.cancel()
        s.start()
        assertNull("the next dictation is an ordinary message", s.results())
    }

    /** AND THE OTHER ESCAPE: an error with nothing heard reports nothing. */
    @Test fun aSilentTagAttemptDoesNotCaptureTheNextMessage() {
        val s = Session()
        s.start("tag")
        assertNull("nothing heard, so nothing reported", s.error(heardSomething = false))
        s.start()
        assertNull("the next dictation is an ordinary message", s.results())
    }

    /** An error that did hear something still knows what it was for. */
    @Test fun apartialTagStillReportsItsPurpose() {
        val s = Session()
        s.start("tag")
        assertEquals("tag", s.error(heardSomething = true))
    }

    /** Two tags in a row are both tags — the fix must not overcorrect. */
    @Test fun consecutiveTagsBothWork() {
        val s = Session()
        s.start("tag"); assertEquals("tag", s.results())
        s.start("tag"); assertEquals("tag", s.results())
    }
}
