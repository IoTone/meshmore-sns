// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.Theme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ThemePrefsTest {

    private class Fake : ThemePrefs.Store {
        val map = HashMap<String, String>()
        override fun getString(key: String) = map[key]
        override fun putString(key: String, value: String?) {
            if (value == null) map.remove(key) else map[key] = value
        }
    }

    @Test fun opensIntoTheDefaultBeforeAnythingIsChosen() {
        val p = ThemePrefs(Fake())
        assertEquals(Theme.DEFAULT, p.current())
        assertFalse(p.chosen())
    }

    @Test fun aChoiceSurvivesARestart() {
        val store = Fake()
        ThemePrefs(store).set(Theme.BIOLUME)
        // A second instance is a fresh process as far as this class is concerned.
        val after = ThemePrefs(store)
        assertEquals(Theme.BIOLUME, after.current())
        assertTrue(after.chosen())
    }

    @Test fun everyThemeRoundTrips() {
        val store = Fake()
        Theme.ALL.forEach { s ->
            ThemePrefs(store).set(s)
            assertEquals(s, ThemePrefs(store).current())
        }
    }

    /**
     * A preference file written by a build that had a theme this build does not
     * must open into HALO rather than crash — and must still report that a
     * choice was made, so a first-run tutorial does not fire again.
     */
    @Test fun aKeyFromAnotherBuildDegradesToTheDefault() {
        val store = Fake()
        store.putString("skin", "holodeck")
        val p = ThemePrefs(store)
        assertEquals(Theme.DEFAULT, p.current())
        assertTrue(p.chosen())
    }
}
