package com.sst.sstcam

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val mediaChannel = "com.sst.sstcam/media"
    private lateinit var wifiDirectChannel: WifiDirectChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        wifiDirectChannel = WifiDirectChannel(applicationContext)
        wifiDirectChannel.register(flutterEngine)
        try {
            wifiDirectChannel.initialize(this)
        } catch (e: Throwable) {
            android.util.Log.e("MainActivity", "WifiDirectChannel.initialize failed: $e")
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveVideoToGallery" -> {
                        val path = call.argument<String>("path")
                        val name = call.argument<String>("name") ?: "video.mp4"
                        if (path == null) {
                            result.error("NULL_PATH", "source path is null", null)
                        } else {
                            try {
                                result.success(saveVideoToGallery(path, name))
                            } catch (e: Exception) {
                                result.error("SAVE_FAILED", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Saves [sourcePath] to Movies/SSTCam/<displayName> in the device gallery.
     *
     * API 29+ (Android 10+): uses MediaStore — no WRITE_EXTERNAL_STORAGE needed.
     * API < 29: copies to the public Movies directory and triggers MediaScanner.
     *
     * Idempotent: checks for an existing entry with the same display name
     * before inserting a new one.
     */
    private fun saveVideoToGallery(sourcePath: String, displayName: String): String {
        val src = File(sourcePath)

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Check for an existing gallery entry with this display name.
            val existing = contentResolver.query(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Video.Media._ID),
                "${MediaStore.Video.Media.DISPLAY_NAME} = ? AND " +
                    "${MediaStore.Video.Media.RELATIVE_PATH} = ?",
                arrayOf(displayName, "Movies/SSTCam/"),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val id = cursor.getLong(0)
                    android.net.Uri.withAppendedPath(
                        MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id.toString()
                    ).toString()
                } else null
            }
            if (existing != null) return existing

            // Insert a new MediaStore entry.
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/SSTCam")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values
            )!!
            contentResolver.openOutputStream(uri)!!.use { out ->
                src.inputStream().use { it.copyTo(out) }
            }
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            uri.toString()
        } else {
            // API < 29: copy to the public Movies directory and scan.
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
                "SSTCam"
            ).also { it.mkdirs() }
            val dest = File(dir, displayName)
            if (!dest.exists()) {
                src.copyTo(dest, overwrite = false)
                MediaScannerConnection.scanFile(
                    applicationContext, arrayOf(dest.absolutePath), null, null
                )
            }
            dest.absolutePath
        }
    }
}
