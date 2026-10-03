package com.example.insta_downlaader

import android.content.Context
import android.content.Intent
import android.util.Log
import java.util.regex.Pattern

object SharedUrlStore {
    private const val PREFS = "share_intent"
    private const val KEY = "pending_url"
    private const val TAG = "Downloader"

    private val urlPattern: Pattern =
        Pattern.compile("https?://[^\\s<>\"']+", Pattern.CASE_INSENSITIVE)

    @Volatile
    private var pending: String? = null

    fun capture(intent: Intent?, context: Context) {
        val text = extractText(intent) ?: return
        val url = extractUrl(text) ?: text.trim()
        if (url.isBlank()) return
        pending = url
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY, url)
            .apply()
        Log.i(TAG, "Captured shared URL")
    }

    fun peek(context: Context): String? {
        pending?.let { return it }
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
    }

    fun consume(context: Context): String? {
        val url = peek(context)
        pending = null
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY)
            .apply()
        return url
    }

    fun extractText(intent: Intent?): String? {
        if (intent == null) return null
        if (Intent.ACTION_SEND != intent.action) return null
        val type = intent.type ?: return null
        if (!type.startsWith("text/")) return null
        val extra = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (!extra.isNullOrBlank()) return extra
        val clip = intent.clipData ?: return null
        if (clip.itemCount <= 0) return null
        return clip.getItemAt(0).coerceToText(null)?.toString()
    }

    fun extractUrl(text: String): String? {
        val matcher = urlPattern.matcher(text)
        if (matcher.find()) {
            return matcher.group().trimEnd('.', ',', ')', ']', '"', '\'')
        }
        return null
    }

    fun isValidHttpUrl(raw: String?): Boolean {
        if (raw.isNullOrBlank()) return false
        val trimmed = raw.trim()
        val url = if (trimmed.startsWith("http://", ignoreCase = true) || trimmed.startsWith("https://", ignoreCase = true)) {
            trimmed
        } else {
            "https://$trimmed"
        }
        return try {
            val uri = android.net.Uri.parse(url)
            val scheme = uri.scheme?.lowercase()
            val host = uri.host
            (scheme == "http" || scheme == "https") && !host.isNullOrBlank()
        } catch (_: Exception) {
            false
        }
    }
}
