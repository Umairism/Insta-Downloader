package com.example.insta_downlaader

import android.app.Activity
import android.os.Bundle
import android.widget.Toast

class ShareHandlerActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val text = SharedUrlStore.extractText(intent)
            val url = if (!text.isNullOrBlank()) {
                SharedUrlStore.extractUrl(text) ?: text.trim()
            } else {
                null
            }

            if (!url.isNullOrBlank() && SharedUrlStore.isValidHttpUrl(url)) {
                DownloadService.start(applicationContext, url)
                Toast.makeText(this, "Media Downloader: Download started", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(this, "Media Downloader: No valid URL found", Toast.LENGTH_SHORT).show()
            }
        } catch (e: Exception) {
            DownloaderLog.e("ShareHandlerActivity failed to process share intent", e)
        } finally {
            finish()
        }
    }
}
