// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.util.Log
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Quaternion
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * THE BOOT SURFACE — what the room does while the mesh loads.
 *
 * Loading a contact list takes fifteen to thirty seconds against a real mesh,
 * and an empty room for thirty seconds reads as a broken app. The usual answer
 * is a spinner on a panel, which is exactly the thing this project exists to
 * avoid. So the wait is spatial: a wordmark turning slowly overhead and a
 * VESSEL that visibly fills with the data as it arrives.
 *
 * The progress is REAL. ContactsStartFrame announces how many contacts are
 * coming, so the fill is received/total and nothing is invented -- no bar that
 * sits at 90%, no indeterminate sweep pretending to be information. When the
 * radio does not tell us a total, the vessel shows arrivals without a fill line
 * rather than guessing one.
 *
 * Everything here is disposed the moment loading ends. A loading surface that
 * lingers is just clutter with a good excuse.
 */
class Boot(
    private val session: Session,
    private val skin: Theme.Skin,
    /** Needed by heroes that draw with real type rather than stroke glyphs. */
    private val context: android.content.Context,
) {

    /** Kept under the old name so every existing reference reads unchanged. */
    private val theme: Horizon.Palette = skin.palette

    private val entities = mutableListOf<Entity>()
    private var hero: Hero? = null
    /**
     * THE MARK — the launcher icon, as the thing it is a picture OF.
     *
     * `tools/gen_icon.py` renders the app icon offline from these exact
     * primitives: signal rings as HALOs, links as SPURs, satellites as MOTEs, a
     * core that is a very coarse mote and therefore an octahedron. The icon has
     * always been "a frame OF the app rather than an illustration of it", and
     * this closes the loop — the thing on the launcher and the thing turning
     * over the boot vessel are the same object, one rendered ahead of time and
     * one alive.
     *
     * The CORE IS THE PARENT. This SDK has no contentless group entity, so the
     * one part that sits at the centre of rotation carries the rest as
     * children: rotating it rotates the whole lockup, and the children's poses
     * stay in its frame where they were authored.
     */
    private var core: MeshEntity? = null
    private var meniscus: MeshEntity? = null
    private val body = mutableListOf<MeshEntity>()
    private val motes = mutableListOf<MeshEntity>()
    private var level = 0f
    private var at: Vector3 = Vector3(0f, 0f, 0f)
    private var t = 0f
    private var lastTickMs = 0L
    private var markUp = MARK_UP

    /**
     * Build overhead and slightly forward. HIGH, because the horizon is at eye
     * level and the boot surface must not occupy the space the mesh is about to
     * arrive into -- the two should never fight for the same air.
     */
    suspend fun build(o: Stage.Origin) {
        clear()
        val root = session.scene.activitySpace
        at = o.place(0f, FORWARD, HEIGHT)

        // THE HERO — the theme's own introduction, in place of the one
        // wordmark that used to serve all nine. See Hero.kt: a theme without
        // one still gets exactly the stroke mesh this line used to build, so
        // the heroes can arrive one at a time without leaving a hole.
        //
        // NOT ADDED TO `entities`. The hero owns what it made and disposes it
        // in its own clear(), which is the rule that keeps a surface's teardown
        // in one place — the lesson from HALO dying on a list it did not empty.
        hero = Heroes.forTheme(session, context, skin, root, at, CAP)
        // THE MARK CLEARS WHATEVER THE HERO TURNED OUT TO BE. MARK_UP was
        // chosen against a one-cap stroke line; a hero with taller type says
        // how far it reaches and the mark goes above that instead.
        markUp = maxOf(MARK_UP, (hero?.riseM ?: 0f) + MARK_GAP)

        // THE BUILD, under the wordmark.
        //
        // Asked for after an afternoon of "is the new version installed?" —
        // twice out loud, and several more times implicitly, each costing a
        // device cycle to answer. On glass there is no other way to tell
        // whether an install landed: ABOUT carries the version but is two
        // pinches deep, and the splash is the one surface nobody can miss.
        //
        // THE TIME, NOT JUST THE NAME. VERSION_NAME is a static 0.1.0 and does
        // not move between debug builds, which is exactly when this matters —
        // so it is the build timestamp that actually answers the question.
        // Small and dim: this is a diagnostic riding a hero shot, and it must
        // not compete with the wordmark it sits under.
        val stamp = "v" + com.iotj.meshmore.xr.BuildConfig.VERSION_NAME + "  " +
            java.text.SimpleDateFormat("MMM dd HH:mm", java.util.Locale.US)
                .format(java.util.Date(com.iotj.meshmore.xr.BuildConfig.BUILD_TIME))
        MeshEntity.create(
            session,
            Prims.build(session, Glyphs.text(stamp, CAP * STAMP_SCALE)),
            listOf(Prims.material(session, theme.alt, 0.55f)),
        ).also {
            it.parent = root
            // UNDER WHATEVER THE HERO ACTUALLY IS. STAMP_DROP was written when
            // every wordmark was stroke glyphs on a baseline and nothing hung
            // below the anchor; a panel of real type is centred and reaches
            // half its height down, so the version printed through the word.
            val drop = maxOf(STAMP_DROP, (hero?.dropM ?: 0f) + STAMP_GAP)
            it.setPose(Pose(Vector3(at.x, at.y - drop, at.z)), Space.ACTIVITY)
            Log.i(TAG, "[boot] stamp %.3fm below the anchor (hero drops %.3fm)"
                .format(drop, hero?.dropM ?: 0f))
            entities += it
        }

        // THE MARK, above the wordmark, forming a banner lockup: mark, then
        // name, then the vessel it is filling.
        val markAt = Vector3(at.x, at.y + markUp, at.z)
        core = MeshEntity.create(
            session,
            // rings=2, seg=4 is a sphere so coarse it IS an octahedron, which
            // is what the icon's central diamond becomes in three dimensions.
            Prims.build(session, Prims.mote(CORE_R, rings = 2, seg = 4)),
            listOf(Prims.material(session, theme.accent, 0.95f)),
        ).also {
            it.parent = root
            it.setPose(Pose(markAt), Space.ACTIVITY)
            entities += it
        }
        val coreEntity = core
        if (coreEntity != null) {
            // SIGNAL RINGS. Two, at different radii, lying flat — seen in
            // perspective from the wearer's eye they read as the concentric
            // rings of the 2D mark, which is what the icon draws.
            listOf(RING_A to 0.0035f, RING_B to 0.0026f).forEach { (rad, tube) ->
                MeshEntity.create(
                    session, Prims.build(session, Prims.halo(rad, tube, 32, 5)),
                    listOf(Prims.material(session, theme.accent, 0.55f)),
                ).also {
                    it.parent = coreEntity
                    it.setPose(Pose(Vector3(0f, 0f, 0f)), Space.PARENT)
                    entities += it
                }
            }
            // THREE LINKED SATELLITES, the mark's other half. Three because the
            // icon has three and because three is the smallest number that
            // reads as a network rather than as a pair.
            repeat(SATS) { i ->
                val a = 2.0 * PI * i / SATS
                val x = (cos(a) * RING_A).toFloat()
                val z = (sin(a) * RING_A).toFloat()
                MeshEntity.create(
                    session, Prims.build(session, Prims.mote(SAT_R, 5, 8)),
                    listOf(Prims.material(session, theme.alt, 0.9f)),
                ).also {
                    it.parent = coreEntity
                    it.setPose(Pose(Vector3(x, 0f, z)), Space.PARENT)
                    entities += it
                }
                MeshEntity.create(
                    session, Prims.build(session, Prims.spur(0f, 0f, 0f, x, 0f, z, 0.0022f)),
                    listOf(Prims.material(session, theme.alt, 0.45f)),
                ).also {
                    it.parent = coreEntity
                    it.setPose(Pose(Vector3(0f, 0f, 0f)), Space.PARENT)
                    entities += it
                }
            }
        }

        // VESSEL. A cage, not a solid: on an additive display a filled tube
        // would wash out everything behind it, and the point is to watch the
        // level rise inside.
        val cageMat = Prims.material(session, theme.accent, 0.35f)
        listOf(0f, VESSEL_H).forEach { y ->
            MeshEntity.create(
                session, Prims.build(session, Prims.halo(RADIUS, 0.004f, 24, 4)), listOf(cageMat),
            ).also {
                it.parent = root
                it.setPose(Pose(Vector3(at.x, at.y - VESSEL_DROP + y, at.z)), Space.ACTIVITY)
                entities += it
            }
        }
        for (i in 0 until STAVES) {
            val a = 2.0 * PI * i / STAVES
            val x = (cos(a) * RADIUS).toFloat()
            val z = (sin(a) * RADIUS).toFloat()
            MeshEntity.create(
                session,
                Prims.build(session, Prims.spur(0f, 0f, 0f, 0f, VESSEL_H, 0f, 0.003f)),
                listOf(cageMat),
            ).also {
                it.parent = root
                it.setPose(Pose(Vector3(at.x + x, at.y - VESSEL_DROP, at.z + z)), Space.ACTIVITY)
                entities += it
            }
        }

        // FLUID, not a stepped bar. The level RISES CONTINUOUSLY: one bright
        // meniscus ring at the surface plus fainter rings beneath it that move
        // with it, which on an additive display reads as a body of liquid
        // without filling the tube with light and hiding the room behind it.
        val fillMat = Prims.material(session, theme.alt, 0.85f)
        meniscus = MeshEntity.create(
            session, Prims.build(session, Prims.halo(RADIUS * 0.86f, 0.007f, 28, 4)), listOf(fillMat),
        ).also {
            it.parent = root
            it.setPose(Pose(Vector3(at.x, at.y - VESSEL_DROP, at.z)), Space.ACTIVITY)
            entities += it
        }
        val bodyMat = Prims.material(session, theme.alt, 0.28f)
        repeat(BODY_RINGS) {
            MeshEntity.create(
                session, Prims.build(session, Prims.halo(RADIUS * 0.80f, 0.004f, 20, 4)), listOf(bodyMat),
            ).also {
                it.parent = root
                it.setEnabled(false)
                body += it
                entities += it
            }
        }

        // PARTICLES. A continuous stream falling in, each on its own phase, so
        // the vessel always looks like it is being fed. They are the only thing
        // that moves when the radio announces no total -- an honest "working"
        // with no invented level under it.
        // ONE MATERIAL PER ENTITY. A single material shared across the
        // particles is released by whichever one is disposed first, while the
        // rest still borrow it, and the renderer aborts in native code — see
        // the note on Horizon's hit proxy for the message it prints.
        repeat(PARTICLES) {
            MeshEntity.create(
                session, Prims.build(session, Prims.mote(0.010f, 4, 6)),
                listOf(Prims.material(session, theme.alt, 0.9f)),
            ).also {
                it.parent = root
                motes += it
                entities += it
            }
        }
        Log.i(TAG, "[boot] surface up: ${entities.size} entities")
    }

    /**
     * Drive it. [fraction] is real progress 0..1; [active] false starts the
     * teardown. Called from the same frame loop as everything else.
     */
    /**
     * A CLOCK, NOT A FRAME COUNT.
     *
     * This used to take `dt` from the caller, which passed a hardcoded 0.033f —
     * thirty frames a second, asserted rather than measured. Every duration on
     * this surface was therefore in FRAMES wearing the units of seconds, and
     * the error is not small: the emulator runs the loop at about ten frames a
     * second, so a 1.8s beam took five real seconds there, while the glasses
     * run faster than thirty and fired the same beam in under one. The
     * operator's report was "nothing new" — the animation had finished before
     * anyone could look at it.
     *
     * Real elapsed time, clamped so a stalled frame cannot teleport the
     * choreography. SPIN_DPS is now honestly degrees per second, and the
     * vessel's ease is honestly per-second too.
     */
    fun tick(fraction: Float, hasTotal: Boolean) {
        val now = android.os.SystemClock.uptimeMillis()
        val dt = if (lastTickMs == 0L) 0f else ((now - lastTickMs) / 1000f).coerceIn(0f, 0.25f)
        lastTickMs = now
        t += dt
        // The hero repaints against elapsed time; it creates nothing here.
        hero?.tick(t)

        // THE MARK TURNS, AND IT MAY TURN ALL THE WAY.
        //
        // The wordmark below it oscillates rather than revolves, because stroke
        // glyphs are flat and a letterform seen edge-on collapses to a bright
        // line. The mark has no such problem: it is a solid with rings around
        // it, and it reads from every angle — which is the whole reason the
        // icon was built as geometry rather than as artwork.
        //
        // Tilted off the vertical so the rings are seen in perspective and not
        // as a line, and slow enough to be ambient rather than a spinner
        // demanding to be watched.
        runCatching {
            core?.setPose(
                Pose(
                    Vector3(at.x, at.y + markUp, at.z),
                    Quaternion.fromEulerAngles(MARK_TILT, t * SPIN_DPS, 0f),
                ),
                Space.ACTIVITY,
            )
        }

        // The wordmark's own swing and breath moved to PlainWordmark, which is
        // the hero every theme without one still gets. It is the same motion,
        // driven from the same clock — see Hero.kt.

        // Ease toward real progress rather than snapping. Contacts arrive in
        // bursts, and a level that jumps in steps reads as a progress bar
        // wearing a costume; a level that flows reads as filling.
        val target = if (hasTotal) fraction else 0f
        level += (target - level) * (dt * 3.2f).coerceAtMost(1f)

        val base = at.y - VESSEL_DROP
        val surfaceY = base + VESSEL_H * level
        meniscus?.setPose(Pose(Vector3(at.x, surfaceY, at.z)), Space.ACTIVITY)
        meniscus?.setEnabled(hasTotal)

        // Body rings sit under the surface and are revealed as depth allows.
        body.forEachIndexed { i, r ->
            val y = surfaceY - (i + 1) * BODY_GAP
            val visible = hasTotal && y > base
            r.setEnabled(visible)
            if (visible) r.setPose(Pose(Vector3(at.x, y, at.z)), Space.ACTIVITY)
        }

        // Particles fall from above into the surface, each offset so the stream
        // is continuous rather than pulsing in lockstep.
        val top = base + VESSEL_H + 0.10f
        motes.forEachIndexed { i, m ->
            val phase = ((t / DROP_PERIOD) + i.toFloat() / PARTICLES) % 1f
            val y = top - (top - surfaceY) * phase
            val a = 2.0 * PI * (i * 2.39f)          // golden-angle scatter
            val rr = RADIUS * 0.55f * ((i % 3) + 1) / 3f
            m.setPose(
                Pose(Vector3(at.x + (cos(a) * rr).toFloat(), y, at.z + (sin(a) * rr).toFloat())),
                Space.ACTIVITY,
            )
            // Fade in on entry and out as it merges with the surface, so a
            // particle never visibly pops out of existence at the meniscus.
            m.setAlpha(0.9f * kotlin.math.min(1f, (1f - phase) * 3f) * kotlin.math.min(1f, phase * 6f))
        }
    }

    fun clear() {
        entities.forEach { runCatching { it.dispose() } }
        entities.forEach { runCatching { it.parent = null } }
        entities.clear(); body.clear(); motes.clear()
        // THE HERO UNMAKES ITSELF. Its entities were never on `entities` —
        // one surface, one owner, which is the rule HALO broke when it left
        // ring handles on a list clear() did not empty and then posed them.
        hero?.clear(); hero = null
        lastTickMs = 0L
        meniscus = null; core = null; level = 0f
    }

    private companion object {
        const val TAG = "MeshmoreXR"
        /**
         * Above eye level but INSIDE the FOV. At 2 m forward, height h subtends
         * atan(h/2): the original 0.95 put the wordmark 25 deg up, well past
         * the Aura's 17 deg half-height, so the vessel was clipped at the top
         * of the frame and the wordmark was off-screen entirely. 0.50 puts the
         * wordmark at 14 deg and the vessel between 0 and 12 -- clear of the
         * horizon ring below, and wholly visible.
         */
        const val HEIGHT = 0.50f
        const val FORWARD = 2.0f
        const val CAP = 0.115f

        /** The build stamp, a quarter the wordmark's size and well under it. */
        const val STAMP_SCALE = 0.26f
        const val STAMP_DROP = 0.075f
        /** Clear air between the hero's lowest ink and the build stamp. */
        const val STAMP_GAP = 0.035f
        const val RADIUS = 0.16f
        const val VESSEL_H = 0.42f
        const val VESSEL_DROP = 0.50f

        /** The lockup: mark above, name below, vessel under both. */
        /**
         * Raised from 0.34 when the wordmark became real type. A stroke
         * wordmark was one cap tall; a panel of the same cap height is twice
         * that, because a rasterised line carries its leading with it. At 0.34
         * the mark's outer ring sat 0.155 above the anchor and the new
         * wordmark reached 0.228 — they overlapped, which a capture showed
         * before anybody had to notice it on glass.
         */
        const val MARK_UP = 0.46f
        /** Clear air between the hero's highest ink and the mark's outer ring. */
        const val MARK_GAP = 0.09f
        const val CORE_R = 0.055f
        const val RING_A = 0.135f
        const val RING_B = 0.185f
        const val SAT_R = 0.024f
        const val SATS = 3

        /**
         * 18 deg/s and a 22-degree tilt.
         *
         * The tilt is what makes the rings read as rings rather than as a line
         * seen edge-on, and the rate is deliberately below the threshold where
         * a turning object starts to feel like a progress indicator — the
         * vessel is the progress indicator, and it is showing a real fraction.
         */
        const val SPIN_DPS = 18f
        const val MARK_TILT = 22f
        const val STAVES = 8
        const val BODY_RINGS = 5
        const val BODY_GAP = 0.045f
        const val PARTICLES = 14
        const val SWING_DEG = 38f
        const val SWING_RATE = 0.55f
        const val DROP_PERIOD = 0.9f
    }
}
