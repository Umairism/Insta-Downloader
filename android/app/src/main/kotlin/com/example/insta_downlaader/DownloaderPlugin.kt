package com.example.insta_downlaader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DownloaderPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var activity: Activity? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        methodChannel = MethodChannel(messenger, METHOD)
        eventChannel = EventChannel(messenger, EVENTS)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        appContext = binding.applicationContext
        DownloadRuntime.emitter = { payload ->
            mainHandler.post {
                eventSink?.success(payload)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        if (DownloadRuntime.emitter != null) {
            DownloadRuntime.emitter = null
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val context = appContext ?: return
        SharedUrlStore.peek(context)?.let { url ->
            events?.success(mapOf("type" to "share", "url" to url))
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            result.error("NO_CONTEXT", "Plugin is not attached", null)
            return
        }
        when (call.method) {
            "startDownload" -> {
                val url = call.argument<String>("url") ?: ""
                if (!SharedUrlStore.isValidHttpUrl(url)) {
                    result.success(
                        mapOf(
                            "ok" to false,
                            "code" to "INVALID_URL",
                            "message" to "Invalid HTTP/HTTPS URL.",
                        ),
                    )
                    return
                }
                maybeRequestNotifications()
                DownloadService.start(context, url)
                result.success(mapOf("ok" to true))
            }
            "cancelDownload" -> {
                DownloadService.cancel(context)
                result.success(mapOf("ok" to true))
            }
            "getInitialSharedUrl" -> {
                result.success(SharedUrlStore.consume(context))
            }
            "getDownloadedMedia" -> {
                val media = getDownloadedMedia(context)
                result.success(media)
            }
            "deleteMedia" -> {
                val uriValue = call.argument<String>("uri")
                if (uriValue.isNullOrBlank()) {
                    result.success(mapOf("ok" to false, "message" to "URI cannot be empty"))
                    return
                }
                val success = deleteMedia(context, uriValue)
                result.success(mapOf("ok" to success))
            }
            "openFile" -> {
                val uriValue = call.argument<String>("uri")
                if (uriValue.isNullOrBlank()) {
                    result.success(mapOf("ok" to false))
                    return
                }
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(Uri.parse(uriValue), "video/*")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                runCatching { context.startActivity(intent) }
                result.success(mapOf("ok" to true))
            }
            else -> result.notImplemented()
        }
    }

    private fun getDownloadedMedia(context: android.content.Context): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        val resolver = context.contentResolver
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            android.provider.MediaStore.Video.Media.getContentUri(android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }

        val projection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            arrayOf(
                android.provider.MediaStore.Video.Media._ID,
                android.provider.MediaStore.Video.Media.DISPLAY_NAME,
                android.provider.MediaStore.Video.Media.SIZE,
                android.provider.MediaStore.Video.Media.DATE_ADDED,
                android.provider.MediaStore.Video.Media.DURATION,
                android.provider.MediaStore.Video.Media.MIME_TYPE,
                android.provider.MediaStore.Video.Media.RELATIVE_PATH,
            )
        } else {
            arrayOf(
                android.provider.MediaStore.Video.Media._ID,
                android.provider.MediaStore.Video.Media.DISPLAY_NAME,
                android.provider.MediaStore.Video.Media.SIZE,
                android.provider.MediaStore.Video.Media.DATE_ADDED,
                android.provider.MediaStore.Video.Media.DURATION,
                android.provider.MediaStore.Video.Media.MIME_TYPE,
                android.provider.MediaStore.Video.Media.DATA,
            )
        }

        val selection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "${android.provider.MediaStore.Video.Media.RELATIVE_PATH} LIKE ?"
        } else {
            "${android.provider.MediaStore.Video.Media.DATA} LIKE ?"
        }
        val selectionArgs = arrayOf("%Media Downloader%")
        val sortOrder = "${android.provider.MediaStore.Video.Media.DATE_ADDED} DESC"

        try {
            resolver.query(collection, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(android.provider.MediaStore.Video.Media._ID)
                val nameCol = cursor.getColumnIndexOrThrow(android.provider.MediaStore.Video.Media.DISPLAY_NAME)
                val sizeCol = cursor.getColumnIndexOrThrow(android.provider.MediaStore.Video.Media.SIZE)
                val dateCol = cursor.getColumnIndexOrThrow(android.provider.MediaStore.Video.Media.DATE_ADDED)
                val durCol = cursor.getColumnIndex(android.provider.MediaStore.Video.Media.DURATION)
                val mimeCol = cursor.getColumnIndex(android.provider.MediaStore.Video.Media.MIME_TYPE)

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val name = cursor.getString(nameCol) ?: "Video"
                    val size = cursor.getLong(sizeCol)
                    val dateAdded = cursor.getLong(dateCol)
                    val duration = if (durCol != -1) cursor.getLong(durCol) else 0L
                    val mimeType = if (mimeCol != -1) cursor.getString(mimeCol) ?: "video/mp4" else "video/mp4"
                    val contentUri = android.content.ContentUris.withAppendedId(collection, id)

                    list.add(
                        mapOf(
                            "id" to id.toString(),
                            "displayName" to name,
                            "size" to size,
                            "dateAdded" to dateAdded,
                            "duration" to duration,
                            "uri" to contentUri.toString(),
                            "mimeType" to mimeType,
                        ),
                    )
                }
            }
        } catch (e: Exception) {
            DownloaderLog.e("Failed to query MediaStore", e)
        }

        return list
    }

    private fun deleteMedia(context: android.content.Context, uriString: String): Boolean {
        return try {
            val uri = Uri.parse(uriString)
            val deleted = context.contentResolver.delete(uri, null, null)
            deleted > 0
        } catch (e: Exception) {
            DownloaderLog.e("Failed to delete media", e)
            false
        }
    }

    fun emitShare(url: String) {
        mainHandler.post {
            eventSink?.success(mapOf("type" to "share", "url" to url))
        }
    }

    private fun maybeRequestNotifications() {
        val current = activity ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            current,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(
                current,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                1001,
            )
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        instance = this
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        instance = this
    }

    override fun onDetachedFromActivity() {
        activity = null
        if (instance === this) instance = null
    }

    companion object {
        const val METHOD = "com.example.insta_downlaader/downloader"
        const val EVENTS = "com.example.insta_downlaader/events"

        @Volatile
        var instance: DownloaderPlugin? = null

        @Volatile
        var appContext: android.content.Context? = null
    }
}
