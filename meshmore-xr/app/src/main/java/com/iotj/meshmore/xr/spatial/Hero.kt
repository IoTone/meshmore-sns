// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.util.Log
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Quaternion
import androidx.xr.runtime.math.Vector3
import androidx.xr.runtime.math.Vector4
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.KhronosUnlitMaterial
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space

/**
 * THE BOOT HERO — how a theme introduces itself.
 *
 * The wordmark used to be one object in all nine themes: `Glyphs.text` extruded
 * into strokes, the same vector font the callsigns use. The verdict was that it
 * "looks like it was made out of sticks", and the deeper waste is that boot is
 * fifteen to thirty seconds of a wearer with nothing else to look at. That is
 * the only uninterrupted attention this app ever gets, and every theme was
 * spending it on the same object.
 *
 * THREE RULES, each one a bill this project has already paid:
 *
 *  1. BORN FINISHED. Everything a hero shows is created in [build], complete
 *     and visible. The frame loop does not start until the whole scene has been
 *     built — fifteen to twenty seconds on this hardware — so a hero that fades
 *     itself in from nothing shows the wearer nothing for most of the surface's
 *     life. [tick] adds motion to something already standing; it must never be
 *     what makes it appear.
 *  2. POSE AND REPAINT ONLY. Meshes are free to move and materials are mutable,
 *     but a panel rewritten per frame rasterises an Android view every time —
 *     the habit that had the inbox writing itself fifteen times a second. A
 *     panel here is born holding its final text and is never written again.
 *  3. IT MUST SAY WHAT IT BUILT. The emulator's one display is FLAG_SECURE, so
 *     there is no spatial screenshot to check. A hero reports its geometry and
 *     cost to logcat or it cannot be reviewed at all.
 */
interface Hero {

    /** Create everything, complete and visible, parented to [root] at [at]. */
    suspend fun build(root: Entity, at: Vector3)

    /** [t] is seconds since the boot surface appeared. Pose and repaint only. */
    fun tick(t: Float)

    /**
     * How far this hero's ink reaches BELOW its anchor, in metres.
     *
     * The boot surface stacks a build stamp under the wordmark, and that
     * layout was written when every wordmark was stroke glyphs sitting ON the
     * baseline — nothing extended downward at all. A panel of real type is
     * centred instead, and reaches half its height below; VECTORLINE adds a
     * ground plane below that. The first real-type hero therefore printed the
     * version straight through the letterforms.
     *
     * So a hero declares its own extent and the stamp is placed under whatever
     * that turns out to be, rather than under a constant that was only ever
     * true for one kind of wordmark.
     */
    val dropM: Float get() = 0f

    /**
     * How far this hero's ink reaches ABOVE its anchor, in metres.
     *
     * The mark — the app icon, drawn as geometry — turns above the wordmark at
     * a height chosen for a one-cap stroke line. A hero that wants bigger type
     * has to be able to say so, or it grows straight into it. Zero means
     * "whatever the boot surface already does".
     */
    val riseM: Float get() = 0f

    fun clear()
}

/**
 * Which hero a theme gets.
 *
 * DEFAULTING TO THE OLD WORDMARK IS DELIBERATE. The heroes arrive one at a
 * time, and a theme without one must look exactly as it did rather than
 * degrading to nothing — so [PlainWordmark] is the same mesh, material, pose
 * and motion the boot surface has always built.
 */
object Heroes {

    suspend fun forTheme(
        session: Session,
        context: android.content.Context,
        skin: Theme.Skin,
        root: Entity,
        at: Vector3,
        cap: Float,
    ): Hero {
        val hero: Hero = when (skin.key) {
            "vector" -> VectorlineHero(session, context, skin.palette, cap)
            "void" -> VoidHero(session, context, skin.palette, cap)
            "biolume" -> BiolumeHero(session, context, skin.palette, cap)
            "recon" -> ReconHero(session, context, skin.palette, cap)
            "aghud" -> AgHero(session, context, skin.palette, cap)
            "nerv" -> NervHero(session, context, skin.palette, cap)
            "halo" -> HaloHero(session, context, skin.palette, cap)
            "seele" -> SeeleHero(session, context, skin.palette, cap)
            "drpop" -> DrPopHero(session, context, skin.palette, cap)
            else -> PlainWordmark(session, skin.palette, cap)
        }
        hero.build(root, at)
        return hero
    }

    const val WORD = "MESHMORE XR"
    const val TAG = "MeshmoreXR"
}

/** The wordmark as it has always been: one extruded stroke mesh, swinging. */
private class PlainWordmark(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val cap: Float,
) : Hero {

    private var entity: MeshEntity? = null
    private var at = Vector3(0f, 0f, 0f)

    override suspend fun build(root: Entity, at: Vector3) {
        this.at = at
        val mesh = Prims.build(session, Glyphs.text(Heroes.WORD, cap))
        entity = MeshEntity.create(
            session, mesh, listOf(Prims.material(session, theme.accent, 0.9f)),
        ).also {
            it.parent = root
            it.setPose(Pose(at), Space.ACTIVITY)
        }
        Log.i(Heroes.TAG, "[hero] plain wordmark, 1 stroke mesh")
    }

    /**
     * The swing and the breath, moved here verbatim when the wordmark stopped
     * being the boot surface's own property. Unchanged on purpose: eight themes
     * still see this, and a refactor is not the place to restyle them.
     */
    override fun tick(t: Float) {
        // Slow turn, but an OSCILLATION rather than a full revolution. Stroke
        // glyphs are flat, so a wordmark spinning through 360 degrees goes
        // edge-on twice per turn and collapses to a bright line -- at 18 deg/s
        // that is an unreadable moment every ten seconds, which reads as a
        // fault rather than as motion. Swinging through +/-38 keeps it legible
        // at every instant while still clearly turning in space.
        val yaw = SWING_DEG * kotlin.math.sin(t * SWING_RATE)
        runCatching {
            entity?.setPose(Pose(at, Quaternion.fromEulerAngles(0f, yaw, 0f)), Space.ACTIVITY)
            // Breathing alpha rather than a hard blink: a flashing wordmark at
            // this size reads as an alarm.
            entity?.setAlpha(0.55f + 0.45f * (0.5f + 0.5f * kotlin.math.sin(t * 2.2f)))
        }
    }

    /** Stroke glyphs sit on the baseline: nothing reaches below the anchor. */
    override val dropM: Float get() = 0f

    override fun clear() {
        runCatching { entity?.parent = null }
        runCatching { entity?.dispose() }
        entity = null
    }

    private companion object {
        const val SWING_DEG = 38f
        const val SWING_RATE = 0.55f
    }
}

/**
 * VECTORLINE — real type, and the beam that crosses it.
 *
 * THE CORRECTION THAT TOOK TWO LOOKS. The brief was "I really don't want this
 * to look like stick figures", and the first cut kept `Glyphs` anyway and
 * defended it: Battlezone drew vectors, so the stroke font looked like the
 * medium rather than the compromise. Then, with everything AROUND the word
 * rebuilt — beam, ground plane, refresh sweep — came the verdict that settled
 * it: "the Meshmore XR part is the same. I'm trying to get rid of that."
 *
 * The stroke font IS the sticks. No amount of beam work around a stick
 * wordmark stops it being one. The letterforms come from the app's real face;
 * the vector character comes from what crosses them.
 *
 * BORN FINISHED, which the first cut also got wrong. It built the letters dark
 * and drew them in over 1.8 seconds, and on glass that produced eighteen
 * seconds of nothing where the wordmark should have been:
 *
 *     02:37:20.883  [hero] vectorline — built
 *     02:37:38.741  [hero] t=0.0
 *
 * `tick` is not called until the whole scene has been built. An entrance
 * animation cannot play when there is nothing running to play it, so the beam
 * is a REFRESH — what a beam on a phosphor tube actually is — and if the loop
 * never ticks at all, the wordmark is still standing there.
 */
private class VectorlineHero(
    private val session: Session,
    private val context: android.content.Context,
    private val theme: Horizon.Palette,
    private val cap: Float,
) : Hero {

    private var word: TextRun.Run? = null
    private var beam: MeshEntity? = null
    private var beamMat: KhronosUnlitMaterial? = null
    private var origin = Vector3(0f, 0f, 0f)
    private var span = 0f
    /** Half the panel's height — everything here rides above the baseline. */
    private var mid = 0f

    override suspend fun build(root: Entity, at: Vector3) {
        origin = at

        // A PANEL IS RIGHT HERE for the reason panels are usually wrong: it is
        // born holding its final text and is never written again, which is the
        // one case that renders reliably on every device.
        // ON THE BASELINE, NOT ON THE CENTRE. Glyphs.text sits on its baseline
        // and grows upward, so the boot surface's stack — mark above, stamp
        // below, vessel under that — was laid out around a wordmark that
        // occupied nothing below the anchor. A panel is centred instead and
        // reaches half its height down, which is how the first real-type build
        // printed the version straight through the letterforms. Lifting it by
        // half its height restores the convention the layout was written for.
        word = TextRun.create(
            session, context, Heroes.WORD, cap, argb(theme.accent, 0.95f), "hero-vector",
        )?.also {
            it.entity.parent = root
            it.entity.setPose(
                Pose(Vector3(at.x, at.y + it.heightM / 2f, at.z)), Space.ACTIVITY,
            )
        }
        span = word?.widthM ?: Glyphs.width(Heroes.WORD, cap)

        // THE BEAM — a bright bar taller than the type, crossing it. On
        // additive optics it needs no mask and no invert: it adds light where
        // it passes, which is what a beam did on a phosphor tube.
        beamMat = Prims.material(session, theme.text, 0f)
        mid = (word?.heightM ?: cap) / 2f
        beam = MeshEntity.create(
            session, Prims.build(session, Prims.bar(cap * 0.05f, cap * 1.8f, cap * 0.04f)),
            listOf(beamMat!!),
        ).also {
            it.parent = root
            it.setPose(Pose(Vector3(at.x - span / 2f, at.y + mid, at.z)), Space.ACTIVITY)
        }

        // NO GROUND PLANE. The first cut hung five rules under the word; seen
        // in a capture they ran the full width of the view and fought the
        // stage's own floor grid, which already draws teal lines across the
        // room. Two grids is noise, and the rules also reached down into the
        // build stamp. The beam crossing real type is the idea; the room
        // supplies the rest.

        Log.i(
            Heroes.TAG,
            ("[hero] vectorline — real type %.3fm x %.3fm on the baseline + beam, " +
                "sweep every %.1fs").format(span, word?.heightM ?: 0f, REFRESH_S),
        )
    }

    /** Moves the beam. The type is never touched — it was finished at build. */
    override fun tick(t: Float) {
        val cycle = t % REFRESH_S
        val sweeping = cycle < REFRESH_SWEEP_S
        val phase = (cycle / REFRESH_SWEEP_S).coerceIn(0f, 1f)
        val x = -span / 2f - cap * 0.3f + (span + cap * 0.6f) * phase
        runCatching {
            beam?.setPose(
                Pose(Vector3(origin.x + x, origin.y + mid, origin.z)), Space.ACTIVITY,
            )
            // Fades at both margins so the beam enters and leaves rather than
            // snapping on at the edge of the word.
            val edge = kotlin.math.sin(phase * Math.PI).toFloat()
            beamMat?.setBaseColorFactor(rgba(theme.text, if (sweeping) 0.85f * edge else 0f))
        }
    }

    /** Baseline-aligned: this hero reaches nothing below the anchor. */
    override val dropM: Float get() = 0f

    private fun argb(rgb: Int, a: Float): Int =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private fun rgba(rgb: Int, a: Float) = Vector4(
        ((rgb shr 16) and 0xFF) / 255f,
        ((rgb shr 8) and 0xFF) / 255f,
        (rgb and 0xFF) / 255f,
        a,
    )

    override fun clear() {
        runCatching { word?.entity?.parent = null }
        runCatching { word?.entity?.dispose() }
        word = null
        listOfNotNull(beam).forEach {
            runCatching { it.parent = null }
            runCatching { it.dispose() }
        }
        beam = null
        beamMat = null
    }

    private companion object {
        /** How often the beam comes round. */
        const val REFRESH_S = 3.2f
        /** How long one sweep takes to cross. */
        const val REFRESH_SWEEP_S = 1.0f
    }
}

/**
 * WHAT EVERY HERO SHARES: a wordmark of real type, standing on the baseline.
 *
 * The letterforms are the one thing all nine agree on — they are the app's
 * name, and the operator's brief was that they stop being stroke glyphs. What
 * differs is what each theme puts AROUND them, which is the whole point of a
 * per-theme hero: the word is the constant, the room it stands in is the
 * theme.
 *
 * Panels are used here in the one way that is safe: born holding their final
 * text and never written again. Everything else a hero adds is meshes, which
 * are free to move.
 */
private abstract class TypeHero(
    protected val session: Session,
    protected val context: android.content.Context,
    protected val theme: Horizon.Palette,
    protected val cap: Float,
) : Hero {

    protected var word: TextRun.Run? = null
    protected var span = 0f
    /** Half the panel's height: everything rides above the baseline. */
    protected var mid = 0f
    protected var origin = Vector3(0f, 0f, 0f)
    protected val parts = mutableListOf<MeshEntity>()
    protected val mats = mutableListOf<KhronosUnlitMaterial>()

    /** Build the wordmark. [scale] multiplies the house cap height. */
    protected suspend fun buildWord(
        root: Entity,
        at: Vector3,
        name: String,
        rgb: Int = theme.accent,
        alpha: Float = 0.95f,
        scale: Float = 1f,
    ) {
        origin = at
        word = TextRun.create(
            session, context, Heroes.WORD, cap * scale, argb(rgb, alpha), name,
        )?.also {
            it.entity.parent = root
            it.entity.setPose(Pose(Vector3(at.x, at.y + it.heightM / 2f, at.z)), Space.ACTIVITY)
        }
        span = word?.widthM ?: Glyphs.width(Heroes.WORD, cap * scale)
        mid = (word?.heightM ?: cap * scale) / 2f
    }

    /** A mesh in this hero's frame, remembered for teardown and repainting. */
    protected suspend fun part(
        root: Entity,
        facets: Prims.Facets,
        rgb: Int,
        alpha: Float,
        at: Vector3,
    ): Int {
        val mat = Prims.material(session, rgb, alpha)
        val e = MeshEntity.create(session, Prims.build(session, facets), listOf(mat)).also {
            it.parent = root
            it.setPose(Pose(at), Space.ACTIVITY)
        }
        parts += e
        mats += mat
        return parts.size - 1
    }

    protected fun paint(i: Int, rgb: Int, a: Float) {
        runCatching { mats[i].setBaseColorFactor(rgba(rgb, a)) }
    }

    protected fun place(i: Int, at: Vector3) {
        runCatching { parts[i].setPose(Pose(at), Space.ACTIVITY) }
    }

    protected fun argb(rgb: Int, a: Float): Int =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    protected fun rgba(rgb: Int, a: Float) = Vector4(
        ((rgb shr 16) and 0xFF) / 255f,
        ((rgb shr 8) and 0xFF) / 255f,
        (rgb and 0xFF) / 255f,
        a,
    )

    override val dropM: Float get() = 0f
    override val riseM: Float get() = mid * 2f

    override fun clear() {
        runCatching { word?.entity?.parent = null }
        runCatching { word?.entity?.dispose() }
        word = null
        parts.forEach { runCatching { it.parent = null } }
        parts.forEach { runCatching { it.dispose() } }
        parts.clear()
        mats.clear()
    }

    protected fun say(what: String) {
        Log.i(
            Heroes.TAG,
            "[hero] $what — type %.3fm x %.3fm, %d mesh(es)".format(span, mid * 2f, parts.size),
        )
    }
}

/**
 * TERMINAL VOID — phosphor text and a cursor, and deliberately nothing else.
 *
 * The theme's own line is "no panels, no chrome, no graphics", so this is the
 * one hero that must resist decoration. What it adds to the word is a block
 * cursor sitting after it, blinking — the single most economical way to say
 * "this is a terminal" and the thing every phosphor screen had.
 *
 * THE CURSOR IS A MESH, NOT A REWRITE. Blinking it by re-rendering the panel
 * would rasterise an Android view twice a second forever, which is the inbox
 * bug wearing a costume. It is a small bar whose material alpha toggles.
 */
private class VoidHero(
    session: Session, context: android.content.Context, theme: Horizon.Palette, cap: Float,
) : TypeHero(session, context, theme, cap) {

    private var cursor = -1

    override suspend fun build(root: Entity, at: Vector3) {
        buildWord(root, at, "hero-void")
        cursor = part(
            root, Prims.bar(cap * 0.5f, cap * 0.92f, cap * 0.03f), theme.accent, 0.9f,
            Vector3(at.x + span / 2f + cap * 0.45f, at.y + mid, at.z),
        )
        say("terminal void — wordmark + block cursor")
    }

    override fun tick(t: Float) {
        // Slow enough to read as a terminal rather than an alarm: a hard 1.4s
        // period, on for slightly longer than off, which is what a VT100 did.
        val on = (t % 1.4f) < 0.8f
        paint(cursor, theme.accent, if (on) 0.9f else 0.05f)
    }
}

/**
 * BIOLUME — the word, and the spores that found it.
 *
 * The theme is "drifting spores, mycelial threads, soft breathing light", and
 * this is the one hero where the furniture is alive. A field of motes drifts
 * around the wordmark on slow independent orbits, brightening and dimming out
 * of phase so the whole thing breathes rather than pulses.
 *
 * THE COUNT IS THE RISK. A full horizon is about 120 entities and this adds
 * its own on top of a boot surface that already has a vessel and a mark, at
 * exactly the moment the radio is busiest. Ninety is the compromise: enough to
 * read as a swarm, few enough that it is not the reason a sync stutters.
 */
private class BiolumeHero(
    session: Session, context: android.content.Context, theme: Horizon.Palette, cap: Float,
) : TypeHero(session, context, theme, cap) {

    private class Spore(val i: Int, val hx: Float, val hy: Float, val r: Float, val ph: Float)

    private val spores = mutableListOf<Spore>()

    override suspend fun build(root: Entity, at: Vector3) {
        buildWord(root, at, "hero-biolume")
        repeat(SPORES) { k ->
            // Deterministic scatter: the same swarm every boot, so a capture is
            // comparable with the last one.
            val a = k * 2.399963f
            // Tighter than the first cut, which scattered them over 0.62 of the
            // span and read as dust on the lens rather than as a swarm around
            // a word. Seen in a capture; the fix was the radius, not the count.
            val rad = span * 0.42f * kotlin.math.sqrt((k + 1f) / SPORES)
            val hx = kotlin.math.cos(a) * rad
            val hy = kotlin.math.sin(a) * rad * 0.42f
            val i = part(
                root, Prims.mote(cap * (0.055f + 0.045f * ((k % 5) / 5f)), 5, 8),
                if (k % 6 == 0) theme.alt else theme.accent, 0.7f,
                Vector3(at.x + hx, at.y + mid + hy, at.z),
            )
            spores += Spore(i, hx, hy, cap * (0.10f + 0.06f * ((k % 7) / 7f)), a)
        }
        say("biolume — wordmark + $SPORES spores")
    }

    override fun tick(t: Float) {
        spores.forEach { s ->
            val d = t * DRIFT + s.ph
            place(
                s.i,
                Vector3(
                    origin.x + s.hx + kotlin.math.cos(d) * s.r,
                    origin.y + mid + s.hy + kotlin.math.sin(d * 0.73f) * s.r * 0.8f,
                    origin.z + kotlin.math.sin(d * 0.51f) * s.r * 0.5f,
                ),
            )
            // Out of phase on purpose: a swarm that brightens together is a
            // strobe, and a swarm that never agrees is alive.
            val b = 0.45f + 0.50f * (0.5f + 0.5f * kotlin.math.sin(t * 1.1f + s.ph * 3f))
            paint(s.i, if (s.i % 6 == 0) theme.alt else theme.accent, b)
        }
    }

    private companion object {
        const val SPORES = 90
        const val DRIFT = 0.35f
    }
}

/**
 * RECON AMBER — the word, under a sweep that never stops.
 *
 * Night operations in one hue at four luminance steps, and the theme's own
 * symbol is RADAR. So the furniture is a radar: two rings and a line going
 * round, sitting beside the wordmark rather than under it, because this is the
 * TRANSIT theme and everything it does is meant to be read at a glance while
 * walking.
 *
 * The sweep is the only moving part, and it moves at a constant rate rather
 * than easing — an instrument, not an animation.
 */
private class ReconHero(
    session: Session, context: android.content.Context, theme: Horizon.Palette, cap: Float,
) : TypeHero(session, context, theme, cap) {

    private var sweep = -1
    private var dish = Vector3(0f, 0f, 0f)

    override suspend fun build(root: Entity, at: Vector3) {
        buildWord(root, at, "hero-recon")
        dish = Vector3(at.x + span / 2f + cap * 1.5f, at.y + mid, at.z)
        // Two rings: the scale a radar reads by. Dim, because in this theme
        // brightness carries information and chrome may not spend it.
        part(root, Prims.halo(cap * 1.15f, cap * 0.022f, 40, 5), theme.alt, 0.85f, dish)
        part(root, Prims.halo(cap * 0.58f, cap * 0.018f, 32, 5), theme.alt, 0.7f, dish)
        sweep = part(
            root, Prims.bar(cap * 1.1f, cap * 0.025f, cap * 0.025f), theme.accent, 0.9f,
            Vector3(dish.x + cap * 0.55f, dish.y, dish.z),
        )
        say("recon amber — wordmark + radar")
    }

    override fun tick(t: Float) {
        // The bar is drawn along +X from the hub, so it is posed at the hub
        // offset by half its length in the direction it points.
        val a = t * SWEEP_RATE
        val r = cap * 0.55f
        runCatching {
            parts[sweep].setPose(
                Pose(
                    Vector3(dish.x + kotlin.math.cos(a) * r, dish.y + kotlin.math.sin(a) * r, dish.z),
                    Quaternion.fromEulerAngles(0f, 0f, Math.toDegrees(a.toDouble()).toFloat()),
                ),
                Space.ACTIVITY,
            )
        }
    }

    private companion object { const val SWEEP_RATE = 1.6f }
}

/**
 * AG-SYSTEMS — the word arriving at speed, and the livery it wears.
 *
 * Wipeout's craft HUD at 900 km/h. The word itself is still — a wordmark that
 * slides around is a banner ad — and the SPEED is carried by chevrons
 * streaming past it and by two livery bars beneath, which is exactly how a
 * racing HUD says velocity without moving the thing you are reading.
 */
private class AgHero(
    session: Session, context: android.content.Context, theme: Horizon.Palette, cap: Float,
) : TypeHero(session, context, theme, cap) {

    private val chev = mutableListOf<Int>()

    override suspend fun build(root: Entity, at: Vector3) {
        buildWord(root, at, "hero-aghud")
        repeat(CHEVRONS) { k ->
            val i = part(
                root, Prims.caret(cap * 0.30f, cap * 0.52f),
                if (k % 2 == 0) theme.accent else theme.alt, 0.5f,
                Vector3(at.x - span / 2f - cap * (0.6f + k * 0.55f), at.y + mid, at.z),
            )
            chev += i
        }
        // Livery: two bars under the word, the wide one in the accent and a
        // short one in the alt, offset like a racing stripe rather than centred.
        part(
            root, Prims.bar(span * 0.72f, cap * 0.045f, cap * 0.03f), theme.accent, 0.85f,
            Vector3(at.x, at.y + mid - mid * 0.78f, at.z),
        )
        part(
            root, Prims.bar(span * 0.30f, cap * 0.030f, cap * 0.03f), theme.alt, 0.9f,
            Vector3(at.x - span * 0.19f, at.y + mid - mid * 0.92f, at.z),
        )
        say("ag-systems — wordmark + $CHEVRONS chevrons + livery")
    }

    override fun tick(t: Float) {
        chev.forEachIndexed { k, i ->
            // Each chevron runs the same track on its own phase, so the stream
            // is continuous rather than a row of things bobbing together.
            val ph = ((t * SPEED + k * (1f / CHEVRONS)) % 1f)
            val x = -span / 2f - cap * 3.4f + ph * cap * 3.0f
            place(i, Vector3(origin.x + x, origin.y + mid, origin.z))
            // Brightest mid-track, gone at both ends: it enters and leaves.
            val a = kotlin.math.sin(ph * Math.PI).toFloat() * 0.75f
            paint(i, if (k % 2 == 0) theme.accent else theme.alt, a)
        }
    }

    private companion object {
        const val CHEVRONS = 6
        const val SPEED = 0.55f
    }
}

/**
 * NERV SPATIAL — the word inside the MAGI.
 *
 * The theme's line is "the command deck, wrapped around you. MAGI as a 360
 * degree ring", and its symbol is HEX. So the word sits inside three arcs that
 * turn slowly against each other — Melchior, Balthasar and Casper, the three
 * that have to agree — on a lattice of hex cells.
 *
 * ORANGE ON A LATTICE, and no attempt at a stencil cut. The obvious NERV move
 * is type with bars knocked out of it, and on additive optics a knockout is
 * impossible: there is no dark to draw with. The lattice does that work
 * instead, by being a grid the word sits ON rather than a mask over it.
 */
private class NervHero(
    session: Session, context: android.content.Context, theme: Horizon.Palette, cap: Float,
) : TypeHero(session, context, theme, cap) {

    private val arcs = mutableListOf<Int>()

    override suspend fun build(root: Entity, at: Vector3) {
        buildWord(root, at, "hero-nerv")
        val c = Vector3(at.x, at.y + mid, at.z)
        // The lattice: hexes as six-segment rings, dim, behind the word.
        var cells = 0
        for (row in -1..1) {
            for (col in -4..4) {
                val hx = col * cap * 0.62f + (if (row % 2 != 0) cap * 0.31f else 0f)
                val hy = row * cap * 0.54f
                if (kotlin.math.abs(hx) < span * 0.52f && kotlin.math.abs(hy) < mid * 1.6f) {
                    part(
                        root, Prims.halo(cap * 0.30f, cap * 0.012f, 6, 4), theme.accent, 0.22f,
                        Vector3(c.x + hx, c.y + hy, c.z - cap * 0.15f),
                    )
                    cells++
                }
            }
        }
        // The three that must agree.
        repeat(3) { k ->
            arcs += part(
                root, Prims.halo(span * (0.60f + k * 0.09f), cap * 0.02f, 30, 5),
                if (k == 1) theme.alt else theme.accent, 0.7f, c,
            )
        }
        say("nerv spatial — wordmark + $cells hex cell(s) + 3 arcs")
    }

    override fun tick(t: Float) {
        arcs.forEachIndexed { k, i ->
            // Counter-rotating, and slowly: a command deck is not a fairground.
            val dir = if (k % 2 == 0) 1f else -1f
            runCatching {
                parts[i].setPose(
                    Pose(
                        Vector3(origin.x, origin.y + mid, origin.z),
                        Quaternion.fromEulerAngles(74f, 0f, t * 7f * dir + k * 40f),
                    ),
                    Space.ACTIVITY,
                )
            }
        }
    }
}

/**
 * HALO FIELD — the calm one, and the only hero allowed to do almost nothing.
 *
 * "The mesh as a calm horizon. The one you can wear for eight hours." A theme
 * whose whole claim is that it can be worn all day cannot open with a
 * performance. So: the word, and three rings lying flat beneath it like the
 * range bands on its own horizon, breathing so slowly that it reads as ambient
 * rather than as an animation waiting to be watched.
 */
private class HaloHero(
    session: Session, context: android.content.Context, theme: Horizon.Palette, cap: Float,
) : TypeHero(session, context, theme, cap) {

    private val rings = mutableListOf<Int>()

    override suspend fun build(root: Entity, at: Vector3) {
        buildWord(root, at, "hero-halo")
        repeat(RINGS) { k ->
            rings += part(
                root, Prims.halo(span * (0.34f + k * 0.20f), cap * 0.018f, 44, 5),
                if (k == 1) theme.alt else theme.accent, 0.5f,
                // Flat, and below the word — the same posture the range bands
                // take on the horizon this theme is named for.
                Vector3(at.x, at.y + mid * 0.16f, at.z),
            )
        }
        say("halo field — wordmark + $RINGS flat rings")
    }

    override fun tick(t: Float) {
        rings.forEachIndexed { k, i ->
            // A wave travelling outward, one ring at a time, at walking pace.
            val ph = t * 0.42f - k * 0.55f
            paint(
                i, if (k == 1) theme.alt else theme.accent,
                0.30f + 0.35f * (0.5f + 0.5f * kotlin.math.sin(ph)),
            )
            runCatching {
                parts[i].setPose(
                    Pose(
                        Vector3(origin.x, origin.y + mid * 0.16f, origin.z),
                        Quaternion.fromEulerAngles(88f, 0f, 0f),
                    ),
                    Space.ACTIVITY,
                )
            }
        }
    }

    private companion object { const val RINGS = 3 }
}

/**
 * SEELE MONOLITH — the word AS the monument, and nothing that moves.
 *
 * "Type is the entire UI. Cream numerals a foot tall, near-zero chrome." This
 * is the theme that shows one row per page and calls it a treatment, so its
 * hero is the only one that gets to be bigger than the others and the only one
 * that is completely still. [tick] does nothing at all, on purpose: a
 * monolith that shimmers is a screensaver.
 *
 * Seven slabs stand behind the word — the committee that is never shown, only
 * heard — and the accent is the single red this theme owns, used once.
 */
private class SeeleHero(
    session: Session, context: android.content.Context, theme: Horizon.Palette, cap: Float,
) : TypeHero(session, context, theme, cap) {

    override suspend fun build(root: Entity, at: Vector3) {
        // BIGGER, and it says so via riseM so the mark gets out of the way.
        buildWord(root, at, "hero-seele", theme.accent, 0.97f, SCALE)
        repeat(SLABS) { k ->
            val x = (k - (SLABS - 1) / 2f) * span * 0.155f
            // Tall, narrow, and set back behind the type. Alternating heights
            // so it reads as an assembly rather than as a fence.
            val h = mid * (1.5f + 0.45f * ((k % 3) / 2f))
            part(
                root, Prims.bar(span * 0.075f, h, cap * 0.03f),
                if (k == SLABS / 2) theme.alert else theme.alt,
                if (k == SLABS / 2) 0.55f else 0.30f,
                Vector3(at.x + x, at.y + mid, at.z - cap * 0.35f),
            )
        }
        say("seele monolith — wordmark at ${SCALE}x + $SLABS slabs")
    }

    /** Nothing. A monolith that moves is not one. */
    override fun tick(t: Float) = Unit

    private companion object {
        const val SLABS = 7
        const val SCALE = 1.45f
    }
}

/**
 * DR POP — the word as printed matter.
 *
 * "Flat colour blocks, fabricated sub-brands, katakana as graphic." The one
 * theme whose premise is graphic design rather than instrumentation, so the
 * furniture is a poster: blocks of flat colour, a fabricated division mark,
 * and メッシュモア set as an image rather than as a label.
 *
 * THE KATAKANA IS A SECOND PANEL, not a decoration on the first. It is the
 * graphic element this theme is named for, and it wants its own size and its
 * own colour — which on a panel means its own run.
 *
 * A RASTER WOULD BE BETTER STILL, and is now known to be possible:
 * `Texture.create` takes an asset path and `KhronosUnlitMaterial` accepts a
 * base colour texture, so an authored PNG could hang on a quad with no new
 * machinery. That needs an image nobody has drawn yet; this is the version
 * that ships without one.
 */
private class DrPopHero(
    session: Session, context: android.content.Context, theme: Horizon.Palette, cap: Float,
) : TypeHero(session, context, theme, cap) {

    private var kana: TextRun.Run? = null

    override suspend fun build(root: Entity, at: Vector3) {
        buildWord(root, at, "hero-drpop", theme.text, 0.97f)
        // Blocks first, so the type reads as printed ON them. Flat, offset,
        // deliberately not centred — the OFFSET plate is this theme's own idiom.
        val blocks = listOf(
            Triple(-span * 0.40f, mid * 1.30f, theme.accent),
            Triple(span * 0.26f, mid * 1.62f, theme.warn),
            Triple(-span * 0.05f, mid * 0.28f, theme.alt),
        )
        blocks.forEachIndexed { k, (x, y, rgb) ->
            part(
                root, Prims.bar(span * (0.30f - k * 0.06f), mid * (0.62f - k * 0.10f), cap * 0.02f),
                rgb, 0.42f, Vector3(at.x + x, at.y + y, at.z - cap * 0.25f),
            )
        }
        kana = TextRun.create(
            session, context, KANA, cap * 0.62f, argb(theme.accent, 0.95f), "hero-drpop-kana",
        )?.also {
            it.entity.parent = root
            it.entity.setPose(
                Pose(Vector3(at.x - span * 0.22f, at.y + mid * 2.05f, at.z), ), Space.ACTIVITY,
            )
        }
        say("dr pop — wordmark + katakana + ${blocks.size} blocks")
    }

    /** Print does not animate. The blocks hold; only the ink is alive. */
    override fun tick(t: Float) = Unit

    override val riseM: Float get() = mid * 2f + cap * 1.2f

    override fun clear() {
        runCatching { kana?.entity?.parent = null }
        runCatching { kana?.entity?.dispose() }
        kana = null
        super.clear()
    }

    private companion object { const val KANA = "メッシュモア" }
}
