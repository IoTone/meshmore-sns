// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * SPEAKING A REPLY.
 *
 * A headset has no keyboard and should not grow one. Dictation is the input a
 * pair of glasses actually has, and on a mesh radio the things people send are
 * short enough that a sentence of speech is usually the whole message.
 *
 * A HARD WORD LIMIT, ENFORCED WHILE YOU TALK. Not a nicety and not a display
 * detail: a MeshCore text frame is small, the band is shared, and a long
 * transmission occupies it for everyone. So there is a ceiling, and the ceiling
 * is visible as you approach it rather than discovered afterwards by having
 * your sentence cut in half. Partial results drive the count, which is exactly
 * what partial results are good for -- they are too unreliable to send and
 * perfectly reliable for counting words.
 *
 * NOTHING LEAVES THE HEADSET WITHOUT A SECOND ACT. This class produces a
 * DRAFT and never a transmission. Speech recognition mishears, and the failure
 * mode of a radio that transmits what it thought it heard is that a stranger
 * receives it -- so the confirm step is not politeness, it is the thing that
 * makes dictation safe to have at all.
 *
 * PERMISSION IS ASKED AT THE MOMENT OF SPEAKING, never at startup. A
 * microphone prompt on first launch of a mesh radio reads as the app wanting to
 * listen to the room, and it would be the first thing anybody saw.
 */
class Dictation(private val context: Context) {

    /** What the wearer is currently saying, and whether it is still running. */
    class Draft(val text: String, val words: Int, val listening: Boolean, val full: Boolean)

    private var rec: SpeechRecognizer? = null
    private var heard = ""
    private var running = false
    private var failure: String? = null

    /** Raised on every change, so the surface can redraw the count. */
    var onUpdate: ((Draft) -> Unit)? = null

    /** Raised once, with the final text, when the wearer stops talking. */
    var onFinal: ((String) -> Unit)? = null

    val listening: Boolean get() = running

    /** Why it is not working, in words meant for the wearer. */
    val problem: String? get() = failure

    fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    /** Must be called on the main thread — SpeechRecognizer insists. */
    fun start() {
        if (running) return
        failure = null
        heard = ""
        if (!hasPermission()) {
            failure = "MIC NOT ALLOWED"
            emit()
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            failure = "NO SPEECH ENGINE"
            emit()
            return
        }
        val r = rec ?: runCatching { SpeechRecognizer.createSpeechRecognizer(context) }
            .onFailure { Log.w(TAG, "[stt] create failed: ${it.javaClass.simpleName}") }
            .getOrNull() ?: run {
            failure = "NO SPEECH ENGINE"
            emit()
            return
        }
        rec = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                running = true
                emit()
            }

            override fun onPartialResults(partial: Bundle?) {
                take(partial)
                // THE CEILING STOPS THE RECOGNISER, not just the display. A
                // limit that only greys out a counter while the engine keeps
                // listening teaches people the limit is advisory, and then the
                // truncation at send time is a surprise.
                if (words(heard) >= MAX_WORDS) stop()
            }

            override fun onResults(results: Bundle?) {
                take(results)
                running = false
                emit()
                onFinal?.invoke(clipped())
            }

            override fun onError(code: Int) {
                running = false
                // NO SPEECH is not an error worth naming: it is what happens
                // when somebody opens dictation and thinks about it.
                failure = when (code) {
                    SpeechRecognizer.ERROR_NO_MATCH,
                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> null
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "MIC NOT ALLOWED"
                    SpeechRecognizer.ERROR_NETWORK,
                    SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "SPEECH NEEDS NETWORK"
                    else -> "COULD NOT HEAR"
                }
                emit()
                if (heard.isNotBlank()) onFinal?.invoke(clipped())
            }

            override fun onBeginningOfSpeech() = Unit
            override fun onEndOfSpeech() { running = false; emit() }
            override fun onRmsChanged(v: Float) = Unit
            override fun onBufferReceived(b: ByteArray?) = Unit
            override fun onEvent(t: Int, p: Bundle?) = Unit
        })
        val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            // Prefer on-device where the platform has it: a mesh radio is used
            // where there is no other network, which is the whole point of one.
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        }
        runCatching { r.startListening(i) }
            .onFailure {
                Log.w(TAG, "[stt] start failed: ${it.javaClass.simpleName}")
                failure = "COULD NOT LISTEN"
                running = false
                emit()
            }
    }

    fun stop() {
        runCatching { rec?.stopListening() }
        running = false
        emit()
    }

    fun cancel() {
        runCatching { rec?.cancel() }
        running = false
        heard = ""
        emit()
    }

    fun release() {
        runCatching { rec?.destroy() }
        rec = null
        running = false
        heard = ""
    }

    private fun take(b: Bundle?) {
        val list = b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        list?.firstOrNull()?.let { heard = it }
        emit()
    }

    private fun emit() = onUpdate?.invoke(
        Draft(clipped(), words(heard), running, words(heard) >= MAX_WORDS),
    )

    /** The draft as it would be sent: never longer than the ceiling. */
    fun clipped(): String =
        heard.trim().split(WS).filter { it.isNotEmpty() }.take(MAX_WORDS).joinToString(" ")

    private fun words(s: String) = s.trim().split(WS).count { it.isNotEmpty() }

    companion object {
        private const val TAG = "MeshmoreXR"
        private val WS = Regex("\\s+")

        /**
         * TWENTY WORDS.
         *
         * Not a round number picked for looking tidy: a MeshCore text frame
         * carries on the order of 150 bytes, an English word averages about
         * five characters plus a space, and twenty of them is roughly 120 —
         * inside the frame with room for a callsign prefix. Past that the
         * radio would fragment or truncate, and a limit the wearer can see is
         * better than one the protocol enforces silently.
         */
        const val MAX_WORDS = 20
    }
}
