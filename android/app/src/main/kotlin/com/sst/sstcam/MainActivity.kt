package com.sst.sstcam

import android.content.ContentValues
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

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
                    "trimVideo" -> {
                        val source = call.argument<String>("source")
                        val output = call.argument<String>("output")
                        val startMs = (call.argument<Number>("startMs") ?: 0).toLong()
                        val durationMs = (call.argument<Number>("durationMs") ?: 0).toLong()
                        if (source == null || output == null) {
                            result.error("NULL_PATH", "source/output path is null", null)
                        } else {
                            try {
                                result.success(trimVideo(source, output, startMs, durationMs))
                            } catch (e: Exception) {
                                result.error("TRIM_FAILED", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Losslessly trims [sourcePath] to [output], keeping samples in
     * [startMs, startMs+durationMs]. Stream-copy via MediaExtractor +
     * MediaMuxer — no decode/encode, so it's fast and quality-preserving.
     * Replaces ffmpeg-kit, whose prebuilt libavfilter.so failed to load on
     * modern Android (UnsatisfiedLinkError: std::__ndk1::bad_function_call).
     *
     * Video starts at the sync sample at/just before startMs (decode needs a
     * keyframe); presentation timestamps are rebased so the clip starts at 0.
     */
    private fun trimVideo(
        sourcePath: String,
        output: String,
        startMs: Long,
        durationMs: Long,
    ): String {
        val extractor = MediaExtractor()
        val muxer = MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            extractor.setDataSource(sourcePath)
            val indexMap = HashMap<Int, Int>()
            var maxInputSize = 0
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/") || mime.startsWith("audio/")) {
                    extractor.selectTrack(i)
                    indexMap[i] = muxer.addTrack(format)
                    if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                        maxInputSize =
                            maxOf(maxInputSize, format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                    }
                }
            }
            if (maxInputSize <= 0) maxInputSize = 1 shl 21 // 2 MB fallback

            val startUs = startMs * 1000
            val endUs = (startMs + durationMs) * 1000
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            muxer.start()
            val buffer = ByteBuffer.allocate(maxInputSize)
            val info = MediaCodec.BufferInfo()
            var baseUs = -1L
            var samplesWritten = 0
            while (true) {
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val sampleTime = extractor.sampleTime
                if (sampleTime > endUs) break
                if (baseUs < 0) baseUs = sampleTime
                val dst = indexMap[extractor.sampleTrackIndex]
                if (dst != null) {
                    info.offset = 0
                    info.size = size
                    info.presentationTimeUs = (sampleTime - baseUs).coerceAtLeast(0)
                    // Map MediaExtractor sample flags to MediaMuxer BufferInfo
                    // flags explicitly. Passing extractor.sampleFlags raw is a bug:
                    // SAMPLE_FLAG_PARTIAL_FRAME (4) has the same bit as
                    // BUFFER_FLAG_END_OF_STREAM (4), which would cut the copy short.
                    info.flags =
                        if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                            MediaCodec.BUFFER_FLAG_KEY_FRAME
                        } else {
                            0
                        }
                    muxer.writeSampleData(dst, buffer, info)
                    samplesWritten++
                }
                extractor.advance()
            }
            // muxer.stop() throws an opaque IllegalStateException if nothing was
            // written (e.g. the requested window is past the end of the recording).
            // Surface a clear, per-clip reason instead so the caller can skip it.
            if (samplesWritten == 0) {
                throw IllegalStateException(
                    "no frames in the requested window (clip start may be past the end of the recording)"
                )
            }
            muxer.stop()
            return output
        } finally {
            try {
                muxer.release()
            } catch (_: Exception) {
            }
            extractor.release()
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
