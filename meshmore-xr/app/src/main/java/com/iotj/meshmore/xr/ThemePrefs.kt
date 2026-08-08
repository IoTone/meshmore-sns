// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.content.Context
import com.iotj.meshmore.xr.spatial.Theme

/**
 * WHICH OF THE NINE, ACROSS RESTARTS.
 *
 * Stores the KEY, not an index. An index is a promise that the order of
 * [Theme.ALL] never changes, and the order is a picker-layout decision that
 * will change — the day a theme is added or the recommendation moves, every
 * wearer silently gets a different theme than the one they chose, and nothing
 * in the app can tell that happened.
 *
 * An unknown key falls back to [Theme.DEFAULT] rather than failing. A build
 * that drops a theme, or a preference file from a newer build, must open into
 * HALO FIELD and not into a crash.
 */
class ThemePrefs(private val store: Store) {

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

    /** The chosen theme, or the default when nothing has been chosen. */
    fun current(): Theme.Skin = Theme.byKey(store.getString(KEY))

    fun set(skin: Theme.Skin) {
        store.putString(KEY, skin.key)
    }

    /** True when the wearer has actually picked, as opposed to never having looked. */
    fun chosen(): Boolean = store.getString(KEY) != null

    private companion object {
        const val FILE = "meshmore-theme"
        const val KEY = "skin"
    }
}
