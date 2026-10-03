package com.example.insta_downlaader

import com.arthenica.ffmpegkit.FFmpegKit
import com.arthenica.ffmpegkit.ReturnCode
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

class FfmpegMerger {
    private val sessionId = AtomicLong(-1)

    fun cancel() {
        val id = sessionId.get()
        if (id >= 0) {
            FFmpegKit.cancel(id)
        } else {
            FFmpegKit.cancel()
        }
    }

    fun mergeOrRemux(inputs: List<File>, output: File): Result<File> {
        return runCatching {
            if (inputs.isEmpty()) {
                error("No input files for FFmpeg")
            }
            if (inputs.size == 1 && inputs[0].extension.equals("mp4", ignoreCase = true)) {
                inputs[0].copyTo(output, overwrite = true)
                return@runCatching output
            }

            DownloaderLog.i("FFmpeg merge started")
            val args = mutableListOf("-y")
            inputs.forEach { file ->
                args += listOf("-i", file.absolutePath)
            }
            if (inputs.size == 1) {
                args += listOf("-c", "copy", "-movflags", "+faststart", output.absolutePath)
            } else {
                args += listOf(
                    "-c",
                    "copy",
                    "-map",
                    "0:v:0",
                    "-map",
                    "1:a:0?",
                    "-shortest",
                    "-movflags",
                    "+faststart",
                    output.absolutePath,
                )
            }

            execute(args.toTypedArray())
            if (!output.exists() || output.length() == 0L) {
                error("FFmpeg produced an empty file")
            }
            DownloaderLog.i("FFmpeg merge finished")
            output
        }.recoverCatching {
            if (inputs.size == 1) {
                val source = inputs[0]
                if (source.exists() && source.length() > 0L) {
                    DownloaderLog.i("FFmpeg copy failed, keeping original stream")
                    source.copyTo(output, overwrite = true)
                    return@recoverCatching output
                }
            }
            throw it
        }
    }

    private fun execute(args: Array<String>) {
        val latch = CountDownLatch(1)
        val failure = AtomicReference<String?>(null)
        val session = FFmpegKit.executeWithArgumentsAsync(args) { completed ->
            sessionId.set(completed.sessionId)
            if (!ReturnCode.isSuccess(completed.returnCode)) {
                failure.set(completed.failStackTrace ?: completed.output ?: "FFmpeg failed")
            }
            latch.countDown()
        }
        sessionId.set(session.sessionId)
        val finished = latch.await(30, TimeUnit.MINUTES)
        if (!finished) {
            FFmpegKit.cancel(session.sessionId)
            error("FFmpeg timed out")
        }
        failure.get()?.let { error(it) }
    }
}
