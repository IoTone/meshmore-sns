package com.iotone.meshmore_sns_app

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
        // Exported files live in the app's private directory, so a path in a
        // snackbar is not an export. The intent hands the receiver a
        // content:// URI with a read grant for that one file and nothing else.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "meshmore/share")
            .setMethodCallHandler { call, result ->
                if (call.method != "shareFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val mime = call.argument<String>("mime") ?: "application/octet-stream"
                val subject = call.argument<String>("subject")
                if (path == null) {
                    result.error("bad_args", "path is required", null)
                    return@setMethodCallHandler
                }
                try {
                    val file = File(path)
                    if (!file.exists()) {
                        result.error("missing", "no such file", null)
                        return@setMethodCallHandler
                    }
                    val uri = FileProvider.getUriForFile(
                        this, "$packageName.fileprovider", file
                    )
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = mime
                        putExtra(Intent.EXTRA_STREAM, uri)
                        if (subject != null) putExtra(Intent.EXTRA_SUBJECT, subject)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(send, subject))
                    result.success(true)
                } catch (e: Exception) {
                    result.error("share", e.message ?: e.javaClass.simpleName, null)
                }
            }
    }
}
