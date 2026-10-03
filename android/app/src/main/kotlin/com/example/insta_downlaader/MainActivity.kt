package com.example.insta_downlaader

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        SharedUrlStore.capture(intent, applicationContext)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(DownloaderPlugin())
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        SharedUrlStore.capture(intent, applicationContext)
        val url = SharedUrlStore.peek(applicationContext)
        if (!url.isNullOrBlank()) {
            DownloaderPlugin.instance?.emitShare(url)
        }
    }
}
