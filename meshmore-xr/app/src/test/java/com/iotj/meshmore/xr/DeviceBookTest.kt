// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The catalogue is data, and data that ships is code with the tests missing.
 *
 * These read the REAL asset rather than a fixture: a typo in devices.json is
 * exactly the failure this file exists to catch, and a fixture would prove
 * only that the parser parses.
 */
class DeviceBookTest {

    private val json: String by lazy {
        val f = File("src/main/assets/devices.json")
        assertTrue("devices.json missing at ${f.absolutePath}", f.exists())
        f.readText()
    }

    private val book: List<DeviceBook.Profile> by lazy { DeviceBook.parse(json) }

    @Test
    fun `catalogue parses and is not empty`() {
        assertTrue("no devices parsed", book.isNotEmpty())
    }

    /**
     * THE STRING THE OPERATOR'S RADIO ACTUALLY SENDS.
     *
     * `Unit C6L` is what DEVICE_QUERY returned from the bench radio on
     * 2026-08-18 — not a name anybody typed, the manufacturer field. It has to
     * land on the profile that records what that board cannot do, because the
     * catalogue is the fallback when there is no observation, and after the
     * self-evidence fix there will often be no observation.
     */
    @Test
    fun `the radios own manufacturer string names the board`() {
        val p = DeviceBook.match(book, "Unit C6L")
        assertEquals("m5-c6l", p?.id)
        assertEquals(false, p?.caps?.gps)
    }

    @Test
    fun `ids are unique`() {
        val ids = book.map { it.id }
        assertEquals("duplicate id in devices.json", ids.size, ids.toSet().size)
    }

    @Test
    fun `every entry declares a known confidence`() {
        book.forEach {
            assertTrue(
                "${it.id} has confidence '${it.confidence}'",
                it.confidence == "tested" || it.confidence == "reported",
            )
        }
    }

    /**
     * UNKNOWN MUST SURVIVE THE PARSER. A JSON null read back as `false` would
     * turn "we have never checked" into "this board does not have one", which
     * is the single way this catalogue can actively mislead a wearer.
     */
    @Test
    fun `null capability stays null`() {
        val rak = book.firstOrNull { it.id == "rak4631" }
        assertNotNull("modular board entry missing", rak)
        assertNull("a modular board's GNSS must stay unknown", rak!!.caps.gps)
    }

    @Test
    fun `the board we have actually tested is recorded as having no position source`() {
        val m5 = book.firstOrNull { it.id == "m5-c6l" }
        assertNotNull("the bench radio's board is missing", m5)
        assertEquals("tested", m5!!.confidence)
        assertEquals(false, m5.caps.gps)
    }

    /** Longest token wins, or a PLUS resolves to the board without the GNSS. */
    @Test
    fun `t-deck plus does not match plain t-deck`() {
        val plus = pick("Dave's T-Deck Plus")
        assertEquals("tdeck-plus", plus?.id)
        assertEquals(true, plus?.caps?.gps)
        assertEquals("tdeck", pick("t-deck by the door")?.id)
    }

    @Test
    fun `matching ignores case and surrounding words`() {
        assertEquals("m5-c6l", pick("SHED C6L NODE")?.id)
        assertEquals("m5-c6l", pick("m5c6l")?.id)
    }

    @Test
    fun `an unrecognised name matches nothing`() {
        assertNull(pick("Portland Metro Repeater 4"))
        assertNull(pick(""))
        assertNull(pick(null))
    }

    /**
     * No token may be so generic that an ordinary node name collides with it.
     * "v3" was in this catalogue for about an hour and would have claimed every
     * node anybody ever called "Base v3".
     */
    @Test
    fun `match tokens are specific enough to be evidence`() {
        book.forEach { p ->
            p.match.forEach { t ->
                assertTrue("token '$t' on ${p.id} is too short to identify a board", t.length >= 3)
                assertEquals("token '$t' on ${p.id} is not lowercase", t.lowercase(), t)
            }
        }
    }

    @Test
    fun `a tested entry carries the evidence that made it tested`() {
        book.filter { it.tested }.forEach {
            assertTrue("${it.id} is 'tested' with no note saying what we saw", it.note.length > 40)
        }
    }

    /**
     * A corrupt catalogue costs the HINTS, never the APP. This is an asset an
     * operator may hand-edit at 2am to add the board they just unboxed.
     */
    @Test
    fun `malformed json yields an empty catalogue rather than an exception`() {
        assertTrue(DeviceBook.parse("").isEmpty())
        assertTrue(DeviceBook.parse("{ devices: [ oh no").isEmpty())
        assertTrue(DeviceBook.parse("""{"schema":1}""").isEmpty())
        assertFalse(DeviceBook.parse(json).isEmpty())
    }

    private fun pick(name: String?): DeviceBook.Profile? = DeviceBook.match(book, name)
}
