// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.content.Context
import android.util.Log
import org.json.JSONObject

/**
 * WHAT THE PROTOCOL WILL NEVER TELL US ABOUT THE RADIO IN YOUR POCKET.
 *
 * MeshCore's companion protocol reports a radio's SETTINGS in full and its
 * HARDWARE not at all. A board with no GNSS does not say so; it answers
 * 0.0/0.0 forever, which is a real place in the Gulf of Guinea and therefore
 * refused as a position — and everything downstream of that refusal is correct
 * behaviour that looks precisely like a broken application. An operator wore
 * this app for a day against such a board and got an empty ring, no bearings,
 * and 316 positioned peers that could not be drawn, with nothing anywhere
 * saying why.
 *
 * So the app carries its own catalogue ([assets/devices.json]) and its own
 * memory of what each radio has actually done ([RadioFacts]).
 *
 * OBSERVATION OUTRANKS THE CATALOGUE, always. What this radio does is a fact;
 * which board it is is a guess, and the guess is made from a name a human
 * typed. Where the two disagree, the radio in the room wins — see [gpsOf].
 */
object DeviceBook {

    /**
     * `null` means UNKNOWN, and unknown is not false.
     *
     * A modular board (RAK's WisBlock) genuinely may or may not carry GNSS
     * depending on what is plugged into it, and telling a wearer "your radio
     * has no GPS" when the truth is "we do not know" costs exactly the trust
     * this file exists to earn back.
     */
    data class Caps(
        val gps: Boolean? = null,
        val screen: Boolean? = null,
        val battery: Boolean? = null,
    )

    data class Profile(
        val id: String,
        val name: String,
        val match: List<String>,
        val caps: Caps,
        val confidence: String,
        val note: String = "",
    ) {
        /** True when we have had this board on the bench ourselves. */
        val tested: Boolean get() = confidence == "tested"
    }

    /**
     * Parse the catalogue. PURE — no android.util.Log anywhere below this
     * line, deliberately: the failure branch is the one worth testing, and a
     * stubbed Log throws on a desktop, so logging the failure would make the
     * failure untestable. [all] does the reporting, on a device, where a log
     * has somewhere to go.
     */
    fun parse(json: String): List<Profile> =
        runCatching { parseOrThrow(json) }.getOrDefault(emptyList())

    private fun parseOrThrow(json: String): List<Profile> {
        val out = mutableListOf<Profile>()
        val arr = JSONObject(json).optJSONArray("devices") ?: return out
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = o.optString("id").takeIf { it.isNotBlank() } ?: continue
            val caps = o.optJSONObject("caps")
            fun flag(name: String): Boolean? =
                if (caps == null || caps.isNull(name)) null else caps.optBoolean(name)
            val match = mutableListOf<String>()
            o.optJSONArray("match")?.let { m ->
                for (j in 0 until m.length()) m.optString(j).takeIf { it.isNotBlank() }
                    ?.let { match += it.lowercase() }
            }
            out += Profile(
                id = id,
                name = o.optString("name", id),
                match = match,
                caps = Caps(flag("gps"), flag("screen"), flag("battery")),
                confidence = o.optString("confidence", "reported"),
                note = o.optString("note", ""),
            )
        }
        return out
    }

    private var cache: List<Profile>? = null

    fun all(context: Context): List<Profile> = cache ?: runCatching {
        context.assets.open("devices.json").bufferedReader().use { it.readText() }
    }.mapCatching { parse(it) }
        .onFailure { Log.w(TAG, "[device] catalogue unreadable: $it") }
        .getOrDefault(emptyList())
        .also { cache = it }

    fun byId(context: Context, id: String?): Profile? =
        id?.let { want -> all(context).firstOrNull { it.id == want } }

    /**
     * Best guess at the board from whatever the radio calls itself.
     *
     * LONGEST TOKEN WINS, which is the whole of the disambiguation and is
     * enough: "T-DECK PLUS" must not resolve to the T-Deck entry just because
     * that entry was declared first, and the only thing separating them is
     * that one token is a prefix of the other.
     */
    fun match(context: Context, radioName: String?): Profile? =
        match(all(context), radioName)

    /** The pure half, so the matching rule itself is testable off-device. */
    fun match(profiles: List<Profile>, radioName: String?): Profile? {
        val hay = radioName?.lowercase()?.takeIf { it.isNotBlank() } ?: return null
        var best: Profile? = null
        var bestLen = 0
        profiles.forEach { p ->
            p.match.forEach { token ->
                if (token.length > bestLen && hay.contains(token)) {
                    best = p; bestLen = token.length
                }
            }
        }
        return best
    }

    /**
     * Does this radio have a position source? `null` when nobody knows yet.
     *
     * Precedence, and the order is the point:
     *  1. WE SAW ONE. A radio that has ever handed us a real fix has a fix.
     *  2. WE WATCHED AND NEVER SAW ONE. A whole session of 0/0 is evidence.
     *  3. The operator pinned the board.
     *  4. The catalogue matched the radio's name.
     * The two observations come first because they are about THIS radio, and
     * the catalogue is only ever about a radio like it.
     */
    fun gpsOf(context: Context, radioKey: String?, radioName: String?): Boolean? {
        RadioFacts.everPositioned(context, radioKey)?.let { return it }
        val pinned = byId(context, RadioFacts.pinnedBoard(context, radioKey))
        pinned?.caps?.gps?.let { return it }
        return match(context, radioName)?.caps?.gps
    }

    /** The board's display name, if we can name it at all. */
    fun nameOf(context: Context, radioKey: String?, radioName: String?): String? =
        byId(context, RadioFacts.pinnedBoard(context, radioKey))?.name
            ?: match(context, radioName)?.name

    /** One line for the log, so a session says what it thinks it is holding. */
    fun describe(context: Context, radioKey: String?, radioName: String?): String {
        val p = byId(context, RadioFacts.pinnedBoard(context, radioKey))
            ?: match(context, radioName)
        val gps = when (gpsOf(context, radioKey, radioName)) {
            true -> "position yes"; false -> "position no"; null -> "position unknown"
        }
        val seen = when (RadioFacts.everPositioned(context, radioKey)) {
            true -> "observed"; false -> "observed"; null -> "not yet observed"
        }
        return "${p?.name ?: "unrecognised board"} (${p?.confidence ?: "no match"}) — $gps, $seen"
    }

    private const val TAG = "MeshmoreXR"
}

/**
 * WHAT THIS PARTICULAR RADIO HAS ACTUALLY DONE, remembered across sessions.
 *
 * Keyed by public key, never by name: names are typed by people, duplicated,
 * and changed on a whim, and a fact filed under one would follow the wrong
 * radio the moment somebody renamed a node.
 *
 * The interesting entry is the negative one. "This radio has never given us a
 * position" is only knowable by watching, and it is exactly what lets the
 * SECOND connection to a GPS-less board explain itself immediately instead of
 * making the wearer sit through another empty ring to learn the same thing.
 */
object RadioFacts {
    private const val FILE = "meshmore-radios"

    private fun prefs(context: Context) =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /**
     * Record what the radio said about where it is.
     *
     * A YES IS PERMANENT AND A NO IS PROVISIONAL, which is not a symmetry
     * error: one real fix proves a position source exists forever, while a
     * session of silence only means it did not speak this time — a cold GNSS
     * indoors is silent for exactly the same reason as a missing one. So a
     * later fix overwrites the suspicion, and the suspicion never overwrites a
     * fix.
     */
    fun notePosition(context: Context, radioKey: String?, known: Boolean, ours: Boolean) {
        val k = radioKey?.takeIf { it.isNotBlank() } ?: return
        // WE CANNOT BE OUR OWN EVIDENCE.
        //
        // With SHARE MY LOCATION on, the app writes the HEADSET's position
        // into the radio's SelfInfo — and this function then read the same
        // field back and filed it as proof the board has GNSS. Circular, and
        // it went unnoticed because the answer it produced was cheerful: the
        // operator's M5 C6L, a board the catalogue records as having no GPS
        // ON THEIR OWN TESTIMONY, came up as "position yes, observed" on the
        // first run against real hardware. The hint that exists to explain an
        // empty ring could never have fired for the radio it was written for.
        //
        // A position we put there says nothing about the board, so nothing is
        // what gets recorded. Not "no" either: absence of evidence.
        if (ours) return
        val p = prefs(context)
        val cur = p.getString(POS + k, null)
        when {
            known && cur != "yes" -> p.edit().putString(POS + k, "yes").apply()
            !known && cur == null -> p.edit().putString(POS + k, "no").apply()
        }
    }

    /**
     * VERSIONED, so the poisoned facts go away.
     *
     * Everything filed under the old `pos:` key was written by a rule that
     * could not tell the radio's own fix from the position this app had just
     * published to it, so any "yes" under it may be an echo. They are not
     * migrated and not read — a wrong fact about hardware is worse than no
     * fact, and the right one is one session away from being observed again.
     */
    private const val POS = "pos2:"

    /** True: seen a fix. False: watched and never saw one. Null: no data. */
    fun everPositioned(context: Context, radioKey: String?): Boolean? {
        val k = radioKey?.takeIf { it.isNotBlank() } ?: return null
        return when (prefs(context).getString(POS + k, null)) {
            "yes" -> true
            "no" -> false
            else -> null
        }
    }

    /**
     * WHAT THIS APP LAST TOLD THE RADIO ITS POSITION WAS.
     *
     * Persisted, because the echo is invisible from inside one session: the
     * in-memory record of what we published dies with the process, and the
     * next launch reads the radio's SelfInfo as though a board with no GNSS
     * had sensed it. Kept as plain degrees and a wall-clock stamp — this is
     * evidence about provenance, not a fix to navigate by.
     */
    fun notePublished(context: Context, lat: Double, lon: Double, atMs: Long) {
        prefs(context).edit()
            .putString("pub", "%.6f,%.6f,%d".format(lat, lon, atMs))
            .apply()
    }

    /** Lat, lon and when — or null if this app has never shared a position. */
    fun lastPublished(context: Context): Triple<Double, Double, Long>? {
        val raw = prefs(context).getString("pub", null) ?: return null
        val p = raw.split(",")
        val la = p.getOrNull(0)?.toDoubleOrNull() ?: return null
        val lo = p.getOrNull(1)?.toDoubleOrNull() ?: return null
        val at = p.getOrNull(2)?.toLongOrNull() ?: return null
        return Triple(la, lo, at)
    }

    /** The operator naming their own hardware outranks any guess from a name. */
    fun pinBoard(context: Context, radioKey: String?, deviceId: String?) {
        val k = radioKey?.takeIf { it.isNotBlank() } ?: return
        prefs(context).edit().apply {
            if (deviceId == null) remove("board:$k") else putString("board:$k", deviceId)
        }.apply()
    }

    fun pinnedBoard(context: Context, radioKey: String?): String? {
        val k = radioKey?.takeIf { it.isNotBlank() } ?: return null
        return prefs(context).getString("board:$k", null)
    }

    fun forget(context: Context, radioKey: String?) {
        val k = radioKey?.takeIf { it.isNotBlank() } ?: return
        prefs(context).edit().remove("pos:$k").remove("board:$k").apply()
    }
}
