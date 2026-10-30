package com.iotone.meshmore_sns_app

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Binder
import android.os.Bundle
import android.os.IBinder
import android.os.Parcel

/**
 * What the running gateway offers to another app on this phone, held in memory and nothing more.
 *
 * **Dart is the single source of truth.** `GatewayService` publishes through the
 * `meshmore/gateway_handoff` channel whenever its state, port, token or peer changes, and clears it
 * when it stops. This object stores that and serves it; it never decides a value, and it is never
 * written to disk, so a process that has died offers nothing instead of a token that no longer
 * opens a listener.
 */
object GatewayHandoffStore {
    const val VERSION = 1

    @Volatile private var offer: Bundle = off()

    fun publish(state: String, port: Int, token: ByteArray?, radioKey: String?, peerName: String?) {
        offer = Bundle().apply {
            putInt("version", VERSION)
            putString("state", state)
            putInt("port", port)
            // A token leaves only while the gateway is running. Any other state with a token attached
            // would hand over a credential for a listener that is not there.
            if (state == "running" && token != null) putByteArray("token", token.copyOf())
            radioKey?.let { putString("radioKey", it) }
            peerName?.let { putString("peerName", it) }
        }
    }

    fun clear() { offer = off() }

    /** A copy: the caller writes it to a parcel and must not be able to alter what is stored. */
    fun current(): Bundle = Bundle(offer)

    private fun off() = Bundle().apply {
        putInt("version", VERSION)
        putString("state", "off")
        putInt("port", 0)
    }
}

/**
 * The same-phone handoff of the gateway's endpoint and token (`meshmore-sns-gateway-handoff.md`).
 *
 * Exported, and guarded by a **signature** permission in the manifest, so the platform refuses a
 * bind from an app signed with another certificate before any of this runs. The check in
 * [onTransact] is the second lock, not the first: the receiver of a Binder call must not assume
 * its own manifest is the only thing that can reach it.
 *
 * A hand-written Binder rather than AIDL: one transaction, one Bundle, and no generated code to
 * keep in step across two repositories.
 */
class GatewayHandoffService : Service() {
    override fun onBind(intent: Intent?): IBinder = HandoffBinder(applicationContext)

    // Nothing is held for a client: every bind gets the current offer, and an unbind frees it.
    override fun onUnbind(intent: Intent?): Boolean = false
}

internal class HandoffBinder(private val context: Context) : Binder() {
    override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
        if (code != TRANSACTION_GET) return super.onTransact(code, data, reply, flags)
        if (reply == null) return false
        // Binder thread, so the calling identity is the caller's. A call from this very process
        // reports denied, which is right: nothing in MeshMore calls itself over Binder.
        if (context.checkCallingPermission(PERMISSION) != PackageManager.PERMISSION_GRANTED) {
            reply.writeException(SecurityException("signature permission $PERMISSION required"))
            return true
        }
        data.enforceInterface(DESCRIPTOR)
        reply.writeNoException()
        reply.writeBundle(GatewayHandoffStore.current())
        return true
    }

    companion object {
        const val PERMISSION = "com.iotone.meshmore_sns_app.permission.GATEWAY_HANDOFF"
        const val DESCRIPTOR = "com.iotone.meshmore_sns_app.GatewayHandoff"
        const val TRANSACTION_GET = IBinder.FIRST_CALL_TRANSACTION
    }
}
