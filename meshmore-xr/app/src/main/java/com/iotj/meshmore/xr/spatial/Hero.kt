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
