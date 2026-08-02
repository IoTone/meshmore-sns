// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Matrix
import android.util.Log
import android.view.View
import androidx.core.graphics.PathParser
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.FloatSize2d
import androidx.xr.runtime.math.IntSize2d
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.PanelEntity

/**
 * AN ASL HAND SHAPE, AS A DIAGRAM IN THE ROOM.
 *
 * "Fist, thumb alongside" is a bad teacher. It is the description I put on the
 * help card because a stroke font cannot draw a hand, and the gesture then
 * failed three times in testing partly because nobody could see what the target
 * shape was. A picture of the letter is the difference between a discoverable
 * command and a secret one.
 *
 * DRAWN, NOT PHOTOGRAPHED, and that matters on this display. A photograph is a
 * rectangle of lit pixels; on additive optics it hangs in the room as a glowing
 * card. A contour drawing is ink and nothing else — the ground stays fully
 * transparent, so the shape reads as a diagram floating in the air rather than
 * as a screen someone left open.
 *
 * It also takes the theme's colour by construction. There is no palette baked
 * into the artwork to fight, because the fill was discarded (see AslGlyphs) and
 * every stroke here is painted in whatever ink the surface is using.
 */
object AslIcon {

    private const val TAG = "MeshmoreXR"

    /**
     * Rasterisation size. These are contour drawings with fine finger
     * separations; below about 200 px the strokes start merging and a fist
     * stops being distinguishable from a flat hand, which is the whole
     * distinction the diagram exists to make.
     */
    private const val PX = 256

    /** A view that draws one contour, and nothing else. */
    private class Glyph(
        context: Context, pathData: String?, ink: Int,
        private val mirror: Boolean, stroked: Boolean,
    ) : View(context) {
        private val path: Path? = pathData?.let {
            runCatching { PathParser.createPathFromPathData(it) }
                .onFailure { e -> Log.w(TAG, "[mark] unparseable: ${e.message}") }
                .getOrNull()
        }
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            // STROKED OR FILLED, because the two artwork sources differ in kind.
            // The Gallaudet letters are closed contours and want a fill; the
            // dock marks are line drawings authored as open paths and want a
            // stroke. Forcing either into the other's mode produces a blot.
            style = if (stroked) Paint.Style.STROKE else Paint.Style.FILL
            strokeWidth = STROKE_UNITS
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            color = ink
        }

        init { setBackgroundColor(Color.TRANSPARENT) }

        override fun onDraw(canvas: Canvas) {
            val p = path ?: return
            // The path is authored in a 100-unit box; scale it to whatever the
            // panel is, with a margin so the outermost stroke is not clipped by
            // the panel edge — the same lesson as the readout, learned once.
            val s = (width.coerceAtMost(height) * 0.88f) / AslGlyphs.BOX
            // The stroke is authored in box units, so it has to scale with the
            // path or a small mark comes out hairline and a large one blocky.
            fill.strokeWidth = STROKE_UNITS * s
            val m = Matrix().apply {
                setScale(s, s)
                postTranslate(
                    (width - AslGlyphs.BOX * s) / 2f,
                    (height - AslGlyphs.BOX * s) / 2f,
                )
            }
            // MIRRORED FOR THE LEFT HAND. The Gallaudet chart draws every
            // letter with the right hand, so a left-hand row showed the wrong
            // hand entirely — and for a shape whose whole meaning is which
            // fingers are where, that is not a cosmetic difference. A hand is
            // chiral: its mirror image is the other hand, which is exactly the
            // transform wanted here and the reason this is a flip about the
            // vertical axis rather than a rotation.
            if (mirror) m.postScale(-1f, 1f, width / 2f, height / 2f)
            val out = Path(p).apply { transform(m) }
            canvas.drawPath(out, fill)
        }
    }

    /**
     * Build [letter] as a panel [sizeM] metres square, inked in [argb].
     * Returns null when the letter has no artwork — the caller falls back to
     * the written description, which is worse but is not nothing.
     */
    fun create(
        session: Session, context: Context, letter: Char, sizeM: Float, argb: Int,
        mirror: Boolean = false,
    ): PanelEntity? {
        if (!AslGlyphs.has(letter)) return null
        return fromPath(session, context, AslGlyphs[letter], sizeM, argb, mirror,
            stroked = false, name = "asl-$letter")
    }

    /**
     * Build any contour as a panel [sizeM] metres square, inked in [argb].
     *
     * Split out from [create] so the dock marks can use the same pipeline: the
     * panel sizing rule, the margin, the mirror and the theme ink are all
     * things you only want to get right once.
     */
    fun fromPath(
        session: Session, context: Context, pathData: String?, sizeM: Float,
        argb: Int, mirror: Boolean = false, stroked: Boolean = false,
        name: String = "mark",
    ): PanelEntity? {
        pathData ?: return null
        return runCatching {
            val v = Glyph(context, pathData, argb, mirror, stroked)
            v.measure(
                View.MeasureSpec.makeMeasureSpec(PX, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(PX, View.MeasureSpec.EXACTLY),
            )
            v.layout(0, 0, PX, PX)
            PanelEntity.create(
                session, v, FloatSize2d(sizeM, sizeM), name,
                Pose(Vector3(0f, 0f, 0f)),
            ).also {
                // PIXELS, THEN SCALE — the same rule TextRun had to learn.
                // `size` and `sizeInPixels` recompute each other through the
                // runtime's metres-per-pixel, so assigning pixels here silently
                // replaced the sizeM asked for with PX x the runtime default,
                // and every hand diagram came out about a fifth too large.
                it.sizeInPixels = IntSize2d(PX, PX)
                val mpp = (it.size.height / PX).takeIf { m -> m > 0f }
                if (mpp != null) runCatching { it.setScale(sizeM / (PX * mpp)) }
                it.cornerRadius = 0f
            }
        }.onFailure { Log.w(TAG, "[mark] panel '$name' failed: ${it.message}") }
            .getOrNull()
    }

    /** Stroke weight, in the 100-unit authoring box. Bold enough to read at 3°. */
    private const val STROKE_UNITS = 7f
}
