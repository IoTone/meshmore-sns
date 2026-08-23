// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.util.Log

/**
 * THE ONE PLACE THIS APP MAKES A SOUND.
 *
 * [Synth] is arithmetic and [Motifs] is a vocabulary; neither knows how to
 * reach a speaker. This does, and it is deliberately the only thing that does,
 * so the rest of the app keeps naming EVENTS rather than tones — the property
 * that made swapping ToneGenerator out a one-file job.
 *
 * ## Why a thread rather than a buffer per cue
 *
 * A cue is a handful of notes that overlap and decay. Rendering each into its
 * own short buffer and firing it at the mixer means the app cannot honour §2.1
 * at all: no voice ceiling, no stealing, no ducking, and two cues landing
 * together clip against each other in the platform mixer where nothing can see
 * it. One renderer with one voice list is what makes those rules expressible.
 *
 * ## Why it stops
 *
 * The track is paused after a short run of silence rather than left playing.
 * On glasses worn all day an always-open output is a battery cost for nothing,
 * and the cost of restarting is a few milliseconds that fall inside the
 * envelope's own attack. Measured on the Aura: 48 kHz native, a 192-frame HAL
 * buffer, and free FAST tracks — so a block is 4 ms and the restart is
 * inaudible.
 */
class Audio {

    private var track: AudioTrack? = null
    private var thread: Thread? = null

    /** Voices the renderer is mixing. Guarded by itself. */
    private val voices = mutableListOf<Synth.Voice>()

    @Volatile private var running = false

    /**
     * Everything is multiplied by this. Speech and the critical cue drop it,
     * so an alert is never argued with by the sound of a menu opening.
     */
    @Volatile var duck: Float = 1f

    /** Set false by the wearer's silent preference; nothing sounds. */
    @Volatile var enabled: Boolean = true

    fun play(motif: Synth.Motif, timbre: Synth.Timbre) {
        if (!enabled) return
        synchronized(voices) { Synth.voice(motif, timbre, voices) }
        start()
    }

    /** Stop everything now — the wearer asked for silence, not a fade. */
    fun silence() {
        synchronized(voices) { voices.clear() }
    }

    private fun start() {
        if (running) return
        val t = open() ?: return
        running = true
        thread = Thread({ render(t) }, "meshmore-audio").apply {
            priority = Thread.MAX_PRIORITY
            isDaemon = true
            start()
        }
    }

    private fun open(): AudioTrack? {
        track?.let { return it }
        return runCatching {
            val min = AudioTrack.getMinBufferSize(
                Synth.RATE,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_FLOAT,
            ).coerceAtLeast(BLOCK * 4)
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        // MEDIA, as §1 requires: a cue that rides the
                        // notification stream is a cue that vanishes when the
                        // wearer silences notifications, and these are the app
                        // answering a hand.
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                        .setSampleRate(Synth.RATE)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                .setBufferSizeInBytes(min)
                .build()
                .also {
                    track = it
                    Log.i(TAG, "[audio] track open — ${Synth.RATE}Hz mono float, buffer ${min}B")
                }
        }.onFailure {
            Log.w(TAG, "[audio] no track: ${it.javaClass.simpleName} — falling back to tones")
        }.getOrNull()
    }

    private fun render(t: AudioTrack) {
        val buf = FloatArray(BLOCK)
        var quiet = 0
        runCatching { t.play() }
        while (running) {
            val any = synchronized(voices) {
                Synth.render(buf, voices)
                voices.isNotEmpty()
            }
            val g = duck
            if (g != 1f) for (i in buf.indices) buf[i] *= g
            val wrote = runCatching {
                t.write(buf, 0, buf.size, AudioTrack.WRITE_BLOCKING)
            }.getOrDefault(-1)
            if (wrote < 0) {
                Log.w(TAG, "[audio] write failed ($wrote) — stopping")
                break
            }
            // A SHORT TAIL OF SILENCE BEFORE STOPPING, so a motif's own gaps —
            // the space between two notes of a rising pair — never pause the
            // track mid-phrase.
            quiet = if (any) 0 else quiet + 1
            if (quiet > TAIL_BLOCKS) break
        }
        running = false
        runCatching { t.pause(); t.flush() }
    }

    fun release() {
        running = false
        synchronized(voices) { voices.clear() }
        runCatching { thread?.join(200) }
        runCatching { track?.release() }
        track = null
        thread = null
    }

    private companion object {
        const val TAG = "MeshmoreXR"

        /** 192 frames is the Aura's own HAL buffer: 4 ms at 48 kHz. */
        const val BLOCK = 192

        /** About a quarter second of silence before the track is paused. */
        const val TAIL_BLOCKS = 60
    }
}
