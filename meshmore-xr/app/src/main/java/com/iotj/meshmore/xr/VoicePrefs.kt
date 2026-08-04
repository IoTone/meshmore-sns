// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.content.Context

/**
 * WHICH CONVERSATIONS READ THEMSELVES ALOUD.
 *
 * Per conversation, not one switch for the app, because the two kinds of
 * traffic on a mesh are not comparable. A busy public channel narrated into
 * your ear all afternoon is intolerable; a direct message from somebody you are
 * coordinating with is the entire reason to be wearing the thing. One global
 * toggle forces a choice between those and people resolve it by turning audio
 * off and never turning it back on.
 *
 * OFF BY DEFAULT, INCLUDING FOR DIRECT MESSAGES. A companion app that starts
 * talking unprompted is startling in a way a visual notification is not: you
 * can look away from a light, and you cannot un-hear a voice in a room with
 * other people in it. Speaking is opted into, once, per conversation.
 *
 * The key is the THREAD id -- a channel index or a sender's key -- which is the
 * same identity threads() groups by. Names are deliberately not used: a channel
 * can be renamed and a preference that follows the label rather than the thing
 * silently detaches from what it was set on.
 */
class VoicePrefs(private val store: Store) {

    interface Store {
        fun getString(key: String): String?
        fun putString(key: String, value: String?)
    }

    constructor(context: Context) : this(PrefsStore(context))

    private class PrefsStore(context: Context) : Store {
        private val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        override fun getString(key: String) = p.getString(key, null)
        override fun putString(key: String, value: String?) {
            p.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
        }
    }

    private val on: MutableSet<String> by lazy {
        (store.getString(KEY) ?: "").split(SEP).filter { it.isNotBlank() }.toMutableSet()
    }

    fun isOn(threadId: String?): Boolean = threadId != null && threadId in on

    fun set(threadId: String?, enabled: Boolean) {
        threadId ?: return
        if (enabled) on.add(threadId) else on.remove(threadId)
        store.putString(KEY, on.joinToString(SEP))
    }

    /** Returns the new state, so a toggle can report what it did. */
    fun toggle(threadId: String?): Boolean {
        threadId ?: return false
        val next = !isOn(threadId)
        set(threadId, next)
        return next
    }

    /** Everything currently speaking, for a settings surface to list. */
    fun enabled(): Set<String> = on.toSet()

    private companion object {
        const val FILE = "meshmore-voice"
        const val KEY = "spoken"
        const val SEP = ""
    }
}
