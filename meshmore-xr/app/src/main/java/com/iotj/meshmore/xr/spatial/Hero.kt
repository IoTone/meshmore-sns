// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.util.Log
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space

/**
 * THE BOOT HERO — how a theme introduces itself.
 *
 * The wordmark used to be one thing in all nine themes: `Glyphs.text` extruded
 * into strokes, the same vector font the node callsigns use. The operator's
 * verdict was that it "looks like it was made out of sticks", and the deeper
 * problem is that it wasted the one moment a theme has to say what it is. Boot
 * is fifteen to thirty seconds of a wearer waiting on a contact sync with
 * nothing else to look at; that is not dead time, it is the only uninterrupted
 * attention this app ever gets.
 *
 * So the wordmark becomes a per-theme surface, and this is its contract.
 *
 * THREE RULES, all of them learned the hard way elsewhere in this app:
 *
 *  1. BUILT ONCE, ANIMATED FREELY. Everything a hero will ever show is created
 *     in [build]; [tick] only moves and repaints what already exists. Meshes
 *     are cheap to pose and materials are mutable, but a panel rewritten per
 *     frame rasterises an Android view every time — the habit that had the
 *     inbox writing itself fifteen times a second.
 *  2. IT MUST SETTLE. The vessel beside it is showing real sync progress, and
 *     an animation still running after four seconds competes with the only
 *     honest information on the surface. Enter, land, hold.
 *  3. IT MUST SAY WHAT IT BUILT. There is no visual check available: the
 *     emulator's only display is FLAG_SECURE, so spatial screencap returns
 *     blank. A hero reports its own geometry and cost to logcat or it cannot
 *     be reviewed at all.
 */
interface Hero {

    /** Create everything, parented to [root], centred on [at]. Never called twice. */
    suspend fun build(root: Entity, at: Vector3)

    /** [t] is seconds since the boot surface appeared. Pose and repaint only. */
    fun tick(t: Float)

    fun clear()
}

/**
 * Which hero a theme gets.
 *
 * DEFAULTING TO THE OLD WORDMARK IS DELIBERATE. The heroes arrive one at a
 * time, and a theme without one must look exactly as it did rather than
 * degrading to nothing — so [PlainWordmark] is the same mesh, the same
 * material and the same pose the boot surface has always built.
 */
object Heroes {

    suspend fun forTheme(
        session: Session,
        skin: Theme.Skin,
        root: Entity,
        at: Vector3,
        cap: Float,
    ): Hero {
        val hero: Hero = when (skin.key) {
            "vector" -> VectorlineHero(session, skin.palette, cap)
            else -> PlainWordmark(session, skin.palette, cap)
        }
        hero.build(root, at)
        return hero
    }

    const val WORD = "MESHMORE XR"
    const val TAG = "MeshmoreXR"
}

/** The wordmark as it has always been: one extruded stroke mesh, held still. */
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
        Log.i(Heroes.TAG, "[hero] plain wordmark, 1 mesh")
    }

    /**
     * The swing and the breath, moved here verbatim from `Boot.tick` when the
     * wordmark stopped being the boot surface's own property. Unchanged on
     * purpose: eight themes still see this, and a refactor is not the place to
     * quietly restyle them.
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
            entity?.setPose(
                Pose(at, androidx.xr.runtime.math.Quaternion.fromEulerAngles(0f, yaw, 0f)),
                Space.ACTIVITY,
            )
            // Breathing alpha rather than a hard blink: a flashing wordmark at
            // this size reads as an alarm.
            entity?.setAlpha(0.55f + 0.45f * (0.5f + 0.5f * kotlin.math.sin(t * 2.2f)))
        }
    }

    private companion object {
        const val SWING_DEG = 38f
        const val SWING_RATE = 0.55f
    }

    override fun clear() {
        runCatching { entity?.parent = null }
        runCatching { entity?.dispose() }
        entity = null
    }
}

/**
 * VECTORLINE — the wordmark drawn by a beam, letter by letter.
 *
 * THE ONE THEME WHERE STICKS ARE CORRECT. Its brief is Tempest, Rez and
 * Battlezone, and those were vector displays: a beam deflected across a
 * phosphor screen, drawing line segments and leaving them glowing. The stroke
 * font is not a compromise here, it is the medium — what was missing was the
 * BEAM. A vector display never showed you a finished frame; it showed you the
 * beam getting there, and the letters behind it burning down to a resting
 * brightness.
 *
 * So the word is built one character at a time rather than as a single mesh,
 * and each character's material is repainted every frame against the beam's
 * position: full brightness where the beam just passed, decaying to a steady
 * glow behind it, dark ahead of it. Ten small meshes and one head, all created
 * at build; [tick] only writes colour.
 */
private class VectorlineHero(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val cap: Float,
) : Hero {

    private class Stroke(val entity: MeshEntity, val mat: androidx.xr.scenecore.KhronosUnlitMaterial, val x: Float)

    private val strokes = mutableListOf<Stroke>()
    private var head: MeshEntity? = null
    private var headMat: androidx.xr.scenecore.KhronosUnlitMaterial? = null
    private val horizon = mutableListOf<Pair<MeshEntity, androidx.xr.scenecore.KhronosUnlitMaterial>>()
    private var origin = Vector3(0f, 0f, 0f)
    private var span = 0f

    override suspend fun build(root: Entity, at: Vector3) {
        origin = at
        val word = Heroes.WORD
        // ADVANCE FROM THE PUBLIC MEASURE, not from the font's private metrics.
        // width(k cells) is linear in k, so the per-cell advance is the
        // difference between two of them and the ink box is the width of one.
        // That keeps this arithmetic correct if the font's spacing ever moves.
        val one = Glyphs.width("M", cap)
        val adv = Glyphs.width("MM", cap) - one
        span = Glyphs.width(word, cap)
        val left = -span / 2f

        word.forEachIndexed { i, ch ->
            if (ch == ' ') return@forEachIndexed
            // Each character is centred on its own ink box by Glyphs.text, so
            // it is placed at the centre of the cell it would occupy in the
            // full word.
            val cx = left + i * adv + one / 2f
            val mesh = Prims.build(session, Glyphs.text(ch.toString(), cap))
            val mat = Prims.material(session, theme.accent, 0f)
            val e = MeshEntity.create(session, mesh, listOf(mat)).also {
                it.parent = root
                it.setPose(Pose(Vector3(at.x + cx, at.y, at.z)), Space.ACTIVITY)
            }
            strokes += Stroke(e, mat, cx)
        }

        // THE BEAM HEAD. A small bright mote riding the baseline — the only
        // part of a vector display that is actually moving.
        headMat = Prims.material(session, theme.text, 0f)
        head = MeshEntity.create(
            session, Prims.build(session, Prims.mote(cap * 0.14f, 5, 8)),
            listOf(headMat!!),
        ).also {
            it.parent = root
            it.setPose(Pose(Vector3(at.x + left, at.y + cap * 0.45f, at.z)), Space.ACTIVITY)
        }

        // A HORIZON IN ONE PASS, under the word. Five rules widening with
        // distance: the cheapest possible reading of Battlezone's ground plane,
        // and five meshes rather than a grid because the wearer's real room is
        // already behind it.
        repeat(HORIZON_LINES) { i ->
            val w = span * (0.30f + i * 0.19f)
            val mat = Prims.material(session, theme.alt, 0f)
            val e = MeshEntity.create(
                session, Prims.build(session, Prims.bar(w, cap * 0.02f, cap * 0.02f)),
                listOf(mat),
            ).also {
                it.parent = root
                it.setPose(
                    Pose(Vector3(at.x, at.y - cap * (0.55f + i * 0.28f), at.z)),
                    Space.ACTIVITY,
                )
            }
            horizon += e to mat
        }

        Log.i(
            Heroes.TAG,
            "[hero] vectorline — ${strokes.size} stroke(s) + head + $HORIZON_LINES rule(s), " +
                "span %.3fm, trace %.1fs".format(span, TRACE_S),
        )
    }

    /**
     * REPAINT ONLY. No entity is created, moved or destroyed here except the
     * head, which is the one thing that travels.
     */
    override fun tick(t: Float) {
        val phase = (t / TRACE_S).coerceIn(0f, 1f)
        val beam = -span / 2f + span * phase
        strokes.forEach { s ->
            val behind = beam - s.x
            val a = when {
                behind < 0f -> 0f
                else -> REST + (1f - REST) * kotlin.math.exp(-behind / (span * TAIL))
            }
            runCatching { s.mat.setBaseColorFactor(rgba(theme.accent, a)) }
        }
        runCatching {
            head?.setPose(
                Pose(Vector3(origin.x + beam, origin.y + cap * 0.45f, origin.z)),
                Space.ACTIVITY,
            )
            headMat?.setBaseColorFactor(rgba(theme.text, if (phase < 1f) 0.95f else 0f))
        }
        // The ground arrives after the word, one rule at a time.
        horizon.forEachIndexed { i, (_, mat) ->
            val up = ((t - HORIZON_AT - i * 0.12f) / 0.5f).coerceIn(0f, 1f)
            runCatching { mat.setBaseColorFactor(rgba(theme.alt, up * 0.55f)) }
        }
    }

    private fun rgba(rgb: Int, a: Float) = androidx.xr.runtime.math.Vector4(
        ((rgb shr 16) and 0xFF) / 255f,
        ((rgb shr 8) and 0xFF) / 255f,
        (rgb and 0xFF) / 255f,
        a,
    )

    override fun clear() {
        val doomed = strokes.map { it.entity } + listOfNotNull(head) + horizon.map { it.first }
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
        strokes.clear()
        horizon.clear()
        head = null
        headMat = null
    }

    private companion object {
        /** How long the beam takes to cross the word. */
        const val TRACE_S = 1.8f
        /** What a drawn letter settles to once the beam has gone. */
        const val REST = 0.55f
        /** Persistence, as a fraction of the word's span. */
        const val TAIL = 0.16f
        const val HORIZON_AT = 2.4f
        const val HORIZON_LINES = 5
    }
}
