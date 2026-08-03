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
        val messages: Int = 0,
        val lastEvent: String = "idle",
        val error: String? = null,
    )

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
    private fun isAllowed(p: MeshNodes.Peer): Boolean =
        ALLOWED_SUFFIXES.any { sfx ->
            p.name.endsWith(sfx, ignoreCase = true) ||
                (p.fullKey ?: p.key).endsWith(sfx, ignoreCase = true)
        }
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
    )

    private val _msgs = MutableStateFlow<List<Msg>>(emptyList())
    val msgs: StateFlow<List<Msg>> = _msgs.asStateFlow()

    /** Raised on arrival so the host can announce it. */
    var onMessage: ((Msg) -> Unit)? = null

    private fun remember(m: Msg) {
        _msgs.value = (listOf(m) + _msgs.value).take(MSG_KEEP)
        onMessage?.invoke(m)
    }

    private val _here = MutableStateFlow(MeshNodes.Here(null, null))
    val here: StateFlow<MeshNodes.Here> = _here.asStateFlow()

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
    }

    private var transport: AndroidBleTransport? = null
    private var session: MeshcoreSession? = null

    fun hasBlePermissions(): Boolean =
        listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
            .all { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }

    /** Scan for a radio whose advert name starts with [namePrefix], then handshake. */
    fun connect(namePrefix: String = "MeshCore", pin: String = BLE_PIN) {
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
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val name = try { result.device.name } catch (_: SecurityException) { null } ?: return
                if (!name.startsWith(namePrefix, ignoreCase = true)) return
                if (seen.put(result.device.address, result) == null) {
                    Log.i(TAG, "[link] found '$name' rssi=${result.rssi}")
                }
            }

            override fun onScanFailed(errorCode: Int) {
                Log.e(TAG, "[link] scan failed code=$errorCode")
                _status.value = _status.value.copy(scanning = false, error = "scan failed $errorCode")
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
    private fun bondThenOpen(device: BluetoothDevice, pin: String) {
        if (device.bondState == BluetoothDevice.BOND_BONDED) {
            Log.i(TAG, "[link] already bonded — connecting")
            openSession(device)
            return
        }
        Log.i(TAG, "[link] not bonded — createBond() with PIN '$pin'")
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
                                // PAIRING_VARIANT_PIN(0) / PASSKEY(1): we supply digits
                                0, 1 -> {
                                    val ok = device.setPin(pin.toByteArray())
                                    Log.i(TAG, "[link] setPin -> $ok")
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
    private fun dumpChannel(c: io.iotone.meshcore.model.ChannelInfo) {
        val psk = c.psk()
        if (c.name().isNullOrBlank() && (psk == null || psk.all { it.toInt() == 0 })) {
            Log.i(TAG, "[radio] channel ${c.channelIdx()}     = <empty slot>")
            return
        }
        val isPublic = psk != null &&
            psk.contentEquals(io.iotone.meshcore.MeshcoreConstants.publicChannelPsk())
        val fp = psk?.take(4)?.joinToString("") { "%02x".format(it) } ?: "?"
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
                    ),
                )
            }

            override fun onOtherFrame(frame: io.iotone.meshcore.frames.MeshcoreInbound) {
                when (frame) {
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
                    is io.iotone.meshcore.frames.AckFrame -> diag("ACK      $frame")
                    is io.iotone.meshcore.frames.MsgSentFrame -> diag("SENT     $frame")
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
        runCatching { session?.close() }
        session = null
        transport = null
        _status.value = Status(lastEvent = "closed")
    }

    companion object {
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
        private const val BLE_PIN = "888294"
        /**
         * How many messages to keep. Enough that a busy channel does not push
         * a direct message out of reach in a minute, few enough that it is
         * plainly a recent-history buffer and not an archive.
         */
        private const val MSG_KEEP = 60
    }
}
