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
     * How far a run's measured cell width may drift from the constant the layout
     * uses before it is worth saying so. 4% of a cell; an 18-cell label would be
     * out by most of a character before this fires.
     */
    private const val CAL_TOLERANCE = 0.035f

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

            // T3 (§7) — THE THREE PROHIBITIONS, asserted here rather than
            // trusted. None of them is currently violated; all three are one
            // careless line away, and every one of them looks correct at the
            // call site because it IS correct on the Latin string you would
            // test with. Written as guards so a future edit trips over them.
            //
            // Tracking is a Latin device: CJK is set on an em grid and the grid
            // is the rhythm, so spacing ideographs apart does not open the line
            // up, it breaks what made it readable.
            letterSpacing = if (TypeRules.mayTrack(text)) letterSpacing else 0f
            // Synthetic bold smears and synthetic italic shears. Tolerable on a
            // Latin letter of few strokes; fatal to a kanji, whose legibility at
            // this size depends on its strokes staying apart.
            if (!TypeRules.maySynthesiseWeight(text)) {
                setTypeface(typeface, android.graphics.Typeface.NORMAL)
            }
            // And nothing here uppercases. On a mixed run that would shout the
            // Latin half and leave the kana alone -- two registers in one line,
            // which reads as a rendering fault rather than as emphasis. Tier S
            // uppercases because its font has no lowercase; tier R has one.
            isAllCaps = false

            // MONOSPACE, for two reasons that happen to be the same reason.
            //
            // AESTHETIC: the plan's body face is M PLUS 1 Code -- "monospaced
            // and technical rather than humanist" (§3) -- chosen so tier R sits
            // beside the stroke font without argument. Proportional sans did
            // not: on the live ring `Woofy Repeater` read as ordinary UI text
            // next to `W7MIR REPEATER` in vector caps, and the horizon started
            // drifting away from its own register. MONOSPACE is the platform
            // stand-in until the real face ships.
            //
            // MEASURABLE: a monospace advance is a constant, so a run's width
            // is cells x advance EXACTLY. The proportional face made the layout
            // estimate conservative by about 2x -- safe, but it spent budget
            // that could have labelled more nodes. Now the estimate can be
            // right instead of merely cautious.
            typeface = Typeface.MONOSPACE
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

        // SELF-CHECK, not a running commentary. The layout predicts this run's
        // width without a device (MeshNodes is pure), from a constant measured
        // once. If the platform ever hands us a different face -- a locale with
        // its own monospace, a future Android -- that constant silently stops
        // describing reality and the ring starts overlapping again with nothing
        // to say why. So: measure every run, log only when it disagrees.
        // Silence here means the constant is still true.
        val cells = TypeTier.displayCells(text)
        if (cells > 0) {
            val measured = (wPx / capPx) / cells
            if (kotlin.math.abs(measured - TypeTier.RUN_CELL_EM) > CAL_TOLERANCE) {
                Log.w(TAG, "[type] CELL WIDTH DRIFT: measured %.3f em/cell, expected %.3f — '%s'"
                    .format(measured, TypeTier.RUN_CELL_EM, text))
            }
        }

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
