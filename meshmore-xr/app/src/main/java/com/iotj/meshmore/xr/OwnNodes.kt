// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.content.Context
import android.util.Log

/**
 * WHICH RADIOS ARE ACTUALLY THE OPERATOR'S, by whole public key.
 *
 * The authorisation this app transmits under is one sentence: the operator's
 * own nodes end in `ab60` and `d563`. That sentence is a NAME rule, and it is
 * the right rule — MeshCore's advert name is not derived from the key, and the
 * operator quotes their hardware by name.
 *
 * But four hex characters are not an identity. On a 350-node mesh a stranger's
 * public key ended in one of those suffixes, and the app treated that node as
 * the operator's own: protected from the contact sweep, and allowed as a
 * destination. Nothing was sent to it, and nothing should have been able to be.
 *
 * So the first time a node identifies itself by name, its whole 32-byte key is
 * written down here, and from then on that key IS that node. Pinning only ever
 * narrows the set — it cannot admit a radio the sentence did not already
 * cover — and it survives restarts because the identity of somebody's own
 * hardware is not a per-session fact.
 */
object OwnNodes {
    private const val FILE = "meshmore-own"

    private fun prefs(context: Context) =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /**
     * Remember [fullKey] as the node behind [suffix].
     *
     * FIRST NAME WINS, and a second claimant is reported rather than accepted.
     * Two contacts whose names both end in the same suffix is either a rename
     * or somebody else's node wearing a familiar-looking name, and neither is
     * a thing to resolve silently while deciding what may be transmitted to.
     */
    fun pin(context: Context, suffix: String, fullKey: String, name: String) {
        val k = fullKey.lowercase()
        if (k.length < 64) return
        val p = prefs(context)
        val existing = p.getString("key:$suffix", null)
        when {
            existing == null -> {
                p.edit().putString("key:$suffix", k).apply()
                Log.i(TAG, "[allow] pinned '$name' as the '$suffix' node (${k.take(12)}…)")
            }
            existing != k -> Log.w(
                TAG,
                "[allow] '$name' also claims '$suffix' but ${existing.take(12)}… was pinned first — " +
                    "the pinned key stays. If the hardware changed, clear it in SETUP.",
            )
        }
    }

    /** True when this exact key is one of the operator's radios. */
    fun isPinned(context: Context, fullKey: String): Boolean {
        val k = fullKey.lowercase()
        return prefs(context).all.any { (name, v) -> name.startsWith("key:") && v == k }
    }

    /** What is pinned, for the log and for a settings surface to show. */
    fun pinned(context: Context): Map<String, String> =
        prefs(context).all.entries
            .filter { it.key.startsWith("key:") }
            .associate { it.key.removePrefix("key:") to (it.value as? String).orEmpty() }

    /** Forget a pin, for when the hardware really did change. */
    fun clear(context: Context, suffix: String? = null) {
        val p = prefs(context)
        if (suffix == null) p.edit().clear().apply()
        else p.edit().remove("key:$suffix").apply()
    }

    private const val TAG = "MeshmoreXR"
}
