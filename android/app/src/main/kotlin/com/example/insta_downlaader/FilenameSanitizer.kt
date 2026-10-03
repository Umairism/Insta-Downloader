package com.example.insta_downlaader

import android.util.Log
import java.io.File
import java.util.Locale

object FilenameSanitizer {
    private val illegal = Regex("[\\\\/:*?\"<>|\\x00-\\x1F]")

    fun sanitize(raw: String, fallback: String = "Media_video"): String {
        var name = raw.substringAfterLast('/').substringAfterLast('\\')
        if (name.isBlank() || name == "." || name == "..") {
            return fallback
        }
        name = name.replace("..", "_")
        name = illegal.replace(name, "_")
        name = name.trim().trim('.')
        if (name.isBlank() || name == "." || name == "..") {
            return fallback
        }
        if (name.length > 80) {
            name = name.substring(0, 80)
        }
        return name
    }

    fun timestampedName(prefix: String = "Media", ext: String = "mp4", nowMillis: Long = System.currentTimeMillis()): String {
        val formatter = java.text.SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", Locale.US)
        val cleanExt = ext.trimStart('.').ifBlank { "mp4" }
        return "${prefix}_${formatter.format(java.util.Date(nowMillis))}.$cleanExt"
    }

    fun assertInside(directory: File, candidate: File) {
        val parent = directory.canonicalFile
        val child = candidate.canonicalFile
        if (!child.path.startsWith(parent.path + File.separator) && child != parent) {
            throw SecurityException("Path traversal blocked")
        }
    }
}

object DownloaderLog {
    private const val TAG = "Downloader"

    fun i(message: String) = Log.i(TAG, message)

    fun e(message: String, error: Throwable? = null) = Log.e(TAG, message, error)
}
