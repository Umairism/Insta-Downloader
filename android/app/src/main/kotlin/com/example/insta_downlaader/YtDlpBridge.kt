package com.example.insta_downlaader

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

class YtDlpBridge(private val context: Context) {
    private val mainHandler = Handler(Looper.getMainLooper())

    @Synchronized
    fun ensureStarted() {
        val updateDir = File(context.filesDir, "ytdlp_update")
        if (updateDir.isDirectory) {
            runCatching {
                android.system.Os.setenv("YTDLP_UPDATE_DIR", updateDir.absolutePath, true)
            }
        }
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(context.applicationContext))
        }
    }

    fun download(
        url: String,
        tempDir: File,
        cancelled: AtomicBoolean,
        onProgress: (status: String, percent: Double?, downloaded: Long?, total: Long?, message: String?) -> Unit,
    ): JSONObject {
        ensureStarted()
        val python = Python.getInstance()
        val module = python.getModule("downloader_engine")
        val progress = ProgressCallback(onProgress)
        val checker = CancelChecker(cancelled)
        val result = module.callAttr(
            "download",
            url,
            tempDir.absolutePath,
            progress,
            checker,
        )
        return JSONObject(result.toString())
    }

    inner class ProgressCallback(
        private val onProgress: (String, Double?, Long?, Long?, String?) -> Unit,
    ) {
        @Suppress("unused")
        fun on_progress(
            status: String?,
            percent: Any?,
            downloaded: Any?,
            total: Any?,
            message: String?,
        ) {
            val task = {
                onProgress(
                    status ?: "downloading",
                    (percent as? Number)?.toDouble(),
                    (downloaded as? Number)?.toLong(),
                    (total as? Number)?.toLong(),
                    message,
                )
            }
            if (Looper.myLooper() == Looper.getMainLooper()) {
                task()
            } else {
                mainHandler.post(task)
            }
        }
    }

    class CancelChecker(private val cancelled: AtomicBoolean) {
        @Suppress("unused")
        fun is_cancelled(): Boolean = cancelled.get()
    }
}
