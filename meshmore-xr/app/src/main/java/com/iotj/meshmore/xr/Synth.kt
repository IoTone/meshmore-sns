// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * THE APP'S SOUND, AS ARITHMETIC.
 *
 * §1.2 of the audio brief asked for procedural synthesis and zero audio
 * assets, and gave the reason that decides it: pure maths can be unit-tested
 * and a sample cannot. What shipped instead was `ToneGenerator` playing the
 * platform's DTMF and CDMA tones — nine tables that do differ from each other,
 * and a vocabulary of beeps that cannot say anything the platform did not
 * already have a beep for. Nine welcome MP3s shipped too, which §1.2 forbids.
 *
 * This is the engine that lets the seam already in [Cue] carry what it was
 * built for. Everything here is deterministic and runs on a desktop JVM: no
 * Android types, no session, no clock. [render] is the whole contract — give
 * it voices and a buffer, get samples.
 *
 * ## The grammar: event owns the contour, theme owns the timbre
 *
 * Nine themes times sixteen events is a hundred and forty-four sounds, which
 * is not a vocabulary, it is a phrasebook nobody opens. So the two axes are
 * split. A message ALWAYS arrives as two notes rising; on AG-SYSTEMS that is a
 * filtered blip, on VOID a square-wave chirp, on SEELE a struck bell. Learn the
 * shape once and it holds everywhere, which is what a wearer changing themes
 * needs and what nine unrelated tone tables can never give.
 *
 * Contour rather than absolute pitch because contour survives a noisy street.
 *
 * ## Why the numbers are what they are
 *
 * 48 kHz because that is the Aura's native rate — measured, along with a
 * 192-frame HAL buffer and a free fast-track path, so a block is 4 ms and the
 * latency is inaudible. Six voices because §2.1 says six with stealing. And
 * every level sits well under 1.0 because additive optics have a brightness
 * budget and a shared band has an airtime budget; a wearable has a loudness
 * one, and the first thing an app that ignores it earns is a silent switch.
 */
object Synth {

    const val RATE = 48_000

    /** §2.1: six concurrent voices, oldest and quietest stolen first. */
    const val MAX_VOICES = 6

    /** Nothing this engine emits may exceed it. */
    const val CEILING = 0.7f

    /**
     * Headroom, applied to every voice.
     *
     * The class note above claimed "every level sits well under 1.0" and the
     * code did not honour it: an oscillator swings +/-1, a level of 1.0 left it
     * there, and every single-note motif in eight of nine packs hit the ceiling
     * and clamped. Distortion on every cue the app makes, from a sentence that
     * was true only in the comment.
     *
     * 0.45 leaves a note peaking at about two thirds of the ceiling, which is
     * room for two voices to overlap during a motif's handover without either
     * of them being squared off.
     */
    const val MASTER = 0.45f

    // --- what a sound is made of --------------------------------------------

    enum class Wave { SINE, TRI, SQUARE, SAW, NOISE }

    /**
     * One theme's voice: what it is made of and how it behaves.
     *
     * [bright] is a one-pole low-pass in normalised cutoff, applied per sample.
     * Cheap, stable, and enough to tell a soft pack from a hard one — a proper
     * filter is a later problem and would not change any decision here.
     */
    data class Timbre(
        val wave: Wave,
        /** Second oscillator a fraction of a semitone away, for width. 0 = off. */
        val detune: Float = 0f,
        /** 0..1, where 1 is unfiltered. */
        val bright: Float = 1f,
        /** Multiplies every envelope stage; a slow pack breathes, a hard one clicks. */
        val timeScale: Float = 1f,
        /** Per-pack loudness trim, so no theme is twice as loud as another. */
        val gain: Float = 1f,
    )

    /** One note of a motif: a pitch offset in semitones, and how long it lasts. */
    data class Step(val semitones: Int, val ms: Int, val level: Float = 1f)

    /**
     * A named shape. THE EVENT'S IDENTITY, and the thing a wearer learns.
     *
     * [root] is the base pitch in Hz before the steps offset it. It is a
     * property of the motif rather than the theme so that a rising two-note
     * message is the same interval everywhere, which is the entire point.
     */
    data class Motif(val root: Float, val steps: List<Step>)

    // --- the voice ----------------------------------------------------------

    /**
     * A sounding note.
     *
     * ATTACK IS NEVER ZERO. A step from silence to full amplitude in one sample
     * is a click, and a click is what cheap alert sounds are made of; 4 ms is
     * inaudible as a fade and removes it entirely.
     */
    class Voice(
        val freq: Float,
        val durMs: Int,
        val level: Float,
        val timbre: Timbre,
        /**
         * Frames of silence before this note begins.
         *
         * THE MOTIF'S WHOLE MEANING LIVES HERE. The first version stored this
         * and never read it, so every note of a motif started at once: a
         * rising two-note message was one chord, the contour that the entire
         * grammar rests on did not exist, and the summed notes hit the clipping
         * ceiling in all nine packs. Three tests caught it before anyone heard
         * it, which is the argument for synthesis over samples in one line.
         */
        val startFrame: Int = 0,
    ) {
        var frame = 0
            private set
        private var waited = 0
        private var phase = 0.0
        private var phase2 = 0.0
        private var lp = 0f
        private var rng = 0x2F6E2B1
        private val total = (durMs * RATE / 1000f * timbre.timeScale).toInt().coerceAtLeast(64)
        private val attack = min(RATE * 4 / 1000, total / 4)

        val done: Boolean get() = waited >= startFrame && frame >= total

        private fun osc(p: Double, w: Wave): Float = when (w) {
            Wave.SINE -> sin(p).toFloat()
            Wave.TRI -> (2.0 / PI * kotlin.math.asin(sin(p))).toFloat()
            Wave.SQUARE -> if (sin(p) >= 0) 1f else -1f
            Wave.SAW -> ((p % (2 * PI)) / PI - 1.0).toFloat()
            Wave.NOISE -> {
                rng = rng * 1103515245 + 12345
                ((rng shr 16) and 0x7FFF) / 16384f - 1f
            }
        }

        /** One sample, envelope and all. Advances the voice. */
        fun next(): Float {
            if (waited < startFrame) { waited++; return 0f }
            if (done) return 0f
            val step = 2.0 * PI * freq / RATE
            phase += step
            if (timbre.detune > 0f) phase2 += step * (1.0 + timbre.detune)
            var s = osc(phase, timbre.wave)
            if (timbre.detune > 0f) s = (s + osc(phase2, timbre.wave)) * 0.5f
            // Attack, then an exponential decay to silence. No sustain: every
            // sound this app makes is an event, and an event does not hold.
            val env = if (frame < attack) {
                frame / attack.toFloat()
            } else {
                val t = (frame - attack) / (total - attack).toFloat()
                exp(-4.0 * t).toFloat()
            }
            // One-pole low pass. bright = 1 leaves the signal alone.
            lp += (s - lp) * timbre.bright.coerceIn(0.02f, 1f)
            frame++
            return lp * env * level * timbre.gain * MASTER
        }
    }

    // --- rendering ----------------------------------------------------------

    /**
     * Mix [voices] into [out], removing the finished ones.
     *
     * MONO, deliberately and temporarily. §4 wants an arrival spatialised to
     * the sender's true bearing, which needs a panner and a bearing this engine
     * has no business knowing; mono now keeps that door open and closes none.
     *
     * The ceiling is a hard clamp rather than a limiter. A limiter would be
     * kinder to a mix that is too hot; a clamp makes it audible in a test, and
     * a test that hears distortion is worth more here than a mix that hides it.
     */
    fun render(out: FloatArray, voices: MutableList<Voice>) {
        java.util.Arrays.fill(out, 0f)
        if (voices.isEmpty()) return
        for (i in out.indices) {
            var acc = 0f
            for (v in voices) if (!v.done) acc += v.next()
            out[i] = acc.coerceIn(-CEILING, CEILING)
        }
        voices.removeAll { it.done }
    }

    /**
     * Turn a motif into voices, stealing if the six are full.
     *
     * STEALS THE OLDEST, which is the one furthest through its decay and so the
     * one whose disappearance is least audible. §2.1 asks for stealing and does
     * not say which; this is the choice that costs the listener least.
     */
    fun voice(motif: Motif, timbre: Timbre, into: MutableList<Voice>) {
        // FRAMES, NOT MILLISECONDS. The first version accumulated the step
        // durations and handed them over as a frame count, so a 90 ms gap
        // became 90 frames — 1.9 ms — and the notes still landed on top of one
        // another. The same three tests failed identically, which is how it was
        // caught: a fix that changes nothing is a fix aimed at the wrong line.
        //
        // Scaled by the pack's own timeScale so a slow theme's notes stay in
        // step with each other rather than overlapping as they lengthen.
        var at = 0f
        motif.steps.forEach { s ->
            while (into.size >= MAX_VOICES) into.removeAt(0)
            into += Voice(
                freq = motif.root * pow2(s.semitones / 12f),
                durMs = s.ms,
                level = s.level,
                timbre = timbre,
                startFrame = at.toInt(),
            )
            at += s.ms * RATE / 1000f * timbre.timeScale
        }
    }

    private fun pow2(x: Float): Float = exp(x * 0.6931472f)

    /** Peak absolute sample, for tests and for a loudness trim that is measured. */
    fun peak(buf: FloatArray): Float {
        var p = 0f
        for (s in buf) p = max(p, abs(s))
        return p
    }

    /** Root-mean-square, which is what "is this actually audible" means. */
    fun rms(buf: FloatArray): Float {
        if (buf.isEmpty()) return 0f
        var acc = 0.0
        for (s in buf) acc += s.toDouble() * s
        return kotlin.math.sqrt(acc / buf.size).toFloat()
    }
}
