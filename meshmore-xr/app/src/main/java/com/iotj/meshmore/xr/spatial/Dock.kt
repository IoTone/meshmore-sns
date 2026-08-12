// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.util.Log
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Quaternion
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.InputEvent
import androidx.xr.scenecore.InteractableComponent
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene

/**
 * THE DOCK — how a surface gets summoned, and the only thing that is always on.
 *
 * The problem it answers, seen on hardware: the RADIO rack left standing in the
 * room is a live radio configuration sitting in the space you gesture in. Eleven
 * controls, four of which can strand the hardware, permanently one stray pinch
 * away while you are doing something else. Every other surface is safe to leave
 * around because reading the mesh cannot change it. Settings are not.
 *
 * So settings are SUMMONED. The dock is the summoning: a short row of pips, each
 * standing for a surface, low and off to the side where you have to go to it.
 *
 * WHAT THIS IS A DOWNPAYMENT ON. The design brief owes a back-of-hand menu, and
 * that is where these pips belong — anchored to the wrist, hidden until you turn
 * your hand over, which is the most deliberate "open settings" gesture available
 * and costs no world space at all. The Aura reports hand tracking, so the anchor
 * is reachable; what is not yet built is the palm-facing test and the wrist
 * pose. Until then the pips live at a fixed body-locked spot.
 *
 * The INTERACTION is the part that transfers, and it is deliberately identical
 * to what the hand menu will need: a pip is a target you pinch, it toggles one
 * surface, and exactly one surface is open at a time. Moving that to the wrist
 * later changes where the pips are and nothing else.
 */
class Dock(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: android.content.Context,
) {

    private var headAt: Vector3? = null

    /**
     * The pip the GAZE is resting on, if any. Folded into focus alongside the
     * pointers so a dwelled pip swells and shows its caption exactly as a
     * pointed-at one does — without it, dwell fires a control whose name the
     * user never saw, which is worse on a row of icons than on a row of words.
     */
    var gazed: String? = null

    /**
     * Face the caption at the viewer, in YAW AND PITCH.
     *
     * The dock sits about 30 degrees below eye level, so it is looked at from
     * above — and a vertical quad seen from 30 degrees above foreshortens to a
     * sliver. That is what "the labels are empty, cut off near the top of the
     * text" was: not empty and not clipped, but edge-on.
     *
     * Yaw alone is not enough here, which is the difference from the microhud.
     * The microhud is at eye level and only ever turned about; the dock is
     * BELOW you, so the pitch term is the whole problem.
     */
    private fun facing(at: Vector3): Quaternion {
        val h = headAt ?: return Quaternion.fromEulerAngles(0f, 0f, 0f)
        val dx = h.x - at.x
        val dy = h.y - at.y
        val dz = h.z - at.z
        val flat = kotlin.math.sqrt(dx * dx + dz * dz)
        if (flat < 1e-5f) return Quaternion.fromEulerAngles(0f, 0f, 0f)
        val yaw = Math.toDegrees(kotlin.math.atan2(dx, dz).toDouble()).toFloat()
        val pitch = Math.toDegrees(kotlin.math.atan2(dy, flat).toDouble()).toFloat()
        // Yaw about world Y, then pitch about the panel's own X — composed
        // rather than written as an Euler triple, for the reason the microhud
        // and the rack both learned: this library's Euler ORDER is not the one
        // the argument names suggest.
        //
        // The pitch is NEGATED, and that sign was settled by looking at it, not
        // by reasoning about it. The first build tilted the caption further away
        // from the eye instead of toward it, which on screen is the same symptom
        // as no rotation at all — a sliver — and is why deriving this in a
        // comment has been wrong four times in this project.
        return Quaternion.fromEulerAngles(0f, yaw, 0f) *
            Quaternion.fromAxisAngle(Vector3(1f, 0f, 0f), -pitch)
    }

    private val captions = HashMap<String, TextRun.Run>()
    private val entities = mutableListOf<Entity>()
    private val pips = mutableListOf<Pip>()
    private val fired = java.util.concurrent.ConcurrentLinkedQueue<Pip>()

    private inner class Pip(
        val name: String,
        val mark: Entity,
        /**
         * Where the pip sits RIGHT NOW.
         *
         * A var, because on a worn dock it moves. It was a val, and everything
         * that is not the mark itself reads it: [pipAt], which is the point
         * every surface in the app rises from, and [gazeTargets], which is the
         * dwell fallback's aim. So the marks rode the forearm while the dock's
         * IDEA of where they were stayed on the floor at the launch origin —
         * gaze aimed at empty ground, and picking SETUP opened the console out
         * in front of wherever the wearer had been facing at launch rather than
         * above the arm they just pinched.
         *
         * Two reported bugs, one stale field.
         */
        var at: Vector3,
        var captionAt: Vector3,
        val toggle: () -> Unit,
    ) {
        /**
         * The hit volume, kept so it can TRAVEL with the mark.
         *
         * It used to be created inline and never referenced again, which is
         * fine for a dock nailed to one spot and wrong the moment the dock
         * rides a wrist: the marks would follow the arm and the things you
         * actually pinch would stay behind in the room.
         */
        var proxy: MeshEntity? = null

        /** Push [hot] and [lit] onto the mark. The only place either is drawn. */
        fun apply() {
            runCatching {
                mark.setScale(if (hot) HOT_SCALE else 1f)
                mark.setAlpha(if (lit) 1f else if (hot) 0.95f else MARK_DIM)
            }
        }

        var lastFire = 0L
        var lit = false
        /** Which pointers are on it. BOTH hands emit rays, hence a set. */
        val pointers = mutableSetOf<String>()
        var hot = false
        var exitAt = 0L
    }

    /** Raised when a pip takes focus. The host makes the sound. */
    var onFocus: ((String) -> Unit)? = null

    suspend fun build(o: Stage.Origin, items: List<Pair<String, () -> Unit>>) {
        clear()
        val root = session.scene.activitySpace

        // LOW AND FORWARD, at about -30 degrees. Far enough down that it is never
        // in the world window or under the microhud, close enough that finding it
        // is one glance rather than a search. You look DOWN for settings, which
        // is the same place the HERE marker lives and the same place a wrist
        // would be.
        val base = o.place(0f, REACH, DROP)

        items.forEachIndexed { i, (name, act) ->
            val x = (i - (items.size - 1) / 2f) * PITCH
            val at = Vector3(base.x + x, base.y, base.z)

            // THE MARK IS THE PIP. One object: silhouette says WHICH control,
            // scale says focus, brightness says whether its surface is open.
            //
            // There used to be a ring here with the mark inside it, and it could
            // not work. A PanelEntity writes depth across its whole quad, so the
            // mark's transparent margin punched a hole in the ring behind it and
            // every pip came out as a bright annulus with a dark square bitten
            // out of the middle. This is the same additive-display rule the hit
            // proxies already obey: on this display transparent is not the same
            // as absent, and only Prims.ghost's alpha-mask material makes it so.
            //
            // Losing the ring costs nothing the marks do not carry better. It
            // existed to say "a pip is not a node"; a flat line drawing says
            // that more plainly than a torus did, since every other thing in
            // the scene is extruded geometry.
            val mark: Entity = Marks[name]?.let { path ->
                AslIcon.fromPath(
                    session, context, path, MARK, argb(theme.accent, 1f),
                    stroked = true, padPx = MARK_PAD, name = "mark-$name",
                )
            } ?: MeshEntity.create(
                // Nobody drew this one. A ring is the honest fallback: visibly
                // a control, visibly not identified, rather than nothing.
                session, Prims.build(session, Prims.halo(R, R * 0.22f)),
                listOf(Prims.material(session, theme.alt, 0.75f)),
            )
            mark.parent = root
            mark.setPose(Pose(at), Space.ACTIVITY)
            runCatching { mark.setAlpha(MARK_DIM) }
            entities += mark

            // THE NAME STAYS UP. A dock you have to hover to identify is a
            // dock you learn by poking it, and seven unlabelled rings are a
            // guessing game — which is what these were, because they were sized
            // wrong rather than because a label could not fit.
            //
            // The old sizing reserved 18 characters ("IN +9999 NNE 999KM") for
            // a future magnified-area readout that was never built. At 0.137 m
            // against a 0.075 m pip pitch every caption overlapped both its
            // neighbours no matter how short the word was, and hiding all but
            // the focused one was the workaround for that.
            //
            // What a pip can actually say is its own name or a short state
            // string — COMPASS is the longest at 7, "OUT x99" also 7. Eight
            // cells is 0.063 m, which clears the pitch, and a shorter word just
            // carries transparent margin that emits nothing on this display.
            //
            // If a genuinely long readout is wanted later it does not belong in
            // this row: it wants its own line below the dock, where it can be as
            // wide as it likes without pushing the names around.
            TextRun.reusable(
                session, context, CAPTION_WIDEST, CAP, argb(theme.alt, 0.95f), "dock-caption",
            )?.also {
                captions[name] = it
                it.entity.parent = root
                it.setText(name)
                it.entity.setEnabled(false)
                entities += it.entity
            }

            val pip = Pip(name, mark, at, Vector3(at.x, at.y - R * 2.4f, at.z), act)
            pips += pip

            // Hit proxy, same reasoning as everywhere else: the thing you point
            // at is deliberately bigger than the thing you see, and alpha 0.02
            // rather than 0 so the renderer cannot decide to skip it.
            MeshEntity.create(
                session, Prims.build(session, Prims.mote(R * 2.0f, 5, 8)),
                listOf(Prims.ghost(session)),
            ).also {
                it.parent = root; it.setPose(Pose(at), Space.ACTIVITY)
                entities += it
                pip.proxy = it
                runCatching {
                    it.addComponent(InteractableComponent.create(session) { ev -> onInput(pip, ev) })
                }.onFailure { e -> Log.w(TAG, "[dock] no input on $name: $e") }
            }
        }
        Log.i(TAG, "[dock] ${pips.size} pip(s) up")
    }

    /**
     * The pips as GAZE TARGETS, for the dwell fallback (§8.2).
     *
     * The dock is wired first because it is the summon surface — everything
     * else in the app is reached through it — and because it sits 30 degrees
     * below eye level, which is not somewhere a gaze rests by accident.
     *
     * Firing goes through the same queue a pinch uses, so a dwelled pip and a
     * pinched one take exactly the same path and cannot drift apart.
     */
    /** Where a pip sits, for a surface that needs to grow out of one. */
    fun pipAt(name: String): Vector3? = pips.firstOrNull { it.name == name }?.at

    fun gazeTargets(): List<Gaze.Target> = pips.map { p ->
        Gaze.Target(p.name, p.at, CONE) { fired.add(p) }
    }

    /**
     * Rename a pip. This is the anchor for magnified navigation: the dock is
     * the one surface that is always present, so it is the only place a "you
     * are here" can live without competing with the ring for space.
     */
    /**
     * Give a pip something other than its own name to say. Null restores it.
     *
     * Used for state a pip carries that the user has to see without pointing at
     * it — the magnification depth, which is a "you are here" and would be
     * useless if you had to go and ask. It no longer pins anything visible:
     * every caption is visible.
     */
    fun setCaption(name: String, caption: String?) {
        captions[name]?.let { c ->
            // The words change; the label does not come and go. An override
            // that appeared and vanished was readable only as "something just
            // happened here", which is not what a state readout is for.
            runCatching { c.setText(caption ?: name) }
        }
    }

    /** Light the pip for whichever surface is open; dark for the rest. */
    fun setLit(name: String, lit: Boolean) {
        pips.firstOrNull { it.name == name }?.let { it.lit = lit; it.apply() }
    }

    private fun onInput(p: Pip, ev: InputEvent) {
        val key = ev.pointerType.toString()
        when (ev.action) {
            InputEvent.Action.HOVER_ENTER, InputEvent.Action.HOVER_MOVE -> p.pointers += key
            InputEvent.Action.HOVER_EXIT -> {
                p.pointers -= key
                p.exitAt = android.os.SystemClock.uptimeMillis()
            }
            InputEvent.Action.UP -> {
                val now = android.os.SystemClock.uptimeMillis()
                if (now - p.lastFire < DEBOUNCE_MS) return
                p.lastFire = now
                Reach.consumed()
                fired.add(p)
            }
            else -> Unit
        }
    }

    /**
     * FOCUS, reconciled per frame rather than from the events themselves.
     *
     * A pip you cannot tell you are pointing at is a pip you aim by trial: you
     * pinch, nothing happens, and you cannot tell whether you missed or whether
     * the control is dead. Focus answers that before the pinch.
     *
     * Reconciled with a grace period because hand tracking drops HOVER_EXIT and
     * re-enters constantly at the edge of a target — driving the visual straight
     * from events makes it strobe.
     */
    private fun reconcileFocus() {
        val now = android.os.SystemClock.uptimeMillis()
        // Aim EVERY caption, every frame. They are all standing now, so a
        // caption that is only re-posed when its focus changes would be left
        // edge-on the moment the user moves.
        pips.forEach { p ->
            captions[p.name]?.let { c ->
                runCatching {
                    c.entity.setPose(Pose(p.captionAt, facing(p.captionAt)), Space.ACTIVITY)
                }
            }
        }
        pips.forEach { p ->
            val want = p.pointers.isNotEmpty() || p.name == gazed ||
                (p.hot && now - p.exitAt < GRACE_MS)
            if (want == p.hot) return@forEach
            p.hot = want
            // TWO CHANNELS ON ONE OBJECT, which is only safe because they are
            // orthogonal: SCALE means "you are pointing at this", BRIGHTNESS
            // means "this surface is open". A single object carrying two
            // STATES would be ambiguous; carrying two different QUESTIONS is
            // how a physical control works.
            runCatching { p.apply()  }
            // ONE CAPTION, AND ONLY ON FOCUS. This is not a retreat to the
            // pre-2026-08-02 behaviour: the objection then was that seven
            // identical rings carry no identity at rest, and the marks now do.
            //
            // It is also forced. At the §4.1 floor a caption is 9.6° of arc
            // against a 5.6° pip pitch, so seven at once cannot be legal AND
            // legible. Exactly one visible has no neighbour to collide with,
            // which is what lets it be the full word at full size.
            captions[p.name]?.let { c ->
                runCatching { c.entity.setEnabled(want) }
            }

            if (want) onFocus?.invoke(p.name)
        }
    }

    /** Drained on the frame loop — nothing opens a surface from an input callback. */
    /**
     * [head] in activity space. Needed because the caption is a PANEL and a
     * panel is a flat, one-sided quad — unlike every other thing in the dock,
     * which is extruded geometry that reads from any angle.
     */
    /**
     * WORN, NOT LAID ON THE FLOOR — the HALO variant.
     *
     * The dock's home is 66 cm forward and 38 cm down, which on glasses reads
     * as lying on the ground: you look at your feet to change a setting. For a
     * theme meant for a trail that is the wrong place twice over — it is in the
     * way of where you are walking, and it stays behind at the launch origin
     * the moment you walk on.
     *
     * So HALO wears it. Same joint maths the [Cuff] uses, and the same rule:
     * present whenever the arm is tracked, hidden the instant it is not. A dock
     * that outlived its arm would be a control panel floating in a field.
     *
     * WHY IT IS FOUR PIPS AND NOT EIGHT. At 66 cm the row spans 53 degrees —
     * already wider than the 34-degree window, which is why it sprawls. A wrist
     * is ~35 cm from the eye and pinch targets need about 5 degrees of
     * separation to be distinguishable by hand, so a pip costs 3.1 cm of
     * forearm. Eight would want a quarter of a metre of arm. Four fit, with the
     * rest one pinch away behind SETUP.
     */
    fun tickWrist(joints: Map<androidx.xr.arcore.HandJointType, Pose>?) {
        if (joints.isNullOrEmpty()) {
            pips.forEach { p -> runCatching { p.mark.setEnabled(false); p.proxy?.setEnabled(false) } }
            return
        }
        val ps = session.scene.perceptionSpace
        fun act(t: androidx.xr.arcore.HandJointType): Vector3? = runCatching {
            ps.getScenePoseFromPerceptionPose(joints[t] ?: return null)
                .poseInActivitySpace.translation
        }.getOrNull()
        val w = act(androidx.xr.arcore.HandJointType.WRIST) ?: return
        val m = act(androidx.xr.arcore.HandJointType.MIDDLE_METACARPAL) ?: return
        // The forearm axis, running back from the wrist toward the elbow — the
        // same direction the cuff sits along, so the two agree about where the
        // arm is rather than each deciding for themselves.
        var ax = w.x - m.x; var ay = w.y - m.y; var az = w.z - m.z
        val len = kotlin.math.sqrt(ax * ax + ay * ay + az * az)
        if (len < 1e-4f) return
        ax /= len; ay /= len; az /= len
        pips.forEachIndexed { i, p ->
            val d = WRIST_FIRST + i * WRIST_PITCH
            val at = Vector3(w.x + ax * d, w.y + ay * d, w.z + az * d)
            runCatching {
                p.mark.setEnabled(true)
                p.mark.setPose(Pose(at, facingHead(at)), Space.ACTIVITY)
                p.mark.setScale(WRIST_SCALE)
                p.proxy?.setEnabled(true)
                p.proxy?.setPose(Pose(at), Space.ACTIVITY)
                // The proxy is built for the floor dock's 8.3 cm spacing. Left
                // at that size on a 6 cm pitch it would still swallow its
                // neighbours, which is the whole defect being fixed here.
                p.proxy?.setScale(WRIST_PROXY_SCALE)
                // AND TELL THE REST OF THE APP. The mark moving is the visible
                // half; this is the half that makes it pointable and makes the
                // surfaces it opens rise from the arm.
                p.at = at
                // The caption hangs toward the wearer rather than below, since
                // "below" on a forearm is the wearer's own sleeve.
                p.captionAt = Vector3(at.x, at.y - R * 1.2f, at.z)
            }
        }
    }

    private fun facingHead(at: Vector3): Quaternion {
        val h = headAt ?: return Quaternion.fromEulerAngles(0f, 0f, 0f)
        val dx = h.x - at.x
        val dz = h.z - at.z
        if (dx * dx + dz * dz < 1e-6f) return Quaternion.fromEulerAngles(0f, 0f, 0f)
        return Quaternion.fromEulerAngles(
            0f, Math.toDegrees(kotlin.math.atan2(dx, dz).toDouble()).toFloat(), 0f,
        )
    }

    fun tick(head: Vector3? = null) {
        headAt = head
        reconcileFocus()
        while (true) {
            val p = fired.poll() ?: break
            Log.i(TAG, "[dock] ${p.name}")
            runCatching { p.toggle() }.onFailure { Log.w(TAG, "[dock] ${p.name} failed: $it") }
        }
    }

    fun clear() {
        pips.clear(); fired.clear(); captions.clear()
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private companion object {
        const val TAG = "MeshmoreXR"
        const val REACH = 0.66f
        /** -0.38 at 0.66 m is about -30 degrees: below everything, above the floor. */
        const val DROP = -0.38f
        const val R = 0.020f
        /**
         * Pip spacing. Widened with the marks: normalising their optical size
         * pulled the small ones UP, which closes the gaps a varied set was
         * getting for free. 0.083 m is 6.2° at the dock's 0.762 m, leaving a
         * gap between adjacent ink slightly wider than the ink itself.
         */
        const val PITCH = 0.083f
        /**
         * Caption cap height. 1.28° at the dock's 0.76 m — DERIVED from §4.1's
         * 1.2° floor, not chosen by eye. It was 0.011 m, which is 0.83°, and it
         * looked perfectly fine on the device; that is precisely why the rule is
         * written as an angle and not as a distance.
         */
        const val CAP = 0.017f
        /**
         * The mark, 3.0° at 0.76 m. Floor argued in Marks' header from the one
         * icon in this app whose legibility has actually been measured.
         */
        const val MARK = 0.042f
        /**
         * Margin inside the mark panel, in the 256 px raster — about 10 px a
         * side, which is what the row was asked for and what the measurement
         * said it did not have: the crosshair was reaching to 16 px and the
         * compass to 21, while the question mark sat at 82 and looked lost.
         * With bounds-fitting every mark now gets exactly this.
         */
        const val MARK_PAD = 12f
        /**
         * Gaze acceptance half-angle. 3.2 degrees — a little wider than a mark
         * itself, because a head is a coarse pointer and the pips are 6.2
         * degrees apart, so this cannot reach a neighbour.
         */
        const val CONE = 0.056f
        const val DIM = 0.18f
        /**
         * A mark at rest. Brighter than [DIM], which was tuned for the solid
         * lamp mote this replaced — the same alpha over a line drawing emits a
         * fraction of the light, because most of the mark is the space between
         * its strokes. Identity has to be readable without pointing at it, or
         * the marks are not doing the job the captions were retired for.
         */
        const val MARK_DIM = 0.55f

        /** Where the first pip sits along the forearm, back from the wrist. */
        const val WRIST_FIRST = 0.035f

        /**
         * THE SPACING WAS AT THE FLOOR, WHICH IS NOT THE SAME AS USABLE.
         *
         * The first cut used 3.4 cm — 5 degrees at a 35 cm wrist, exactly the
         * hand-separation floor — and it was reported cramped and unhittable.
         * Both, for the same reason: the HIT PROXY is a sphere of radius
         * R * 2.0 = 4 cm, so at 3.4 cm spacing each proxy overlapped its
         * neighbours by more than a whole slot and the raycast returned
         * whichever it reached first rather than the one being aimed at. A
         * floor is where a thing stops being possible, not where it starts
         * being good.
         *
         * A forearm is about 22 cm of usable length, so four pips fit at 6 cm
         * with room to spare: 0.035 + 3 x 0.060 = 0.215 m. At 35 cm that is
         * 9.8 degrees apart, twice the floor.
         */
        const val WRIST_PITCH = 0.060f

        /**
         * ...and the proxy shrinks to match, because the spacing only helps if
         * the targets stop overlapping. 2.2 cm radius is under half the pitch —
         * so no two ever touch — and still subtends 3.6 degrees at a wrist,
         * comfortably past the 2-degree floor for anything reached for.
         */
        const val WRIST_PROXY_SCALE = 0.55f

        /**
         * The mark itself. 0.042 m at 0.66 m is 3.6 degrees; the first cut
         * scaled it to hold that angle at a 35 cm wrist and got a pip so small
         * it read as a speck. With 6 cm of room there is no reason to be that
         * austere: 0.75 gives 5.1 degrees, well clear of the 3-degree icon
         * floor and actually visible on an arm in daylight.
         */
        const val WRIST_SCALE = 0.75f
        const val DEBOUNCE_MS = 350L
        const val GRACE_MS = 180L
        /** Enough swell to read at a glance, not so much it looks like a press. */
        const val HOT_SCALE = 1.35f
        /**
         * Sized once for the longest thing a caption ever says: a pip's own
         * name (COMPASS, 7) or a short state string ("OUT x99", 7). Eight cells
         * is 0.063 m against a 0.075 m pip pitch, so the row never collides.
         */
        const val CAPTION_WIDEST = "MMMMMMMM"
        /** Unfocused caption. Legible, but the focused one is plainly brighter. */
        const val CAPTION_DIM = 0.62f

        fun argb(rgb: Int, a: Float) =
            (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)
        /**
         * Hit proxies are meant to be reached for and not seen. 0.02 was chosen
         * so the renderer could not decide to skip a fully transparent entity —
         * but on an ADDITIVE display 2% of a bright accent still emits, and a
         * 4 cm sphere of it beside every pip read as a second, useless ring.
         * 0.004 is the smallest value observed to stay hit-tested.
         */
        const val PROXY_A = 0.004f
    }
}
