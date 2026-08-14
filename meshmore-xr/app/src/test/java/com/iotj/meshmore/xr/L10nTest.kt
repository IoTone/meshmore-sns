// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JAPANESE IS A LAUNCH LANGUAGE, and the two ways it silently breaks are both
 * pinned here: a key that exists in English and not in Japanese falls back to
 * English mid-sentence, and a format-arg mismatch crashes at the moment the
 * string is finally used — which for a notice is on somebody's face.
 */
class L10nTest {

    private fun res(name: String): Map<String, String> {
        // Gradle runs JVM tests from the module dir; walk up until the res
        // tree is found so this also works from the repo root.
        var d = File(System.getProperty("user.dir"))
        repeat(4) {
            val f = File(d, "src/main/res/$name/strings.xml")
                .takeIf { it.exists() } ?: File(d, "app/src/main/res/$name/strings.xml")
            if (f.exists()) {
                return Regex("<string name=\"([^\"]+)\">(.*?)</string>", RegexOption.DOT_MATCHES_ALL)
                    .findAll(f.readText())
                    .associate {
                        // Android strips a wrapping quote pair (it exists to
                        // protect significant whitespace); read it as AAPT does.
                        it.groupValues[1] to it.groupValues[2].removeSurrounding("\"")
                    }
            }
            d = d.parentFile ?: return@repeat
        }
        error("strings.xml for $name not found from ${System.getProperty("user.dir")}")
    }

    /**
     * EVERY KEY IN BOTH LANGUAGES. Android's fallback makes a missing JA key
     * render in English rather than fail, which is exactly why nobody notices
     * until a Japanese wearer does.
     */
    @Test fun everyEnglishKeyHasJapanese() {
        val en = res("values")
        val ja = res("values-ja")
        val missing = en.keys - ja.keys
        assertTrue("missing in ja: $missing", missing.isEmpty())
        val extra = ja.keys - en.keys
        assertTrue("ja keys with no en: $extra", extra.isEmpty())
    }

    /**
     * SAME FORMAT ARGS, both sides. `%1$s` present in EN and absent in JA does
     * not fail at build — it throws or garbles when getString runs with the
     * argument the code always passes.
     */
    @Test fun formatArgsAgreeAcrossLocales() {
        val en = res("values")
        val ja = res("values-ja")
        val spec = Regex("%[0-9]+\\$[sd]")
        en.forEach { (k, v) ->
            val a = spec.findAll(v).map { it.value }.toSortedSet()
            val b = spec.findAll(ja[k] ?: "").map { it.value }.toSortedSet()
            assertEquals("arg mismatch on '$k'", a, b)
        }
    }

    /** Promotion is a floor: it raises JA and never touches EN. */
    @Test fun theKanjiFloorPromotesAndNeverDemotes() {
        L10n.ja = false
        assertEquals(0.026f, L10n.cap(0.026f), 1e-6f)
        assertEquals(28, L10n.cells(28))
        L10n.ja = true
        assertEquals(0.039f, L10n.cap(0.026f), 1e-6f)
        assertEquals(18, L10n.cells(28))
        L10n.ja = false
    }

    /**
     * The promoted row still fits its plate. 13 kanji at the promoted cap must
     * stay inside the 0.46 m plate the Latin contract was written for — the
     * template changed, the furniture did not.
     */
    @Test fun aJapaneseRowFitsTheLatinPlate() {
        // CJK advance ≈ 1.0 em at cap height; the promoted cap is 1.5 × 0.0227.
        val cap = com.iotj.meshmore.xr.spatial.ROW_CAP_M * L10n.KANJI_PROMOTE
        val width = 13 * cap * 1.05f
        assertTrue("JA row is ${width}m against a 0.46m plate", width <= 0.47f)
        // ...and vertically inside the 0.062 m plate with room to breathe.
        assertTrue(cap < com.iotj.meshmore.xr.spatial.ROW_PLATE_H * 0.62f)
    }

    /**
     * Terseness is a CONTRACT for JA strings, not a taste: anything longer
     * than the JA row template gets clipped with an ellipsis by fit(), and a
     * clipped instruction is worse than a short one. The bay strings must fit
     * unclipped.
     */
    @Test fun theJapaneseBayStringsFitTheirTemplates() {
        val ja = res("values-ja")
        val rows = listOf(
            "r_location", "r_share", "r_diag", "r_autopen", "r_motion",
            "r_chansend", "r_telem", "c_new", "c_reroll", "c_join_public",
            "c_join_arm",
        )
        rows.forEach { k ->
            val v = ja[k]!!
            assertTrue(
                "'$k' = '$v' is ${v.length} chars against a 13-glyph JA row",
                v.length <= 13,
            )
        }
        val notes = listOf(
            "f_pending", "f_radio_idle", "f_app", "f_about", "f_chan",
            "f_chan_new", "f_chan_public", "f_telem", "f_chansend_arm",
            "f_erase_arm", "f_chan_no_radio",
        )
        notes.forEach { k ->
            val v = ja[k]!!
            assertTrue(
                "'$k' = '$v' is ${v.length} chars against a 15-glyph JA note",
                v.length <= 15,
            )
        }
    }
}
