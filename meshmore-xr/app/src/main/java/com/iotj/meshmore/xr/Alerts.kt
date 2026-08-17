// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * THINGS THE APP WANTS TO SAY THAT ARE NOT WORTH THE ROOM.
 *
 * There are exactly two conditions that earn a card standing in the world: no
 * radio, and no position. Both stop the app doing the thing it exists for, and
 * both were asked for in as many words after a day of the app showing nothing
 * instead.
 *
 * Everything else is an ALERT — true, worth recording, and not worth a surface
 * in front of somebody's face. A full contact store is the type case: it
 * explains why a node never appeared, it wants acting on eventually, and it is
 * not a reason to interrupt a wearer who is doing something else. Shown that
 * way it read as an alarm; the operator's instruction was to put it where the
 * radio log lives and leave it off by default.
 *
 * So: a ring buffer, a panel that is off unless asked for, and nothing in the
 * world. The same shape as the debug log, for the same reason — a scrolling
 * list is the right form for a history, and making it spatial would make it
 * worse.
 */
object Alerts {

    enum class Level { INFO, WARN }

    data class Entry(
        val atMs: Long,
        val level: Level,
        /** Short, stable, and the thing a wearer would search for. */
        val tag: String,
        val text: String,
        /** How many times running this same line has been raised. */
        val count: Int = 1,
    )

    /** Deep enough for a session, short enough to never be a memory question. */
    const val MAX = 120

    private val _log = MutableStateFlow<List<Entry>>(emptyList())
    val log: StateFlow<List<Entry>> = _log.asStateFlow()

    /**
     * Record one.
     *
     * DEDUPED ON THE TAG AND THE TEXT TOGETHER, because the conditions that
     * raise alerts are mostly STANDING conditions — a store stays full, a
     * region stays wrong — and a per-second tick would otherwise fill the
     * buffer with one fact. The count is kept instead, which is more useful
     * anyway: "×47" is how long it has been true.
     */
    fun say(level: Level, tag: String, text: String, nowMs: Long = System.currentTimeMillis()) {
        val cur = _log.value
        val last = cur.lastOrNull()
        if (last != null && last.tag == tag && last.text == text) {
            _log.value = cur.dropLast(1) + last.copy(atMs = nowMs, count = last.count + 1)
            return
        }
        Log.i(TAG, "[alert] $tag — $text")
        _log.value = (cur + Entry(nowMs, level, tag, text)).takeLast(MAX)
    }

    fun info(tag: String, text: String) = say(Level.INFO, tag, text)
    fun warn(tag: String, text: String) = say(Level.WARN, tag, text)

    fun clear() { _log.value = emptyList() }

    /** How many WARN entries are outstanding, for a one-glyph indicator. */
    val warnings: Int get() = log.value.count { it.level == Level.WARN }

    private const val TAG = "MeshmoreXR"
}
