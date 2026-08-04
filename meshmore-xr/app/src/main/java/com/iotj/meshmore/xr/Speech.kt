// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.content.Context
import android.speech.tts.TextToSpeech
import android.util.Log
import java.util.Locale

/**
 * READING A MESSAGE OUT LOUD.
 *
 * The single most glasses-shaped feature in the roadmap, and the cheapest. A
 * head-mounted display is worn while doing something else with your hands and
 * eyes -- walking, driving a boat, working a site -- and the whole argument for
 * putting a mesh radio on your face is that you can stay in the task. A message
 * you have to stop and read defeats that; a message that reads itself does not.
 *
 * §4.1's legibility floor has no jurisdiction here, which is the point: audio
 * is the one channel in this app that costs no visual angle at all.
 *
 * LAZY AND FORGIVING. TextToSpeech takes a moment to initialise and can fail
 * outright on a device with no voice data, so nothing here is created until
 * something is actually spoken and every failure is a log line rather than an
 * exception. A companion app that crashes because it could not find a voice is
 * a worse companion than one that stays quiet.
 */
class Speech(private val context: Context) {

    private var tts: TextToSpeech? = null
    private var ready = false
    private var pending: String? = null

    /** Whether the engine ever came up. Surfaces use it to say so honestly. */
    val available: Boolean get() = ready

    fun say(text: String) {
        if (text.isBlank()) return
        val t = tts
        if (t != null) {
            if (ready) speak(t, text) else pending = text
            return
        }
        pending = text
        tts = runCatching {
            TextToSpeech(context) { status ->
                ready = status == TextToSpeech.SUCCESS
                if (!ready) {
                    Log.w(TAG, "[tts] engine unavailable (status $status)")
                    pending = null
                    return@TextToSpeech
                }
                runCatching { tts?.language = Locale.getDefault() }
                    .onFailure { Log.w(TAG, "[tts] locale: ${it.javaClass.simpleName}") }
                pending?.let { p -> tts?.let { speak(it, p) } }
                pending = null
            }
        }.onFailure { Log.w(TAG, "[tts] no engine: ${it.javaClass.simpleName}") }.getOrNull()
    }

    private fun speak(t: TextToSpeech, text: String) {
        // FLUSH, not queue. Two messages arriving together should leave you
        // hearing the newer one, not waiting out the older -- a backlog you
        // cannot skip is the reason people turn announcements off.
        runCatching { t.speak(text, TextToSpeech.QUEUE_FLUSH, null, "meshmore") }
            .onFailure { Log.w(TAG, "[tts] speak failed: ${it.javaClass.simpleName}") }
    }

    fun stop() {
        runCatching { tts?.stop() }
    }

    fun release() {
        runCatching { tts?.stop(); tts?.shutdown() }
        tts = null
        ready = false
        pending = null
    }

    private companion object {
        const val TAG = "MeshmoreXR"
    }
}
