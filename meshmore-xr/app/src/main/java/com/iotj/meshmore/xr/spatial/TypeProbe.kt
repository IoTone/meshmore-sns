// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.Log
import androidx.xr.runtime.Session
import androidx.xr.scenecore.Texture
import java.io.File

/**
 * CAN WE RASTERISE TEXT AT RUNTIME AND SAMPLE IT? — a probe, not a feature.
 *
 * MeshmoreXR-typography.md §6.2 specifies tier R as: one text run -> Paint ->
 * PNG in cacheDir -> Texture.create(path) -> quad. Everything downstream of that
 * plan — CJK output, accents, real place names, the back-of-hand menu, every
 * label on the RADIO rack — assumes it works.
 *
 * Reading the bytecode of scenecore 1.0.0-beta01 says it does not:
 *
 *     Texture.create() expects a path relative to `assets/`, received absolute path
 *     ...
 *     new File(path.toString()).isAbsolute()   // -> require(!isAbsolute)
 *
 * `assets/` is baked into the APK at build time and is read-only at runtime, so
 * if that is the whole story then no string we compose at runtime can ever
 * become a texture, and §6.2 is not implementable on this version.
 *
 * That is a big enough claim to be worth testing rather than asserting. A
 * relative path might still resolve against somewhere writable; the require()
 * might be advisory; the message might be stale. So this writes a real PNG and
 * tries every addressing mode we have, on the device, and says what happened.
 *
 * Delete this file once the answer is recorded in the typography plan. A probe
 * that outlives its question becomes a feature nobody asked for.
 */
object TypeProbe {

    private const val TAG = "MeshmoreXR"

    suspend fun run(session: Session, context: Context) {
        Log.i(TAG, "[type] ---- tier R texture probe ----")

        // A run with Latin, CJK and an emoji: the three cases tier S cannot draw
        // and the whole reason tier R exists.
        val text = "中継局 ABC ⚡"
        val px = 96f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = px
            color = Color.WHITE
            isSubpixelText = true
        }
        val w = kotlin.math.ceil(paint.measureText(text)).toInt().coerceAtLeast(1)
        val fm = paint.fontMetrics
        val h = kotlin.math.ceil(fm.bottom - fm.top).toInt().coerceAtLeast(1)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        Canvas(bmp).apply {
            // TRANSPARENT GROUND. On an additive display this is what makes the
            // quad emit only ink and no rectangle (§6.3).
            drawColor(Color.TRANSPARENT)
            drawText(text, 0f, -fm.top, paint)
        }
        // Did Android's font fallback chain actually draw the kanji and the
        // emoji, or did it give us tofu? Count non-transparent pixels: a real
        // render is dense, tofu boxes are outlines, nothing is zero.
        var ink = 0
        val row = IntArray(w)
        for (y in 0 until h step 2) {
            bmp.getPixels(row, 0, w, 0, y, w, 1)
            for (p in row) if (p ushr 24 > 8) ink++
        }
        Log.i(TAG, "[type] rasterised '$text' ${w}x${h}px, ink=$ink samples")

        val png = File(context.cacheDir, "typeprobe.png")
        png.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        Log.i(TAG, "[type] wrote ${png.absolutePath} (${png.length()} bytes)")

        // Every addressing mode we have. Absolute is what §6.2 assumed; the
        // others are the ways a relative path could still reach a writable file.
        val attempts = listOf(
            "absolute cacheDir" to png.absolutePath,
            "relative to /" to png.absolutePath.removePrefix("/"),
            "bare filename" to png.name,
            "assets (known-good control)" to "typeprobe-control.png",
        )
        for ((label, p) in attempts) {
            val r = runCatching { Texture.create(session, java.nio.file.Paths.get(p)) }
            if (r.isSuccess) {
                Log.i(TAG, "[type] OK   $label -> ${r.getOrNull()}")
            } else {
                val e = r.exceptionOrNull()
                Log.w(TAG, "[type] FAIL $label -> ${e?.javaClass?.simpleName}: ${e?.message}")
            }
        }
        Log.i(TAG, "[type] ---- probe done ----")
    }
}
