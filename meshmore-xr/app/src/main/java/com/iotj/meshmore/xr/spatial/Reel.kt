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
 * OWED: rotation by thumb-along-index, and the per-message CROWN. The reel
 * currently shows the newest at the front and does not turn.
 */
class Reel(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    /** One message, already formatted. */
    class Slot(val who: String, val words: String)

    private class Cell(val run: TextRun.Run, val mote: MeshEntity)

    private val cells = mutableListOf<Cell>()
    /** The oval itself, so the slots read as sitting ON something. */
    private var panel: MeshEntity? = null
    /** The raised card: whichever slot is current, big enough to read. */
    private var stem: MeshEntity? = null
    private var cardWho: TextRun.Run? = null
    private val cardBody = mutableListOf<TextRun.Run>()
    /** Which slot is current. Fixed at the front until rotation lands. */
    private var current = 0
    private val entities = mutableListOf<Entity>()
    private var slots: List<Slot> = emptyList()

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
            cells += Cell(run, mote)
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
            session, context, CARD_WIDEST, CARD_CAP * 0.8f,
            argb(theme.accent, 0.95f), "reel-card-who",
        )?.also { it.entity.parent = root; it.entity.setEnabled(false); entities += it.entity }
        repeat(CARD_LINES) {
            val r = TextRun.reusable(
                session, context, CARD_WIDEST, CARD_CAP, argb(theme.text, 0.98f), "reel-card",
            ) ?: return@repeat
            r.entity.parent = root; r.entity.setEnabled(false); entities += r.entity
            cardBody += r
        }

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
                runCatching { it.run.entity.setEnabled(false); it.mote.setEnabled(false) }
            }
            runCatching {
                panel?.setEnabled(false)
                stem?.setEnabled(false)
                cardWho?.entity?.setEnabled(false)
                cardBody.forEach { it.entity.setEnabled(false) }
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

        cells.forEachIndexed { i, c ->
            val msg = slots.getOrNull(i)
            // Slot 0 sits at the FRONT — nearest the wearer along the hand —
            // and the rest wrap round. Newest first, which is what triage wants.
            val t = (i.toFloat() / SLOTS) * TAU
            val ox = kotlin.math.sin(t) * RX
            val oy = -kotlin.math.cos(t) * RY
            val at = Vector3(
                cx + bx * ox + ax * oy,
                cy + by * ox + ay * oy,
                cz + bz * ox + az * oy,
            )
            // Senders only on the front arc — enough to choose by. The words
            // are on the raised card, because five lines of them do not fit.
            val named = msg != null && i < FRONT
            runCatching {
                c.mote.setEnabled(msg != null)
                c.mote.setPose(Pose(at), Space.ACTIVITY)
                c.mote.setScale(if (i == current) 1.8f else 1f)
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
        val q = Quaternion.fromLookTowards(
            Vector3(ux * s, uy * s, uz * s), Vector3(ax, ay, az),
        )
        val mid = Vector3(cx, cy, cz)
        runCatching {
            panel?.setEnabled(true)
            panel?.setPose(Pose(mid, q), Space.ACTIVITY)
            stem?.setEnabled(slots.isNotEmpty())
            stem?.setPose(Pose(mid, q), Space.ACTIVITY)
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
            val at = Vector3(cx + ux * s * RAISE, cy + uy * s * RAISE, cz + uz * s * RAISE)
            val r = facing(at, h)
            cardWho?.setText(sel.who)
            cardWho?.entity?.setPose(Pose(at, r), Space.ACTIVITY)
            val wrapped = wrap(sel.words)
            cardBody.forEachIndexed { i, line ->
                val txt = wrapped.getOrNull(i)
                line.entity.setEnabled(txt != null)
                if (txt == null) return@forEachIndexed
                line.setText(txt)
                line.entity.setPose(
                    Pose(
                        Vector3(at.x, at.y - CARD_CAP * (2.0f + i * 1.7f), at.z),
                        r,
                    ),
                    Space.ACTIVITY,
                )
            }
        }
    }

    /**
     * Break the words across the card's lines.
     *
     * A single line of message text at a readable size is 0.25 m wide at a
     * third of a metre — about forty degrees, which is wider than the display.
     * So it wraps, at spaces where there are any and mid-word where there are
     * not, because a long unbroken token is a real thing people send.
     */
    internal fun wrap(text: String): List<String> {
        val out = mutableListOf<String>()
        var cur = StringBuilder()
        for (word in text.trim().split(' ')) {
            var w = word
            while (w.length > CARD_COLS) {
                if (cur.isNotEmpty()) { out += cur.toString(); cur = StringBuilder() }
                out += w.take(CARD_COLS)
                w = w.drop(CARD_COLS)
                if (out.size >= CARD_LINES) return out.take(CARD_LINES)
            }
            if (w.isEmpty()) continue
            when {
                cur.isEmpty() -> cur.append(w)
                cur.length + 1 + w.length <= CARD_COLS -> cur.append(' ').append(w)
                else -> {
                    out += cur.toString()
                    if (out.size >= CARD_LINES) return out
                    cur = StringBuilder(w)
                }
            }
        }
        if (cur.isNotEmpty()) out += cur.toString()
        return out.take(CARD_LINES)
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
        panel = null; stem = null; cardWho = null; cardBody.clear(); current = 0
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
        /** 1.8° where the card sits: the one thing here meant to be READ. */
        const val CARD_CAP = 0.012f
        /** Wide enough to read, narrow enough to fit a 34° field. */
        const val CARD_COLS = 14
        const val CARD_LINES = 3
        const val CARD_WIDEST = "MMMMMMMMMMMMMM"
        /** Sender labels hang just under their marker. */
        const val LABEL_DROP = 0.014f
    }
}
