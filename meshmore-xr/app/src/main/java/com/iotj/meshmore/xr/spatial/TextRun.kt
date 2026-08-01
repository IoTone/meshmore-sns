// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.graphics.Typeface
import android.util.Log
import android.view.View
import android.widget.TextView
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.FloatSize2d
import androidx.xr.runtime.math.IntSize2d
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.PanelEntity
import androidx.xr.scenecore.Space

/**
 * TIER R — one run of real type, as ink in the room.
 *
 * MeshmoreXR-typography.md §6.2, as revised on 2026-07-31. The plan's original
 * mechanism (rasterise to a PNG, upload with Texture.create) is not implementable
 * on scenecore 1.0.0-beta01: Texture.create resolves against the AssetManager, so
 * a string composed at runtime can never become a sampled texture. Measured, not
 * assumed -- see the probe output in the plan.
 *
 * What DOES work is a PanelEntity carrying a plain TextView. It lives in the same
 * entity graph as everything else, so it poses, billboards, alphas and disposes
 * exactly like a mote or a stroke label; and Android's font fallback chain draws
 * kanji, kana, accents and emoji for free, without shipping a face for any of
 * them.
 *
 * WHY THIS IS NOT A PANEL, since it will be challenged and should be:
 *
 *   - The ground is fully transparent. On an additive display that emits
 *     literally nothing -- photograph it and there is no rectangle.
 *   - cornerRadius is forced to 0. A rounded corner is the single most panel-ish
 *     thing a surface can have, and the default is not zero.
 *   - It is depth-placed and billboarded, anchored to a thing in the room rather
 *     than to the viewport.
 *   - It carries ONE RUN. Not a document, not a list, nothing scrolls.
 *
 * Those are the four properties §6.3 bans, absent. The mechanism is a panel API;
 * the result is not a panel, and the distinction is about what renders.
 *
 * ANGULAR SIZING, as everywhere else. The caller passes a CAP HEIGHT IN METRES
 * derived from the run's own range, so a distant node's label subtends the same
 * angle as a near one. Getting there needs the cap height in PIXELS, which is
 * measured off the actual glyphs rather than guessed from a ratio -- font metrics
 * differ per face and the fallback chain means we do not always know which face
 * drew it.
 */
object TextRun {

    private const val TAG = "MeshmoreXR"

    /**
     * Rasterisation size. The plan's floor is 48 px em; above that, hinting
     * artefacts stop dominating. 96 buys headroom for the 2x oversample the plan
     * asks for without making a long place name enormous in memory.
     */
    private const val RASTER_PX = 96f

    /**
     * A run's panel plus what the caller needs to place it.
     *
     * [widthM] and [heightM] are the rendered size in metres, which the caller
     * cannot compute in advance: it depends on the text, the face the fallback
     * chain picked, and the script.
     */
    class Run(
        val entity: PanelEntity,
        val widthM: Float,
        val heightM: Float,
    )

    /**
     * Build [text] as a run whose capitals stand [capHeightM] metres tall.
     *
     * [argb] is the ink colour. There is no background: the view is transparent
     * and stays that way.
     */
    fun create(
        session: Session,
        context: Context,
        text: String,
        capHeightM: Float,
        argb: Int,
        name: String = "run",
    ): Run? = runCatching {
        val tv = TextView(context).apply {
            this.text = text
            setTextColor(argb)
            setBackgroundColor(Color.TRANSPARENT)
            textSize = RASTER_PX
            includeFontPadding = false
            setPadding(0, 0, 0, 0)
            maxLines = 1
            // Sans rather than the stroke font's register on purpose: this tier
            // exists precisely for strings the stroke font cannot draw, and the
            // face that draws them is whatever the platform's fallback chain
            // selects. Naming a family it may not have would only mislead.
            typeface = Typeface.SANS_SERIF
        }
        tv.measure(View.MeasureSpec.UNSPECIFIED, View.MeasureSpec.UNSPECIFIED)
        val wPx = tv.measuredWidth
        val hPx = tv.measuredHeight
        if (wPx <= 0 || hPx <= 0) {
            Log.w(TAG, "[type] run '$text' measured ${wPx}x$hPx — skipped")
            return@runCatching null
        }
        tv.layout(0, 0, wPx, hPx)

        // CAP HEIGHT FROM THE GLYPHS, not from a ratio. Faces disagree (Saira
        // 0.688 em, M PLUS 0.730) and the fallback chain means we do not
        // reliably know which face drew this run, so measure an actual capital.
        // Falling back to the nominal 0.72 em keeps a script with no Latin
        // capitals -- a name that is entirely kanji -- from scaling to nothing.
        val bounds = Rect()
        tv.paint.getTextBounds("H", 0, 1, bounds)
        val capPx = if (bounds.height() > 0) bounds.height().toFloat() else RASTER_PX * 0.72f
        val scale = capHeightM / capPx

        val panel = PanelEntity.create(
            session, tv, IntSize2d(wPx, hPx), name,
            Pose(Vector3(0f, 0f, 0f)),
        )
        // Order matters: setSizeInPixels comes from create(), and setSize then
        // fixes the WORLD size. Setting only pixels leaves the panel at whatever
        // metres-per-pixel default the runtime chose.
        panel.size = FloatSize2d(wPx * scale, hPx * scale)
        // A rounded corner is the most panel-ish property a surface has, and the
        // default is not zero. There is no visible ground to round, but there is
        // no reason to leave the geometry claiming otherwise either.
        panel.cornerRadius = 0f
        Run(panel, wPx * scale, hPx * scale)
    }.onFailure {
        Log.w(TAG, "[type] run '$text' failed: ${it.javaClass.simpleName}: ${it.message}")
    }.getOrNull()
}
