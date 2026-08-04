// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * HISTORY ACROSS A PROCESS DEATH.
 *
 * The behaviour worth testing is exactly the one that spans a restart -- save,
 * die, load -- so the store takes its backing as an interface and this drives
 * it with a map. The same bargain RadioConfig already makes, for the same
 * reason: the durability rule is the feature, and it should not be the
 * untested part.
 *
 * The escaping gets the most attention here because it is the part that fails
 * SILENTLY. A broken separator does not throw; it swallows the rest of the
 * record, and the symptom is "some old messages are missing" reported weeks
 * later by somebody who cannot reproduce it.
 */
class MsgStoreTest {

    private class Mem : MsgStore.Store {
        val m = HashMap<String, String?>()
        override fun getString(key: String) = m[key]
        override fun putString(key: String, value: String?) { m[key] = value }
    }

    private fun msg(
        text: String,
        who: String = "chuck",
        direct: Boolean = false,
        ch: String? = "#0",
        name: String? = "PORTLAND",
    ) = MeshLink.Msg(
        fromKey = "ab60", fromName = who, text = text, atEpochSec = 1_700_000_000L,
        direct = direct, channel = ch, channelName = name,
    )

    private fun roundTrip(msgs: List<MeshLink.Msg>): List<MeshLink.Msg> {
        val mem = Mem()
        MsgStore(mem).save(msgs)
        // A NEW instance off the same bytes: the point is the restart.
        return MsgStore(mem).load()
    }

    @Test
    fun `nothing stored means no history, not a crash`() {
        assertEquals(emptyList<MeshLink.Msg>(), MsgStore(Mem()).load())
    }

    @Test
    fun `a message survives intact`() {
        val out = roundTrip(listOf(msg("the repeater is back up")))
        assertEquals(1, out.size)
        assertEquals("the repeater is back up", out[0].text)
        assertEquals("chuck", out[0].fromName)
        assertEquals("#0", out[0].channel)
        assertEquals("PORTLAND", out[0].channelName)
        assertEquals(false, out[0].direct)
    }

    @Test
    fun `a DM stays a DM`() {
        assertTrue(roundTrip(listOf(msg("just you", direct = true, ch = null)))[0].direct)
    }

    @Test
    fun `order is preserved, newest first`() {
        val out = roundTrip(listOf(msg("newest"), msg("middle"), msg("oldest")))
        assertEquals(listOf("newest", "middle", "oldest"), out.map { it.text })
    }

    @Test
    fun `the separators themselves survive being in a message`() {
        // Somebody pastes control characters, or a radio emits them. Without
        // escaping, the unit separator ends the field and the record separator
        // ends the message -- taking every older message with it.
        val nasty = "unit\u001fsep record\u001esep newline\nend"
        val out = roundTrip(listOf(msg(nasty), msg("older survives")))
        assertEquals(nasty, out[0].text)
        assertEquals(2, out.size)
        assertEquals("older survives", out[1].text)
    }

    @Test
    fun `a literal backslash does not corrupt the record`() {
        // The case that breaks if escape order is reversed: the text already
        // contains the escape sequence the encoder produces, so a naive
        // decoder turns it into a real separator.
        val trap = """C:\path\u and a real \u001f after"""
        val out = roundTrip(listOf(msg(trap), msg("still here")))
        assertEquals(trap, out[0].text)
        assertEquals(2, out.size)
    }

    @Test
    fun `an empty message body is not lost`() {
        val out = roundTrip(listOf(msg(""), msg("after")))
        assertEquals(2, out.size)
        assertEquals("", out[0].text)
    }

    @Test
    fun `a corrupt record is dropped, not fatal`() {
        val mem = Mem()
        MsgStore(mem).save(listOf(msg("good one")))
        mem.m["log"] = "garbage-with-no-fields\u001e" + mem.m["log"]
        val out = MsgStore(mem).load()
        assertEquals(listOf("good one"), out.map { it.text })
    }

    @Test
    fun `a record from an older shorter format is dropped rather than throwing`() {
        val mem = Mem()
        mem.m["log"] = "key\u001fname\u001ftext\u001f1700000000"   // no direct flag
        assertEquals(emptyList<MeshLink.Msg>(), MsgStore(mem).load())
    }

    @Test
    fun `clearing really clears`() {
        val mem = Mem()
        val s = MsgStore(mem)
        s.save(listOf(msg("gone soon")))
        s.clear()
        assertEquals(emptyList<MeshLink.Msg>(), MsgStore(mem).load())
    }
}
