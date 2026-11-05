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
    }
}
