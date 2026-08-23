// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.ToneGenerator
import android.util.Log

/**
 * AUDIBLE CONFIRMATION — the one channel a gesture can use.
 *
 * A pinch on a target confirms itself: the thing you touched moves. A GESTURE
 * has no such feedback. You make a shape at the air and either something happens
 * or it does not, and when it does not you cannot tell which of these failed:
 * the hand was not seen, the shape was not recognised, the recognition did not
 * reach the action, or the action did nothing visible. Four failures, one
 * silence.
 *
 * A sound splits that in half. It fires at RECOGNITION, before the action runs,
 * so hearing it means "the classifier saw the letter" and the remaining question
 * is only whether the action worked. Not hearing it means the problem is
 * upstream of the app's logic entirely. That is the single most useful bit of
 * information available while gestures are unreliable, and it costs one tone.
 *
 * DISTINCT TONES PER OUTCOME, because "I heard something" is much weaker than
 * "I heard the recognition tone rather than the rejection one".
 *
 * ## The nine packs, and what these are not
 *
 * Brief §7 gives every theme an audio pack with a name and a character —
 * "Sonar", "Codec", "Arcade", "Bloom". Those descriptions are of COMPOSED
 * packs: granular textures, breath, a scale that shifts with mesh activity.
 * None of that is here and none of it is pretended.
 *
 * What is here is the SEAM in the right place, filled with the best that
 * ToneGenerator can do. Each pack picks its own tones, lengths and volume from
 * the platform's built-in set, which is enough for nine identities that are
 * audibly different from each other and roughly the right character —
 * TRIBUNAL is low and nearly silent, PURE PHASE is a bright stab, CODEC is a
 * radio click. Swapping in real assets later means replacing [play] and
 * nothing else; every call site already says WHICH EVENT rather than which
 * sound, which is the part that is expensive to change and the part that is
 * already right.
 *
 * The alternative was one beep for all nine themes with a comment promising
 * better, which is what was here before, and which makes eight of the nine
 * themes silent about their own identity.
 */
class Cue {

    /**
     * One theme's sonic identity.
     *
     * [vol] is 0..100 into ToneGenerator. It varies per pack on purpose:
     * "near-silence otherwise" is TRIBUNAL's actual spec and a pack that is
     * quiet is a design choice rather than a broken one.
     */
    class Pack(
        val key: String,
        val recognised: Int,
        val recognisedMs: Int,
        val opened: Int,
        val openedMs: Int,
        val tick: Int,
        val tickMs: Int,
        val closed: Int,
        val closedMs: Int,
        val vol: Int = 70,
        /**
         * E10 — a channel message. Defaults to the pack's own OPEN tone so a
         * pack that has not been given one is quiet-but-present rather than
         * silent; every pack below states its own.
         */
        val msgChannel: Int = opened,
        val msgChannelMs: Int = 300,
        /**
         * E11 — a DM. §2 is explicit that this "must be sonically distinct
         * from E10": the difference between somebody talking to a room and
         * somebody talking to YOU is the single most useful thing audio can
         * carry here, and it is carried by pitch and length, never by volume.
         */
        val msgDirect: Int = recognised,
        val msgDirectMs: Int = 400,
        /** E13 — the radio linked. One tone, at the end of the four steps. */
        val linkUp: Int = opened,
        val linkUpMs: Int = 260,
        /** E0 — WAKE. The only event allowed to run long; see [wake]. */
        val wakeTone: Int = opened,
        val wakeMs: Int = 900,
        /** E7 — a peer nobody here has heard before. Short; the mesh is busy. */
        val nodeFound: Int = tick,
        val nodeFoundMs: Int = 160,
    )

    companion object {
        private const val TAG = "MeshmoreXR"

        /**
         * A tone id no pack plays. §4.4: "Any theme may declare an event
         * silent; no theme may declare E16 CRITICAL silent."
         *
         * A sentinel rather than a nullable field, so a silent event is a
         * VALUE in the table beside the loud ones and reads as a decision.
         * Nullability would have made the same statement as an absence, which
         * is indistinguishable from forgetting.
         */
        const val SILENT = -1

        /**
         * How loud a welcome plays, as a fraction of the stream.
         *
         * WAS 0.22 AND WAS INAUDIBLE. "Low level" was read as an attenuation to
         * apply in the app, and that stacked three quiet things on top of each
         * other: the asset's own level (mean −14.9 dBFS, which is ordinary for
         * music), the wearer's music volume (7 of 15 on a USB route), and then
         * another 13 dB from this number. The result was a tune that the log
         * reported playing and nobody could hear.
         *
         * THE WEARER'S VOLUME CONTROL IS THE VOLUME CONTROL. An app that
         * pre-attenuates by an amount it picked is fighting the one control the
         * wearer actually has, and it loses in both directions — inaudible for
         * anybody who has turned the device down, and no quieter for anybody who
         * has turned it up. This keeps a little headroom under full scale so a
         * greeting is not the loudest thing the app can do, and leaves the rest
         * to the hardware.
         */
        const val WELCOME_GAIN = 0.8f

        /**
         * WHICH TUNE A THEME ARRIVES ON.
         *
         * Four exist — HALO, NERV, BIOLUME, VECTORLINE; the rest fall back to HALO's,
         * and that fallback is the honest shape of an unfinished set — five
         * silent themes would read as five broken ones. The seam that had to
         * be right is the CALL SITE, which asks for "this theme's welcome" and
         * does not know which file that is; adding the next one is a file in
         * res/raw and a line here.
         *
         * THE FALLBACK IS HALO'S AND NOT NERV'S, deliberately. HALO is the
         * first theme in the ladder and the one a fresh install wears, so the
         * tune most people hear first is the one written for the theme they are
         * actually in — and a theme borrowing a neighbour's identity is less
         * wrong when it borrows the default's.
         */
        fun welcomeFor(key: String): Int = when (key) {
            "halo" -> R.raw.welcome_halo
            "nerv" -> R.raw.welcome_nerv
            "biolume" -> R.raw.welcome_biolume
            "vector" -> R.raw.welcome_vector
            // AG-SYSTEMS TAKES THE HARD-DRIVING ONE. It is the Wipeout craft
            // HUD at 900 km/h and its audio pack is called velocity; if a
            // track is going to push, it pushes here.
            "aghud" -> R.raw.welcome_aghud
            "drpop" -> R.raw.welcome_drpop
            "recon" -> R.raw.welcome_recon
            // THE LAST TWO ARE SYNTHESISED, and they are the two that should
            // be. TERMINAL VOID is a terminal waking up — three square blips,
            // a sweep, and a phosphor hum that fades under the wordmark. SEELE
            // MONOLITH does not chirp: one slab of low tone, a fifth arriving
            // late, a single bell. A monolith that played a jingle would be
            // arguing with its own theme.
            "seele" -> R.raw.welcome_seele
            "void" -> R.raw.welcome_void
            else -> R.raw.welcome_halo
        }

        /** §2.1's ceiling, expressed as a minimum gap rather than a rate. */
        const val CHANNEL_GAP_MS = 900L
        const val DIRECT_GAP_MS = 400L

        /**
         * After this many channel arrivals inside the window the channel voice
         * rests until the window rolls over — roughly the spec's "20 s of
         * continuous traffic".
         */
        const val BURST_WINDOW_MS = 20_000L
        const val BURST_MAX = 12

        /**
         * Discovery is the loosest bucket because it is the noisiest event: a
         * radio waking in a busy area meets a dozen strangers in a minute.
         */
        const val DISCOVERY_GAP_MS = 2_500L

        /**
         * §2's duration for E16, and the only event allowed near it. Long
         * enough that it cannot be mistaken for an ordinary arrival, which is
         * the entire point of having it.
         */
        const val CRITICAL_MS = 1200

        /**
         * SONAR — HALO FIELD. A soft ping, sparse by design so it survives
         * eight hours outdoors without fatigue.
         */
        val SONAR = Pack(
            "sonar",
            ToneGenerator.TONE_PROP_BEEP, 90,
            ToneGenerator.TONE_PROP_BEEP2, 120,
            ToneGenerator.TONE_PROP_ACK, 30,
            ToneGenerator.TONE_PROP_NACK, 140,
            msgChannel = ToneGenerator.TONE_CDMA_PIP, msgChannelMs = 260,
            msgDirect = ToneGenerator.TONE_CDMA_ABBR_ALERT, msgDirectMs = 420,
            linkUp = ToneGenerator.TONE_CDMA_ANSWER, linkUpMs = 260,
            wakeTone = ToneGenerator.TONE_CDMA_ONE_MIN_BEEP, wakeMs = 900,
        )

        /** MISSION CONTROL — NERV. Data chirps and a three-tone alert cadence. */
        val MISSION = Pack(
            "mission",
            ToneGenerator.TONE_CDMA_ABBR_ALERT, 100,
            ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 150,
            ToneGenerator.TONE_CDMA_PIP, 30,
            ToneGenerator.TONE_SUP_ERROR, 180,
            vol = 78,
            msgChannel = ToneGenerator.TONE_CDMA_PIP, msgChannelMs = 240,
            msgDirect = ToneGenerator.TONE_CDMA_ABBR_ALERT, msgDirectMs = 440,
            linkUp = ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, linkUpMs = 300,
            wakeTone = ToneGenerator.TONE_CDMA_ABBR_ALERT, wakeMs = 950,
        )

        /** VELOCITY — AG-SYSTEMS. Confident and glossy; a race-start triad. */
        val VELOCITY = Pack(
            "velocity",
            ToneGenerator.TONE_CDMA_HIGH_SLS, 90,
            ToneGenerator.TONE_CDMA_ANSWER, 140,
            ToneGenerator.TONE_CDMA_PIP, 25,
            ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 170,
            vol = 76,
            msgChannel = ToneGenerator.TONE_CDMA_PIP, msgChannelMs = 220,
            msgDirect = ToneGenerator.TONE_CDMA_HIGH_SLS, msgDirectMs = 430,
            linkUp = ToneGenerator.TONE_CDMA_ANSWER, linkUpMs = 280,
            wakeTone = ToneGenerator.TONE_CDMA_HIGH_SLS, wakeMs = 950,
        )

        /**
         * TRIBUNAL — SEELE. "Deep resonant strikes for critical events, and
         * near-silence otherwise." The quietest pack in the set, and the low
         * PBX tone is the deepest thing the platform offers.
         */
        val TRIBUNAL = Pack(
            "tribunal",
            ToneGenerator.TONE_CDMA_LOW_PBX_L, 110,
            ToneGenerator.TONE_CDMA_LOW_PBX_SS, 190,
            ToneGenerator.TONE_CDMA_LOW_PBX_L, 25,
            ToneGenerator.TONE_CDMA_LOW_PBX_SLS, 220,
            vol = 52,
            // "Near-silence otherwise" — a channel message on the busiest band
            // in the app is exactly what TRIBUNAL declines to announce. §4.4
            // permits any theme to render an event as deliberate silence, and
            // this is the theme the permission was written for.
            msgChannel = SILENT, msgChannelMs = 0,
            // ...and silent on discovery too. "Near-silence otherwise" cannot
            // survive a chirp at every stranger the radio meets, and discovery
            // is the noisiest event in the taxonomy. E16 is still loud, because
            // no theme may silence that one.
            nodeFound = SILENT, nodeFoundMs = 0,
            msgDirect = ToneGenerator.TONE_CDMA_LOW_PBX_L, msgDirectMs = 460,
            linkUp = ToneGenerator.TONE_CDMA_LOW_PBX_SS, linkUpMs = 320,
            wakeTone = ToneGenerator.TONE_CDMA_LOW_PBX_SLS, wakeMs = 700,
        )

        /** PURE PHASE — DR POP. Y2K stabs. The loudest and most musical. */
        val PUREPHASE = Pack(
            "purephase",
            ToneGenerator.TONE_DTMF_D, 80,
            ToneGenerator.TONE_DTMF_A, 130,
            ToneGenerator.TONE_DTMF_1, 25,
            ToneGenerator.TONE_DTMF_S, 150,
            vol = 82,
            msgChannel = ToneGenerator.TONE_DTMF_3, msgChannelMs = 220,
            msgDirect = ToneGenerator.TONE_DTMF_B, msgDirectMs = 430,
            linkUp = ToneGenerator.TONE_DTMF_A, linkUpMs = 280,
            wakeTone = ToneGenerator.TONE_DTMF_D, wakeMs = 950,
        )

        /**
         * CODEC — RECON AMBER. Squelch bursts and morse-adjacent clicks.
         * "Monochrome sound to match monochrome light", so every event is the
         * same voice at a different length.
         */
        val CODEC = Pack(
            "codec",
            ToneGenerator.TONE_SUP_RADIO_ACK, 80,
            ToneGenerator.TONE_SUP_RADIO_NOTAVAIL, 120,
            ToneGenerator.TONE_CDMA_KEYPAD_VOLUME_KEY_LITE, 20,
            ToneGenerator.TONE_SUP_RADIO_NOTAVAIL, 180,
            vol = 66,
            msgChannel = ToneGenerator.TONE_SUP_RADIO_ACK, msgChannelMs = 200,
            msgDirect = ToneGenerator.TONE_SUP_RADIO_ACK, msgDirectMs = 460,
            linkUp = ToneGenerator.TONE_SUP_RADIO_ACK, linkUpMs = 300,
            wakeTone = ToneGenerator.TONE_SUP_RADIO_NOTAVAIL, wakeMs = 800,
        )

        /**
         * ARCADE — VECTORLINE. Every interaction a note on a scale. Four DTMF
         * rows are four pitches, which is as close to "quantized to a scale" as
         * this gets without assets.
         */
        val ARCADE = Pack(
            "arcade",
            ToneGenerator.TONE_DTMF_5, 70,
            ToneGenerator.TONE_DTMF_9, 110,
            ToneGenerator.TONE_DTMF_3, 22,
            ToneGenerator.TONE_DTMF_0, 150,
            vol = 74,
            msgChannel = ToneGenerator.TONE_DTMF_7, msgChannelMs = 240,
            msgDirect = ToneGenerator.TONE_DTMF_C, msgDirectMs = 440,
            linkUp = ToneGenerator.TONE_DTMF_9, linkUpMs = 300,
            wakeTone = ToneGenerator.TONE_DTMF_5, wakeMs = 950,
        )

        /** BLOOM — BIOLUME. Soft chimes, the least fatiguing pack. */
        val BLOOM = Pack(
            "bloom",
            ToneGenerator.TONE_CDMA_ANSWER, 100,
            ToneGenerator.TONE_CDMA_NETWORK_USA_RINGBACK, 160,
            ToneGenerator.TONE_CDMA_PIP, 22,
            ToneGenerator.TONE_CDMA_ONE_MIN_BEEP, 190,
            vol = 60,
            msgChannel = ToneGenerator.TONE_CDMA_PIP, msgChannelMs = 280,
            msgDirect = ToneGenerator.TONE_CDMA_ANSWER, msgDirectMs = 460,
            linkUp = ToneGenerator.TONE_CDMA_NETWORK_USA_RINGBACK, linkUpMs = 320,
            wakeTone = ToneGenerator.TONE_CDMA_NETWORK_USA_RINGBACK, wakeMs = 1000,
        )

        /** TELETYPE — TERMINAL VOID. Mechanical clacks, a real BEL. Lo-fi on purpose. */
        val TELETYPE = Pack(
            "teletype",
            ToneGenerator.TONE_PROP_ACK, 40,
            ToneGenerator.TONE_PROP_PROMPT, 80,
            ToneGenerator.TONE_PROP_ACK, 15,
            ToneGenerator.TONE_SUP_ERROR, 160,
            vol = 72,
            msgChannel = ToneGenerator.TONE_PROP_ACK, msgChannelMs = 200,
            msgDirect = ToneGenerator.TONE_PROP_PROMPT, msgDirectMs = 420,
            linkUp = ToneGenerator.TONE_PROP_BEEP2, linkUpMs = 260,
            wakeTone = ToneGenerator.TONE_PROP_PROMPT, wakeMs = 900,
        )

        val PACKS = listOf(
            SONAR, MISSION, VELOCITY, TRIBUNAL, PUREPHASE, CODEC, ARCADE, BLOOM, TELETYPE,
        )

        /**
         * A theme's pack by name, falling back to SONAR.
         *
         * Falls back rather than throwing: a theme with a typo'd pack name
         * should sound like the default, not take the audio path down.
         *
         * PURE, AND DELIBERATELY SILENT ABOUT THE FALLBACK. The obvious thing
         * is a warning here, and the first version had one — but a fallback
         * only reachable through a typo in a table that ships compiled does not
         * want a log line noticed at 3 a.m. on a headset, it wants a test.
         * `CuePackTest.everyThemesPackExists` walks every theme against every
         * pack and fails the build, which is a stronger guarantee and an
         * earlier one. Keeping this pure also keeps it callable from a JVM test
         * at all: android.util.Log is not mocked there and a warning would make
         * this function throw in exactly the case it exists to survive.
         */
        fun packFor(key: String): Pack = PACKS.firstOrNull { it.key == key } ?: SONAR
    }

    /**
     * The touch channel, riding the same events as the tones. Optional and
     * set by the host: Cue is constructed before a Context exists, and a cue
     * with no haptics is the emulator's normal state, not a fault.
     */
    var haptics: Haptics? = null

    private var gen: ToneGenerator? = null
    private var genVol: Int = -1

    /**
     * The pack in force. Set on a theme change, including a picker PREVIEW —
     * §S11 asks that you "hear the theme's audio pack fire on a sample event",
     * and a picker that restyles the world silently is showing you two thirds
     * of what you are choosing.
     */
    var pack: Pack = SONAR
        set(value) {
            if (field.key == value.key) return
            field = value
            // The generator carries the volume, so a pack that is quieter than
            // the last one needs a new one. Released rather than kept: two live
            // ToneGenerators on the same stream is a way to find out that this
            // device only has so many.
            if (genVol != value.vol) {
                runCatching { gen?.release() }
                gen = null
            }
            Log.i(TAG, "[cue] pack -> ${value.key}")
        }

    private fun tone(): ToneGenerator? {
        gen?.let { return it }
        // A missing or busy audio path must not take a gesture down with it.
        val t = runCatching { ToneGenerator(AudioManager.STREAM_MUSIC, pack.vol) }
            .onFailure { Log.w(TAG, "[cue] no tone generator: ${it.javaClass.simpleName}") }
            .getOrNull()
        gen = t
        genVol = pack.vol
        return t
    }

    /** A letter was recognised. Fires BEFORE the action, on purpose. */
    fun recognised() {
        play(Motifs.RECOGNISED, pack.recognised, pack.recognisedMs)
        // A letter recognised IS the commit of a gesture: E3, not E2 — the
        // spec keeps hover silent in the hand even on fast actuators.
        haptics?.click()
    }

    /** A surface opened. Higher and shorter than a rejection. */
    fun opened() {
        play(Motifs.OPENED, pack.opened, pack.openedMs)
        // E3 COMMIT. A surface opening is a selection that landed.
        haptics?.click()
    }

    /**
     * A DETENT PASSED — one notch of a continuous control.
     *
     * Deliberately the shortest and least eventful of these. A reel turned
     * through six slots fires this six times in about a second, and a tone
     * that is satisfying once is intolerable at that rate; this one has to
     * disappear into the gesture rather than announce it.
     */
    fun tick() = play(Motifs.TICK, pack.tick, pack.tickMs)

    /** A surface closed, or an action declined. */
    fun closed() = play(Motifs.CLOSED, pack.closed, pack.closedMs)

    // --- arrival, §S4's fourth channel ---------------------------------------

    /**
     * E10 / E11 — a message landed.
     *
     * §S4 fires four things on arrival and says the design must survive losing
     * any one. Three were built and this was the missing one, which meant every
     * arrival was silent — and audio is the one channel that reaches a wearer
     * who is not looking at anything.
     *
     * Channel and direct are DIFFERENT SOUNDS, not the same sound louder. §2
     * requires it, and the reason is that the distinction being carried is
     * categorical — a room, or you — and loudness is a scale.
     */
    fun arrived(direct: Boolean) {
        // E11 only: a DM summons; channel traffic gets NO haptic — the
        // difference between a room talking and somebody talking to YOU is
        // carried by this channel existing only for the second.
        if (direct) haptics?.summon()
        if (!allow(if (direct) Kind.DIRECT else Kind.CHANNEL)) return
        if (direct) play(Motifs.DM, pack.msgDirect, pack.msgDirectMs)
        else play(Motifs.CHANNEL, pack.msgChannel, pack.msgChannelMs)
    }

    /** E13 — the radio linked. */
    fun linked() {
        play(Motifs.LINKED, pack.linkUp, pack.linkUpMs)
        haptics?.rise()
    }

    /**
     * E13's other half — the radio LEFT. The closed tone plus the falling
     * buzz: this is the event most worth feeling, because it fires exactly
     * when the wearer is looking at a trail rather than at the band.
     */
    fun dropped() {
        // ITS OWN SHAPE NOW. Losing the radio used to play the same tone as
        // closing a menu — the biggest event in the app and the smallest,
        // indistinguishable. See Motifs.DROPPED, the inverse of LINKED.
        play(Motifs.DROPPED, pack.closed, pack.closedMs)
        haptics?.fall()
    }

    /**
     * E4 DENY — the closed tone with the double-click refusal under it.
     * For actions the app REFUSES (allow-list, no radio), never for things
     * that merely closed; a denial that feels like a close gets retried.
     */
    fun denied() {
        // Unpitched, in every pack — see Motifs.timbreFor. A refusal that
        // shares a tone with "a surface closed" is a refusal nobody notices.
        play(Motifs.DENIED, pack.closed, pack.closedMs)
        haptics?.refuse()
    }

    /**
     * E7 — a new peer joined the mesh.
     *
     * Rate-capped hard, and on its own bucket. Discovery is genuinely delightful
     * on a live mesh and it is also the event most likely to become a hailstorm:
     * a radio coming up in a busy area can meet a dozen strangers in a minute,
     * and the spec's §2.1 exists because of exactly that.
     */
    fun nodeFound() {
        if (!allow(Kind.DISCOVERY)) return
        play(Motifs.NODE_FOUND, pack.nodeFound, pack.nodeFoundMs)
    }

    /**
     * E16 CRITICAL — and it is the one event with rules rather than a tone.
     *
     * §2 and §4.4 together: "E16 CRITICAL is exempt from all three [density
     * mechanisms], ducks every other voice by 12 dB, and is the only event
     * permitted to interrupt", and "no theme may declare E16 CRITICAL silent".
     *
     * So this is deliberately NOT a per-pack field. Every other event in this
     * file is a theme's to choose, and making this one a table entry would be
     * inviting a future theme to give it a soft chime or nothing at all —
     * which the spec forbids, and which nobody would notice until it mattered.
     * It is the same tone, at the same length, in all nine, exempt from the
     * cap, and it stops the pack's own voice first.
     *
     * WHAT FIRES IT, today: a message whose intent reads as distress. Autopen
     * already classifies that — it is the case where it refuses to draft a
     * reply — so the same reading that declines to put words in your mouth is
     * the one that makes the app get your attention.
     */
    fun critical() {
        // Interrupt rather than mix. QUEUE_FLUSH stops whatever the pack was
        // saying, which is what "the only event permitted to interrupt" means
        // with the tools this path has.
        runCatching { tone()?.stopTone() }
        play(Motifs.CRITICAL, ToneGenerator.TONE_CDMA_ABBR_ALERT, CRITICAL_MS)
        haptics?.alarm()
        Log.i(TAG, "[cue] CRITICAL")
    }

    /**
     * E0 — WAKE, at first light, while the scene builds.
     *
     * Added to the taxonomy rather than found in it, because the wait is real:
     * the scene takes about fourteen seconds on this hardware and for most of
     * it the wearer has a wordmark and no evidence anything is happening. That
     * is the longest unexplained silence in the product and the first thing
     * anybody experiences.
     */
    /**
     * E12 — A MESSAGE YOU SENT ARRIVED.
     *
     * The reliability work has known this to the millisecond for weeks and had
     * nowhere to say it: a wearer had to open a bay to discover whether their
     * message landed. Short and high, and quiet enough to fire on every
     * message without becoming the sound of the app.
     */
    fun delivered() = play(Motifs.DELIVERED, pack.tick, pack.tickMs)

    /**
     * AND ONE THAT DID NOT.
     *
     * The only descending motif in the set, so a loss can never be mistaken
     * for anything else. Unpleasant on purpose; short so it is not a
     * punishment. A haptic goes with it because this is the one outcome a
     * wearer would want to feel while looking somewhere else.
     */
    fun lost() {
        play(Motifs.LOST, pack.closed, pack.closedMs)
        haptics?.fall()
    }

    /** A node that was there is not any more — NODE_FOUND, mirrored. */
    fun nodeLost() = play(Motifs.NODE_LOST, pack.closed, pack.closedMs)

    fun wake() = play(Motifs.OPENED, pack.wakeTone, pack.wakeMs)

    /**
     * One rung of the link handshake, as pitch.
     *
     * The four steps already exist and already log; four ascending DTMF rows
     * against them cost nothing and turn a readout into something you can HEAR
     * go wrong — you stop hearing the ladder climb, and where it stopped is
     * where the fault is.
     *
     * Deliberately the same four tones in every pack. This is a measurement,
     * not an identity, and somebody who learns the ladder in one theme should
     * not have to relearn it in another.
     */
    fun linkStep(n: Int) {
        val row = intArrayOf(
            ToneGenerator.TONE_DTMF_1,
            ToneGenerator.TONE_DTMF_4,
            ToneGenerator.TONE_DTMF_7,
            ToneGenerator.TONE_DTMF_S,
        )
        play(row.getOrNull(n - 1) ?: return, 70)
    }

    // --- density control, §2.1, mandatory ------------------------------------

    private enum class Kind { CHANNEL, DIRECT, DISCOVERY }

    private val lastAt = HashMap<Kind, Long>()
    private var burst = 0
    private var burstFrom = 0L

    /**
     * THE RATE CEILING AND THE AMBIENT FLOOR, from §2.1.
     *
     * "Without limits the app becomes unwearable" is not a figure of speech on
     * this mesh: the Portland channel lands three messages a second on a busy
     * evening, and a companion app that chirps at that rate gets muted — at
     * which point it has lost ALL FOUR arrival channels, not one.
     *
     * Two of the spec's three mechanisms are implementable against a
     * ToneGenerator. The rate ceiling is exact. The ambient decay is not: the
     * platform offers no per-tone gain, so the honest version of "floors at
     * -18 dB" is "stops sounding" — which is a bigger intervention than
     * specified and is therefore logged when it happens.
     *
     * DIRECT MESSAGES GET THEIR OWN BUCKET, and a shorter gap. Somebody
     * addressing you personally three times in ten seconds is not noise; it is
     * the most important thing that has happened all day.
     */
    private fun allow(kind: Kind): Boolean {
        val now = android.os.SystemClock.uptimeMillis()
        val gap = when (kind) {
            Kind.DIRECT -> DIRECT_GAP_MS
            Kind.CHANNEL -> CHANNEL_GAP_MS
            Kind.DISCOVERY -> DISCOVERY_GAP_MS
        }
        if (now - (lastAt[kind] ?: 0L) < gap) return false
        if (kind == Kind.CHANNEL) {
            if (now - burstFrom > BURST_WINDOW_MS) { burst = 0; burstFrom = now }
            burst++
            if (burst > BURST_MAX) {
                // The mesh should FEEL busy without becoming fatiguing. The
                // ember and the cuff still fire; only the sound stands down.
                if (burst == BURST_MAX + 1) {
                    Log.i(TAG, "[cue] channel audio resting — busy mesh")
                }
                return false
            }
        }
        lastAt[kind] = now
        return true
    }

    /**
     * WHAT THIS PACK SOUNDS LIKE, on demand.
     *
     * The picker's sample event. Deliberately the OPEN tone rather than a
     * separate demo sound: a demo that plays something the app never plays is a
     * demo of nothing, and the point is to let somebody choose a pack they will
     * be hearing all day.
     */
    fun sample() = play(Motifs.OPENED, pack.opened, pack.openedMs)

    /**
     * THE THEME'S WELCOME — the one composed sound in the app, played once when
     * a theme arrives.
     *
     * Everything else here is a TONE: a confirmation, a measurement, feedback
     * you need and stop hearing after a day. This is the opposite kind of sound
     * and needs the opposite treatment. It plays at arrival and never again,
     * which is what makes it a greeting rather than a jingle — a sound that
     * announces a theme every time you glance at something would be the first
     * thing anybody turned off.
     *
     * QUIET, DELIBERATELY. [WELCOME_GAIN] is a fraction of full scale because
     * these are open-ear glasses: whatever plays here is mixed with traffic,
     * conversation and everything else the wearer needs to keep hearing, and a
     * welcome that talks over the room is a welcome that makes the glasses
     * unwearable in company.
     *
     * ONE AT A TIME, and a fast theme-switch cuts the previous one off rather
     * than layering — two overlapping greetings is a noise, not a chord.
     *
     * Failure is silence. A missing resource, a busy audio path, or a codec
     * this device does not have must never take down the theme change it is
     * decorating.
     */
    fun welcome(context: Context, resId: Int, loop: Boolean = false) {
        if (resId == 0) return
        runCatching {
            stopWelcome()
            // STATED ATTRIBUTES, not the default. On XR the default carries no
            // usage and the platform is free to place the stream where it
            // likes; MUSIC/MEDIA is what this is and what the wearer's own
            // volume control governs.
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            val mp = MediaPlayer.create(context, resId, attrs, 0)
            if (mp == null) {
                Log.w(TAG, "[cue] welcome $resId would not open")
                return
            }
            mp.setVolume(WELCOME_GAIN, WELCOME_GAIN)
            // LOOPED WHILE SOMETHING IS BEING WAITED FOR, once otherwise.
            //
            // The tune is three seconds and the boot is about fourteen, so a
            // single pass leaves eleven seconds of silence in the middle of the
            // one wait the wearer cannot skip. Looping is only ever right while
            // a wait is in progress, which is why the caller says so rather than
            // this deciding: a loop with nothing to end it is a jingle that
            // never stops, and [endWelcome] is the other half of this call.
            mp.isLooping = loop
            // WHAT THE HARDWARE IS ACTUALLY DOING, because "it played" and "it
            // was audible" are different claims and the first one is all a
            // start() can support. Reported as no sound at all while the log
            // said playing: the route was a USB device at 7 of 15 and the gain
            // was a further 13 dB down on already-quiet content.
            val am = context.getSystemService(AudioManager::class.java)
            val vol = am?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: -1
            val max = am?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: -1
            Log.i(TAG, "[cue] welcome gain=$WELCOME_GAIN stream=$vol/$max")
            if (vol == 0) Log.w(TAG, "[cue] welcome inaudible — music volume is 0")
            // RELEASED BY THE PLAYER ITSELF. A MediaPlayer holds a codec and an
            // audio track; leaving nine of them finished-but-alive is how a
            // long session runs out of both.
            mp.setOnCompletionListener {
                runCatching { it.release() }
                if (welcomer === it) welcomer = null
            }
            welcomer = mp
            mp.start()
            Log.i(TAG, "[cue] welcome playing at $WELCOME_GAIN")
        }.onFailure { Log.w(TAG, "[cue] welcome failed: ${it.javaClass.simpleName}") }
    }

    /**
     * END A LOOPING WELCOME — at the moment the thing it was covering happens.
     *
     * Stops LOOPING rather than stopping the sound: cutting a three-second tune
     * off mid-phrase is more noticeable than the wait it was covering, and the
     * event that ends the wait is a good moment to hear a phrase finish. If it
     * is already on its last pass this does nothing at all, which is correct.
     *
     * Idempotent, because the caller is a frame loop and will call it on every
     * frame after the one that mattered.
     */
    fun endWelcome() {
        welcomer?.let {
            if (it.isLooping) {
                runCatching { it.isLooping = false }
                Log.i(TAG, "[cue] welcome — last pass")
            }
        }
    }

    private fun stopWelcome() {
        welcomer?.let { runCatching { it.stop() }; runCatching { it.release() } }
        welcomer = null
    }

    private var welcomer: MediaPlayer? = null

    /**
     * THE SYNTHESISER, WHICH IS NOW WHAT MAKES THE SOUND.
     *
     * §1.2 asked for procedural synthesis and zero audio assets from the
     * start; what shipped was the platform's DTMF and CDMA tones because they
     * were there. [Synth] and [Motifs] replace them, and this is the seam the
     * class note above promised would be the only thing that had to change —
     * all 148 call sites still name an event.
     */
    private val audio = Audio()

    /** Off with the wearer's silent preference; nothing sounds at all. */
    var enabled: Boolean
        get() = audio.enabled
        set(v) { audio.enabled = v; if (!v) audio.silence() }

    /**
     * Play a shape, in this pack's voice.
     *
     * [fallbackId] and [fallbackMs] are the old ToneGenerator values, kept for
     * one reason: a device that refuses an AudioTrack should still answer a
     * gesture. A silent app on a headset is indistinguishable from an app that
     * did not see the hand, which is the whole failure Cue was written for.
     */
    private fun play(motif: Synth.Motif, fallbackId: Int, fallbackMs: Int) {
        if (!audio.enabled) return
        val timbre = Motifs.timbreFor(pack.key, motif)
        runCatching { audio.play(motif, timbre) }
            .onFailure {
                Log.w(TAG, "[cue] synth failed: ${it.javaClass.simpleName} — tone")
                play(fallbackId, fallbackMs)
            }
    }

    private fun play(id: Int, ms: Int) {
        // SILENT is a value in the table, not an absence. See the constant.
        if (id == SILENT || ms <= 0) return
        runCatching { tone()?.startTone(id, ms) }
            .onFailure { Log.w(TAG, "[cue] tone failed: ${it.javaClass.simpleName}") }
    }

    fun release() {
        audio.release()
        runCatching { gen?.release() }
        gen = null
        genVol = -1
        stopWelcome()
    }
}
