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
    session: Session, context: android.content.Context, theme: Horizon.Palette, cap: Float,
) : TypeHero(session, context, theme, cap) {

    private var beam = -1

    override suspend fun build(root: Entity, at: Vector3) {
        buildWord(root, at, "hero-vector")
        // THE BEAM — a bright bar taller than the type, crossing it. On
        // additive optics it needs no mask and no invert: it adds light where
        // it passes, which is what a beam did on a phosphor tube.
        beam = part(
            root, Prims.bar(cap * 0.075f, cap * 1.8f, cap * 0.05f), theme.text, 0f,
            Vector3(at.x - span / 2f, at.y + mid, at.z),
        )
        say("vectorline — wordmark + beam every ${REFRESH_S}s")
    }

    override fun tick(t: Float) {
        // JITTER AND SAG. A vector monitor never held a shape perfectly still:
        // the deflection amplifiers drifted, and the image swelled a fraction
        // when the beam had a lot to draw. Two sine waves at deliberately
        // unrelated rates give a wobble that never repeats on a beat, which is
        // what makes it read as instability rather than as animation.
        val jx = kotlin.math.sin(t * 7.3f) * 0.0035f + kotlin.math.sin(t * 3.1f) * 0.0022f
        val jy = kotlin.math.sin(t * 5.9f) * 0.0028f + kotlin.math.sin(t * 2.3f) * 0.0018f
        moveWord(dx = jx, dy = jy, capScale = 1f + kotlin.math.sin(t * 1.7f) * 0.012f)

        val cycle = t % REFRESH_S
        val sweeping = cycle < REFRESH_SWEEP_S
        val phase = (cycle / REFRESH_SWEEP_S).coerceIn(0f, 1f)
        val x = -span / 2f - cap * 0.3f + (span + cap * 0.6f) * phase
        place(beam, Vector3(origin.x + x, origin.y + mid, origin.z))
        // Fades at both margins so the beam enters and leaves rather than
        // snapping on at the edge of the word.
        val edge = kotlin.math.sin(phase * Math.PI).toFloat()
        paint(beam, theme.text, if (sweeping) 0.85f * edge else 0f)
    }

    private companion object {
        /** How often the beam comes round. */
        const val REFRESH_S = 3.2f
        /** How long one sweep takes to cross. */
        const val REFRESH_SWEEP_S = 1.0f
    }
}

/**
 * A NOTE ON LINE WEIGHT, paid for once and applied to every hero below.
 *
 * The first NERV build put 27 hex cells and 3 arcs in the scene and a capture
 * showed none of them — only the wordmark. They were drawn with tubes of
 * `cap * 0.012`, which is 1.4 mm, which at the boot surface's two metres is
 * 0.04 degrees. The brief's own floor for anything that must be SEEN is 0.6.
 *
 * Stroke weight on this surface is therefore never below about `cap * 0.045`
 * (5 mm, 0.15 degrees) and usually above it. Real type gets away with less
 * because a glyph is a filled shape read as a whole; a lone line has nothing
 * to be read as.
 */
private abstract class TypeHero(
    protected val session: Session,
    protected val context: android.content.Context,
    protected val theme: Horizon.Palette,
    protected val cap: Float,
) : Hero {

    protected var word: TextRun.Run? = null
    /** Where the word was built. All motion is measured from here, never accumulated. */
    protected var home = Vector3(0f, 0f, 0f)
    /** The cap height it was built at, so a breath can be a ratio of it. */
    protected var baseCap = 0f
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
        home = Vector3(at.x, at.y + mid, at.z)
        baseCap = cap * scale
    }

    /**
     * HOW THE WORD ITSELF MOVES.
     *
     * Every hero got furniture that moves and left the type dead still, which
     * made nine themes share one gesture: none. This is the other half — the
     * wordmark's own behaviour, which is the most characteristic thing a
     * theme can do, because it is the one object all nine have in common.
     *
     * THREE RULES, and they are the same three the surface already lives by:
     *
     *  1. FROM HOME, NEVER ACCUMULATED. Every call is an absolute offset from
     *     where the word was built. A motion that integrates drifts, and a
     *     drifting wordmark walks out of a layout that was measured once.
     *  2. TRANSFORMS ONLY. Pose, scale and alpha are transforms on a panel
     *     that already holds its raster. `setCapHeight` is `setScale` — it
     *     does not re-render type, which per-frame would be the inbox bug
     *     with a different surface's name on it.
     *  3. SMALL, BUT NOT INVISIBLE. At two metres one degree is 35 mm, so
     *     millimetres are the working unit — and the first cut of every gesture
     *     below was three to five of them, which a centroid tracked across
     *     thirty captured frames could not separate from its own noise. SEELE,
     *     which provably does not move, measured 1.0 mm of travel; half the
     *     themes measured the same. Motion nobody can see is not restraint, it
     *     is a rounding error. The working range is 10-20 mm.
     */
    protected fun moveWord(
        dx: Float = 0f,
        dy: Float = 0f,
        dz: Float = 0f,
        yawDeg: Float = 0f,
        rollDeg: Float = 0f,
        capScale: Float = 1f,
        alpha: Float? = null,
    ) {
        val w = word ?: return
        runCatching {
            w.entity.setPose(
                Pose(
                    Vector3(home.x + dx, home.y + dy, home.z + dz),
                    Quaternion.fromEulerAngles(0f, yawDeg, rollDeg),
                ),
                Space.ACTIVITY,
            )
            if (capScale != 1f) w.setCapHeight(baseCap * capScale)
            alpha?.let { w.entity.setAlpha(it) }
        }
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

        // PHOSPHOR, AND INTERFERENCE. The word does not move at all for most
        // of its life — this is a terminal, and terminals hold. What it does
        // is FLICKER, faintly and irregularly, the way a phosphor screen does;
        // and once every few seconds the picture tears upward by two
        // millimetres for a single beat, which is a tube losing its lock. The
        // hold is the character. The interruption is what makes the hold read
        // as a screen rather than as a sticker.
        val roll = t % ROLL_S
        val torn = roll < 0.10f
        moveWord(
            dy = if (torn) 0.010f else 0f,
            alpha = 0.90f + 0.09f * kotlin.math.sin(t * 11.7f) * kotlin.math.sin(t * 4.3f),
        )
    }

    private companion object { const val ROLL_S = 4.7f }
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
        // FLOATING, NOT ANIMATED. The word drifts the way something suspended
        // in water drifts — five millimetres up and down over nine seconds,
        // with a slow swell in scale a beat out of phase with it, so the rise
        // and the growth never quite agree. Nothing in a living thing moves on
        // one clock.
        moveWord(
            dy = kotlin.math.sin(t * 0.68f) * 0.018f,
            dx = kotlin.math.sin(t * 0.41f) * 0.008f,
            capScale = 1f + kotlin.math.sin(t * 0.52f) * 0.022f,
        )
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
        //
        // STOOD UP TO FACE THE WEARER. Prims.halo lies in the horizontal plane
        // — a ring on a table — so from a surface above eye level it reads as a
        // thin ellipse. The sweep bar was already turning in the vertical
        // plane, so the first capture showed a dish and its hand in two
        // different planes. A radar is a disc you look AT.
        val facing = Quaternion.fromEulerAngles(90f, 0f, 0f)
        upright(part(root, Prims.halo(cap * 1.15f, cap * 0.055f, 40, 5), theme.alt, 0.85f, dish), dish, facing)
        upright(part(root, Prims.halo(cap * 0.58f, cap * 0.050f, 32, 5), theme.alt, 0.7f, dish), dish, facing)
        sweep = part(
            root, Prims.bar(cap * 1.1f, cap * 0.060f, cap * 0.060f), theme.accent, 0.95f,
            Vector3(dish.x + cap * 0.55f, dish.y, dish.z),
        )
        say("recon amber — wordmark + radar")
    }

    override fun tick(t: Float) {
        // A RE-LOCK, NOT A DRIFT. Night operations, and the word behaves like
        // a stabilised sight: it holds dead still, then steps two millimetres
        // and settles, on a strict interval. The step is instant and the
        // settle is fast — an instrument correcting itself, never a thing
        // gliding around. Nothing in this theme eases.
        val since = t % RELOCK_S
        val kick = if (since < 0.22f) (1f - since / 0.22f) else 0f
        moveWord(dx = kick * 0.009f, dy = kick * -0.006f)
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

    private fun upright(i: Int, at: Vector3, q: Quaternion) {
        runCatching { parts[i].setPose(Pose(at, q), Space.ACTIVITY) }
    }

    private companion object {
        const val SWEEP_RATE = 1.6f
        const val RELOCK_S = 2.4f
    }
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
            root, Prims.bar(span * 0.72f, cap * 0.085f, cap * 0.04f), theme.accent, 0.9f,
            Vector3(at.x, at.y + mid - mid * 0.78f, at.z),
        )
        part(
            root, Prims.bar(span * 0.30f, cap * 0.060f, cap * 0.04f), theme.alt, 0.95f,
            Vector3(at.x - span * 0.19f, at.y + mid - mid * 0.92f, at.z),
        )
        say("ag-systems — wordmark + $CHEVRONS chevrons + livery")
    }

    override fun tick(t: Float) {
        // UNDER LOAD. A craft HUD at speed is not bolted to the world — it
        // rides the airframe. The word banks a degree either side and drifts
        // four millimetres against the bank, which reads as the whole thing
        // being pushed rather than as the letters wobbling.
        val sway = kotlin.math.sin(t * 0.75f)
        moveWord(dx = sway * -0.015f, yawDeg = sway * 3.0f, rollDeg = sway * 1.4f)
        chev.forEachIndexed { k, i ->
            // Each chevron runs the same track on its own phase, so the stream
            // is continuous rather than a row of things bobbing together.
            val ph = ((t * SPEED + k * (1f / CHEVRONS)) % 1f)
            val x = -span / 2f - cap * 3.4f + ph * cap * 3.0f
            // POINTING WHERE THE SPEED GOES. Prims.caret builds a cone on its
            // vertical axis, so the first build had six chevrons pointing at
            // the ceiling while streaming sideways — visible the moment there
            // was a capture to look at. Laid over to face along the track.
            runCatching {
                parts[i].setPose(
                    Pose(
                        Vector3(origin.x + x, origin.y + mid, origin.z),
                        Quaternion.fromEulerAngles(0f, 0f, -90f),
                    ),
                    Space.ACTIVITY,
                )
            }
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
                        root, Prims.halo(cap * 0.42f, cap * 0.045f, 6, 4), theme.accent, 0.45f,
                        Vector3(c.x + hx, c.y + hy, c.z - cap * 0.15f),
                    )
                    cells++
                }
            }
        }
        // The three that must agree.
        repeat(3) { k ->
            arcs += part(
                root, Prims.halo(span * (0.60f + k * 0.09f), cap * 0.055f, 30, 5),
                if (k == 1) theme.alt else theme.accent, 0.7f, c,
            )
        }
        say("nerv spatial — wordmark + $cells hex cell(s) + 3 arcs")
    }

    override fun tick(t: Float) {
        // A HARD RE-SEAT. Evangelion's title cards cut, they do not dissolve,
        // and the MAGI does not ease into a decision. So the word SNAPS six
        // millimetres and snaps back eighty milliseconds later, with nothing
        // in between: the only motion in this app with no interpolation in it
        // at all, which is the point.
        val phase = t % RESEAT_S
        val cut = phase < 0.13f
        moveWord(dx = if (cut) -0.020f else 0f, alpha = if (cut) 1f else 0.93f)
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

    private companion object { const val RESEAT_S = 3.0f }
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
                root, Prims.halo(span * (0.34f + k * 0.20f), cap * 0.055f, 44, 5),
                if (k == 1) theme.alt else theme.accent, 0.5f,
                // Flat, and below the word — the same posture the range bands
                // take on the horizon this theme is named for.
                Vector3(at.x, at.y + mid * 0.16f, at.z),
            )
        }
        say("halo field — wordmark + $RINGS flat rings")
    }

    override fun tick(t: Float) {
        // A BREATH. The theme that claims eight hours of wear does the least
        // of the nine — twelve millimetres of rise and fall over seven seconds,
        // the light coming up as it rises. The first cut used three, which
        // measured at the noise floor of the capture: at two metres a degree is
        // 35 mm, so 3 mm is a twelfth of one and nobody was ever going to see
        // it. Calm has to be visible before it can be calm.
        val b = kotlin.math.sin(t * 0.9f)
        moveWord(dy = b * 0.012f, alpha = 0.88f + 0.09f * b)
        rings.forEachIndexed { k, i ->
            // A wave travelling outward, one ring at a time, at walking pace.
            val ph = t * 0.42f - k * 0.55f
            paint(
                i, if (k == 1) theme.alt else theme.accent,
                0.30f + 0.35f * (0.5f + 0.5f * kotlin.math.sin(ph)),
            )
            // No rotation: Prims.halo already lies flat, which is what a range
            // band is. Standing them up would make them a target, not a scale.
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

    /**
     * NOTHING. AND THAT IS THE GESTURE.
     *
     * Eight themes were given a way of moving the word, and this one keeps
     * absolute stillness on purpose. A monolith that drifts, breathes or
     * flickers is a screensaver; the whole authority of the thing is that it
     * does not react to you. In a set where everything else is alive, the one
     * that refuses is the one you notice.
     */
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
                rgb, 0.55f, Vector3(at.x + x, at.y + y, at.z - cap * 0.25f),
            )
        }
        kana = TextRun.create(
            session, context, KANA, cap * 0.62f, argb(theme.accent, 0.95f), "hero-drpop-kana",
        )?.also {
            it.entity.parent = root
            it.entity.setPose(
                // Closer than the first cut, which put it at 2.05 and pushed the
                // katakana off the top of the frame — it is the graphic this
                // theme is named for and it cannot be the part that gets cropped.
                Pose(Vector3(at.x - span * 0.22f, at.y + mid * 1.42f, at.z)), Space.ACTIVITY,
            )
        }
        say("dr pop — wordmark + katakana + ${blocks.size} blocks")
    }

    /**
     * REGISTRATION SHIFT. Print does not animate — but print MISREGISTERS, and
     * a plate that lands a hair off is the most print thing that can happen to
     * a word. Every couple of seconds the type jumps three millimetres and a
     * hair up, for a tenth of a second, exactly as though the sheet moved
     * under the press. Everything else here holds absolutely still.
     */
    override fun tick(t: Float) {
        val phase = t % REGISTER_S
        val off = phase < 0.14f
        moveWord(dx = if (off) 0.011f else 0f, dy = if (off) 0.007f else 0f)
    }

    override val riseM: Float get() = mid * 2.9f

    override fun clear() {
        runCatching { kana?.entity?.parent = null }
        runCatching { kana?.entity?.dispose() }
        kana = null
        super.clear()
    }

    private companion object {
        const val KANA = "メッシュモア"
        const val REGISTER_S = 2.2f
    }
}
