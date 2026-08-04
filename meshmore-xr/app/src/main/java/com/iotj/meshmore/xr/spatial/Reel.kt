// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.content.Context
import android.util.Log
import androidx.xr.arcore.HandJointType
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Quaternion
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.MeshEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * THE REEL — the last dozen messages, on the chat palm.
 *
 * §S4 splits reading into two jobs and puts them in two places. *Triage*
 * happens on the hand: "turn the chat palm up and the REEL appears — an oval
 * ring buffer of the last ~12 messages, rotated with thumb-along-index, ~5
 * legible across the front arc." *Reading* happens in FOCUS, which is the
 * thread corridor.
 *
 * A RING BUFFER THAT LOOKS LIKE ONE. §S4: "the reel is a view of the last N,
 * never the archive — the shape is a ring buffer and it says so honestly."
 * That is why it is a closed oval rather than a list: a list implies a top and
 * an end and invites scrolling toward an archive that does not exist here.
 * Older hands off to the thread.
 *
 * ONE MESSAGE READS AT A TIME, AND IT PROJECTS UP.
 *
 * The first build put five full messages across the front arc, as §S4's "~5
 * legible" was read to mean. On the glasses they collided with each other and
 * with the ring's own callsigns behind them: at a palm's distance a
 * sender-plus-text line is 0.19 m wide and the slots are 0.09 m apart, so five
 * of them is a pile. §4.1 forbids the obvious escape of shrinking the type.
 *
 * So the oval is a PANEL of markers and the SELECTED message lifts off it
 * toward the wearer, alone, at a size meant to be read. The front arc keeps
 * senders only — enough to choose by — and the words belong to whichever slot
 * is current. That is what the surface is for: triage is choosing, not
 * reading, and the reading happens either on the raised card or in the thread.
 *
 * HYSTERESIS IS MANDATORY, and §5 says why in as many words: reveal above 0.6,
 * hide below 0.45, because a single threshold makes the surface strobe as the
 * wrist hovers at the boundary and "flicker on a hand-anchored element is the
 * most nauseating failure mode available in XR". The gap is not tuning slack;
 * it is the feature.
 *
 * IT TURNS BOTH WAYS. Thumb toward the fingertip goes back in time, thumb
 * toward the knuckle comes forward, and the ring wraps, so any message is
 * reachable from any other in whichever direction is shorter.
 *
 * OWED: the per-message CROWN.
 */
class Reel(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    /**
     * One message, already formatted.
     *
     * [direct] and [origin] are what make a DM tellable from channel traffic.
     * §S4 requires the two to be "distinguished by form in every channel -- and
     * never by colour alone", which the ring answers with a RING: a direct
     * message gets a circle drawn round its marker, and channel traffic does
     * not. Circled means somebody addressed you, and it survives being seen at
     * the edge of vision, at five millimetres, by someone who cannot tell the
     * theme's two blues apart.
     */
    class Slot(
        val who: String,
        val words: String,
        val direct: Boolean = false,
        val origin: String = "",
    )

    private class Cell(val run: TextRun.Run, val mote: MeshEntity, val ring: MeshEntity)

    private val cells = mutableListOf<Cell>()
    /** The oval itself, so the slots read as sitting ON something. */
    private var panel: MeshEntity? = null
    /** The raised card: whichever slot is current, big enough to read. */
    private var stem: MeshEntity? = null
    private var hint: TextRun.Run? = null
    private var cardWho: TextRun.Run? = null
    private val cardBody = mutableListOf<TextRun.Run>()
    /**
     * How far the ring has been turned, in slots. Continuous, so the oval
     * moves with the thumb rather than jumping between detents — the snap is
     * for WHICH message is current, not for where the markers are drawn.
     */
    private var spin = 0f
    /** Clutch state: where the thumb was, and where the spin was, at contact. */
    private var grabT = 0f
    private var grabSpin = 0f
    private var scrubbing = false
    /** Whether they have ever turned it. The hint retires once they have. */
    private var turned = false
    /** Which slot is at the front. Derived from [spin], never set directly. */
    private var current = 0
    private val entities = mutableListOf<Entity>()
    private var slots: List<Slot> = emptyList()

    /**
     * One notch of the ring went past. The host owns the sound: the reel has no
     * business holding an audio path, and the themes' audio packs (§7) will
     * want to answer this differently per profile.
     */
    var onDetent: (() -> Unit)? = null

    /** Revealed, with the hysteresis of §5 rather than a single threshold. */
    var open: Boolean = false
        private set

    suspend fun build() {
        clear()
        val root = session.scene.activitySpace
        repeat(SLOTS) {
            val run = TextRun.reusable(
                session, context, WIDEST, CAP, argb(theme.text, 0.95f), "reel",
            ) ?: return@repeat
            run.entity.parent = root
            run.entity.setEnabled(false)
            entities += run.entity
            val mote = MeshEntity.create(
                session, Prims.build(session, Prims.mote(MOTE, 4, 6)),
                listOf(Prims.material(session, theme.alt, 0.85f)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            // The DM ring. Its own entity per cell rather than a shared one,
            // because sharing a material aborts the renderer natively on this
            // path -- learned the expensive way in Horizon, HereMark, Hud and
            // Boot.
            val ring = MeshEntity.create(
                session, Prims.build(session, Prims.halo(MOTE * 2.4f, MOTE * 0.32f, 16, 4)),
                listOf(Prims.material(session, theme.accent, 0.95f)),
            ).also { it.parent = root; it.setEnabled(false); entities += it }
            cells += Cell(run, mote, ring)
        }
        // THE PANEL. Without it the messages are text floating over a hand and
        // read as debris from the ring behind them; with it they are markers on
        // a surface. An outline rather than a fill: a filled oval on additive
        // optics is a lamp, and it would wash out the very words it carries.
        // A true ellipse at true size, not a circle scaled to fit: the slots
        // sit on an RX-by-RY oval and a circle through the wide pair misses the
        // narrow pair by 3 cm, which at palm range is not subtle.
        panel = MeshEntity.create(
            session, Prims.build(session, Prims.oval(RX, RY, TUBE, 56, 5)),
            listOf(Prims.material(session, theme.alt, 0.5f)),
        ).also { it.parent = root; it.setEnabled(false); entities += it }

        // THE PROJECTOR BEAM. The card is not merely floating near the oval, it
        // comes OUT of it, and a stem is what makes that read as one gesture
        // rather than two surfaces that happen to be adjacent. Along local +Z,
        // which fromLookTowards puts on the palm normal, so it is constant in
        // the palm's frame and needs no rebuilding as the hand moves.
        stem = MeshEntity.create(
            session, Prims.build(session, Prims.spur(0f, 0f, 0f, 0f, 0f, RAISE, TUBE * 0.6f)),
            listOf(Prims.material(session, theme.accent, 0.35f)),
        ).also { it.parent = root; it.setEnabled(false); entities += it }

        cardWho = TextRun.reusable(
            session, context, HEAD_WIDEST, CARD_CAP * 0.75f,
            argb(theme.accent, 0.95f), "reel-card-who",
        )?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }
        repeat(CARD_LINES) {
            val r = TextRun.reusable(
                session, context, CARD_WIDEST, CARD_CAP, argb(theme.text, 0.98f), "reel-card",
            ) ?: return@repeat
            r.entity.parent = root; r.entity.setEnabled(false); entities += r.entity
            cardBody += r
        }

        // HOW TO TURN IT, ON THE SURFACE ITSELF. §S4 gives the reel a gesture
        // and no way to find out about it, and an undocumented gesture is the
        // same as an absent one — this exact reel was reported as "I couldn't
        // figure out how to move to an earlier one". Shown only while the reel
        // is short enough to be new to somebody, and only when there is
        // somewhere to turn TO.
        hint = TextRun.reusable(
            session, context, HINT_WIDEST, CAP * 0.85f, argb(theme.alt, 0.75f), "reel-hint",
        )?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }
        Log.i(TAG, "[reel] $SLOTS slots, $FRONT named, raised card")
    }

    fun setMessages(list: List<Slot>) {
        slots = list.take(SLOTS)
    }

    /**
     * [joints] are the CHAT hand's; [palmDot] how squarely its palm faces the
     * wearer; [head] where they are.
     */
    fun tick(
        joints: Map<HandJointType, Pose>?,
        palmDot: Float?,
        head: Vector3?,
        nowMs: Long,
    ) {
        val was = open
        open = when {
            joints.isNullOrEmpty() || palmDot == null || head == null -> false
            palmDot > REVEAL -> true
            palmDot < HIDE -> false
            else -> open          // the gap: neither reveal nor hide
        }
        if (was != open) Log.i(TAG, "[reel] ${if (open) "revealed" else "hidden"}")
        if (!open) {
            cells.forEach {
                runCatching {
                    it.run.entity.setEnabled(false)
                    it.mote.setEnabled(false)
                    it.ring.setEnabled(false)
                }
            }
            runCatching {
                panel?.setEnabled(false)
                stem?.setEnabled(false)
                cardWho?.entity?.setEnabled(false)
                cardBody.forEach { it.entity.setEnabled(false) }
                hint?.entity?.setEnabled(false)
            }
            return
        }

        // Captured non-null: the reveal test above already required them, but
        // `open` is a var so the compiler cannot carry that through.
        val h = head ?: return
        val js = joints ?: return
        val ps = session.scene.perceptionSpace
        fun act(t: HandJointType): Vector3? = runCatching {
            ps.getScenePoseFromPerceptionPose(js[t] ?: return null)
                .poseInActivitySpace.translation
        }.getOrNull()
        val w = act(HandJointType.WRIST) ?: return
        val m = act(HandJointType.MIDDLE_METACARPAL) ?: return
        val ix = act(HandJointType.INDEX_PROXIMAL) ?: return
        val li = act(HandJointType.LITTLE_PROXIMAL) ?: return

        // The palm's own frame: along the hand, across it, and the normal.
        var ax = m.x - w.x; var ay = m.y - w.y; var az = m.z - w.z
        val al = sqrt(ax * ax + ay * ay + az * az).let { if (it > 1e-5f) it else return }
        ax /= al; ay /= al; az /= al
        var bx = li.x - ix.x; var by = li.y - ix.y; var bz = li.z - ix.z
        val bl = sqrt(bx * bx + by * by + bz * bz).let { if (it > 1e-5f) it else return }
        bx /= bl; by /= bl; bz /= bl
        // Normal = along x across, so the oval lies flat over the palm and
        // stands off it rather than intersecting the hand.
        val nx = ay * bz - az * by
        val ny = az * bx - ax * bz
        val nz = ax * by - ay * bx
        val nl = sqrt(nx * nx + ny * ny + nz * nz).let { if (it > 1e-5f) it else return }
        val ux = nx / nl; val uy = ny / nl; val uz = nz / nl
        // Toward the wearer, so the oval floats above the palm and not through
        // the back of the hand. The sign is settled by which way the palm is
        // facing rather than derived — this project has lost four arguments to
        // handedness signs written in comments.
        val toHead = ((h.x - w.x) * ux + (h.y - w.y) * uy + (h.z - w.z) * uz)
        val s = if (toHead >= 0f) 1f else -1f
        val cx = w.x + ax * (ALONG) + ux * s * STANDOFF
        val cy = w.y + ay * (ALONG) + uy * s * STANDOFF
        val cz = w.z + az * (ALONG) + uz * s * STANDOFF

        // The palm's two rotations, shared by everything below. fromLookTowards
        // puts local +Z on `forward` and local +Y on `up` (PalmFrameTest), so
        // the oval wants the normal forward and the DM rings -- which are tori
        // about their own Y -- want it up.
        val fwd = Vector3(ux * s, uy * s, uz * s)
        val along = Vector3(ax, ay, az)
        val q = Quaternion.fromLookTowards(fwd, along)
        val qRing = Quaternion.fromLookTowards(along, fwd)

        // TURN THE RING — OVER THE MESSAGES THAT EXIST, not over twelve slots.
        //
        // The first version stepped through all SLOTS regardless of how many
        // messages were in them, so with two messages ten of the twelve detents
        // selected nothing and the card simply vanished. From the wearer's side
        // that is indistinguishable from the gesture not working, which is
        // exactly how it was reported. The ring buffer's CAPACITY is twelve;
        // its CONTENTS are however many have arrived, and the control has to
        // follow the contents.
        val n = slots.size
        if (n == 0) {
            spin = 0f; scrubbing = false
        } else {
            // A CLUTCH, NOT AN ABSOLUTE MAPPING: the thumb travels about 9 cm,
            // so mapping its whole length onto a whole turn puts the detents
            // millimetres apart. One stroke covers half the ring and you lift
            // and re-place to go further — the gesture a scroll wheel makes,
            // and the reason a scroll wheel works.
            //
            // IT RUNS BOTH WAYS: toward the fingertip goes back in time, toward
            // the knuckle comes forward, and the ring wraps, so every message
            // is reachable in either direction. The floor of two is what makes
            // that legible on a SHORT reel — at half-the-ring, two messages
            // needed a whole stroke each way to move at all, which reads as a
            // control that only goes one way rather than one that is stiff.
            val gain = (n / 2f).coerceAtLeast(2f)
            val thumb = act(HandJointType.THUMB_TIP)
            // The whole finger, knuckle to tip. Intermediate joints are
            // optional so a partial tracking frame degrades to the chord
            // rather than dropping the gesture altogether.
            val bones = listOfNotNull(
                ix,
                act(HandJointType.INDEX_INTERMEDIATE),
                act(HandJointType.INDEX_DISTAL),
                act(HandJointType.INDEX_TIP),
            )
            if (thumb != null && bones.size >= 2) {
                val sc = scrub(bones, thumb)
                if (sc.on && !scrubbing) {
                    scrubbing = true; grabT = sc.t; grabSpin = spin
                    Log.i(TAG, "[reel] scrub start at %.2f".format(sc.t))
                } else if (!sc.on && scrubbing) {
                    scrubbing = false
                    Log.i(TAG, "[reel] scrub end")
                }
                if (scrubbing) spin = grabSpin + (sc.t - grabT) * gain
            } else if (scrubbing) {
                scrubbing = false
                Log.i(TAG, "[reel] scrub end (lost joints)")
            }
        }
        // The front slot, snapped. Sliding the thumb toward the fingertip
        // brings OLDER messages round to the front, which is the direction the
        // hand is already travelling when it reaches for the past.
        val front = if (n == 0) 0 else ((-Math.round(spin)) % n + n) % n
        if (front != current) {
            current = front
            turned = true
            onDetent?.invoke()
            Log.i(TAG, "[reel] message ${current + 1} of $n")
        }

        cells.forEachIndexed { i, c ->
            val msg = slots.getOrNull(i)
            // The oval is divided by how many messages there ARE, so whichever
            // one is selected sits at the front and the rest spread evenly
            // round. Dividing by the capacity instead left a half-empty reel
            // with its markers bunched at one edge and the front position empty
            // most of the time.
            val span = n.coerceAtLeast(1)
            val t = ((i + spin) / span) * TAU
            val ox = kotlin.math.sin(t) * RX
            val oy = -kotlin.math.cos(t) * RY
            val at = Vector3(
                cx + bx * ox + ax * oy,
                cy + by * ox + ay * oy,
                cz + bz * ox + az * oy,
            )
            // Senders only on the front arc — enough to choose by. The words
            // are on the raised card, because five lines of them do not fit.
            //
            // Which slots are named follows where they are DRAWN, not their
            // index: once the ring turns, "the front five" is a fact about the
            // oval rather than about the message list.
            val steps = ((i + spin) % span + span) % span
            val fromFront = kotlin.math.min(steps, span - steps)
            val named = msg != null && fromFront <= FRONT / 2f
            runCatching {
                c.mote.setEnabled(msg != null)
                c.mote.setPose(Pose(at), Space.ACTIVITY)
                c.mote.setScale(if (i == current) 1.8f else 1f)
                // CIRCLED = ADDRESSED TO YOU. Lying in the oval's own plane, so
                // it reads as a ring rather than as an edge-on line.
                c.ring.setEnabled(msg?.direct == true)
                c.ring.setPose(Pose(at, qRing), Space.ACTIVITY)
                c.ring.setScale(if (i == current) 1.8f else 1f)
                c.run.entity.setEnabled(named)
                if (!named) return@runCatching
                c.run.setText(msg!!.who)
                c.run.entity.setPose(
                    Pose(Vector3(at.x, at.y - LABEL_DROP, at.z), facing(at, h)),
                    Space.ACTIVITY,
                )
            }
        }

        // The oval and its beam share one rotation: normal forward, along-hand
        // up. That second argument is the whole reason PalmFrameTest exists —
        // it is what stops the wide axis from ending up running up the fingers.
        val mid = Vector3(cx, cy, cz)
        runCatching {
            panel?.setEnabled(true)
            panel?.setPose(Pose(mid, q), Space.ACTIVITY)
            stem?.setEnabled(slots.isNotEmpty())
            stem?.setPose(Pose(mid, q), Space.ACTIVITY)
        }

        // THE HINT DOUBLES AS THE CONTACT LAMP.
        //
        // The gesture had exactly one failure mode and no way to see it: touch
        // the finger and either the reel turned or nothing at all happened, and
        // "nothing at all happened" covers both "not detected" and "detected,
        // nowhere to go". Those need opposite fixes, and telling them apart was
        // costing a round trip through the headset each time.
        //
        // So while the thumb is riding the finger the line says so, and says
        // where you are in the reel. It also keeps showing after the wearer has
        // turned it — the position readout is useful forever, the instruction
        // is not.
        runCatching {
            val show = n > 1 && (scrubbing || !turned)
            hint?.entity?.setEnabled(show)
            if (show) {
                val hAt = Vector3(
                    cx - ax * (RY + HINT_DROP),
                    cy - ay * (RY + HINT_DROP),
                    cz - az * (RY + HINT_DROP),
                )
                hint?.setText(
                    if (scrubbing) "\u25c0  ${current + 1} OF $n  \u25b6" else HINT,
                )
                hint?.entity?.setPose(Pose(hAt, facing(hAt, h)), Space.ACTIVITY)
            }
        }

        // AND THE CURRENT MESSAGE PROJECTS UP — off the panel along its own
        // normal, where the beam ends. Nearer the eye than the oval, so it is
        // bigger in angle as well as in metres: ~1.8 degrees against the ring's
        // 1.2, which is the difference between reading and counting.
        val sel = slots.getOrNull(current)
        runCatching {
            cardWho?.entity?.setEnabled(sel != null)
            if (sel == null) {
                cardBody.forEach { it.entity.setEnabled(false) }
                return@runCatching
            }
            val wrapped = wrap(sel.words, CARD_COLS, CARD_LINES)
            // THE BLOCK GROWS UPWARD FROM A FIXED CLEARANCE, rather than
            // hanging down from a fixed top. A long message that hangs down
            // runs into the hand it is sitting on, and raising the anchor by a
            // constant instead leaves a one-line message floating absurdly
            // high. Pinning the BOTTOM means short messages sit close to the
            // oval and long ones ride up out of the way, which is what was
            // asked for and also the only version that works at both extremes.
            val pitch = CARD_CAP * 1.7f
            val baseY = cy + uy * s * RAISE + CLEAR + pitch * wrapped.size
            val at = Vector3(cx + ux * s * RAISE, baseY, cz + uz * s * RAISE)
            val r = facing(at, h)
            // WHO, AND FROM WHERE. A name alone cannot say whether Chuck spoke
            // to the whole channel or to you, and those are different enough
            // that guessing wrong is embarrassing in one direction and a missed
            // message in the other.
            cardWho?.setText(
                if (sel.direct) "${sel.who} \u2192 YOU"
                else "${sel.who} \u00b7 ${sel.origin.ifBlank { "CHANNEL" }}",
            )
            cardWho?.entity?.setPose(Pose(at, r), Space.ACTIVITY)
            cardBody.forEachIndexed { i, line ->
                val txt = wrapped.getOrNull(i)
                line.entity.setEnabled(txt != null)
                if (txt == null) return@forEachIndexed
                line.setText(txt)
                line.entity.setPose(
                    Pose(Vector3(at.x, baseY - pitch * (1.4f + i), at.z), r),
                    Space.ACTIVITY,
                )
            }
        }
    }

    private fun facing(at: Vector3, head: Vector3): Quaternion {
        val dx = head.x - at.x
        val dz = head.z - at.z
        if (dx * dx + dz * dz < 1e-6f) return Quaternion.fromEulerAngles(0f, 0f, 0f)
        return Quaternion.fromEulerAngles(
            0f, Math.toDegrees(atan2(dx, dz).toDouble()).toFloat(), 0f,
        )
    }

    fun clear() {
        cells.clear(); slots = emptyList(); open = false
        panel = null; stem = null; cardWho = null; cardBody.clear()
        current = 0; spin = 0f; grabT = 0f; grabSpin = 0f; scrubbing = false
        hint = null; turned = false
        val doomed = entities.toList()
        entities.clear()
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        (((a.coerceIn(0f, 1f) * 255).toInt() and 0xFF) shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"
        const val TAU = (2.0 * Math.PI).toFloat()
        /** "the last ~12 messages" (§S4). */
        const val SLOTS = 12
        /** "~5 legible across the front arc" (§S4). */
        const val FRONT = 5
        /** The oval, in the palm's plane. Wider than tall, hence oval. */
        const val RX = 0.085f
        const val RY = 0.055f
        /** How far up the hand its centre sits, from the wrist. */
        const val ALONG = 0.06f
        /** And how far off the palm, so it floats rather than intersects. */
        const val STANDOFF = 0.06f
        /** Small: a slot you cannot read still has to be countable. */
        const val MOTE = 0.005f
        /**
         * 1.2° at the ~0.45 m a raised palm sits from the eye. This is the one
         * surface where the floor genuinely binds — a hand is close, and close
         * means small in metres for the same angle.
         */
        const val CAP = 0.0094f
        /** §5's thresholds, verbatim. The gap between them is the feature. */
        const val REVEAL = 0.6f
        const val HIDE = 0.45f
        const val WIDEST = "MMMMMMMM"
        const val TUBE = 0.0022f
        /** How far the current message stands off the panel, toward the wearer. */
        const val RAISE = 0.07f
        /**
         * 1.8° where the card sits (~0.32 m): the one thing here meant to be
         * READ. Comfortably over §4.1's 1.2° floor and the 1.30° house
         * standard, with the margin spent on WIDTH rather than on height —
         * a clipped message is a worse failure than a slightly smaller one.
         */
        const val CARD_CAP = 0.010f
        /**
         * EIGHTEEN BY NINE — about 150 characters, against the 42 the first card
         * held, which duly clipped very nearly everything.
         *
         * Eighteen is a BOUND, not a preference: at CARD_CAP the worst case of
         * eighteen capital M's is 0.169 m, and at 0.32 m that subtends about
         * 30° against a 34° field. Real text averages far narrower. Twenty
         * would fit the arithmetic and leave nothing for a hand held closer
         * than assumed.
         */
        const val CARD_COLS = 18
        const val CARD_LINES = 9
        const val CARD_WIDEST = "MMMMMMMMMMMMMMMMMM"
        /** How far the bottom of the block clears the oval. */
        const val CLEAR = 0.02f
        /** The header holds "NAME · CHANNEL", which is longer than a body line. */
        const val HEAD_WIDEST = "MMMMMMMMMMMMMMMMMMMM"
        /** Sender labels hang just under their marker. */
        const val LABEL_DROP = 0.014f
        const val HINT = "THUMB ALONG INDEX TO TURN"
        /** Wide enough for the hint AND for the position readout it becomes. */
        const val HINT_WIDEST = "THUMB ALONG INDEX TO TURN"
        const val HINT_DROP = 0.022f
    }
}

/**
 * How close to the index's axis counts as riding it, as a fraction of that
 * finger's own length — so it holds across hand sizes.
 *
 * A thumb resting against the side of the index sits about 22 mm off its axis
 * on a 75 mm finger, which is 0.29. The first value here was 0.34, leaving
 * about 4 mm for hand-tracking jitter to eat before the gesture silently stops
 * being detected — and a gesture that fails silently is reported as "I could
 * not figure out how to do it", not as a bug. 0.45 leaves real headroom and is
 * still nowhere near an abducted thumb, which is 0.8 and up.
 */
internal const val CONTACT_FRAC = 0.45f

/**
 * WHERE THE THUMB SITS ALONG THE INDEX — the reel's one real haptic.
 *
 * §5: thumb-along-index is "the app's only source of genuine haptics", because
 * you are touching your own finger. Nothing else here can be felt, and a
 * control you can feel is worth more than three you cannot.
 *
 * [t] runs 0 at the index knuckle to 1 at its tip, measured along the finger's
 * ARC. [on] is whether the thumb is close enough to count as riding it, as a
 * FRACTION of that finger's own length rather than in millimetres — hands
 * differ in size by well over the tolerance an absolute threshold would need,
 * and this project has already had one gesture fail for exactly that reason.
 *
 * IT FOLLOWS THE BONES, NOT A CHORD. The first version measured against the
 * straight line from knuckle to fingertip, which is only the finger's shape
 * while the finger is straight — and nobody slides a thumb along a rigid
 * index. Curl it thirty degrees and the middle of the finger stands about a
 * centimetre off its own chord, so a thumb resting ON the finger measures as a
 * centimetre and a half away from it and the gesture stops being detected. The
 * failure is silent and looks exactly like bad tracking. Reported as "doesn't
 * seem to work for me", which is what a silent failure always sounds like.
 *
 * Pure, and separately tested: the alternative is discovering a sign error by
 * wearing the headset, which costs several minutes per attempt.
 */
internal class Scrub(val t: Float, val on: Boolean)

/** Two-point form: a straight finger, and what the tests started from. */
internal fun scrub(prox: Vector3, tip: Vector3, thumb: Vector3): Scrub =
    scrub(listOf(prox, tip), thumb)

internal fun scrub(bones: List<Vector3>, thumb: Vector3): Scrub {
    if (bones.size < 2) return Scrub(0f, false)
    // Segment lengths, and the total, which is both the arc-length denominator
    // and the scale the contact tolerance is expressed in.
    val seg = FloatArray(bones.size - 1)
    var total = 0f
    for (k in 0 until bones.size - 1) {
        val a = bones[k]; val b = bones[k + 1]
        seg[k] = sqrt(
            (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) + (b.z - a.z) * (b.z - a.z),
        )
        total += seg[k]
    }
    if (total < 1e-5f) return Scrub(0f, false)

    var bestD = Float.MAX_VALUE
    var bestArc = 0f
    var run = 0f
    for (k in 0 until bones.size - 1) {
        val a = bones[k]; val b = bones[k + 1]
        val l2 = seg[k] * seg[k]
        if (l2 > 1e-10f) {
            val vx = thumb.x - a.x; val vy = thumb.y - a.y; val vz = thumb.z - a.z
            val dx = b.x - a.x; val dy = b.y - a.y; val dz = b.z - a.z
            // Clamped BEFORE the perpendicular, so a thumb held out past the
            // fingertip measures from the tip rather than from an infinite
            // line — otherwise an open hand reads as contact.
            val u = ((vx * dx + vy * dy + vz * dz) / l2).coerceIn(0f, 1f)
            val px = vx - dx * u; val py = vy - dy * u; val pz = vz - dz * u
            val d = sqrt(px * px + py * py + pz * pz)
            if (d < bestD) { bestD = d; bestArc = run + seg[k] * u }
        }
        run += seg[k]
    }
    return Scrub((bestArc / total).coerceIn(0f, 1f), bestD < CONTACT_FRAC * total)
}

/**
 * Break the words across the card's lines.
 *
 * A single line of message text at a readable size is wider than the display,
 * so it wraps: at spaces where there are any, and mid-word where there are not,
 * because a long unbroken token is a real thing people send.
 *
 * WHEN IT DOES NOT FIT, IT SAYS SO. Word packing never reaches the raw
 * cols x lines product -- a line ends when the next word will not fit, so a
 * fourteen-column line holding "abc abc abc" wastes three of its characters --
 * which means a message sized against that product overflows and loses its
 * tail. Dropping it silently is the bad version: the wearer reads a sentence
 * that simply stops, with no way to tell a terse message from a truncated one.
 * The ellipsis is the difference between "that is all he said" and "there is
 * more of this in the thread".
 */
internal fun wrap(text: String, cols: Int, lines: Int): List<String> {
    if (cols <= 0 || lines <= 0) return emptyList()
    val all = mutableListOf<String>()
    var cur = StringBuilder()
    for (word in text.trim().split(' ')) {
        var w = word
        while (w.length > cols) {
            if (cur.isNotEmpty()) { all += cur.toString(); cur = StringBuilder() }
            all += w.take(cols)
            w = w.drop(cols)
        }
        if (w.isEmpty()) continue
        when {
            cur.isEmpty() -> cur.append(w)
            cur.length + 1 + w.length <= cols -> cur.append(' ').append(w)
            else -> { all += cur.toString(); cur = StringBuilder(w) }
        }
    }
    if (cur.isNotEmpty()) all += cur.toString()
    if (all.size <= lines) return all
    val kept = all.take(lines).toMutableList()
    val last = kept[lines - 1]
    kept[lines - 1] =
        if (last.length < cols) "$last\u2026" else last.take(cols - 1) + "\u2026"
    return kept
}
