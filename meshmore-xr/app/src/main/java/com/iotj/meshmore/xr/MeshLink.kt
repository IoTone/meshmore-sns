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

    private fun hex(b: ByteArray?): String =
        b?.take(6)?.joinToString("") { "%02x".format(it) } ?: ""

    private fun upsert(p: MeshNodes.Peer) {
        // Merge rather than replace: an advert carries a position and a name, a
        // contact also carries the hop count. Whichever arrives second must not
        // erase what the first one knew.
        peers.compute(p.key) { _, old ->
            if (old == null) p else p.copy(
                name = p.name.ifBlank { old.name },
                lat = p.lat ?: old.lat,
                lon = p.lon ?: old.lon,
                hops = if (p.hops > 0) p.hops else old.hops,
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

        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val name = try { result.device.name } catch (_: SecurityException) { null } ?: return
                if (!name.startsWith(namePrefix, ignoreCase = true)) return
                Log.i(TAG, "[link] found '$name' rssi=${result.rssi}")
                scanner.stopScan(this)
                _status.value = _status.value.copy(scanning = false, deviceName = name, lastEvent = "found $name")
                bondThenOpen(result.device, pin)
            }

            override fun onScanFailed(errorCode: Int) {
                Log.e(TAG, "[link] scan failed code=$errorCode")
                _status.value = _status.value.copy(scanning = false, error = "scan failed $errorCode")
            }
        }
        scanner.startScan(emptyList(), settings, cb)

        // Bounded: park with a clear state rather than scanning forever.
        Handler(Looper.getMainLooper()).postDelayed({
            if (_status.value.scanning) {
                scanner.stopScan(cb)
                Log.w(TAG, "[link] scan timeout — no radio named '$namePrefix*'")
                _status.value = _status.value.copy(scanning = false, error = "no radio found", lastEvent = "timeout")
            }
        }, SCAN_TIMEOUT_MS)
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

    private fun openSession(device: BluetoothDevice) {
        val t = AndroidBleTransport(context)
        val s = MeshcoreSession(APP_NAME, t, object : SessionListener {
            override fun onStateChanged(state: SessionState) {
                Log.i(TAG, "[link] state -> $state")
                _status.value = _status.value.copy(state = state, lastEvent = state.name)
            }

            override fun onReady(selfInfo: SelfInfo) {
                // THE CHECKPOINT: CMD_APP_START -> RESP_CODE_SELF_INFO decoded.
                Log.i(TAG, "[link] READY name='${selfInfo.name()}' " +
                        "freq=${selfInfo.frequencyMhz()} sf=${selfInfo.spreadingFactor()} " +
                        "bw=${selfInfo.bandwidthKhz()} cr=${selfInfo.codingRate()} " +
                        "tx=${selfInfo.txPowerDbm()}dBm advType=${selfInfo.advType()}")
                _status.value = _status.value.copy(selfInfo = selfInfo, lastEvent = "READY")
                _here.value = MeshNodes.Here(selfInfo.latitude(), selfInfo.longitude())
                Log.i(TAG, "[link] here = ${selfInfo.latitude()}, ${selfInfo.longitude()} " +
                    "(fix=${_here.value.known})")
                // ASK FOR THE MESH. The device does not push its contact list on
                // connect, so a client that only listens sees an empty horizon
                // while the radio's own screen shows a full one. This is the
                // difference between "no nodes" and "never asked".
                Log.i(TAG, "[link] requesting contacts")
                session?.requestContacts()
                session?.requestBatteryStorage()
            }

            override fun onAdvert(frame: AdvertFrame) {
                val a = frame.advert()
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
                _status.value = _status.value.let { it.copy(adverts = it.adverts + 1, lastEvent = "advert") }
            }

            override fun onContact(frame: ContactFrame) {
                val c = frame.contact()
                upsert(
                    MeshNodes.Peer(
                        key = hex(c.publicKey()),
                        name = c.name() ?: "",
                        type = c.type(),
                        // outPathLen is the number of relays in the stored path,
                        // so hops to us is that plus our own final leg.
                        hops = c.outPathLen() + 1,
                        lat = c.latitude(),
                        lon = c.longitude(),
                        lastSeenEpochSec = c.lastAdvertTimestamp(),
                    )
                )
                _load.value = _load.value.let { it.copy(received = it.received + 1) }
                _status.value = _status.value.let { it.copy(contacts = it.contacts + 1, lastEvent = "contact") }
            }

            override fun onChannelMessage(frame: ChannelMessageFrame) {
                Log.i(TAG, "[link] channel msg: ${frame.message().text()}")
                _status.value = _status.value.let { it.copy(messages = it.messages + 1, lastEvent = "msg") }
            }

            override fun onOtherFrame(frame: io.iotone.meshcore.frames.MeshcoreInbound) {
                when (frame) {
                    is io.iotone.meshcore.frames.ContactsStartFrame -> {
                        Log.i(TAG, "[link] contacts sync: ${frame.count()} expected")
                        _load.value = Load(total = frame.count().toInt(), received = 0)
                    }
                    is io.iotone.meshcore.frames.EndOfContactsFrame -> {
                        Log.i(TAG, "[link] contacts sync complete")
                        _load.value = _load.value.copy(done = true)
                    }
                    is io.iotone.meshcore.frames.BatteryStorageFrame -> {
                        val mv = runCatching { frame.battery().batteryMillivolts() }.getOrNull()
                        Log.i(TAG, "[link] battery = ${mv}mV")
                        _load.value = _load.value.copy(batteryMv = mv)
                    }
                    else -> Unit
                }
            }

            override fun onDecodeFailure(failure: DecodeFailure) {
                // Decoding is total, so this is data we should look at, not a crash.
                Log.w(TAG, "[link] decode failure: ${failure.error()}")
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
        private const val SCAN_TIMEOUT_MS = 12_000L
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
    }
}
