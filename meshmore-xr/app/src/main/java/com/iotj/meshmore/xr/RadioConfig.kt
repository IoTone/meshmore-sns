// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import android.content.Context

/**
 * THE RADIO'S OWN CONFIGURATION — staged, committed, and recoverable.
 *
 * Design brief §9.6.5. This is the state machine under the RADIO rack; the rack
 * is how you touch it, this is what it touches.
 *
 * THE PROBLEM IT EXISTS TO SOLVE. Frequency, bandwidth, spreading factor and
 * coding rate are one command and one working configuration. Applying them a
 * control at a time walks the radio through combinations that match no mesh at
 * all -- you would lose contact somewhere in the middle of your own edit. So
 * edits accumulate in PENDING and only reach the radio when [stage] is
 * committed, as a set.
 *
 * AND THE PART THAT CANNOT BE SOLVED. Once a set is committed, nothing can tell
 * you whether it was right. A radio on the wrong parameters is still connected
 * over BLE, still answers every query, still reports itself healthy -- it simply
 * hears nothing, which is indistinguishable from a quiet mesh. No companion
 * protocol reports transmission or reception success. There is no verification
 * available at any layer.
 *
 * So the answer is not verification, it is A WAY BACK: the previous set is kept,
 * and kept ON DISK.
 *
 * WHY DISK, AND WHY NO DEAD-MAN TIMER. In-memory recovery covers the case where
 * you notice immediately. It does not cover the realistic one: you commit, the
 * mesh goes quiet, you assume it is a quiet evening, and you find out tomorrow.
 * By then the process is long gone and with it the only record of what the radio
 * used to be set to -- the radio itself cannot tell you, because it is now
 * reporting its new, wrong parameters as its truth.
 *
 * A dead-man timer (auto-revert unless confirmed within N seconds) was the
 * alternative and was rejected. It makes a bad commit self-healing at the cost
 * of a radio that changes its own settings back while the user watches, and
 * "confirmed" has no honest definition here: hearing a packet within N seconds
 * proves the parameters work, but hearing NOTHING proves nothing at all on a
 * mesh that is often quiet for minutes at a time. A timer would revert good
 * commits on quiet evenings, which is a worse failure than the one it prevents
 * because it is silent and it is wrong.
 */
class RadioConfig(
    private val store: Store,
    /**
     * Where this narrates. A callback rather than android.util.Log so the class
     * stays pure -- the same reason MeshNodes takes no session: the part most
     * worth testing is the part that must not need an Android runtime to run.
     */
    private val log: (String) -> Unit = {},
) {

    /**
     * The two writes this needs, and nothing else.
     *
     * Injected rather than reaching for SharedPreferences directly, because the
     * behaviour worth testing here is precisely the one that spans a process
     * death -- commit, restart, revert -- and a class welded to a Context cannot
     * be asked about that without dragging in a whole Android runtime. The
     * durability rule is the feature; it should not be the untested part.
     */
    interface Store {
        fun getString(key: String): String?
        fun putString(key: String, value: String?)
        fun getLong(key: String): Long
        fun putLong(key: String, value: Long)
    }

    constructor(context: Context, log: (String) -> Unit = {}) : this(PrefsStore(context), log)

    private class PrefsStore(context: Context) : Store {
        private val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        override fun getString(key: String) = p.getString(key, null)
        override fun putString(key: String, value: String?) {
            p.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
        }
        override fun getLong(key: String) = p.getLong(key, 0L)
        override fun putLong(key: String, value: Long) { p.edit().putLong(key, value).apply() }
    }

    /** The four LoRa parameters plus TX power: one set, applied together. */
    data class Params(
        val freqMhz: Double,
        val bandwidthKhz: Double,
        val spreadingFactor: Int,
        val codingRate: Int,
        val txDbm: Int,
    ) {
        fun pretty() = "%.3fMHz BW%.4g SF%d 4/%d %ddBm"
            .format(freqMhz, bandwidthKhz, spreadingFactor, codingRate, txDbm)

        fun encode() = "$freqMhz|$bandwidthKhz|$spreadingFactor|$codingRate|$txDbm"

        companion object {
            fun decode(s: String?): Params? {
                val p = s?.split("|") ?: return null
                if (p.size != 5) return null
                return runCatching {
                    Params(p[0].toDouble(), p[1].toDouble(), p[2].toInt(), p[3].toInt(), p[4].toInt())
                }.getOrNull()
            }
        }
    }

    /** What the radio reports it is running. Null until self-info arrives. */
    var live: Params? = null
        private set

    /** What the encoders are showing. Never touches the radio until committed. */
    var pending: Params? = null
        private set

    /**
     * The set the radio was on before the last commit, or null if there has not
     * been one. SURVIVES RESTARTS -- see the class doc for why that is the whole
     * point rather than a nicety.
     */
    val previous: Params?
        get() = Params.decode(store.getString(KEY_PREVIOUS))

    /** When [previous] was recorded, epoch millis, or 0. For the rack's caption. */
    val previousAt: Long
        get() = store.getLong(KEY_PREVIOUS_AT)

    /**
     * Adopt what the radio reports. Called on every self-info, so it also runs
     * on a reconnect after a commit -- which is exactly when the previous set on
     * disk starts earning its keep.
     */
    fun observe(p: Params) {
        live = p
        // Only seed PENDING from the radio when there is nothing staged. Doing
        // it unconditionally would silently discard an edit in progress every
        // time self-info arrived.
        if (pending == null) pending = p
        log("live = ${p.pretty()}")
        previous?.let { log("previous set on disk = ${it.pretty()} — REVERT available") }
    }

    /** Stage an edit. Returns the new pending set, or null before self-info. */
    fun stage(edit: (Params) -> Params): Params? {
        val base = pending ?: live ?: return null
        pending = edit(base)
        return pending
    }

    /** True when the staged set differs from what the radio is running. */
    fun dirty(): Boolean = live != null && pending != null && live != pending

    /**
     * Record a commit. The caller is responsible for actually sending it; this
     * moves the bookkeeping and writes the previous set to disk FIRST, because
     * a crash between the write and the send must leave a way back, not lose one.
     */
    fun commit(): Params? {
        val next = pending ?: return null
        val was = live
        if (was != null) {
            store.putString(KEY_PREVIOUS, was.encode())
            store.putLong(KEY_PREVIOUS_AT, System.currentTimeMillis())
            log("previous set saved: ${was.pretty()}")
        }
        live = next
        log("COMMIT ${next.pretty()}")
        return next
    }

    /**
     * Take the previous set for a revert. Clears it: a revert restores one step,
     * and keeping it would offer a "way back" to the configuration you just
     * escaped from.
     */
    fun takePrevious(): Params? {
        val p = previous ?: return null
        store.putString(KEY_PREVIOUS, null)
        store.putLong(KEY_PREVIOUS_AT, 0L)
        pending = p
        live = p
        log("REVERT to ${p.pretty()}")
        return p
    }

    /** Drop a staged edit without touching the radio. */
    fun discard() { pending = live }

    private companion object {
        const val FILE = "meshmore-xr-radio"
        const val KEY_PREVIOUS = "previous_params"
        const val KEY_PREVIOUS_AT = "previous_params_at"
    }
}
