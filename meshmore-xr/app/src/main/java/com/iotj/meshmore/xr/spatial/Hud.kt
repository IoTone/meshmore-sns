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
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.tan

/**
 * THE MICROHUD — the only head-locked surface in the app.
 *
 * Everything else is in the room. This is the exception, and it earns it by
 * answering the one question the horizon cannot: which way am I facing. A
 * bearing ring is useless without a compass, because "that node is at 040" only
 * means something if you know where 040 is from here.
 *
 * It lives in two thin bands at the top and bottom of the FOV, deliberately
 * outside the world window so it never covers what you are looking at
 * (AiRspace-HUD-and-symbology.md §4):
 *
 *   compass ribbon   +11.9 deg .. +15.1 deg
 *   world window     +/-10.0 deg          <- kept clear
 *   node stats       -12.2 deg .. -14.8 deg
 *   safe area        +/-15.5 deg
 *
 * THE MAPPING IS TANGENT, NOT LINEAR. Screen offset for a bearing is
 *
 *     x = D * tan(bearing - headYaw)
 *
 * The tempting linear form -- offset proportional to angle -- agrees at centre
 * and at the FOV edge and is wrong by 8-10% of half-width in between, which is
 * exactly where the ticks are. A compass whose ticks do not sit over their
 * bearings is decoration. The prototype's Hud.js has this bug; this does not.
 */
class Hud(private val session: Session, private val theme: Horizon.Palette) {

    private val entities = mutableListOf<Entity>()
    private val minors = mutableListOf<MeshEntity>()
    private val majors = mutableListOf<Pair<Int, MeshEntity>>()   // bearing deg -> entity
    private var status: MeshEntity? = null

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        val mat = Prims.material(session, theme.accent, 0.75f)
        val matDim = Prims.material(session, theme.accent, 0.42f)

        // Minor ticks are identical, so a POOL is enough: only about a dozen
        // are ever on screen and which bearings they represent changes every
        // time the head turns. Pre-building all 72 would be 60 entities kept
        // permanently disabled for nothing.
        repeat(MINOR_POOL) {
            MeshEntity.create(
                session, Prims.build(session, Prims.bar(TICK_W, MINOR_H, TICK_W)), listOf(matDim),
            ).also { it.parent = root; it.setEnabled(false); minors += it; entities += it }
        }

        // Majors carry their own bearing text, so they cannot be pooled -- each
        // is built once for its own heading. Cardinals fold in here rather than
        // forming a second set: N/E/S/W are multiples of 15 too, and one ribbon
        // of marks reads better than two interleaved ones.
        for (b in 0 until 360 step MAJOR_STEP) {
            val f = Prims.Facets()
            f.addTranslated(Prims.bar(TICK_W, MAJOR_H, TICK_W), 0f, 0f, 0f)
            val label = CARDINALS[b] ?: "%03d".format(b)
            f.addTranslated(
                Glyphs.text(label, LABEL_CAP), 0f, -(MAJOR_H / 2f + LABEL_CAP * 1.1f), 0f,
            )
            MeshEntity.create(session, Prims.build(session, f), listOf(mat)).also {
                it.parent = root; it.setEnabled(false); majors += b to it; entities += it
            }
        }
        Log.i(TAG, "[hud] built ${entities.size} entities")
    }

    /**
     * Re-place the ribbon for the current head pose. Called every frame: a
     * head-locked surface that lags is worse than none, because the lag is
     * read as the world sliding.
     */
    fun tick(head: Pose) {
        val yaw = yawOf(head)
        val pitch = pitchOf(head)
        val t = head.translation

        // PITCH IS PART OF THE LOCK. The bands were yaw-locked but pinned to a
        // fixed WORLD HEIGHT, which is not the same as being pinned to the
        // view. Tip your head down and the FOV moves while the bands stay put,
        // so they ride up out of their reserved strips: the link readout ended
        // up across the middle of the scene, printing through node callsigns,
        // while the compass ribbon left the top of the display entirely. The
        // bands are supposed to be the two edges of the view -- compass above,
        // link below -- and that only holds if they follow where the view is
        // actually pointing.
        //
        // ROLL IS DELIBERATELY EXCLUDED. Tilting your head should not tilt the
        // instrument; a horizon that rolls with the head is the classic way to
        // make an HMD nauseating. Yaw and pitch, nothing else.
        val cp = cos(pitch)
        val sp = sin(pitch)

        // Local (x, y, -D) in the head's yaw+pitch frame -> activity space.
        //
        // THE ROTATION IS -yaw, NOT +yaw. The HUD is a sheet of glass in front
        // of the face: its normal must point back AT the head, which is the
        // reverse of the head's own forward axis. Using +yaw orients it the
        // same way the head faces -- i.e. edge-on-to-mirrored, off by 2*yaw --
        // so the ticks and numerals counter-rotate as you turn, twice as fast
        // and the wrong way. It is invisible on the bench because the error
        // vanishes at yaw 0, which is exactly where a recentred app starts.
        //
        // Every mark shares this one rotation rather than each turning toward
        // the head from its own position. That is deliberate: a HUD is PAINTED
        // ON THE GLASS. Per-mark billboarding would fan the ribbon outward at
        // the edges, and the numerals would visibly swivel as they slid across
        // -- motion that means nothing, on the one surface that must be dead
        // still for the world behind it to be readable.
        //
        // The tilt is composed as (yaw * pitch) rather than written as a single
        // Euler triple: the yaw term is empirically verified against the horizon
        // billboards, and multiplying a local-X rotation onto its RIGHT applies
        // the pitch in the entity's own frame, which is well-defined whatever
        // this library's Euler ORDER turns out to be. Guessing an Euler
        // convention that happens to agree at zero is how the +yaw bug survived.
        val face = Quaternion.fromEulerAngles(0f, -Math.toDegrees(yaw.toDouble()).toFloat(), 0f) *
            Quaternion.fromAxisAngle(Vector3(1f, 0f, 0f), Math.toDegrees(pitch.toDouble()).toFloat())

        // The head's flat basis. Everything is placed as
        //     head + x*right + y'*up + z'*forward
        // with (y, -D) rotated by pitch about `right` first, so a band at -13.5
        // deg stays at -13.5 deg of the VIEW rather than of the world.
        fun place(e: Entity, x: Float, y: Float) {
            val fwdX = sin(yaw); val fwdZ = -cos(yaw)
            val rgtX = cos(yaw); val rgtZ = sin(yaw)
            val up = y * cp + D * sp
            val fwd = D * cp - y * sp
            e.setPose(
                Pose(
                    Vector3(t.x + x * rgtX + fwd * fwdX, t.y + up, t.z + x * rgtZ + fwd * fwdZ),
                    face,
                ),
                Space.ACTIVITY,
            )
        }

        var slot = 0
        var bearing = 0
        while (bearing < 360) {
            val d = wrapDeg(bearing - Math.toDegrees(yaw.toDouble()).toFloat())
            if (abs(d) <= SAFE_H_DEG) {
                val x = D * tan(Math.toRadians(d.toDouble())).toFloat()
                if (bearing % MAJOR_STEP == 0) {
                    majors.firstOrNull { it.first == bearing }?.second?.let {
                        it.setEnabled(true); place(it, x, RIBBON_Y)
                    }
                } else if (slot < minors.size) {
                    minors[slot].let { it.setEnabled(true); place(it, x, RIBBON_Y) }
                    slot++
                }
            } else if (bearing % MAJOR_STEP == 0) {
                majors.firstOrNull { it.first == bearing }?.second?.setEnabled(false)
            }
            bearing += MINOR_STEP
        }
        for (i in slot until minors.size) minors[i].setEnabled(false)

        status?.let { place(it, 0f, STATS_Y) }
    }

    /**
     * The link readout: connection, battery, and how much of the mesh we hold.
     * Rebuilt only when the TEXT changes -- once a second at most -- because
     * rebuilding a mesh every frame to move three characters is how a HUD eats
     * a frame budget.
     */
    suspend fun setStatus(text: String) {
        if (text == lastStatus) return
        lastStatus = text
        runCatching { status?.let { entities.remove(it); (it as Entity).dispose() } }
        status = MeshEntity.create(
            session, Prims.build(session, Glyphs.text(text, STATS_CAP)),
            listOf(Prims.material(session, theme.alt, 0.8f)),
        ).also { it.parent = session.scene.activitySpace; entities += it }
    }

    private var lastStatus: String? = null

    fun clear() {
        entities.forEach { runCatching { it.parent = null } }
        entities.forEach { runCatching { it.dispose() } }
        entities.clear(); minors.clear(); majors.clear()
        status = null; lastStatus = null
    }

    private fun yawOf(p: Pose): Float {
        val q = p.rotation
        val fx = 2f * (q.x * q.z + q.w * q.y)
        val fz = 1f - 2f * (q.x * q.x + q.y * q.y)
        return atan2(-fx, fz)
    }

    /**
     * Elevation of the head's forward axis: + is looking up. Taken from the
     * forward VECTOR rather than from an Euler decomposition, so head roll
     * cannot leak into it.
     */
    private fun pitchOf(p: Pose): Float {
        val q = p.rotation
        val fy = -2f * (q.y * q.z - q.w * q.x)
        return asin(fy.coerceIn(-1f, 1f))
    }

    /** Shortest signed difference, so the ribbon does not tear at north. */
    private fun wrapDeg(d: Float): Float {
        var x = d % 360f
        if (x > 180f) x -= 360f
        if (x < -180f) x += 360f
        return x
    }

    private companion object {
        const val TAG = "MeshmoreXR"
        /** HUD plane distance. Everything angular is evaluated here. */
        const val D = 1.05f
        const val SAFE_H_DEG = 28f
        /** Ribbon centre: +13.5 deg, mid-band of +11.9..+15.1. */
        const val RIBBON_Y = 0.252f
        /** Stats centre: -13.5 deg. */
        const val STATS_Y = -0.252f
        const val MINOR_STEP = 5
        const val MAJOR_STEP = 15
        const val MINOR_POOL = 16
        const val TICK_W = 0.004f
        const val MINOR_H = 0.014f
        const val MAJOR_H = 0.026f
        const val LABEL_CAP = 0.021f
        const val STATS_CAP = 0.020f
        val CARDINALS = mapOf(0 to "N", 90 to "E", 180 to "S", 270 to "W")
    }
}
