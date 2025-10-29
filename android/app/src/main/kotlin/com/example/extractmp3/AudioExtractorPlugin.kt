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
                        // Run extraction in background thread
                        CoroutineScope(Dispatchers.IO).launch {
                            val response = extractAudioInBackground(call)
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
                    return false
                }
                
                extractor.selectTrack(audioTrackIndex)
                extractor.seekTo(startTimeUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                
                val sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                val channelCount = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                val mime = inputFormat.getString(MediaFormat.KEY_MIME) ?: ""
                
                decoder = MediaCodec.createDecoderByType(mime)
                decoder.configure(inputFormat, null, null, 0)
                decoder.start()
                
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
                
                File(outputPath).parentFile?.mkdirs()
                muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                
                var muxerTrackIndex = -1
                var muxerStarted = false
                
                val decoderBufferInfo = MediaCodec.BufferInfo()
                val encoderBufferInfo = MediaCodec.BufferInfo()
                
                var extractorDone = false
                var encoderDone = false
                
                while (!encoderDone) {
                    if (!extractorDone) {
                        val inputBufferIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                        if (inputBufferIndex >= 0) {
                            val inputBuffer = decoder.getInputBuffer(inputBufferIndex)
                            val sampleSize = extractor.readSampleData(inputBuffer!!, 0)
                            val presentationTimeUs = extractor.sampleTime
                            
                            if (sampleSize < 0 || presentationTimeUs > endTimeUs) {
                                decoder.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                extractorDone = true
                            } else {
                                decoder.queueInputBuffer(inputBufferIndex, 0, sampleSize, presentationTimeUs, 0)
                                extractor.advance()
                            }
                        }
                    }
                    
                    val outputBufferIndex = decoder.dequeueOutputBuffer(decoderBufferInfo, TIMEOUT_US)
                    
                    if (outputBufferIndex >= 0) {
                        val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
                        
                        if (decoderBufferInfo.size > 0 && decoderBufferInfo.presentationTimeUs >= startTimeUs) {
                            val encoderInputBufferIndex = encoder.dequeueInputBuffer(TIMEOUT_US)
                            if (encoderInputBufferIndex >= 0) {
                                val encoderInputBuffer = encoder.getInputBuffer(encoderInputBufferIndex)
                                encoderInputBuffer!!.clear()
                                
                                outputBuffer!!.position(decoderBufferInfo.offset)
                                outputBuffer.limit(decoderBufferInfo.offset + decoderBufferInfo.size)
                                encoderInputBuffer.put(outputBuffer)
                                
                                val flags = if ((decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                } else 0
                                
                                encoder.queueInputBuffer(
                                    encoderInputBufferIndex,
                                    0,
                                    decoderBufferInfo.size,
                                    decoderBufferInfo.presentationTimeUs - startTimeUs,
                                    flags
                                )
                            }
                        }
                        
                        decoder.releaseOutputBuffer(outputBufferIndex, false)
                    }
                    
                    val encoderOutputBufferIndex = encoder.dequeueOutputBuffer(encoderBufferInfo, TIMEOUT_US)
                    
                    if (encoderOutputBufferIndex >= 0) {
                        val encodedData = encoder.getOutputBuffer(encoderOutputBufferIndex)
                        
                        if ((encoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 && encoderBufferInfo.size > 0) {
                            if (!muxerStarted) {
                                return false
                            }
                            encodedData!!.position(encoderBufferInfo.offset)
                            encodedData.limit(encoderBufferInfo.offset + encoderBufferInfo.size)
                            muxer.writeSampleData(muxerTrackIndex, encodedData, encoderBufferInfo)
                        }
                        
                        encoder.releaseOutputBuffer(encoderOutputBufferIndex, false)
                        
                        if ((encoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            encoderDone = true
                        }
                    } else if (encoderOutputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        if (muxerStarted) return false
                        muxerTrackIndex = muxer.addTrack(encoder.outputFormat)
                        muxer.start()
                        muxerStarted = true
                    }
                }
                
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
    }
}