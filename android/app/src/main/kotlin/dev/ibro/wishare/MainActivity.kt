package dev.ibro.wishare

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Environment
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OPEN_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openFile" -> openFile(call, result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MULTICAST_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    multicastLock?.acquire()
                    result.success(null)
                }
                "release" -> {
                    multicastLock?.let { if (it.isHeld) it.release() }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private val multicastLock: WifiManager.MulticastLock? by lazy {
        val manager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        manager?.createMulticastLock("wishare_mdns")?.apply { setReferenceCounted(true) }
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

    private fun openFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("invalid_arguments", "path is required", null)
            return
        }
        val file = File(path)
        if (!file.exists()) {
            result.success(false)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, contentResolver.getType(uri) ?: "*/*")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (intent.resolveActivity(packageManager) == null) {
                result.success(false)
                return
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("open_failed", e.message, null)
        }
    }

    private companion object {
        const val DOWNLOAD_CHANNEL = "dev.ibro.wishare/downloads"
        const val MULTICAST_CHANNEL = "dev.ibro.wishare/multicast"
        const val OPEN_CHANNEL = "dev.ibro.wishare/open"
    }
}
