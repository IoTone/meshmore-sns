// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

/**
 * AUTOPEN — a reply written for THIS message rather than for messages in
 * general.
 *
 * `MeshmoreXR-autopen-spec.md`, built. The three canned replies cover most mesh
 * traffic precisely because most mesh traffic is acknowledgement. What they
 * cannot do is answer a question: "what's your ETA?" gets STAND BY, which is
 * not an answer, and the wearer either dictates or lets it go. This is for that
 * gap.
 *
 * ## What this is NOT, said plainly
 *
 * **There is no model here.** The spec says "a small on-device model" and this
 * is not one — it is intent recognition and a table of drafts. That deserves
 * stating rather than hiding behind the feature's name.
 *
 * It is also, on reflection, most of what the spec actually asked for. The spec
 * itself argues the point: "a cheerful reply to a message the model *scored* as
 * cheerful is a machine agreeing with its own guess. The useful version reads
 * intent — is this a question, a summons, a status report, an emergency — and
 * drafts accordingly." Reading intent is the whole job, and on the traffic a
 * LoRa mesh actually carries — a hundred and fifty bytes, mostly logistics —
 * the intent is usually carried by a handful of words and a question mark.
 *
 * What a real model would buy is the CONTENT of the answer: "20 minutes" rather
 * than "on my way". That needs to know something this app does not know, which
 * is where the wearer is going and when they will get there. So the honest
 * version of this feature drafts the FORM and leaves the wearer to supply the
 * fact — which is what these drafts do.
 *
 * The seam is the right shape either way. [suggest] takes a string and returns
 * a string, runs in microseconds, has no dependencies, and could be replaced by
 * a model tomorrow without any caller changing.
 *
 * ## Constraints from the spec, all still in force
 *
 * - **IT PROPOSES, IT NEVER SENDS.** The output goes to `Crown.propose`, which
 *   routes to the CONFIRM level like every other draft. `MeshLink.replyTo`
 *   remains the single gate.
 * - **MARKED AS GENERATED**, at COMPOSE and again at CONFIRM.
 * - **ON DEVICE.** Trivially: there is nothing to call.
 * - **THE WORD CEILING APPLIES.** Clipped to [Dictation.MAX_WORDS].
 * - **FAILS INTO ABSENCE.** No suggestion is a normal outcome, not an error.
 */
object Autopen {

    /**
     * What the incoming message is DOING, which is the thing worth answering.
     *
     * Not a sentiment scale. The spec's argument, kept: a reply keyed to how
     * cheerful a message sounded is a machine agreeing with its own guess,
     * while a reply keyed to whether somebody asked you a question is answering
     * the question.
     */
    enum class Intent { QUESTION, SUMMONS, STATUS, GREETING, EMERGENCY, UNKNOWN }

    /**
     * EMERGENCY exists so that nothing is suggested for it.
     *
     * This is the failure case the spec singles out — "an emergency wrongly
     * answered with a breezy acknowledgement" — and the fix is not a better
     * draft, it is no draft. A person who has just read a distress message
     * should compose the reply themselves, and the two seconds a canned button
     * saves are not worth the chance of sending something glib to somebody in
     * trouble because a classifier saw the word "help" in "help me carry this".
     *
     * The classifier is also least reliable here: the vocabulary is small, the
     * stakes are highest, and a false positive and a false negative are both
     * bad in the same direction.
     */
    private val EMERGENCY_WORDS = setOf(
        "sos", "mayday", "emergency", "urgent", "injured", "hurt", "bleeding",
        "trapped", "lost", "accident", "fire", "unconscious", "ambulance",
    )

    /**
     * Somebody wants you to come, or to be somewhere.
     *
     * "here" and "over" were in this list and had to come out. Both are ordinary
     * words in ordinary status traffic — "all good here", "over the ridge" —
     * and both made a report of somebody's own position read as a request for
     * yours. A word only belongs here if its presence is hard to explain any
     * other way.
     */
    private val SUMMONS_WORDS = setOf(
        "come", "meet", "bring", "waiting", "join", "rendezvous",
    )

    /**
     * "need" is a summons only when it is about YOU.
     *
     * It was a bare word in the list above until it was run over an evening of
     * real traffic from the Portland mesh, where "if you want new functionality
     * you need to start with the protocol" was answered with "ON MY WAY". The
     * word carries a summons about as often as it carries advice.
     */
    private val SUMMONS_PHRASES = setOf("need you", "need your", "need a hand", "need help")

    private val GREETING_WORDS = setOf(
        "hi", "hey", "hello", "morning", "evening", "night", "gday", "yo",
    )

    /**
     * A question that is asking WHEN. The most common one worth a form.
     *
     * Split into whole words and phrases because they must be matched
     * differently. A phrase has to be a substring; a single word must not be —
     * `contains("when")` also fires on "whenever", and more importantly it
     * fires on "when" used as a conjunction, which is most of its uses:
     * "let me know when you're done" is not a question about time.
     */
    private val WHEN_WORDS = setOf("eta", "when", "ready")
    private val WHEN_PHRASES = setOf("how long", "what time")

    /** A question that is asking WHERE. */
    private val WHERE_WORDS = setOf("where", "location", "position", "coords")
    private val WHERE_PHRASES = setOf("which way", "how far")

    /**
     * A question is SHORT. Past this it is prose, and prose containing "when"
     * is almost always using it as a conjunction.
     *
     * "have a look at the repeater log when you get a chance tomorrow" was
     * classified as a question about time on exactly that word.
     */
    private const val QUESTION_MAX_WORDS = 10

    private fun hits(words: List<String>, t: String, set: Set<String>, phrases: Set<String>) =
        words.any { it in set } || phrases.any { t.contains(it) }

    /** A question that is asking WHETHER — answerable yes or no. */
    private val YESNO_STARTS = setOf(
        "are", "is", "can", "could", "do", "did", "does", "will", "would",
        "have", "has", "should", "you", "any",
        // The interrogatives. A message opening with one of these is asking
        // something even when the writer did not reach for the question mark,
        // which on a thumb keyboard is most of the time.
        "what", "who", "how", "why", "which", "whats", "wheres", "whos",
    )

    /**
     * Read the intent. Pure, and cheap enough to run on arrival.
     *
     * THE ORDER IS THE DESIGN, and three of these rungs are there because the
     * obvious order got it wrong:
     *
     * 1. EMERGENCY first — a message that is both a question and a distress
     *    call is a distress call.
     * 2. A QUESTION MARK next. It is the strongest signal available and mesh
     *    traffic uses it correctly.
     * 3. SUMMONS **before** the bare time words. "come to the gate when you
     *    can" was being answered with an ETA, because "when" was tested first.
     *    An imperative beats a conjunction.
     * 4. Time and place words only on a SHORT message — see
     *    [QUESTION_MAX_WORDS].
     */
    fun read(text: String): Intent {
        val t = text.lowercase().trim()
        if (t.isBlank()) return Intent.UNKNOWN
        val words = t.split(Regex("[^a-z0-9]+")).filter { it.isNotBlank() }
        if (words.isEmpty()) return Intent.UNKNOWN

        if (words.any { it in EMERGENCY_WORDS }) return Intent.EMERGENCY
        if (t.contains('?')) return Intent.QUESTION
        if (hits(words, t, SUMMONS_WORDS, SUMMONS_PHRASES)) return Intent.SUMMONS
        if (words.size <= QUESTION_MAX_WORDS &&
            (hits(words, t, WHEN_WORDS, WHEN_PHRASES) ||
                hits(words, t, WHERE_WORDS, WHERE_PHRASES))
        ) {
            return Intent.QUESTION
        }
        // An unpunctuated question, which is most of them on a keyboard the
        // size of a thumb. Bounded by length: "have" opening a long sentence is
        // a statement about something, not a question.
        if (words.first() in YESNO_STARTS && words.size <= 8) return Intent.QUESTION
        if (words.size <= 3 && words.any { it in GREETING_WORDS }) return Intent.GREETING
        if (words.size >= 4) return Intent.STATUS
        return Intent.UNKNOWN
    }

    /**
     * A draft for [incoming], or null when there is nothing useful to offer.
     *
     * NULL IS A NORMAL ANSWER. The spec asks that this "fail silently into 'no
     * suggestion' rather than blocking the crown", and the same applies when it
     * simply has nothing to add: offering a fourth button that says roughly
     * what the first three say wastes a row and teaches the wearer to ignore
     * the row. It only speaks when it has a shape the canned replies do not.
     */
    fun suggest(incoming: String): String? {
        val t = incoming.lowercase()
        val words = t.split(Regex("[^a-z0-9]+")).filter { it.isNotBlank() }
        val draft = when (read(incoming)) {
            // See EMERGENCY_WORDS. No draft, on purpose.
            Intent.EMERGENCY -> null
            Intent.QUESTION -> when {
                hits(words, t, WHEN_WORDS, WHEN_PHRASES) -> "ETA TO FOLLOW, STAND BY"
                hits(words, t, WHERE_WORDS, WHERE_PHRASES) -> "SENDING MY POSITION SHORTLY"
                else -> "GOT YOUR QUESTION, ANSWERING SHORTLY"
            }
            Intent.SUMMONS -> "ON MY WAY, WILL CONFIRM WHEN CLOSE"
            // STATUS and GREETING are exactly what ROGER and the other canned
            // replies already cover. A fourth button that duplicates the first
            // three is worse than no fourth button.
            Intent.STATUS, Intent.GREETING, Intent.UNKNOWN -> null
        } ?: return null
        return clip(draft)
    }

    /**
     * The same ceiling dictation lives under, applied to generated text.
     *
     * [Dictation.MAX_WORDS] is derived from the MeshCore frame size, not from
     * taste, so text that did not come from a microphone is subject to the same
     * arithmetic. None of the drafts above is near it — this is here so that
     * the next person to add one cannot quietly break the frame budget.
     */
    fun clip(text: String): String {
        val w = text.trim().split(Regex("\\s+")).filter { it.isNotBlank() }
        return if (w.size <= Dictation.MAX_WORDS) w.joinToString(" ")
        else w.take(Dictation.MAX_WORDS).joinToString(" ")
    }

    /** What the COMPOSE row says. Short: the crown's plates are 12 characters. */
    const val LABEL = "AUTO REPLY"

    /** What the CONFIRM screen says, so the marking survives to the last screen. */
    const val MARK = "SUGGESTED — READ IT"
}
