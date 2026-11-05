package com.iotone.meshmore_sns_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "meshmore/app_lifecycle")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // **Back leaves the task running, it does not finish the engine.** The radio
                    // link lives in the main isolate, and finishing the Activity destroys it: the
                    // radio disconnects and the foreground service stops (measured on the device,
                    // 2026-11-01). The foreground service and the notification already say the app
                    // is running.
                    "moveTaskToBack" -> result.success(moveTaskToBack(true))
                    else -> result.notImplemented()
                }
            }
        // The history store's key lives in the Android Keystore and never
        // leaves it, so sealing and opening happen here, not in Dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "meshmore/secure_store")
            .setMethodCallHandler { call, result ->
                val data = call.argument<ByteArray>("data")
                if (data == null) {
                    result.error("bad_args", "data is required", null)
                    return@setMethodCallHandler
                }
                try {
                    when (call.method) {
                        "seal" -> result.success(SecureStore.seal(data))
                        "open" -> result.success(SecureStore.open(data))
                        else -> result.notImplemented()
                    }
                } catch (e: javax.crypto.AEADBadTagException) {
                    // Wrong key, or the file was altered: the Dart side reports
                    // this as a corrupt store rather than as a write failure.
                    result.error("corrupt", "tag mismatch", null)
                } catch (e: Exception) {
                    result.error("cipher", e.message ?: e.javaClass.simpleName, null)
                }
            }
    }
}
