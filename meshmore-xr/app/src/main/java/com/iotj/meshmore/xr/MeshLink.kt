// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.Manifest
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import io.iotone.meshcore.android.AndroidBleTransport
import io.iotone.meshcore.android.MeshcoreSession
import io.iotone.meshcore.android.SessionListener
import com.iotj.meshmore.xr.spatial.MeshNodes
import com.iotj.meshmore.xr.spatial.MeshTopology
import io.iotone.meshcore.android.SessionState
import io.iotone.meshcore.frames.AdvertFrame
import io.iotone.meshcore.frames.ChannelMessageFrame
import io.iotone.meshcore.frames.ContactFrame
import io.iotone.meshcore.frames.DecodeFailure
import io.iotone.meshcore.model.SelfInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * P0 checkpoint 3 — the MeshCore companion radio, over BLE, FROM THE GLASSES.
 *
 * This is the assumption the whole project rests on: that libmeshcore-android's
 * Nordic BLE stack works on XR hardware and the CMD_APP_START ->
 * RESP_CODE_SELF_INFO handshake decodes.
 *
 * Nothing here is XR-specific on purpose. The transport, session and codec are
 * the SAME code the Flutter SNS app's Java twin uses, pinned to the same
 * firmware commit. If this works, the protocol layer is done and every later
 * surface is UI work.
 *
 * State is exposed as a StateFlow so Compose can observe it; the library
 * dispatches its callbacks on the main thread already.
 */
class MeshLink(private val context: Context) {

    data class Status(
        val state: SessionState = SessionState.DISCONNECTED,
        val scanning: Boolean = false,
        val deviceName: String? = null,
        val selfInfo: SelfInfo? = null,
        val adverts: Int = 0,
        val contacts: Int = 0,
        /**
         * How many the radio can hold, once it has been asked. Zero means
         * nobody knows yet — and a capacity warning must never be raised from
         * a number nobody knows.
         */
        val maxContacts: Int = 0,
        /** What the radio said it holds, at the last sync. */
        val heldByRadio: Int = 0,
        val messages: Int = 0,
        val lastEvent: String = "idle",
        val error: String? = null,
        /**
         * When the link DROPPED, having previously been READY — the wall clock,
         * or null if we are connected or have never connected at all.
         *
         * A cold start and a drop are different facts and used to look the same:
         * both showed DISCONNECTED, and the horizon carried on drawing the mesh
         * it last heard as though the radio were still feeding it. On a hike the
         * radio goes out of BLE range in a backpack, in a pannier, behind a body,
         * and the wearer's only evidence was that nothing new ever arrived —
         * which is also what a quiet mesh looks like. This is the timestamp that
         * separates them, and how long ago it was is the number worth showing.
         */
        val droppedAtMs: Long? = null,
    )

    /**
     * How long the app has been BLIND, in millis — null while the link is up or
     * before it has ever come up.
     */
    fun blindForMs(nowMs: Long = System.currentTimeMillis()): Long? =
        _status.value.droppedAtMs?.let { (nowMs - it).coerceAtLeast(0L) }

    /**
     * The link, in the four characters the status band can spare.
     *
     * "LINK" when it is up, the session's own state word when it has never been
     * up, and after a drop the thing that is actually worth knowing: HOW LONG
     * the app has been blind. `LOST 4M` says the mesh you are looking at is four
     * minutes old at best. `DISC` said nothing at all, and said it identically
     * whether the radio had been gone two seconds or the whole walk.
     */
    fun linkChip(nowMs: Long = System.currentTimeMillis()): String =
        chipFor(_status.value.state, blindForMs(nowMs))

    /**
     * WHERE THE LINK IS, AS A STEP OUT OF FOUR — never a spinner.
     *
     * §S2: "shown as literal steps with step semantics (STEP 2/4), never a
     * spinner." The reason is not decoration. A spinner says only "something is
     * happening", so every failure looks identical: a radio that is switched
     * off, a radio out of range, a bond the OS silently refused, and a
     * handshake that stalled all present as the same turning circle, and a
     * tester can only report "it didn't connect". A step number says WHICH of
     * those four it got through, which is most of the diagnosis before anybody
     * opens a log.
     *
     * Returns null once READY: a progress readout that lingers after arrival is
     * a progress readout people stop reading.
     */
    fun linkStep(): String? {
        val st = _status.value
        if (st.state == SessionState.READY) return null
        // A DROP IS NOT STEP 1. Re-entering the ladder at "LOOKING FOR A RADIO"
        // reads as a fresh boot, and the wearer's question after a drop is not
        // "which step is it on" but "did I lose the radio, and is it coming
        // back". Deliberately carries no duration: this string drives the notice
        // band, which speaks on CHANGE, and a counting number would make it
        // speak every second. The count belongs in the status chip.
        if (st.droppedAtMs != null) {
            return context.getString(R.string.link_lost)
        }
        // PAIRING IS A HANDOFF TO THE WEARER, and the one moment in the whole
        // connect where they must DO something: read six digits off the
        // radio's screen and type them into the system dialog. Saying which is
        // the difference between a first pairing and a support ticket.
        if (st.lastEvent == "pairing") {
            return context.getString(R.string.link_pair_code)
        }
        val n = when {
            st.scanning -> 1
            st.state == SessionState.DISCONNECTED -> if (st.deviceName == null) 1 else 2
            st.state == SessionState.CONNECTING -> 2
            st.state == SessionState.HANDSHAKING -> 3
            else -> 4
        }
        val what = when (n) {
            1 -> context.getString(R.string.link_scan)
            2 -> context.getString(R.string.link_connecting, st.deviceName ?: "RADIO")
            3 -> context.getString(R.string.link_handshake)
            else -> context.getString(R.string.link_reading)
        }
        // The error replaces the step rather than sitting beside it: if we know
        // why it stopped, the step it stopped on is the less useful half.
        st.error?.let { return context.getString(R.string.link_failed, it.uppercase()) }
        return context.getString(R.string.link_step, n, what)
    }

    private val _status = MutableStateFlow(Status())
    val status: StateFlow<Status> = _status.asStateFlow()

    /**
     * THE MESH ITSELF, keyed by public key.
     *
     * Adverts and contacts describe the same peers from two directions: an
     * advert is what just came over the air, a contact is what the radio has
     * persisted. Merging them into one keyed table means a node heard live and
     * a node remembered from an hour ago are the same mote, not two.
     *
     * Keyed by PUBLIC KEY, never by name. Names are user-supplied, duplicated,
     * and changed on a whim; the key is the identity. Two radios both called
     * "node" must remain two motes.
     */
    private val peers = java.util.concurrent.ConcurrentHashMap<String, MeshNodes.Peer>()

    /**
     * The ONLY nodes this app will transmit to, by public-key suffix.
     *
     * Authorised by the operator on 2026-08-03 as hardware they own. Anything
     * else on the mesh belongs to somebody else and is never addressed —
     * receiving is passive, sending is not.
     */
    private val ALLOWED_SUFFIXES = listOf("ab60", "d563")

    /**
     * Matched against the NAME first, which is how these nodes are actually
     * identified — and not against the key, which is what the first attempt
     * did and why it refused both.
     *
     * MeshCore's default advert name is NOT derived from the public key.
     * D38F07AED563 has key prefix 1a17e848dbc2; the two share nothing. The
     * operator quotes their hardware by the name, the name is what appears in
     * every other app, and the key is an implementation detail nobody reads.
     *
     * Still an allow-list, and still explicit: a name is weaker evidence than
     * a key, so the match is logged with both before anything is transmitted.
     */
    /**
     * FOUR HEX CHARACTERS IS NOT AN IDENTITY, and a 350-node mesh proved it.
     *
     * A contact called '7182', 12,486 km away, was being treated as the
     * operator's own hardware — protected from the sweep and, far more
     * seriously, MESSAGEABLE — because its public key happens to end in the
     * same four characters as one of the allowed suffixes. Across 350 contacts
     * and two suffixes that is about a one-in-a-hundred event, so it was due.
     *
     * The suffixes are the operator's stated authorisation and stay exactly as
     * given. What changes is how a peer is matched against them:
     *
     *  1. A PINNED FULL KEY always wins. Once a node has identified itself by
     *     NAME, its whole 32-byte key is remembered and only that key is that
     *     node from then on.
     *  2. A NAME ending in the suffix is how these radios are actually
     *     identified — MeshCore's advert name is not derived from the key, the
     *     operator quotes their hardware by name, and it is what every other
     *     app shows. This match also PINS, so it happens once.
     *  3. A KEY ending in the suffix and nothing else is no longer enough. It
     *     is logged, once per peer, saying precisely that it was ignored — so
     *     if a genuine node of the operator's is ever identified only that way,
     *     the log says so instead of the app silently refusing to talk to it.
     *
     * This can only ever NARROW what the app will transmit to, which is the
     * right direction for a rule the operator gave in one sentence.
     */
    private fun isAllowed(p: MeshNodes.Peer): Boolean {
        val full = p.fullKey?.lowercase()
        if (full != null && OwnNodes.isPinned(context, full)) return true
        val byName = ALLOWED_SUFFIXES.firstOrNull { p.name.endsWith(it, ignoreCase = true) }
        if (byName != null) {
            if (full != null && full.length >= 64) OwnNodes.pin(context, byName, full, p.name)
            return true
        }
        val byKey = ALLOWED_SUFFIXES.firstOrNull {
            (p.fullKey ?: p.key).endsWith(it, ignoreCase = true)
        }
        if (byKey != null && warnedKeyOnly.add(p.key)) {
            Log.w(
                TAG,
                "[allow] '${p.name}' key=${p.key} ends in '$byKey' but its NAME does not — " +
                    "not treated as your node. If this IS yours, say so and it will be pinned.",
            )
            // Worth a line in the alerts panel too: this is the app declining
            // to treat something as the operator's hardware, and a refusal
            // nobody can see is indistinguishable from a bug.
            Alerts.warn(
                "ALLOW",
                context.getString(com.iotj.meshmore.xr.R.string.al_lookalike, p.name.take(18)),
            )
        }
        return false
    }

    /**
     * Settle WHICH radios are the operator's, once the store is fully read.
     *
     * isAllowed pins as a side effect, but it is only called when something
     * asks — a transmit, a sweep, a menu — so on a session where nobody
     * messaged anyone the app never wrote down whose hardware was in the room.
     * Doing it at sync means the identity is settled before the first send can
     * happen, and the log carries the answer whether or not anyone asks.
     */
    private fun resolveOwnNodes() {
        val all = peers.values.toList()
        val mine = all.filter { p ->
            ALLOWED_SUFFIXES.any { p.name.endsWith(it, ignoreCase = true) }
        }
        mine.forEach { p ->
            val sfx = ALLOWED_SUFFIXES.first { p.name.endsWith(it, ignoreCase = true) }
            p.fullKey?.takeIf { it.length >= 64 }
                ?.let { OwnNodes.pin(context, sfx, it.lowercase(), p.name) }
        }
        val collisions = all.filter { p ->
            !mine.contains(p) &&
                ALLOWED_SUFFIXES.any { (p.fullKey ?: p.key).endsWith(it, ignoreCase = true) }
        }
        Log.i(
            TAG,
            "[allow] your nodes: " +
                (mine.joinToString { "'${it.name}'" }.ifBlank { "none in this store" }) +
                "; pinned=" + OwnNodes.pinned(context).size +
                "; key-only lookalikes ignored=" + collisions.size,
        )
        collisions.take(4).forEach {
            Log.i(TAG, "[allow] lookalike '${it.name}' key=${it.key} — not yours")
        }
    }

    /** Peers already reported as key-only matches, so the log says it once. */
    private val warnedKeyOnly = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private val _mesh = MutableStateFlow<List<MeshNodes.Peer>>(emptyList())
    val mesh: StateFlow<List<MeshNodes.Peer>> = _mesh.asStateFlow()

    /**
     * LOADING, as a real fraction rather than a spinner.
     *
     * The contact sync announces its size up front (ContactsStartFrame carries
     * a count), so the progress we show is the progress that exists -- no
     * invented percentage, and the bar cannot sit at 90% forever.
     */
    data class Load(
        val total: Int = 0,
        val received: Int = 0,
        val done: Boolean = false,
        val batteryMv: Int? = null,
        val rssi: Int? = null,
    ) {
        val fraction: Float get() = if (total <= 0) 0f else (received.toFloat() / total).coerceIn(0f, 1f)
    }

    private val _load = MutableStateFlow(Load())
    val load: StateFlow<Load> = _load.asStateFlow()

    /** Where the radio thinks it is; the origin every bearing is measured from. */
    /**
     * What people have said to us, newest first.
     *
     * Kept in memory only. A companion app that forgets your messages when it
     * restarts is a poor one and this will want persisting, but a ring buffer
     * that is honest about being a ring buffer beats a store that half works.
     */
    data class Msg(
        val fromKey: String,
        val fromName: String,
        val text: String,
        val atEpochSec: Long,
        val direct: Boolean,
        val channel: String? = null,
        /**
         * The channel's NAME, when the radio has told us one.
         *
         * Separate from [channel] on purpose: [channel] is the slot index and
         * is what threads are grouped by, because it is stable. A name can be
         * blank, can be renamed, and can collide between two radios -- all of
         * which are fine for a label and fatal for an identity.
         */
        val channelName: String? = null,
        /**
         * WHAT BECAME OF A MESSAGE WE SENT. Null for everything received.
         *
         * Two hours of soak established that about one direct message in ten
         * is never acknowledged, and that the app had no idea: it said "sent"
         * the moment the radio took the frame and never revisited it. A
         * messaging app that cannot tell you whether your message arrived is
         * asking you to trust it about the one thing you actually care about.
         */
        val delivery: Delivered? = null,
        /** The CRC tag the radio will acknowledge this by. See [Delivered]. */
        val ackTag: Long? = null,
    )

    /**
     * SENT is what the radio accepted. DELIVERED is what the far end confirmed.
     * LOST is what never came back inside the radio's own estimated timeout —
     * and MeshCore does not retry, so lost means lost until somebody resends.
     */
    enum class Delivered { SENT, DELIVERED, LOST }

    private val _msgs = MutableStateFlow<List<Msg>>(emptyList())
    val msgs: StateFlow<List<Msg>> = _msgs.asStateFlow()

    /** Raised on arrival so the host can announce it. */
    var onMessage: ((Msg) -> Unit)? = null

    /**
     * E7 — a peer this app has never heard before just joined the mesh.
     *
     * Raised from [upsert], the one place that knows the difference between
     * "new" and "heard again"; every other caller sees a merged table and
     * cannot tell. Deliberately NOT raised for a bare advert from an unknown
     * key — a bare advert is a public key and nothing else, so announcing it
     * would be announcing a node whose name we cannot say.
     */
    var onNodeFound: ((MeshNodes.Peer) -> Unit)? = null

    /**
     * NOT DURING THE CONTACT SYNC, and the number that settled it is 113.
     *
     * Every contact the radio has ever stored arrives through [upsert] at
     * connect, so on a real mesh every one of them is "new" — 113 of them
     * inside about one second, measured on the Portland mesh 2026-08-10. Fired
     * as discovery that is not a mesh coming alive around you, it is a database
     * being read, and announcing it would be the single most annoying thing
     * this app does.
     *
     * E7 means "a peer entered the mesh WHILE I WAS WATCHING". So the signal is
     * suppressed until the sync that follows a connect has finished, which is
     * the same moment the loading vessel stops filling.
     */
    private var announceFinds = false

    /**
     * One conversation: a channel, or one person.
     *
     * [id] is the channel tag or the sender's key prefix — whichever it is,
     * every message in the thread shares it, which is the only grouping the
     * protocol actually supports. MeshCore has no thread identity of its own.
     */
    data class Thread(
        val id: String,
        val title: String,
        val direct: Boolean,
        val messages: List<Msg>,
    ) {
        val newest: Msg? get() = messages.firstOrNull()
    }

    /**
     * The message buffer as conversations, most recently active first.
     *
     * Grouped rather than interleaved because a flat feed is what a packet
     * monitor shows. People do not think in packets; they think "what did
     * Astor say" and "what is happening on the channel", and those are two
     * different questions that a single stream answers badly.
     */
    fun threads(): List<Thread> =
        _msgs.value
            .groupBy { if (it.direct) it.fromKey else (it.channel ?: "#") }
            .map { (id, ms) ->
                val first = ms.first()
                Thread(
                    id = id,
                    title = if (first.direct) {
                        first.fromName.ifBlank { id }
                    } else {
                        channelTitle(id, first.channelName)
                    },
                    direct = first.direct,
                    messages = ms,
                )
            }
            .sortedByDescending { it.newest?.atEpochSec ?: 0L }

    /**
     * WHAT TO CALL A CHANNEL, given that "#0" is not a name.
     *
     * `#0` is the radio's filing system — the slot number the hardware and the
     * phone app use — and it went straight onto the inbox row and the thread
     * header as though it were what people call the channel. Reported from the
     * glasses: "channel indicated as #0 is confusing. What is #0?"
     *
     * In order of authority: the name the radio reports for that slot, then the
     * name carried on the message itself, then PUBLIC if the slot is on the
     * well-known public key — a FACT about the channel rather than a guess from
     * its number, and the reason `Chan.publicKey` exists — and only then a
     * numbered fallback, which at least says what KIND of thing it is.
     */
    private fun channelTitle(threadId: String, fromMessage: String?): String {
        val idx = threadId.removePrefix("#").toIntOrNull()
        val slot = idx?.let { chans[it] }
        val named = slot?.name?.trim()?.ifBlank { null }
            ?: fromMessage?.trim()?.ifBlank { null }
        return when {
            named != null -> named
            slot?.publicKey == true ->
                context.getString(com.iotj.meshmore.xr.R.string.chan_public)
            idx != null ->
                context.getString(com.iotj.meshmore.xr.R.string.chan_numbered, idx)
            else -> context.getString(com.iotj.meshmore.xr.R.string.chan_generic)
        }
    }

    /**
     * History across restarts.
     *
     * Lazy rather than built in the constructor: MeshLink is created before the
     * scene is, and reading a preferences file is not something to do on the
     * way to first frame.
     */
    private val store by lazy { MsgStore(context) { Log.i(TAG, it) } }

    /**
     * Bring back what was said before the app was last closed.
     *
     * Call once. Restored messages do NOT fire onMessage: they are history, and
     * announcing forty of them at startup would ring the cuff, chime the audio
     * and light every arrival channel the app has for things the user read
     * yesterday.
     */
    fun restore() {
        if (_msgs.value.isNotEmpty()) return
        val old = store.load()
        if (old.isNotEmpty()) _msgs.value = old.take(MSG_KEEP)
    }

    private fun remember(m: Msg) {
        _msgs.value = (listOf(m) + _msgs.value).take(MSG_KEEP)
        // Written on arrival rather than at shutdown, because an XR app is
        // killed by the system far more often than it is closed by a person,
        // and onDestroy is not a promise.
        runCatching { store.save(_msgs.value) }
            .onFailure { Log.w(TAG, "[store] save failed: ${it.javaClass.simpleName}") }
        onMessage?.invoke(m)
    }

    /** Save without adding, for when only a message's STATE changed. */
    private fun persist() {
        runCatching { store.save(_msgs.value) }
            .onFailure { Log.w(TAG, "[store] save failed: ${it.javaClass.simpleName}") }
    }

    /**
     * Send an unanswered message again.
     *
     * MeshCore does not retry direct messages, so a lost one stays lost — and
     * two hours of measurement put that at roughly one in ten. Resending is
     * therefore not a convenience, it is the only recovery there is.
     *
     * NEW MESSAGE, NEW TAG. The mesh has no notion of "the same message twice",
     * so this is an ordinary send that happens to carry identical words, and it
     * goes through the same allow-list as everything else. The old line's state
     * is left alone: it really did go unanswered, and rewriting history to say
     * otherwise would be the app lying to make itself look better.
     */
    fun resend(m: Msg): Sent {
        if (!m.direct) return Sent.Refused("ONLY DIRECT MESSAGES CAN BE RESENT")
        val peer = peers.values.firstOrNull {
            (it.fullKey ?: it.key).startsWith(m.fromKey, ignoreCase = true) ||
                m.fromKey.startsWith(it.key, ignoreCase = true)
        } ?: return Sent.Refused("NOT IN CONTACTS")
        Log.i(TAG, "[tx] resending to '${peer.name}': '${m.text.take(32)}'")
        return sendDirect(peer, m.text)
    }

    /** The most recent message we sent that never came back. */
    fun lastUnanswered(): Msg? = _msgs.value.firstOrNull {
        it.fromName == "ME" && it.delivery == Delivered.LOST
    }

    /** Forget everything. The one thing a message log must always allow. */
    fun forgetMessages() {
        _msgs.value = emptyList()
        runCatching { store.clear() }
        Log.i(TAG, "[store] history cleared")
    }

    private val _here = MutableStateFlow(MeshNodes.Here(null, null))
    val here: StateFlow<MeshNodes.Here> = _here.asStateFlow()

    /**
     * Load a fabricated mesh, as though the radio had delivered it.
     *
     * INJECTED AT THE SOURCE rather than substituted at the surfaces. The mesh
     * is read from `link.mesh` in half a dozen places — the horizon, the
     * roster, the magnifier, the near-node menu — and a simulation that
     * intercepted each one would be testing the interception. Putting the peers
     * in the same table an advert fills means every one of those reads the fake
     * mesh without knowing it is fake, which is the only version of this worth
     * having.
     */
    fun loadSimulated(list: List<MeshNodes.Peer>) {
        list.forEach { peers[it.key] = it }
        _load.value = Load(done = true, total = list.size, received = list.size)
        Log.i(TAG, "[link] SIMULATED mesh: ${list.size} peers")
        publish()
    }

    private fun publish() {
        val v = peers.values.sortedBy { it.name }
        _mesh.value = v
        // Logged on completion only. A 254-contact sync logging per contact
        // floods the ring buffer and evicts the lines you actually need -- the
        // build and teardown events at either end of the load.
        if (_load.value.done || v.size % 50 == 0) {
            val withPos = v.count { it.lat != null && it.lon != null &&
                (kotlin.math.abs(it.lat) > 1e-7 || kotlin.math.abs(it.lon) > 1e-7) }
            Log.i(TAG, "[link] mesh: ${v.size} peers, $withPos with a position")
        }
    }

    /** The six-byte identity every source agrees on. Used as the map key. */
    private fun hex(b: ByteArray?): String =
        b?.take(6)?.joinToString("") { "%02x".format(it) } ?: ""

    /** The whole thing, when a source actually carries it. */
    private fun hexFull(b: ByteArray?): String? =
        b?.takeIf { it.size > 6 }?.joinToString("") { "%02x".format(it) }

    /**
     * A ROUTE APPEARING IS THE EVENT WE ARE WAITING FOR.
     *
     * The topology census measured 350 contacts and zero resolvable routes,
     * because this radio has only ever listened: MeshCore records a path when
     * a message ARRIVES, so a passive device learns none. The cheapest way to
     * change that is for somebody to message us — no transmission on our side
     * at all — and this says so out loud the moment it happens, rather than
     * leaving it to be noticed at the next contact sync.
     */
    private fun notePathChange(old: MeshNodes.Peer?, now: MeshNodes.Peer) {
        // ANY non-null path is a learned route. An EMPTY one means DIRECT —
        // no relays — and the first version tested isNotEmpty(), so it missed
        // exactly the case that arrived: the operator's DM taught this radio a
        // one-hop route and the watcher written to announce it said nothing.
        val had = old?.path != null
        val has = now.path != null
        if (!has || had) return
        val hops = now.path!!
        val how = if (hops.isEmpty()) "DIRECT, no relays"
                  else "${hops.size} relay(s): " + hops.joinToString(",") { "%02x".format(it) }
        Log.i(TAG, "[topology] ROUTE LEARNED for ${now.name.ifBlank { now.key }} — $how")
        diag("ROUTE    ${now.name.ifBlank { now.key.takeLast(4) }}  $how")
    }

    private fun upsert(p: MeshNodes.Peer) {
        val isNew = !peers.containsKey(p.key)
        // Merge rather than replace: an advert carries a position and a name, a
        // contact also carries the hop count. Whichever arrives second must not
        // erase what the first one knew.
        peers.compute(p.key) { _, old ->
            notePathChange(old, p)
            if (old == null) p else p.copy(
                name = p.name.ifBlank { old.name },
                lat = p.lat ?: old.lat,
                lon = p.lon ?: old.lon,
                hops = if (p.hops > 0) p.hops else old.hops,
                // An advert never carries the full key, so a later advert must
                // not erase what a contact told us.
                fullKey = p.fullKey ?: old.fullKey,
                favourite = p.favourite || old.favourite,
                telemetry = p.telemetry ?: old.telemetry,
                path = p.path ?: old.path,
                lastSeenEpochSec = maxOf(p.lastSeenEpochSec, old.lastSeenEpochSec),
            )
        }
        publish()
        // AFTER the table is consistent, never inside compute(): a listener
        // that reads the mesh from within a ConcurrentHashMap remapping is a
        // listener that can deadlock, and this one draws.
        if (isNew && announceFinds) runCatching { onNodeFound?.invoke(p) }
    }

    private var transport: AndroidBleTransport? = null
    private var session: MeshcoreSession? = null

    // --- link loss and recovery ----------------------------------------------

    /**
     * True once a handshake has completed. This is what makes a drop a drop:
     * DISCONNECTED before the first READY is a radio that was never found, and
     * retrying that on a timer is a scan loop nobody asked for.
     */
    private var everReady = false

    /** Has this session ever completed a handshake? The no-radio card keys on it. */
    val everConnected: Boolean get() = everReady

    /** Set by [close] so a deliberate shutdown does not immediately reconnect. */
    private var closedByUser = false

    /** Which rung of [RETRY_MS] the next attempt uses. */
    private var retryRung = 0

    private val retryHandler = Handler(Looper.getMainLooper())
    private var retry: Runnable? = null

    /** The arguments of the last [connect], so a retry reaches the same radio. */
    private var lastPrefix = "MeshCore"
    private var lastPin: String? = null

    /**
     * Come back on our own, on a widening interval.
     *
     * The wearer has no keyboard and, in a spatial scene, no reconnect button
     * within reach — the only one that existed was on the flat fallback surface,
     * which is not where anybody is when the radio drops. So the app has to be
     * the thing that keeps trying.
     *
     * THE LADDER WIDENS because the two causes want opposite things. A radio
     * that blinked (a body between it and the glasses, a moment of interference)
     * is back in seconds and a fast first retry catches it before the wearer
     * notices. A radio that is off, flat, or left at home is not coming back at
     * all, and scanning at full rate for the rest of a hike costs battery on the
     * one device that cannot be recharged from a pocket. Fast then patient
     * serves both.
     */
    private fun scheduleReconnect() {
        retry?.let { retryHandler.removeCallbacks(it) }
        val wait = RETRY_MS[retryRung.coerceAtMost(RETRY_MS.size - 1)]
        Log.i(TAG, "[link] reconnect in ${wait / 1000}s (rung $retryRung)")
        val r = Runnable {
            retry = null
            if (closedByUser) return@Runnable
            if (_status.value.state == SessionState.READY) return@Runnable
            // Tear the old session down FIRST. Its transport still holds a GATT
            // client for a device that is gone; opening a second one beside it
            // leaks the first and, on some stacks, is refused outright.
            runCatching { session?.close() }
            session = null
            transport = null
            retryRung++
            connect(lastPrefix, lastPin)
        }
        retry = r
        retryHandler.postDelayed(r, wait)
    }

    /**
     * Keep going after a reconnect ATTEMPT fails.
     *
     * [scheduleReconnect] fires once per drop; without this, a retry whose scan
     * timed out — the overwhelmingly likely outcome while the radio is still out
     * of range — would be the last one, and the app would sit blind forever
     * having tried exactly once. Only ever re-arms while [Status.droppedAtMs] is
     * set, so a cold start that cannot find a radio still fails quietly instead
     * of scanning for the rest of the day.
     */
    private fun retryIfDropped() {
        if (_status.value.droppedAtMs != null && !closedByUser) scheduleReconnect()
    }

    fun hasBlePermissions(): Boolean =
        listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
            .all { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }

    /** Scan for a radio whose advert name starts with [namePrefix], then handshake. */
    fun connect(namePrefix: String = "MeshCore", pin: String? = null) {
        // A RECONNECT REPLAYS THE WHOLE CONTACT LIST, so the suppression has to
        // re-arm here and not only at construction. Otherwise the second
        // connect of a session announces 113 strangers.
        announceFinds = false
        lastPrefix = namePrefix
        lastPin = pin
        closedByUser = false
        retry?.let { retryHandler.removeCallbacks(it); retry = null }
        if (!hasBlePermissions()) {
            Log.w(TAG, "[link] BLE permission not granted — fail safe, no scan")
            _status.value = _status.value.copy(error = "BLE permission denied", lastEvent = "permission")
            return
        }
        val bm = context.getSystemService(BluetoothManager::class.java)
        val adapter = bm?.adapter
        if (adapter == null || !adapter.isEnabled) {
            Log.w(TAG, "[link] bluetooth off/absent — Tier 0, app stays usable")
            _status.value = _status.value.copy(error = "Bluetooth off", lastEvent = "bt-off")
            // Worth continuing to wait on: an adapter that is off can be turned
            // back on, and on glasses that is done somewhere this app cannot see.
            retryIfDropped()
            return
        }
        val scanner = adapter.bluetoothLeScanner ?: run {
            _status.value = _status.value.copy(error = "no BLE scanner")
            return
        }

        Log.i(TAG, "[link] scan start prefix='$namePrefix'")
        _status.value = _status.value.copy(scanning = true, lastEvent = "scanning", error = null)

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        // CHOOSE, DO NOT RACE. A mesh is by definition a place where several
        // MeshCore radios are in range, and this used to take whatever answered
        // FIRST. With a neighbour's node nearer than the user's own, that meant
        // grabbing a stranger, offering it our PIN, and failing the bond --
        // "bond 11 -> 10" and then silence -- while the user's own paired radio
        // sat a metre away untouched.
        //
        // So: collect for a short settle window, then rank. A radio we are
        // already BONDED to wins outright, because a bond is the user having
        // already said "this one is mine". Among strangers, take the strongest
        // signal: the user's radio is the one on their person, and arrival order
        // is not a property of anything we care about.
        //
        // The ranking happens over SCAN RESULTS rather than over the adapter's
        // bond list, deliberately. Going straight to a bonded address without
        // scanning connects to a radio that is switched off just as happily as
        // to one that is on, and then waits forever -- which is exactly how this
        // looked before: "already bonded, connecting", and no state change ever.
        // A device in the scan results is a device that is actually there.
        val seen = LinkedHashMap<String, ScanResult>()
        val others = LinkedHashSet<String>()
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val name = try { result.device.name } catch (_: SecurityException) { null } ?: return
                if (!name.startsWith(namePrefix, ignoreCase = true)) {
                    // NAME THE AIR. "no radio found" with a silent scan is
                    // undiagnosable from a log: the radio being off, renamed,
                    // or captured by another central all look identical.
                    // Logging every named stranger once turns two of those
                    // into a visible fact — a renamed radio appears here under
                    // its new name, and an empty list says the radio is not
                    // advertising at all (off, or connected elsewhere).
                    if (others.size < 12 && others.add(name)) {
                        Log.i(TAG, "[link] in the air (not ours): '$name' rssi=${result.rssi}")
                    }
                    return
                }
                if (seen.put(result.device.address, result) == null) {
                    Log.i(TAG, "[link] found '$name' rssi=${result.rssi}")
                }
            }

            override fun onScanFailed(errorCode: Int) {
                Log.e(TAG, "[link] scan failed code=$errorCode")
                _status.value = _status.value.copy(scanning = false, error = "scan failed $errorCode")
                retryIfDropped()
            }
        }
        scanner.startScan(emptyList(), settings, cb)

        // SETTLE, THEN CHOOSE — AND KEEP LISTENING UNTIL THERE IS SOMETHING TO
        // CHOOSE FROM.
        //
        // The first version stopped the scan unconditionally at the end of the
        // settle window and only then checked whether it had heard anything. A
        // radio whose advert did not land inside that first 1.5 s was therefore
        // invisible forever, and the log said "still listening" while the
        // scanner was already stopped -- so the failure presented as a dead
        // radio when the radio was fine and we had stopped looking. Adverts are
        // not on our schedule; the window has to re-arm.
        val handler = Handler(Looper.getMainLooper())
        var waited = 0L
        lateinit var settle: Runnable
        settle = Runnable {
            if (!_status.value.scanning) return@Runnable
            // Bonded first, then signal. compareBy is ascending, so maxWith over
            // (isBonded, rssi) picks a bonded radio if there is one and the
            // loudest stranger otherwise.
            val best = seen.values.maxWithOrNull(
                compareBy<ScanResult>({ if (it.device.bondState == BluetoothDevice.BOND_BONDED) 1 else 0 }, { it.rssi })
            )
            if (best == null) {
                waited += SCAN_SETTLE_MS
                if (waited >= SCAN_TIMEOUT_MS) {
                    scanner.stopScan(cb)
                    Log.w(TAG, "[link] no radio named '$namePrefix*' after ${SCAN_TIMEOUT_MS / 1000}s")
                    _status.value = _status.value.copy(
                        scanning = false, error = "no radio found", lastEvent = "timeout")
                    retryIfDropped()
                } else {
                    handler.postDelayed(settle, SCAN_SETTLE_MS)
                }
                return@Runnable
            }
            scanner.stopScan(cb)
            val name = runCatching { best.device.name }.getOrNull() ?: best.device.address
            val why = if (best.device.bondState == BluetoothDevice.BOND_BONDED) "bonded" else "strongest"
            Log.i(TAG, "[link] ${seen.size} candidate(s) after ${waited + SCAN_SETTLE_MS}ms — " +
                "$why '$name' rssi=${best.rssi}")
            _status.value = _status.value.copy(scanning = false, deviceName = name, lastEvent = "found $name")
            bondThenOpen(best.device, pin)
        }
        handler.postDelayed(settle, SCAN_SETTLE_MS)
    }

    /**
     * MeshCore's companion_radio_ble variant is built with BLE_PIN_CODE, so the
     * radio requires a bonded (encrypted) link before its GATT characteristics
     * answer. Without this the transport connects, service discovery succeeds,
     * APP_START goes out -- and the session sits in HANDSHAKING forever, which
     * is exactly what it looks like when you forget to pair.
     *
     * We supply the PIN programmatically rather than dropping the user into the
     * system pairing dialog: on glasses that dialog is a poor experience, and
     * for a fixed-PIN build there is nothing for the user to decide. A radio
     * built with a random PIN would need the dialog (or the QR path in S2 LINK).
     */
    private fun bondThenOpen(device: BluetoothDevice, pin: String?) {
        if (device.bondState == BluetoothDevice.BOND_BONDED) {
            Log.i(TAG, "[link] already bonded — connecting")
            openSession(device)
            return
        }
        Log.i(TAG, "[link] not bonded — createBond() " +
            if (pin != null) "with explicit PIN" else "(system dialog will ask for the code)")
        _status.value = _status.value.copy(lastEvent = "pairing")

        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_PAIRING_REQUEST)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                when (intent.action) {
                    BluetoothDevice.ACTION_PAIRING_REQUEST -> {
                        // BLE has several pairing variants and they need
                        // DIFFERENT responses. Answering a passkey-confirmation
                        // with setPin() silently fails the bond, which is what
                        // "bond 11 -> 10" looks like.
                        val variant = intent.getIntExtra(BluetoothDevice.EXTRA_PAIRING_VARIANT, -1)
                        val key = intent.getIntExtra(BluetoothDevice.EXTRA_PAIRING_KEY, -1)
                        Log.i(TAG, "[link] pairing request variant=$variant key=$key")
                        runCatching {
                            when (variant) {
                                // PAIRING_VARIANT_PIN(0) / PASSKEY(1).
                                //
                                // THE DIALOG IS THE PLAN, not a failure mode.
                                // This firmware regenerates its PIN every boot
                                // and shows it on the radio's screen; an app
                                // constant can never be right, and the old one
                                // ("888294", one long-dead boot's number)
                                // auto-replied AND suppressed the system
                                // dialog — so every real pairing failed
                                // silently, and adb with --es pin was the only
                                // path that ever worked. When no explicit PIN
                                // was supplied we now do NOTHING here: the
                                // system pairing dialog appears, the XR soft
                                // keyboard raises with it, and the wearer
                                // types the six digits straight off the
                                // radio's screen. Auto-reply survives only for
                                // an explicitly provided PIN (the test flag).
                                0, 1 -> {
                                    if (pin != null) {
                                        val ok = device.setPin(pin.toByteArray())
                                        Log.i(TAG, "[link] setPin(explicit) -> $ok")
                                    } else {
                                        Log.i(TAG, "[link] passkey wanted — leaving the system dialog to ask")
                                        return@runCatching
                                    }
                                }
                                // PASSKEY_CONFIRMATION(2) / CONSENT(3): just say yes
                                2, 3 -> {
                                    val ok = device.setPairingConfirmation(true)
                                    Log.i(TAG, "[link] setPairingConfirmation -> $ok")
                                }
                                else -> Log.w(TAG, "[link] unhandled pairing variant $variant")
                            }
                            abortBroadcast()   // suppress the system dialog
                        }.onFailure { Log.w(TAG, "[link] pairing response failed: $it") }
                    }
                    BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                        val st = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, -1)
                        Log.i(TAG, "[link] bond state -> $st")
                        if (st == BluetoothDevice.BOND_BONDED) {
                            runCatching { context.unregisterReceiver(this) }
                            openSession(device)
                        } else if (st == BluetoothDevice.BOND_NONE) {
                            runCatching { context.unregisterReceiver(this) }
                            _status.value = _status.value.copy(error = "pairing failed", lastEvent = "bond-fail")
                            retryIfDropped()
                        }
                    }
                }
            }
        }
        context.registerReceiver(receiver, filter)
        if (!device.createBond()) {
            Log.w(TAG, "[link] createBond() refused")
            runCatching { context.unregisterReceiver(receiver) }
            _status.value = _status.value.copy(error = "createBond refused")
        }
    }

    /**
     * WHAT HAPPENED TO THE MESSAGES WE SENT.
     *
     * Three numbers that are genuinely different: how many we handed to the
     * radio, how many the radio accepted for transmission, and how many the
     * far end acknowledged. On a mesh the gap between the second and third is
     * the only honest measure of reliability, and nothing in this app was
     * counting it.
     */
    data class Delivery(
        val attempted: Int = 0,
        val accepted: Int = 0,
        val acked: Int = 0,
        val refused: Int = 0,
        val lastTag: Long = 0L,
        val lastLatencyMs: Long? = null,
        val totalLatencyMs: Long = 0L,
    ) {
        /** Acked over accepted, as a percentage; null when nothing was sent. */
        val reliability: Double?
            get() = if (accepted == 0) null else acked * 100.0 / accepted
        val meanLatencyMs: Long? get() = if (acked == 0) null else totalLatencyMs / acked
    }

    private val _delivery = MutableStateFlow(Delivery())
    val delivery: StateFlow<Delivery> = _delivery.asStateFlow()

    /**
     * The message whose SENT confirmation has not arrived yet.
     *
     * Set the instant a send is handed to the radio and cleared by the very
     * next MsgSentFrame. One at a time is not an assumption about the protocol
     * being polite — the app only ever has one send in flight, because a send
     * is a deliberate act by a wearer.
     */
    private var awaitingTag: Msg? = null

    private fun tagMessage(m: Msg, tag: Long) {
        _msgs.value = _msgs.value.map {
            if (it === m) it.copy(ackTag = tag, delivery = Delivered.SENT) else it
        }
        persist()
    }

    private fun markDelivered(tag: Long) {
        var hit = false
        _msgs.value = _msgs.value.map {
            if (it.ackTag == tag && it.delivery != Delivered.DELIVERED) {
                hit = true
                it.copy(delivery = Delivered.DELIVERED)
            } else {
                it
            }
        }
        if (hit) persist()
    }

    /**
     * Give up on anything still unacknowledged past [afterMs].
     *
     * The radio publishes its own estimated round trip — about 2.2 s direct,
     * 8 s flooded — and everything measured in two hours of soak came back
     * inside 2.4 s. A minute is therefore not a judgement call, it is a
     * generous multiple of the longest thing ever observed.
     */
    fun sweepLost(afterMs: Long = 60_000L, nowMs: Long = System.currentTimeMillis()) {
        val stale = pending.filter { nowMs - it.value > afterMs }.keys
        if (stale.isEmpty()) return
        stale.forEach { pending.remove(it) }
        var hit = false
        _msgs.value = _msgs.value.map {
            if (it.ackTag in stale && it.delivery == Delivered.SENT) {
                hit = true
                Log.w(TAG, "[tx] no ack for tag=0x%08x — marking lost".format(it.ackTag))
                it.copy(delivery = Delivered.LOST)
            } else {
                it
            }
        }
        if (hit) persist()
    }

    /** Ack tags we are waiting on, and when each was accepted. */
    private val pending = java.util.concurrent.ConcurrentHashMap<Long, Long>()

    /** Sent but never acknowledged within the window; the drops. */
    fun lostAfter(ms: Long, nowMs: Long = System.currentTimeMillis()): Int =
        pending.count { nowMs - it.value > ms }

    fun noteAttempt(ok: Boolean) {
        _delivery.value = _delivery.value.copy(
            attempted = _delivery.value.attempted + 1,
            refused = _delivery.value.refused + if (ok) 0 else 1,
        )
    }

    /** What the radio said it is, once DEVICE_QUERY has been answered. */
    var deviceInfo: io.iotone.meshcore.model.DeviceInfo? = null
        private set

    /** How many contacts this radio can hold; 0 until the query is answered. */
    var maxContacts: Int = 0
        private set

    /** Set before connect to make the connect-time advert a flood. */
    var floodOnConnect: Boolean = false

    /** The radio's own configuration: staged, committed, recoverable (§9.6.5). */
    val radio = RadioConfig(context) { Log.i(TAG, "[radio] $it") }

    /**
     * Send the staged parameter set to the radio, as ONE command.
     *
     * The previous set is written to disk before anything goes out, so a crash
     * between the two leaves a way back rather than losing one. Nothing here
     * verifies the result, because nothing can: see RadioConfig's class doc.
     */
    fun commitRadio(): Boolean {
        val s = session
        if (s == null || _status.value.state != SessionState.READY) {
            Log.w(TAG, "[radio] commit skipped — link not ready")
            return false
        }
        if (!radio.dirty()) { Log.i(TAG, "[radio] nothing staged"); return false }
        val next = radio.commit() ?: return false
        diag(">>RADIO  COMMIT ${next.pretty()}")
        s.setRadioParams(
            io.iotone.meshcore.model.RadioParams.of(
                next.freqMhz, next.bandwidthKhz, next.spreadingFactor, next.codingRate,
            )
        )
        s.setTxPower(next.txDbm)
        // A parameter change can only be proven by hearing something afterwards,
        // and a quiet mesh proves nothing -- but announcing ourselves on the new
        // configuration is the one action that gives the change a chance to be
        // noticed by somebody else.
        announce(false)
        return true
    }

    /** Put the radio back on the set it was running before the last commit. */
    fun revertRadio(): Boolean {
        val s = session
        if (s == null || _status.value.state != SessionState.READY) return false
        val p = radio.takePrevious() ?: run { Log.i(TAG, "[radio] no previous set"); return false }
        diag(">>RADIO  REVERT ${p.pretty()}")
        s.setRadioParams(
            io.iotone.meshcore.model.RadioParams.of(
                p.freqMhz, p.bandwidthKhz, p.spreadingFactor, p.codingRate,
            )
        )
        s.setTxPower(p.txDbm)
        announce(false)
        return true
    }

    /** Rename the node as it advertises itself. */
    fun setNodeName(name: String) {
        val s = session ?: return
        if (_status.value.state != SessionState.READY) return
        Log.i(TAG, "[radio] advert name -> '$name'")
        diag(">>RADIO  name '$name'")
        s.setAdvertName(name)
        announce(false)
    }

    // ---- DIAGNOSTICS ------------------------------------------------------
    //
    // A rolling transcript of every frame the codec decodes. This exists
    // because "the radio is quiet" and "the radio is talking and we are
    // dropping it" are indistinguishable from the horizon, and the difference
    // is the whole debugging problem. Logcat has this, but logcat is not
    // available to someone wearing the glasses.

    private val _diag = MutableStateFlow<List<String>>(emptyList())
    val diag: StateFlow<List<String>> = _diag.asStateFlow()

    /** Bounded: this is a tail, not a recording. */
    private fun diag(line: String) {
        val stamp = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US)
            .format(java.util.Date())
        _diag.value = (_diag.value + "$stamp  $line").takeLast(DIAG_MAX)
    }

    fun clearDiag() { _diag.value = emptyList() }

    /**
     * Give the radio a position to advertise, and permission to advertise it.
     *
     * THE RADIO WAS ANNOUNCING ITSELF AT 0/0. Two separate reasons, and fixing
     * either alone changes nothing:
     *
     *  - It has no GPS, so its stored position is 0/0 -- which is not a blank,
     *    it is the Gulf of Guinea. Other nodes were free to plot it there.
     *  - advertLocPolicy was 0, meaning "omit position from adverts" however
     *    good the position is.
     *
     * The position we send is the one the horizon is already measured from, so
     * what we tell the mesh and what we draw cannot disagree.
     *
     * THIS BROADCASTS WHERE YOU ARE, to a public channel, unencrypted. That is
     * a materially different act from using the same fix locally to compute
     * bearings, so it is a separate setting -- enabling headset GPS does not
     * silently start telling everyone about it.
     */
    fun publishPosition(here: MeshNodes.Here) {
        val s = session
        if (s == null || _status.value.state != SessionState.READY) return
        if (!here.known) return
        // DEDUPE, and re-advertise only on a real move. A GPS fix jitters by
        // metres every second; re-announcing on every wobble would put an
        // advert on a shared channel several times a minute for no new
        // information. MOVE_DEG is about 11 m.
        val prev = published
        val moved = prev == null ||
            kotlin.math.abs(prev.lat!! - here.lat!!) > MOVE_DEG ||
            kotlin.math.abs(prev.lon!! - here.lon!!) > MOVE_DEG
        if (!moved) return
        published = here
        // Remembered across launches too: see RadioFacts.notePublished. A
        // radio with no GNSS will hand this exact position back to us next
        // time, and without this the app has no way to know it wrote it.
        RadioFacts.notePublished(context, here.lat!!, here.lon!!, System.currentTimeMillis())
        Log.i(TAG, "[link] advertising position ${here.lat}, ${here.lon} (policy -> share)")
        diag(">>POS    %.5f, %.5f  policy=share".format(here.lat, here.lon))
        s.setAdvertPosition(here.lat!!, here.lon!!)
        s.setAdvertLocPolicy(LOC_POLICY_SHARE)
        // The position only reaches the mesh inside an advert, so one goes out
        // with it -- and only here, on an actual change.
        announce(false)
    }

    private var published: MeshNodes.Here? = null

    /**
     * Put a self-advert on the air, so other nodes learn this radio exists.
     *
     * [flood] false is zero-hop -- direct neighbours only. True propagates
     * through every repeater that hears it, which is how you become visible
     * across a whole mesh and also how you spend everyone else's airtime.
     */
    /**
     * PATH PROBE — send to a peer so the mesh tells us how it gets there.
     *
     * MeshCore learns a stored route when a contact ANSWERS: the reply carries
     * the path back and the radio keeps it. A device that has only ever
     * received adverts therefore has no routes at all, which is exactly what
     * the topology census measured on 2026-08-03 — 350 contacts, 350 flood,
     * zero resolvable. Sending is the only thing that moves that number.
     *
     * STRICTLY ALLOW-LISTED, and this is the whole reason the method exists in
     * this shape. Sending puts a packet on a shared radio band addressed to
     * somebody else's hardware, so it is not something to sweep a contact list
     * with. [ALLOWED_SUFFIXES] holds the ONLY keys this app will message —
     * nodes the operator owns and explicitly authorised on 2026-08-03. A key
     * that is not in that list is refused and logged, not sent.
     */
    /**
     * WHAT HAPPENED TO A REPLY. Not a boolean: "it did not send" and "it is not
     * allowed to send" are different facts and the surface has to say which.
     */
    sealed class Sent {
        object Ok : Sent()
        object NotReady : Sent()
        /** [why] is shown to the wearer verbatim, so it is written for them. */
        class Refused(val why: String) : Sent()
    }

    /**
     * CHANNEL TRANSMIT IS OFF, and this is a deliberate default rather than an
     * oversight.
     *
     * The operator's standing authorisation (2026-08-03) covers NODES they own:
     * "my own nodes I am comfortable sending to end in ab60 and d563". A direct
     * message to one of those is squarely inside it. A CHANNEL message is not
     * the same act -- it puts a packet on a shared band addressed to everyone
     * listening on that channel, most of whom are strangers -- so it is not
     * covered by permission to talk to your own hardware, and quietly treating
     * it as if it were would be helping myself to a wider licence than was
     * given.
     *
     * Flip it when you want the app to speak on channels. Nothing else needs
     * to change; the reply path is already built for it.
     */
    var channelTxAuthorised: Boolean = false

    /**
     * Answer a message where it came from: the channel if it was a channel, the
     * sender if it was direct.
     *
     * The allow-list is enforced HERE, at the one place that transmits, rather
     * than by whichever surface happens to be calling. A guard that lives in
     * the UI is a guard that the next surface forgets.
     */
    fun replyTo(m: Msg, text: String): Sent {
        val s = session
        if (s == null || _status.value.state != SessionState.READY) return Sent.NotReady
        if (text.isBlank()) return Sent.Refused("NOTHING TO SEND")

        if (!m.direct) {
            val idx = m.channel?.removePrefix("#")?.toIntOrNull()
                ?: return Sent.Refused("UNKNOWN CHANNEL")
            if (!channelTxAuthorised) {
                Log.w(TAG, "[tx] channel reply refused — channel TX not authorised")
                return Sent.Refused("CHANNEL SEND IS OFF")
            }
            return runCatching {
                s.sendChannelMessage(idx, System.currentTimeMillis() / 1000, text)
                diag(">>CHAN ${m.channelName ?: m.channel}")
                Log.i(TAG, "[tx] -> channel $idx")
                Sent.Ok as Sent
            }.getOrElse { Sent.Refused("SEND FAILED") }
        }

        val peer = peers.values.firstOrNull {
            m.fromKey.isNotBlank() &&
                ((it.fullKey ?: it.key).startsWith(m.fromKey, ignoreCase = true) ||
                    m.fromKey.startsWith(it.key, ignoreCase = true))
        } ?: return Sent.Refused("SENDER NOT IN CONTACTS")
        return sendDirect(peer, text)
    }

    /**
     * SPEAK FIRST. Start a conversation with a node that has never sent you
     * one.
     *
     * Until now every path to the radio's transmitter began with somebody
     * else's message: reply to a card, reply in a thread. A node you had never
     * heard from could be starred, ranged, asked for telemetry — and not
     * addressed, which for a messaging application is the one verb that cannot
     * be missing. MESSAGE on such a node answered "NO THREAD YET", which is a
     * true statement of the app's own limitation offered as though it were a
     * fact about the mesh.
     *
     * Same transmitter, same allow-list, same one place that refuses.
     */
    fun sendTo(peerKey: String?, text: String): Sent {
        if (session == null || _status.value.state != SessionState.READY) return Sent.NotReady
        if (text.isBlank()) return Sent.Refused("NOTHING TO SEND")
        val want = peerKey?.trim().orEmpty()
        if (want.isEmpty()) return Sent.Refused("NO ADDRESS")
        val peer = peers.values.firstOrNull {
            (it.fullKey ?: it.key).startsWith(want, ignoreCase = true) ||
                want.startsWith(it.key, ignoreCase = true)
        } ?: return Sent.Refused("NOT IN CONTACTS")
        return sendDirect(peer, text)
    }

    /** The one path to the transmitter for a direct message. */
    private fun sendDirect(peer: MeshNodes.Peer, text: String): Sent {
        val s = session ?: return Sent.NotReady
        if (!isAllowed(peer)) {
            // Named, so the refusal is checkable rather than mysterious.
            Log.w(TAG, "[tx] refused — '${peer.name}' key=${peer.key} not in $ALLOWED_SUFFIXES")
            return Sent.Refused("NOT AN AUTHORISED NODE")
        }
        val full = unhex(peer.fullKey ?: peer.key)
        if (full == null || full.size < 6) return Sent.Refused("UNUSABLE KEY")
        Log.i(TAG, "[tx] -> name='${peer.name}' key=${peer.key} (authorised)")
        diag(">>DM   ${peer.name.ifBlank { peer.key.takeLast(4) }}")
        return runCatching {
            s.sendDirectMessage(
                full.copyOfRange(0, 6), System.currentTimeMillis() / 1000, text,
            )
            // OUR OWN WORDS GO IN THE LOG TOO. A conversation that shows only
            // the other half is not a conversation, and the thread corridor
            // already knows how to draw a line as mine.
            val mine = Msg(
                fromKey = peer.key, fromName = "ME", text = text,
                atEpochSec = System.currentTimeMillis() / 1000,
                direct = true, channel = null,
                delivery = Delivered.SENT,
            )
            remember(mine)
            // The radio answers with the tag a moment from now; this is the
            // message it belongs to.
            awaitingTag = mine
            Sent.Ok as Sent
        }.getOrElse { Sent.Refused("SEND FAILED") }
    }

    /**
     * WHAT A GARBAGE COLLECTION WOULD TAKE, and why each one is safe to take.
     *
     * A companion radio holds a fixed number of contacts. A mesh that has been
     * running for months fills that store with nodes heard once, from a
     * hilltop, at 300 km — and when it is full the radio stops accepting new
     * ones. The node that matters, the one in the same room, cannot be added.
     * The operator is then locked out of their own hardware by a list of
     * strangers, which is exactly what happened here on 2026-08-16.
     *
     * FOUR THINGS ARE NEVER COLLECTED, and the order of these checks is the
     * safety argument:
     *  1. Anything on the allow-list. These are the operator's OWN radios —
     *     the only nodes this app may transmit to — and a sweep that removed
     *     one would delete the thing the sweep was run to make room for.
     *  2. Favourites. A star is the wearer saying "this one matters"; nothing
     *     automatic gets to overrule that.
     *  3. Anything without a usable position. No position is not evidence of
     *     distance — a GPS-less board reports 0/0 forever — and treating
     *     unknown as far would collect the quiet local nodes first.
     *  4. Anything nearer than [km]. That is the whole criterion.
     *
     * Returns the candidates rather than acting, so a caller can count them,
     * name them, and ask before anything is destroyed.
     */
    /**
     * THE ONE RULE ABOUT WHAT MAY BE FORGOTTEN, so two callers cannot disagree.
     *
     * The distance sweep and the filter-driven bulk forget arrive at their
     * candidates completely differently — one measures, one is handed whatever
     * the wearer narrowed to — and both must refuse the same things. Written
     * once, here, beside the transmitter that enforces the other allow-list.
     *
     * Never: the operator's own radios (the sweep exists to make room FOR
     * them), favourites (a star outranks anything automatic), and anything
     * without a full 32-byte key (REMOVE_CONTACT is keyed by the whole thing;
     * a prefix would either miss or match something else).
     */
    fun forgettable(
        candidates: List<MeshNodes.Peer>,
        isFavourite: (String) -> Boolean = { false },
    ): List<MeshNodes.Peer> = candidates.filter { p ->
        when {
            isAllowed(p) -> false
            // BOTH KINDS OF STAR. A favourite set on the RADIO arrives on the
            // peer's own flag and a favourite set in this app lives in
            // NodeTags; the ring and the search list draw them identically, so
            // a sweep that honoured only one would delete a node the wearer
            // can see is starred. Caught on the emulator: 'Alberta Base' sat
            // in a FORGET 76 with a filled star beside it.
            p.favourite -> false
            isFavourite(p.fullKey ?: p.key) -> false
            (p.fullKey?.length ?: 0) < 64 -> false
            else -> true
        }
    }

    fun farContacts(
        origin: MeshNodes.Here,
        km: Double,
        isFavourite: (String) -> Boolean = { false },
    ): List<MeshNodes.Peer> {
        if (!origin.known) return emptyList()
        val oLat = origin.lat ?: return emptyList()
        val oLon = origin.lon ?: return emptyList()
        return forgettable(peers.values.toList(), isFavourite).filter { p ->
            val lat = p.lat
            val lon = p.lon
            when {
                lat == null || lon == null -> false
                kotlin.math.abs(lat) < 1e-7 && kotlin.math.abs(lon) < 1e-7 -> false
                else -> MeshNodes.haversineKm(oLat, oLon, lat, lon) >= km
            }
        }.sortedByDescending { p ->
            MeshNodes.haversineKm(oLat, oLon, p.lat ?: 0.0, p.lon ?: 0.0)
        }
    }

    /**
     * Forget one contact, on the radio.
     *
     * NOT A BLOCK. The radio drops it from its store and frees the slot; if
     * that node adverts again it is learned again. Every caller must say so —
     * "forget" rather than "delete" — because a wearer who thinks this stops
     * someone contacting them is wrong in a way that matters.
     */
    fun forgetContact(peer: MeshNodes.Peer): Boolean {
        val s = session
        if (s == null || _status.value.state != SessionState.READY) return false
        if (isAllowed(peer)) {
            // The one refusal that is not about safety of the air but about
            // the operator's own kit. Loud, because a silent no here would
            // look like a bug in the sweep.
            Log.w(TAG, "[gc] refused to forget own node '${peer.name}' (${peer.key})")
            return false
        }
        val full = unhex(peer.fullKey ?: peer.key) ?: return false
        if (full.size < 32) {
            // REMOVE_CONTACT is keyed by the FULL 32 bytes. A prefix would
            // either miss or, far worse, match something else.
            Log.w(TAG, "[gc] no full key for '${peer.name}' — not forgetting on a prefix")
            return false
        }
        return runCatching {
            s.removeContact(full)
            peers.remove(peer.key)
            diag("--DROP ${peer.name.ifBlank { peer.key.takeLast(4) }}")
            Log.i(TAG, "[gc] forgot '${peer.name}' key=${peer.key}")
            _mesh.value = peers.values.toList()
            true
        }.getOrElse {
            Log.w(TAG, "[gc] remove failed for ${peer.key}: $it")
            false
        }
    }

    /** Forget many. Returns how many the radio was actually told to drop. */
    fun forgetContacts(list: List<MeshNodes.Peer>): Int =
        list.count { forgetContact(it) }

    fun probePaths(text: String = "meshmore-xr path probe") {
        val s = session
        if (s == null || _status.value.state != SessionState.READY) {
            Log.w(TAG, "[probe] skipped — link not ready")
            return
        }
        val targets = peers.values.filter { isAllowed(it) }
        if (targets.isEmpty()) {
            // WHERE ELSE THE STRING MIGHT LIVE. A MeshCore node is quoted by
            // people in several ways — the head of the key, the tail, or just
            // its name — so say which of those matched anything before
            // concluding the node is absent.
            ALLOWED_SUFFIXES.forEach { sfx ->
                val named = peers.values.filter { it.name.contains(sfx, ignoreCase = true) }
                Log.w(TAG, "[probe] '$sfx': nameMatches=${named.size}" +
                    (named.firstOrNull()?.let { " e.g. '${it.name}' key=${it.key}" } ?: ""))
            }
            Log.w(TAG, "[probe] full keys are " +
                (peers.values.firstOrNull { it.fullKey != null }?.fullKey?.length ?: 0) +
                " hex; with full=" + peers.values.count { it.fullKey != null } +
                "/" + peers.size)
            peers.values.filter { it.fullKey != null }.take(3).forEach {
                Log.w(TAG, "[probe] e.g. ${it.name.take(16)} = ${it.fullKey}")
            }
            Log.w(TAG, "[probe] none of the allowed nodes are in contacts: $ALLOWED_SUFFIXES")
            return
        }
        targets.forEach { p ->
            val full = unhex(p.fullKey ?: p.key)
            if (full == null || full.size < 6) {
                Log.w(TAG, "[probe] ${p.name}: unusable key")
                return@forEach
            }
            // The command takes the first six bytes, not the whole identity.
            val prefix = full.copyOfRange(0, 6)
            // BOTH identifiers, before transmitting. A name matched an
            // allow-list entry; the key says which physical radio that is.
            Log.i(TAG, "[probe] -> name='${p.name}' key=${p.key} (authorised)")
            diag(">>PROBE  ${p.name.ifBlank { p.key.takeLast(4) }}")
            s.sendDirectMessage(prefix, System.currentTimeMillis() / 1000, text)
            // And ask what it is while we are talking to it. Needs the WHOLE
            // key, so a peer we only ever heard advert cannot be asked.
            if (full.size >= 32) {
                runCatching { s.requestPeerTelemetry(full) }
                    .onFailure { Log.w(TAG, "[probe] telemetry req failed: $it") }
            } else {
                Log.w(TAG, "[probe] ${p.name}: no full key, telemetry not requested")
            }
        }
        _status.value = _status.value.copy(lastEvent = "probe")
    }

    /**
     * Who may ask this radio what it knows.
     *
     * A GUARDED write, like the rack's link-breaking fields: this is the only
     * setting in the app that decides what leaves the device about the person
     * wearing it, and LOCATION is not the same decision as battery level.
     */
    fun setTelemetryPermissions(p: com.iotj.meshmore.xr.spatial.TelemetryPerms.Perms) {
        val s = session
        if (s == null || _status.value.state != SessionState.READY) {
            Log.w(TAG, "[telemetry] set skipped — link not ready")
            return
        }
        Log.i(TAG, "[telemetry] permissions -> $p (packed=0x%02x)".format(p.packed()))
        diag(">>TELPERM $p")
        s.setTelemetryPermissions(p.packed())
    }

    /** What the radio currently allows, straight from the last SELF_INFO. */
    fun telemetryPermissions(): com.iotj.meshmore.xr.spatial.TelemetryPerms.Perms =
        com.iotj.meshmore.xr.spatial.TelemetryPerms.unpack(
            _status.value.selfInfo?.telemetryModeRaw() ?: 0,
        )

    /**
     * May this app OPEN A CONVERSATION with this node?
     *
     * The same allow-list [isAllowed] enforces at transmit time, exposed so a
     * surface can decline BEFORE offering a compose — a MESSAGE action that
     * opens a keyboard and then refuses on send is a trap, not a guard. The
     * refusal inside [reply] stays; this is the polite copy of it.
     */
    /**
     * The same rule [isAllowed] transmits under, asked before a surface opens.
     *
     * It must be the same rule and not a similar one: a compose screen that
     * appears for a node the transmitter will refuse is a trap, and one that
     * refuses a node the transmitter would accept is a bug nobody can see.
     */
    fun mayMessage(name: String, fullKey: String?): Boolean {
        val full = fullKey?.lowercase()
        if (full != null && OwnNodes.isPinned(context, full)) return true
        return ALLOWED_SUFFIXES.any { name.endsWith(it, ignoreCase = true) }
    }

    /**
     * Ask one peer for its telemetry, by full 32-byte key.
     *
     * MANUAL AND SINGULAR, which is the whole courtesy argument: a request
     * costs the other node battery and shared airtime, so it happens when a
     * wearer asks about a node they are looking at — never on a timer, never
     * swept across the mesh. The reply arrives as a telemetry frame and lands
     * on the peer like any other.
     */
    fun askTelemetry(fullKeyHex: String?): Boolean {
        val s = session
        if (s == null || _status.value.state != SessionState.READY) {
            Log.w(TAG, "[telemetry] ask skipped — link not ready")
            return false
        }
        val key = fullKeyHex?.takeIf { it.length == 64 }?.let { unhex(it) } ?: run {
            Log.w(TAG, "[telemetry] ask skipped — no full key")
            return false
        }
        Log.i(TAG, "[telemetry] asking ${fullKeyHex.take(12)}…")
        diag(">>TELEM? ${fullKeyHex.take(12)}")
        s.requestPeerTelemetry(key)
        return true
    }

    /** Re-sync contacts, which is how a newly learned path becomes visible. */
    fun refreshContacts() {
        val s = session ?: return
        if (_status.value.state != SessionState.READY) return
        Log.i(TAG, "[link] re-requesting contacts to pick up learned paths")
        s.requestContacts()
    }

    private fun unhex(h: String): ByteArray? = runCatching {
        ByteArray(h.length / 2) { i -> ((h[i * 2].digitToInt(16) shl 4) or
            h[i * 2 + 1].digitToInt(16)).toByte() }
    }.getOrNull()

    fun announce(flood: Boolean) {
        val s = session
        if (s == null || _status.value.state != SessionState.READY) {
            Log.w(TAG, "[link] advert skipped — link not ready")
            return
        }
        Log.i(TAG, "[link] self-advert -> ${if (flood) "FLOOD" else "zero-hop"}")
        diag(">>ADVERT ${if (flood) "FLOOD" else "zero-hop"} sent — waiting for OK")
        s.sendSelfAdvert(flood)
        _status.value = _status.value.copy(lastEvent = "advert")
    }

    /**
     * Everything the radio will tell us about itself, in one readable block.
     *
     * This is a DIAGNOSTIC, not a feature: when the horizon is empty or the
     * mesh is quiet, the first question is always "what is this radio actually
     * set to", and reconstructing that from a one-line summary and the
     * firmware's own menus is slow and error-prone. Frequency, spreading
     * factor and bandwidth have to match the mesh exactly or the radio hears
     * nothing while looking perfectly healthy.
     */
    private fun dumpRadio(s: SelfInfo) {
        val key = s.publicKey()?.joinToString("") { "%02x".format(it) } ?: "?"
        Log.i(TAG, "[radio] ======== MeshCore radio ========")
        Log.i(TAG, "[radio] name          = ${s.name()}")
        Log.i(TAG, "[radio] public key    = $key")
        Log.i(TAG, "[radio] advert type   = ${s.advType()} (${advTypeName(s.advType())})")
        Log.i(TAG, "[radio] frequency     = ${s.frequencyMhz()} MHz")
        Log.i(TAG, "[radio] bandwidth     = ${s.bandwidthKhz()} kHz")
        Log.i(TAG, "[radio] spread factor = SF${s.spreadingFactor()}")
        Log.i(TAG, "[radio] coding rate   = 4/${s.codingRate()}")
        Log.i(TAG, "[radio] tx power      = ${s.txPowerDbm()} dBm (max ${s.maxTxPowerDbm()})")
        Log.i(TAG, "[radio] position      = ${s.latitude()}, ${s.longitude()}" +
            if (MeshNodes.Here(s.latitude(), s.longitude()).known) "" else "  (no GPS fix)")
        Log.i(TAG, "[radio] adv loc policy= ${s.advertLocPolicy()}")
        Log.i(TAG, "[radio] telemetry     = " +
            com.iotj.meshmore.xr.spatial.TelemetryPerms.unpack(s.telemetryModeRaw()) +
            "  (raw 0x%02x)".format(s.telemetryModeRaw()))
        Log.i(TAG, "[radio] multi-acks    = ${s.multiAcks()}")
        Log.i(TAG, "[radio] manual add    = ${s.manualAddContacts()}")
    }

    /**
     * One channel slot. The PSK is fingerprinted, never printed: it is the key
     * that decrypts every message on that channel, and a log that leaks it is
     * a log that cannot be pasted anywhere. Matching it against the well-known
     * public PSK is the one comparison worth making, because "am I on Public
     * or on something private" is the question being asked.
     */
    /**
     * Channel slot index -> its name, as the radio reports it.
     *
     * The names were being logged and dropped, so a message could only ever say
     * "#0" -- which is the radio's filing system, not a thing anybody calls a
     * channel. Kept here rather than re-read per message: the enumeration
     * happens once at connect and channels do not rename themselves.
     */
    private val chanNames = HashMap<Int, String>()

    /**
     * One channel slot the radio has told us about.
     *
     * [publicKey] is whether the slot carries the WELL-KNOWN public PSK — which
     * is not a detail, it is the difference between a band anyone within range
     * can read and one only your group can. A surface that lists channels
     * without saying which is which is inviting somebody to say something on
     * the public one thinking it was private.
     */
    data class Chan(
        val idx: Int,
        val name: String,
        val publicKey: Boolean,
        /** The thread id [threads] groups this channel's traffic under. */
        val threadId: String = "#$idx",
    )

    private val chans = LinkedHashMap<Int, Chan>()

    /**
     * The channel slots, in slot order, as reported at connect.
     *
     * Slot order rather than most-recently-active: these are POSITIONS on the
     * radio, the same numbers the phone app and the hardware use, and a list
     * that reorders itself as traffic arrives is a list where the thing you
     * reached for last time is somewhere else now.
     */
    fun channels(): List<Chan> = chans.values.sortedBy { it.idx }

    /** How many messages are held for a channel, for a surface that shows weight. */
    fun countFor(threadId: String): Int = _msgs.value.count { it.channel == threadId }

    /**
     * The lowest slot the radio reported as EMPTY, or null when all four are
     * spoken for.
     *
     * Empty is a real answer here rather than an absence: [dumpChannel] returns
     * early on a slot with no name and a zero key, so a slot missing from
     * [chans] is one the radio has told us is free — not one we failed to ask
     * about. That distinction only holds AFTER the connect-time enumeration,
     * which is why [writeChannel] refuses when the link is not READY.
     */
    fun freeSlot(): Int? = (0 until CHANNEL_SLOTS).firstOrNull { it !in chans }

    /** What a channel write did, in a form a surface can put into words. */
    sealed interface Wrote {
        data class Ok(val idx: Int, val name: String) : Wrote
        data class Refused(val why: String) : Wrote
    }

    /**
     * Write a channel into a FREE slot.
     *
     * NEVER OVER AN OCCUPIED ONE, and that is a stronger rule than the phone
     * app's. The firmware keeps one key per slot and takes the last written;
     * replacing a key silently ends every conversation that used it, and the
     * old key is gone from the radio. The phone can warn about that because it
     * can show you the key you are about to destroy and let you write it down
     * first. On the glasses there is nowhere to write it down and no way to get
     * it back, so the only safe answer is to decline and say which surface can
     * do it. Slot 0 in particular is the public channel on a stock radio, and
     * an accidental pinch that takes it out takes the wearer off the band
     * everybody else is on.
     *
     * THE KEY IS NEVER LOGGED — a fingerprint of the first four bytes goes to
     * the log so a write can be correlated with what the radio reports back,
     * and the other twelve bytes stay out of logcat and out of the diagnostics
     * tail, which is a surface the wearer can open and read.
     */
    fun writeChannel(name: String, psk: ByteArray): Wrote {
        val s = session
        if (s == null || _status.value.state != SessionState.READY) {
            return Wrote.Refused("NO RADIO")
        }
        if (psk.size != io.iotone.meshcore.MeshcoreConstants.CHANNEL_PSK_SIZE) {
            // Not reachable from any surface today; here because a short key
            // would be zero-padded by the codec into a DIFFERENT, weaker key
            // than the one whose name we are about to tell people to type.
            Log.e(TAG, "[chan] refused — key is ${psk.size} bytes, not 16")
            return Wrote.Refused("BAD KEY")
        }
        val idx = freeSlot() ?: return Wrote.Refused("NO FREE SLOT")
        val fp = psk.take(4).joinToString("") { "%02x".format(it) }
        Log.i(TAG, "[chan] slot $idx <- \"$name\" psk $fp…")
        diag(">>CHAN SET $idx $name")
        s.setChannel(idx, name, psk)
        // ASK FOR IT BACK. The device does not echo a slot write, so without
        // this the app would show a channel it hoped it had made. The reply
        // lands in dumpChannel and is what actually populates the bay.
        s.requestChannel(idx)
        return Wrote.Ok(idx, name)
    }

    private fun dumpChannel(c: io.iotone.meshcore.model.ChannelInfo) {
        val psk = c.psk()
        if (c.name().isNullOrBlank() && (psk == null || psk.all { it.toInt() == 0 })) {
            Log.i(TAG, "[radio] channel ${c.channelIdx()}     = <empty slot>")
            return
        }
        c.name()?.takeIf { it.isNotBlank() }?.let { chanNames[c.channelIdx()] = it }
        val isPublic = psk != null &&
            psk.contentEquals(io.iotone.meshcore.MeshcoreConstants.publicChannelPsk())
        val fp = psk?.take(4)?.joinToString("") { "%02x".format(it) } ?: "?"
        // REMEMBERED, not only logged. This enumeration is the ONLY place the
        // app learns a channel exists before traffic arrives on it — an empty
        // channel is still a channel you can set to read itself aloud, and a
        // list that only shows what has already spoken is a list that is empty
        // exactly when somebody is setting the app up.
        chans[c.channelIdx()] = Chan(
            idx = c.channelIdx(),
            name = c.name()?.takeIf { it.isNotBlank() } ?: "CHANNEL ${c.channelIdx()}",
            publicKey = isPublic,
        )
        Log.i(TAG, "[radio] channel ${c.channelIdx()}     = \"${c.name()}\"  psk $fp…  " +
            if (isPublic) "PUBLIC (well-known key)" else "private/custom key")
    }

    private fun advTypeName(t: Int) = when (t) {
        0 -> "none"; 1 -> "chat/companion"; 2 -> "repeater"; 3 -> "room"; 4 -> "sensor"
        else -> "unknown"
    }

    private fun openSession(device: BluetoothDevice) {
        val t = AndroidBleTransport(context)
        val s = MeshcoreSession(APP_NAME, t, object : SessionListener {
            override fun onStateChanged(state: SessionState) {
                Log.i(TAG, "[link] state -> $state")
                _status.value = _status.value.copy(state = state, lastEvent = state.name)
                when {
                    state == SessionState.READY -> {
                        everReady = true
                        retryRung = 0
                        if (_status.value.droppedAtMs != null) {
                            Log.i(TAG, "[link] recovered after " +
                                "${(blindForMs() ?: 0L) / 1000}s blind")
                            _status.value = _status.value.copy(droppedAtMs = null, error = null)
                        }
                    }
                    // DISCONNECTED AFTER READY is the drop. Only stamped once:
                    // the retry itself passes back through DISCONNECTED on its
                    // way out, and restamping would reset the blind clock every
                    // few seconds and report the outage as permanently new.
                    state == SessionState.DISCONNECTED && everReady && !closedByUser -> {
                        if (_status.value.droppedAtMs == null) {
                            Log.w(TAG, "[link] DROPPED — radio out of range or off")
                            _status.value = _status.value.copy(
                                droppedAtMs = System.currentTimeMillis(),
                                lastEvent = "dropped",
                            )
                        }
                        scheduleReconnect()
                    }
                }
            }

            override fun onReady(selfInfo: SelfInfo) {
                // THE CHECKPOINT: CMD_APP_START -> RESP_CODE_SELF_INFO decoded.
                dumpRadio(selfInfo)
                // Adopt the radio's own parameters as LIVE. This runs on every
                // reconnect, including the one after a commit went wrong -- which
                // is exactly when the previous set on disk starts earning its
                // keep, because the radio now reports its new wrong parameters
                // as its truth and has no memory of anything else.
                radio.observe(
                    RadioConfig.Params(
                        freqMhz = selfInfo.frequencyMhz(),
                        bandwidthKhz = selfInfo.bandwidthKhz(),
                        spreadingFactor = selfInfo.spreadingFactor(),
                        codingRate = selfInfo.codingRate(),
                        txDbm = selfInfo.txPowerDbm(),
                    )
                )
                _status.value = _status.value.copy(selfInfo = selfInfo, lastEvent = "READY")
                _here.value = MeshNodes.Here(selfInfo.latitude(), selfInfo.longitude())
                Log.i(TAG, "[link] here = ${selfInfo.latitude()}, ${selfInfo.longitude()} " +
                    "(fix=${_here.value.known})")
                // ASK FOR THE MESH. The device does not push its contact list on
                // connect, so a client that only listens sees an empty horizon
                // while the radio's own screen shows a full one. This is the
                // difference between "no nodes" and "never asked".
                // ANNOUNCE OURSELVES. Until now this app was a pure listener:
                // it asked for contacts, heard 162 nodes, and never once put
                // anything on the air. A REPEATER beacons on a timer, but this
                // radio adverts as type 1 (chat/companion) and a companion only
                // advertises when its client asks it to -- so nothing else on
                // the mesh had any reason to know the radio existed, and it did
                // not appear in another node's scan however close it was.
                //
                // ZERO-HOP by default. That reaches direct neighbours, which is
                // what "the node next to me should see me" needs, and it costs
                // the wider mesh nothing. A FLOOD advert propagates across every
                // repeater in range of every hop; that is a deliberate act on a
                // shared public channel, so it stays behind an explicit flag
                // rather than firing on every launch.
                announce(floodOnConnect)

                Log.i(TAG, "[link] requesting contacts")
                session?.requestContacts()
                session?.requestBatteryStorage()
                // Enumerate the channel slots. There is no "how many channels"
                // query -- an unconfigured slot simply answers with an empty
                // name -- so we ask for a fixed few and print what comes back.
                for (i in 0 until CHANNEL_SLOTS) session?.requestChannel(i)
            }

            override fun onAdvert(frame: AdvertFrame) {
                val a = frame.advert()
                // A BARE advert is a public key and nothing else: "this node
                // was just heard". It must refresh liveness WITHOUT touching
                // name or position -- writing its empty name over a contact's
                // real one would blank the callsign of every node that speaks.
                if (a.isBare) {
                    val k = hex(a.publicKey())
                    val now = System.currentTimeMillis() / 1000
                    val known = peers[k]
                    if (known != null) {
                        peers[k] = known.copy(lastSeenEpochSec = now)
                        publish()
                    }
                    Log.i(TAG, "[link] heard $k${if (known == null) " (unknown)" else " ${known.name}"}")
                    _status.value = _status.value.let {
                        it.copy(adverts = it.adverts + 1, lastEvent = "heard")
                    }
                    return
                }
                Log.i(TAG, "[link] advert '${a.name()}' type=${a.type()} " +
                    "lat=${a.latitude()} lon=${a.longitude()}")
                upsert(
                    MeshNodes.Peer(
                        key = hex(a.publicKey()),
                        name = a.name() ?: "",
                        type = a.type(),
                        // An advert carries no path, so hop count stays unknown
                        // until a contact for the same key fills it in.
                        hops = 0,
                        lat = a.latitude(),
                        lon = a.longitude(),
                        lastSeenEpochSec = a.timestamp(),
                    )
                )
                diag("ADVERT   ${a.name()?.ifBlank { null } ?: hex(a.publicKey()).take(12)}" +
                    "  type=${a.type()}" +
                    (a.latitude()?.let { la -> "  %.4f,%.4f".format(la, a.longitude()) } ?: ""))
                _status.value = _status.value.let { it.copy(adverts = it.adverts + 1, lastEvent = "advert") }
            }

            /**
             * INBOUND DIRECT MESSAGES, which this app could not receive at all
             * until 2026-08-03.
             *
             * The session drains the device's queue by itself — triggerDrain on
             * MSGS_WAITING, continueDrain after each item — and hands each
             * message here. Nothing was listening, so every DM ever sent to
             * this radio was fetched, dispatched, and dropped on the floor,
             * with the sender left believing nothing arrived.
             *
             * The first attempt at this fix put handlers in onOtherFrame, which
             * these frames never reach: the session intercepts MSGS_WAITING and
             * NO_MORE_MESSAGES outright and routes contact messages to their own
             * callback. Reading the dispatch would have been quicker than
             * writing the handler.
             */
            override fun onContactMessage(
                frame: io.iotone.meshcore.frames.ContactMessageFrame,
            ) {
                val m = frame.message()
                val pre = hex(m.pubKeyPrefix())
                val who = peers.values.firstOrNull { it.key == pre }
                // pathLen is the hop count the message ARRIVED by; 0xFF means it
                // flooded. This is the number the topology census watches.
                val via = if (m.pathLen() == MeshTopology.PATH_LEN_FLOOD) "flood"
                          else "${m.pathLen()} hop(s)"
                val name = who?.name?.ifBlank { null } ?: pre
                Log.i(TAG, "[msg] DM from $name via $via" +
                    (m.snrDb()?.let { " snr=${it}dB" } ?: "") + ": ${m.text()}")
                diag("<<DM     $name  ($via)  ${m.text()}")
                _status.value = _status.value.copy(lastEvent = "dm")
                remember(
                    Msg(
                        fromKey = pre, fromName = name, text = m.text(),
                        atEpochSec = m.timestamp(), direct = true,
                    ),
                )
                // A message arriving is when the radio learns a route back, so
                // go looking for one now rather than at the next sync.
                session?.requestContacts()
            }

            override fun onContact(frame: ContactFrame) {
                val c = frame.contact()
                upsert(
                    MeshNodes.Peer(
                        key = hex(c.publicKey()),
                        fullKey = hexFull(c.publicKey()),
                        // The operator's own "this one is mine", stored on the
                        // radio and ignored by this app until now.
                        favourite = (c.flags() and
                            io.iotone.meshcore.model.Contact.FLAG_FAVOURITE) != 0,
                        name = c.name() ?: "",
                        type = c.type(),
                        // outPathLen is the number of relays in the stored path,
                        // so hops to us is that plus our own final leg.
                        hops = c.outPathLen() + 1,
                        // THE ROUTE ITSELF, which used to be read for its
                        // LENGTH and then dropped. One byte per relay — the
                        // first byte of its public key — which is all MeshCore
                        // stores and is why MeshTopology has to treat two
                        // repeaters sharing a first byte as ambiguous.
                        path = if (c.outPathLen() == MeshTopology.PATH_LEN_FLOOD) null
                               else c.activePath().map { b -> b.toInt() and 0xFF },
                        flood = c.outPathLen() == MeshTopology.PATH_LEN_FLOOD,
                        lat = c.latitude(),
                        lon = c.longitude(),
                        lastSeenEpochSec = c.lastAdvertTimestamp(),
                    )
                )
                _load.value = _load.value.let { it.copy(received = it.received + 1) }
                _status.value = _status.value.let { it.copy(contacts = it.contacts + 1, lastEvent = "contact") }
            }

            override fun onChannelMessage(frame: ChannelMessageFrame) {
                val cm = frame.message()
                Log.i(TAG, "[link] channel msg: ${cm.text()}")
                diag("CHANMSG  ${cm.text()}")
                _status.value = _status.value.let {
                    it.copy(messages = it.messages + 1, lastEvent = "msg")
                }
                // CHANNEL TRAFFIC IS MESSAGES TOO. A channel message carries no
                // sender key — it is a broadcast on a shared key — so the
                // sender, when there is one, is whatever the text was prefixed
                // with. Splitting that out is the channel's convention rather
                // than the protocol's, so it is done leniently and the whole
                // line is kept either way.
                val raw = cm.text()
                val cut = raw.indexOf(": ")
                val who = if (cut in 1..24) raw.take(cut) else ""
                val body = if (cut in 1..24) raw.substring(cut + 2) else raw
                remember(
                    Msg(
                        fromKey = "", fromName = who, text = body,
                        atEpochSec = cm.timestamp(), direct = false,
                        channel = "#${cm.channelIdx()}",
                        channelName = chanNames[cm.channelIdx()],
                    ),
                )
            }

            override fun onOtherFrame(frame: io.iotone.meshcore.frames.MeshcoreInbound) {
                when (frame) {
                    // WHAT THE RADIO IS, AND HOW MUCH IT CAN HOLD.
                    //
                    // maxContacts is the number that makes "your contact store
                    // is full" a fact rather than an inference. Everything else
                    // here is the board identification the DeviceBook has been
                    // guessing at from names: manufacturer is the closest thing
                    // MeshCore has to a model string, and firmware version and
                    // build date pin down what is actually running.
                    is io.iotone.meshcore.frames.DeviceInfoFrame -> {
                        val d = frame.info()
                        deviceInfo = d
                        maxContacts = d.maxContacts()
                        Log.i(
                            TAG,
                            "[device] '${d.manufacturer().trim()}' fw ${d.firmwareVersion().trim()} " +
                                "(${d.firmwareBuildDate().trim()}) — holds ${d.maxContacts()} contacts, " +
                                "${d.maxGroupChannels()} channels",
                        )
                        _status.value = _status.value.copy(maxContacts = d.maxContacts())
                    }
                    is io.iotone.meshcore.frames.TelemetryResponseFrame -> {
                        // WHICH PEER, by key PREFIX — the reply carries the
                        // first bytes of the public key, not the whole thing.
                        val pre = hex(frame.pubKeyPrefix())
                        val entries = runCatching {
                            io.iotone.meshcore.codec.CayenneLpp.decode(frame.lppPayload())
                        }.getOrElse { emptyList() }
                        var volts: Double? = null
                        var tempC: Double? = null
                        var hum: Double? = null
                        val other = HashMap<Int, List<Double>>()
                        entries.forEach { e ->
                            when (e.type()) {
                                io.iotone.meshcore.codec.CayenneLpp.LppType.VOLTAGE ->
                                    volts = e.values().firstOrNull()
                                io.iotone.meshcore.codec.CayenneLpp.LppType.TEMPERATURE ->
                                    tempC = e.values().firstOrNull()
                                io.iotone.meshcore.codec.CayenneLpp.LppType.HUMIDITY ->
                                    hum = e.values().firstOrNull()
                                // KEPT, not dropped. A sensor we have not seen
                                // before is information; a decoder that
                                // discards the unfamiliar makes a mesh look
                                // emptier than it is.
                                else -> other[e.type()] = e.values()
                            }
                        }
                        val t = MeshNodes.Telemetry(
                            atEpochSec = System.currentTimeMillis() / 1000,
                            volts = volts, tempC = tempC, humidityPct = hum,
                            other = other,
                        )
                        val hit = _mesh.value.firstOrNull { it.key.startsWith(pre) }
                        Log.i(TAG, "[telemetry] ${hit?.name ?: pre} -> $t" +
                            (if (other.isEmpty()) "" else "  types=${other.keys}"))
                        diag("TELEM    ${hit?.name?.ifBlank { null } ?: pre}  $t")
                        if (hit != null) {
                            peers[hit.key] = hit.copy(telemetry = t)
                            publish()
                        }
                    }
                    is io.iotone.meshcore.frames.ContactsStartFrame -> {
                        Log.i(TAG, "[link] contacts sync: ${frame.count()} expected")
                        // THE RADIO'S OWN COUNT, and the only one that can be
                        // compared with the radio's own capacity. The app's map
                        // is keyed by a 6-byte prefix and quietly holds one
                        // fewer when two contacts collide there — 349 against a
                        // 350-contact store, which made "full" untestable by a
                        // single off-by-one.
                        _status.value = _status.value.copy(heldByRadio = frame.count().toInt())
                        _load.value = Load(total = frame.count().toInt(), received = 0)
                    }
                    is io.iotone.meshcore.frames.EndOfContactsFrame -> {
                        Log.i(TAG, "[link] contacts sync complete")
                        // THE CENSUS. Step 1 of the topology spec: measure what
                        // fraction of a real mesh has a route we can actually
                        // resolve, before designing anything on top of it. SNS's
                        // field note says to expect very little.
                        runCatching {
                            val selfKey = _status.value.selfInfo
                                ?.publicKey()?.joinToString("") { b -> "%02x".format(b) }
                                ?: "self"
                            val g = MeshTopology.resolve(selfKey, _mesh.value)
                            Log.i(TAG, "[topology] " + g.census)
                            Log.i(TAG, "[topology] edges=" + g.edges.size +
                                " by kind " + g.edges.groupingBy { it.kind }.eachCount())
                            // NAME the resolvable ones. A count that moved is
                            // interesting; knowing which node moved it is what
                            // you act on.
                            _mesh.value.filter { it.path != null }.forEach { p ->
                                Log.i(TAG, "[topology] routed: ${p.name.ifBlank { p.key }} " +
                                    "key=${p.key} hops=" + (p.path?.size ?: -1))
                            }
                        }.onFailure { Log.w(TAG, "[topology] census failed: " + it) }
                        _load.value = _load.value.copy(done = true)
                        // FROM HERE, A NEW PEER IS NEWS. Everything before this
                        // was the radio reading out what it already knew.
                        announceFinds = true
                        Log.i(TAG, "[link] contact sync done — discovery is live")
                        resolveOwnNodes()
                        // ASKED AFTER THE STORE IS READ, so the answer arrives
                        // beside the count it explains.
                        runCatching { session?.deviceQuery(1) }
                    }
                    is io.iotone.meshcore.frames.BatteryStorageFrame -> {
                        val mv = runCatching { frame.battery().batteryMillivolts() }.getOrNull()
                        Log.i(TAG, "[radio] battery       = ${mv}mV" +
                            if (mv != null && mv <= 0) "  (no cell reported — external power)" else "")
                        _load.value = _load.value.copy(batteryMv = mv)
                    }
                    is io.iotone.meshcore.frames.ChannelInfoFrame -> dumpChannel(frame.info())
                    // THE ADVERT RECEIPT. CMD_SEND_SELF_ADVERT is answered with
                    // OK or ERROR, and both used to fall into `else -> Unit`.
                    // That meant "we sent the advert" was a claim about a byte
                    // we put on a wire, not about anything the radio did with
                    // it -- and if the firmware rejected it we would never have
                    // known. It is still only the FIRMWARE's acknowledgement,
                    // not proof of a transmission: no companion protocol
                    // reports that.
                    is io.iotone.meshcore.frames.OkFrame ->
                        diag("OK       command accepted")
                    is io.iotone.meshcore.frames.ErrorFrame -> {
                        Log.w(TAG, "[link] ERROR from radio: $frame")
                        diag("ERROR    radio rejected a command: $frame")
                    }
                    is io.iotone.meshcore.frames.RfLogFrame ->
                        diag("RF       ${frame.log()}")
                    is io.iotone.meshcore.frames.TelemetryResponseFrame ->
                        diag("TELEM    ${frame}")
                    // DELIVERY, AS THE PROTOCOL ACTUALLY REPORTS IT.
                    //
                    // Two different facts, and until now both were a line of
                    // text in the radio log: RESP_CODE_SENT says the radio
                    // ACCEPTED the message and hands back the CRC tag it will
                    // be acknowledged by; PUSH_CODE_ACK says the DESTINATION
                    // received it. Everything this app could previously say
                    // about a message was "we asked the radio to send it".
                    is io.iotone.meshcore.frames.MsgSentFrame -> {
                        // The tag belongs to the message submitted a moment
                        // ago — the radio answers one send at a time, and the
                        // app has exactly one outstanding when this arrives.
                        awaitingTag?.let { mine ->
                            awaitingTag = null
                            tagMessage(mine, frame.sent().expectedAck())
                        }
                        // FLOOD OR DIRECT IS THE COST OF THE MESSAGE.
                        //
                        // A direct message with a known route is one
                        // transmission. A flooded one is repeated by every
                        // repeater that hears it, and 310 of the 350 contacts
                        // in this operator's store are repeaters — so the same
                        // message can cost ten or twenty times the airtime,
                        // which is the difference between a test and an
                        // imposition. It was only ever visible in the in-app
                        // diagnostics ring, which is not where anyone analysing
                        // an hour-long run is looking.
                        Log.i(TAG, "[tx] accepted tag=0x%08x %s timeout=%dms".format(
                            frame.sent().expectedAck(),
                            if (frame.sent().isFlood()) "FLOOD" else "direct",
                            frame.sent().estTimeoutMs(),
                        ))
                        val tag = frame.sent().expectedAck()
                        pending[tag] = System.currentTimeMillis()
                        _delivery.value = _delivery.value.copy(
                            accepted = _delivery.value.accepted + 1,
                            lastTag = tag,
                        )
                        diag("SENT     $frame")
                    }
                    is io.iotone.meshcore.frames.AckFrame -> {
                        markDelivered(frame.ackCrc())
                        val at = pending.remove(frame.ackCrc())
                        val ms = at?.let { System.currentTimeMillis() - it }
                        _delivery.value = _delivery.value.copy(
                            acked = _delivery.value.acked + 1,
                            lastLatencyMs = ms ?: _delivery.value.lastLatencyMs,
                            totalLatencyMs = _delivery.value.totalLatencyMs + (ms ?: 0L),
                        )
                        Log.i(TAG, "[tx] delivered tag=0x%08x%s".format(
                            frame.ackCrc(), ms?.let { " in ${it}ms" } ?: " (unmatched)",
                        ))
                        diag("ACK      $frame")
                    }
                    is io.iotone.meshcore.frames.UnsupportedFrame ->
                        diag("UNSUP    $frame")
                    else -> diag("FRAME    ${frame.javaClass.simpleName}")
                }
            }

            override fun onDecodeFailure(failure: DecodeFailure) {
                // Decoding is total, so this is data we should look at, not a crash.
                Log.w(TAG, "[link] decode failure: ${failure.error()}")
                diag("DECODE!  ${failure.error()}")
                _status.value = _status.value.copy(lastEvent = "decode-fail")
            }
        })
        transport = t
        session = s
        // The library's own live test posts this to the main looper; BLE stack
        // setup is not safe to kick off from an arbitrary thread.
        Handler(Looper.getMainLooper()).post { t.connectToDevice(device) }
    }

    fun close() {
        Log.i(TAG, "[link] close")
        // BEFORE the teardown, so the DISCONNECTED that the session's own close
        // delivers is not read as a drop and answered with a reconnect.
        closedByUser = true
        retry?.let { retryHandler.removeCallbacks(it); retry = null }
        retryRung = 0
        runCatching { session?.close() }
        session = null
        transport = null
        _status.value = Status(lastEvent = "closed")
    }

    companion object {
        /**
         * [linkChip]'s arithmetic, without a Context — so it can be tested.
         *
         * Coarse on purpose. Seconds below a minute, then whole minutes, then
         * whole hours: the wearer's decision is "is this worth stopping to fix",
         * and that answer does not change between 4 and 5 minutes.
         */
        internal fun chipFor(state: SessionState, blindMs: Long?): String {
            if (state == SessionState.READY) return "LINK"
            if (blindMs == null) return state.name.take(4)
            val s = blindMs / 1000
            val d = when {
                s < 60 -> "${s}S"
                s < 3600 -> "${s / 60}M"
                else -> "${s / 3600}H"
            }
            return "LOST $d"
        }

        private const val TAG = "MeshmoreXR"
        private const val APP_NAME = "MeshmoreXR"
        /** ~11 m. Below this a "move" is GPS jitter, not a move. */
        private const val MOVE_DEG = 0.0001
        /** advertLocPolicy: 0 omits position from adverts, 1 shares it. */
        const val LOC_POLICY_SHARE = 1
        /** Lines kept in the diagnostics tail. */
        private const val DIAG_MAX = 300
        /** Channel slots to enumerate at connect. The firmware has no count query. */
        private const val CHANNEL_SLOTS = 4
        private const val SCAN_TIMEOUT_MS = 12_000L
        /**
         * How long to wait before each reconnect attempt after a drop.
         *
         * The first rung is short because most drops are not outages: a hand,
         * a body, a jacket over the pannier. The last rung is a minute and is
         * where it stays — a radio that has been gone five minutes is off or
         * left behind, and the cost of asking again is a 12-second scan on a
         * head-worn battery. Roughly one scan a minute is the floor at which
         * "walk back into range and it just comes back" still holds.
         */
        internal val RETRY_MS = longArrayOf(2_000, 5_000, 10_000, 20_000, 60_000)
        /**
         * How long to collect advertisers before choosing the strongest. Long
         * enough that a second radio gets a chance to be heard, short enough
         * that a lone radio still connects in well under a second of felt delay.
         */
        private const val SCAN_SETTLE_MS = 1_500L
        /**
         * NOT a constant in practice. MyMesh.cpp:932 does:
         *     if (has_display && BLE_PIN_CODE == 123456)
         *         _active_ble_pin = rng.nextInt(100000, 999999);  // random per boot
         * so adding the OLED turned this board from a static 123456 into a
         * random 6-digit PIN shown on screen, regenerated on every reboot.
         * Hardcoded here only to close P0 checkpoint 3; S2 LINK reads it from
         * the user (or a QR code, via arcore's QrCode API).
         */
        /**
         * How many messages to keep. Enough that a busy channel does not push
         * a direct message out of reach in a minute, few enough that it is
         * plainly a recent-history buffer and not an archive.
         */
        /**
         * How much history is kept.
         *
         * Sixty was the size of a buffer nobody could look at beyond the newest
         * few, so it never mattered. Now that it survives restarts and can be
         * paged, it is the actual answer to "how far back does this go" -- and
         * at roughly 120 bytes a message this is about fifty kilobytes, which
         * is nothing.
         */
        private const val MSG_KEEP = 500
    }
}
