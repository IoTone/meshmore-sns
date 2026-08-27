// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import kotlin.math.abs

/**
 * THE WEATHER PEOPLE ALREADY TOLD YOU ABOUT.
 *
 * The measured half of WX — asking radios for their environment telemetry — is
 * built, correct, and returns nothing: 13 asked, 0 answered, because MeshCore
 * ships with every telemetry class set to DENY and almost nobody changes it.
 * That is not fixable from this app.
 *
 * This is the other half, and the operator's framing of it is the right one:
 * *"read off of the readings from the messages posted on public, in the case
 * that most nodes don't have telemetry available."* People say it is raining.
 * They say it constantly. That costs no airtime, needs no permission, works
 * with the radio off, and is the ONLY weather signal on a mesh where the
 * sensors are all switched off — which is every mesh.
 *
 * ## What is inherited from the phone, and what is not
 *
 * SNS settled the hard parts and they are kept, because they exist to stop
 * false positives rather than to find more hits:
 *
 *  - **Confidence is a MAX, never a sum.** Two weak hints do not make a strong
 *    one; they make one weak one, twice.
 *  - **Concrete nouns outrank qualitative ones.** "rain" and "snow" are things;
 *    "hot" and "cold" get said about coffee, arguments and people, so they
 *    score lowest.
 *  - **English matches on a word boundary** so "sun" does not fire on "Sunday".
 *    Japanese has no word boundaries and matches by substring.
 *  - **Negation kills the hit outright** rather than lowering it. "no rain
 *    today" is not weak evidence of rain.
 *  - **Emoji are the strongest signal of all.** On a mesh people type 🌧 far
 *    more often than they type a sentence about rain, and an emoji cannot be
 *    negated by accident or matched inside another word.
 *
 * Two things differ, and both are because a wrong answer costs more here:
 *
 *  - **The floor is higher.** SNS puts the threshold at 0.5 in its callers.
 *    A wrong chip in a phone list is a shrug; this app's destination for the
 *    same fact is a glyph hanging in the sky over a real direction, which is a
 *    much more assertive claim. [FLOOR] is 0.7.
 *  - **The window is hours, not a day.** The operator asked for a daily reset;
 *    this resets faster. Weather from twenty hours ago is not weather, and a
 *    surface that says CONDITIONS while showing yesterday evening is worse than
 *    one that says nothing. Every row carries how long ago it was said, so the
 *    wearer can judge it rather than trust it.
 *
 * ## Where the position comes from
 *
 * SNS resolves place names in the text against a bundled GeoNames gazetteer.
 * There is no gazetteer here and adding one is a real asset with real size, so
 * this uses the cheaper source SNS falls back to anyway: **the sender's own
 * node position**, which this app already has for hundreds of peers. Place
 * names in text are a separate, later, separable job.
 */
object Wx {

    /**
     * The nine conditions, each with the glyph a sky icon would use.
     *
     * Nine because that is what the phone's lexicon settled on and there is no
     * reason for the two apps to disagree about what weather is.
     */
    enum class Condition(val glyph: String) {
        CLEAR("☀"),
        CLOUDS("☁"),
        FOG("🌫"),
        RAIN("🌧"),
        SNOW("❄"),
        WIND("🌬"),
        STORM("⛈"),
        HEAT("🔥"),
        COLD("🧊"),
    }

    /** Below this, it is not said out loud. See the class note. */
    const val FLOOR = 0.70

    /**
     * How far back a mention still counts as weather.
     *
     * Six hours. Long enough that a mesh which only talks in the morning still
     * has something to say by afternoon, short enough that nothing here is ever
     * describing a different day.
     */
    const val WINDOW_S = 6 * 3600L

    /** Cell size for grouping, in degrees. About 5.5 km — the phone's figure. */
    const val CELL_DEG = 0.05

    /** How many regions a bay can show before it stops being a summary. */
    const val TOP_CELLS = 5

    /** Confidence by evidence, strongest first. A MAX is taken, never a sum. */
    private const val C_EMOJI = 0.90
    private const val C_STRONG = 0.80
    private const val C_PLAIN = 0.70
    private const val C_SOFT = 0.55

    data class Obs(
        /** Every condition the message hinted at, with the best evidence for each. */
        val scored: Map<Condition, Double>,
        val confidence: Double,
        val atEpochSec: Long,
        val fromKey: String,
        val fromName: String,
    ) {
        /** Good enough to report on the strength of this message alone. */
        val conditions: Set<Condition>
            get() = scored.filterValues { it >= FLOOR }.keys

        /**
         * Hinted at, but not on one person's word.
         *
         * HEAT and COLD live here permanently, and that is the point. Every
         * term for them is qualitative — "hot" and "cold" are said about
         * coffee, arguments and people — so each scores below [FLOOR] and none
         * of them can ever clear it alone. Raising their score to fix that
         * would buy two conditions at the price of trusting the least reliable
         * words in the lexicon; requiring corroboration keeps them reportable
         * without trusting any single message. See [SOFT_CORROBORATION].
         */
        val soft: Set<Condition>
            get() = scored.filterValues { it < FLOOR }.keys
    }

    /**
     * How many messages in a region must agree before a soft condition counts.
     *
     * One person saying "hot" is somebody's opinion about their kitchen. Three
     * radios in the same 5 km cell saying it is a heatwave.
     */
    const val SOFT_CORROBORATION = 2

    /**
     * One place, and what the weather is said to be there.
     *
     * [label] is a sender's name rather than a place name, and the distinction
     * is worth keeping in view: this says "the weather where this radio is",
     * not "the weather in this town". Without a gazetteer that is the honest
     * claim, and it is a hyperlocal one, which is what was wanted.
     */
    data class Cell(
        val label: String,
        val condition: Condition,
        /** How many messages mentioned it here. */
        val mentions: Int,
        /** The most recent, so a wearer can judge how stale it is. */
        val lastAtEpochSec: Long,
        val lat: Double,
        val lon: Double,
    ) {
        fun agoS(nowEpochSec: Long): Long = (nowEpochSec - lastAtEpochSec).coerceAtLeast(0)
    }

    // ---- the lexicon -------------------------------------------------------

    /**
     * Emoji carry no language and cannot be negated, so they are listed apart
     * and scored highest.
     */
    private val EMOJI: List<Pair<String, Condition>> = listOf(
        "☀" to Condition.CLEAR, "🌞" to Condition.CLEAR, "🌤" to Condition.CLEAR,
        "☁" to Condition.CLOUDS, "⛅" to Condition.CLOUDS, "🌥" to Condition.CLOUDS,
        "🌫" to Condition.FOG,
        "🌧" to Condition.RAIN, "🌦" to Condition.RAIN, "☔" to Condition.RAIN,
        "❄" to Condition.SNOW, "🌨" to Condition.SNOW, "☃" to Condition.SNOW,
        "💨" to Condition.WIND, "🌬" to Condition.WIND,
        "⛈" to Condition.STORM, "🌩" to Condition.STORM, "🌪" to Condition.STORM,
    )

    /** English terms. Matched on a word boundary so "sun" misses "Sunday". */
    private val EN: List<Triple<String, Condition, Double>> = listOf(
        t("sun", Condition.CLEAR), t("sunny", Condition.CLEAR),
        t("sunshine", Condition.CLEAR), t("clear", Condition.CLEAR),
        t("bluebird", Condition.CLEAR),
        t("cloud", Condition.CLOUDS), t("clouds", Condition.CLOUDS),
        t("cloudy", Condition.CLOUDS), t("overcast", Condition.CLOUDS),
        s("fog", Condition.FOG), s("foggy", Condition.FOG), s("mist", Condition.FOG),
        s("misty", Condition.FOG), s("haze", Condition.FOG), s("hazy", Condition.FOG),
        s("rain", Condition.RAIN), s("raining", Condition.RAIN),
        s("rainy", Condition.RAIN), s("drizzle", Condition.RAIN),
        s("downpour", Condition.RAIN), s("shower", Condition.RAIN),
        s("showers", Condition.RAIN), s("wet", Condition.RAIN),
        s("snow", Condition.SNOW), s("snowing", Condition.SNOW),
        s("snowy", Condition.SNOW), s("sleet", Condition.SNOW),
        s("hail", Condition.SNOW), s("flurries", Condition.SNOW),
        s("blizzard", Condition.SNOW),
        t("wind", Condition.WIND), t("windy", Condition.WIND),
        t("gusty", Condition.WIND), t("breezy", Condition.WIND),
        t("gale", Condition.WIND), t("blustery", Condition.WIND),
        s("storm", Condition.STORM), s("stormy", Condition.STORM),
        s("thunder", Condition.STORM), s("thunderstorm", Condition.STORM),
        s("lightning", Condition.STORM), s("typhoon", Condition.STORM),
        s("hurricane", Condition.STORM), s("cyclone", Condition.STORM),
        w("hot", Condition.HEAT), w("scorching", Condition.HEAT),
        w("sweltering", Condition.HEAT), w("muggy", Condition.HEAT),
        w("humid", Condition.HEAT), w("heatwave", Condition.HEAT),
        w("baking", Condition.HEAT),
        w("cold", Condition.COLD), w("freezing", Condition.COLD),
        w("frigid", Condition.COLD), w("chilly", Condition.COLD),
        w("frosty", Condition.COLD), w("frost", Condition.COLD),
        w("icy", Condition.COLD),
    )

    /**
     * Japanese terms — a PARALLEL LIST, not a translation of the English one.
     *
     * This app ships in Japanese, and an English-only miner is a surface that
     * goes quiet in a Japanese build. Matched by substring because Japanese has
     * no word boundaries to anchor to.
     */
    private val JA: List<Triple<String, Condition, Double>> = listOf(
        t("晴れ", Condition.CLEAR), t("快晴", Condition.CLEAR),
        t("日差し", Condition.CLEAR), t("青空", Condition.CLEAR),
        t("曇り", Condition.CLOUDS), t("くもり", Condition.CLOUDS), t("雲", Condition.CLOUDS),
        s("霧", Condition.FOG), s("もや", Condition.FOG), s("かすみ", Condition.FOG),
        s("雨", Condition.RAIN), s("小雨", Condition.RAIN), s("大雨", Condition.RAIN),
        s("にわか雨", Condition.RAIN), s("土砂降り", Condition.RAIN),
        s("雪", Condition.SNOW), s("大雪", Condition.SNOW), s("みぞれ", Condition.SNOW),
        s("ひょう", Condition.SNOW),
        t("風", Condition.WIND), t("強風", Condition.WIND), t("突風", Condition.WIND),
        s("嵐", Condition.STORM), s("雷", Condition.STORM), s("雷雨", Condition.STORM),
        s("台風", Condition.STORM),
        w("暑い", Condition.HEAT), w("蒸し暑い", Condition.HEAT), w("猛暑", Condition.HEAT),
        w("寒い", Condition.COLD), w("凍る", Condition.COLD), w("霜", Condition.COLD),
    )

    private fun s(term: String, c: Condition) = Triple(term, c, C_STRONG)
    private fun t(term: String, c: Condition) = Triple(term, c, C_PLAIN)
    private fun w(term: String, c: Condition) = Triple(term, c, C_SOFT)

    /** English negators, looked for in the characters BEFORE a hit. */
    private val EN_NOT = listOf("no", "not", "without", "n't", "never", "hardly")
    private const val EN_NOT_WINDOW = 16

    /** Japanese negates AFTER the term, so the window runs the other way. */
    private val JA_NOT = listOf("ない", "ません", "じゃない", "ではない", "なし")
    private const val JA_NOT_WINDOW = 8

    // ---- the scan ----------------------------------------------------------

    /**
     * Pull the weather out of one message, or null if it is just a message.
     *
     * NULL IS THE COMMON CASE and stays cheap: every public-channel message
     * passes through here and almost none of them are about the weather.
     */
    fun scan(text: String, atEpochSec: Long, fromKey: String, fromName: String): Obs? {
        if (text.isBlank()) return null
        val lower = text.lowercase()
        val hits = mutableMapOf<Condition, Double>()

        EMOJI.forEach { (glyph, c) ->
            if (text.contains(glyph)) best(hits, c, C_EMOJI)
        }
        EN.forEach { (term, c, conf) ->
            if (wordAt(lower, term) >= 0 && !negatedBefore(lower, term)) best(hits, c, conf)
        }
        JA.forEach { (term, c, conf) ->
            if (text.contains(term) && !negatedAfter(text, term)) best(hits, c, conf)
        }

        if (hits.isEmpty()) return null
        return Obs(
            scored = hits.toMap(),
            confidence = hits.values.max(),
            atEpochSec = atEpochSec,
            fromKey = fromKey,
            fromName = fromName,
        )
    }

    /** A MAX, never a sum. Two weak hints are still one weak hint. */
    private fun best(into: MutableMap<Condition, Double>, c: Condition, conf: Double) {
        val cur = into[c]
        if (cur == null || conf > cur) into[c] = conf
    }

    /** Index of [term] in [text] on a word boundary, or -1. */
    internal fun wordAt(text: String, term: String): Int {
        var from = 0
        while (true) {
            val i = text.indexOf(term, from)
            if (i < 0) return -1
            val before = if (i == 0) ' ' else text[i - 1]
            val afterAt = i + term.length
            val after = if (afterAt >= text.length) ' ' else text[afterAt]
            if (!before.isLetterOrDigit() && !after.isLetterOrDigit()) return i
            from = i + 1
        }
    }

    internal fun negatedBefore(text: String, term: String): Boolean {
        val i = wordAt(text, term)
        if (i < 0) return false
        val window = text.substring((i - EN_NOT_WINDOW).coerceAtLeast(0), i)
        return EN_NOT.any { wordAt(window, it) >= 0 || window.endsWith(it) }
    }

    internal fun negatedAfter(text: String, term: String): Boolean {
        val i = text.indexOf(term)
        if (i < 0) return false
        val start = i + term.length
        val window = text.substring(start, (start + JA_NOT_WINDOW).coerceAtMost(text.length))
        return JA_NOT.any { window.contains(it) }
    }

    // ---- the summary -------------------------------------------------------

    /**
     * EVERY OBSERVATION IN THE WINDOW, GROUPED BY WHERE IT WAS SAID.
     *
     * [positionOf] resolves a sender's key to their node's position, which is
     * the app's own contact store. A sender with no position still counts
     * toward [Report.heard] but gets no cell, because the phone app's rule is
     * the right one: **wrong placement is worse than no placement.**
     */
    fun summarise(
        msgs: List<MeshLink.Msg>,
        nowEpochSec: Long,
        /**
         * How far back to look. Defaults to [WINDOW_S]; the bay also asks for a
         * DAY, so that "nothing right now" can be told apart from "nothing at
         * all" — the same distinction the advert count draws for the radio, and
         * the one that stops a quiet hour reading as a broken feature.
         *
         * BEFORE [positionOf], so the common call can still pass the position
         * lookup as a trailing lambda.
         */
        windowS: Long = WINDOW_S,
        positionOf: (String) -> Pair<Double, Double>?,
    ): Report {
        val since = nowEpochSec - windowS
        val obs = msgs
            // PUBLIC TRAFFIC. A direct message about the weather is a private
            // remark to us, not a report about a region, and counting it would
            // let one chatty contact colour a whole map.
            .filter { !it.direct }
            .filter { it.atEpochSec in since..nowEpochSec }
            .filter { it.fromName != Meshbook.ME }
            .mapNotNull { scan(it.text, it.atEpochSec, it.fromKey, it.fromName) }

        val located = mutableListOf<Pair<Obs, Pair<Double, Double>>>()
        obs.forEach { o -> positionOf(o.fromKey)?.let { located += o to it } }

        val cells = located
            .groupBy { (_, p) -> cellOf(p.first) to cellOf(p.second) }
            .mapNotNull { (_, group) -> cell(group) }
            .sortedWith(
                compareByDescending<Cell> { it.mentions }.thenByDescending { it.lastAtEpochSec },
            )

        return Report(
            heard = obs.size,
            unplaced = obs.size - located.size,
            cells = cells.take(TOP_CELLS),
        )
    }

    data class Report(
        /** Weather mentions in the window, placed or not. */
        val heard: Int,
        /** Of those, the ones from a radio whose position we do not know. */
        val unplaced: Int,
        val cells: List<Cell>,
    ) {
        val empty: Boolean get() = heard == 0
    }

    private fun cellOf(deg: Double): Long = Math.floor(deg / CELL_DEG).toLong()

    private fun cell(group: List<Pair<Obs, Pair<Double, Double>>>): Cell? {
        // THE DOMINANT CONDITION, by how many messages carried it. A strictly
        // greater comparison, so a tie keeps the first rather than flapping
        // between two equally-mentioned conditions each time the bay opens.
        val strong = mutableMapOf<Condition, Int>()
        val soft = mutableMapOf<Condition, Int>()
        group.forEach { (o, _) ->
            o.conditions.forEach { c -> strong[c] = (strong[c] ?: 0) + 1 }
            o.soft.forEach { c -> soft[c] = (soft[c] ?: 0) + 1 }
        }
        // A SOFT CONDITION JOINS THE COUNT ONLY ONCE THE REGION AGREES. Below
        // that it is not evidence of weather, it is one person's adjective.
        soft.forEach { (c, n) ->
            if (n >= SOFT_CORROBORATION) strong[c] = (strong[c] ?: 0) + n
        }
        var top: Condition? = null
        var topN = 0
        Condition.entries.forEach { c ->
            val n = strong[c] ?: 0
            if (n > topN) { top = c; topN = n }
        }
        val condition = top ?: return null
        // THE CENTROID, not the first radio's position — a cell can hold
        // several and the group's middle is a fairer claim than any member's.
        val lat = group.map { it.second.first }.average()
        val lon = group.map { it.second.second }.average()
        // Named for whoever said the most here.
        val label = group
            .map { it.first.fromName }
            .filter { it.isNotBlank() }
            .groupingBy { it }.eachCount()
            .maxByOrNull { it.value }?.key
            ?: group.first().first.fromKey.takeLast(4)
        return Cell(
            label = label,
            condition = condition,
            mentions = group.size,
            lastAtEpochSec = group.maxOf { it.first.atEpochSec },
            lat = lat,
            lon = lon,
        )
    }

    /** `2H AGO`, `18M AGO`, `NOW`. Short enough for a row that already has a glyph. */
    fun ago(seconds: Long): String = when {
        seconds < 90 -> "NOW"
        seconds < 3600 -> "${seconds / 60}M"
        else -> "${seconds / 3600}H"
    }

    /** True when two positions land in the same cell. Used by the tests. */
    internal fun sameCell(aLat: Double, aLon: Double, bLat: Double, bLon: Double): Boolean =
        cellOf(aLat) == cellOf(bLat) && cellOf(aLon) == cellOf(bLon) &&
            abs(aLat - bLat) < 1.0
}
