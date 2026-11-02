package com.iotone.meshmore_sns_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Dart's GatewayService publishes what the gateway offers; the handoff service only serves it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "meshmore/gateway_handoff")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "publish" -> {
                        GatewayHandoffStore.publish(
                            state = call.argument<String>("state") ?: "off",
                            port = call.argument<Int>("port") ?: 0,
                            token = call.argument<ByteArray>("token"),
                            radioKey = call.argument<String>("radioKey"),
                            peerName = call.argument<String>("peerName"),
                        )
                        result.success(null)
                    }
                    "clear" -> { GatewayHandoffStore.clear(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "meshmore/app_lifecycle")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // **Back leaves the task running, it does not finish the engine.** The radio
                    // link and the loopback gateway live in the main isolate, and finishing the
                    // Activity destroys it: the radio disconnects and every app that was handed the
                    // gateway endpoint finds nothing listening (measured on the device, 2026-11-01).
                    // The foreground service and the notification already say the app is running.
                    "moveTaskToBack" -> result.success(moveTaskToBack(true))
                    else -> result.notImplemented()
                }
            }
    }

    // With the engine gone nothing is listening any more, so nothing may be offered: a stale
    // "running" would hand a client a token for a port nobody holds.
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        GatewayHandoffStore.clear()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
