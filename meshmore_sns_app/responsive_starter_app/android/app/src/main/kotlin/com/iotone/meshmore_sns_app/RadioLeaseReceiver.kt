package com.iotone.meshmore_sns_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * **Give the radio back when another app asks for it.**
 *
 * A MeshCore BLE companion accepts exactly **one** central, by firmware design, and Android offers
 * no way for one app to close another app's GATT link. So when a second app wants the same radio the
 * only workable arrangement is an agreement: the app that holds it lets go, the app that wants it
 * says when it is done, and the holder comes back.
 *
 * Without this the two apps take turns being evicted. Measured on the device, 2026-11-10: while the
 * other app was mid-handshake this one was registering a GATT client, connecting, and dropping the
 * link every thirty seconds (`DISCONNECTED … reason=22` three times a minute). From the operator's
 * side that is "handshake, fail, handshake, fail", on a radio that was working perfectly.
 *
 * The contract is the pair of actions in [ACTION_WANTED] and [ACTION_FREE], plus an answer in
 * [ACTION_GRANTED]. The requester is another app on this phone; the request is an explicit
 * broadcast, so a manifest receiver like this one is reached even when Meshmore is in the background.
 *
 * **What this deliberately does not do is stop the app.** Losing the radio is not the same as being
 * finished: the foreground service, the notification and the pending work all stay, and [ACTION_FREE]
 * brings the link back without the operator touching anything. That is the whole point of the
 * handoff — share the radio, not the app's life.
 */
class RadioLeaseReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_WANTED = "io.ldmux.mobile.action.RADIO_WANTED"
        const val ACTION_FREE = "io.ldmux.mobile.action.RADIO_FREE"
        const val ACTION_GRANTED = "io.ldmux.mobile.action.RADIO_GRANTED"
        private const val PREFS = "meshmore_radio_lease"
        private const val KEY_YIELDED = "yielded"

        private const val KEY_YIELDED_AT = "yielded_at"

        /**
         * How long a hold survives its holder going quiet.
         *
         * The flag used to be permanent until [ACTION_FREE], and a holder that was killed, uninstalled
         * or simply never finished leaves no FREE to send. The result was unrecoverable and measured on
         * the device on 2026-11-11: `meshmore_radio_lease.xml` held `yielded=true`, every launch read it
         * and skipped the automatic connect, and the app sat disconnected until the operator tapped
         * Connect — which is a state the lease was never meant to create. A hold is a statement about
         * *now*; nothing can hold a radio for a quarter of an hour without saying anything, so the claim
         * expires.
         */
        private const val HOLD_TTL_MS = 15L * 60L * 1000L

        /**
         * How long to wait for the Dart side to acknowledge a yield before
         * answering anyway.
         *
         * A broadcast receiver's budget is five seconds. Four leaves the
         * requester its grant and the system its window, and the flag is already
         * written, so an unanswered yield cannot leave the radio held.
         */
        private const val LEASE_ANSWER_TIMEOUT_MS = 4_000L

        /**
         * True while another app holds the radio, as last recorded.
         *
         * Persisted across processes because this app may be dead when the request arrives, and refused
         * once stale: a hold nobody renewed is not evidence that the radio is still in use.
         */
        fun isYielded(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (!prefs.getBoolean(KEY_YIELDED, false)) return false
            val at = prefs.getLong(KEY_YIELDED_AT, 0L)
            val age = System.currentTimeMillis() - at
            // A hold written before this timestamp existed has `at == 0`, so it reads as stale and the
            // flag repairs itself on the first launch after the update.
            if (at <= 0L || age > HOLD_TTL_MS) {
                setYielded(context, false)
                return false
            }
            return true
        }

        /** Take the radio back: the operator asked for it, which outranks a stale hold. */
        fun clear(context: Context) = setYielded(context, false)

        private fun setYielded(context: Context, yielded: Boolean) {
            val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            if (yielded) {
                editor.putBoolean(KEY_YIELDED, true)
                    .putLong(KEY_YIELDED_AT, System.currentTimeMillis())
            } else {
                editor.putBoolean(KEY_YIELDED, false).remove(KEY_YIELDED_AT)
            }
            editor.apply()
        }

        /**
         * The live Dart side, when this app is running.
         *
         * Nullable on purpose: the receiver is declared in the manifest and therefore runs whether or
         * not the engine is alive. With no engine there is no BLE link to release, so nothing is lost
         * — the flag alone is the correct state, and the next launch reads it.
         */
        private var channel: MethodChannel? = null

        fun attach(engine: FlutterEngine) {
            channel = MethodChannel(engine.dartExecutor.binaryMessenger, "meshmore/radio_lease")
        }

        fun detach() {
            channel = null
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_WANTED -> {
                // The flag goes first: if the process is killed between here and the Dart call, the
                // next launch must still know that the radio is somebody else's.
                setYielded(context, true)
                val pending = goAsync()
                // **Addressed to the app that asked, and to nobody else.** `setPackage(null)` would
                // clear the address and make this an implicit broadcast, which on Android 8+ reaches
                // only receivers that registered at runtime — so the answer would go nowhere while
                // looking like it had been sent. No `requested_by`, no answer.
                val requester = intent.getStringExtra("requested_by")
                // Answer only after the flag is set, so a requester that connects the instant it
                // hears the answer cannot race a link that is still up.
                //
                // **The answer cannot wait on a busy app.** A broadcast receiver has five seconds
                // to finish, and this one finished only when Dart answered. Measured on the device,
                // 2026-11-13: three ANRs whose subject is exactly this intent, while the app's main
                // isolate was stalled on a frame. The flag is already written by then, so the
                // contract holds without the answer: the requester may connect, and the next launch
                // reads the flag. Waiting past the system's window turns a busy app into a crash
                // dialog, which is the one outcome that costs the operator something.
                var finished = false
                val done: () -> Unit = {
                    if (!finished) {
                        finished = true
                        if (requester != null) {
                            runCatching {
                                context.sendBroadcast(
                                    Intent(ACTION_GRANTED)
                                        .setPackage(requester)
                                        .putExtra("granted_by", context.packageName)
                                )
                            }
                        }
                        runCatching { pending.finish() }
                        Unit
                    }
                }
                val ch = channel
                if (ch == null) {
                    // Nothing is holding the radio: this was a cold process, or the app is stopped.
                    done()
                    return
                }
                Handler(Looper.getMainLooper()).postDelayed({
                    if (!finished) {
                        android.util.Log.w(
                            "MeshmoreLease",
                            "yield unanswered after ${LEASE_ANSWER_TIMEOUT_MS}ms; answering on the flag"
                        )
                        done()
                    }
                }, LEASE_ANSWER_TIMEOUT_MS)
                ch.invokeMethod("yield", null, object : MethodChannel.Result {
                    override fun success(result: Any?) { done() }
                    override fun error(code: String, message: String?, details: Any?) { done() }
                    override fun notImplemented() { done() }
                })
            }
            ACTION_FREE -> {
                setYielded(context, false)
                channel?.invokeMethod("resume", null)
            }
        }
    }
}
