// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * WHICH CONVERSATIONS SPEAK, ACROSS A RESTART.
 *
 * The setting people will be angriest about getting wrong: audio that turns
 * itself back on is worse than audio that never worked, because it happens in
 * a room with other people in it.
 */
class VoicePrefsTest {

    private class Mem : VoicePrefs.Store {
        val m = HashMap<String, String?>()
        override fun getString(key: String) = m[key]
        override fun putString(key: String, value: String?) { m[key] = value }
    }

    @Test
    fun `everything is silent until asked`() {
        val v = VoicePrefs(Mem())
        assertFalse(v.isOn("#0"))
        assertFalse(v.isOn("ab60"))
    }

    @Test
    fun `a null thread is never on and never crashes`() {
        val v = VoicePrefs(Mem())
        assertFalse(v.isOn(null))
        assertFalse(v.toggle(null))
        v.set(null, true)
        assertEquals(emptySet<String>(), v.enabled())
    }

    @Test
    fun `it survives a restart`() {
        val mem = Mem()
        VoicePrefs(mem).set("ab60", true)
        assertTrue(VoicePrefs(mem).isOn("ab60"))
        assertFalse(VoicePrefs(mem).isOn("#0"))
    }

    @Test
    fun `turning one on does not turn the others on`() {
        val mem = Mem()
        val v = VoicePrefs(mem)
        v.set("#0", true)
        assertTrue(v.isOn("#0"))
        assertFalse(v.isOn("#1"))
        assertFalse(v.isOn("ab60"))
    }

    @Test
    fun `off stays off through a restart`() {
        val mem = Mem()
        VoicePrefs(mem).set("#0", true)
        VoicePrefs(mem).set("#0", false)
        assertFalse("audio that switches itself back on is the worst bug here",
            VoicePrefs(mem).isOn("#0"))
    }

    @Test
    fun `toggle reports the state it left behind`() {
        val v = VoicePrefs(Mem())
        assertTrue(v.toggle("#2"))
        assertTrue(v.isOn("#2"))
        assertFalse(v.toggle("#2"))
        assertFalse(v.isOn("#2"))
    }

    @Test
    fun `a thread id containing punctuation round-trips`() {
        // Thread ids are channel tags and key prefixes; nothing guarantees they
        // avoid whatever character the store happens to separate on.
        val mem = Mem()
        val odd = "weird,id with spaces|and#hash"
        VoicePrefs(mem).set(odd, true)
        val back = VoicePrefs(mem)
        assertTrue(back.isOn(odd))
        assertEquals(setOf(odd), back.enabled())
    }
}
