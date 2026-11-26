package dev.ibro.wishare

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DOWNLOAD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enqueue" -> enqueueDownload(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun enqueueDownload(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val fileName = call.argument<String>("fileName")
        val title = call.argument<String>("title") ?: "Wishare update"
        val description = call.argument<String>("description") ?: "Wishare update"

        if (url.isNullOrBlank() || fileName.isNullOrBlank()) {
            result.error("invalid_arguments", "url and fileName are required", null)
            return
        }
        val uri = Uri.parse(url)
        if (uri.scheme != "http" && uri.scheme != "https") {
            result.error("invalid_url", "Only http(s) downloads are allowed", null)
            return
        }

        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val request = DownloadManager.Request(uri)
            .setTitle(title)
            .setDescription(description)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true)

        try {
            result.success(manager.enqueue(request))
        } catch (e: Exception) {
            result.error("enqueue_failed", e.message, null)
        }
    }

    private companion object {
        const val DOWNLOAD_CHANNEL = "dev.ibro.wishare/downloads"
    }
}
