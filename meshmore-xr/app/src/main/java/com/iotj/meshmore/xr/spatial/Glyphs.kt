// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

/**
 * HOLOGRAPHIC TEXT — glyphs as extruded strokes, not textured quads.
 *
 * A textured quad is a panel wearing a disguise: it has a rectangle, it has a
 * surface, and in passthrough you can see its edges. Stroke glyphs have none of
 * that. Each character is a set of line segments extruded into square-section
 * tubes by Prims.spur, so a callsign floating at a node is genuinely made of
 * light in the room rather than printed on something.
 *
 * It is also the only text that matches the rest of the symbology: same
 * primitive, same baked shading, same faceting. And it is the Wipeout/Tron
 * register -- vector type, drawn not set.
 *
 * The font is a 4x6 stroke grid, uppercase + digits + the few marks callsigns
 * actually use. Callsigns and units stay Latin in every locale
 * (MeshmoreXR-i18n-ja.md), so CJK is deliberately NOT in this path -- Japanese
 * UI text goes through a different surface, not through node labels.
 */
object Glyphs {

    /** Segments as (x0,y0,x1,y1) on a 0..4 x 0..6 grid. */
    private val FONT: Map<Char, FloatArray> = buildMap {
        put('A', floatArrayOf(0f,0f, 0f,4f,  0f,4f, 2f,6f,  2f,6f, 4f,4f,  4f,4f, 4f,0f,  0f,3f, 4f,3f))
        put('B', floatArrayOf(0f,0f, 0f,6f,  0f,6f, 3f,6f,  3f,6f, 4f,5f,  4f,5f, 3f,3f,  0f,3f, 3f,3f,  3f,3f, 4f,2f,  4f,2f, 3f,0f,  0f,0f, 3f,0f))
        put('C', floatArrayOf(4f,5f, 3f,6f,  3f,6f, 1f,6f,  1f,6f, 0f,5f,  0f,5f, 0f,1f,  0f,1f, 1f,0f,  1f,0f, 3f,0f,  3f,0f, 4f,1f))
        put('D', floatArrayOf(0f,0f, 0f,6f,  0f,6f, 3f,6f,  3f,6f, 4f,5f,  4f,5f, 4f,1f,  4f,1f, 3f,0f,  3f,0f, 0f,0f))
        put('E', floatArrayOf(4f,6f, 0f,6f,  0f,6f, 0f,0f,  0f,0f, 4f,0f,  0f,3f, 3f,3f))
        put('F', floatArrayOf(4f,6f, 0f,6f,  0f,6f, 0f,0f,  0f,3f, 3f,3f))
        put('G', floatArrayOf(4f,5f, 3f,6f,  3f,6f, 1f,6f,  1f,6f, 0f,5f,  0f,5f, 0f,1f,  0f,1f, 1f,0f,  1f,0f, 3f,0f,  3f,0f, 4f,1f,  4f,1f, 4f,3f,  4f,3f, 2f,3f))
        put('H', floatArrayOf(0f,0f, 0f,6f,  4f,0f, 4f,6f,  0f,3f, 4f,3f))
        put('I', floatArrayOf(2f,0f, 2f,6f,  1f,6f, 3f,6f,  1f,0f, 3f,0f))
        put('J', floatArrayOf(4f,6f, 4f,1f,  4f,1f, 3f,0f,  3f,0f, 1f,0f,  1f,0f, 0f,1f))
        put('K', floatArrayOf(0f,0f, 0f,6f,  0f,3f, 4f,6f,  0f,3f, 4f,0f))
        put('L', floatArrayOf(0f,6f, 0f,0f,  0f,0f, 4f,0f))
        put('M', floatArrayOf(0f,0f, 0f,6f,  0f,6f, 2f,3f,  2f,3f, 4f,6f,  4f,6f, 4f,0f))
        put('N', floatArrayOf(0f,0f, 0f,6f,  0f,6f, 4f,0f,  4f,0f, 4f,6f))
        put('O', floatArrayOf(0f,1f, 1f,0f,  1f,0f, 3f,0f,  3f,0f, 4f,1f,  4f,1f, 4f,5f,  4f,5f, 3f,6f,  3f,6f, 1f,6f,  1f,6f, 0f,5f,  0f,5f, 0f,1f))
        put('P', floatArrayOf(0f,0f, 0f,6f,  0f,6f, 3f,6f,  3f,6f, 4f,5f,  4f,5f, 4f,4f,  4f,4f, 3f,3f,  3f,3f, 0f,3f))
        put('Q', floatArrayOf(0f,1f, 1f,0f,  1f,0f, 3f,0f,  3f,0f, 4f,1f,  4f,1f, 4f,5f,  4f,5f, 3f,6f,  3f,6f, 1f,6f,  1f,6f, 0f,5f,  0f,5f, 0f,1f,  2f,2f, 4f,0f))
        put('R', floatArrayOf(0f,0f, 0f,6f,  0f,6f, 3f,6f,  3f,6f, 4f,5f,  4f,5f, 4f,4f,  4f,4f, 3f,3f,  3f,3f, 0f,3f,  2f,3f, 4f,0f))
        put('S', floatArrayOf(4f,5f, 3f,6f,  3f,6f, 1f,6f,  1f,6f, 0f,5f,  0f,5f, 1f,3f,  1f,3f, 3f,3f,  3f,3f, 4f,2f,  4f,2f, 3f,0f,  3f,0f, 1f,0f,  1f,0f, 0f,1f))
        put('T', floatArrayOf(0f,6f, 4f,6f,  2f,6f, 2f,0f))
        put('U', floatArrayOf(0f,6f, 0f,1f,  0f,1f, 1f,0f,  1f,0f, 3f,0f,  3f,0f, 4f,1f,  4f,1f, 4f,6f))
        put('V', floatArrayOf(0f,6f, 2f,0f,  2f,0f, 4f,6f))
        put('W', floatArrayOf(0f,6f, 1f,0f,  1f,0f, 2f,3f,  2f,3f, 3f,0f,  3f,0f, 4f,6f))
        put('X', floatArrayOf(0f,0f, 4f,6f,  0f,6f, 4f,0f))
        put('Y', floatArrayOf(0f,6f, 2f,3f,  4f,6f, 2f,3f,  2f,3f, 2f,0f))
        put('Z', floatArrayOf(0f,6f, 4f,6f,  4f,6f, 0f,0f,  0f,0f, 4f,0f))
        put('0', floatArrayOf(0f,1f, 1f,0f,  1f,0f, 3f,0f,  3f,0f, 4f,1f,  4f,1f, 4f,5f,  4f,5f, 3f,6f,  3f,6f, 1f,6f,  1f,6f, 0f,5f,  0f,5f, 0f,1f,  0f,1f, 4f,5f))
        put('1', floatArrayOf(1f,5f, 2f,6f,  2f,6f, 2f,0f,  1f,0f, 3f,0f))
        put('2', floatArrayOf(0f,5f, 1f,6f,  1f,6f, 3f,6f,  3f,6f, 4f,5f,  4f,5f, 0f,0f,  0f,0f, 4f,0f))
        put('3', floatArrayOf(0f,6f, 4f,6f,  4f,6f, 2f,3f,  2f,3f, 4f,2f,  4f,2f, 3f,0f,  3f,0f, 1f,0f,  1f,0f, 0f,1f))
        put('4', floatArrayOf(3f,0f, 3f,6f,  3f,6f, 0f,2f,  0f,2f, 4f,2f))
        put('5', floatArrayOf(4f,6f, 0f,6f,  0f,6f, 0f,3f,  0f,3f, 3f,3f,  3f,3f, 4f,2f,  4f,2f, 3f,0f,  3f,0f, 1f,0f,  1f,0f, 0f,1f))
        put('6', floatArrayOf(4f,5f, 3f,6f,  3f,6f, 1f,6f,  1f,6f, 0f,5f,  0f,5f, 0f,1f,  0f,1f, 1f,0f,  1f,0f, 3f,0f,  3f,0f, 4f,1f,  4f,1f, 4f,2f,  4f,2f, 3f,3f,  3f,3f, 0f,3f))
        put('7', floatArrayOf(0f,6f, 4f,6f,  4f,6f, 1f,0f))
        put('8', floatArrayOf(1f,3f, 0f,4f,  0f,4f, 0f,5f,  0f,5f, 1f,6f,  1f,6f, 3f,6f,  3f,6f, 4f,5f,  4f,5f, 4f,4f,  4f,4f, 3f,3f,  3f,3f, 1f,3f,  1f,3f, 0f,2f,  0f,2f, 0f,1f,  0f,1f, 1f,0f,  1f,0f, 3f,0f,  3f,0f, 4f,1f,  4f,1f, 4f,2f,  4f,2f, 3f,3f))
        put('9', floatArrayOf(0f,1f, 1f,0f,  1f,0f, 3f,0f,  3f,0f, 4f,1f,  4f,1f, 4f,5f,  4f,5f, 3f,6f,  3f,6f, 1f,6f,  1f,6f, 0f,5f,  0f,5f, 0f,4f,  0f,4f, 1f,3f,  1f,3f, 4f,3f))
        put('.', floatArrayOf(2f,0f, 2f,1f))
        put('-', floatArrayOf(1f,3f, 3f,3f))
        put('_', floatArrayOf(0f,0f, 4f,0f))
        put('/', floatArrayOf(0f,0f, 4f,6f))
        put(':', floatArrayOf(2f,1f, 2f,2f,  2f,4f, 2f,5f))
        put('?', floatArrayOf(0f,5f, 1f,6f,  1f,6f, 3f,6f,  3f,6f, 4f,5f,  4f,5f, 2f,3f,  2f,3f, 2f,2f,  2f,0f, 2f,1f))
        put('#', floatArrayOf(1f,0f, 1f,6f,  3f,0f, 3f,6f,  0f,2f, 4f,2f,  0f,4f, 4f,4f))
        put('*', floatArrayOf(2f,1f, 2f,5f,  0f,2f, 4f,4f,  0f,4f, 4f,2f))
    }

    private const val GW = 4f      // glyph cell width, in grid units
    private const val GH = 6f      // cap height
    private const val ADV = 5.6f   // advance, including the gap

    /** Width of [text] in world units at cap height [size]. */
    fun width(text: String, size: Float): Float =
        if (text.isEmpty()) 0f else (text.length * ADV - (ADV - GW)) * (size / GH)

    /**
     * Build [text] as extruded strokes, centred on the origin in X and sitting
     * on the baseline in Y. [size] is CAP HEIGHT in metres -- callers should
     * derive it from visual angle, never pick it in absolute units (L7).
     */
    fun text(text: String, size: Float, strokeR: Float = 0f): Prims.Facets {
        val f = Prims.Facets()
        val s = size / GH
        val r = if (strokeR > 0f) strokeR else size * 0.055f
        var pen = -width(text, size) / 2f
        for (ch in text.uppercase()) {
            val segs = FONT[ch]
            if (segs != null) {
                var i = 0
                while (i + 3 < segs.size) {
                    val x0 = pen + segs[i] * s
                    val y0 = segs[i + 1] * s
                    val x1 = pen + segs[i + 2] * s
                    val y1 = segs[i + 3] * s
                    f.addTranslated(Prims.spur(x0, y0, 0f, x1, y1, 0f, r), 0f, 0f, 0f)
                    i += 4
                }
            }
            pen += ADV * s
        }
        return f
    }
}
