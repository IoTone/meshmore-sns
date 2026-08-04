// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.content.Context

/**
 * MESSAGES THAT SURVIVE THE APP CLOSING.
 *
 * Until this existed, every message the radio had ever handed us lived in one
 * in-memory list and died with the process. Close the app, take the glasses
 * off, get killed by the launcher in the background -- and the entire
 * conversation history was gone. Not aged out, not paged away: gone, with
 * nowhere to look and nothing to say it had happened.
 *
 * That is not a spatial-design decision and there is no argument for it in the
 * brief. It is simply what an app does when nobody has written the persistence
 * yet, and the companion app on the phone has always retained history, so the
 * XR client losing it is a straightforward regression from the user's point of
 * view rather than a different way of working.
 *
 * WHY SHAREDPREFERENCES AND NOT A DATABASE. The cap is a few hundred messages
 * of a couple of hundred bytes -- tens of kilobytes, read once at startup and
 * rewritten on arrival. A database earns its keep with queries, migrations and
 * partial reads, and this has none of those. Room here would be ceremony.
 *
 * THE ENCODING IS DELIBERATELY DULL. Unit-separated fields, record-separated
 * messages, and the text field escaped because it is the one an actual human
 * types and therefore the one that will eventually contain whatever character
 * seemed impossible. A malformed record is dropped rather than throwing:
 * losing one message from a previous version's format is a nuisance, and
 * failing to start because of it is a bug report.
 */
class MsgStore(private val store: Store, private val log: (String) -> Unit = {}) {

    /** The two operations this needs. Injected so the round trip is testable. */
    interface Store {
        fun getString(key: String): String?
        fun putString(key: String, value: String?)
    }

    constructor(context: Context, log: (String) -> Unit = {}) : this(PrefsStore(context), log)

    private class PrefsStore(context: Context) : Store {
        private val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        override fun getString(key: String) = p.getString(key, null)
        override fun putString(key: String, value: String?) {
            p.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
        }
    }

    /** Everything remembered, newest first. */
    fun load(): List<MeshLink.Msg> {
        val raw = store.getString(KEY) ?: return emptyList()
        val out = raw.split(RS).mapNotNull { decode(it) }
        log("[store] restored ${out.size} message(s)")
        return out
    }

    /** Replace the record. [msgs] is newest-first and already capped. */
    fun save(msgs: List<MeshLink.Msg>) {
        store.putString(KEY, msgs.joinToString(RS) { encode(it) })
    }

    fun clear() = store.putString(KEY, null)

    private fun encode(m: MeshLink.Msg): String = listOf(
        m.fromKey, m.fromName, esc(m.text), m.atEpochSec.toString(),
        if (m.direct) "1" else "0", m.channel.orEmpty(), m.channelName.orEmpty(),
    ).joinToString(US)

    private fun decode(s: String): MeshLink.Msg? {
        if (s.isEmpty()) return null
        val f = s.split(US)
        // Written by an older version with fewer fields, or truncated on the
        // way in. Either way it is one message, and one message is not worth
        // refusing to start over.
        if (f.size < 5) return null
        val at = f[3].toLongOrNull() ?: return null
        return MeshLink.Msg(
            fromKey = f[0],
            fromName = f[1],
            text = unesc(f[2]),
            atEpochSec = at,
            direct = f[4] == "1",
            channel = f.getOrNull(5)?.takeIf { it.isNotEmpty() },
            channelName = f.getOrNull(6)?.takeIf { it.isNotEmpty() },
        )
    }

    /**
     * The separators cannot appear in a field, and the escape cannot either.
     *
     * The backslash goes FIRST on the way out and LAST on the way back, which
     * is the whole correctness argument for this pair of functions: reverse
     * that and a message containing a literal backslash-u001f round-trips into
     * a field separator and silently eats the rest of the record.
     */
    private fun esc(s: String) = s
        .replace("\\", "\\\\").replace(US, "\\u").replace(RS, "\\r").replace("\n", "\\n")

    private fun unesc(s: String): String {
        val b = StringBuilder(s.length)
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c != '\\' || i == s.length - 1) { b.append(c); i++; continue }
            when (s[i + 1]) {
                '\\' -> b.append('\\')
                'u' -> b.append(US)
                'r' -> b.append(RS)
                'n' -> b.append('\n')
                else -> { b.append(c); b.append(s[i + 1]) }
            }
            i += 2
        }
        return b.toString()
    }

    private companion object {
        const val FILE = "meshmore-msgs"
        const val KEY = "log"
        /** ASCII's own separators, which is what they are for. */
        const val US = "\u001f"
        const val RS = "\u001e"
    }
}
