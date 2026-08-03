// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

/**
 * THE DOCK MARKS — what each pip is, without spelling it.
 *
 * The dock's pips were seven identical rings. Identity lived only in position,
 * which is a memory test, so on 2026-08-02 they were given permanent captions.
 * That fixed the guessing game and created a worse problem: at the brief's
 * legibility floor (§4.1, no text below 1.2° of visual angle) an eight-character
 * caption is 9.6° of arc against a 5.6° pip pitch. Permanent captions and legal
 * type are not simultaneously possible on a row this dense — one of the two has
 * to go, and it cannot be the legibility.
 *
 * A MARK resolves it, because the requirement was never that the pip carry a
 * WORD. It was that the pip carry IDENTITY at rest. A distinct silhouette does
 * that in 3° where a word needs 9.6°, and the caption is then free to appear on
 * focus only — where, being the only one visible, it can be the full word at
 * full legal size.
 *
 * SIZED FROM A MEASUREMENT, not a guess. §4.1's 1.2° is a rule about TEXT: you
 * have to resolve strokes to tell 8 from B. Telling seven distinct silhouettes
 * apart is an easier discrimination and the text floor does not transfer — but
 * icons need their own floor and this project has a datum for it. The ASL hand
 * diagrams on the help card are 3.25° and resolve finger separations on this
 * display, confirmed in capture. That is a far harder discrimination than these,
 * so 3.0° is conservative. See `MeshmoreXR-console-spec.md` §8.1.
 *
 * DRAWN AS LINES, not filled shapes. Authored as open paths in the same
 * 100-unit box as AslGlyphs and stroked rather than filled — a line drawing
 * survives being small in a way a solid does not, and on additive optics a
 * filled mark is a lump of emitted light where an outline is a diagram.
 */
object Marks {

    /** Every path is authored in the same 100-unit box as [AslGlyphs]. */
    private val PATHS: Map<String, String> = mapOf(

        // COMPASS — a four-point rose. Not a needle in a circle, which at 3°
        // is a circle. The long north spike is the whole read.
        "COMPASS" to "M50 6 L58 42 L94 50 L58 58 L50 94 L42 58 L6 50 L42 42 Z",

        // LINK — emission arcs off a point. The radio link, and deliberately
        // NOT the same idea as RADIO: this is the connection, that is the box.
        "LINK" to "M50 82 L50 76 M30 66 A28 28 0 0 1 70 66 M16 50 A48 48 0 0 1 84 50",

        // RADIO — an instrument face: chassis, two knobs, a readout. The rack
        // in miniature, so the pip and the surface it opens agree.
        "RADIO" to "M10 28 H90 V72 H10 Z M26 50 m-9 0 a9 9 0 1 0 18 0 a9 9 0 1 0 -18 0 " +
            "M52 42 H80 M52 58 H80",

        // HELP — a question mark. There is no cleverer answer and a cleverer
        // answer would be worse.
        "HELP" to "M33 34 A17 17 0 1 1 50 54 L50 64 M50 80 L50 84",

        // HERE — a crosshair on your own position. Reads as a fix, which is
        // what it is; a map pin would claim a map we are not showing.
        // The circle was authored centred on (50,24) while its ticks were
        // placed around (50,50), so it drew as a ring with three dashes
        // scattered below and beside it rather than as a crosshair. Bounds
        // fitting made it worse, not better: the shape was still wrong, it was
        // just wrong at a consistent size.
        "HERE" to "M50 50 m-20 0 a20 20 0 1 0 40 0 a20 20 0 1 0 -40 0 " +
            "M50 6 V22 M50 78 V94 M6 50 H22 M78 50 H94",

        // WIDE — corner brackets opening outward. Magnification as a framing
        // gesture rather than a lens, which at this size is an ellipse.
        "WIDE" to "M34 10 H10 V34 M66 10 H90 V34 M90 66 V90 H66 M34 90 H10 V66 " +
            "M40 50 H60 M50 40 V60",

        // NORTH — a compass needle, and deliberately NOT another rose.
        //
        // COMPASS (the band toggle) is already a four-point star, and two
        // compass-shaped marks a few degrees apart would be a coin toss. A
        // needle is the instrument you point, which is what this pip does: you
        // face north and tell the ring so.
        "NORTH" to "M50 6 L64 50 L50 94 L36 50 Z M50 6 L50 94 M30 50 H70",

        // HANDS — four fingers, a thumb and a palm.
        //
        // First attempt borrowed the Gallaudet 'B' the help card already draws,
        // on the reasoning that reusing verified artwork beats authoring a
        // seventh shape. On the glasses it was plainly the weakest of the seven:
        // those are FILLED contours carrying finger-separation detail, which is
        // exactly right at the help card's 3.25° where telling one letter from
        // another is the task, and is noise at 3.0° where the task is only
        // telling a hand from a question mark. Same artwork, different job.
        "HANDS" to "M36 58 V26 M48 58 V20 M60 58 V24 M70 58 V34 M28 58 L18 44 " +
            "M28 58 H72 V78 A12 12 0 0 1 60 90 H40 A12 12 0 0 1 28 78 Z",
    )

    /**
     * The contour for [name], or null if the dock grows a pip nobody drew — in
     * which case the caller falls back to a ring rather than failing to build.
     */
    operator fun get(name: String): String? = PATHS[name]?.takeIf { it.isNotEmpty() }

    fun has(name: String): Boolean = get(name) != null
}
