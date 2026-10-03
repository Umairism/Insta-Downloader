package com.example.insta_downlaader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

data class DownloadTask(
    val id: String = UUID.randomUUID().toString(),
    val url: String,
    val createdAt: Long = System.currentTimeMillis()
)

class DownloadService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CANCEL -> {
                DownloadRuntime.cancel()
                return START_NOT_STICKY
            }
            ACTION_START, ACTION_ENQUEUE -> {
                val url = intent.getStringExtra(EXTRA_URL)
                if (url.isNullOrBlank()) {
                    if (taskQueue.isEmpty() && !isProcessing.get()) {
                        stopSelf()
                    }
                    return START_NOT_STICKY
                }

                val task = DownloadTask(url = url.trim())
                taskQueue.add(task)
                startInForeground()

                emitState(
                    state = "queued",
                    message = "Queued for download",
                    extra = mapOf(
                        "taskId" to task.id,
                        "url" to task.url,
                        "queueSize" to taskQueue.size,
                    ),
                )

                scheduleQueueProcessing()
            }
        }
        return START_NOT_STICKY
    }

    private fun scheduleQueueProcessing() {
        synchronized(queueLock) {
            if (isProcessing.compareAndSet(false, true)) {
                worker.execute {
                    processQueue()
                }
            }
        }
    }

    private fun processQueue() {
        try {
            while (true) {
                val task = taskQueue.poll()
                if (task == null) {
                    isProcessing.set(false)
                    synchronized(queueLock) {
                        if (!taskQueue.isEmpty() && isProcessing.compareAndSet(false, true)) {
                            // Another task was added while completing
                            return@synchronized
                        }
                    }
                    if (!isProcessing.get()) {
                        break
                    }
                    continue
                }

                DownloadRuntime.activeTask = task
                DownloadRuntime.cancelled.set(false)
                runDownload(task)
                DownloadRuntime.activeTask = null
            }
        } finally {
            isProcessing.set(false)
            if (taskQueue.isEmpty()) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }

    private fun runDownload(task: DownloadTask) {
        val tempDir = File(cacheDir, "downloads/${task.id}")
        tempDir.mkdirs()
        val merger = FfmpegMerger()
        DownloadRuntime.merger = merger
        var currentTitle: String = "Media"

        try {
            emitState("validating", message = "Validating URL", extra = mapOf("taskId" to task.id))
            DownloaderLog.i("Validating URL: ${task.url}")

            if (!SharedUrlStore.isValidHttpUrl(task.url)) {
                emitError("INVALID_URL", "Invalid HTTP/HTTPS URL.")
                showFailureNotification("Invalid URL provided")
                return
            }

            emitState("downloading", message = "Downloading media", extra = mapOf("taskId" to task.id))
            updateProgressNotification(title = "Media Downloader", status = "Starting download...", percent = null)

            val bridge = YtDlpBridge(applicationContext)
            var lastNotificationTime = 0L

            val result = bridge.download(task.url, tempDir, DownloadRuntime.cancelled) { status, percent, downloaded, total, message ->
                val now = System.currentTimeMillis()
                if (now - lastNotificationTime > 400L || percent == 100.0) {
                    lastNotificationTime = now
                    val statusText = if (percent != null) {
                        "Downloading... ${percent.toInt()}%"
                    } else {
                        message ?: "Downloading..."
                    }
                    updateProgressNotification(
                        title = currentTitle,
                        status = statusText,
                        percent = percent,
                        downloaded = downloaded,
                        total = total,
                    )
                }

                emitState(
                    state = status,
                    percent = percent,
                    downloaded = downloaded,
                    total = total,
                    message = message ?: "Downloading",
                    extra = mapOf("taskId" to task.id),
                )
            }

            if (DownloadRuntime.cancelled.get()) {
                emitCancelled(task.id)
                return
            }

            val ok = result.optBoolean("ok", false)
            if (!ok) {
                val code = result.optString("code", "PROCESS")
                val message = result.optString("message", "Content unavailable or unsupported website.")
                if (code == "CANCELLED") {
                    emitCancelled(task.id)
                } else {
                    emitError(code, message, task.id)
                    showFailureNotification(message)
                }
                return
            }

            val extractedTitle = result.optString("title", "Media").ifBlank { "Media" }
            currentTitle = FilenameSanitizer.sanitize(extractedTitle, "Media_video")

            val filesJson = result.optJSONArray("files")
            val files = buildList {
                if (filesJson != null) {
                    for (index in 0 until filesJson.length()) {
                        add(File(filesJson.getString(index)))
                    }
                }
            }.filter { it.isFile }

            if (files.isEmpty()) {
                emitError("NO_MEDIA", "No media files could be extracted.", task.id)
                showFailureNotification("No media files could be extracted")
                return
            }

            emitState("processing", message = "Processing/Merging", extra = mapOf("taskId" to task.id))
            updateProgressNotification(title = currentTitle, status = "Processing media...", percent = null)

            val ext = result.optString("ext", "mp4").ifBlank { "mp4" }
            val outputName = FilenameSanitizer.timestampedName(prefix = currentTitle, ext = "mp4")
            val output = File(tempDir, outputName)
            FilenameSanitizer.assertInside(tempDir, output)

            val needsMerge = result.optBoolean("needs_merge", false)
            val finalFile: File = if (needsMerge && files.size > 1) {
                merger.mergeOrRemux(files, output).getOrElse { error ->
                    if (DownloadRuntime.cancelled.get()) {
                        emitCancelled(task.id)
                        return
                    }
                    DownloaderLog.e("FFmpeg failed", error)
                    emitError("PROCESS", "Failed to process/merge media.", task.id)
                    showFailureNotification("Failed to process media")
                    return
                }
            } else if (files.size == 1 && files[0].extension.equals("mp4", ignoreCase = true)) {
                files[0]
            } else {
                merger.mergeOrRemux(files, output).getOrElse {
                    files[0]
                }
            }

            if (DownloadRuntime.cancelled.get()) {
                emitCancelled(task.id)
                return
            }

            emitState("saving", message = "Saving to device", extra = mapOf("taskId" to task.id))
            updateProgressNotification(title = currentTitle, status = "Saving to storage...", percent = 100.0)

            val saved = MediaStoreSaver(applicationContext).saveVideo(finalFile, output.name)
            emitState(
                state = "completed",
                percent = 100.0,
                message = "Download completed.",
                extra = mapOf(
                    "taskId" to task.id,
                    "title" to currentTitle,
                    "savedPath" to saved.displayPath,
                    "savedUri" to saved.uri.toString(),
                ),
            )
            DownloaderLog.i("File successfully saved: ${saved.displayPath}")

            showCompletionNotification(
                title = currentTitle,
                fileName = output.name,
                uri = saved.uri,
            )
        } catch (error: Exception) {
            if (DownloadRuntime.cancelled.get()) {
                emitCancelled(task.id)
            } else {
                DownloaderLog.e("Download failed", error)
                val userMsg = userMessageFor(error)
                emitError("PROCESS", userMsg, task.id)
                showFailureNotification(userMsg)
            }
        } finally {
            DownloadRuntime.merger = null
            tempDir.deleteRecursively()
        }
    }

    private fun userMessageFor(error: Exception): String {
        val text = error.message?.lowercase().orEmpty()
        return when {
            "network" in text || "timeout" in text || "unable to resolve" in text ->
                "Network connection failed."
            "unsupported" in text ->
                "Unsupported website or format."
            else ->
                "Content unavailable or unsupported."
        }
    }

    private fun emitCancelled(taskId: String) {
        emitState("cancelled", message = "Download was cancelled.", extra = mapOf("taskId" to taskId))
    }

    private fun emitError(code: String, message: String, taskId: String? = null) {
        val payload = mutableMapOf<String, Any?>(
            "type" to "state",
            "state" to "error",
            "code" to code,
            "message" to message,
        )
        if (taskId != null) {
            payload["taskId"] = taskId
        }
        DownloadRuntime.emit(payload)
    }

    private fun emitState(
        state: String,
        percent: Double? = null,
        downloaded: Long? = null,
        total: Long? = null,
        message: String? = null,
        extra: Map<String, Any?> = emptyMap(),
    ) {
        val payload = mutableMapOf<String, Any?>(
            "type" to "state",
            "state" to state,
            "message" to message,
            "percent" to percent,
            "downloadedBytes" to downloaded,
            "totalBytes" to total,
        )
        payload.putAll(extra)
        DownloadRuntime.emit(payload)
    }

    private fun ensureNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            val progressChannel = NotificationChannel(
                CHANNEL_PROGRESS,
                "Active Downloads",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows progress of currently running media downloads"
                setShowBadge(false)
            }
            val completeChannel = NotificationChannel(
                CHANNEL_COMPLETE,
                "Completed Downloads",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Notifies when downloads finish or fail"
                setShowBadge(true)
            }
            manager.createNotificationChannel(progressChannel)
            manager.createNotificationChannel(completeChannel)
        }
    }

    private fun startInForeground() {
        val notification = buildProgressNotification(
            title = "Media Downloader",
            status = "Preparing...",
            percent = null,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateProgressNotification(
        title: String,
        status: String,
        percent: Double? = null,
        downloaded: Long? = null,
        total: Long? = null,
    ) {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val notification = buildProgressNotification(title, status, percent, downloaded, total)
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun buildProgressNotification(
        title: String,
        status: String,
        percent: Double? = null,
        downloaded: Long? = null,
        total: Long? = null,
    ): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val cancelIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, DownloadService::class.java).setAction(ACTION_CANCEL),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val queueCount = taskQueue.size
        val queueSuffix = if (queueCount > 0) " (+$queueCount queued)" else ""
        val contentText = "$status$queueSuffix"

        val builder = NotificationCompat.Builder(this, CHANNEL_PROGRESS)
            .setContentTitle(title)
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(openIntent)
            .addAction(0, "Cancel", cancelIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)

        if (percent != null) {
            builder.setProgress(100, percent.toInt(), false)
        } else {
            builder.setProgress(100, 0, true)
        }

        return builder.build()
    }

    private fun showCompletionNotification(title: String, fileName: String, uri: Uri) {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "video/*")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val pendingOpen = PendingIntent.getActivity(
            this,
            System.currentTimeMillis().toInt(),
            viewIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_COMPLETE)
            .setContentTitle("Media Downloader")
            .setContentText("Download complete: $fileName")
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentIntent(pendingOpen)
            .setAutoCancel(true)
            .build()

        manager.notify(System.currentTimeMillis().toInt(), notification)
    }

    private fun showFailureNotification(message: String) {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val notification = NotificationCompat.Builder(this, CHANNEL_COMPLETE)
            .setContentTitle("Media Downloader")
            .setContentText("Download failed: $message")
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setAutoCancel(true)
            .build()

        manager.notify(System.currentTimeMillis().toInt(), notification)
    }

    companion object {
        private const val CHANNEL_PROGRESS = "downloads_progress"
        private const val CHANNEL_COMPLETE = "downloads_complete"
        private const val NOTIFICATION_ID = 42

        const val ACTION_START = "com.example.insta_downlaader.START"
        const val ACTION_ENQUEUE = "com.example.insta_downlaader.ENQUEUE"
        const val ACTION_CANCEL = "com.example.insta_downlaader.CANCEL"
        const val EXTRA_URL = "url"

        private val worker = Executors.newSingleThreadExecutor()
        private val taskQueue = ConcurrentLinkedQueue<DownloadTask>()
        private val isProcessing = AtomicBoolean(false)
        private val queueLock = Any()

        fun start(context: Context, url: String) {
            val intent = Intent(context, DownloadService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_URL, url)
            }
            androidx.core.content.ContextCompat.startForegroundService(context, intent)
        }

        fun cancel(context: Context) {
            val intent = Intent(context, DownloadService::class.java).apply {
                action = ACTION_CANCEL
            }
            context.startService(intent)
            DownloadRuntime.cancel()
        }
    }
}

object DownloadRuntime {
    val cancelled = AtomicBoolean(false)

    @Volatile
    var activeTask: DownloadTask? = null

    @Volatile
    var merger: FfmpegMerger? = null

    @Volatile
    var emitter: ((Map<String, Any?>) -> Unit)? = null

    fun cancel() {
        cancelled.set(true)
        merger?.cancel()
    }

    fun emit(payload: Map<String, Any?>) {
        emitter?.invoke(payload)
    }
}
