package com.example.extractmp3

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaCodecInfo
import android.media.MediaMetadataRetriever
import com.naman14.androidlame.AndroidLame
import com.naman14.androidlame.LameBuilder
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import android.util.Log
import kotlinx.coroutines.*

class AudioExtractorPlugin {
    companion object {
        private const val TAG = "AudioExtractor"
        private const val CHANNEL = "audio_extractor"
        private const val DURATION_CHANNEL = "audio_duration"
        private const val TIMEOUT_US = 10000L
        
        fun registerWith(flutterEngine: FlutterEngine) {
            val channel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                CHANNEL
            )
            
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractAudio" -> {
                        CoroutineScope(Dispatchers.IO).launch {
                            val response = extractAudioInBackground(call)
                            withContext(Dispatchers.Main) {
                                result.success(response)
                            }
                        }
                    }
                    "extractAudioSegments" -> {
                        CoroutineScope(Dispatchers.IO).launch {
                            val response = extractMultipleSegments(call)
                            withContext(Dispatchers.Main) {
                                result.success(response)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
            
            val durationChannel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                DURATION_CHANNEL
            )
            
            durationChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDuration" -> getDuration(call, result)
                    else -> result.notImplemented()
                }
            }
        }
        
        private fun getDuration(call: MethodCall, result: MethodChannel.Result) {
            try {
                val filePath = call.argument<String>("filePath")!!
                val retriever = MediaMetadataRetriever()
                retriever.setDataSource(filePath)
                
                val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                val durationMs = durationStr?.toLongOrNull() ?: 0L
                val durationSeconds = durationMs / 1000.0
                
                retriever.release()
                
                result.success(durationSeconds)
            } catch (e: Exception) {
                Log.e(TAG, "Error getting duration", e)
                result.error("DURATION_ERROR", "Failed to get duration: ${e.message}", null)
            }
        }
        
        private suspend fun extractAudioInBackground(call: MethodCall): Map<String, Any?> = withContext(Dispatchers.IO) {
            try {
                val inputPath = call.argument<String>("inputPath")!!
                val outputPath = call.argument<String>("outputPath")!!
                val startTime = call.argument<Double>("startTime")!!
                val endTime = call.argument<Double>("endTime")!!
                
                Log.d(TAG, "Starting extraction in background")
                Log.d(TAG, "Input: $inputPath")
                Log.d(TAG, "Output: $outputPath")
                Log.d(TAG, "Time: $startTime to $endTime seconds")
                
                val tempM4aPath = outputPath.replace(".mp3", "_temp.m4a")
                Log.d(TAG, "Temp M4A: $tempM4aPath")
                
                val extractSuccess = extractAudioSegment(
                    inputPath,
                    tempM4aPath,
                    (startTime * 1_000_000).toLong(),
                    (endTime * 1_000_000).toLong()
                )
                
                Log.d(TAG, "Extract to M4A success: $extractSuccess")
                
                if (!extractSuccess) {
                    File(tempM4aPath).delete()
                    return@withContext mapOf(
                        "success" to false,
                        "message" to "Failed to extract audio segment",
                        "outputPath" to null
                    )
                }
                
                val tempFile = File(tempM4aPath)
                if (!tempFile.exists() || tempFile.length() < 1000) {
                    Log.e(TAG, "Temp M4A file is invalid: ${tempFile.length()} bytes")
                    tempFile.delete()
                    return@withContext mapOf(
                        "success" to false,
                        "message" to "Extracted file is too small",
                        "outputPath" to null
                    )
                }
                
                Log.d(TAG, "Temp M4A file size: ${tempFile.length()} bytes")
                Log.d(TAG, "Converting M4A to MP3...")
                
                val convertSuccess = convertM4aToMp3Simple(tempM4aPath, outputPath)
                
                Log.d(TAG, "Convert to MP3 success: $convertSuccess")
                
                tempFile.delete()
                
                if (convertSuccess) {
                    val outputFile = File(outputPath)
                    Log.d(TAG, "Final MP3 file size: ${outputFile.length()} bytes")
                    mapOf(
                        "success" to true,
                        "message" to "Extraction successful",
                        "outputPath" to outputPath
                    )
                } else {
                    mapOf(
                        "success" to false,
                        "message" to "Failed to convert to MP3",
                        "outputPath" to null
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error during extraction", e)
                mapOf(
                    "success" to false,
                    "message" to "Error: ${e.message}",
                    "outputPath" to null
                )
            }
        }
        
        private suspend fun extractMultipleSegments(call: MethodCall): Map<String, Any?> = withContext(Dispatchers.IO) {
            try {
                val inputPath = call.argument<String>("inputPath")!!
                val outputPath = call.argument<String>("outputPath")!!
                val segmentsList = call.argument<List<Map<String, Any>>>("segments")!!
                
                Log.d(TAG, "=== Starting multi-segment extraction ===")
                Log.d(TAG, "Input: $inputPath")
                Log.d(TAG, "Output: $outputPath")
                Log.d(TAG, "Number of segments: ${segmentsList.size}")
                
                val tempDir = File(outputPath).parentFile
                val segmentFiles = mutableListOf<String>()
                
                try {
                    // Extract each segment
                    for ((index, segmentMap) in segmentsList.withIndex()) {
                        Log.d(TAG, "Processing segment ${index + 1}/${segmentsList.size}")
                        
                        val startTime = (segmentMap["startPosition"] as Double) * 1_000_000
                        val endTime = (segmentMap["endPosition"] as Double) * 1_000_000
                        val silenceDuration = (segmentMap["silenceDuration"] as? Double ?: 0.0)
                        
                        Log.d(TAG, "Segment $index: ${startTime/1_000_000}s to ${endTime/1_000_000}s")
                        
                        val tempM4aPath = "${tempDir}/segment_${index}_temp.m4a"
                        val tempMp3Path = "${tempDir}/segment_${index}.mp3"
                        
                        // Extract segment to M4A
                        Log.d(TAG, "Extracting segment $index to M4A...")
                        val extractSuccess = extractAudioSegment(inputPath, tempM4aPath, startTime.toLong(), endTime.toLong())
                        
                        if (!extractSuccess) {
                            Log.e(TAG, "Failed to extract segment $index")
                            // Clean up
                            segmentFiles.forEach { File(it).delete() }
                            return@withContext mapOf(
                                "success" to false,
                                "message" to "Failed to extract segment ${index + 1}",
                                "outputPath" to null
                            )
                        }
                        
                        // Check M4A file
                        val m4aFile = File(tempM4aPath)
                        Log.d(TAG, "M4A file size: ${m4aFile.length()} bytes")
                        
                        if (!m4aFile.exists() || m4aFile.length() < 1000) {
                            Log.e(TAG, "M4A file too small or missing")
                            m4aFile.delete()
                            segmentFiles.forEach { File(it).delete() }
                            return@withContext mapOf(
                                "success" to false,
                                "message" to "Segment ${index + 1} file is invalid",
                                "outputPath" to null
                            )
                        }
                        
                        // Convert to MP3
                        Log.d(TAG, "Converting segment $index to MP3...")
                        val convertSuccess = convertM4aToMp3Simple(tempM4aPath, tempMp3Path)
                        m4aFile.delete()
                        
                        if (!convertSuccess) {
                            Log.e(TAG, "Failed to convert segment $index to MP3")
                            segmentFiles.forEach { File(it).delete() }
                            return@withContext mapOf(
                                "success" to false,
                                "message" to "Failed to convert segment ${index + 1} to MP3",
                                "outputPath" to null
                            )
                        }
                        
                        // Check MP3 file
                        val mp3File = File(tempMp3Path)
                        Log.d(TAG, "MP3 file size: ${mp3File.length()} bytes")
                        
                        segmentFiles.add(tempMp3Path)
                        
                        // Add silence if needed
                        if (silenceDuration > 0) {
                            Log.d(TAG, "Adding ${silenceDuration}s silence after segment $index")
                            val silencePath = "${tempDir}/silence_${index}.mp3"
                            val silenceSuccess = createSilence(silencePath, silenceDuration)
                            if (silenceSuccess) {
                                segmentFiles.add(silencePath)
                                Log.d(TAG, "Silence file created: ${File(silencePath).length()} bytes")
                            } else {
                                Log.w(TAG, "Failed to create silence file")
                            }
                        }
                        
                        Log.d(TAG, "Segment $index completed successfully")
                    }
                    
                    Log.d(TAG, "All segments extracted. Total files to combine: ${segmentFiles.size}")
                    
                    // Combine all segments
                    Log.d(TAG, "Combining MP3 files...")
                    val combineSuccess = combineMP3Files(segmentFiles, outputPath)
                    
                    // Clean up temp files
                    Log.d(TAG, "Cleaning up temp files...")
                    var deletedCount = 0
                    segmentFiles.forEach { 
                        if (File(it).delete()) deletedCount++
                    }
                    Log.d(TAG, "Deleted $deletedCount temp files")
                    
                    if (combineSuccess) {
                        val finalFile = File(outputPath)
                        Log.d(TAG, "=== Extraction completed successfully ===")
                        Log.d(TAG, "Final file size: ${finalFile.length()} bytes")
                        mapOf(
                            "success" to true,
                            "message" to "Extraction successful",
                            "outputPath" to outputPath
                        )
                    } else {
                        Log.e(TAG, "Failed to combine segments")
                        mapOf(
                            "success" to false,
                            "message" to "Failed to combine segments",
                            "outputPath" to null
                        )
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Exception during extraction", e)
                    // Clean up on error
                    segmentFiles.forEach { 
                        try {
                            File(it).delete()
                        } catch (ex: Exception) {
                            Log.e(TAG, "Error deleting temp file: $it", ex)
                        }
                    }
                    throw e
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error extracting multiple segments", e)
                mapOf(
                    "success" to false,
                    "message" to "Error: ${e.message}",
                    "outputPath" to null
                )
            }
        }        

        private fun extractAudioSegment(
            inputPath: String,
            outputPath: String,
            startTimeUs: Long,
            endTimeUs: Long
        ): Boolean {
            val extractor = MediaExtractor()
            var decoder: MediaCodec? = null
            var encoder: MediaCodec? = null
            var muxer: MediaMuxer? = null
            
            try {
                Log.d(TAG, "extractAudioSegment: Setting up extractor")
                extractor.setDataSource(inputPath)
                
                var audioTrackIndex = -1
                var inputFormat: MediaFormat? = null
                
                for (i in 0 until extractor.trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    
                    if (mime.startsWith("audio/")) {
                        audioTrackIndex = i
                        inputFormat = format
                        break
                    }
                }
                
                if (audioTrackIndex == -1 || inputFormat == null) {
                    Log.e(TAG, "No audio track found")
                    return false
                }
                
                extractor.selectTrack(audioTrackIndex)
                extractor.seekTo(startTimeUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                
                val sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                val channelCount = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                val mime = inputFormat.getString(MediaFormat.KEY_MIME) ?: ""
                
                Log.d(TAG, "Audio format: $sampleRate Hz, $channelCount channels, $mime")
                
                decoder = MediaCodec.createDecoderByType(mime)
                decoder.configure(inputFormat, null, null, 0)
                decoder.start()
                Log.d(TAG, "Decoder started")
                
                val outputFormat = MediaFormat.createAudioFormat(
                    MediaFormat.MIMETYPE_AUDIO_AAC,
                    sampleRate,
                    channelCount
                )
                outputFormat.setInteger(MediaFormat.KEY_BIT_RATE, 192000)
                outputFormat.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                outputFormat.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
                
                encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
                encoder.configure(outputFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                encoder.start()
                Log.d(TAG, "Encoder started")
                
                File(outputPath).parentFile?.mkdirs()
                muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                
                var muxerTrackIndex = -1
                var muxerStarted = false
                
                val decoderBufferInfo = MediaCodec.BufferInfo()
                val encoderBufferInfo = MediaCodec.BufferInfo()
                
                var extractorDone = false
                var decoderDone = false
                var encoderDone = false
                
                Log.d(TAG, "Starting processing loop")
                
                while (!encoderDone) {
                    // Feed decoder
                    if (!extractorDone) {
                        val inputBufferIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                        if (inputBufferIndex >= 0) {
                            val inputBuffer = decoder.getInputBuffer(inputBufferIndex)
                            val sampleSize = extractor.readSampleData(inputBuffer!!, 0)
                            val presentationTimeUs = extractor.sampleTime
                            
                            if (sampleSize < 0 || presentationTimeUs > endTimeUs) {
                                decoder.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                extractorDone = true
                                Log.d(TAG, "Extractor done, signaled decoder")
                            } else {
                                decoder.queueInputBuffer(inputBufferIndex, 0, sampleSize, presentationTimeUs, 0)
                                extractor.advance()
                            }
                        }
                    }
                    
                    // Get decoder output
                    val outputBufferIndex = decoder.dequeueOutputBuffer(decoderBufferInfo, TIMEOUT_US)
                    
                    if (outputBufferIndex >= 0) {
                        val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
                        
                        val isEOS = (decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        
                        if (decoderBufferInfo.size > 0 && decoderBufferInfo.presentationTimeUs >= startTimeUs) {
                            // Feed to encoder - wait for available buffer
                            var encoderInputIndex = -1
                            var attempts = 0
                            while (encoderInputIndex < 0 && attempts < 1000) {
                                encoderInputIndex = encoder.dequeueInputBuffer(1000)
                                attempts++
                            }
                            
                            if (encoderInputIndex >= 0) {
                                val encoderInputBuffer = encoder.getInputBuffer(encoderInputIndex)
                                encoderInputBuffer!!.clear()
                                
                                outputBuffer!!.position(decoderBufferInfo.offset)
                                outputBuffer.limit(decoderBufferInfo.offset + decoderBufferInfo.size)
                                encoderInputBuffer.put(outputBuffer)
                                
                                val flags = if (isEOS) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0
                                
                                encoder.queueInputBuffer(
                                    encoderInputIndex,
                                    0,
                                    decoderBufferInfo.size,
                                    decoderBufferInfo.presentationTimeUs - startTimeUs,
                                    flags
                                )
                                
                                if (isEOS) {
                                    Log.d(TAG, "END_OF_STREAM sent to encoder")
                                }
                            }
                        } else if (isEOS) {
                            // Empty EOS buffer - still need to signal encoder
                            var encoderInputIndex = -1
                            var attempts = 0
                            while (encoderInputIndex < 0 && attempts < 1000) {
                                encoderInputIndex = encoder.dequeueInputBuffer(1000)
                                attempts++
                            }
                            
                            if (encoderInputIndex >= 0) {
                                encoder.queueInputBuffer(encoderInputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                Log.d(TAG, "Empty END_OF_STREAM sent to encoder")
                            }
                        }
                        
                        decoder.releaseOutputBuffer(outputBufferIndex, false)
                        
                        if (isEOS) {
                            decoderDone = true
                            Log.d(TAG, "Decoder done")
                        }
                    }
                    
                    // Get encoder output
                    val encoderOutputIndex = encoder.dequeueOutputBuffer(encoderBufferInfo, TIMEOUT_US)
                    
                    when {
                        encoderOutputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            if (!muxerStarted) {
                                muxerTrackIndex = muxer.addTrack(encoder.outputFormat)
                                muxer.start()
                                muxerStarted = true
                                Log.d(TAG, "Muxer started")
                            }
                        }
                        encoderOutputIndex >= 0 -> {
                            val encodedData = encoder.getOutputBuffer(encoderOutputIndex)
                            
                            if ((encoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 && 
                                encoderBufferInfo.size > 0 && muxerStarted) {
                                encodedData!!.position(encoderBufferInfo.offset)
                                encodedData.limit(encoderBufferInfo.offset + encoderBufferInfo.size)
                                muxer.writeSampleData(muxerTrackIndex, encodedData, encoderBufferInfo)
                            }
                            
                            encoder.releaseOutputBuffer(encoderOutputIndex, false)
                            
                            if ((encoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                encoderDone = true
                                Log.d(TAG, "Encoder done - extraction complete!")
                            }
                        }
                    }
                }
                
                Log.d(TAG, "extractAudioSegment completed successfully")
                return true
                
            } catch (e: Exception) {
                Log.e(TAG, "Error extracting", e)
                return false
            } finally {
                try {
                    extractor.release()
                    decoder?.stop()
                    decoder?.release()
                    encoder?.stop()
                    encoder?.release()
                    muxer?.stop()
                    muxer?.release()
                    Log.d(TAG, "Cleanup completed")
                } catch (e: Exception) {
                    Log.e(TAG, "Cleanup error", e)
                }
            }
        }
        private fun convertM4aToMp3Simple(inputM4aPath: String, outputMp3Path: String): Boolean {
            val extractor = MediaExtractor()
            var decoder: MediaCodec? = null
            var lame: AndroidLame? = null
            var outputStream: FileOutputStream? = null
            
            try {
                extractor.setDataSource(inputM4aPath)
                
                var audioTrackIndex = -1
                var inputFormat: MediaFormat? = null
                
                for (i in 0 until extractor.trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("audio/")) {
                        audioTrackIndex = i
                        inputFormat = format
                        break
                    }
                }
                
                if (audioTrackIndex == -1 || inputFormat == null) return false
                
                extractor.selectTrack(audioTrackIndex)
                
                val sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                val channelCount = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                val mime = inputFormat.getString(MediaFormat.KEY_MIME) ?: ""
                
                decoder = MediaCodec.createDecoderByType(mime)
                decoder.configure(inputFormat, null, null, 0)
                decoder.start()
                
                lame = AndroidLame(
                    LameBuilder()
                        .setInSampleRate(sampleRate)
                        .setOutChannels(channelCount)
                        .setOutBitrate(192)
                        .setOutSampleRate(sampleRate)
                        .setQuality(5)
                )
                
                File(outputMp3Path).parentFile?.mkdirs()
                outputStream = FileOutputStream(outputMp3Path)
                
                val mp3Buffer = ByteArray(8192)
                val decoderBufferInfo = MediaCodec.BufferInfo()
                var extractorDone = false
                
                while (true) {
                    if (!extractorDone) {
                        val inputBufferIndex = decoder.dequeueInputBuffer(5000)
                        if (inputBufferIndex >= 0) {
                            val inputBuffer = decoder.getInputBuffer(inputBufferIndex)
                            val sampleSize = extractor.readSampleData(inputBuffer!!, 0)
                            
                            if (sampleSize < 0) {
                                decoder.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                extractorDone = true
                            } else {
                                decoder.queueInputBuffer(inputBufferIndex, 0, sampleSize, extractor.sampleTime, 0)
                                extractor.advance()
                            }
                        }
                    }
                    
                    val outputBufferIndex = decoder.dequeueOutputBuffer(decoderBufferInfo, 5000)
                    
                    if (outputBufferIndex >= 0) {
                        if (decoderBufferInfo.size > 0) {
                            val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
                            outputBuffer!!.position(decoderBufferInfo.offset)
                            outputBuffer.limit(decoderBufferInfo.offset + decoderBufferInfo.size)
                            
                            val pcmData = ShortArray(decoderBufferInfo.size / 2)
                            outputBuffer.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(pcmData)
                            
                            val bytesEncoded = if (channelCount == 1) {
                                lame.encode(pcmData, pcmData, pcmData.size, mp3Buffer)
                            } else {
                                val left = ShortArray(pcmData.size / 2)
                                val right = ShortArray(pcmData.size / 2)
                                for (i in pcmData.indices step 2) {
                                    left[i / 2] = pcmData[i]
                                    if (i + 1 < pcmData.size) right[i / 2] = pcmData[i + 1]
                                }
                                lame.encode(left, right, left.size, mp3Buffer)
                            }
                            
                            if (bytesEncoded > 0) {
                                outputStream.write(mp3Buffer, 0, bytesEncoded)
                            }
                        }
                        
                        decoder.releaseOutputBuffer(outputBufferIndex, false)
                        
                        if ((decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            break
                        }
                    }
                }
                
                val flushBytes = lame.flush(mp3Buffer)
                if (flushBytes > 0) {
                    outputStream.write(mp3Buffer, 0, flushBytes)
                }
                
                return true
                
            } catch (e: Exception) {
                Log.e(TAG, "MP3 conversion error", e)
                return false
            } finally {
                try {
                    extractor.release()
                    decoder?.stop()
                    decoder?.release()
                    outputStream?.close()
                    lame?.close()
                } catch (e: Exception) {
                    Log.e(TAG, "Cleanup error", e)
                }
            }
        }

        private fun createSilence(outputPath: String, durationSeconds: Double): Boolean {
            try {
                val lame = AndroidLame(
                    LameBuilder()
                        .setInSampleRate(44100)
                        .setOutChannels(2)
                        .setOutBitrate(192)
                        .setOutSampleRate(44100)
                        .setQuality(5)
                )
                
                val outputStream = FileOutputStream(outputPath)
                val mp3Buffer = ByteArray(8192)
                
                val sampleCount = (44100 * durationSeconds).toInt()
                
                val left = ShortArray(sampleCount / 2) { 0 }
                val right = ShortArray(sampleCount / 2) { 0 }
                
                val bytesEncoded = lame.encode(left, right, left.size, mp3Buffer)
                if (bytesEncoded > 0) {
                    outputStream.write(mp3Buffer, 0, bytesEncoded)
                }
                
                val flushBytes = lame.flush(mp3Buffer)
                if (flushBytes > 0) {
                    outputStream.write(mp3Buffer, 0, flushBytes)
                }
                
                outputStream.close()
                lame.close()
                
                return true
            } catch (e: Exception) {
                Log.e(TAG, "Error creating silence", e)
                return false
            }
        }

        private fun combineMP3Files(inputFiles: List<String>, outputPath: String): Boolean {
            try {
                val outputStream = FileOutputStream(outputPath)
                
                for (inputFile in inputFiles) {
                    val inputStream = File(inputFile).inputStream()
                    inputStream.copyTo(outputStream)
                    inputStream.close()
                }
                
                outputStream.close()
                return true
            } catch (e: Exception) {
                Log.e(TAG, "Error combining MP3 files", e)
                return false
            }
        }
    }
}