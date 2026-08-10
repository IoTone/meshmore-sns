// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

/**
 * HOW A SURFACE ARRIVES — the transition grammar, as arithmetic.
 *
 * `MeshmoreXR-theme-expression.md` §1. The gap it closes was a gap in the
 * BRIEF, not in the build: §7 never specified how a menu enters or leaves, so
 * every theme's console fanned identically and the crown dropped in
 * identically. A theme that restyles the content and leaves the behaviour of
 * every menu untouched reads as a palette no matter how many palettes it has.
 *
 * PURE, AND AT FILE SCOPE, so it is testable without a Session — the lesson
 * this codebase has now learned three times. Nothing here draws; it answers
 * "where is element N of this surface, this many milliseconds in", and the
 * surfaces apply it.
 *
 * ## What it is allowed to animate, and why that list is short
 *
 * POSE and SCALE, and nothing else.
 *
 * Not alpha on the entity: `MeshEntity.setAlpha` is a no-op on this material
 * path. Not colour on the material either, even though [Ink] proved that one
 * works — [Ink.retint] owns every registered material, and a per-frame writer
 * on the same one is the two-writers bug this codebase keeps meeting. A
 * transition that fought the theme system would be a strange thing to build
 * INTO the theme system.
 *
 * So a fade is expressed as a rise in scale, which is the same trade the Cuff
 * and the Reel already make, and which survives being seen at the edge of
 * vision better than a brightness change does.
 *
 * ## The two rules from the spec, enforced here rather than trusted
 *
 * **Nothing exceeds [CEILING_MS].** Above that a menu stops feeling like a
 * response to your hand. This is the one place the aesthetic loses, and
 * `RevealTest` asserts it for all nine themes so a future flourish cannot
 * quietly break it.
 *
 * **Every transition has a designed reduce-motion form.** Not an instant cut —
 * [reduced] keeps each theme's ORDER and stagger while removing travel, so a
 * wearer who cannot take movement still sees DR POP arrive all at once and
 * TERMINAL VOID arrive line by line. Those carry different information about
 * how sudden the change was, and both survive being frozen.
 */
object Reveal {

    /**
     * Where one element is, right now.
     *
     * [along] is the offset toward the wearer's right, [depth] toward them, in
     * metres; both are zero when settled. [scale] multiplies the element's own
     * size. [on] is false while an element is waiting for its turn in a
     * staggered reveal — it has not arrived yet, and drawing it at scale zero
     * is not the same thing as not drawing it.
     */
    class Frame(val on: Boolean, val along: Float, val depth: Float, val scale: Float) {
        companion object {
            /** Settled: exactly where the surface's own layout put it. */
            val SETTLED = Frame(true, 0f, 0f, 1f)
            val WAITING = Frame(false, 0f, 0f, 1f)
        }
    }

    /**
     * One theme's grammar. Distances are metres AT ONE METRE, the distance
     * every column in this app is placed at.
     */
    class Grammar(
        val durationMs: Int,
        /** Delay per element. Zero means the whole surface arrives at once. */
        val staggerMs: Int,
        /** How far in from the side it travels. Negative comes from the left. */
        val slide: Float = 0f,
        /** How far out from the wearer it starts. */
        val push: Float = 0f,
        /** Scale at t=0. 1.0 means it arrives at full size — a slam. */
        val from: Float = 1f,
        /** Overshoot past 1.0 before settling, as a fraction. */
        val spring: Float = 0f,
        /** Bottom-up rather than top-down. */
        val reverse: Boolean = false,
    )

    /**
     * Nobody may exceed this, INCLUDING STAGGER across a six-row surface.
     *
     * The "including stagger" is not pedantry, it is where the first version of
     * this file went wrong. The published spec gave each theme a duration and a
     * stagger — VECTORLINE 320/20, BIOLUME 380/40, TERMINAL VOID 240/34 — and
     * every one of those durations is comfortably under 400. On the six-row
     * bays the app actually draws they total 420, 580 and 410: the LAST row of
     * BIOLUME landed more than half a second after the surface opened, which is
     * well past the point where a menu stops feeling like an answer.
     *
     * A per-element budget is not a budget. RevealTest measures the whole
     * surface, which is what a wearer experiences.
     */
    const val CEILING_MS = 400

    /**
     * SEELE MONOLITH's zero is the identity and must not be "fixed" later.
     *
     * A monolith does not animate. It is also the only theme that hands a
     * motion-sensitive wearer a first-class option rather than a degraded one,
     * which is worth more than any flourish it gives up.
     */
    private val INSTANT = Grammar(durationMs = 0, staggerMs = 0)

    fun grammarFor(skin: Theme.Skin): Grammar = when (skin.key) {
        // Fade-up in place, all at once. Expressed as a small scale rise, since
        // brightness is not ours to animate.
        "halo" -> Grammar(durationMs = 180, staggerMs = 0, from = 0.94f)
        // Hard wipe left to right, top-down. The bracket that snaps shut after
        // the content lands is the menu treatment's job, not this one's.
        "nerv" -> Grammar(durationMs = 220, staggerMs = 30, slide = -0.09f)
        // In from the direction of travel, with overshoot and settle.
        "aghud" -> Grammar(durationMs = 260, staggerMs = 25, slide = 0.11f, spring = 0.06f)
        "seele" -> INSTANT
        // Slam-cut at full scale. from = 1.0 on purpose: DR POP does not grow
        // into place, it is suddenly there, and simultaneity is the point.
        "drpop" -> Grammar(durationMs = 90, staggerMs = 0, from = 1f)
        // A beam drawing one line at a time, top to bottom.
        "recon" -> Grammar(durationMs = 200, staggerMs = 22, from = 0.99f)
        // Strokes draw themselves: vertices first, so each element starts small
        // and grows along its own edges.
        "vector" -> Grammar(durationMs = 290, staggerMs = 20, from = 0.55f)
        // Grows from a point with a soft overshoot, and from the bottom, the
        // way something rooted does.
        // Slower per element than anything else and still inside the budget:
        // BIOLUME buys its unhurried feel from the CURVE and the overshoot
        // rather than from wall time, because wall time is shared with five
        // other rows and it does not get to spend all of it.
        "biolume" -> Grammar(
            durationMs = 270, staggerMs = 22, from = 0.05f, spring = 0.10f, reverse = true,
        )
        // Types itself. A row is a line of the terminal and arrives whole; the
        // per-character grain lives in the row's own text, not in its pose.
        "void" -> Grammar(durationMs = 230, staggerMs = 30, push = 0.02f)
        else -> Grammar(durationMs = 180, staggerMs = 0, from = 0.94f)
    }

    /**
     * Reduce-motion, per the spec's first supporting rule.
     *
     * Keeps the ORDER — the stagger, which is information about how sudden the
     * change was — and removes the TRAVEL, which is the part that makes people
     * ill. An instant cut would have thrown away the first along with the
     * second, and then all nine themes would arrive identically again, which is
     * the exact problem this file exists to solve.
     */
    var reduced: Boolean = false

    /**
     * Where element [index] of a surface is, [elapsedMs] after it opened.
     *
     * Past the end of its own transition an element is [Frame.SETTLED], which
     * is what makes this safe to call every frame forever: a surface that has
     * been open for a minute costs the same arithmetic and lands in exactly the
     * place its layout asked for.
     */
    fun at(skin: Theme.Skin, index: Int, count: Int, elapsedMs: Long): Frame {
        val g = grammarFor(skin)
        if (g.durationMs == 0 && g.staggerMs == 0) return Frame.SETTLED

        val slot = if (g.reverse) (count - 1 - index).coerceAtLeast(0) else index
        val begin = slot.toLong() * g.staggerMs
        if (elapsedMs < begin) return Frame.WAITING
        val dur = g.durationMs.coerceAtLeast(1)
        val t = ((elapsedMs - begin).toFloat() / dur).coerceIn(0f, 1f)
        if (t >= 1f) return Frame.SETTLED

        // Ease-out cubic. Fast at the start and settling at the end is what
        // makes a surface feel like it is answering rather than winding up.
        val e = 1f - (1f - t) * (1f - t) * (1f - t)
        // Overshoot, folded in over the last third so the spring is a settle
        // rather than a bounce that reads as a bug.
        val over = if (g.spring > 0f) g.spring * kotlin.math.sin(t * Math.PI.toFloat()) else 0f

        if (reduced) {
            // Order kept, travel removed. Scale still resolves, so an element
            // is never drawn at zero and never jumps.
            return Frame(true, 0f, 0f, 1f)
        }
        return Frame(
            on = true,
            along = g.slide * (1f - e),
            depth = g.push * (1f - e),
            scale = (g.from + (1f - g.from) * e + over).coerceAtLeast(0.02f),
        )
    }

    /** How long the whole surface takes, stagger included. For the ceiling test. */
    fun totalMs(skin: Theme.Skin, count: Int): Int {
        val g = grammarFor(skin)
        return g.durationMs + g.staggerMs * (count - 1).coerceAtLeast(0)
    }
}
