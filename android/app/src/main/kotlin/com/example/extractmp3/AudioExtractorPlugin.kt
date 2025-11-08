package com.example.extractmp3

import android.content.ContentResolver
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

object AudioExtractorNative {
    private fun resolveInputPath(resolver: ContentResolver, rawPath: String, cacheDir: File): String {
        return if (rawPath.startsWith("content://")) {
            val uri = Uri.parse(rawPath)
            val tmp = File(cacheDir, "input_${System.currentTimeMillis()}.mp3")
            resolver.openInputStream(uri).use { ins ->
                FileOutputStream(tmp).use { outs -> ins?.copyTo(outs) }
            }
            tmp.absolutePath
        } else {
            rawPath
        }
    }

    private fun runFfmpeg(command: String): Pair<Boolean, String> {
        val session = FFmpegKit.execute(command)
        val ok = ReturnCode.isSuccess(session.returnCode)
        return ok to session.allLogsAsString
    }

    fun handle(
        call: MethodCall,
        result: MethodChannel.Result,
        resolver: ContentResolver,
        cacheDir: File,
        filesDir: File
    ) {
        when (call.method) {
            "extractAudioSegments" -> {
                val inputPath = call.argument<String>("inputPath")
                val outputPathWanted = call.argument<String>("outputPath")
                @Suppress("UNCHECKED_CAST")
                val segments = call.argument<List<Map<String, Any>>>("segments") ?: emptyList()

                if (inputPath.isNullOrBlank() || segments.isEmpty()) {
                    return result.success(mapOf(
                        "success" to false, "message" to "Bad arguments", "outputPath" to null
                    ))
                }

                val outFile = if (outputPathWanted.isNullOrBlank()) {
                    File(filesDir, "extracted_${System.currentTimeMillis()}.mp3")
                } else File(outputPathWanted)

                try {
                    val safeInput = resolveInputPath(resolver, inputPath, cacheDir)
                    val tempDir = File(cacheDir, "ffseg_${System.currentTimeMillis()}").apply { mkdirs() }
                    val parts = mutableListOf<File>()

                    segments.forEachIndexed { idx, seg ->
                        val start = (seg["startPosition"] as Number).toDouble()
                        val end   = (seg["endPosition"] as Number).toDouble()
                        val dur   = end - start
                        val segFile = File(tempDir, "segment_$idx.mp3")

                        val cutCmd = listOf(
                            "-ss", start.toString(),
                            "-t",  dur.toString(),
                            "-i", "\"$safeInput\"",
                            "-c:a", "libmp3lame",
                            "-b:a", "32k",
                            "\"${segFile.absolutePath}\"",
                            "-y"
                        ).joinToString(" ")
                        val (ok1, log1) = runFfmpeg(cutCmd)
                        if (!ok1) {
                            return result.success(mapOf(
                                "success" to false,
                                "message" to "FFmpeg segment $idx failed:\n$log1",
                                "outputPath" to null
                            ))
                        }
                        parts.add(segFile)

                        val silUser = (seg["silenceDuration"] as Number?)?.toDouble() ?: 0.0
                        val silDur = if (silUser > 0.0) silUser else if (idx < segments.size - 1) 1.0 else 0.0
                        if (silDur > 0.0) {
                            val silFile = File(tempDir, "silence_$idx.mp3")
                            val silCmd = listOf(
                                "-f", "lavfi",
                                "-i", "\"anullsrc=r=44100:cl=mono\"",
                                "-t", silDur.toString(),
                                "-c:a", "libmp3lame",
                                "-b:a", "32k",
                                "\"${silFile.absolutePath}\"",
                                "-y"
                            ).joinToString(" ")
                            val (ok2, log2) = runFfmpeg(silCmd)
                            if (!ok2) {
                                return result.success(mapOf(
                                    "success" to false,
                                    "message" to "FFmpeg silence gen failed:\n$log2",
                                    "outputPath" to null
                                ))
                            }
                            parts.add(silFile)
                        }
                    }

                    val listFile = File(tempDir, "concat.txt").apply {
                        writeText(parts.joinToString("\n") { f ->
                            "file '${f.absolutePath.replace("'", "'\\''")}'"
                        })
                    }

                    val concatCmd = listOf(
                        "-f", "concat", "-safe", "0",
                        "-i", "\"${listFile.absolutePath}\"",
                        "-c:a", "libmp3lame", "-b:a", "32k",
                        "\"${outFile.absolutePath}\"",
                        "-y"
                    ).joinToString(" ")
                    val (ok3, log3) = runFfmpeg(concatCmd)
                    if (!ok3) {
                        return result.success(mapOf(
                            "success" to false,
                            "message" to "FFmpeg concat failed:\n$log3",
                            "outputPath" to null
                        ))
                    }

                    result.success(mapOf(
                        "success" to true,
                        "message" to "Extraction successful",
                        "outputPath" to outFile.absolutePath
                    ))
                } catch (t: Throwable) {
                    result.success(mapOf(
                        "success" to false,
                        "message" to "Android native exception: ${t.message}",
                        "outputPath" to null
                    ))
                }
            }

            "extractAudio" -> {
                val inputPath = call.argument<String>("inputPath")
                val outputPath = call.argument<String>("outputPath")
                val start = call.argument<Double>("startTime") ?: 0.0
                val end   = call.argument<Double>("endTime")   ?: 0.0
                if (inputPath.isNullOrBlank() || outputPath.isNullOrBlank() || end <= start) {
                    return result.success(mapOf(
                        "success" to false, "message" to "Bad arguments", "outputPath" to null
                    ))
                }
                val dur = end - start
                try {
                    val safeInput = resolveInputPath(resolver, inputPath, cacheDir)
                    val cmd = listOf(
                        "-ss", start.toString(),
                        "-t",  dur.toString(),
                        "-i", "\"$safeInput\"",
                        "-c:a", "libmp3lame", "-b:a", "32k",
                        "\"$outputPath\"",
                        "-y"
                    ).joinToString(" ")
                    val (ok, log) = runFfmpeg(cmd)
                    if (!ok) {
                        result.success(mapOf(
                            "success" to false, "message" to "FFmpeg single extract failed:\n$log", "outputPath" to null
                        ))
                    } else {
                        result.success(mapOf(
                            "success" to true, "message" to "OK", "outputPath" to outputPath
                        ))
                    }
                } catch (t: Throwable) {
                    result.success(mapOf(
                        "success" to false, "message" to "Android native exception: ${t.message}", "outputPath" to null
                    ))
                }
            }

            else -> result.notImplemented()
        }
    }
}
