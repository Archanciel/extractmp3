// android/app/src/main/kotlin/com/example/extractmp3/AudioExtractorPlugin.kt
package <your.package>

import android.content.ContentResolver
import android.net.Uri
import android.os.Environment
import com.arthenica.ffmpegkit.FFmpegKit
import com.arthenica.ffmpegkit.ReturnCode
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

object AudioExtractorNative {

    // Ensure we have a real filesystem path; copy content:// to a temp file if needed.
    private fun resolveInputPath(call: MethodCall, resolver: ContentResolver, rawPath: String, cacheDir: File): String {
        return if (rawPath.startsWith("content://")) {
            val uri = Uri.parse(rawPath)
            val tmp = File(cacheDir, "input_${System.currentTimeMillis()}.mp3")
            resolver.openInputStream(uri).use { `in` ->
                FileOutputStream(tmp).use { out -> `in`?.copyTo(out) }
            }
            tmp.absolutePath
        } else {
            rawPath // file:// or plain path
        }
    }

    private fun runFfmpeg(command: String): Pair<Boolean, String> {
        val session = FFmpegKit.execute(command)
        val rc = session.returnCode
        val logs = session.allLogsAsString
        return Pair(ReturnCode.isSuccess(rc), logs)
    }

    fun handle(call: MethodCall, result: MethodChannel.Result, resolver: ContentResolver, cacheDir: File, filesDir: File) {
        when (call.method) {
            "extractAudioSegments" -> {
                val inputPath = call.argument<String>("inputPath") ?: return result.success(
                    mapOf("success" to false, "message" to "inputPath missing", "outputPath" to null)
                )
                val outputPathWanted = call.argument<String>("outputPath")
                @Suppress("UNCHECKED_CAST")
                val segments = call.argument<List<Map<String, Any>>>("segments") ?: emptyList()

                // Choose a safe output path inside app-private external files if not provided
                val outFile = if (outputPathWanted.isNullOrBlank()) {
                    val dir = filesDir // or context.getExternalFilesDir(null)
                    File(dir, "extracted_${System.currentTimeMillis()}.mp3")
                } else {
                    File(outputPathWanted)
                }

                try {
                    val safeInput = resolveInputPath(call, resolver, inputPath, cacheDir)
                    val tempDir = File(cacheDir, "ffseg_${System.currentTimeMillis()}")
                    tempDir.mkdirs()

                    val segmentFiles = mutableListOf<File>()

                    // Generate each segment as MP3 (you can switch to WAV intermediates if you prefer)
                    segments.forEachIndexed { idx, seg ->
                        val start = (seg["startPosition"] as Number).toDouble()
                        val end   = (seg["endPosition"] as Number).toDouble()
                        val dur   = end - start
                        val segFile = File(tempDir, "segment_$idx.mp3")

                        val cmd = listOf(
                            "-ss", start.toString(),
                            "-t", dur.toString(),
                            "-i", "\"$safeInput\"",
                            "-c:a", "libmp3lame",
                            "-b:a", "32k",
                            "\"${segFile.absolutePath}\"",
                            "-y"
                        ).joinToString(" ")
                        val (ok1, log1) = runFfmpeg(cmd)
                        if (!ok1) {
                            return result.success(mapOf(
                                "success" to false,
                                "message" to "FFmpeg segment $idx failed:\n$log1",
                                "outputPath" to null
                            ))
                        }
                        segmentFiles.add(segFile)

                        // Add silence after the segment, if requested (> 0) or as default between segments
                        val sil = ((seg["silenceDuration"] as Number?)?.toDouble() ?: 0.0)
                        val needDefault = (sil == 0.0 && idx < segments.size - 1)
                        val silDur = if (sil > 0) sil else if (needDefault) 1.0 else 0.0
                        if (silDur > 0.0) {
                            val silFile = File(tempDir, "silence_${idx}.mp3")
                            // Generate silence with anullsrc then encode as MP3
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
                            segmentFiles.add(silFile)
                        }
                    }

                    // Concat list file
                    val listFile = File(tempDir, "concat.txt")
                    listFile.writeText(segmentFiles.joinToString("\n") { f ->
                        "file '${f.absolutePath.replace("'", "'\\''")}'"
                    })

                    // Re-encode once at the end (avoid MP3 padding problems)
                    val concatCmd = listOf(
                        "-f", "concat",
                        "-safe", "0",
                        "-i", "\"${listFile.absolutePath}\"",
                        "-c:a", "libmp3lame",
                        "-b:a", "32k",
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
                        "success" to false,
                        "message" to "Bad arguments for extractAudio",
                        "outputPath" to null
                    ))
                }
                val dur = end - start
                try {
                    val safeInput = resolveInputPath(call, resolver, inputPath, cacheDir)
                    val cmd = listOf(
                        "-ss", start.toString(),
                        "-t", dur.toString(),
                        "-i", "\"$safeInput\"",
                        "-c:a", "libmp3lame",
                        "-b:a", "32k",
                        "\"$outputPath\"",
                        "-y"
                    ).joinToString(" ")
                    val (ok, log) = runFfmpeg(cmd)
                    if (!ok) {
                        result.success(mapOf(
                            "success" to false,
                            "message" to "FFmpeg single extract failed:\n$log",
                            "outputPath" to null
                        ))
                    } else {
                        result.success(mapOf(
                            "success" to true,
                            "message" to "OK",
                            "outputPath" to outputPath
                        ))
                    }
                } catch (t: Throwable) {
                    result.success(mapOf(
                        "success" to false,
                        "message" to "Android native exception: ${t.message}",
                        "outputPath" to null
                    ))
                }
            }

            else -> result.notImplemented()
        }
    }
}
