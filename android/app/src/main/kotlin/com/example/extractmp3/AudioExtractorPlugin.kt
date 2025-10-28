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

class AudioExtractorPlugin {
    companion object {
        private const val CHANNEL = "audio_extractor"
        private const val DURATION_CHANNEL = "audio_duration"
        private const val TIMEOUT_US = 10000L
        
        fun registerWith(flutterEngine: FlutterEngine) {
            // Audio extraction channel
            val channel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                CHANNEL
            )
            
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractAudio" -> {
                        extractAudio(call, result)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
            
            // Duration channel
            val durationChannel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                DURATION_CHANNEL
            )
            
            durationChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDuration" -> {
                        getDuration(call, result)
                    }
                    else -> {
                        result.notImplemented()
                    }
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
                e.printStackTrace()
                result.error("DURATION_ERROR", "Failed to get duration: ${e.message}", null)
            }
        }

        private fun extractAudio(call: MethodCall, result: MethodChannel.Result) {
            try {
                val inputPath = call.argument<String>("inputPath")!!
                val outputPath = call.argument<String>("outputPath")!!
                val startTime = call.argument<Double>("startTime")!!
                val endTime = call.argument<Double>("endTime")!!
                
                android.util.Log.d("AudioExtractor", "Starting extraction")
                android.util.Log.d("AudioExtractor", "Input: $inputPath")
                android.util.Log.d("AudioExtractor", "Output: $outputPath")
                android.util.Log.d("AudioExtractor", "Time: $startTime to $endTime")
                
                // First extract to temporary M4A file
                val tempM4aPath = outputPath.replace(".mp3", "_temp.m4a")
                
                android.util.Log.d("AudioExtractor", "Temp M4A: $tempM4aPath")
                
                val extractSuccess = extractAudioSegment(
                    inputPath,
                    tempM4aPath,
                    (startTime * 1_000_000).toLong(),
                    (endTime * 1_000_000).toLong()
                )
                
                android.util.Log.d("AudioExtractor", "Extract success: $extractSuccess")
                
                if (!extractSuccess) {
                    result.success(mapOf(
                        "success" to false,
                        "message" to "Failed to extract audio segment",
                        "outputPath" to null
                    ))
                    return
                }
                
                // Convert M4A to MP3
                android.util.Log.d("AudioExtractor", "Converting M4A to MP3")
                val convertSuccess = convertM4aToMp3(tempM4aPath, outputPath)
                
                android.util.Log.d("AudioExtractor", "Convert success: $convertSuccess")
                
                // Clean up temp file
                File(tempM4aPath).delete()
                
                if (convertSuccess) {
                    result.success(mapOf(
                        "success" to true,
                        "message" to "Extraction successful",
                        "outputPath" to outputPath
                    ))
                } else {
                    result.success(mapOf(
                        "success" to false,
                        "message" to "Failed to convert to MP3",
                        "outputPath" to null
                    ))
                }
            } catch (e: Exception) {
                e.printStackTrace()
                android.util.Log.e("AudioExtractor", "Error: ${e.message}", e)
                result.success(mapOf(
                    "success" to false,
                    "message" to "Error: ${e.message}\n${e.stackTraceToString()}",
                    "outputPath" to null
                ))
            }
        }

        private fun convertM4aToMp3(inputM4aPath: String, outputMp3Path: String): Boolean {
            val extractor = MediaExtractor()
            var decoder: MediaCodec? = null
            var outputStream: FileOutputStream? = null
            var lame: AndroidLame? = null
            
            try {
                // Set up extractor
                extractor.setDataSource(inputM4aPath)
                
                // Find audio track
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
                
                // Get audio parameters
                val sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                val channelCount = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                val mime = inputFormat.getString(MediaFormat.KEY_MIME) ?: ""
                
                // Create decoder
                decoder = MediaCodec.createDecoderByType(mime)
                decoder.configure(inputFormat, null, null, 0)
                decoder.start()
                
                // Initialize LAME encoder
                val lameBuilder = LameBuilder()
                    .setInSampleRate(sampleRate)
                    .setOutChannels(channelCount)
                    .setOutBitrate(192)
                    .setOutSampleRate(sampleRate)
                    .setQuality(5)
                
                lame = AndroidLame(lameBuilder)
                
                // Create output file
                val outputFile = File(outputMp3Path)
                outputFile.parentFile?.mkdirs()
                outputStream = FileOutputStream(outputFile)
                
                val decoderInputBuffers = decoder.inputBuffers
                val decoderOutputBuffers = decoder.outputBuffers
                val decoderBufferInfo = MediaCodec.BufferInfo()
                
                var extractorDone = false
                val mp3Buffer = ByteArray(8192)
                
                while (true) {
                    // Feed decoder
                    if (!extractorDone) {
                        val inputBufferIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                        if (inputBufferIndex >= 0) {
                            val inputBuffer = decoderInputBuffers[inputBufferIndex]
                            val sampleSize = extractor.readSampleData(inputBuffer, 0)
                            
                            if (sampleSize < 0) {
                                decoder.queueInputBuffer(
                                    inputBufferIndex,
                                    0,
                                    0,
                                    0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                )
                                extractorDone = true
                            } else {
                                val presentationTimeUs = extractor.sampleTime
                                decoder.queueInputBuffer(
                                    inputBufferIndex,
                                    0,
                                    sampleSize,
                                    presentationTimeUs,
                                    0
                                )
                                extractor.advance()
                            }
                        }
                    }
                    
                    // Get decoded PCM data
                    val outputBufferIndex = decoder.dequeueOutputBuffer(decoderBufferInfo, TIMEOUT_US)
                    
                    if (outputBufferIndex >= 0) {
                        val outputBuffer = decoderOutputBuffers[outputBufferIndex]
                        
                        if (decoderBufferInfo.size > 0) {
                            // Convert ByteBuffer to short array (PCM data)
                            outputBuffer.position(decoderBufferInfo.offset)
                            outputBuffer.limit(decoderBufferInfo.offset + decoderBufferInfo.size)
                            
                            val pcmData = ShortArray(decoderBufferInfo.size / 2)
                            outputBuffer.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(pcmData)
                            
                            // Encode PCM to MP3
                            val bytesEncoded = if (channelCount == 1) {
                                lame.encode(pcmData, pcmData, pcmData.size, mp3Buffer)
                            } else {
                                // For stereo, we need to split into left and right channels
                                val leftChannel = ShortArray(pcmData.size / 2)
                                val rightChannel = ShortArray(pcmData.size / 2)
                                
                                for (i in pcmData.indices step 2) {
                                    leftChannel[i / 2] = pcmData[i]
                                    if (i + 1 < pcmData.size) {
                                        rightChannel[i / 2] = pcmData[i + 1]
                                    }
                                }
                                
                                lame.encode(leftChannel, rightChannel, leftChannel.size, mp3Buffer)
                            }
                            
                            if (bytesEncoded > 0) {
                                outputStream.write(mp3Buffer, 0, bytesEncoded)
                            }
                        }
                        
                        decoder.releaseOutputBuffer(outputBufferIndex, false)
                        
                        if ((decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            break
                        }
                    } else if (outputBufferIndex == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED) {
                        // Output buffers changed, update reference
                    } else if (outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        // Output format changed
                    }
                }
                
                // Flush remaining MP3 data
                val flushBytes = lame.flush(mp3Buffer)
                if (flushBytes > 0) {
                    outputStream.write(mp3Buffer, 0, flushBytes)
                }
                
                return true
                
            } catch (e: Exception) {
                e.printStackTrace()
                return false
            } finally {
                extractor.release()
                decoder?.stop()
                decoder?.release()
                outputStream?.close()
                lame?.close()
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
                extractor.seekTo(startTimeUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                
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
                outputFormat.setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectLC
                )
                
                encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
                encoder.configure(outputFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                encoder.start()
                
                val outputFile = File(outputPath)
                outputFile.parentFile?.mkdirs()
                
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
                            
                            if (sampleSize < 0 || extractor.sampleTime > endTimeUs) {
                                decoder.queueInputBuffer(
                                    inputBufferIndex,
                                    0,
                                    0,
                                    0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                )
                                extractorDone = true
                            } else {
                                val presentationTimeUs = extractor.sampleTime
                                decoder.queueInputBuffer(
                                    inputBufferIndex,
                                    0,
                                    sampleSize,
                                    presentationTimeUs,
                                    0
                                )
                                extractor.advance()
                            }
                        }
                    }
                    
                    val outputBufferIndex = decoder.dequeueOutputBuffer(decoderBufferInfo, TIMEOUT_US)
                    
                    if (outputBufferIndex >= 0) {
                        val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
                        
                        if (decoderBufferInfo.presentationTimeUs >= startTimeUs) {
                            val encoderInputBufferIndex = encoder.dequeueInputBuffer(TIMEOUT_US)
                            if (encoderInputBufferIndex >= 0) {
                                val encoderInputBuffer = encoder.getInputBuffer(encoderInputBufferIndex)
                                encoderInputBuffer!!.clear()
                                
                                outputBuffer!!.limit(decoderBufferInfo.offset + decoderBufferInfo.size)
                                outputBuffer.position(decoderBufferInfo.offset)
                                encoderInputBuffer.put(outputBuffer)
                                
                                val flags = if ((decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                } else {
                                    0
                                }
                                
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
                    
                    var encoderOutputBufferIndex = encoder.dequeueOutputBuffer(encoderBufferInfo, TIMEOUT_US)
                    
                    while (encoderOutputBufferIndex >= 0) {
                        val encodedData = encoder.getOutputBuffer(encoderOutputBufferIndex)
                        
                        if ((encoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 &&
                            encoderBufferInfo.size != 0
                        ) {
                            if (!muxerStarted) {
                                throw RuntimeException("Muxer not started")
                            }
                            
                            encodedData!!.position(encoderBufferInfo.offset)
                            encodedData.limit(encoderBufferInfo.offset + encoderBufferInfo.size)
                            
                            muxer.writeSampleData(muxerTrackIndex, encodedData, encoderBufferInfo)
                        }
                        
                        encoder.releaseOutputBuffer(encoderOutputBufferIndex, false)
                        
                        if ((encoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            encoderDone = true
                            break
                        }
                        
                        encoderOutputBufferIndex = encoder.dequeueOutputBuffer(encoderBufferInfo, TIMEOUT_US)
                    }
                    
                    if (encoderOutputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        if (muxerStarted) {
                            throw RuntimeException("Format changed twice")
                        }
                        
                        val newFormat = encoder.outputFormat
                        muxerTrackIndex = muxer.addTrack(newFormat)
                        muxer.start()
                        muxerStarted = true
                    }
                }
                
                return true
                
            } catch (e: Exception) {
                e.printStackTrace()
                return false
            } finally {
                extractor.release()
                decoder?.stop()
                decoder?.release()
                encoder?.stop()
                encoder?.release()
                muxer?.stop()
                muxer?.release()
            }
        }
    }
}