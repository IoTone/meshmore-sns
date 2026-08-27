// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

/**
 * THE LAST DAY ON THIS MESH, AS A SHAPE.
 *
 * Not a log — the inbox is the log, and reading it tells you what was said
 * without ever telling you what KIND of day it was. Meshbook answers the
 * questions a log cannot: was it busy, who carried it, did anyone answer YOU,
 * and when is this band actually awake.
 *
 * ## It costs nothing, and that is the point
 *
 * Every figure comes from messages already on this device. No query, no
 * airtime, no permission, no protocol work — and it is the one surface in the
 * app that is fully useful with the radio switched off. On the operator's own
 * glasses the store was carrying 67 KB of history while nothing in the app
 * could say a single thing about it.
 *
 * ## What is taken from SNS and what is not
 *
 * The phone app settled the shape and its decisions are kept: a ROLLING
 * twenty-four hours rather than a calendar day (collection does not run in the
 * background, so a midnight reset would erase the evening), and a
 * twenty-four-bucket histogram by local hour.
 *
 * Two things differ, and both are because this app knows more:
 *
 *  - **Replies.** SNS counts a message as a reply when its text begins with
 *    `>`, which is a typing convention and only works where people follow it.
 *    Here a reply is a message that ARRIVED after one of ours in the same
 *    thread, which is a fact rather than a habit. And the delivery ledger adds
 *    the figure SNS cannot compute at all: how many of ours were delivered.
 *  - **Scope.** SNS reads channel traffic only, where senders are anonymous
 *    and identity is a self-declared `name:` prefix. This includes direct
 *    messages, where the sender is a KEY, so "top voices" means something.
 */
object Meshbook {

    /** The window. Rolling, not a calendar day — see the class note. */
    const val WINDOW_S = 24 * 3600L

    /** How many voices a bay can usefully show before it becomes a list. */
    const val TOP_VOICES = 5

    data class Voice(val name: String, val said: Int, val lastAtEpochSec: Long)

    /** A word the day kept coming back to, and how many messages carried it. */
    data class Topic(val term: String, val said: Int)

    data class Book(
        /** Messages in the window, ours and theirs. */
        val total: Int,
        /** Of those, the ones we sent. */
        val mine: Int,
        /**
         * Ours that COULD be acknowledged — direct messages with a delivery
         * state. Channel sends are not in it: MeshCore group traffic carries
         * no ack, so counting them in the denominator reported the operator's
         * own mesh at 4% delivered when the direct soaks had measured 90%.
         */
        val trackable: Int,
        /** Ours that the far end acknowledged. */
        val delivered: Int,
        /** Ours the app gave up on. */
        val lost: Int,
        /** Ours that somebody answered in the same thread. */
        val answered: Int,
        /** Counts by local hour, index 0..23. */
        val hourly: List<Int>,
        val voices: List<Voice>,
        /** Distinct senders heard, ourselves excluded. */
        val speakers: Int,
        /** What the day was ABOUT, strongest first. May be empty; usually is on a quiet day. */
        val topics: List<Topic>,
    ) {
        val theirs: Int get() = total - mine

        /** Of the messages we sent, the share that was acknowledged. */
        val deliveryPct: Int?
            get() = if (trackable == 0) null else (delivered * 100.0 / trackable).toInt()

        /** And the share somebody replied to, which is a different question. */
        val replyPct: Int?
            get() = if (mine == 0) null else (answered * 100.0 / mine).toInt()

        val busiestHour: Int? get() = hourly.withIndex().maxByOrNull { it.value }
            ?.takeIf { it.value > 0 }?.index

        val peak: Int get() = hourly.maxOrNull() ?: 0
    }

    /**
     * THE ONE PLACE ALL OF THIS IS COMPUTED.
     *
     * [nowEpochSec] is passed rather than read so the whole thing is a pure
     * function of its inputs — which is what lets a day's traffic be built in
     * a test and the answers asserted, rather than waiting for a real day.
     *
     * [hourOf] converts an epoch second to a local hour, injected for the same
     * reason: a histogram bucketed by the machine's timezone cannot be checked
     * anywhere except in that timezone.
     */
    fun of(
        msgs: List<MeshLink.Msg>,
        nowEpochSec: Long,
        hourOf: (Long) -> Int,
    ): Book {
        val since = nowEpochSec - WINDOW_S
        // AT OR AFTER, and not in the future. A peer's clock can be days out —
        // 71 contacts on this mesh reported timestamps ahead of now — and a
        // message stamped tomorrow would sit in the window forever and land in
        // whatever bucket its wrong hour points at.
        val win = msgs.filter { it.atEpochSec in since..nowEpochSec }

        val hourly = MutableList(24) { 0 }
        win.forEach { hourly[hourOf(it.atEpochSec).coerceIn(0, 23)] += 1 }

        val mineList = win.filter { it.fromName == ME }
        val theirsList = win.filter { it.fromName != ME }

        // A NAME, A KEY, OR NOTHING AT ALL. Channel traffic carries no sender
        // key and its name is whatever the text was prefixed with, so a
        // message with neither produced a voice called "" — which drew as a
        // blank row with a count beside it, top of the list, on the operator's
        // own mesh. Those are grouped as one anonymous voice instead.
        val voices = theirsList
            .groupBy {
                it.fromName.ifBlank { it.fromKey.takeLast(4).ifBlank { ANON } }
            }
            .map { (name, m) -> Voice(name, m.size, m.maxOf { it.atEpochSec }) }
            .sortedWith(compareByDescending<Voice> { it.said }.thenBy { it.name })

        return Book(
            total = win.size,
            mine = mineList.size,
            trackable = mineList.count { it.delivery != null },
            delivered = mineList.count { it.delivery == MeshLink.Delivered.DELIVERED },
            lost = mineList.count { it.delivery == MeshLink.Delivered.LOST },
            answered = answered(win),
            hourly = hourly,
            voices = voices.take(TOP_VOICES),
            speakers = voices.size,
            // EVERY message in the window, ours included. A day where the only
            // person talking about the ferry was you is still a day about the
            // ferry, and excluding our own words would make the book quieter
            // the more we said.
            topics = topics(win, voices.map { it.name }),
        )
    }

    /**
     * HOW MANY OF OUR MESSAGES SOMEBODY ANSWERED.
     *
     * A reply is somebody else's message arriving AFTER one of ours in the
     * same thread, and before we speak there again. That is a fact about the
     * conversation; SNS's rule — the text begins with `>` — is a fact about
     * how somebody types, and it undercounts every reply from a person who
     * does not use the convention, which on this mesh is nearly everybody.
     *
     * Counted once per message of ours, so a thread where four people answer
     * at once is one answered message rather than four.
     */
    private fun answered(win: List<MeshLink.Msg>): Int {
        var n = 0
        win.groupBy { it.channel ?: it.fromKey }.forEach { (_, thread) ->
            val ordered = thread.sortedBy { it.atEpochSec }
            ordered.forEachIndexed { i, m ->
                if (m.fromName != ME) return@forEachIndexed
                val replied = ordered.drop(i + 1)
                    .takeWhile { it.fromName != ME }
                    .any { it.fromName != ME }
                if (replied) n++
            }
        }
        return n
    }

    /**
     * WHAT THE DAY WAS ABOUT.
     *
     * SNS settled the shape and its two good decisions are kept. A term counts
     * ONCE PER MESSAGE, so "topics" measures how many messages mentioned a
     * thing rather than how emphatically one person repeated it — otherwise a
     * single excited sender owns the whole list. And a term must appear in at
     * least [TOPIC_MIN] messages, because one mention is a remark, not a topic.
     *
     * PEOPLE ARE NOT TOPICS. The day's own voice handles are struck out, or a
     * channel where everybody prefixes their name turns "topics" into a second,
     * worse copy of the voices list — which is the row directly above it.
     *
     * ## Where this departs from the phone
     *
     * SNS tokenises on a character-class split that treats every CJK range as
     * word characters. Japanese does not put spaces between words, so a
     * sentence of kana and kanji survives that split as ONE token — an entire
     * clause, offered to the wearer as a topic. It passes every test written
     * in English and produces nonsense in Japanese, in an app that ships in
     * Japanese.
     *
     * So a CJK run is kept only when it is short enough to plausibly BE a word
     * — [CJK_MIN] to [CJK_MAX] characters, which covers ordinary compound
     * nouns — and a longer run is dropped rather than shown. Dropping is the
     * honest failure here: a missing topic reads as a quiet day, an invented
     * one reads as a lie about what people said. Proper segmentation needs a
     * dictionary this app has no room for.
     */
    private fun topics(win: List<MeshLink.Msg>, voiceNames: List<String>): List<Topic> {
        val banned = voiceNames.flatMap { tokens(it) }.toSet()
        val counts = mutableMapOf<String, Int>()
        win.forEach { m ->
            // ONCE PER MESSAGE — a set, not a list.
            termsOf(m.text).forEach { t ->
                if (t !in banned) counts[t] = (counts[t] ?: 0) + 1
            }
        }
        return counts.entries
            .filter { it.value >= TOPIC_MIN }
            .map { Topic(it.key, it.value) }
            .sortedWith(compareByDescending<Topic> { it.said }.thenBy { it.term })
            .take(TOP_TOPICS)
    }

    /** The distinct topic-worthy terms in one message. */
    internal fun termsOf(text: String): Set<String> =
        tokens(body(text))
            .filter { keep(it) }
            .toSet()

    private fun keep(t: String): Boolean {
        // PLURALS TOO. The list is written in the singular, and the operator's
        // own mesh promptly reported MESSAGES as the topic of the day because
        // "message" was struck out and "messages" was not. Crude, and right
        // far more often than it is wrong: the only way this misfires is a real
        // topic whose singular happens to be a stopword.
        if (t in STOPWORDS || t.removeSuffix("s") in STOPWORDS) return false
        if (t.all { it.isDigit() }) return false
        return if (isCjk(t)) t.length in CJK_MIN..CJK_MAX else t.length >= LATIN_MIN
    }

    private fun isCjk(t: String): Boolean = t.any { it.code >= 0x3040 }

    /**
     * The message without its `name: ` prefix.
     *
     * Channel traffic carries the sender as text rather than as a key, and
     * leaving it in would make every regular's handle the day's top topic.
     * Bounded at 32 characters so a colon in an ordinary sentence — "left at
     * 10: nobody there" — does not eat the first half of the message.
     */
    private fun body(text: String): String {
        val sep = text.indexOf(": ")
        return if (sep in 1..32) text.substring(sep + 2) else text
    }

    private fun tokens(s: String): List<String> {
        val out = mutableListOf<String>()
        val cur = StringBuilder()
        // QUOTED LINES ARE SKIPPED. A reply that quotes the message it answers
        // would otherwise count every term in that message a second time, and
        // the loudest topic of the day becomes whatever got quoted most.
        s.lineSequence().filterNot { it.trimStart().startsWith(">") }.forEach { line ->
            line.lowercase().forEach { c ->
                if (c.isLetterOrDigit()) cur.append(c) else {
                    if (cur.isNotEmpty()) { out += cur.toString(); cur.clear() }
                }
            }
            if (cur.isNotEmpty()) { out += cur.toString(); cur.clear() }
        }
        return out
    }

    /** A term must carry this many MESSAGES before it is a topic rather than a remark. */
    const val TOPIC_MIN = 2

    /** How many a bay can show before the list stops being a summary. */
    const val TOP_TOPICS = 6

    const val LATIN_MIN = 3
    const val CJK_MIN = 2
    const val CJK_MAX = 6

    /**
     * Words that carry no subject.
     *
     * Taken from SNS so the two apps agree about what is not a topic, plus the
     * mesh's own furniture — a network where people say "mesh", "node" and
     * "test" constantly would otherwise report those as the news every day.
     */
    private val STOPWORDS = setOf(
        "the", "and", "for", "are", "was", "were", "been", "being", "this",
        "that", "these", "those", "with", "from", "have", "has", "had", "not",
        "you", "your", "youre", "yours", "they", "them", "their", "theyre",
        "she", "him", "her", "his", "hers", "our", "ours", "its", "who", "whom",
        "what", "when", "where", "which", "how", "why", "all", "any", "some",
        "can", "cant", "cannot", "will", "wont", "would", "could", "should",
        "shouldnt", "does", "doesnt", "did", "didnt", "dont", "get", "got",
        "getting", "going", "gonna", "wanna", "like", "just", "now", "here",
        "there", "then", "than", "too", "very", "about", "out", "over", "into",
        "onto", "off", "down", "back", "still", "also", "much", "many", "more",
        "most", "lot", "lots", "yeah", "yep", "nope", "okay", "lol", "haha",
        "hey", "hello", "thanks", "thx", "please", "pls", "http", "https",
        "www", "com", "one", "two", "see", "good", "well", "sure",
        "know", "think", "need", "want", "make", "made", "time", "today",
        "tonight", "morning", "afternoon", "evening", "guys", "everyone",
        // The mesh's own furniture.
        "mesh", "node", "nodes", "test", "testing", "hop", "hops", "ack",
        "msg", "message", "radio", "signal", "copy", "roger",
        // ORDINARY ENGLISH, added after the first run on a real day.
        //
        // SNS's list was written against a quiet channel and it shows: on 380
        // messages the operator's own mesh reported DOING, ANYONE and BUT as
        // the topics of the day. A term list can only ever be as good as the
        // traffic it was tested on, and this is the traffic.
        //
        // The rule for adding one: strike it if a wearer reading it as "the
        // day was about X" would learn nothing. REPEATER stays — that is a
        // real subject on this mesh. BUT never is.
        "but", "doing", "does", "done", "anyone", "anybody", "someone",
        "somebody", "something", "anything", "nothing", "everything",
        "come", "comes", "coming", "went", "goes", "gone",
        "look", "looks", "looking", "seen", "saw", "say", "says", "tell",
        "told", "asking", "asks", "work", "works", "working",
        "run", "runs", "running", "try", "tries", "trying",
        "use", "used", "using", "way", "ways", "day", "days", "night",
        "week", "weeks", "year", "years", "people", "thing", "things",
        "little", "big", "long", "short", "new", "old", "next", "last",
        "first", "again", "away", "around", "though", "because", "before",
        "after", "while", "since", "until", "yet", "ever", "even", "own",
        "same", "other", "another", "each", "every", "both", "few", "less",
        "least", "best", "better", "worse", "worst", "right", "left",
        "under", "through", "between", "against", "during", "within",
        "along", "across", "behind", "beyond", "near", "far",
        "hear", "heard", "hearing", "seeing", "great", "nice", "cool",
        "fine", "true", "yes", "maybe", "probably", "actually", "really",
        "pretty", "quite", "always", "often", "sometimes", "usually",
        "anyway", "anyways", "welcome", "later", "soon", "ago",
    )

    /** How the app marks its own messages, everywhere. */
    const val ME = "ME"

    /**
     * Everybody who spoke without saying who they were.
     *
     * One bucket rather than one voice each: on a channel there is no key to
     * tell them apart, so counting them separately would invent a crowd out of
     * what might be one person.
     */
    const val ANON = "?"

    /**
     * The histogram as a row of blocks, for a surface that has no geometry.
     *
     * Eight levels because that is what the block characters give, and the
     * scale is the peak rather than an absolute — a quiet day should still
     * show its own shape rather than a flat line.
     */
    fun sparkline(hourly: List<Int>): String {
        val peak = hourly.maxOrNull() ?: 0
        if (peak == 0) return "·".repeat(hourly.size)
        val bars = " ▁▂▃▄▅▆▇█"
        return hourly.joinToString("") { v ->
            if (v == 0) "·" else bars[(v * 8 / peak).coerceIn(1, 8)].toString()
        }
    }
}
