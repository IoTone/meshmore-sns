package com.iotone.meshmore_sns_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
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

        /** True while another app holds the radio. Persisted, because the process may die. */
        fun isYielded(context: Context): Boolean = context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_YIELDED, false)

        private fun setYielded(context: Context, yielded: Boolean) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_YIELDED, yielded)
                .apply()
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
                val done: () -> Unit = {
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
                val ch = channel
                if (ch == null) {
                    // Nothing is holding the radio: this was a cold process, or the app is stopped.
                    done()
                    return
                }
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
