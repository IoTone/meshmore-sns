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
     * Widest panel we will ask for. Comfortably under the 4096 px most GL
     * implementations guarantee, with room for the 2x oversample.
     */
    private const val MAX_PX = 2048

    /**
     * The runtime's metres-per-pixel, as measured on this device. Only ever a
     * seed for the create call — the real figure is read back afterwards,
     * because a constant that describes one runtime's default is exactly the
     * kind of thing that stops being true without saying so.
     */
    private const val NOMINAL_MPP = 3.9e-4f

    /**
     * DRAW EVERY PANEL'S OWN EDGE. Off by default; `--ez outline true`.
     *
     * A run that renders wrong is nearly impossible to diagnose from the run
     * itself: a panel that is too short, a panel seen edge-on, text laid out
     * against stale bounds and a panel occluded by the floor all produce the
     * same photograph — a sliver of glyph tops — and this file has now had all
     * four. Guessing between them cost several build-and-look cycles each time.
     *
     * The outline settles it in one look, because it separates the two things
     * that are otherwise conflated: WHERE THE SURFACE IS, and WHERE THE TEXT
     * LANDS INSIDE IT. If the rectangle is missing, the panel is not where you
     * think. If it is a sliver, the panel is edge-on. If it is right and the
     * text is not inside it, the layout is stale.
     */
    @JvmStatic
    var outline: Boolean = false

    /**
     * The debug background: the view's own edge, its padding box, and a ruler.
     *
     * Two rectangles alone could not settle it. They showed the text sitting low
     * and clipped, which is equally consistent with the TEXT being drawn wrong
     * and with the VIEW being mapped onto the quad wrong — and those have
     * opposite fixes. The tick marks are at known fractions of the view, so the
     * photograph reports the mapping directly instead of being reasoned about:
     * if the centre tick lands at the middle of the outline the mapping is
     * honest and the text is at fault, and if it does not, it is the mapping.
     */
    private class Ruler(
        private val pad: Int, private val tag: String,
    ) : android.graphics.drawable.Drawable() {
        private var drawn = 0
        private val p = android.graphics.Paint().apply {
            isAntiAlias = false
            style = android.graphics.Paint.Style.STROKE
        }

        override fun draw(canvas: android.graphics.Canvas) {
            val b = bounds
            // GROUND TRUTH, taken at the only moment that matters. Everything
            // else about this panel is measured before the runtime has had its
            // say; this runs inside the actual render into the surface.
            if (drawn < 24) {
                drawn++
                Log.i(TAG, "[type] DRAW bounds=" + b.width() + "x" + b.height() +
                    " canvas=" + canvas.width + "x" + canvas.height + " tag=" + tag)
            }
            val w = b.width().toFloat()
            val h = b.height().toFloat()
            val t = (h * 0.04f).coerceAtLeast(2f)
            p.strokeWidth = t
            // The view's edge.
            p.color = 0xFFFF3060.toInt()
            canvas.drawRect(t / 2, t / 2, w - t / 2, h - t / 2, p)
            // The padding box the text is composed into.
            p.color = 0xFF30A0FF.toInt()
            p.strokeWidth = t * 0.6f
            canvas.drawRect(
                pad.toFloat(), pad.toFloat(), w - pad, h - pad, p,
            )
            // Quarter, half, three-quarter — drawn as short stubs from the left
            // edge so they cannot be mistaken for the boxes. The half is longest.
            p.strokeWidth = t * 0.7f
            p.color = 0xFF40FF80.toInt()
            canvas.drawLine(0f, h * 0.5f, w * 0.25f, h * 0.5f, p)
            p.color = 0xFFFFD000.toInt()
            canvas.drawLine(0f, h * 0.25f, w * 0.12f, h * 0.25f, p)
            canvas.drawLine(0f, h * 0.75f, w * 0.12f, h * 0.75f, p)
        }

        override fun setAlpha(a: Int) {}
        override fun setColorFilter(f: android.graphics.ColorFilter?) {}
        @Deprecated("Drawable API", ReplaceWith("android.graphics.PixelFormat.TRANSLUCENT"))
        override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
    }

    /** Loaded once. createFromAsset parses the whole 1.5 MB file every call. */
    private var cached: Typeface? = null

    /**
     * M PLUS 1 Code, or the platform's monospace if the asset is somehow
     * missing. The fallback is deliberate but noisy: a silent substitution
     * changes the cell width the layout is budgeting against, and the drift
     * check below is what would notice — so say it once, loudly, here too.
     */
    private fun face(context: Context): Typeface {
        cached?.let { return it }
        val t = runCatching { Typeface.createFromAsset(context.assets, FONT_ASSET) }
            .onFailure { Log.e(TAG, "[type] $FONT_ASSET missing — falling back to platform monospace") }
            .getOrDefault(Typeface.MONOSPACE)
        cached = t
        return t
    }

    private const val FONT_ASSET = "fonts/MPLUS1Code-Regular.ttf"

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
        private val view: TextView? = null,
        private val wPx: Int = 0,
        private val hPx: Int = 0,
        private val mpp: Float = 1f,
        private val capPx: Float = 1f,
    ) {

        /**
         * Re-size in the world WITHOUT re-rasterising.
         *
         * The pixels are fixed for the life of the panel; only how large that
         * raster is drawn changes. Assigning `size` here instead is what broke
         * the dock caption — see the note at the panel construction.
         */
        fun setCapHeight(capHeightM: Float) {
            runCatching { entity.setScale((capHeightM / capPx) / mpp) }
        }

        /** World width this run occupies at [capHeightM]. */
        fun widthAt(capHeightM: Float): Float = wPx * capHeightM / capPx

        /** World height this run occupies at [capHeightM]. */
        fun heightAt(capHeightM: Float): Float = hPx * capHeightM / capPx
        /**
         * Change the words WITHOUT rebuilding the panel.
         *
         * The alternative — dispose and recreate per change — is what a live
         * readout did, several times a second, and it produced overlapping
         * panels showing different text at once: the old one still rendering
         * while the new one drew over it, which reads as a label cut through its
         * own middle. It also churned a PanelEntity (a real Android View and its
         * surface) per update, which is not a thing to do at frame rate on a
         * device that thermally throttles.
         *
         * Only valid for a panel built with [reusable], whose pixel size was
         * fixed up front so the text can change without the geometry moving.
         */
        fun setText(text: String): Boolean {
            val v = view
            if (outline) Log.i(TAG, "[type] setText('" + text + "') view=" +
                (if (v == null) "NULL" else "ok") + " had='" + (v?.text ?: "") + "'")
            if (v == null) return false
            if (v.text.toString() == text) return true
            v.text = text
            // AND LAY IT OUT AGAIN, BY HAND. This is the whole bug.
            //
            // TextView.setText calls checkForRelayout(), which calls
            // requestLayout() — and requestLayout on a view with NO PARENT is a
            // no-op. Nothing else was ever going to lay this view out, so its
            // internal Layout kept whatever geometry it had from the last pass
            // while the new string drew against it. The panel and the surface
            // were exactly the right size the entire time; the TEXT inside was
            // being composed against stale bounds, which is why it appeared
            // sliced through its own middle.
            //
            // A panel-hosted View is detached by construction. Every property
            // change that would normally trigger a layout has to be finished by
            // hand here.
            val ws = View.MeasureSpec.makeMeasureSpec(wPx, View.MeasureSpec.EXACTLY)
            val hs = View.MeasureSpec.makeMeasureSpec(hPx, View.MeasureSpec.EXACTLY)
            v.measure(ws, hs)
            v.layout(0, 0, wPx, hPx)
            v.invalidate()
            if (outline) {
                val lay = v.layout
                Log.i(TAG, "[type] laid '" + text + "' view=" + v.width + "x" + v.height +
                    " meas=" + v.measuredWidth + "x" + v.measuredHeight +
                    " pad=" + v.paddingTop + "/" + v.paddingBottom +
                    " layoutH=" + (lay?.height ?: -1) +
                    " lineTop=" + (lay?.getLineTop(0) ?: -1) +
                    " lineBottom=" + (lay?.getLineBottom(0) ?: -1) +
                    " base=" + v.baseline + " gravity=" + v.gravity)
            }
            return true
        }
    }

    /**
     * Build [text] as a run whose capitals stand [capHeightM] metres tall.
     *
     * [argb] is the ink colour. There is no background: the view is transparent
     * and stays that way.
     */
    /**
     * A run whose text can change later.
     *
     * [widest] is the longest string this panel will ever hold; the panel is
     * sized for it once and never resized. A readout that re-measures itself is
     * a readout that jitters, and on this SDK it is also a readout that rebuilds
     * a View every time a digit changes.
     */
    fun reusable(
        session: Session,
        context: Context,
        widest: String,
        capHeightM: Float,
        argb: Int,
        name: String = "run",
    ): Run? = create(session, context, widest, capHeightM, argb, name, reusable = true)

    fun create(
        session: Session,
        context: Context,
        text: String,
        capHeightM: Float,
        argb: Int,
        name: String = "run",
        reusable: Boolean = false,
    ): Run? = runCatching {
        val tv = TextView(context).apply {
            this.text = text
            setTextColor(argb)
            if (outline) {
                background = Ruler((RASTER_PX * 0.12f).toInt(), name)
            } else {
                setBackgroundColor(Color.TRANSPARENT)
            }
            // PIXELS, EXPLICITLY. The `textSize` property setter is SP, which
            // the platform scales by the user's font-size preference and the
            // display density — so the view drew larger than the panel we had
            // sized from RASTER_PX, and the difference showed up as text cut off
            // at the top, bottom and right edges. Everything downstream treats
            // RASTER_PX as pixels; this makes that true.
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, RASTER_PX)
            includeFontPadding = false
            // PADDING, and CENTRED inside it. Measuring a glyph box exactly and
            // sizing a panel to it leaves no room for the parts of a face that
            // legitimately exceed it — descenders, accents, the odd overhang —
            // and any rounding in either direction takes a slice off an edge.
            // The margin costs a few millimetres of transparent nothing.
            val pad = (RASTER_PX * 0.12f).toInt()
            setPadding(pad, pad, pad, pad)
            gravity = android.view.Gravity.CENTER
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

            // M PLUS 1 CODE — T4. The plan's body face (§3): "monospaced and
            // technical rather than humanist", chosen so tier R sits beside the
            // stroke font without argument.
            //
            // Two reasons, and they turn out to be one. AESTHETICALLY,
            // proportional sans made `Woofy Repeater` read as ordinary UI text
            // next to `W7MIR REPEATER` in vector caps and the ring drifted away
            // from its own register. MEASURABLY, a monospace advance is a
            // constant, so a run's width is cells x advance exactly -- which is
            // what lets a layout with no access to a font predict it.
            //
            // Shipped rather than borrowed. Typeface.MONOSPACE was the stand-in
            // and it is whatever the platform happens to mean by monospace: it
            // varies by Android version and by locale, and its CJK coverage is
            // nobody's promise. This file is 5,232 ideographs and 181 kana that
            // will still be there next release.
            typeface = face(context)
        }
        tv.measure(View.MeasureSpec.UNSPECIFIED, View.MeasureSpec.UNSPECIFIED)

        // WIDTH CEILING. A long run at 96 px rasterises very wide -- the hand
        // readout's 88-character template came to ~4200 px -- and past the
        // platform's surface limit the panel clamps, the TextView re-lays out
        // inside the smaller box, and a maxLines=1 string becomes a wrapped one
        // whose first line is all you see. That is what "only the top fifth of
        // the text" was: not clipping, WRAPPING, caused by asking for a panel
        // wider than the device would give.
        //
        // So the type shrinks to fit rather than the panel silently truncating.
        // A smaller readout you can read beats a large one you cannot.
        if (tv.measuredWidth > MAX_PX) {
            val shrink = MAX_PX.toFloat() / tv.measuredWidth
            // COMPLEX_UNIT_PX AGAIN. `tv.textSize = x` is the SP setter, which
            // the platform multiplies by display density — so the shrink path
            // made the text BIGGER on any device with density > 1, and a panel
            // asked to fit 2048 px came back at 3082. The very same mistake was
            // fixed a few lines above and this second instance was left behind,
            // which is the argument for the property never being used here at
            // all: one of them is right and they look identical.
            tv.setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, RASTER_PX * shrink)
            tv.measure(View.MeasureSpec.UNSPECIFIED, View.MeasureSpec.UNSPECIFIED)
            Log.i(TAG, "[type] '%s' shrunk to %.0f px to fit %d".format(
                text.take(24), RASTER_PX * shrink, MAX_PX))
        }
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
            // DIRECTIONAL. Only UNDER-reservation is a fault: the layout
            // cleared less arc than the run occupies, so the label is about to
            // print through its neighbour. Over-reservation wastes a little arc
            // and collides with nothing, which is exactly what modelling an
            // emoji as 3 cells does -- it is 2.5, and rounding down would trade
            // a harmless gap for a real overlap. Warning on both directions made
            // the check cry wolf about the safe one.
            if (measured > TypeTier.RUN_CELL_EM + CAL_TOLERANCE) {
                Log.w(TAG, "[type] CELL WIDTH UNDER-RESERVED: measured %.3f em/cell, " +
                    "budgeted %.3f — labels will overlap — '%s'"
                    .format(measured, TypeTier.RUN_CELL_EM, text))
            }
        }

        // SIZE IS PIXELS. THE WORLD SIZE IS A SCALE. This is the third and
        // last attempt at this, and the first one that is not a race between
        // two setters.
        //
        // `size` and `sizeInPixels` are not two independent properties. Each
        // one RECOMPUTES the other through the runtime's own metres-per-pixel,
        // so whichever is assigned last silently discards the other. Assigning
        // metres second — the previous fix — meant every panel was re-rasterised
        // at the runtime's default ~3.9e-4 m/px: the dock caption asked for
        // 886x141 px and was drawn at 350x55, measured from inside the draw
        // call. A TextView laid out for 141 px, told to render 96 px type into
        // 55, shows the top of the capitals and nothing else. That is the whole
        // of the "empty dock labels" bug, and it looked for three rounds like
        // clipped text because the visible sliver was the top of the caps
        // sitting near the BOTTOM of the panel.
        //
        // So: state the pixels, which is the thing that must be exact, and then
        // reach the size we want with SCALE. A scale is a transform on the
        // entity. It cannot re-enter the sizing arithmetic, cannot re-measure
        // the view, and cannot be undone by a later size assignment.
        val panel = PanelEntity.create(
            session, tv, FloatSize2d(wPx * NOMINAL_MPP, hPx * NOMINAL_MPP), name,
            Pose(Vector3(0f, 0f, 0f)),
        )
        panel.sizeInPixels = IntSize2d(wPx, hPx)
        // READ BACK what the runtime chose rather than trusting NOMINAL_MPP.
        // The nominal figure is what this device reported once; it is a seed for
        // the create call, not a fact to build on.
        val mpp = (panel.size.height / hPx).takeIf { it > 0f } ?: NOMINAL_MPP
        val k = (capHeightM / capPx) / mpp
        runCatching { panel.setScale(k) }
        Log.i(TAG, "[type] panel '" + text.take(14) + "' view=" + wPx + "x" + hPx +
            "px mpp=" + mpp + " scale=" + k + " cap=" + capPx + "px -> " +
            (wPx * capHeightM / capPx) + "x" + (hPx * capHeightM / capPx) + "m")
        panel.cornerRadius = 0f
        Run(
            panel, wPx * capHeightM / capPx, hPx * capHeightM / capPx,
            if (reusable) tv else null, wPx, hPx, mpp, capPx,
        )
    }.onFailure {
        Log.w(TAG, "[type] run '$text' failed: ${it.javaClass.simpleName}: ${it.message}")
    }.getOrNull()
}
